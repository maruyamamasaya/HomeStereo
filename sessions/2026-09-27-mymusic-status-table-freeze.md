# MyMusic status table freeze

- 「MyMusic適用状況」で狭いfilterから「すべて」へ戻すと、SwiftUI `Table`の差分更新が12,188行の自動行高計算を行い、CPU 99.9%・数GBのmemoryを消費して応答不能になることをprocess sampleで確認した。
- 一覧行を固定高の1段表示へ軽量化し、一覧内のtext selectionを詳細欄へ限定した。
- filterまたは検索条件が変わったときはnative tableを置き換え、大量行を差分insertしないようにした。表示対象配列も1回のView更新につき一度だけ計算する。
- 実データ12,188曲で初期表示、未接続328曲から全件への復帰、検索0件から全件への復帰を確認した。操作後はCPU 0%、RSS約351MiBだった。
- `./scripts/verify.sh fast`、macOS Debug build、実データUI確認に成功した。`/Applications/HomeStereo.app`へのdeployは実施していない。
