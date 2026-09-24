# Automatic Library update phase

- FSEventsで登録folder配下の追加／変更／削除を監視し、通知を2秒debounceして既存差分scanへ接続。
- scan世代IDでキャンセル済みの古い結果をDBへ反映しない。
- metadata解析後にもsize／更新日時を再確認し、コピー中ファイルは次回scanまで保留。
- 権限消失、キャンセル、sleep中は既存Libraryを維持し、wake後に監視と差分scanを再開。
- 自動更新ON／OFFと最終更新日時をfolder画面へ追加。
- 41 tests passed、macOS Debug build succeeded。
- 実folder変更とsleep連携は実機確認まで保留。
