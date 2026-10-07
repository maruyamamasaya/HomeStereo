# プレイリスト追加先の選択

- HomeStereo曲テーブルの行アイコンは1曲、上部ボタンと曲名context menuは選択した複数曲を対象に選択シートを開く。ランダム表示時も画面内の選択曲だけを対象にする。
- 通常／作業用、すべて／タグなし／各タグで絞り込み。追加先は複数選択でき、filter切り替えでも保持し、選択名・件数・追加曲数を表示。追加済みの全件／部分件数を表示し、全件追加済みの行は操作不可。削除操作は持たない。
- Track IDによる既存追加判定。確定時に最新のplaylistをtransaction内で読み直し、入力と既存の重複を除外して末尾追加する。既存の重複曲や曲順、tags、canonical IDは変更しない。
- 全追加先を単一transactionで保存。削除済み追加先は全体を拒否し、保存失敗も全体rollback。保存エラーはシート内に表示して再試行可能。
- 新規UIファイルをSPMとXcodeへ登録。既存add経路も重複防止保存を使用。MyMusic側とJSON契約は変更しない。

## 自動検証
- ./scripts/verify.sh最終実行成功。XCTest128件（3件skip・失敗0）、Swift Testing85件成功。Debug BUILD SUCCEEDED。
- 入力内の重複、既存曲、部分追加、種類をまたぐ複数追加先、再実行の無変更、削除済み追加先による全体拒否、2件目更新失敗による全体rollbackを検証。
- Simulator testなし。test端末作成・削除0、XCTestDevices UUID folder0件、合計12K（metadataのみ）。

## 配置・手動確認
- ./scripts/deploy-macos.sh成功。Release Build／Install／Launch成功、/Applications/HomeStereo.app、jp.local.HomeStereo.Beta。
- 実アプリで曲テーブルの2曲選択→上部一括追加→対象2曲のシートを確認。追加先チェック後にタグなし／作業用へ切り替えても1件・2曲の選択を保持し、選択名も表示。レイアウトを確認してキャンセルした。
- 2曲選択状態のまま行の追加アイコンを押し、対象が1曲になることを確認してキャンセル。利用者のリストには確認用の曲を追加していない。
- 実画面からの保存確定は利用者データを変更しないため未実施。保存・重複防止・rollbackは一時DBの自動テストで検証済み。
