# Compact Main Window

- メインWindowの初期幅を1080pxから820pxへ縮小した。
- Sidebarの基準幅を縮め、Now Playingバーを利用可能な幅に応じて1段／2段へ切り替えるようにした。
- Now Playingバーの出力先表示をRenderer選択メニューへ変更し、再生操作の近くで選択と再検索ができるようにした。
- 旧window frameの保存値が新しい初期サイズを打ち消さないよう、autosave keyを更新した。
- 旧レイアウトで開いたQueue Inspectorが横幅を広げたまま復元されないよう、表示状態の保存キーを移行した。
- 狭いWindowの最小サイズを680×520pxに定めた。
- `./scripts/verify.sh`成功（通常test 63件、20,000曲性能test 1件skip、macOS Debug build成功）。
