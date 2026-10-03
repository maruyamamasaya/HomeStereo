import json
from pathlib import Path
import tempfile
import unittest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import worker

class WorkerTests(unittest.TestCase):
    def task(self,path,semantic=True,volume=True):
        return {'localTrackID':'local','path':str(path),'semantic':semantic,'loudness':volume,'record':{
            'id':'test','analysisVersion':2,'analyzedAt':'2026-10-04T00:00:00Z','importedAt':'2026-10-04T00:00:00Z',
            'features':{'calm':0.5},'sourceIdentity':{'relativePath':'song.wav','fileSize':path.stat().st_size,'duration':60},'sourceFormat':'fixture','sourceFileName':'fixture'}}
    def run_fixture(self,task,root,engine,volume):
        request=root/'request.json'; request.write_text(json.dumps({'version':1,'support':str(root),'tasks':[task]}))
        worker.run(request,engine_factory=lambda:engine,loudness_fn=volume)
        return json.loads((root/'results.json').read_text())
    def testAbruptExitKeepsCompletedRecordJournal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); audio=root/'song.wav'; audio.write_bytes(b'fixture')
            class AbruptExit(BaseException): pass
            class Engine:
                calls=0
                def analyze(self,*args):
                    self.calls+=1
                    if self.calls==2: raise AbruptExit()
                    return {'calm':0.7}
            tasks=[self.task(audio,volume=False),self.task(audio,volume=False)]
            tasks[1]['localTrackID']='second'
            request=root/'request.json'
            request.write_text(json.dumps({'version':1,'support':str(root),'tasks':tasks}))
            with self.assertRaises(AbruptExit): worker.run(request,engine_factory=Engine)
            records=[json.loads(line) for line in (root/'completed.jsonl').read_text().splitlines()]
            self.assertEqual(len(records),1)
            self.assertEqual(records[0]['features']['calm'],0.7)
            self.assertFalse((root/'results.json').exists())
    def testGainAndPeakEvenInNoChangeWindow(self):
        self.assertEqual(worker.gain(-20,-10),4)
        self.assertEqual(worker.gain(-14,0),-1)
        self.assertEqual(worker.gain(-8,-1),-4)
        with self.assertRaises(ValueError):worker.gain(float('nan'),0)
        with self.assertRaises(ValueError):worker.gain(-14,5)
    def testCacheAvoidsSecondReadAndLoudnessFailureRetainsSemanticCheckpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);audio=root/'song.wav';audio.write_bytes(b'fixture')
            class Engine:
                calls=0
                def analyze(self,*args): self.calls+=1;return {'calm':0.7}
            engine=Engine();calls=[]
            def fail(*args): calls.append(1);raise ValueError('fail')
            task=self.task(audio)
            first=self.run_fixture(task,root,engine,fail)
            self.assertEqual(len(first['failures']),1);self.assertEqual(first['records'],[])
            def volume(*args): calls.append(1);return {'integratedLUFS':-20,'truePeakDBTP':-10,'normalizationGainDB':4}
            second=self.run_fixture(task,root,engine,volume)
            third=self.run_fixture(task,root,engine,volume)
            self.assertEqual(engine.calls,1);self.assertEqual(len(calls),2)
            self.assertEqual(second['records'][0]['features'],third['records'][0]['features'])
            self.assertEqual(second['records'][0]['analyzedAt'],third['records'][0]['analyzedAt'])
            self.assertEqual(second['records'][0]['loudnessSource']['analyzedAt'],third['records'][0]['loudnessSource']['analyzedAt'])
            audio.write_bytes(b'changed')
            self.run_fixture(self.task(audio),root,engine,volume)
            self.assertEqual(engine.calls,2)
    def testLoudnessOnlyAndCancellation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);audio=root/'song.wav';audio.write_bytes(b'fixture')
            def volume(*args):return {'integratedLUFS':-20,'truePeakDBTP':-10,'normalizationGainDB':4}
            result=self.run_fixture(self.task(audio,semantic=False),root,None,volume)
            self.assertEqual(result['records'][0]['features']['calm'],0.5)
            (root/'cancel').touch()
            result=self.run_fixture(self.task(audio),root,None,volume)
            self.assertEqual(result['records'],[])
            self.assertEqual(json.loads((root/'status.json').read_text())['state'],'cancelled')

if __name__=='__main__':unittest.main()
