# Code Map

検索を開始するための索引であり、全ファイル一覧ではない。概念から候補を得た後、下記のsymbol/文字列でexact searchし、referenceとtestを確認する。

## App UI and Composition

Primary paths: `Sources/HomeStereoApp/`  
Search keywords: `HomeStereoApp`, `ContentView`, `PlayerBar`, `AVRoutePickerView`, `keyboardShortcut`  
Key entry points: `HomeStereoApp.body`, `ContentView.body`, `PlayerBar.body`  
Related tests: UI testなし。state/behaviorは`Tests/HomeStereoAppCoreTests/`

## App State and Coordination

Primary paths: `Sources/HomeStereoAppCore/PlaybackStore.swift`, `Protocols.swift`, `Track.swift`  
Search keywords: `PlaybackStore`, `restoreLibrary`, `chooseFolder`, `selectTrack`, `UserFacingError`  
Key entry points: `PlaybackStore.init`, `restoreLibrary`, `selectTrack`  
Related tests: `Tests/HomeStereoAppCoreTests/PlaybackStoreTests.swift`

## Folder Access and Persistence

Primary paths: `Sources/HomeStereoAppCore/FolderAccessService.swift`, `HomeStereoApp.entitlements`  
Search keywords: `musicFolderBookmark`, `bookmarkData`, `securityScoped`, `NSOpenPanel`, `user-selected.read-only`  
Key entry points: `FolderAccessService.chooseFolder`, `saveBookmark`, `restoreFolder`  
Related tests: `Tests/HomeStereoAppCoreTests/FolderAccessServiceTests.swift`

## Library Scan and Metadata

Primary paths: `Sources/HomeStereoAppCore/LibraryService.swift`, `Track.swift`  
Search keywords: `LibraryService`, `supportedExtensions`, `candidateURLs`, `AVURLAsset`, `commonMetadata`  
Key entry points: `LibraryService.scan`, `LibraryService.supports`  
Related tests: `Tests/HomeStereoAppCoreTests/LibraryServiceTests.swift`

## Local Playback and Queue

Primary paths: `Sources/HomeStereoAppCore/AudioPlaybackService.swift`, `PlaybackQueue.swift`  
Search keywords: `AVQueuePlayer`, `AVPlayerItemDidPlayToEndTime`, `PlaybackQueue`, `routePickerPlayer`  
Key entry points: `AudioPlaybackService.load`, `play`, `next`, `PlaybackQueue.moveNext`  
Related tests: `AudioPlaybackServiceTests.swift`, `PlaybackQueueTests.swift` under `Tests/HomeStereoAppCoreTests/`

## DLNA CLI Orchestration

Primary paths: `Sources/HomeStereoCLI/main.swift`, `docs/dlna-playback.md`  
Search keywords: `HomeStereoCommand`, `--renderer`, `--file`, `[DLNA]`, `SetAVTransportURI`  
Key entry points: `HomeStereoCommand.main`, `Options.parse`  
Related tests: orchestration/実機testなし。primitiveは`Tests/HomeStereoKitTests/`

## DLNA Discovery and Device Description

Primary paths: `Sources/HomeStereoKit/Discovery.swift`, `DeviceDescriptionParser.swift`, `Models.swift`  
Search keywords: `SSDPDiscovery`, `239.255.255.250`, `DeviceDescriptionLoader`, `MediaRenderer`, `AVTransport`  
Key entry points: `SSDPDiscovery.deviceDescriptionURL`, `DeviceDescriptionLoader.load`, `DeviceDescriptionParser.parse`  
Related tests: `parsesRendererDescriptionAndResolvesRelativeServiceURLs` in `Tests/HomeStereoKitTests/HomeStereoKitTests.swift`

## DLNA HTTP and SOAP

Primary paths: `Sources/HomeStereoKit/TrackHTTPServer.swift`, `HTTPTypes.swift`, `SOAP.swift`  
Search keywords: `/tracks/`, `TrackHTTPServer`, `ByteRange`, `AudioMIMEType`, `SOAPRequestBuilder`, `UPnPController`, `SOAPACTION`  
Key entry points: `TrackHTTPServer.start`, `ByteRange.parse`, `SOAPRequestBuilder.envelope`, `UPnPController.setAVTransportURI`  
Related tests: URL/MIME/range/SOAP tests in `Tests/HomeStereoKitTests/HomeStereoKitTests.swift`

## Build and Configuration

Primary paths: `Package.swift`, `HomeStereo.xcodeproj/project.pbxproj`, `HomeStereoApp.entitlements`, `scripts/verify.sh`  
Search keywords: `executableTarget`, `PRODUCT_BUNDLE_IDENTIFIER`, `MACOSX_DEPLOYMENT_TARGET`, `CODE_SIGN`, `ENABLE_APP_SANDBOX`  
Key entry points: SwiftPM target declarations、Xcode `HomeStereo` target、`./scripts/verify.sh`  
Related tests: `swift test`とXcode Debug build。詳細は`TESTING.md`
