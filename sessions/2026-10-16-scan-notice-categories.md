# ライブラリscan通知の分類

- ScanNoticeに移動成功／注意／エラーの種類を追加し、LibraryServiceで分類する。文言の解析で分類しない。
- LibraryViewsは種類別の件数付きDisclosureGroupを表示し、空の種類は表示しない。移動成功と読み込みエラーの混同を解消。
- 照合曖昧・更新中の保留は注意、metadata読取失敗はエラー。scan、曲ID、永続化の処理は変更なし。
- renameの既存テストに移動成功の分類とエラーなしの検証を追加。
- `./scripts/verify.sh`成功。XCTest 139件（3件skip）、Swift Testing 85件成功、macOS Debug BUILD SUCCEEDED。git diff --check成功。
- 初回はsandboxのcache書込制約、次はビルド中の整形変更で中断。変更確定後の再実行は成功。
- 実アプリの表示は未確認。正式配置／再起動は未実施。Simulator／Xcode test端末は使用・作成・削除なし（swift testのみ）。

## 正式配置

- ユーザーの明示依頼で `./scripts/deploy-macos.sh` を実行し成功。Release BUILD SUCCEEDED、署名検証、配置後hash一致、正式pathからの起動成功。
- build `20261016181544`、bundle `jp.local.HomeStereo.Beta`。起動中の旧processは終了して置換。
- 実行ファイルSHA-256: `e09f4a6b21371a4ab10432385ba501c7390344463a49c37f9e262c6b9159702d`。
- 画面の手動確認は未実施。

## 残差分の確認・コミット

- ユーザーの明示依頼で残る6ファイルを確認。ScanNotice.Kind、LibraryServiceでの分類、種類別UI、renameテスト、CURRENTと本記録に限定される。移動照合／永続化の処理変更なし。
- この同一ソースを含む直前のverify.sh最終結果はXCTest 141件（3件skip、失敗0）、Swift Testing 86件成功、macOS Debug BUILD SUCCEEDED。既に検証済みのためテスト／buildを重複実行せず、git diff --checkを再確認。
- UIの実機目視は未実施。今回test端末の作成・削除なし。
