# 音楽特徴量 Import Beta

## 実施

- MyMusicとHomeStereoの別Git境界を確認。ユーザーの明示依頼でHomeStereoを変更し、MyMusicのソースは変更していない。作業開始前から両方の特にHomeStereoに多数の未コミット変更があり、それらを保持した。
- MyMusicの特徴量snapshot v1とAnalyzer schema v1を確認し、HomeStereoへ独立FeatureCodec／Resolver／actor archive、Store、Sidebar一覧と詳細、Preview確認Import、再照合、JSON Exportを追加。
- 2万件を想定しdecode・照合・保存をMainActor外で処理。検索をdebounce、一覧を200件ずつ表示。ID／パス／metadata索引を利用。
- 特徴量と音量は別解析版でも欠落時だけ補完し、補完元を表示。モデル名を解析版から推測しない。
- 全件保存snapshotとiPhone向けAnalyzer JSONを区別。Analyzerは同一版・同一日時のグループごとに出力して既存契約を維持。
- 個人JSONはfixtureへコピーせず、環境変数で明示したlocal検証時だけread。

## 検証

- `./scripts/verify.sh fast`: 成功（初回追加5テストを含む）。通常sandboxではSwiftの既存cacheへのアクセスが制限されたため、通常のキャッシュアクセスを許可して実施。
- 提供JSONを指定した`./scripts/verify.sh`: 成功。XCTest 107件、1 skip、0 failure。Swift Testing 79件成功。macOS Debug BUILD SUCCEEDED。
- 追加7テスト: 形式と値域、日時、snapshot／Analyzer round-trip、ID／パス／曖昧照合、古い版と音量補完、失敗時atomic保持、2万件の再Import、提供9,283件の値・日時保持。
- 提供されたVolume JSONは7,806件で特徴量JSON内の音量3項目と全件一致。今回のImportには特徴量JSONだけで足りる。単独Volume Importは対象外。
- Xcode test／Simulatorは実行していない。Swift package testとmacOS buildのみ。Simulator／test端末の作成・削除は0件。DerivedDataは削除していない。終了時の既存XCTestDevicesは90,913,760 KiB（約86.7 GiB）。開始前一覧の記録は行っていないため新旧差分による削除は実施していない。

## 未確認・次段階

- UIの手動操作、実HomeStereo Libraryとの照合件数、実iPhoneへの再Importは未確認。
- 解析実行、cache／Embeddingの引継ぎ、自動iCloud同期、未解析Library全曲一覧は未実装。
- 原JSONにモデル名なし。更新対象は版だけで断定せず、元音源・解析設定・既存cacheを確認する必要がある。
- 独立archiveは既存HomeStereo JSON Backupの対象に含めていない。交換JSONへ出力できないローカルprovenanceやMyMusic ID未付与のAnalyzer結果の退避は内部archiveの保持が必要。

## macOSデプロイ

- ユーザーの明示依頼で`./scripts/deploy-macos.sh`を実行し、未コミット変更を保持したままRelease build、署名／Bundle ID／実行ファイル一致検証、`/Applications/HomeStereo.app`への配置と起動が成功した。
- Build: `20261003234813`、Bundle Identifier: `jp.local.HomeStereo.Beta`。MyMusicのiPhoneデプロイは実施していない。
- 専用デプロイ手順による一時build成果物のcleanupのみを実施。追加test／Simulator実行なし。
