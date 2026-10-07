# 正式配置とリモート反映

ユーザーの明示依頼により、未コミットの保存状態backup v2変更を含む全変更を保持してdeploy-macos.shを実行した。Git rootはHomeStereo、main、fetch後origin/mainと一致。共通データ契約はMyMusicと本文一致。

- Analyzer installer成功後、HomeStereo.xcodeproj／HomeStereo scheme／Release clean build: BUILD SUCCEEDED。
- product HomeStereo.app、bundle jp.local.HomeStereo.Beta、build 20261008073746。
- /Applications/HomeStereo.appへ配置、署名検証成功。実行ファイルSHA-256は2d8d07bd1a638e7598d5912f2a9b25f743681598f59a0135795ad498085a2a6bでbuild成果物と一致。正式pathから起動成功。
- スクリプト所定の旧build／一時bundle整理以外の削除は行わない。実データrestore、実機UI／DLNA再生の検証は未実施。
- 実装時のverify full（XCTest139／3skip、Swift Testing85、Debug build成功）は2026-10-08-state-backup.md参照。今回はdeployのRelease buildとgit diff --checkで確認し、同じtestを再実行しない。Simulator／test端末新規作成なし。
- 既存の全未コミット変更と今回の配置記録をコミット・push対象とする。
