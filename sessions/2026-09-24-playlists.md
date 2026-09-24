# Playlist phase

- ローカルPlaylistの作成、名称変更、削除、順序編集、複数選択削除を追加。
- 曲、Album、Artist、現在QueueからTrack ID参照で追加し、音源を複製しない。
- missing参照を保持し、M3U8 Import／Exportでは相対pathの一意候補だけを接続する。
- Playlist保存はSQLite transactionで適用し、更新日時が古い保存の後着を拒否する。
- `./scripts/verify.sh`: 36 tests passed、macOS Debug build succeeded。
- SRS-HG1でのPlaylist連続再生は実機確認まで保留。
