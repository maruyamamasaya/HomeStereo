# macOS Usability and Accessibility

曲、Album、Artist、Playlistを複数選択可能にし、Track UUIDだけのdrag payloadでQueue／Playlistへ追加できるようにした。右クリックから再生、次、Queue、Playlist操作を提供し、Queue／PlaylistだけでDeleteが参照を消す。全消去、Playlist／folder削除、Favorite／履歴resetには確認を追加した。

Queue InspectorとArtwork付き小型player Windowを追加し、共有Storeで複数Windowを同期する。window frame、Sidebar、Inspector状態を復元する。⌘F、Space、⌘Oを追加し、VoiceOver label／value／hint、system color／fontを使用した。通常test 51件とmacOS Debug buildを実行する。VoiceOver、Light／Dark、Reduce Motion、drag、狭いwindowの物理UI確認は最終実機確認まで未実施。
