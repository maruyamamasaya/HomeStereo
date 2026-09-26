# 2026-09-25 ローカルデプロイ

## 結果

- HomeStereo 0.1（build 1）のRelease版をarm64でbuildした。
- ad-hoc署名を検証し、`/Applications/HomeStereo.app`へ初回配置した。
- bundle identifierは`jp.local.HomeStereo.Beta`を維持した。
- インストール先の実行ファイルから起動し、最新のスピーカー画面と非モーダルエラー表示を確認した。

## 検証

- Release build: 成功
- `codesign --verify --deep --strict`: 成功
- インストール先processの起動: 成功
- スピーカー再検索: 完了したが0台。初回の`No route to host`表示は再試行で解消した。

## 未確認

- SRS-HG1／HG10の検出と実音再生
- 公開配布用署名、notarization（このMac限定のため対象外）
