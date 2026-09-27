# 曲一覧・キュー・履歴UI更新

## 実装

- 曲一覧を150件ずつの段階表示から全件表示へ変更した。
- 曲名、アーティスト、アルバム、ジャンル、年、時間のTable headerで昇順／降順を切り替えられるようにした。音質、サイズ、ファイルパスは表示専用とした。
- ヘッダー並び替えとジャンル変更ではAlbum／Artist一覧を再集計しない。音質比較で比較回数分の文字列を生成していた経路は削除した。
- 曲一覧へジャンル絞り込みを追加した。
- 上部toolbarの並び替えPicker、選択件数、選択曲再生、選択曲操作Menuを削除した。複数曲操作は既存のcontext menuを使う。
- 曲一覧から通常再生またはシャッフル再生を始めると、現在の絞り込み／並び順を候補として最大100曲のキューを作る。
- キューは最大100曲とし、既存のdrag並び替えに加えてcontext menuから1曲ずつ上下移動できるようにした。
- 最近再生は同じ曲の最新eventだけを表示する。全eventは「よく聴く」の集計と永続履歴のため保持する。
- 下部バーの音量sliderを112ptから168ptへ広げ、シーク表示と重複していた再生状態・経過時間表示を削除した。

## 性能

`HOMESTEREO_RUN_PERFORMANCE=1 /usr/bin/time -l swift test --filter LibraryPerformanceTests/testThirtyThousandTrackMetadataFixture`を実行した。30,000件load 0.364秒、全件sort／集計0.750秒、ヘッダー並び替えのみ0.381秒、検索／集計0.744秒、peak memory footprint 18,154,192 bytes、swap 0で成功した。詳細は[`docs/performance.md`](../docs/performance.md)を参照する。

## 検証

- `LibraryBrowserTests`成功
- 30,000候補から100曲へ制限し、単項目を上下移動するtest成功
- 最近再生履歴が曲ごとに最新1件だけになるtest成功
- 30,000曲性能test成功
- `./scripts/verify.sh fast`成功（XCTest 62件中61件成功＋性能test 1件skip、Swift Testing 67件成功）
- デプロイ前の`./scripts/verify.sh`成功（上記test＋macOS Debug build）

## デプロイ

`./scripts/deploy-macos.sh`でRelease build `20260926233013`を`/Applications/HomeStereo.app`へ配置した。ad-hoc署名、bundle identifier、build番号、実行ファイルSHA-256の照合に成功し、正式配置から起動した。SHA-256は`afd985219348d89df615e68df9f5bdb0b165c9b8ac3ce2c03b8b4d957c0165d4`。

ヘッダー並び替えを6列へ限定した変更と再集計省略の最適化は、このデプロイ後の変更であり未デプロイ。

実アプリでの手動UI確認は未実施。
