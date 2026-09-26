# Architecture

## System Overview

```text
SwiftUI View
  -> LibraryStore -> LibraryBrowserIndex / ArtworkCache
                  -> FolderAccessService / LibraryService / SQLiteLibraryRepository
  -> QueueStore -> SQLiteLibraryRepository
  -> PlaylistStore -> SQLiteLibraryRepository / PlaylistFileService
  -> ListeningStore -> QueueStore callbacks / SQLiteLibraryRepository
  -> RecoveryStore -> MacSystemEventMonitor / RendererPlaybackStore
  -> RendererPlaybackStore
    -> RendererDiscoveryService -> SSDP M-SEARCH
    -> DeviceDescriptionService -> URLSession / XMLParser
    -> LocalMediaHTTPServerFactory -> Network.framework -> selected file
    -> UPnPRendererController -> SOAP AVTransport / RenderingControl
    -> MacPlaybackActivityManager -> idle sleep assertion
```

通常の単体出力ではRendererがtoken付きLAN URLから音源を取得する。Sonyステレオ出力では、AVFoundationで選択曲をLEFT／RIGHTのPCM WAVへ分離し、SRS-HG10とSRS-HG1向けに独立したtoken付きLAN URLを生成する。2つのUPnP controllerがSetURI／Play／Stop／Seek／Volumeを各Rendererへ並行送信する。左右割り当ては実機のfriendly nameに合わせ、HG10（L soundbar）=LEFT／HG1（R soundbar）=RIGHTとしてUIへ明示する。

ステレオ出力品質は元sample rate／24-bit PCMのハイレゾ維持と、48kHz／16-bit PCMの安定優先を選べる。再生前に両controllerへ問い合わせて通信を確立し、SetURI後に両方のTrackURI一致を確認してからPlayを並行送信する。Sony独自MultiChannelによるネイティブSTEREOはHG10／HG1間で実機拒否されたため、自動fallbackや識別子偽装を行わない。

main Window、MenuBarExtra、小型player Window、Queue Inspectorは同じStore instanceを参照し、別の再生状態を持たない。Queue曲、直接選択ファイル、Renderer polling結果は`QueueStore.nowPlaying`の`NowPlayingPresentation`へ集約し、画面と`MPNowPlayingInfoCenter`は同じ曲情報・状態・操作可否を使う。window frameはAppKit autosave、SidebarはSceneStorage、InspectorはAppStorageで復元する。drag payloadはTrack UUIDだけを含み、音源pathやfile dataを渡さない。

## Targets

- `HomeStereoDLNAApp`: SwiftUI entry、NavigationSplitView、commands
- `HomeStereoDLNAAppCore`: DLNA／Library observable Store、protocol、production service adapter
- `HomeStereoAppCore`: Library model、folder access、AVFoundation scan、SQLite repository
- `HomeStereoKit`: SSDP、Device XML、HTTP server、SOAP primitive
- `HomeStereoCLI`: 既知IP向けの旧実機診断入口
- `SonyStereoBridgeAudio`: BlackHole等のCore Audio device probe、AUHAL capture、共通timelineからのL/R固定長WAV segment生成
- `SonyStereoBridgeCLI`: MyMusic／macOS GUIから独立した2 Renderer PoC。UPnP probe、固定WAV再生とCore Audio capture commandを担当する

旧ローカル再生UIは現行targetに含めない。`HomeStereoAppCore`のLibrary関連sourceだけを現行Appから再利用する。

Sony Stereo Bridgeの段階構成とPhase gateは[`docs/sony-stereo-bridge/architecture.md`](docs/sony-stereo-bridge/architecture.md)を正本とする。Phase 4は固定長capture segmentまでで、chunked／終端なしstreamは含めない。

## Data and Security

Library index、Queue snapshot（Track ID、順序、現在位置、repeat／shuffle）、Playlist（順序付きTrack ID参照）、Favorite、再生イベントをApplication SupportのSQLiteへ保存する。関連データは音源を複製せず、missing Track ID参照も保持する。選択ファイルはsecurity-scoped read-only accessで直接読む。HTTP URLはopaque UUIDとrandom tokenを使い、固定LAN addressだけへbindする。serverはファイル／Renderer変更とapp終了時に停止する。

SQLite schema v6はTrackにmacOS file resource identifierのopaque bytesを任意保存する。scanのIdentity判定は同一folder内で、path完全一致、resource identifierの一意一致、file size・duration・音源仕様・metadataの保守的一意一致の順で行う。曖昧なら新規Trackとし、判定理由をscan noticeへ残す。path変更と既存Track IDの確定はscan成功後の単一transaction内で行い、Playlist、Favorite、履歴、Queueの参照は書き換えない。

SQLite schema v8はTrackへ音声トラックの推定bit rateを追加する。metadata schema v3では既存曲も次回scan時に再解析し、genre、release year、bit rateを更新する。

iPhone版MyMusicとの将来連携は、曲一覧、Preferences、Playback Eventsを別々のversion付きJSON文書として扱う。`HomeStereoAppCore`内でCodable DTO、JSON非依存の交換model、Import／Export serviceを分離し、decode後に文書全体を検証してから交換modelへ変換する。SQLite schema v9は既存Track主キーを維持したまま外部Track ID対応、Preferences、互換Playback Eventsを独立tableへ保存する。HomeStereoの実再生はRenderer位置差分を追う一時的なSessionへ集約し、確定時だけRepository経由でappendする。未連携eventはHomeStereo Track IDで保持し、export時にlinkを遅延解決する。詳細は[`docs/mymusic-json-interchange.md`](docs/mymusic-json-interchange.md)を正本とする。

## Protocols

- SSDP: UDP multicast `239.255.255.250:1900`
- Description: Renderer広告URLへのHTTP GET
- Media: `GET|HEAD /tracks/<UUID>?token=<token>`、単一byte Range
- Control: SOAP AVTransport／RenderingControl

外部package依存はない。App Sandboxはfile read-only、network client/serverを許可する。

sleep／wakeとnetwork path通知は`SystemEventMonitoring`境界に隔離する。復帰時はQueueと履歴を保存したまま、network復帰後に有限の指数backoffでSSDP再検索し、UDNで同一Rendererを選んで実状態を取得する。自動再生・自動音量変更は行わない。

各ローカル再生sessionはgeneration IDを持つ。pollingはawait境界ごとにgenerationを確認し、前曲の遅延応答を破棄する。完走は同一URI、直前の再生状態、終端近傍の位置を合わせて1回だけ確定する。操作commandは直列化し、状態取得SOAPだけtimeout時に1回再試行する。診断Exportはaction、結果、HTTP／UPnP codeだけを保持し、音源path、機器IP、tokenを含めない。
