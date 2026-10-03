# 音楽特徴量 Import Beta

Sidebar「音源の特性 > 音楽特徴量」で既存解析結果を取り込み、曲ごとの全特徴量、解析版、日時、対象音源、照合方法を確認する。音源の変更は行わない。未解析曲の解析と、このMac出力での音量補正にも対応する。

## 利用手順

1. 音楽フォルダを登録する。MyMusic Library JSONのImportでCanonical Track IDを関連付けておくとID優先照合が使える。
2. 「特徴量JSONを読み込む…」でMyMusicアプリの`MyMusic-Track-Features.json`、またはAnalyzerのschemaVersion 1 JSONを選ぶ。
3. 全件検証後の件数Previewを確認して「読み込む」。未照合・曖昧な結果も保存する。再Importは同一曲を統合する。
4. 一覧から曲を選ぶと、全特徴量、相対パス、byte数、曲長、任意の更新日時／hash、解析版と解析日時、元データ取込日時、入力ファイル名を確認できる。
5. フォルダscanやMyMusic Library Importの後は「照合を更新」で保存済み結果を再照合する。

モデル／解析方式の名前は既存JSONに含まれないため「不明」と表示する。analysisVersionだけからモデル名を推測しない。スコアを確率として表示しない。

## JSON契約

- MyMusic snapshot: `version: 1`, `exportedAt`, `tracks`。曲ごとに`trackID`, `sourceIdentity`, `analysisVersion`, `analyzedAt`, `importedAt`, `features`、任意の`title`／`artist`を持つ。
- Analyzer: `schemaVersion: 1`, `analysisVersion`, `generatedAt`, `tracks`。曲ごとにrelativePath、fileSize、duration、features、任意のmetadataを持つ。
- 日時はISO-8601の小数秒あり／なしを受理する。書き出しはUTCの小数秒付き。
- schema、UUID、日時、相対パス、有限値、scoreの0...1、BPMの正値、音量補正の−4...4、音量3項目の完全性、未知field、同一文書の曲重複を全件検証する。
- snapshotはMyMusic IDで、AnalyzerはNFC相対パス・サイズ・曲長・metadataの組で重複を検出する。rootの異なる同じ識別情報を持つAnalyzerの独立した曲は現行契約では区別できない。統合前にMyMusic IDを持つsnapshotを利用する。

## 照合と保存

保存済みMyMusic IDの対応を優先し、サイズ一致・曲長差0.5秒以内を検証する。対応IDがない場合だけNFCかつcase-sensitiveな相対パスを使う。パス候補がない場合だけtitle＋artist、任意album、サイズ・曲長でfallbackする。複数候補は曖昧として自動接続しない。照合結果から完全な音源一致や再解析不要を推測しない。

結果は`Application Support/HomeStereo/track-features.json`のversion 1 archiveへatomic保存する。SQLite、音源、MyMusicリポジトリ、既存Analyzer cacheへ書き込まない。保存処理はactorが直列化し、保存失敗時は画面へ成功を反映しない。新しい解析版を優先し、同じ版では新しい解析日時を優先する。音量項目が欠ける場合だけ完全な既存音量3項目を補完し、補完元の解析版・日時・ファイル名を内部archiveと詳細表示へ残す。

読み込み、decode、照合、保存は画面処理から分離する。パス・metadata・IDを索引化し、曲数×結果数の全件比較を避ける。一覧は検索をdebounceして200件ずつ表示する。検索対象は保存済み結果だけであり、未解析の全Library曲一覧ではない。

## 書き出し

- 「全件保存用JSON」: MyMusicアプリの特徴量書き出しと同じsnapshot契約。MyMusic IDがある曲だけを出力し、対象外件数を表示する。iPhoneのAnalyzer Import入口に渡す形式ではない。
- 「iPhone読み込み用JSON」: 同じ解析版の結果をまとめて既存Analyzer schema v1へ出力する。generatedAtはJSON生成日時で、既存iPhoneはこれを各曲の解析日時として保存する。曲別の元計算日時はこの形式では表現できず、全件保存snapshotとHomeStereo archiveに保持する。解析ごとに数千の日時グループを選ばせないため版ごとの一括書き出しとする。異なる版は混ぜない。相対パスの衝突がある場合は書き出しを拒否する。
- 外部契約には入力ファイル名と音量項目の別provenance fieldがないため、この情報はHomeStereo archive内だけで保持する。

## 更新の次段階

「未解析曲を解析」「音量未解析を解析」「旧版・変更曲を更新」を分ける。既存JSONのsemantic scoreを持つ曲は未解析から除外する。音量だけの追加では分類モデルを実行しない。更新候補は保存済みStable ID、size、任意mtime、解析版から判定し、変更が確認できない既存版2を自動で再解析しない。結果は完了／中断時に取り込む。失敗曲は件数を示し、次回再試行する。MyMusicの既存JSONは利用するが、元のEmbedding／cacheを流用したとは扱わない。

実行は独立したHomeStereoAnalyzerへJSONで渡し、HomeStereo本体のsandboxを維持する。[導入と実行境界](../analyzer/README.md)を参照。

「このMacで音量ノーマライズ」は既定OFF。保存済み音量3項目から再生時に固定gainを適用する。AVPlayerのunity上限内で±4 dB相対補正を表現するため全曲に−4 dBのheadroomを入れる。したがって解析の−14 LUFS基準へ上げられた曲も、実再生は概ね−18 LUFSとなる。全曲を厳密に同じLUFSへ揃える設計ではない。補正OFFではplayer volumeをunityへ戻す。システム出力音量や音源は変更しない。DLNA／Sonyステレオ出力には適用しない。

2026-10-03の提供データは特徴量9,283件（解析版2: 9,267、版1: 16）、音量3項目7,806件。別のVolume Normalization JSONの7,806件は全件同値で、特徴量JSONだけで情報を保持できる。単独Volume JSONにはサイズ、曲長、解析版、解析日時がないため、このBetaでは特徴量JSONと同列のImport形式として扱わない。`isEnabled`によるHomeStereoの再生設定変更も行わない。
