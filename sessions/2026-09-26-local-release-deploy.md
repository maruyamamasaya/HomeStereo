# 2026-09-26 ローカルReleaseデプロイ

## 結果

- 現在の作業ツリーからarm64のRelease版をbuildした。
- 実行中のHomeStereoを通常終了し、`/Applications/HomeStereo.app`を更新した。
- bundle identifier `jp.local.HomeStereo.Beta`とad-hoc署名を維持した。

## 検証

- `./scripts/verify.sh`: 成功
  - XCTest 59件中58件成功、明示実行制の性能test 1件skip
  - Swift Testing 60件成功
  - macOS Debug build成功
- macOS Release build: 成功
- `codesign --verify --deep --strict`: 成功
- build成果物と配置先実行ファイルのSHA-256一致: 成功

## 未確認

- 配置後アプリの起動と画面操作
- SRS-HG1／HG10の検出、実音再生、同期
- 公開配布用署名とnotarization（このMac限定デプロイのため対象外）
