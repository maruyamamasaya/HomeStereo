# Architecture

## System Overview

同一リポジトリに、現在のmacOS Appと旧DLNA CLIの2経路がある。両者はbuild targetと実行経路が分離され、Appは`HomeStereoKit`へ依存しない。

```text
macOS App
SwiftUI View -> PlaybackStore -> AppCore services -> File system / UserDefaults / AVFoundation
                                                        |
                                                        +-> AVRoutePickerView -> macOS output routing

DLNA CLI (separate)
CLI -> SSDP/device XML -> local HTTP track server -> renderer
                       -> SOAP AVTransport ---------> renderer
```

## Technology Stack

- Swift 6 package manifest、macOS 14+
- SwiftUI、Observation、AppKit
- AVFoundation、AVKit
- Foundation、Network、FoundationXML
- XCTest（AppCore）とSwift Testing（Kit）
- 外部package依存なし

## Directory Structure

```text
Sources/HomeStereoApp/       macOS App entryとView
Sources/HomeStereoAppCore/   状態、model、folder/library/playback service
Sources/HomeStereoCLI/       DLNA検証CLI entry
Sources/HomeStereoKit/       SSDP、XML、HTTP server、SOAP
Tests/                       AppCore/Kitの自動テスト
docs/                        DLNA実機検証資料
decisions/                   設計判断
sessions/                    AI作業記録
scripts/                     標準検証入口
```

## Main Components

- `HomeStereoApp`: production serviceを組み立て、windowとcommandsを定義する。
- `ContentView` / `PlayerBar`: 表示とユーザー操作。OS/APIの主要処理は直接持たない。
- `PlaybackStore`: View向け状態とfolder scan/playback操作の調停点。
- `FolderAccessService`: `NSOpenPanel`、security-scoped bookmark、UserDefaults境界。
- `LibraryService`: ファイル列挙とAVFoundation metadata/readability判定。
- `AudioPlaybackService`: `AVQueuePlayer`と`PlaybackQueue`を所有する。
- `HomeStereoKit`: DLNA向け探索、XML parsing、track HTTP配信、SOAP操作。

## Data Flow

Appでは、folder選択またはbookmark復元後にscopeを開始し、`LibraryService`が`Track`を生成する。曲選択は`PlaybackStore`から`AudioPlaybackService`へqueue全体とindexを渡す。再生状態callbackがStoreを更新し、ViewへObservationで反映される。

DLNA CLIでは、既知renderer IPからSSDPでDescription URLを得てXMLを解析する。Mac上の1ファイルをtoken付きURLでHTTP公開し、そのURLをSOAP `SetAVTransportURI`でrendererへ渡す。

## API Structure

サーバー側Web APIはない。DLNA経路だけが次のネットワークprotocolを利用する。

- SSDP M-SEARCH: UDP multicast `239.255.255.250:1900`
- Device Description: rendererのHTTP URL
- track配信: `GET|HEAD /tracks/<UUID>?token=<token>`、単一byte range対応
- UPnP SOAP: rendererが広告したAVTransport/RenderingControl URL

## Database

DBはない。Appの唯一の永続データは、標準`UserDefaults`の`musicFolderBookmark`に保存するsecurity-scoped bookmarkである。音源自体はコピー・変更しない。

## Authentication

ユーザー認証はない。ローカルHTTP track URLはランダムtokenで限定されるが、アカウント認証機構ではない。

## External Services

クラウドサービスや第三者SDKはない。外部接点はApple framework、ローカルファイルシステム、ユーザーが選ぶ音声出力先、DLNA CLI利用時のLAN内rendererのみ。

## Deployment

Appは`HomeStereo.xcodeproj`の`HomeStereo` schemeでbuildする。Bundle IDは`jp.local.HomeStereo.Beta`、versionは0.1、ad-hoc署名、Hardened RuntimeとApp Sandboxが有効。配布・notarization・CI設定はない。Swift Packageはlibrary、CLI、App executableとtest targetを定義する。

## Important Dependencies

外部依存はない。特に重要な境界は`AudioPlaybackServicing`、`LibraryScanning`、`FolderAccessServicing`、`BookmarkStoring`で、AppCore testはfake/in-memory実装へ差し替える。
