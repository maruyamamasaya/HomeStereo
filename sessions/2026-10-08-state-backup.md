# 保存状態JSON backup Beta

- MyMusic側の明示依頼を受け、JSON backupをv2へ拡張。既存SQLite schema v14/MyMusic wireを変更せず、DB backup API snapshot、features、PlaylistImportArchive、AnalysisRuns、選定4 settingsをSHA付きpayloadへ保存する。
- v1 decode/mergeを維持し、旧形式にない既存tags/Playlist連携IDを保持。v2は確認後pendingへ保存し、次回App initでrepository open前に検証・適用。旧rootは退避して自動削除しない。
- StateBackupTests: temp保存先でJSON encode/decode、stage/startup apply/reopen、代表10table全field/ID/曲順/重複参照/tags/評価/詳細event/link/累計/fingerprint/features/音量/settings/原本の一致、破損DB/path拒否を確認。LegacyBackupResolutionTestsも追加。
- 最終./scripts/verify.sh成功: XCTest139（3skip）、Swift Testing85、macOS Debug BUILD SUCCEEDED。初回sandbox cache制限は承認付き既存verifyで解消。testで発見したtemp path正規化/fixture日時精度を修正して再検証。
- docs/json-backup.mdを現行仕様へ書換え、CURRENT/ARCHITECTURE更新。新Swift fileだけXcode sourceへ追加。
- 未検証: 実Mac UI、別Mac bookmark再設定/音源接続、大容量/空き容量障害、全UserDefaults/Analyzer資産の保全。新v2は旧appでは読めない。複数fileの同時点凍結ではない。
- 実データrestore/正式配置/commitなし。Simulator/test端末なし、macOS native Swift Package testsのみ。
