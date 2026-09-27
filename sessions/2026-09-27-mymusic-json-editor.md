# MyMusic JSON加工ツール

- 管理Sidebarへ臨時の「開発者」を追加した。
- Library／Playlist／Preferences／Playback Eventsを、現在のSQLite値から生成するか既存JSONから開ける。
- 大量データを全セル展開せず、左で1レコードを選び、右の表で文書設定と選択レコードの文字列／数値／真偽値を編集する。
- 編集内容はSQLiteへ戻さず、MyMusic JSON contractの検証に成功した場合だけ任意のJSONファイルへ保存する。
- 単一Playlist JSONは編集時に統合版の`playlists`配列へ正規化する。
- `swift test --filter MyMusicTransferStoreTests`成功（9件）。`./scripts/verify.sh`成功（XCTest 87件中86件成功＋性能test 1件skip、Swift Testing 77件成功、macOS Debug build成功）。
- 実画面での大量Library、Keyboard、VoiceOver、狭いwindowの確認は未実施。
