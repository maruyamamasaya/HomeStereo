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

Rendererはtoken付きLAN URLから音源を取得し、Sony側がWireless StereoのL/Rへ振り分ける。MacからL/Rへ個別streamを送らない。

main Window、MenuBarExtra、小型player Window、Queue Inspectorは同じStore instanceを参照し、別の再生状態を持たない。window frameはAppKit autosave、SidebarはSceneStorage、InspectorはAppStorageで復元する。drag payloadはTrack UUIDだけを含み、音源pathやfile dataを渡さない。

## Targets

- `HomeStereoDLNAApp`: SwiftUI entry、NavigationSplitView、commands
- `HomeStereoDLNAAppCore`: DLNA／Library observable Store、protocol、production service adapter
- `HomeStereoAppCore`: Library model、folder access、AVFoundation scan、SQLite repository
- `HomeStereoKit`: SSDP、Device XML、HTTP server、SOAP primitive
- `HomeStereoCLI`: 既知IP向けの旧実機診断入口
- `SonyStereoBridgeCLI`: MyMusic／macOS GUIから独立した2 Renderer固定WAV PoC。SSDP probe、SCPD action収集、ConnectionManager format収集、単一／左右別ファイル再生を担当する

旧ローカル再生UIは現行targetに含めない。`HomeStereoAppCore`のLibrary関連sourceだけを現行Appから再利用する。

Sony Stereo Bridgeの段階構成とPhase gateは[`docs/sony-stereo-bridge/architecture.md`](docs/sony-stereo-bridge/architecture.md)を正本とする。現段階では固定ファイルだけで、ライブ入力とWeb UIは含めない。

## Data and Security

Library index、Queue snapshot（Track ID、順序、現在位置、repeat／shuffle）、Playlist（順序付きTrack ID参照）、Favorite、再生イベントをApplication SupportのSQLiteへ保存する。関連データは音源を複製せず、missing Track ID参照も保持する。選択ファイルはsecurity-scoped read-only accessで直接読む。HTTP URLはopaque UUIDとrandom tokenを使い、固定LAN addressだけへbindする。serverはファイル／Renderer変更とapp終了時に停止する。

SQLite schema v6はTrackにmacOS file resource identifierのopaque bytesを任意保存する。scanのIdentity判定は同一folder内で、path完全一致、resource identifierの一意一致、file size・duration・音源仕様・metadataの保守的一意一致の順で行う。曖昧なら新規Trackとし、判定理由をscan noticeへ残す。path変更と既存Track IDの確定はscan成功後の単一transaction内で行い、Playlist、Favorite、履歴、Queueの参照は書き換えない。

## Protocols

- SSDP: UDP multicast `239.255.255.250:1900`
- Description: Renderer広告URLへのHTTP GET
- Media: `GET|HEAD /tracks/<UUID>?token=<token>`、単一byte Range
- Control: SOAP AVTransport／RenderingControl

外部package依存はない。App Sandboxはfile read-only、network client/serverを許可する。

sleep／wakeとnetwork path通知は`SystemEventMonitoring`境界に隔離する。復帰時はQueueと履歴を保存したまま、network復帰後に有限の指数backoffでSSDP再検索し、UDNで同一Rendererを選んで実状態を取得する。自動再生・自動音量変更は行わない。

各ローカル再生sessionはgeneration IDを持つ。pollingはawait境界ごとにgenerationを確認し、前曲の遅延応答を破棄する。完走は同一URI、直前の再生状態、終端近傍の位置を合わせて1回だけ確定する。操作commandは直列化し、状態取得SOAPだけtimeout時に1回再試行する。診断Exportはaction、結果、HTTP／UPnP codeだけを保持し、音源path、機器IP、tokenを含めない。
