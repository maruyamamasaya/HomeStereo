# Architecture

## System Overview

```text
SwiftUI View
  -> LibraryStore -> LibraryBrowserIndex / ArtworkCache
                  -> FolderAccessService / LibraryService / SQLiteLibraryRepository
  -> QueueStore -> SQLiteLibraryRepository
  -> PlaylistStore -> SQLiteLibraryRepository / PlaylistFileService
  -> ListeningStore -> QueueStore callbacks / SQLiteLibraryRepository
  -> AnalyticsStore -> AnalyticsService -> SQLiteLibraryRepository
  -> MyMusicTransferStore / MyMusicStatusStore -> SQLiteLibraryRepository
  -> RecoveryStore -> MacSystemEventMonitor / RendererPlaybackStore
  -> RendererPlaybackStore
    -> SystemAudioPlayer -> AVPlayer -> macOS system audio output
    -> RendererDiscoveryService -> SSDP M-SEARCH
    -> DeviceDescriptionService -> URLSession / XMLParser
    -> LocalMediaHTTPServerFactory -> Network.framework -> selected file
    -> UPnPRendererController -> SOAP AVTransport / RenderingControl
    -> MacPlaybackActivityManager -> idle sleep assertion
```

「このMac」出力ではAVPlayerがmacOSで選択中のサウンド出力へ再生し、音量制御はmacOSへ委ねる。通常の単体DLNA出力ではRendererがtoken付きLAN URLから音源を取得する。Sonyステレオ出力では、AVFoundationで選択曲をLEFT／RIGHTのPCM WAVへ分離し、SRS-HG10とSRS-HG1向けに独立したtoken付きLAN URLを生成する。選曲時とQueue再生中の次曲をutility優先度で先行変換し、source path／size／更新日時／出力設定が同じ変換結果を最大2件再利用する。2つのUPnP controllerがSetURI／Play／Stop／Seek／Volumeを各Rendererへ並行送信する。左右割り当ては実機のfriendly nameに合わせ、HG10（L soundbar）=LEFT／HG1（R soundbar）=RIGHTとしてUIへ明示する。

ステレオ出力品質は元sample rate／24-bit PCMのハイレゾ維持と、48kHz／16-bit PCMの安定優先を選べる。再生前に両controllerへ問い合わせて通信を確立し、SetURI後に両方のTrackURI一致を確認してからPlayを並行送信する。先読みが未完了の直接選曲では安全なWAV生成完了を待つ。Sony独自MultiChannelによるネイティブSTEREOはHG10／HG1間で実機拒否されたため、自動fallbackや識別子偽装を行わない。

main Window、MenuBarExtra、小型player Window、Queue Inspectorは同じStore instanceを参照し、別の再生状態を持たない。Queue曲、直接選択ファイル、Renderer polling結果は`QueueStore.nowPlaying`の`NowPlayingPresentation`へ集約し、画面と`MPNowPlayingInfoCenter`は同じ曲情報・状態・操作可否を使う。window frameはAppKit autosave、SidebarはSceneStorage、InspectorはAppStorageで復元する。drag payloadはTrack UUIDだけを含み、音源pathやfile dataを渡さない。

テーマは`HomeStereoTheme`が安定した保存IDと表示tokenを所有し、`appearance.theme`へ端末内保存する。Living Aurora／Pulse Neon／Blue Cosmosのtokenと世界観は、GitHub `maruyamamasaya/living-aurora-ui` commit `7138d4a5f8578cc1991c6a3add76fef30c11e345`の`docs/DESIGN_SYSTEM.md`と`src/styles/themes.css`を正本とする。`HomeStereoThemeRoot`がmain Window、Mini Player、MenuBarExtra、Settingsへ同じcolor scheme／tint／静的背景を注入する。テーマ変更で再生Storeやnavigation identityを作り直さず、音源、SQLite、MyMusic JSON、Backup契約には含めない。既定の`system`は従来のmacOS外観を維持し、暗色4テーマだけdark schemeを指定する。Web固有のpointer反応や常時animationは移植せず、Reduce Transparencyまたはincreased contrastでは不透明なbaseだけにする。

## Targets

- `HomeStereoDLNAApp`: SwiftUI entry、NavigationSplitView、commands
- `HomeStereoDLNAAppCore`: DLNA／Library observable Store、protocol、production service adapter
- `HomeStereoAppCore`: Library model、folder access、AVFoundation scan、SQLite repository
- `HomeStereoKit`: SSDP、Device XML、HTTP server、SOAP primitive
- `HomeStereoCLI`: 既知IP向けの旧実機診断入口
- `SonyStereoBridgeAudio`: BlackHole等のCore Audio device probe、AUHAL capture、共通timelineからのL/R固定長WAV segment生成
- `SonyStereoBridgeCLI`: MyMusic／macOS GUIから独立した2 Renderer PoC。UPnP probe、固定WAV再生とCore Audio capture commandを担当する

旧ローカル再生UIは現行targetに含めない。現行Appの「このMac」出力は`HomeStereoDLNAAppCore`の再生境界へ統合し、Queue、履歴、Now PlayingをDLNA出力と共有する。

Sony Stereo Bridgeの段階構成とPhase gateは[`docs/sony-stereo-bridge/architecture.md`](docs/sony-stereo-bridge/architecture.md)を正本とする。Phase 4は固定長capture segmentまでで、chunked／終端なしstreamは含めない。

## Data and Security

Library index、Queue snapshot（Track ID、順序、現在位置、repeat／shuffle）、Playlist（順序付きTrack ID参照）、Favorite、再生イベントをApplication SupportのSQLiteへ保存する。関連データは音源を複製せず、missing Track ID参照も保持する。選択ファイルはsecurity-scoped read-only accessで直接読む。HTTP URLはopaque UUIDとrandom tokenを使い、固定LAN addressだけへbindする。serverはファイル／Renderer変更とapp終了時に停止する。

SQLite schema v6はTrackにmacOS file resource identifierのopaque bytesを任意保存する。scanのIdentity判定は同一folder内で、path完全一致、resource identifierの一意一致、file size・duration・音源仕様・metadataの保守的一意一致の順で行う。曖昧なら新規Trackとし、判定理由をscan noticeへ残す。path変更と既存Track IDの確定はscan成功後の単一transaction内で行い、Playlist、Favorite、履歴、Queueの参照は書き換えない。

SQLite schema v8はTrackへ音声トラックの推定bit rateを追加する。metadata schema v3では既存曲も次回scan時に再解析し、genre、release year、bit rateを更新する。

SQLite schema v12はローカル分析用の詳細再生event、Track／日別／入口別集計、Good／Bad評価に加え、MyMusic Library JSONの集計済み`playCount` snapshotを追加する。`ListeningStore`は実際の再生開始・位置・終了という事実だけを受け、`MyMusicPlaybackSession`と共通Policyでpause／seekを除いた実聴時間、完走、Skipを確定する。Repositoryはraw eventと集計を同一transactionで保存し、event IDの重複時は集計しない。履歴eventはTrackへのcascade foreign keyを持たず、ライブラリから曲が消えても未解決履歴として保持する。MyMusic snapshotがある場合、`AnalyticsService`は総再生回数・曲別回数・ランキングにその集計値を使い、期間別回数・再生時間・完走／Skip率は詳細eventから算出する。`AnalyticsStore`は読み取り専用snapshotをbackground taskで構築し、revision変更時に古いtaskをcancelして完成値だけをMainActorへ公開する。Preference、詳細履歴、MyMusic集計の削除境界を分ける。詳細は[`docs/playback-analytics.md`](docs/playback-analytics.md)を正本とする。

SQLite schema v13はジャンル表示プリセットの編集済み正本と配列順を`genre_display_presets`へ保存する。`GenreDisplayPresetStore`がCRUD、並べ替え、同名merge Import、version 1 JSON Exportを担当し、`LibraryStore`は選択されたプリセットを`LibraryBrowserIndex`の複数ジャンルfilterへ渡す。Mac AnalyticsやiPhoneのApplication Supportへ直接書き込まず、`mymusic.genre-display-presets` JSONだけを交換境界とする。

iPhone版MyMusicとの連携は、曲一覧、Playlist、Preferences、Playback Eventsを別々のversion付きJSON文書として扱う。`HomeStereoAppCore`内でCodable DTO、JSON非依存の交換model、Import／Export serviceを分離し、decode後に文書全体を検証してから交換modelへ変換する。Libraryの`relativePath`は両端末で選択した共通音楽ルート以下だけを表し、端末固有の絶対pathを含めない。保存済みMyMusic ID、NFCかつcase-sensitiveなrelative path＋size／duration、fingerprint、一意metadataの順に既存曲へMyMusic IDを関連付け、HomeStereoのTrack主キーは変更・再生成しない。SQLite schema v10は既存Track／Playlist主キーを維持したままCanonical Track ID、snapshot在籍状態、Canonical Playlist ID、Preferences、互換Playback Eventsを保存する。Playlist JSONはCanonical Track ID完全一致だけで曲を解決し、単一transactionで追加／更新する。Playlistの`kind`は`regular`／`work`を維持し、UIとローカル追加先を分離する。作業用曲の分類は再生時間ではなくgenreの「作業用BGM」だけを使う。Import commit後は文書種別に応じて表示用Storeを再読込し、`MyMusicStatusStore`は全HomeStereo曲をlink、Preferences、Events、MyMusic Playlistと読み取り専用で結合して適用状況を表示する。詳細は[`docs/mymusic-json-interchange.md`](docs/mymusic-json-interchange.md)を正本とする。

## Protocols

- SSDP: UDP multicast `239.255.255.250:1900`
- Description: Renderer広告URLへのHTTP GET
- Media: `GET|HEAD /tracks/<UUID>?token=<token>`、単一byte Range
- Control: SOAP AVTransport／RenderingControl

外部package依存はない。App Sandboxはfile read-only、network client/serverを許可する。

sleep／wakeとnetwork path通知は`SystemEventMonitoring`境界に隔離する。復帰時はQueueと履歴を保存したまま、network復帰後に有限の指数backoffでSSDP再検索し、UDNで同一Rendererを選んで実状態を取得する。自動再生・自動音量変更は行わない。

各ローカル再生sessionはgeneration IDを持つ。pollingはawait境界ごとにgenerationを確認し、前曲の遅延応答を破棄する。完走は同一URI、直前の再生状態、終端近傍の位置を合わせて1回だけ確定する。操作commandは直列化し、状態取得SOAPだけtimeout時に1回再試行する。診断Exportはaction、結果、HTTP／UPnP codeだけを保持し、音源path、機器IP、tokenを含めない。
