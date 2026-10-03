"""Install an independent personal-use analyzer companion, without changing app entitlements."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import urllib.request

parser=argparse.ArgumentParser()
parser.add_argument('--models-source',type=Path)
args=parser.parse_args()
source=Path(__file__).resolve().parent
support=Path.home()/'Library/Application Support/HomeStereoAnalyzer'
support.mkdir(parents=True,exist_ok=True)
lock=(support/'analysis.lock').open('a+')
try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: raise RuntimeError('Stop the running analysis before updating the companion runtime')
runtime=support/'runtime'
if not (runtime/'bin/python').exists(): subprocess.run(['/opt/homebrew/bin/python3.12','-m','venv',str(runtime)],check=True)
subprocess.run([str(runtime/'bin/python'),'-m','pip','install','-r',str(source/'requirements-lock.txt' if (source/'requirements-lock.txt').exists() else source/'requirements.txt')],check=True)
models=support/'models';models.mkdir(exist_ok=True)
manifest=json.loads((source/'models.json').read_text())
for spec in manifest['models'].values():
    for ext in ('json','onnx'):
        name=f'{spec["prefix"]}.{ext}';target=models/name;expected=manifest['sha256'][name]
        if target.exists():
            if hashlib.sha256(target.read_bytes()).hexdigest()!=expected: raise ValueError(f'Existing model checksum mismatch: {name}')
            continue
        candidates=[]
        if args.models_source:
            candidates=[args.models_source/name,args.models_source/'human_eval'/name]
        found=next((p for p in candidates if p.exists()),None)
        data=found.read_bytes() if found else urllib.request.urlopen('https://essentia.upf.edu/models/'+spec['base']+'.'+ext,timeout=60).read(30_000_001)
        if len(data)>30_000_000 or hashlib.sha256(data).hexdigest()!=expected: raise ValueError(f'Model checksum mismatch: {name}')
        temporary=target.with_suffix(target.suffix+'.tmp');temporary.write_bytes(data);temporary.replace(target)
code=support/'code';code.mkdir(exist_ok=True)
for name in ('worker.py','inference.py','frontend.py','models.json'):
    shutil.copy2(source/name,code/name)
(support/'bin').mkdir(exist_ok=True)
for tool in ('ffmpeg','ffprobe'):
    target=support/'bin'/tool
    if not target.exists(): target.symlink_to('/opt/homebrew/bin/'+tool)
    subprocess.run([str(target),'-version'],stdout=subprocess.DEVNULL,check=True)
# A Launch Services companion executes outside the UI app sandbox with unchanged UI entitlements.
app=Path('/Applications/HomeStereoAnalyzer.app')
contents=app/'Contents';(contents/'MacOS').mkdir(parents=True,exist_ok=True)
plist={'CFBundleIdentifier':'jp.local.HomeStereo.Analyzer','CFBundleName':'HomeStereoAnalyzer','CFBundleExecutable':'HomeStereoAnalyzer','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','LSUIElement':True,'LSMultipleInstancesProhibited':False,'CFBundleDocumentTypes':[{'CFBundleTypeName':'HomeStereo Analysis Request','CFBundleTypeRole':'Viewer','LSHandlerRank':'None','LSItemContentTypes':['public.json']}]}
(contents/'Info.plist').write_bytes(plistlib.dumps(plist))
# Launch Services requires a native executable; a shell entry may exit before receiving arguments.
import tempfile
launcher=contents/'MacOS/HomeStereoAnalyzer'
def swift_string(value): return json.dumps(str(value),ensure_ascii=False)
launcher_source = """import AppKit
import Foundation
let support = __SUPPORT__
final class Launcher: NSObject, NSApplicationDelegate {
    var started = false
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !started, let url = urls.first else { return }
        start(url)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = CommandLine.arguments.dropFirst().first, path.hasSuffix(".json") {
            start(URL(fileURLWithPath: path))
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+30) {
            if !self.started { exit(1) }
        }
    }
    func start(_ url: URL) {
        guard !started else { return }
        started = true
        let scoped = url.startAccessingSecurityScopedResource()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: __PYTHON__)
        process.arguments = [__WORKER__, url.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HOMESTEREO_ANALYZER_HOME"] = support
        environment["ORT_DISABLE_TELEMETRY"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["NUMBA_CACHE_DIR"] = support + "/numba-cache"
        process.environment = environment
        let logURL = URL(fileURLWithPath: support + "/launcher-error.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        process.standardError = try? FileHandle(forWritingTo: logURL)
        process.terminationHandler = { process in
            if scoped { url.stopAccessingSecurityScopedResource() }
            exit(process.terminationStatus)
        }
        do { try process.run() }
        catch {
            try? Data(String(describing: error).utf8).write(to: logURL)
            exit(1)
        }
    }
}
let delegate = Launcher()
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
application.delegate = delegate
application.run()
""".replace('__SUPPORT__',swift_string(support)).replace('__PYTHON__',swift_string(runtime/'bin/python')).replace('__WORKER__',swift_string(code/'worker.py'))
with tempfile.TemporaryDirectory(prefix='homestereo-launcher-') as tmp:
    swift=Path(tmp)/'Launcher.swift';swift.write_text(launcher_source)
    subprocess.run(['xcrun','swiftc',str(swift),'-o',str(launcher)],check=True)
launcher.chmod(0o755)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('Installed HomeStereoAnalyzer with independent runtime and verified models.')
