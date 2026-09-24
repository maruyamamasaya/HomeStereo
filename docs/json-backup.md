# HomeStereo JSON Backup contract

`kind: "home-stereo-backup"`、`schemaVersion: 1`を正式な交換契約とする。文書はUTF-8の単一JSONで、日時は小数秒を含むISO-8601 UTC、IDはUUID文字列、数値は有限かつ非負である。完全なfixtureは[`Tests/Fixtures/home-stereo-backup-v1.json`](../Tests/Fixtures/home-stereo-backup-v1.json)を参照する。

## Top-level

```json
{
  "kind": "home-stereo-backup",
  "schemaVersion": 1,
  "exportedAt": "2026-09-24T00:00:00.000Z",
  "appVersion": "1.0",
  "playlists": [],
  "favorites": [],
  "playbackEvents": [],
  "settings": { "automaticLibraryUpdates": true }
}
```

Playlistは`id`、`name`、`createdAt`、`updatedAt`、順序を保つ`tracks`を持つ。Favoriteは`track`と`addedAt`、Playback Eventは`id`、`track`、`startedAt`、`playedSeconds`、`outcome`（`completed`または`stopped`）を持つ。

Track参照は`trackID`、`relativePath`、`fileSize`、`duration`、`title`、任意の`artist`／`album`からなる。絶対path、bookmark、機器IP、一時HTTP URL、音源、Library index、Artwork、認証情報は含めない。

## Validation and import

Importは文書全体を先にdecode・検証し、kind／version、不正UUID／日時、重複Playlist・Favorite・event ID、NaN／Infinity、負数を拒否する。Track照合はID、相対path一意一致、相対path＋size＋durationの一意一致、metadata＋durationの一意一致の順で行う。曖昧候補は接続せず、未解決とともにpreviewへ表示する。

確認後、Playlist更新／追加、Favorite merge、event ID重複排除を単一SQLite transactionで適用する。JSONにない既存データは削除しない。失敗時はrollbackする。ImportはQueue、再生、SRS-HG1を操作しない。

## Stable output and migration

object key、Playlist、Favorite、Playback Eventの順序を安定化し、Playlist内の曲順だけは意味のある順序として保持する。`exportedAt`以外が同じ入力なら同一内容になる。

互換性を壊す変更ではschemaVersionを増やす。新versionを追加するときは、旧version専用DTOを保持し、検証後に最新の内部表現へ明示migrationする。未知versionを推測して読み替えない。version 1 fixtureは回帰資産として永続的に保持する。
