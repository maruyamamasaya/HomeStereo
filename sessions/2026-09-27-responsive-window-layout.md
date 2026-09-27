# Responsive Window Layout

- メインWindowの初期サイズを1280×760px、最小content sizeを760×460pxへ調整し、外枠込み960×540級でも利用できるようにした。
- 1180px未満ではQueue Inspectorを自動的に表示対象から外し、Toolbarの同じ操作をQueue画面への移動へ切り替えた。幅を戻したときは利用者が保存したInspector表示設定を復元する。
- Now Playingバーを含む既存のsystem fontと`ViewThatFits`を維持し、狭い幅でもフォント自体は縮小しない。
- `./scripts/verify.sh`成功。XCTest 82件中81件成功＋性能test 1件skip、Swift Testing 75件成功、macOS Debug build成功。
- Debug版を実際に1920px級から960×540級へresizeし、Queue Inspectorの自動退避、Toolbar操作のQueue画面切替、Now Playingバーの折り返し、system fontの可読性を目視確認した。広幅へ戻すとInspectorが復元されることも確認した。
- 高さ620px未満ではSidebarのセクション見出しだけを省略し、文字サイズを維持したまま「MyMusic適用状況」まで全項目を表示する。`/Applications/HomeStereo.app`のRelease版を高さ540px級へresizeして確認した。
- Release build `20260927111752`を`/Applications/HomeStereo.app`へ配置し、署名・bundle ID・build番号・実行ファイルSHA-256一致をdeploy scriptで確認して起動した。
