# Code Map

## DLNA App UI

Primary: `Sources/HomeStereoDLNAApp/`
Keywords: `HomeStereoDLNAApp`, `DLNAContentView`, `DevicesView`, `PlaybackView`, `keyboardShortcut`

## State and Services

Primary: `Sources/HomeStereoDLNAAppCore/`
Keywords: `RendererPlaybackStore`, `RendererDiscovering`, `MediaServerCreating`, `RendererControlling`, `PlaybackDiagnostic`
Tests: `Tests/HomeStereoDLNAAppCoreTests/RendererPlaybackStoreTests.swift`

## Library Folder, Scan, and Persistence

Primary: `Sources/HomeStereoAppCore/Track.swift`, `FolderAccessService.swift`, `LibraryService.swift`, `LibraryRepository.swift`, `Sources/HomeStereoDLNAAppCore/LibraryStore.swift`
Keywords: `LibraryFolder`, `ScanProgress`, `normalizedRelativePath`, `TrackIdentityResolver`, `fileResourceIdentifier`, `SQLiteLibraryRepository`, `prepareTrack`
Tests: `Tests/HomeStereoAppCoreTests/LibraryPersistenceTests.swift`

## Library Browsing and Artwork

Primary: `Sources/HomeStereoAppCore/LibraryBrowser.swift`, `Sources/HomeStereoDLNAAppCore/ArtworkCache.swift`, `Sources/HomeStereoDLNAApp/LibraryViews.swift`
Keywords: `LibraryBrowserIndex`, `LibraryAlbum.ID`, `LibraryArtist`, `LibrarySort`, `CachedArtwork`
Tests: `Tests/HomeStereoAppCoreTests/LibraryBrowserTests.swift`

## Queue and Continuous Playback

Primary: `Sources/HomeStereoAppCore/QueueModels.swift`, `Sources/HomeStereoDLNAAppCore/QueueStore.swift`, `RendererPlaybackStore.swift`, `Sources/HomeStereoDLNAApp/QueueView.swift`
Keywords: `QueueSnapshot`, `playNow`, `playNext`, `advanceAfterCompletion`, `onTrackFinished`, `QueueRepeatMode`
Tests: `Tests/HomeStereoDLNAAppCoreTests/RendererPlaybackStoreTests.swift`

## Playlists and M3U8

Primary: `Sources/HomeStereoAppCore/PlaylistModels.swift`, `Sources/HomeStereoDLNAAppCore/PlaylistStore.swift`, `Sources/HomeStereoDLNAApp/PlaylistsView.swift`
Keywords: `Playlist`, `PlaylistItem`, `savePlaylist`, `parseM3U8`, `M3U8ImportResult`
Tests: `Tests/HomeStereoAppCoreTests/PlaylistPersistenceTests.swift`, `Tests/HomeStereoDLNAAppCoreTests/RendererPlaybackStoreTests.swift`

## Favorites and Playback History

Primary: `Sources/HomeStereoAppCore/ListeningModels.swift`, `Sources/HomeStereoDLNAAppCore/ListeningStore.swift`, `Sources/HomeStereoDLNAApp/ListeningView.swift`
Keywords: `Favorite`, `PlaybackEvent`, `playedSeconds`, `onTrackEnded`, `frequentTracks`
Tests: `Tests/HomeStereoAppCoreTests/ListeningPersistenceTests.swift`

## macOS Playback Integration

Primary: `Sources/HomeStereoDLNAAppCore/SystemPlaybackIntegration.swift`, `Sources/HomeStereoDLNAApp/MenuBarPlaybackView.swift`, `HomeStereoDLNAApp.swift`
Keywords: `MPRemoteCommandCenter`, `MPNowPlayingInfoCenter`, `NowPlayingSnapshot`, `MenuBarExtra`

## Sleep, Network, and Recovery

Primary: `Sources/HomeStereoDLNAAppCore/RecoveryStore.swift`, `Services.swift`, `RendererPlaybackStore.swift`
Keywords: `MacSystemEventMonitor`, `SystemPlaybackEvent`, `ReconnectPolicy`, `prepareForSystemInterruption`, `reconnect`

## Automatic Library Updates

Primary: `Sources/HomeStereoDLNAAppCore/LibraryStore.swift`, `Services.swift`, `Sources/HomeStereoAppCore/LibraryService.swift`
Keywords: `FolderChangeMonitor`, `folderDidChange`, `changeDebounce`, `scanGeneration`, `isStable`
Tests: `Tests/HomeStereoDLNAAppCoreTests/LibraryAutoUpdateTests.swift`

## JSON Backup Contract

Primary: `Sources/HomeStereoAppCore/BackupContract.swift`, `Sources/HomeStereoDLNAAppCore/BackupStore.swift`, `Sources/HomeStereoDLNAApp/BackupView.swift`, `docs/json-backup.md`
Keywords: `HomeStereoBackup`, `BackupCodec`, `BackupTrackMatcher`, `mergeBackup`, `BackupImportPreview`
Tests: `Tests/HomeStereoAppCoreTests/BackupContractTests.swift`, `Tests/Fixtures/home-stereo-backup-v1.json`

## Library Performance

Primary: `Sources/HomeStereoAppCore/LibraryRepository.swift`, `LibraryService.swift`, `Sources/HomeStereoDLNAAppCore/LibraryStore.swift`, `ArtworkCache.swift`, `docs/performance.md`
Keywords: `TrackFingerprint`, `displayLimit`, `scheduleBrowserRebuild`, `downsample`, `idx_tracks_artist`
Tests: `Tests/HomeStereoAppCoreTests/LibraryPerformanceTests.swift`

## Discovery and Description

Primary: `Sources/HomeStereoKit/Discovery.swift`, `DeviceDescriptionParser.swift`, `ServiceDescription.swift`, `Models.swift`
Keywords: `SSDPDiscovery.discover`, `parseResponse`, `DeviceDescriptionLoader`, `ServiceDescriptionLoader`, `connectionManager`, `presentationURL`

## Sony Stereo Bridge PoC

Primary: `Sources/SonyStereoBridgeCLI/main.swift`, `scripts/sony-stereo-bridge-split.sh`, `docs/sony-stereo-bridge/`
Keywords: `sony-stereo-bridge`, `probe`, `play-one`, `play-pair`, `leftDelayMs`, `GetProtocolInfo`
Tests: `Tests/HomeStereoKitTests/HomeStereoKitTests.swift`

## HTTP Media Server

Primary: `Sources/HomeStereoKit/TrackHTTPServer.swift`, `HTTPTypes.swift`
Keywords: `TrackHTTPServer`, `MediaHTTPRequestHandler`, `ByteRange`, `TrackURLBuilder`, `AudioMIMEType`

## SOAP Control

Primary: `Sources/HomeStereoKit/SOAP.swift`
Keywords: `UPnPController`, `SOAPRequestBuilder`, `SOAPResponseParser`, `GetTransportInfo`, `GetPositionInfo`, `GetVolume`, `GetProtocolInfo`

## Build and Permissions

Primary: `Package.swift`, `HomeStereo.xcodeproj/project.pbxproj`, `HomeStereoApp.entitlements`
Keywords: `HomeStereoDLNAApp`, `network.client`, `network.server`, `NSLocalNetworkUsageDescription`
