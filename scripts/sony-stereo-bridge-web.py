#!/usr/bin/env python3

"""Loopback-only Phase 3/4 diagnostic panel for Sony Stereo Bridge."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import secrets
import signal
import subprocess
import threading

REPO = Path(__file__).resolve().parent.parent
MEDIA_DIR = Path("/tmp/sony-stereo-bridge-sync")
REPORT_PATH = Path("/tmp/sony-stereo-bridge-sync-web-report.json")
OBSERVATION_PATH = Path("/tmp/sony-stereo-bridge-acoustic-observations.json")
CAPTURE_DIR = Path("/tmp/sony-stereo-bridge-realtime")
CAPTURE_REPORT_PATH = Path("/tmp/sony-stereo-bridge-capture-report.json")
TOKEN = secrets.token_urlsafe(24)
STATE_LOCK = threading.Lock()
STATE = {"running": False, "logs": [], "exitCode": None}
OBSERVATIONS: list[dict] = []
ACTIVE_PROCESS = None


def append_log(value: str) -> None:
    with STATE_LOCK:
        STATE["logs"] = (STATE["logs"] + [value.rstrip()])[-300:]


def run_job(command: list[str]) -> None:
    global ACTIVE_PROCESS
    with STATE_LOCK:
        if STATE["running"]:
            raise RuntimeError("A test is already running")
        STATE.update(running=True, logs=[], exitCode=None)

    def worker() -> None:
        global ACTIVE_PROCESS
        process = None
        try:
            process = subprocess.Popen(
                command,
                cwd=REPO,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
            with STATE_LOCK:
                ACTIVE_PROCESS = process
            assert process.stdout is not None
            for line in process.stdout:
                append_log(line)
            code = process.wait()
        except Exception as error:  # Display local operational failures in the panel.
            append_log(f"error: {error}")
            code = 1
        with STATE_LOCK:
            if process is not None and ACTIVE_PROCESS is process:
                ACTIVE_PROCESS = None
            STATE["running"] = False
            STATE["exitCode"] = code

    threading.Thread(target=worker, daemon=True).start()


def stop_job() -> bool:
    with STATE_LOCK:
        process = ACTIVE_PROCESS
    if process is None or process.poll() is not None:
        return False
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=2)
    append_log("Local playback job stopped; sending UPnP Stop to both renderers.")
    return True


def stop_pair(left: str, right: str) -> dict:
    local_stopped = stop_job()
    process = subprocess.run(
        [
            "swift", "run", "sony-stereo-bridge", "stop-pair",
            "--left", left, "--right", right, "--timeout", "8",
        ],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=30,
    )
    for line in (process.stdout + process.stderr).splitlines():
        append_log(line)
    if process.returncode != 0:
        raise RuntimeError("UPnP Stop failed; see the status log")
    return {"localProcessStopped": local_stopped, "renderersStopped": True}


def html() -> bytes:
    return f"""<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Sony Stereo Bridge</title>
<style>
:root {{ color-scheme: dark; font-family: system-ui, sans-serif; background:#101318; color:#eef2f7; }}
body {{ max-width:900px; margin:0 auto; padding:28px; }}
h1 {{ margin-bottom:4px; }} .note {{ color:#aab6c5; }}
.grid {{ display:grid; grid-template-columns:1fr 1fr; gap:16px; margin:22px 0; }}
.card {{ background:#1a2029; border:1px solid #344052; border-radius:12px; padding:18px; }}
input {{ width:90px; padding:8px; font-size:18px; }} input.selector {{ width:150px; }} button {{ padding:9px 13px; margin:4px; cursor:pointer; }}
.primary {{ background:#4c8dff; color:white; border:0; border-radius:8px; }}
.danger {{ background:#7b2831; color:white; border:0; border-radius:8px; }}
pre {{ min-height:180px; max-height:340px; overflow:auto; background:#080a0d; padding:14px; border-radius:8px; white-space:pre-wrap; }}
.status {{ display:grid; grid-template-columns:140px 1fr; gap:7px 14px; }} .status dt {{ color:#aab6c5; }} .status dd {{ margin:0; }}
.meter {{ height:12px; background:#080a0d; border-radius:8px; overflow:hidden; }} .meter span {{ display:block; height:100%; width:0; background:#4c8dff; }}
@media(max-width:650px) {{ .grid {{ grid-template-columns:1fr; }} }}
</style></head><body>
<h1>Sony Stereo Bridge</h1>
<p class="note">Phase 3 · HG1=LEFT / HG10=RIGHT · click peak −50.5 dBFS</p>
<div class="grid">
<section class="card"><h2>LEFT · SRS-HG1</h2><label>Delay <input id="left" type="number" value="0" min="-5000" max="5000" step="1"> ms</label><div id="lp"></div></section>
<section class="card"><h2>RIGHT · SRS-HG10</h2><label>Delay <input id="right" type="number" value="0" min="-5000" max="5000" step="1"> ms</label><div id="rp"></div></section>
</div>
<section class="card">
<label>反復回数 <input id="runs" type="number" value="10" min="1" max="20"></label>
<label>テスト音量 <input id="testVolume" type="number" value="2" min="0" max="10"> / 100</label>
<button class="primary" onclick="generate(4,1)">極小クリック生成</button>
<button class="primary" onclick="runTest()">同期テスト開始</button>
<button class="danger" onclick="prepareLong()">10分音源を生成</button>
<p class="note">Delayは早い側に正値を加えてください。負値指定時も内部で相対差へ正規化します。</p>
</section>
<section class="card">
<h2>聴感／マイク測定値</h2>
<label>Test # <input id="observedRun" type="number" value="1" min="1" max="20"></label>
<label>RIGHTの実音遅れ <input id="observedMs" type="number" value="0" min="-1000" max="1000" step="1"> ms</label>
<button onclick="recordObservation()">測定値を記録</button>
<p class="note">正値はRIGHTが遅い、負値はLEFTが遅い。早い側へ同じ絶対値のDelayを設定します。</p>
</section>
<section class="card">
<h2>Realtime Input · Phase 4 Gate</h2>
<dl class="status">
<dt>Device</dt><dd id="audioDevice">checking…</dd>
<dt>Permission</dt><dd id="audioPermission">checking…</dd>
<dt>Status</dt><dd id="audioStatus">INACTIVE</dd>
<dt>Format</dt><dd id="audioFormat">—</dd>
<dt>Buffer</dt><dd><input id="bufferFrames" type="number" value="1024" min="64" max="8192" step="64"> frames</dd>
<dt>Segment</dt><dd><select id="segmentSeconds"><option>1</option><option>2</option><option>5</option></select> s</dd>
<dt>Input Latency</dt><dd id="inputLatency">—</dd>
<dt>Sync Offset</dt><dd id="syncOffset">LEFT 0 ms / RIGHT 0 ms</dd>
<dt>Drift</dt><dd>not measured</dd>
<dt>LEFT level</dt><dd><div class="meter"><span id="leftMeter"></span></div><small id="leftLevel">—</small></dd>
<dt>RIGHT level</dt><dd><div class="meter"><span id="rightMeter"></span></div><small id="rightLevel">—</small></dd>
</dl>
<label>LEFT channel <input id="leftChannel" type="number" value="1" min="1" max="256"></label>
<label>RIGHT channel <input id="rightChannel" type="number" value="2" min="1" max="256"></label>
<button onclick="refreshAudio()">Refresh Devices</button>
<button class="primary" onclick="capturePCM()">Capture PCM Only (5 s)</button>
<p class="note">このボタンはWAV segmentを生成するだけです。Sony機器への送信や音量変更は行いません。2chは1/2、16ch方式は1/3を指定します。</p>
<hr>
<h3>Captured Segment Speaker Test</h3>
<label>LEFT <input class="selector" id="leftRenderer" value="SRS-HG1"></label>
<label>RIGHT <input class="selector" id="rightRenderer" value="SRS-HG10"></label>
<p><label><input id="speakerSafety" type="checkbox" style="width:auto"> LEFT ONLY／RIGHT ONLY確認済み（再生前に指定音量を機器へ設定・再確認します）</label></p>
<button class="primary" onclick="playCapture()">Play Captured Segments</button>
<button class="danger" onclick="stopJob()">Stop</button>
<p class="note">無音または−6 dBFSを超えるcaptureは拒否します。各segmentは個別にSetURI／Playするため、現段階では境界にgapが出ます。</p>
</section>
<h2>Status: <span id="state">idle</span></h2><pre id="logs"></pre>
<script>
const token={json.dumps(TOKEN)}, presets=[-100,-50,-20,-10,-5,-1,0,1,5,10,20,50,100];
for (const [box,input] of [['lp','left'],['rp','right']]) {{
  const root=document.getElementById(box); presets.forEach(v=>{{const b=document.createElement('button');b.textContent=(v>0?'+':'')+v;b.onclick=()=>document.getElementById(input).value=v;root.appendChild(b)}})
}}
async function post(path,data) {{ const r=await fetch(path,{{method:'POST',headers:{{'Content-Type':'application/json','X-Bridge-Token':token}},body:JSON.stringify(data)}}); const j=await r.json(); if(!r.ok) throw Error(j.error); return j; }}
async function generate(duration,interval) {{ try {{ await post('/api/generate',{{duration,interval}}); }} catch(e) {{ alert(e.message); }} }}
async function runTest() {{
  if(!confirm('左右スピーカーを音量 '+testVolume.value+'/100 に設定して極小クリックを再生します。続けますか？')) return;
  try {{ await post('/api/run',{{left:+left.value,right:+right.value,runs:+runs.value,hold:5,statusInterval:5,testVolume:+testVolume.value}}); }} catch(e) {{ alert(e.message); }}
}}
async function recordObservation() {{ try {{ const j=await post('/api/observation',{{run:+observedRun.value,offsetMs:+observedMs.value}}); alert('記録しました: '+j.rating); }} catch(e) {{ alert(e.message); }} }}
async function prepareLong() {{ if(!confirm('約10分の極小クリックWAVを生成します。まだ再生はしません。')) return; await generate(600,5); }}
async function refreshAudio() {{ try {{ const j=await (await fetch('/api/audio-probe')).json(); audioPermission.textContent=j.audioInputAuthorization; const d=j.devices.find(x=>x.name.toLowerCase().includes('blackhole')); audioDevice.textContent=d?d.name+' ['+d.uid+']':'BlackHole not found'; audioFormat.textContent=d?d.nominalSampleRate+' Hz · '+d.inputChannels+' ch · '+d.bufferFrameSize+' frames':'—'; inputLatency.textContent=d?(d.inputLatencyFrames/d.nominalSampleRate*1000).toFixed(3)+' ms (HAL only)':'—'; }} catch(e) {{ audioDevice.textContent='probe failed'; }} }}
async function capturePCM() {{ try {{ await post('/api/capture',{{device:'BlackHole',duration:5,segmentSeconds:+segmentSeconds.value,leftChannel:+leftChannel.value,rightChannel:+rightChannel.value,bufferFrames:+bufferFrames.value}}); }} catch(e) {{ alert(e.message); }} }}
async function playCapture() {{
  if(!speakerSafety.checked) {{ alert('左右routing確認とスピーカー本体の低音量設定が必要です。'); return; }}
  if(!confirm('取得済みの音をHG1=LEFT、HG10=RIGHTへ低音量で送ります。続けますか？')) return;
  try {{ await post('/api/play-capture',{{left:leftRenderer.value,right:rightRenderer.value,safetyConfirmed:true,testVolume:+testVolume.value}}); }} catch(e) {{ alert(e.message); }}
}}
async function stopJob() {{ try {{ await post('/api/stop',{{left:leftRenderer.value,right:rightRenderer.value}}); }} catch(e) {{ alert(e.message); }} }}
function setMeter(id,label,value) {{ const db=Number(value); document.getElementById(id).style.width=(Number.isFinite(db)?Math.max(0,Math.min(100,(db+80)/80*100)):0)+'%'; document.getElementById(label).textContent=Number.isFinite(db)?db.toFixed(1)+' dBFS':'—'; }}
async function poll() {{ try {{ const j=await (await fetch('/api/status')).json(); state.textContent=j.running?'running':(j.exitCode===null?'idle':'exit '+j.exitCode); audioStatus.textContent=j.running?'ACTIVE':'INACTIVE'; logs.textContent=j.logs.join('\\n'); logs.scrollTop=logs.scrollHeight; if(j.capture&&j.capture.segments.length){{const s=j.capture.segments.at(-1);setMeter('leftMeter','leftLevel',s.leftPeakDBFS);setMeter('rightMeter','rightLevel',s.rightPeakDBFS);}} }} catch(e) {{ state.textContent='offline'; }} setTimeout(poll,700); }} refreshAudio(); poll();
</script></body></html>""".encode()


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status: int, value: dict) -> None:
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/":
            data = html()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        elif self.path == "/api/status":
            with STATE_LOCK:
                value = dict(STATE)
                value["observations"] = list(OBSERVATIONS)
                value["capture"] = json.loads(CAPTURE_REPORT_PATH.read_text()) if CAPTURE_REPORT_PATH.is_file() else None
                self.send_json(200, value)
        elif self.path == "/api/audio-probe":
            process = subprocess.run(
                ["swift", "run", "sony-stereo-bridge", "audio-probe"],
                cwd=REPO,
                capture_output=True,
                text=True,
                timeout=10,
            )
            if process.returncode != 0:
                self.send_json(500, {"error": process.stderr.strip() or "audio probe failed"})
            else:
                self.send_json(200, json.loads(process.stdout))
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        if self.headers.get("X-Bridge-Token") != TOKEN:
            self.send_json(403, {"error": "invalid token"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 4096:
                raise ValueError("request too large")
            body = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/api/generate":
                duration = int(body.get("duration", 4))
                interval = int(body.get("interval", 1))
                if not 1 <= duration <= 600 or not 1 <= interval <= 60:
                    raise ValueError("duration or interval is out of range")
                run_job([str(REPO / "scripts/sony-stereo-bridge-sync-click.sh"), str(MEDIA_DIR), str(duration), str(interval)])
            elif self.path == "/api/run":
                left = int(body.get("left", 0)); right = int(body.get("right", 0))
                runs = int(body.get("runs", 10)); hold = float(body.get("hold", 5))
                status_interval = float(body.get("statusInterval", 5))
                test_volume = int(body.get("testVolume", 2))
                if not -5000 <= left <= 5000 or not -5000 <= right <= 5000:
                    raise ValueError("delay is out of range")
                if not 1 <= runs <= 20 or not 1 <= hold <= 600:
                    raise ValueError("runs or hold is out of range")
                if not 0 <= test_volume <= 10:
                    raise ValueError("test volume must be between 0 and 10")
                for path in (MEDIA_DIR / "left-click.wav", MEDIA_DIR / "right-click.wav"):
                    if not path.is_file():
                        raise ValueError("generate click files first")
                run_job([
                    "swift", "run", "sony-stereo-bridge", "play-pair",
                    "--left", "SRS-HG1", "--left-file", str(MEDIA_DIR / "left-click.wav"),
                    "--right", "SRS-HG10", "--right-file", str(MEDIA_DIR / "right-click.wav"),
                    "--left-delay", str(left), "--right-delay", str(right),
                    "--runs", str(runs), "--timeout", "8", "--http-port", "9876",
                    "--hold", str(hold), "--status-interval", str(status_interval),
                    "--test-volume", str(test_volume),
                    "--output", str(REPORT_PATH),
                ])
            elif self.path == "/api/observation":
                run = int(body.get("run", 0)); offset = float(body.get("offsetMs", 0))
                if not 1 <= run <= 20 or not -1000 <= offset <= 1000:
                    raise ValueError("run or offset is out of range")
                OBSERVATIONS.append({"run": run, "offsetMs": offset})
                offsets = [item["offsetMs"] for item in OBSERVATIONS]
                center = sorted(offsets)[len(offsets) // 2]
                variation = max(abs(value - center) for value in offsets)
                rating = "Excellent" if variation <= 5 else "Good" if variation <= 20 else "Usable" if variation <= 40 else "Poor"
                OBSERVATION_PATH.write_text(json.dumps({"rating": rating, "observations": OBSERVATIONS}, indent=2) + "\n")
                append_log(f"Acoustic Test {run:02d}: RIGHT offset {offset:+.1f} ms; variation {variation:.1f} ms; {rating}")
                self.send_json(200, {"recorded": True, "rating": rating, "variationMs": variation})
                return
            elif self.path == "/api/capture":
                duration = int(body.get("duration", 5))
                segment = float(body.get("segmentSeconds", 1))
                left_channel = int(body.get("leftChannel", 1))
                right_channel = int(body.get("rightChannel", 2))
                buffer_frames = int(body.get("bufferFrames", 1024))
                device = str(body.get("device", "BlackHole"))
                if not 1 <= duration <= 600 or segment not in (1, 2, 5):
                    raise ValueError("duration or segment size is out of range")
                if not 1 <= left_channel <= 256 or not 1 <= right_channel <= 256:
                    raise ValueError("channel is out of range")
                if not 64 <= buffer_frames <= 8192:
                    raise ValueError("buffer frames is out of range")
                run_job([
                    "swift", "run", "sony-stereo-bridge", "capture-segments",
                    "--device", device,
                    "--output-dir", str(CAPTURE_DIR),
                    "--duration", str(duration),
                    "--segment-seconds", str(segment),
                    "--left-channel", str(left_channel),
                    "--right-channel", str(right_channel),
                    "--buffer-frames", str(buffer_frames),
                    "--output", str(CAPTURE_REPORT_PATH),
                ])
            elif self.path == "/api/play-capture":
                if body.get("safetyConfirmed") is not True:
                    raise ValueError("routing and low-volume confirmation is required")
                left = str(body.get("left", "")).strip()
                right = str(body.get("right", "")).strip()
                test_volume = int(body.get("testVolume", 2))
                if not left or not right or len(left) > 100 or len(right) > 100:
                    raise ValueError("LEFT and RIGHT renderer selectors are required")
                if not 0 <= test_volume <= 10:
                    raise ValueError("test volume must be between 0 and 10")
                if not CAPTURE_REPORT_PATH.is_file():
                    raise ValueError("capture report is missing; run Capture PCM Only first")
                run_job([
                    "swift", "run", "sony-stereo-bridge", "play-capture",
                    "--capture-report", str(CAPTURE_REPORT_PATH),
                    "--left", left,
                    "--right", right,
                    "--confirm-routing",
                    "--confirm-low-volume",
                    "--test-volume", str(test_volume),
                    "--timeout", "8",
                    "--http-port", "9876",
                    "--segment-tail", "0.25",
                    "--safety-ceiling-dbfs", "-6",
                    "--output", "/tmp/sony-stereo-bridge-captured-playback-report.json",
                ])
            elif self.path == "/api/stop":
                left = str(body.get("left", "")).strip()
                right = str(body.get("right", "")).strip()
                if not left or not right or len(left) > 100 or len(right) > 100:
                    raise ValueError("LEFT and RIGHT renderer selectors are required")
                self.send_json(200, stop_pair(left, right))
                return
            else:
                self.send_json(404, {"error": "not found"})
                return
            self.send_json(202, {"accepted": True})
        except (ValueError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})

    def log_message(self, format: str, *args: object) -> None:
        return


if __name__ == "__main__":
    port = int(os.environ.get("SONY_STEREO_BRIDGE_WEB_PORT", "9875"))
    if not 1024 <= port <= 65535:
        raise SystemExit("SONY_STEREO_BRIDGE_WEB_PORT must be between 1024 and 65535")
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Sony Stereo Bridge UI: http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
