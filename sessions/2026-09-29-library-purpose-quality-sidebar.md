# 2026-09-29 音源の用途・品質Sidebar

## Result

- Sidebarへ「音源の特性」セクションを追加し、「作業用BGM」と「ハイレゾ」を共通曲ライブラリのfilterとして実装した。
- 通常の「曲」一覧には、作業用BGMにもハイレゾにも該当しない曲だけを表示する。
- 作業用BGMはgenreの「作業用BGM」、ハイレゾはgenreの「ハイレゾ」、または44.1kHz・16bit以上を最低条件として24bit以上／48kHz超で判定する。音源の複製や変換は行わない。
- 曲・アルバム・アーティストの既存modelと画面は維持し、filter後の曲にも元のAlbum／Artist表示を残した。
- 通常／作業用に分かれていたPlaylistのSidebarを1画面へ統合し、どの音源もPlaylistへ追加できるようにした。既存`kind`はMyMusic JSON互換用metadataとして保持する。

## Validation

- `./scripts/verify.sh fast`: 成功。
- `./scripts/verify.sh`: 成功。XCTest 98件中97件成功、性能test 1件skip。Swift Testing 77件成功、macOS Debug build成功。
- macOS実画面の手動操作確認は未実施。
