# このMac出力

- 出力先へ「このMac」を追加し、AVPlayerからmacOSのシステム出力へ再生する経路を実装した。
- Queue、履歴、Now Playing、再生位置、完走時の次曲処理はDLNA出力と同じStore境界を使う。
- ローカル出力時はアプリ内音量sliderを表示せず、macOS標準の音量キーとシステム設定へ委ねる。
- fake local playerによる再生・一時停止・seek・完走の自動testを追加した。
- `./scripts/verify.sh`成功（XCTest 62件中61件成功＋性能test 1件skip、Swift Testing 65件成功、macOS Debug build成功）。
- Release build `20260926223530`を`/Applications/HomeStereo.app`へ配置し、署名、bundle identifier、SHA-256一致を確認して起動した。実音確認は未実施。
