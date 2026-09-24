# macOS playback integration phase

- MPRemoteCommandCenterのplay／pause／toggle／前曲／次曲を既存QueueStoreへ接続。
- MPNowPlayingInfoCenterへ曲名、Track Artist、Album、Artwork、時間、Renderer由来の状態を同期。
- 通信失敗時はNow Playingを再生中にせず、MenuBarExtraから基本操作とメインWindow表示を可能にした。
- `./scripts/verify.sh`: 39 tests passed、macOS Debug build succeeded。
- media keyとMenuBarExtraの手動操作は実機確認まで保留。
