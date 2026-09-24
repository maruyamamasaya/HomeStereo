# Apple Music風UI改善 第一段階

- Sidebarを「ライブラリ」「コレクション」「再生」「管理」に分け、日本語の利用者向け名称へ整理した。
- 画面下部へArtwork、曲名、Artist、前／再生／次、出力先、経過時間を表示する常設Now Playingバーを追加した。
- 通信復旧表示はNow Playingバーの下へ統合し、既存のQueue Inspectorと再生処理は維持した。
- 別Bundle IDの検証用Appで、2台のRenderer表示、Sidebar、空のNow Playing状態を目視確認した。
- `./scripts/verify.sh fast`と`./scripts/verify.sh`が成功（通常test 65件、20,000曲性能test 1件skip、macOS Debug build成功）。
