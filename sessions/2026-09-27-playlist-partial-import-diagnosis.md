# Playlist partial import diagnosis

- MyMusic Playlist JSONは文書全体をdecode・検証した後、各曲のCanonical `trackID`を保存済み`mymusic_track_links`へ完全一致させる。
- 未解決または競合する曲はPlaylistから除外され、解決できた曲だけが順序を保って保存される。Playlist内metadataからのfallback照合は行わない。
- 実利用DBではHomeStereo曲12,188件、MyMusic link 11,860件で、328件が未接続だった。MyMusic由来Playlist「アゲ洋楽」は0曲で保存されており、JSON構文失敗ではなく全曲のTrack ID未解決と整合する。
- 最新の`MyMusic-Library.json`を先にImportし、そのPreviewの未解決／曖昧／ID競合を確認してから`MyMusic-Playlists.json`を再Importするのが現行仕様上の復旧手順。
