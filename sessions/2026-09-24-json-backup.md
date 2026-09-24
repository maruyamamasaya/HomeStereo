# JSON Backup phase

- kindとschemaVersionを持つ正式なversion 1 contract、UTC日時、UUID、Track復元hintを実装。
- key／collection順を安定化し、一時fileへのatomic Exportを追加。
- 全体検証後の照合preview、明示確認、単一SQLite transaction merge、rollbackを実装。
- 曖昧候補を拒否し、未解決参照を保持。既存データ、Queue、再生は変更しない。
- schema説明、完全fixture、migration方針を`docs/json-backup.md`へ記録。
- `./scripts/verify.sh`: 45 tests passed、macOS Debug build succeeded。
