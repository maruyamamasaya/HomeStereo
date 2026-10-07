# HomeStereo JSON Backup contract

更新: 2026-10-08。アプリの書き出しは`kind: "home-stereo-backup"`、`schemaVersion: 2`。既存schemaVersion 1の読み込みを維持する。SQLite schema v14、MyMusic連携JSONのwire形式は変更しない。

## 新形式v2の保存範囲

既存のplaylists/favorites/playbackEvents/settingsに加え、`state`を持つ。stateは`databaseSchemaVersion`、`files`、`settings`からなる。各fileは相対path、base64のdata、SHA-256。settingsは選定UserDefaultsをbinary plistにしたbase64である。

- `Library.sqlite3`: SQLite backup APIでsnapshot。全テーブルのID・曲順・タグ・Favorite・Good/Bad・簡易/詳細Events・集計・MyMusic link/送信世代・genre preset・queue・folder bookmarkを保持する。
- `track-features.json`: 特徴量、音量解析、解析由来と両曲IDを保持する。
- `PlaylistImportArchive`、`AnalysisRuns`: 実在する全通常ファイルを保持する。列挙/読取失敗・symlinkでは書き出しを中止し、無言で部分backupを作らない。
- settings: `LibraryAutoUpdateEnabled`、`audio.normalization.enabled`、`analysis.concurrency`、`appearance.theme`。

音源、Analyzer companionのmodel/cache、すべてのUserDefaults、スピーカー設定、Artwork cache等は対象外。フォルダのpath/bookmarkはDBに残るが、別Macで同じアクセス権が使える保証はない。音源を別途保存し、必要に応じて登録済みフォルダへのアクセスを再設定する。新Macへの実機移行は未検証。

JSONは単一ファイルだがbase64のため元ファイルより大きい。メモリへpayloadを読み込む。大容量履歴/原本/AnalysisRunsでの性能・空き容量は実機計測が必要。DB snapshotはSQLite単位で整合し、別JSONや解析途中ファイルまで全体を凍結するtransactionではない。再生中の未確定sessionは確定済み履歴とは別である。

## v2復元

1. 文書全体をdecodeしversion、hash、許可path、plist、DB integrity/foreign key/schema、Feature modelを確認する。
2. 確認画面は保存状態の置き換えと再起動の必要性を示す。確認後だけpending directoryへ保存する。live DBは変更しない。
3. 次回起動時、SQLite repositoryを開く前にpendingを再検証し適用する。現在のHomeStereo rootはApplication Support内の`HomeStereo-before-restore-<UUID>`へ退避して保持する。
4. 選定設定を戻し、各Storeが既存形式からloadする。復元準備後の追加backup操作は抑止する。

退避は自動削除しない。復元前に空き容量が必要。復元時に書き出されていた状態へ戻るため、それ以降の変更が現在状態には含まれなくなることを確認画面で明示する。既存JSONのmergeとは異なる。

現行受信側はDB schema v14だけを許可し、未知version/schemaを推測変換しない。旧アプリは新v2を読めない。既存v1 backupは新アプリで引き続き読める。

## 旧形式v1

UTF-8のJSON、日時は小数秒付きISO-8601 UTC、UUID文字列、有限非負数。`Tests/Fixtures/home-stereo-backup-v1.json`を回帰資産として維持する。

v1はPlaylistのID/名称/日時/kind/順序付き曲参照、Favorite、簡易Playback Event、automaticLibraryUpdatesだけを持つ。詳細Events、評価、link、tags、featuresは持たない。

Importは文書全体を検証してからID、相対path、size/duration、metadataで照合する。曖昧/未解決は元ID参照を保持する。Playlist更新、Favorite merge、event ID重複排除をSQLite transactionで行い、文書にないデータを全削除しない。既存PlaylistのtagsとMyMusic Playlist IDは、v1にないため維持する。新Playlistのtagsは空。失敗時はrollbackする。

## 検証

`StateBackupTests`はtemp保存先でJSON往復、pending、次回起動適用、repository再openを通し、代表10テーブルの全field、Playlist item ID/曲順/重複参照/tags、評価、詳細event、link、累計、fingerprint、feature/音量原本bytes、settings、Import原本の一致を確認する。破損DBとpath traversalがpendingを作らないことも確認する。

旧v1 fixture往復と`LegacyBackupResolutionTests`で既存tags/連携ID保持を確認する。これらは実データ/別Macの権限/大容量の操作確認の代用ではない。
