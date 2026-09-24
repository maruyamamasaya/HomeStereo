# Session: Library browsing
Date: 2026-09-24

## Request
曲、Album、Artistの閲覧、検索、sort、詳細、Artwork cache、DLNA単曲再生。

## Changes
- AlbumをAlbum Artist＋Album名、ArtistをTrack Artistだけで集約した。
- Viewへ渡す検索／sort済みsnapshotをLibraryStoreで生成した。
- Artworkを遅延取得し、48件／24 MiB上限のmemory cacheへ保持した。
- 曲と詳細行のdouble-clickを既存DLNA単曲経路へ接続した。

## Validation
- Unit Test 31件、失敗0。
- macOS Debug build成功。

## Remaining Issues
- SRS-HG1実機再生は未確認。
