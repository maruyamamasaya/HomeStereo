# MyMusic JSON interchange

iPhone版MyMusicとの連携では、音源を含めず、次の4文書を独立して扱う。

- `MyMusic-Library.json`: `version: 1`、曲metadata。識別子のfield名は`trackID`。選択した共通音楽ルート以下の`relativePath`と`fileSize`をoptionalで持つ。
- `MyMusic-Playback-Preferences.json`: `schemaVersion: 2`、お気に入りと長期的な好み。識別子のfield名は`trackId`。
- `MyMusic-Playback-Events.json`: `schemaVersion: 1`、append-onlyの再生イベント。識別子のfield名は`trackId`。

Library Importでは曲の照合だけでなく、明示された`playCount`と`lastPlayedAt`を未照合Track IDも含めてsnapshot保存する。分析の全期間再生回数はこの`playCount`を正本とし、期間別回数、再生時間、完走／Skip率はPlayback Eventsを使う。
- `MyMusic-Playlists.json`: `version: 1`、単一または複数プレイリスト。曲識別子のfield名は`trackID`。同じ契約の`MyMusic-Regular-Playlists.json`と`MyMusic-Work-Playlists.json`も受理する。

JSON契約の正本は`MyMusicJSONContract.swift`、JSONから独立した交換modelは`MyMusicInterchangeModels.swift`、変換境界は`MyMusicJSONService.swift`とする。日時はUTC ISO 8601、秒数は有限かつ0以上、UUIDは標準文字列としてdecodeする。optional値はencode時に省略する。

Import serviceはUTF-8の文書全体をdecode・検証してから内部交換modelを返す。未知version、重複ID、不正日時、不正範囲、未知の列挙値、`completed == true && skipped == true`を拒否する。service自身は永続化しないため、不正文書の部分保存は発生しない。`MyMusicImportMergeService`はLibrary／PreferencesをTrack UUID単位でmergeし、JSONにない既存値を残す。Eventsは`eventId`単位で重複を除いてappendする。永続化を接続する際は、この結果を文書単位の単一transactionで保存する。

曲一覧の`favorite`と`playCount`は互換用の派生値であり、正本はそれぞれPreferencesとPlayback Eventsである。Library importで受けた`trackID`は内部交換modelでも同じUUIDを保持し、別UUIDを生成しない。Preferencesは`trackId`単位のmerge、Eventsは`eventId`単位の重複排除とする。JSONにない既存値を削除しない。HomeStereoからPreferencesを書き出すときは、MyMusic Track ID接続済みかつMac側でFavoriteまたは`track_preferences`を変更した曲だけをschema version 2のまま出力する。未接続曲はHomeStereo Track IDを外部へ出さず、接続後まで未送信状態を保持する。

## Canonical identity

MyMusicが発行する`trackID`だけを端末間のCanonical Track IDとする。HomeStereoの`tracks.id`はローカルDB主キーとして維持し、MyMusic IDを持たない曲へ外部UUIDを発行しない。MyMusic向けJSONへHomeStereo Track IDを出力しない。

## SQLite persistence

SQLite schema v10ではHomeStereoの`tracks.id`を変更せず、次を利用する。

- `tracks.audio_fingerprint`: HomeStereo側で既知の64文字SHA-256。未計算ならNULL。
- `mymusic_track_links`: HomeStereo Track IDとMyMusic Track IDの1対1対応、MyMusic側のrelative path／file size／duration／fingerprint、`first_seen_at`、`last_seen_at`、最新snapshot在籍状態、`matched_at`、`match_method`、`source`。
- `playlists.mymusic_playlist_id`: MyMusicのCanonical Playlist ID。ローカル主キーは維持し、`kind`と`tags_json`も保存する。
- `mymusic_preferences`: 解決済み曲の`playback_preference`と`favorite`。Favoriteは既存`favorites` tableにも同じtransactionで差分反映する。
- `mymusic_preference_export_changes`: MacでFavorite／Good／Badを変更したHomeStereo Track ID、変更世代token、変更日時。MyMusic JSONには含めないローカル送信管理情報。
- `mymusic_playback_events`: MyMusic互換event。`event_id`を主キーとしappend-onlyで保存する。HomeStereo生成eventは未連携曲でも保持できるよう`mymusic_track_id`をnullableとする。

データフローは`JSON Data -> MyMusicJSONImportService -> JSON非依存交換model -> MyMusicPersistenceService -> MyMusicPersisting -> SQLite transaction`とする。DTOはtableやSQLを参照しない。

MyMusicとHomeStereoが同じiCloud Drive音楽フォルダを参照する場合、`relativePath`は各端末で利用者が選択した共通音楽ルートから音源までのパスとする。iCloud containerまでの絶対パス、File Provider固有prefix、端末名、ユーザー名は含めない。Library照合は、保存済みMyMusic Track ID、Unicode NFCのrelative path完全一致、同候補のfile size＋duration検証、パス候補がない場合だけaudio fingerprint完全一致、title＋artist＋album＋durationの保守的一致の順で行う。duration許容差は0.5秒。区切りは`/`、大文字小文字は区別し、絶対パス、`.`、`..`、先頭`./`、backslashを拒否する。パス候補とsize／durationが矛盾する場合は別方式へfallbackせず未解決とする。複数候補は`ambiguous`、別MyMusic IDへ接続済みなら`conflict`とし、title単独では接続しない。旧Library v1にrelative pathとfile sizeがない場合、その段階を飛ばす。

HomeStereoの既存`tracks.id`は変更せず、相対パスから新しいCanonical IDを生成しない。アプリ間のCanonical IDはMyMusic Library JSONから受け取った`trackID`であり、`mymusic_track_links.myMusicTrackID`としてHomeStereo曲へ関連付ける。HomeStereoのrelative pathはこの関連付けの照合キーである。

Library snapshotは1 transactionで適用する。snapshotから消えたlinkは`in_current_snapshot = 0`とするが、HomeStereo Track、既存Playlist、履歴とその参照は削除しない。

Preferencesと外部Import Eventsは保存済みlinkからHomeStereo曲を解決する。未解決Preferences／外部Eventsはゴースト曲を作らず結果へ残し、SQLiteへ保存しない。Eventsの元platformは維持する。同一event IDは再Import時に無視する。各文書のdecode・全体検証が成功した後だけ単一transactionを開始し、SQL失敗時はrollbackする。

HomeStereoの実再生は`QueueStore -> ListeningStore -> MyMusicPlaybackSession -> MyMusicPersisting -> SQLite`で記録する。Sessionは再生開始時に`mac-{UUID}`を採番し、Renderer位置の5秒以下の正差分だけを実聴時間へ加える。pause/resumeは同一Sessionを使い、seek、buffer、停止時間は加算しない。終了は共通finalizeへ集約し、`listenedSeconds >= max(3, trackDuration * 0.94)`をcompleted、未完了かつ明示的な曲移動だけをskippedとする。

未連携のHomeStereo生成eventはHomeStereo Track IDで保存し、JSON export時に最新の`mymusic_track_links`から再解決する。解決済みeventだけをJSONへ含め、`exportPlaybackEventsWithReport`がexport件数と未解決件数を返す。再生回数表示は保存eventとは分離し、`listenedSeconds >= min(30, trackDuration * 0.5)`を採用する。

## Playlist JSON

単一プレイリストrootと`playlists`配列rootの両方を受理する。統合版、通常版、作業用版はファイル名ではなく各Playlistの`kind`で区別する。曲は`trackID == mymusic_track_id`の完全一致だけで解決し、metadataから推測しない。未解決・競合曲は除外して件数を報告し、解決済み曲の順序を保つ。同じ`playlistID`の再Importは既存Playlistを更新して重複を作らず、文書全体を1 transactionで適用する。

Exportは全ローカルPlaylistを複数形式で書き出す。各曲にはMyMusic Track IDだけを使用し、未接続または競合中の曲は除外して、総曲数、出力曲数、未接続数、競合数を表示する。`kind`はImport値またはローカル作成時の`regular`／`work`を維持する。Sidebarでは通常と作業用を別画面に表示し、ローカル追加時も種類を混在させない。作業用曲はdurationではなく、複数genreを`;`またはNULで分割・trimした集合に「作業用BGM」が含まれるかだけで判定する。MyMusicから再Importされた同一`playlistID`を以後の正本として扱う。M3U8は一般互換用途として維持し、Identity同期には使わない。

## Manual Import / Export

アプリのSidebarにある「管理 > MyMusic連携」から、4文書を個別に手動Import／Exportできる。現在はユーザーが標準ファイル選択・保存panelで操作する手動連携のみで、自動同期、folder監視、iCloud同期は行わない。

「管理 > MyMusic適用状況」では、全HomeStereo曲についてローカルTrack IDとMyMusic TrackIDを並べ、最新Library snapshot在籍、照合方法、Library JSON出力対象、Preferences、互換Playback Events、MyMusic由来Playlistを確認できる。未接続曲とsnapshot外の接続は別状態として表示し、検索と状態filterを提供する。この画面は確認専用で、対応関係を編集しない。

推奨Import順序は次の通り。

1. `MyMusic-Library.json`
2. `MyMusic-Playlists.json`
3. `MyMusic-Playback-Preferences.json`
4. `MyMusic-Playback-Events.json`

Importはファイル名ではなくroot構造とversionを検証し、照合結果をPreviewした後、「読み込む」が押された場合だけSQLite transactionを実行する。選択URLは読み取り中だけsecurity-scoped accessを開始し、恒久参照やbookmarkとして保持しない。明細表示は先頭100件に制限する。

Playlist Importのtransaction完了後は`PlaylistStore`を再読込し、プレイリスト画面へ即時反映する。Preferences Import後も`ListeningStore`を再読込する。再読込はcommit成功後だけ行い、Import失敗時に既存画面状態を成功扱いで更新しない。

Exportできる文書はLibrary、Playlists、Preferences、Playback Eventsの4種類。PreferencesはMyMusic側のschemaを変更せず、最後のMyMusic Import以降にMacで変更した接続済み曲だけをCanonical Track ID、現在のお気に入り、`-10...+10`のGood／Badとして出力する。書き出し前に対象件数と先頭100曲を確認でき、保存panelのキャンセルまたは書込失敗では未送信状態を維持する。保存成功後はPreview時点の変更tokenだけを解除し、Preview後に同じ曲を再編集した場合は次回分へ残す。MyMusic Importは含まれる曲をMacの現在値へ反映し、該当曲の未送信状態を解除する。したがってMyMusicで変更した曲AとMacで変更した曲Bは、Macから曲Bだけを書き戻して両方を維持できる。同じ曲を両側で変更した場合は、最後に行ったImportまたはMac編集が優先される。Playback Eventsは既定で直近1か月を対象とし、開始日と終了日（両日を含む）または全期間を選べる。選択期間内でMyMusic Track IDを解決できたeventだけを書き出し、同じ期間内で除外した未解決件数を画面へ表示する。期間内が0件でも有効な空`events`配列を書き出す。MyMusic側は厳格検証とPreview確認を経るPlayback Events手動Importに対応している。Import Previewを表示中に別のImport／Exportを選んだ場合は、未適用のPreviewを破棄して選択した操作へ切り替える。ファイルpanelをキャンセルした場合はPreviewを維持する。
