# 曲一覧のscroll負荷調査・改善

- HomeStereoの曲一覧性能改善としてMATCH。Git rootと既存変更を確認し、先行するキュー／小型player等の変更を保持した。ユーザーから再生中に起きやすいとの補足。
- LibraryViews、QueueStoreのposition／presentation更新、LibraryStore／ArtworkCacheの画像取得経路、既存performance文書・履歴・テストを確認。実アプリのframe計測や症状再現は未実施。
- QueueStoreに曲ID変更時だけ通知するnowPlayingTrackIDを追加し、曲行をelapsed更新から分離。テストでelapsed=12への更新は通知0、次曲切替は通知1を確認。
- drag payloadを行描画時ではなくdrag開始時に生成。選択ヘッダーは1回の計算結果を再利用し、未選択時の全曲走査を省略。
- Artwork cache hitをfolder DB読込・bookmark解決より前に判定。cancel確認を追加。画像取得時にNSImageを作り、bodyでの繰り返し生成を除去。cache上限／security scopeは維持。
- CURRENT、ARCHITECTURE、docs/performanceを更新。DB／音源／交換JSONの変更なし。

## 検証

- ./scripts/verify.sh成功（cacheアクセスのため権限付き）。XCTest 145件中3件skip、失敗0。Swift Testing 88件成功。macOS Debug BUILD SUCCEEDED。
- 画像cacheのサイズ別lookupとremoveAllを追加検証。git diff --check成功。
- 実音源2万曲・再生中のスクロール、初回／往復、複数選択の体感比較は未確認。原因全体や改善率は未確定。/Applicationsのapp更新は未実施。
- XCTestDevicesは前後ともUUID folderなし、12K（.DS_Storeのみ）。test端末作成0／削除0。DerivedData削除なし。
