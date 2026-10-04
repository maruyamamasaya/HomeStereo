"""Independent local companion worker. Read selected sources, cache results, never write audio."""
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import threading
import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

PROFILE='discogs-effnet-semantic-v2-evaluated-frontend-1'
LOUDNESS_PROFILE='ffmpeg-bs1770-lufs-tp-target14-headroom1-gain4-v1'

def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')
def atomic(path,value):
    path=Path(path)
    with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,delete=False) as f:
        json.dump(value,f,allow_nan=False); f.flush(); os.fsync(f.fileno()); name=f.name
    os.replace(name,path)

def gain(lufs,peak):
    if not math.isfinite(lufs) or not math.isfinite(peak): raise ValueError('Non-finite loudness')
    desired=0. if -17<=lufs<=-11 else max(-4.,min(4.,-14.-lufs))
    safe=min(desired,-1.-peak)
    if safe < -4.: raise ValueError('Peak requires attenuation beyond the compatible JSON range')
    return round(safe,3)

def loudness(path,ffmpeg):
    proc=subprocess.run([str(ffmpeg),'-hide_banner','-nostats','-nostdin','-threads','1','-filter_threads','1','-i',str(path),'-map','0:a:0','-vn','-sn','-dn','-af','loudnorm=I=-14:TP=-1:LRA=11:print_format=json','-f','null','-'],capture_output=True,text=True,timeout=1800,check=True)
    decoder=json.JSONDecoder(); data=None
    for pos in reversed([i for i,c in enumerate(proc.stderr) if c=='{']):
        try: candidate,_=decoder.raw_decode(proc.stderr[pos:])
        except json.JSONDecodeError: continue
        if isinstance(candidate,dict) and {'input_i','input_tp'}<=candidate.keys(): data=candidate; break
    if data is None: raise ValueError('Loudness measurements missing')
    lufs,peak=float(data['input_i']),float(data['input_tp'])
    return {'integratedLUFS':round(lufs,3),'truePeakDBTP':round(peak,3),'normalizationGainDB':gain(lufs,peak)}

def signature(path,task):
    stat=path.stat()
    return hashlib.sha256(json.dumps([str(path),stat.st_size,stat.st_mtime_ns,PROFILE,LOUDNESS_PROFILE],separators=(',',':')).encode()).hexdigest()

def run(request_path, engine_factory=None, loudness_fn=loudness):
    request_path=Path(request_path).resolve(); directory=request_path.parent
    request=json.loads(request_path.read_text())
    if request.get('version')!=1: raise ValueError('Unsupported request version')
    concurrency=request.get('concurrency',1)
    if type(concurrency) is not int or concurrency not in (1,2,3,6): raise ValueError('Unsupported concurrency')
    tasks=request['tasks']
    if len({t['localTrackID'] for t in tasks}) != len(tasks): raise ValueError('Duplicate task identity')
    support=Path(os.environ.get('HOMESTEREO_ANALYZER_HOME') or request['support']).resolve()
    if not support.is_dir(): raise ValueError('Analyzer runtime is missing')
    lock=(support/'analysis.lock').open('a+')
    try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:
        atomic(directory/'status.json',{'state':'failed','completed':0,'total':0,'failed':0,'message':'別の解析が実行中です。'})
        return
    db=sqlite3.connect(support/'analysis.sqlite3')
    db.execute('CREATE TABLE IF NOT EXISTS results (track_id TEXT, signature TEXT, semantic TEXT, loudness TEXT, PRIMARY KEY(track_id,signature))')
    columns={row[1] for row in db.execute('PRAGMA table_info(results)')}
    for name in ('semantic_at','loudness_at'):
        if name not in columns: db.execute(f'ALTER TABLE results ADD COLUMN {name} TEXT')
    db.commit()
    db.close()
    local=threading.local()
    results=[]; failures=[]; total=len(tasks)
    completed=0
    def status(state,current=''):
        atomic(directory/'status.json',{'state':state,'completed':completed,'total':total,'failed':len(failures),'message':current})
    status('running')
    # Each completed record is durable even if the process or main app exits.
    journal=(directory/'completed.jsonl').open('w')
    def process_task(task):
        record=task['record']; track_id=task['localTrackID']; path=Path(task['path'])
        connection=sqlite3.connect(support/'analysis.sqlite3',timeout=60)
        try:
            before=signature(path,task)
            stat=path.stat()
            if stat.st_size!=record['sourceIdentity']['fileSize']: raise ValueError('Source size changed; rescan the library')
            row=connection.execute('SELECT semantic,loudness,semantic_at,loudness_at FROM results WHERE track_id=? AND signature=?',(track_id,before)).fetchone()
            semantic=json.loads(row[0]) if row and row[0] and row[2] else None
            volume=json.loads(row[1]) if row and row[1] and row[3] else None
            semantic_at=row[2] if row else None
            loudness_at=row[3] if row else None
            if task['semantic'] and semantic is None:
                if not hasattr(local,'engine'):
                    if engine_factory is None:
                        from inference import Inference
                        local.engine=Inference(support/'models',support/'bin/ffmpeg',support/'bin/ffprobe')
                    else: local.engine=engine_factory()
                semantic=local.engine.analyze(path,record['sourceIdentity']['duration'])
                if signature(path,task)!=before: raise ValueError('Source changed during semantic analysis')
                semantic_at=now()
                connection.execute('INSERT INTO results(track_id,signature,semantic,semantic_at) VALUES(?,?,?,?) ON CONFLICT(track_id,signature) DO UPDATE SET semantic=excluded.semantic, semantic_at=excluded.semantic_at',(track_id,before,json.dumps(semantic),semantic_at)); connection.commit()
            if task['loudness'] and volume is None:
                volume=loudness_fn(path,support/'bin/ffmpeg')
                if signature(path,task)!=before: raise ValueError('Source changed during loudness analysis')
                loudness_at=now()
                connection.execute('INSERT INTO results(track_id,signature,loudness,loudness_at) VALUES(?,?,?,?) ON CONFLICT(track_id,signature) DO UPDATE SET loudness=excluded.loudness, loudness_at=excluded.loudness_at',(track_id,before,json.dumps(volume),loudness_at)); connection.commit()
            at=now()
            if semantic and task['semantic']:
                record['features']=semantic
                record['analysisVersion']=2; record['analyzedAt']=semantic_at
                record['modelDescription']='Discogs-EffNet + Jamendo / binary heads (Semantic v2)'
                record['analysisProfile']=PROFILE
                record['sourceIdentity']['modificationDate']=datetime.datetime.fromtimestamp(stat.st_mtime,datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')
            if volume and task['loudness']:
                record['features'].update(volume)
                record['loudnessSource']={'analysisVersion':record['analysisVersion'],'analyzedAt':loudness_at,'sourceFileName':'HomeStereo Analyzer','methodName':LOUDNESS_PROFILE}
            record['sourceFileName']='HomeStereo Analyzer'; record['sourceFormat']='Analyzer schema v1'; record['importedAt']=at
            return record, None
        except Exception as error:
            return None, {'trackID':track_id,'message':type(error).__name__}
        finally:
            connection.close()
    try:
        # Only active slots are submitted, so cancellation never leaves a large queued batch.
        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            iterator=iter(tasks)
            active=set()
            def fill():
                while len(active)<concurrency and not (directory/'cancel').exists():
                    task=next(iterator,None)
                    if task is None: break
                    active.add(pool.submit(process_task,task))
            fill()
            while active:
                done,active=wait(active,return_when=FIRST_COMPLETED)
                for future in done:
                    record,failure=future.result()
                    if record is not None:
                        journal.write(json.dumps(record,allow_nan=False)+"\n")
                        journal.flush(); os.fsync(journal.fileno())
                        results.append(record)
                    else:
                        failures.append(failure)
                    completed+=1
                    status('running',f'{completed} / {total}')
                fill()
        atomic(directory/'results.json',{'version':1,'records':results,'failures':failures})
        status('cancelled' if (directory/'cancel').exists() else 'completed')
    finally: journal.close(); lock.close()

if __name__=='__main__':
    request=Path(sys.argv[1])
    try: run(request)
    except Exception as error:
        atomic(request.parent/'status.json',{'state':'failed','completed':0,'total':0,'failed':0,'message':type(error).__name__})
        raise
