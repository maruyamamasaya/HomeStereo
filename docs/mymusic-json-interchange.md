# MyMusic JSON interchange

iPhone版MyMusicとの将来連携では、音源を含めず、次の3文書を独立して扱う。

- `MyMusic-Library.json`: `version: 1`、曲metadata。識別子のfield名は`trackID`。
- `MyMusic-Playback-Preferences.json`: `schemaVersion: 2`、お気に入りと長期的な好み。識別子のfield名は`trackId`。
- `MyMusic-Playback-Events.json`: `schemaVersion: 1`、append-onlyの再生イベント。識別子のfield名は`trackId`。

JSON契約の正本は`MyMusicJSONContract.swift`、JSONから独立した交換modelは`MyMusicInterchangeModels.swift`、変換境界は`MyMusicJSONService.swift`とする。日時はUTC ISO 8601、秒数は有限かつ0以上、UUIDは標準文字列としてdecodeする。optional値はencode時に省略する。

Import serviceはUTF-8の文書全体をdecode・検証してから内部交換modelを返す。未知version、重複ID、不正日時、不正範囲、未知の列挙値、`completed == true && skipped == true`を拒否する。service自身は永続化しないため、不正文書の部分保存は発生しない。`MyMusicImportMergeService`はLibrary／PreferencesをTrack UUID単位でmergeし、JSONにない既存値を残す。Eventsは`eventId`単位で重複を除いてappendする。永続化を接続する際は、この結果を文書単位の単一transactionで保存する。

曲一覧の`favorite`と`playCount`は互換用の派生値であり、正本はそれぞれPreferencesとPlayback Eventsである。Library importで受けた`trackID`は内部交換modelでも同じUUIDを保持し、別UUIDを生成しない。Preferencesは`trackId`単位のmerge、Eventsは`eventId`単位の重複排除とする。JSONにない既存値を削除しない。

## SQLite persistence

SQLite schema v9ではHomeStereoの`tracks.id`を変更せず、次を利用する。

- `tracks.audio_fingerprint`: HomeStereo側で既知の64文字SHA-256。未計算ならNULL。
- `mymusic_track_links`: HomeStereo Track IDとMyMusic Track IDの1対1対応、照合時snapshot、`matched_at`、`match_method`、`source`。
- `mymusic_preferences`: 解決済み曲の`playback_preference`と`favorite`。Favoriteは既存`favorites` tableにも同じtransactionで差分反映する。
- `mymusic_playback_events`: MyMusic互換event。`event_id`を主キーとしappend-onlyで保存する。HomeStereo生成eventは未連携曲でも保持できるよう`mymusic_track_id`をnullableとする。

データフローは`JSON Data -> MyMusicJSONImportService -> JSON非依存交換model -> MyMusicPersistenceService -> MyMusicPersisting -> SQLite transaction`とする。DTOはtableやSQLを参照しない。

Library照合は、保存済みMyMusic Track ID、audio fingerprint完全一致、relative path＋file size＋duration、title＋artist＋album＋durationの保守的一致の順で行う。metadata候補が複数、または候補が別MyMusic IDへ接続済みなら`ambiguous`とし、title単独では接続しない。現行Library v1にrelative pathとfile sizeがない場合、その段階を飛ばす。

Preferencesと外部Import Eventsは保存済みlinkからHomeStereo曲を解決する。未解決Preferences／外部Eventsはゴースト曲を作らず結果へ残し、SQLiteへ保存しない。Eventsの元platformは維持する。同一event IDは再Import時に無視する。各文書のdecode・全体検証が成功した後だけ単一transactionを開始し、SQL失敗時はrollbackする。

HomeStereoの実再生は`QueueStore -> ListeningStore -> MyMusicPlaybackSession -> MyMusicPersisting -> SQLite`で記録する。Sessionは再生開始時に`mac-{UUID}`を採番し、Renderer位置の5秒以下の正差分だけを実聴時間へ加える。pause/resumeは同一Sessionを使い、seek、buffer、停止時間は加算しない。終了は共通finalizeへ集約し、`listenedSeconds >= max(3, trackDuration * 0.94)`をcompleted、未完了かつ明示的な曲移動だけをskippedとする。

未連携のHomeStereo生成eventはHomeStereo Track IDで保存し、JSON export時に最新の`mymusic_track_links`から再解決する。解決済みeventだけをJSONへ含め、`exportPlaybackEventsWithReport`がexport件数と未解決件数を返す。再生回数表示は保存eventとは分離し、`listenedSeconds >= min(30, trackDuration * 0.5)`を採用する。

## Manual Import / Export

アプリのSidebarにある「管理 > MyMusic連携」から、3文書を個別に手動Import／Exportできる。現在はユーザーが標準ファイル選択・保存panelで操作する手動連携のみで、自動同期、folder監視、iCloud同期は行わない。

推奨Import順序は次の通り。

1. `MyMusic-Library.json`
2. `MyMusic-Playback-Preferences.json`
3. `MyMusic-Playback-Events.json`

Importはファイル名ではなくroot構造とversionを検証し、照合結果をPreviewした後、「読み込む」が押された場合だけSQLite transactionを実行する。選択URLは読み取り中だけsecurity-scoped accessを開始し、恒久参照やbookmarkとして保持しない。明細表示は先頭100件に制限する。

Exportできる文書はLibrary、Preferences、Playback Eventsの3種類。Playback EventsはMyMusic Track IDを解決できたeventだけを書き出し、除外した未解決件数を画面へ表示する。0件でも有効な空`events`配列を書き出す。MyMusic側のPlayback Events Importは現時点では未実装である。
