# MyMusic Canonical Identity・Playlist JSON連携

## 実装

- MyMusic `trackID`をCanonical IDとし、HomeStereo Track IDをローカル主キーのまま維持した。
- relative pathを`/`区切り、Unicode NFC、case-sensitiveで検証・照合する。絶対パス、`.`、`..`、backslashは禁止した。
- 照合順を保存済みID、relative path＋file size＋duration、fingerprint、metadata fallbackとし、duration許容差を0.5秒にした。曖昧とID競合を分けて報告する。
- SQLite schema v10へMyMusic snapshotのfirst／last seenと在籍状態、PlaylistのCanonical ID／kind／tagsを追加した。snapshotから外れた曲と既存参照は削除しない。
- MyMusic Playlist JSON v1の単一／複数形式を追加した。曲はCanonical Track ID完全一致だけで解決し、未解決曲を安全に除外する。
- `playlistID`単位で追加／更新し、同一文書の再Importで重複を作らない。文書単位transactionで失敗時にrollbackする。
- Playlist exportはMyMusic Track IDだけを使用し、総曲数、出力数、未接続数、競合数を表示する。M3U8機能は維持した。

## 検証

- `./scripts/verify.sh`成功。XCTest 72件中71件成功、任意の30,000曲性能test 1件skip。Swift Testing 68件成功、macOS Debug build成功。
- 単一／複数Playlist JSON、旧Library JSON、NFC、case sensitivity、相対path重複、保存済みID優先、fingerprint、冪等Import、部分Import、ローカルID非出力、snapshot除外後の履歴／Playlist保持、transaction rollbackを自動testで確認した。

## デプロイ

未実施。追加要件完了後にまとめて実施する。
