# Session: MyMusic Preferences bidirectional export
Date: 2026-09-27

## Request
MyMusicアプリ側のPreferences JSON仕様を変えず、Mac側で変更したお気に入りとGood／BadをMyMusicへ戻せるようにする。

## Investigation
Preferences Importは`mymusic_preferences`とMac側の`favorites`／`track_preferences`を更新していたが、ExportはImport時の`mymusic_preferences`だけを読んでいた。このためMac側の変更はJSONへ反映されなかった。

## Changes
- schema version 2とfield名は変更していない。
- Preferences ExportはMyMusic Track ID接続済みの全曲を対象に、現在のMac側FavoriteとGood／Badを読み取る。
- 未設定値は`favorite: false`、`playbackPreference: 0`として出力する。
- MyMusic未接続曲はHomeStereo Track IDを出さず除外する。
- Import PreviewとMyMusic適用状況も、Exportされる現在のMac状態を基準にした。
- Canonical Track ID、Favorite追加／解除、Good／Bad変更、未接続曲除外を自動testへ追加した。

## Validation
- `swift test --filter MyMusicPersistenceTests`: 22件成功。
- `./scripts/verify.sh`: XCTest 95件中94件成功・1件skip、Swift Testing 77件成功、macOS Debug build成功。
- `./scripts/deploy-macos.sh`: Release build、署名、bundle identifier、build番号、実行file hashを検証し、`/Applications/HomeStereo.app`へ配備して起動。build `20260927233207`。

## Result
既存のMyMusic Preferences JSONをそのまま使い、手動Import／Exportでお気に入りとGood／Badを双方向に受け渡せる。

## Remaining Issues
- 同時編集の自動mergeや自動同期は行わない。利用者が最後にImportしたJSONの値、または最後にExportしたMacの現在値を手動で受け渡す。
