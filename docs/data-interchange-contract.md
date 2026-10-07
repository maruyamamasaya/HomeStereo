# MyMusic / HomeStereo データ交換・保全契約

契約ID: `mymusic-homestereo-interchange`
文書revision: 3 / 更新日: 2026-10-04
状態: 共通設計方針。既存wire形式を変更しない。未実装の保全要件は下記に区別する。

## 目的と責務

両アプリで交換データの粒度と意味を揃え、Import、Export、照合失敗、競合、再送、障害で利用者のデータを失わないことを目標にする。文書の存在だけでは無消失を保証しない。実装・障害試験・復元検証を通して達成を確認する。

両者は別Gitの独立したプレイヤーであり、製品方針ではMyMusicを中心に置く。HomeStereoは検索・分析・統合的な設定を担い、Mac固有の再生音響・スピーカー設定は独立して発展させる。各アプリのDBや保存領域へ相手が直接書き込まない。製品上の優先順位とデータの所有権・競合解決は別に定義する。

## 共通粒度と既存wire形式

| データ | 交換単位と識別 | 既存形式 | 保存上の意味 |
| --- | --- | --- | --- |
| Library | 論理曲1件、MyMusic発行Track ID | Library version 1、`trackID` | 曲の照合用snapshot。収録外は履歴削除を意味しない |
| Preferences | 曲1件のFavoriteと長期的Preference | schemaVersion 2、`trackId` | 記載曲のmerge。欠落は削除・初期化を意味しない |
| Playback Events | 再生session由来の確定event 1件、`eventId` | schemaVersion 1、`trackId` | event IDでappend・重複排除。集計値と混同しない |
| Playlists | Playlist 1件、`playlistID`と順序付き曲参照 | version 1、曲は`trackID` | 順序・kind・tagsを保持。未照合曲の欠落を意図的削除と区別する |

HomeStereoのローカルTrack主キーは維持し、MyMusic Track IDへの対応を別管理する。未接続曲に交換用MyMusic IDを捏造しない。Library照合には共通音楽root以下のrelativePath、fileSize、duration等を使い、端末固有絶対pathを交換Identityにしない。曖昧候補は統合しない。

Playback Eventsのrootは`schemaVersion`、`exportedAt`、`events`。各eventは`eventId`、`trackId`、`trackTitle`、`artist`、optional `album`、`playedAt`、`playDuration`、`trackDuration`、`completed`、`skipped`、`playSource`、`selectionType`、`platform`、`schemaVersion`を保持する。eventIdはUUID限定ではなく非空の安定した文字列、trackIdはUUIDである。時刻はタイムゾーン付きISO 8601、秒は有限・非負。表示日付のCalendar集計と絶対時刻を区別する。

MyMusic受信側は`completed == (playDuration >= max(3, trackDuration × 0.94))`を検証し、completedとskippedの同時trueを拒否する。元platformとevent IDを再Exportでも維持する。再生回数の加算閾値と完走判定は別概念であり、集計回数だけから詳細eventを作らない。

Features・音量解析・ジャンルプリセット等は個別の既存契約を参照する。この文書で新たな共通wire形式を発明しない。Mac固有スピーカー設定は共通交換の対象外とし、追加依頼時に個別に設計する。

## 保全要件（実装の達成確認が必要）

1. Import元の原本bytesと内容hash、受信日時、送信元、契約versionを保持する。新規fieldを既存JSONへ無断追加せず、必要なら別の管理record／sidecarとして設計する。
2. 文書全体の検証後に適用する。不正文書や保存失敗では既存値を変更せず、transaction rollback／atomic保存を用いる。memory反映は保存成功後に行う。
3. 未照合・曖昧・期間外の項目は「保存成功件数」に含めない。原本または保留領域に保持し、照合後の再適用を可能にする。skipだけで原本を破棄しない。
4. 同じID・同じ内容の再送は何度でも同じ結果になる。同じevent IDで内容が異なる場合は上書きも無言の破棄もせず、両原本を残して競合として報告する。
5. Library snapshotからの欠落、空events、部分Export、未接続曲の除外は削除指示ではない。削除は別の明示操作とし、対象・確認・復旧手段を定義する。
6. Preference／Playlistの異なる編集値は無条件の後勝ちにしない。適用前の値と受信値を保持し、競合解決方法を契約で決める。未解決曲を除外したPlaylistで完全な既存Playlistを無言で上書きしない。
7. Exportのファイル保存成功と、相手での受領・保存成功を区別する。送信変更の解除・原本削除は受領確認と再送可能性を含む設計にする。Preview後の再編集は別世代として保持する。
8. Import前backup、世代保持、復元手順を設ける。期限・容量による原本削除は明示した運用方針で行い、未受領・未解決データを自動削除しない。
9. 項目ごとの排他的結果（適用／同一重複／未照合／期間外／競合／不正）と件数を記録する。受領確認は原本hash、契約revision、対象範囲と結果を特定し、単なるExport完了を受領扱いしない。

## 現在確認できる範囲と不足

- MyMusicはPlayback Events文書の全体検証、期間Preview、新規eventのtransaction保存、event IDによる重複排除を実装している。未解決曲や期間外eventは適用しない。Import確定時の全原本atomic保存・read-back確認をDI-001として実装した。未照合・期間外も原本に残すが、再適用UI・受領確認による再送管理は未実装。
- HomeStereoはMyMusic IDとローカルIDを分離し、Library snapshotから消えたlinkを在籍外として扱い、関連履歴を削除しない設計を記録している。未解決の外部Preferences／Eventsは結果へ残すがDBへ保存しない。原本の耐久保留は達成未確認。
- HomeStereoのPreference変更管理はExportファイル保存成功時に世代一致のdirtyを解除する。相手での適用を保証する仕組みにはなっていない。
- HomeStereoの既存連携文書には、LibraryのplayCountを全期間回数の正本とする記述と、Eventsを正本とする記述が併存する。集計snapshotと詳細eventの対象範囲を決めるまで単純加算しない。
- 両実装でのvalidation完全一致、同一event ID異内容の競合保全、未照合Playlist参照の耐久保留・部分適用、全項目の受領確認・復元は未検証。

## Playlist往復保全 Beta（2026-10-04）

- MyMusicはplaylistID付きJSONを同じIDで受け、同一内容は追加・書換えしない。IDなし旧形式は新規追加を維持する。既存複製の推測統合・削除は行わない。
- 異内容の更新は確認画面で明示する。MyMusicは更新確認後に保存し、HomeStereoは既存Import Previewで確認する。両側でPreview／確認時のPlaylist snapshotと確定時の値を比較し、再編集があれば中止する。
- 両側の適用前に原本bytesと更新前の全ローカルPlaylistをhash名でatomic保存しread-back確認する。MyMusicはApplication Support/MyMusic/PlaylistImportArchive、HomeStereoはSQLite directoryのPlaylistImportArchive。保管・保存失敗では既存Playlistを変更しない。自動削除しない。復元UI・原本の外部backup包含・原本とsnapshotを組にした受領記録は未実装。
- 未照合／種別非互換（MyMusic）／Track ID競合（HomeStereo）があるPlaylist文書は全体のImportを停止する。JSON Exportも未解決参照を除外せず停止する。これは破壊的な部分反映を止める段階的対策であり、未照合参照を保持して部分適用するDI-006の完成ではない。
- HomeStereoのタグ編集・filterは受信タグの保持に加え、同じ配列を編集してJSONへ出力する。MyMusic互換の20個／40文字と重複正規化を使う。JSONの不正なタグ・kind・IDを黙って初期値へ変更しない。MyMusic旧JSONでtags欠落の場合は既存タグを維持し、明示の空配列は確認後に削除として反映する。
- JSON wire v1とSQLite schema v14は変更しない。検索条件・ローカル説明・Artworkは共通JSONの対象外であり、MyMusicの既存Playlist更新ではローカル値を保持する。端末間の編集競合を自動mergeする仕組みは未実装。

## 互換性の完成条件

共通の小さなfixtureを両repositoryで管理し、両アプリのencode/decodeと意味の一致を確認する。必要な試験は正常往復、再Import、同一ID異内容、不正末尾項目、未接続→接続後再送、部分snapshot、空文書、競合編集、Preview後再編集、保存途中障害、backup復元。元eventのID・時刻・実聴秒・platform、Playlist順序・未解決参照が失われないことを検証する。

schema追加は受信側の対応を確認してから送信側で有効化する。未知fieldを拒否する受信側があるため、optional追加も無条件に後方互換とは扱わない。未知versionを受信しても、既存保存値と受信原本を保持する。

## 両Gitでの文書管理

MyMusic: `Documentation/DataInterchangeContract.md`
HomeStereo: `docs/data-interchange-contract.md`

同じ契約ID・revision・本文を両方に置く。これは別Gitのため自動で同期されない。片側だけの契約変更は未同期と報告し、両側のレビュー・fixture検証後にrevisionを揃える。内部実装の詳細は各repositoryの文書・コードを正とする。連携変更の開始時に両文書のrevisionと内容を比較し、不一致を推測で解消しない。

参照実装: MyMusicの`PlaybackEventImportService.swift`／`MusicDataExportService.swift`、HomeStereoの`MyMusicJSONContract.swift`／`MyMusicJSONService.swift`。HomeStereo詳細: `docs/mymusic-json-interchange.md`。
