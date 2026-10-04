# ミュージック共通ジャンルプリセット

- HomeStereo継続依頼（MATCH）、Git root確認。既存未コミット作業を保持。
- LibraryBrowser: Album／Artistの構築元を全曲からgenreFilteredへ変更。ジャンルに一致する収録曲だけを持つcollectionとなる。検索はcollection名／収録曲、曲は個々の曲という既存仕様を維持。
- LibraryStore: preset／単一genre／sort変更でもcollectionを更新し、連続操作による古いcollectionの残留を防止。既存background actor、sort済みbase cache、検索debounceを維持。
- LibraryViews: Album／Artistでもpreset tagsと単一genre menu、選択名付き件数を表示。ジャンル0件の案内追加。共有Storeなので曲／お気に入りからの選択も共通。既存collection detail／再生／最大100曲生成はfiltered collectionを使用。
- 既存固定分類／未分類JSON契約、DB、外部依存変更なし。CURRENT／ARCHITECTURE更新。
- verify.sh fast成功: XCTest116（3 skip、失敗0）、Swift Testing84成功。追加テストで混在Albumの収録曲filter、Artist、検索と解除、単一genre、0件、preset直後のsort変更でも全一覧更新を確認。
- Debug BUILD SUCCEEDED。既存テストを無目的に再実行せず、fastとDebug buildでfull相当の検証を実施。
- xcodebuild test／Simulator不使用。test端末作成0・削除0（swift testのみ）。
- Release BUILD SUCCEEDED、deploy-macos.sh成功、署名／hash照合成功。正式配置/Applications/HomeStereo.app build20261004130336を起動。
- 実UIで選択済み「クラシックのみ」がアルバム76件→アーティスト69組へ共通適用され、両画面のタグ選択／選択名／件数／キュー作成buttonを確認。プリセットは変更せず維持。実ライブラリで全操作・VoiceOver・性能数値測定は未実施。
