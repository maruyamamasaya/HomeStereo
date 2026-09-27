# MyMusic application status and UI refresh

- 管理Sidebarへ「MyMusic適用状況」を追加した。
- 全HomeStereo曲のローカルTrack ID、MyMusic TrackID、snapshot在籍、照合方法、JSON出力対象、Preferences／Events／MyMusic Playlist関連を一覧・検索・filter・詳細で確認できる。
- MyMusic Playlist Import完了後に`PlaylistStore`、Preferences Import完了後に`ListeningStore`を再読込し、SQLiteへの適用を画面へ即時反映する。
- `MyMusicTransferStoreTests`へcommit後hookと適用状況Storeの回帰testを追加した。
- `swift test --filter MyMusicTransferStoreTests`は7件成功。
