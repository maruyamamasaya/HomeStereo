# テーマ設定

## 結果

- GitHub APIで非公開repository `maruyamamasaya/living-aurora-ui`を直接確認し、commit `7138d4a5f8578cc1991c6a3add76fef30c11e345`の`docs/DESIGN_SYSTEM.md`、`docs/themes/`、`src/styles/themes.css`を参照した。
- HomeStereoへシステム／シンプルダーク／Living Aurora／Pulse Neon／Blue Cosmosを追加した。設定画面と「表示」メニューから変更し、`appearance.theme`へ保存する。
- detail画面、sidebar、queue inspector、案内barへ共通のテーマ背景と半透明surfaceを適用した。曲Tableは標準の交互行グレーを無効化し、テーマ色が行の背後まで見える構成にした。
- main Window、Mini Player、MenuBarExtra、Settingsへ共通のcolor scheme、accent、静的背景を適用する。既定は従来外観を保つシステムとした。
- Reduce Transparencyまたはincreased contrastでは装飾光を描画しない。再生、Library、SQLite、MyMusic JSON、Backupの契約は変更していない。

## 検証

- `./scripts/verify.sh fast`と`./scripts/verify.sh`は成功した。XCTestは94件中93件成功・performance fixture 1件skip、Swift Testingは77件成功、macOS Debug buildとad-hoc署名は`BUILD SUCCEEDED`。
- Blue Cosmosの実画面で、スピーカー、曲、アルバム、sidebar、queue inspectorを確認した。曲一覧から不透明な交互行グレーが外れ、テーマ色と半透明surfaceが表示されることを確認した。
- `./scripts/deploy-macos.sh`でRelease版を`/Applications/HomeStereo.app`へ配置し、正式配置から起動した。bundle versionは`20260927231159`、実行ファイルSHA-256は`27d2f190e5e26a0b05aa04775516f5888679ecb3b4f483326f2ee4653c904c22`。配置前後の署名、bundle identifier、build番号、実行ファイルhash照合は成功した。
- Living Aurora／Pulse Neon／シンプルダーク、Light／Dark切替、VoiceOver、Reduce Transparencyの実画面確認は未実施。
