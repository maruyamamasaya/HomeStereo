# Library・再生中・スピーカーUI一括改善

- 曲一覧へ行内再生ボタン、再生中表示、選択件数、Queue／Playlist操作menuを追加した。
- アルバム一覧を可変幅Artwork gridへ変更し、詳細にArtwork、metadata、再生／Shuffle／Queue追加、曲番号を追加した。
- 検索結果件数、検索clear、検索0件とLibrary空の別表示を追加した。
- 「再生中」画面をArtwork、曲情報、進捗、基本操作、音量中心に再構成し、接続・診断情報をDisclosureへ移した。
- スピーカー一覧からIPを外し、選択状態と再生可否を主表示にして、UPnP情報をDisclosureへ移した。
- Queue／Playlistを含む主要操作を狭いwindowで折り返すよう調整した。
- `./scripts/verify.sh`で全testとmacOS Debug buildが成功した。確認用別Bundleの空状態は目視済み。populate済みLibrary各画面の最終目視は確認待ち。
