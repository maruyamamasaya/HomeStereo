# Sony Stereo Bridge Phase 4 Input

- BlackHole 2ch v0.6.1とAudio Hijackのinstallを確認した。
- `audio-probe`でBlackHole 2ch（96kHz、2ch、512 frames）を列挙した。
- OS既定入力を変えずにdevice IDを選択するAUHAL captureを追加した。
- 1つのcallback／timelineからL/Rを分離し、1/2/5秒の16-bit mono PCM WAV segmentを生成する。
- CLIで2秒、Web UIで5秒の無音captureに成功。1秒WAVの形式を`ffprobe`で確認した。
- Web UIにdevice、permission、format、buffer、channel mapping、左右level、PCM-only captureを追加した。
- 初回実行ではApplication／Channels／Output Device blockがOffで完全無音だった。3 blockをすべてOnへ修正した。
- Musicのtest signalをOutput 2%でcaptureし、LEFT ONLYは左−54.0dBFS／右−160dBFS、RIGHT ONLYは左−160dBFS／右−54.0dBFSを確認した。
- 既存Audio Hijack sessionはBlackHole入力→160% gain→headphone出力の逆向き構成だったため、実行・編集しなかった。
- `Sony Stereo Bridge - BlackHole` sessionはMusic→Channels No Change→BlackHole 2ch、全block On、Output 2%、Auto Run Off、Stoppedへ更新した。
- 実装経緯、成功／未検証matrix、優先課題を`docs/sony-stereo-bridge/status-and-history.md`へ集約した。
- 未完了: 物理的な左右定位、segment境界gap／click、音響同期、chunked／live HTTP、drift。
