# MyMusic IDと同期の調査

- HomeStereo IDとMyMusic IDは`mymusic_track_links`で対応付け、ローカルIDは変更しない。
- 未接続時のMac生成Playback Eventsは保存され、Export時に最新linkからMyMusic IDを解決する。既存の遅延解決testも確認した。
- Favorite／Good・Badの未送信変更もHomeStereo IDで記録し、接続後にPreferencesへ出力する。
- Preferences Importは対象曲のMac現在値を反映し、未送信変更を解除する。接続後にこれをImportした場合、先行したMac編集が書き戻し対象から消える。
- PreferencesとEventsは独立した手動JSON連携。Eventsの既定範囲は直近1か月。Mac生成履歴は実聴30秒超のみ。
- 今回は実装と既存testの読解のみ。実データの対応・出力JSON・MyMusic側Importは未確認。実装変更・test実行なし。
