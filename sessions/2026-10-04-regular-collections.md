# Album／Artistから作業用BGM・ハイレゾを除外

- HomeStereo継続依頼（MATCH）、Git root確認。既存未コミット変更を保持。
- LibraryBrowserIndexのcollection構築元をgenreFiltered内のisRegularLibraryTrackへ限定。専用scope用tracksは保持。
- 通常曲と混在するcollectionは通常曲だけを表示、通常曲0件はcollection非表示。収録曲、曲数、再生、キュー作成、1曲Album非表示も同条件へ揃う。
- LibraryViewsに通常曲collectionが0件の案内を追加。元音源／DB／交換JSON／外部依存変更なし。
- LibraryBrowserTestsに固定genre／混在collection／preset適用時の除外テストを追加し、音質属性で分類する既存テストを新仕様へ更新。CURRENT／ARCHITECTURE更新。
- xcodebuild test／Simulator不使用。test端末作成0・削除0（swift testのみ）。
- verify.sh成功: XCTest117（3 skip、失敗0）、Swift Testing84成功、Debug BUILD SUCCEEDED。
- Release BUILD SUCCEEDED、deploy-macos.sh成功、署名／hash照合成功。/Applications/HomeStereo.app build20261004131753起動。
- 実UIで通常曲Album525（1曲非表示ON保存復元も確認）／Artist1263組の一覧を確認。実音再生・VoiceOver・全filterの通し確認は未実施。
