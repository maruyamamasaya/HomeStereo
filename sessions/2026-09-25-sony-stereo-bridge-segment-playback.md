# 2026-09-25 Sony Stereo Bridge segment playback

## 結果

- `capture-segments`のreportを検証し、左右WAVをHG1／HG10へ順次送る`play-capture`を追加した。
- 無音、-6dBFS超、WAV欠落、左右同一file、0.1秒未満のtailをspeaker送信前に拒否する。
- LEFT ONLY／RIGHT ONLY確認とspeaker本体低音量の明示flagを必須にした。
- capture終了時の短いcallback tailはsegmentとして保存しないようにした。
- Web UIへrenderer指定、安全確認checkbox、Play Captured Segments、Stopを追加した。
- localhost:9875のWeb UIを新実装へ再起動した。
- Audio Hijackで分離確認済みのLEFT／RIGHT各1秒segmentをHG1／HG10へ送信した。音量2/100の−84.5dBFSと、利用者指定の音量5/100の−54.0dBFSで、両方のHTTP GET、Play、位置1.000秒、`STOPPED`を確認した。
- 音量5の2segmentはいずれも左右のPlay送信差0ms。SOAP完了はRIGHTが64ms／34ms早かったが、これはDACの音響開始差ではない。
- 終了後に両RendererへStopを送り、HG1／HG10とも`STOPPED`を再確認した。Audio HijackもStoppedへ戻した。

## 検証

- `python3 -m py_compile scripts/sony-stereo-bridge-web.py`: 成功
- 別portのWeb UI smoke test: 成功
- confirmationなしのCLI実行拒否: 確認済み
- 既存の無音capture reportのCLI実行拒否: 確認済み
- `./scripts/verify.sh`: 成功
  - XCTest 32件成功、任意の20,000曲性能test 1件skip
  - Swift Testing 43件成功
  - macOS Debug build成功

## 未確認

- スピーカー実音の物理的な左右定位
- segment境界のgap／click、音響開始offset、drift
- chunked／continuous live PCM
