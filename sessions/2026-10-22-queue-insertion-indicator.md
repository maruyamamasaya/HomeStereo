# キューの挿入位置表示

- HomeStereoのUI改善として実施。開始時にGit rootを確認。既存の小型プレイヤー等の未コミット変更は保持。
- QueueViewの行高を計測し、drag位置の上下半分から挿入境界を決定。青い線を表示し、drop時も同じ境界を使用する。再生済み非表示時は現在曲直後を下限とする。
- 曲一覧からのdropを末尾固定から指定位置への追加へ変更。複数providerはdrag順で読み取り、利用可能曲だけを追加する。キュー内の移動・末尾追加領域・再生中曲の移動禁止を維持。
- QueueStore.insertを追加し、現在項目のidentity／位置を維持して保存。100曲上限は既存policyを使用し、次曲先読みを更新する。
- CURRENT／ARCHITECTUREを更新。JSON／DB schema変更なし。

## 検証

- git diff --check成功。
- ./scripts/verify.sh成功。XCTest 145件（3件skip、失敗0）、Swift Testing 87件成功。指定位置・複数曲の順序・現在項目保持・復元・上限のテストを追加。
- macOS Debug build: BUILD SUCCEEDED。最初のsandbox実行はcompiler cache権限で失敗したため、権限付きで再実行。
- 実アプリでのドラッグ操作・線の表示・自動スクロールは未確認。/Applicationsへの配置は未実施。
- XCTestDevicesは開始前／終了後ともUUID folderなし、12K（.DS_Storeのみ）。test端末の作成0／削除0。DerivedData削除なし。
