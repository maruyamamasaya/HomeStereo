# UI候補B: 再生キュー／プレイリスト

## 実施内容

- 再生キューを曲順編集へ集中させ、再生済み／再生中／次／その後を区別した。
- 選択したQueue項目を現在曲の直後へ移動する「次に再生」を実装した。
- Queueの再生操作を下部バーと再生中画面へ集約した。
- Shuffle／Repeatを共通部品化し、下部バーと再生中画面へ追加した。
- Playlist一覧と詳細へ代表Artwork、曲数、合計時間、利用不可件数を追加した。
- Playlist作成、名称変更、Import／Export、削除をToolbar／dialog／menuへ整理した。
- Playlist再生時はmissingまたは未解決の参照を再生対象から除外するようにした。
- Queue／Playlist周辺の利用者向け用語を日本語へ統一した。

## 検証

- `./scripts/verify.sh`: 成功。
- XCTest 32件成功、任意の性能test 1件skip。
- Swift Testing 39件成功。
- macOS Debug build成功。
- 「次に再生」の順序保持とPlaylistの利用不可曲除外を自動testへ追加した。
- 分離した一時プレビューで空の再生キュー、空のPlaylist、下部バーのShuffle／Repeatを目視確認した。
- 実データ入りQueue／Playlistと再生中画面の最終目視は確認待ち。
