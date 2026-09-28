# Session: MyMusic Preferences差分Export
Date: 2026-09-28

## Request
MyMusic Preferences JSON schemaを変えず、MyMusicとMacで別の曲を更新しても古い全件snapshotで上書きしないよう、Macで変更した曲だけを書き出す。保存前に対象件数と一覧を確認し、完了後にmacOS Appへ配備する。

## Changes
- SQLite schema v14にMac変更曲、世代token、変更日時を保持する`mymusic_preference_export_changes`を追加した。
- Favorite追加／解除、一括解除、Good／Bad変更、Backup Favorite mergeを曲単位の未送信変更として記録する。
- MyMusic Preferences ImportはMacの現在値をMyMusic値へ揃え、解決済み曲の未送信状態を解除する。
- Preferences Exportは接続済みの未送信変更曲だけを既存schema version 2で生成する。
- 保存前に対象件数と先頭100曲、Favorite、Good／Bad、Canonical Track IDを表示する。
- 保存成功時だけPreview時点と同じtokenを解除する。キャンセル／書込失敗では維持し、Preview後の再編集は次回分へ残す。

## Validation
- MyMusic関連target test成功。
- `./scripts/verify.sh fast`: XCTest 97件中96件成功・性能test 1件skip、Swift Testing 77件成功。
- `./scripts/verify.sh`: 同じ全testとmacOS Debug build成功。
- `./scripts/deploy-macos.sh`: Release build、署名、bundle identifier、build番号、実行file hashを検証し、`/Applications/HomeStereo.app`へ配備して起動。build `20260928004914`、SHA-256 `40ab91fbc48b39564fabb2cedfadc9e0deb3c9f7fb05877af511e4f79025f532`。
- Sandbox container内の実DBがschema v14へ移行し、`mymusic_preference_export_changes`が作成されたことを確認した。

## Result
MyMusicで変更した曲AとMacで変更した曲Bを、既存JSON schemaの曲単位mergeで両立できる。Macからは曲Bだけを出力する。

## Conflict Rule
同じ曲を両側で変更した場合は、最後に行ったMyMusic ImportまたはMac編集が優先される。
