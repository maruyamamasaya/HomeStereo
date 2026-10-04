"""Evaluated Discogs-EffNet + semantic heads, bounded CPU and no audio writes."""
import hashlib
import json
import os
import subprocess
from pathlib import Path
os.environ['ORT_DISABLE_TELEMETRY'] = '1'
from frontend import mel_spectrogram, average_channels, _segment_offsets

MAPPING = {
    'piano': ('tags','piano'), 'electronic': ('tags','electronic'),
    'ambient': ('tags','ambient'), 'dark': ('mood','dark'),
    'vocal': ('voice_instrumental','voice'), 'instrumental': ('voice_instrumental','instrumental'),
    'aggressive': ('mood_aggressive','aggressive'), 'calm': ('mood_relaxed','relaxed'),
    'drumAndBass': ('discogs','Electronic---Drum n Bass'),
}
PROFILE = 'discogs-effnet-semantic-v2-evaluated-frontend-1'

class Inference:
    def __init__(self, model_dir, ffmpeg, ffprobe):
        import onnxruntime as ort
        ort.disable_telemetry_events()
        self.ffmpeg, self.ffprobe = str(ffmpeg), str(ffprobe)
        manifest = json.loads(Path(__file__).with_name('models.json').read_text())
        self.sessions, self.labels = {}, {}
        for group, spec in manifest['models'].items():
            prefix = spec['prefix']
            for ext in ('json','onnx'):
                path = Path(model_dir)/f'{prefix}.{ext}'
                if hashlib.sha256(path.read_bytes()).hexdigest() != manifest['sha256'][path.name]:
                    raise ValueError(f'Model checksum mismatch: {path.name}')
            metadata = json.loads((Path(model_dir)/f'{prefix}.json').read_text())
            self.labels[group] = metadata['classes']
            if group not in ('discogs','tags','mood') and metadata['inference']['embedding_model']['model_name'] != 'discogs-effnet-bs64-1':
                raise ValueError('Incompatible head embedding')
            options = ort.SessionOptions(); options.intra_op_num_threads=1; options.inter_op_num_threads=1
            options.execution_mode=ort.ExecutionMode.ORT_SEQUENTIAL
            self.sessions[group]=ort.InferenceSession(str(Path(model_dir)/f'{prefix}.onnx'),options,providers=['CPUExecutionProvider'])
            if self.sessions[group].get_outputs()[0].shape[-1] != len(self.labels[group]):
                raise ValueError('Model label/output mismatch')
        for group,label in MAPPING.values():
            if label not in self.labels[group]: raise ValueError('Missing semantic label')

    def analyze(self,path,duration):
        import numpy as np
        import librosa
        probe=subprocess.run([self.ffprobe,'-v','error','-select_streams','a:0','-show_entries','stream=channels,sample_rate','-of','json',str(path)],capture_output=True,timeout=30,check=True)
        stream=json.loads(probe.stdout)['streams'][0]
        channels,rate=int(stream['channels']),int(stream['sample_rate'])
        if not 1<=channels<=8 or not 8000<=rate<=192000: raise ValueError('Unsupported audio format')
        totals={key:np.zeros(len(labels),dtype=np.float64) for key,labels in self.labels.items()}; count=0
        for offset in _segment_offsets(duration,30.,3):
            decoded=subprocess.run([self.ffmpeg,'-v','error','-nostdin','-threads','1','-filter_threads','1','-ss',str(offset),'-i',str(path),'-t',str(min(30.,duration-offset)),'-map','0:a:0','-vn','-ac',str(channels),'-ar',str(rate),'-f','f32le','pipe:1'],capture_output=True,timeout=120,check=True)
            mono=average_channels(decoded.stdout,channels)
            y22=librosa.resample(mono,orig_sr=rate,target_sr=22050,res_type='soxr_hq')
            y16=librosa.resample(y22,orig_sr=22050,target_sr=16000,res_type='soxr_hq')
            if not np.isfinite(y16).all(): raise ValueError('Non-finite audio')
            mel=mel_spectrogram(y16); starts=range(0,len(mel)-128+1,62)
            if not starts: raise ValueError('No complete model patches')
            for first in range(0,len(starts),8):
                batch=np.stack([mel[s:s+128] for s in starts[first:first+8]])
                style,embedding=self.sessions['discogs'].run(['activations','embeddings'],{'melspectrogram':batch})
                predictions={'discogs':style}
                for group,session in self.sessions.items():
                    if group!='discogs': predictions[group]=session.run(None,{session.get_inputs()[0].name:embedding})[0]
                for group,values in predictions.items():
                    if not np.isfinite(values).all() or np.any(values<0) or np.any(values>1): raise ValueError('Invalid model output')
                    if group not in ('discogs','tags','mood') and not np.allclose(values.sum(axis=1),1,atol=1e-5): raise ValueError('Invalid binary probabilities')
                    totals[group]+=values.sum(axis=0,dtype=np.float64)
                count+=len(batch)
        return {key:round(float(totals[group][self.labels[group].index(label)]/count),6) for key,(group,label) in MAPPING.items()}
