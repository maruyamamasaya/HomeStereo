# テーマ設定

## 結果

- GitHub APIで非公開repository `maruyamamasaya/living-aurora-ui`を直接確認し、commit `7138d4a5f8578cc1991c6a3add76fef30c11e345`の`docs/DESIGN_SYSTEM.md`、`docs/themes/`、`src/styles/themes.css`を参照した。
- HomeStereoへシステム／シンプルダーク／Living Aurora／Pulse Neon／Blue Cosmosを追加した。設定画面と「表示」メニューから変更し、`appearance.theme`へ保存する。
- main Window、Mini Player、MenuBarExtra、Settingsへ共通のcolor scheme、accent、静的背景を適用する。既定は従来外観を保つシステムとした。
- Reduce Transparencyまたはincreased contrastでは装飾光を描画しない。再生、Library、SQLite、MyMusic JSON、Backupの契約は変更していない。

## 検証

- `./scripts/verify.sh fast`: 成功。XCTest 87件中86件成功＋性能test 1件skip、Swift Testing 77件成功、Swift Package build成功。
- `./scripts/verify.sh`: 成功。上記testに加え、Xcode macOS Debug buildとad-hoc署名に成功。
- 実画面での各テーマ、Light／Dark、VoiceOver、Reduce Transparencyの確認は未実施。
