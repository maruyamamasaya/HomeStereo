# MyMusic集計済み再生回数の正本化

- MyMusic Library JSONの`playCount`とHomeStereoの詳細event再集計が一致しない原因を確認した。
- schema v12へ`mymusic_library_play_counts`を追加し、未紐付け曲を含む全`playCount` snapshotをLibrary Importと同じtransactionで置換保存する。
- snapshotがある場合、分析の総再生回数、再生済み曲数、曲別回数、ランキング、評価別回数はMyMusic値を使う。
- 期間別回数、再生時間、完走／Skip率、履歴は情報を持つ詳細eventから引き続き算出する。
- MyMusic適用状況へ曲別のMyMusic再生回数を追加した。
- `./scripts/verify.sh`と最終UI追加後の`./scripts/verify.sh fast`成功。XCTest 82件中81件成功、性能test 1件skip、Swift Testing 75件成功、macOS Debug build成功。
- `./scripts/deploy-macos.sh`で`/Applications/HomeStereo.app`へ配備した。bundle versionは`20260927104916`。
- 最新のMyMusic Library JSONから4,237件・合計6,609回をschema v12の集計snapshotへ反映した。うち接続済みは4,190件・6,510回、未接続は47件・99回。
- 配備後のアプリ画面で総再生回数6,609、MyMusic値を正本とする説明、適用状況の曲別再生回数を確認した。
