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

main Window、MenuBarExtra、小型player Window、Queue Inspectorは同じStore instanceを参照し、別の再生状態を持たない。 各一覧からの最大100曲キュー生成はQueueStoreが利用可能TrackとTrackPreferencePersistingのGood値を読み、QueueCandidateSelectionで重複なしの重み付き抽選を行う。再生中のQueueItemは維持して待ち曲だけを置き換え、全クリアも再生と履歴sessionを終了しない。Queue曲、直接選択ファイル、Renderer polling結果は`QueueStore.nowPlaying`の`NowPlayingPresentation`へ集約し、画面と`MPNowPlayingInfoCenter`は同じ曲情報・状態・操作可否を使う。window frameはAppKit autosave、SidebarはSceneStorage、InspectorはAppStorageで復元する。drag payloadはTrack UUIDだけを含み、音源pathやfile dataを渡さない。

テーマは`HomeStereoTheme`が安定した保存IDと表示tokenを所有し、`appearance.theme`へ端末内保存する。Living Aurora／Pulse Neon／Blue Cosmosのtokenと世界観は、GitHub `maruyamamasaya/living-aurora-ui` commit `7138d4a5f8578cc1991c6a3add76fef30c11e345`の`docs/DESIGN_SYSTEM.md`と`src/styles/themes.css`を正本とする。`HomeStereoThemeRoot`がmain Window、Mini Player、MenuBarExtra、Settingsへ同じcolor scheme／tint／静的背景を注入し、`homeStereoThemeScreen`、`homeStereoThemeSidebar`、`homeStereoThemeBar`、`homeStereoThemeSurface`が各画面の半透明surfaceを共通化する。テーマ変更で再生Storeやnavigation identityを作り直さず、音源、SQLite、MyMusic JSON、Backup契約には含めない。既定の`system`は従来のmacOS外観を維持し、暗色4テーマだけdark schemeを指定する。Web固有のpointer反応や常時animationは移植せず、Reduce Transparencyまたはincreased contrastでは不透明なbaseだけにする。

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

SQLite schema v13はジャンル表示プリセットの編集済み正本と配列順を`genre_display_presets`へ保存する。`GenreDisplayPresetStore`がCRUD、並べ替え、同名merge Import、version 1 JSON Exportを担当し、`LibraryStore`は選択されたプリセットを`LibraryBrowserIndex`の複数ジャンルfilterへ渡す。曲・Album・Artistは同じ選択条件を共有し、collectionはgenreFilteredから通常曲だけを抽出して構築し、作業用BGM／ハイレゾを除外する。曲の検索は個々の曲、collectionの検索は名称と収録曲で判定する既存方式を維持する。ジャンル／sort変更時はbackground actorで3種類を同時更新し、sort済みbaseを再利用する。Mac AnalyticsやiPhoneのApplication Supportへ直接書き込まず、`mymusic.genre-display-presets` JSONだけを交換境界とする。

iPhone版MyMusicとの連携は、曲一覧、Playlist、Preferences、Playback Eventsを別々のversion付きJSON文書として扱う。`HomeStereoAppCore`内でCodable DTO、JSON非依存の交換model、Import／Export serviceを分離し、decode後に文書全体を検証してから交換modelへ変換する。Libraryの`relativePath`は両端末で選択した共通音楽ルート以下だけを表し、端末固有の絶対pathを含めない。保存済みMyMusic ID、NFCかつcase-sensitiveなrelative path＋size／duration、fingerprint、一意metadataの順に既存曲へMyMusic IDを関連付け、HomeStereoのTrack主キーは変更・再生成しない。SQLite schema v10は既存Track／Playlist主キーを維持したままCanonical Track ID、snapshot在籍状態、Canonical Playlist ID、Preferences、互換Playback Eventsを保存する。schema v14の`mymusic_preference_export_changes`はMacで変更した曲と世代tokenだけを保持し、Preferences Importで該当曲をMyMusic値へ揃えてdirtyを解除する。Preferences Exportはdirty曲だけを既存schema v2でPreviewし、ファイル保存成功後にPreview時点と一致するtokenだけを解除するため、Preview後の再編集を失わない。Playlist JSONはCanonical Track ID完全一致だけで曲を解決し、単一transactionで追加／更新する。Playlistの`kind`は`regular`／`work`を交換互換用metadataとして維持するが、UIは全Playlistを同じ画面に表示し、どの曲も複数Playlistへ所属できる。作業用曲の分類は再生時間ではなくgenreの「作業用BGM」だけを使う。ハイレゾはgenreの「ハイレゾ」、または44.1kHz・16bit以上を最低条件として24bit以上／48kHz超を満たす品質属性として扱う。通常の曲一覧はこの2分類を除外し、専用Sidebarでそれぞれを表示する。いずれもTrackを複製せず、Album／Artistとの関係を維持する。Import commit後は文書種別に応じて表示用Storeを再読込し、`MyMusicStatusStore`は全HomeStereo曲をlink、Preferences、Events、MyMusic Playlistと読み取り専用で結合して適用状況を表示する。詳細は[`docs/mymusic-json-interchange.md`](docs/mymusic-json-interchange.md)を正本とする。

## Protocols

- SSDP: UDP multicast `239.255.255.250:1900`
- Description: Renderer広告URLへのHTTP GET
- Media: `GET|HEAD /tracks/<UUID>?token=<token>`、単一byte Range
- Control: SOAP AVTransport／RenderingControl

外部package依存はない。App Sandboxはユーザー選択fileのread/writeとnetwork client/serverを許可する。write権限は標準保存panelで明示選択したJSON出力に使い、音源folder／音源本体は実装上読み取り専用として変更・削除しない。

sleep／wakeとnetwork path通知は`SystemEventMonitoring`境界に隔離する。復帰時はQueueと履歴を保存したまま、network復帰後に有限の指数backoffでSSDP再検索し、UDNで同一Rendererを選んで実状態を取得する。自動再生・自動音量変更は行わない。

各ローカル再生sessionはgeneration IDを持つ。pollingはawait境界ごとにgenerationを確認し、前曲の遅延応答を破棄する。完走は同一URI、直前の再生状態、終端近傍の位置を合わせて1回だけ確定する。操作commandは直列化し、状態取得SOAPだけtimeout時に1回再試行する。診断Exportはaction、結果、HTTP／UPnP codeだけを保持し、音源path、機器IP、tokenを含めない。

## 音楽特徴量の独立した保存境界

`TrackFeatureView` → `TrackFeatureStore` → `FeatureCodec`／索引化した`FeatureResolver` → `FeatureRepository` actor → Application Supportの`HomeStereo/track-features.json`（archive v1）。既存SQLiteからTrackとMyMusic linkをread-only取得し、特徴量はSQLite／音源から独立して保存する。未照合は破棄せず再照合できる。外部契約はMyMusic snapshot v1とAnalyzer schema v1のまま維持し、両アプリの内部Model・DBを共有しない。詳細と書き出しの用途別制約は[音楽特徴量](docs/track-features.md)を正本とする。

特徴量の実行は`FeatureAnalysisPlanner`で現在Libraryと既存結果から対象を索引化し、`FeatureAnalysisService`がversion 1 JSON jobを独立`HomeStereoAnalyzer.app`へ渡す。専用Python runtime／model／cacheは別Application Supportに置き、本体のsandbox entitlementを広げず、隣接MyMusic repositoryを参照しない。音量解析とsemanticを独立cacheし、結果とprogressをfile経由で返す。`TrackFeatureStore`から検証済み曲別音量値を`RendererPlaybackStore`へ渡し、`SystemAudioPlayer`だけがAVPlayer.volumeを変更する。詳細なprofileと保存境界は[Analyzer](analyzer/README.md)。

解析workerは成功した曲をcompleted.jsonlへ1行ずつ耐久保存する。FeatureRunFilesは完全な行だけを検証し、異常終了時の返却とTrackFeatureStore.loadでの復旧に使用する。復旧時も既存FeatureRepositoryのmerge境界を使い、原本journalは保持する。

Sandbox本体からの解析job受け渡しはNSWorkspace.openのdocument URLを使う。補助アプリのAppKit delegateがopen eventを受け、request pathをPythonへ渡す。command-line arguments指定だけの起動は使用しない。

内部解析requestはconcurrency（2／3／6）を持ち、workerが上限付きthread poolで曲単位に実行する。task別SQLite connectionとthread別ONNX engineを使い、progress／results／journalの書き込みは集約側のみが行う。同時解析設定は端末内UserDefaultsだけに保存し、MyMusic交換JSONを変更しない。

Albumの表示identityはtitleのみで構成し、Track Artist／Album Artistの差では分割しない。LibraryBrowserIndexとArtist画面のAlbum groupingは同じtitle基準を使う。genre・通常曲filter後のmembershipから共通Album Artistの表示値を求めるが、元Track metadata／永続化IDは変更しない。

## ページ操作と分析表示

メインウィンドウ右上toolbarはパネル開閉を中心とし、各ページの実行操作は本文ヘッダー／関連セクションへ置く。Backup、Library、Album、Artist、Listening、Playlist、Genre Preset、MyMusic Status、Renderer、Now Playingの操作はページ内へ配置する。

AnalyticsSnapshotのrecentEventsは直近500件を維持し、historyDaysは全詳細イベントを保持する。カレンダーは日／週の半開区間で表示し、評価は−10〜＋10と未設定を別々に選択する。完走・スキップ専用ページは詳細イベント由来の率と分母を表示する。特徴量のVoice分類はFeatureVoiceCategoryのスコア比較による表示上の目安で、判定保留／未解析を分離する。

特徴量の緑チェックはローカル曲照合とCanonical ID照合を分ける。Canonical IDはMyMusic linkが両方向で一意のときだけ一致表示する。MyMusic連携はTrackFeatureStoreの既存JSON出力を再利用する。JSON加工ツールは特徴量snapshot／Analyzer文書をFeatureCodecで読み込み・保存時検証し、編集結果をファイルだけへ書く。SQLiteや特徴量archiveへ自動適用しない。

RendererPlaybackStoreは初期状態でこのMacを選び、曲一覧を開く。RecoveryStoreのスリープ・ネットワーク復帰処理は維持し、起動時に自動再生はしない。MainNowPlayingBarは横幅に応じて既存のregular／compact layoutを使い、Good／Badは両layout共通の再生操作群へ置く。PlaybackViewはArtworkとmetadataを中央配置し、最大820pxの内容幅を保つ。特徴量・JSON編集のpaneは横幅約960pxのウィンドウを想定して最小幅を抑える。
