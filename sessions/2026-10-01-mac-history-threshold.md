# Macの短時間再生記録を除外

- HomeStereoで新規生成する履歴とMyMusic互換Playback Eventsは、実聴時間が30秒を超えた場合だけ保存。30秒以下は完走・停止とも除外し、checkpoint／flushでも書き込まない。
- 履歴のplayedSecondsも既存セッションの位置差分に揃え、pause／seekを除外。開始時の0秒履歴表示をやめ、既存履歴と外部Importは変更しない。
- CURRENT、TESTING、MyMusic連携仕様に条件を記載。
- 検証: fastとfull成功。XCTest 99件中98件成功・性能1件skip、Swift Testing 79件成功、Debug build成功。0／29／30／31秒、停止／完走、pause／seek、途中flushを検証。Queue連携テストの時間入力はposition callbackで決定的に供給。
- 実機再生は未確認。既存記録の削除とApplicationsへの配備は行っていない。
