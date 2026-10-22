# 新アイコンの正式配置

- 明示依頼により `./scripts/deploy-macos.sh` を実行し、現在の作業ツリーをRelease build・配置・起動。
- HomeStereo.xcodeproj / HomeStereo scheme / HomeStereo.app、bundle `jp.local.HomeStereo.Beta`、build `20261023034515`。
- BUILD SUCCEEDED。配置先は `/Applications/HomeStereo.app`。署名、build成果物との実行ファイルSHA-256一致、正式pathのprocess起動、AppIcon.icnsの存在を確認。
- 共通installer経由でHomeStereoAnalyzerのアイコンも更新。一時build・旧bundleは専用scriptでcleanup。
- Dock/Finderの実画面表示は未確認。アプリロジック変更・test実行・test端末の作成／削除なし。

## 旧版の確認・登録整理

- 追加依頼でSpotlightとApplications、Desktop、Downloads、Development、Xcode DerivedData、/private/tmpを調査。HomeStereo.appの実体は正式配置の1件のみ。走査エラーなし。
- Launch Servicesには削除済み `/private/tmp/HomeStereoDerivedData/Build/Products/Debug/HomeStereo.app` の登録が残っていたため解除。正式版を再登録し、同bundle identifierの登録が `/Applications/HomeStereo.app` 1件だけであることを再確認。
- アプリ実体の削除は不要。HomeStereoAnalyzerは別用途の補助アプリとして保持。
- 今回のアイコン10画像・CURRENT・関連sessionをまとめてcommitする。追加のbuild／testは実行せず、直前に成功したDebug／Release buildを検証結果とする。
