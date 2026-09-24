# Session: Library foundation
Date: 2026-09-24

## Request
複数音楽folder登録、差分scan、metadata、SQLite永続化、最小UI、既存DLNA単曲再生への接続。

## Changes
- security-scoped bookmarkをSQLiteのfolder recordと対応付け、複数folderを復元可能にした。
- AVFoundation scan、安定UUID、path正規化、差分判定、missing／notice／進捗を追加した。
- LibraryStoreとfolder／曲UIを追加し、選択曲を既存RendererPlaybackStoreへ渡した。

## Validation
- SwiftPM: AppCore 15件、DLNA 13件、失敗0。
- macOS Debug build: 成功。

## Remaining Issues
- SRS-HG1実機でLibrary曲の再生とfolder bookmark再起動復元は未確認。
- Album／Artist閲覧、Queue等は次フェーズ。
