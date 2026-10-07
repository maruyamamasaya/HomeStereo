# プレイリスト統合

## 変更
- HomeStereoの管理メニューから、同じ種類の2件を統合して新規リストを作成する画面を追加。通常／作業用の境界を維持する。
- 順序は1件目→2件目。重複Track IDは既定で最初の1曲だけに集約し、保持も選択可能。未解決Track IDも保持する。タグを正規化して合流し、20個超の場合は中止する。
- 新規Playlist ID・item IDを発行し、元のCanonical Playlist IDは引き継がない。
- 元リストは既定で保持。削除を選択した場合は元2件をmerge-before JSONへ保存し、新規保存と削除をSQLiteの単一transactionで実行。確認後の元リスト変更・消失は拒否。

## 検証
- ./scripts/verify.sh: XCTest 125件、3件skip、失敗0。Swift Testing 85件成功。Debug BUILD SUCCEEDED。
- 追加の削除失敗注入後: PlaylistTagTests 5件成功。2件目の削除失敗で、新規作成と1件目の削除もrollbackされることを確認。
- Swift Package testのみ実施。Simulator／XCTestDevicesの新規作成・削除は0。

## 配置・手動確認
- ./scripts/deploy-macos.sh成功。Release build 20261004163747、/Applications/HomeStereo.app、jp.local.HomeStereo.Beta。Build／Install／Launch成功。
- 管理メニュー→統合画面→2件目選択を実アプリで確認。73曲・タグ3個のpreview、既定の重複集約ON・削除OFF、作成ボタンの有効化と画面レイアウトを確認してキャンセル。利用者のリストは作成／削除していない。
- XCTestDevicesのUUID folderは0件、フォルダ総容量12K（metadataのみ）。このタスクの作成／削除端末0件。

## 制約
- タグ合計が上限超過の場合は、元のタグを編集してから再度統合する。
- 削除前archiveの復元UIは既存と同様に未実装。MyMusic側は今回変更しない。JSON取り込みの削除伝搬は追加しない。
