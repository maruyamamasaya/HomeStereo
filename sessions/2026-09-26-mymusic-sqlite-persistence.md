# Session: MyMusic SQLite persistence
Date: 2026-09-26

## Request
MyMusic JSON交換modelをHomeStereo SQLiteへ接続し、外部Track ID対応、Preferences、Playback Eventsを再起動後も維持する。

## Investigation
既存schema v6、単一transactionのmigration、Track scan transaction、Favorite／旧PlaybackEvent／Backup mergeを確認した。外部ID管理は存在しなかった。

## Changes
- 同時追加されたbit rate永続化と共存するschema v8へ移行し、`tracks.audio_fingerprint`、`mymusic_track_links`、`mymusic_preferences`、`mymusic_playback_events`を追加。
- JSON DTO非依存の永続化model、Repository protocol、Import／Export serviceを追加。
- 保存済みID、fingerprint、path＋size＋duration、保守的metadataの順で照合し、曖昧候補を保存しない。
- Preferencesを既存Favoriteと同一transactionでmerge。未記載値を維持し、同値更新を省略。
- Eventsをevent IDでappend-only保存。未解決eventは報告して保存せず、元platformを維持。
- 再Import、再起動、migration、rollbackを含む永続化testを追加。

## Validation
- `swift test --filter MyMusicPersistenceTests`
- `./scripts/verify.sh fast`

## Result
外部Track ID対応とMyMusic連携データがSQLiteへ永続化され、JSON文書単位で検証・transaction適用できる。

## Remaining Issues
file選択UI、自動同期、実再生処理からのMyMusic互換event生成、audio fingerprintの計算処理は未実装。
