# 現在曲のGood／Bad操作

- メニューバーに現在曲の評価値とGood +1／Bad −1を追加。
- 下部再生バー右側と小型プレイヤーに、右下の数値バッジ付き👍／👎を追加。既存PlaybackPreferenceStoreを共有し、−10〜+10の境界と保存処理を維持。
- ライブラリ曲を特定できない直接ファイルや同期チェックでは評価操作を表示しない。保存失敗はメニューの文言／アイコンのエラー表示で示す。
- 検証: ./scripts/verify.sh成功（XCTest 99件中98件成功・性能1件skip、Swift Testing 78件成功、macOS Debug build成功）。初回fastはsandboxによるキャッシュアクセス制限で停止し、権限付きfullで確認。
- 実画面の配置・クリック操作は未確認。既存の作業中差分を保持。Applicationsへの配備は未実施。
