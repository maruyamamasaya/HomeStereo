# M4Aジャンル・年metadata修正

- 実Library DBを集計し、3,923曲中genre／release yearがともに0件、3,836曲はmetadata schema v3で再解析済みと確認した。
- 原因はM4AのiTunes metadata identifierを汎用文字列判定で認識できていなかったこと。
- `iTunesMetadataUserGenre`と`iTunesMetadataReleaseDate`を明示的に抽出するよう変更した。
- Track metadata schemaをv4へ更新し、既存曲を次回scan時に再解析する。
- iTunes形式のgenre／release dateを使う回帰testを追加した。
- `./scripts/verify.sh fast`と`./scripts/verify.sh`が成功。XCTest 60件成功（性能fixture 1件skip）、Swift Testing 60件成功、Xcode macOS Debug build成功。
- Release build後、実行中のHomeStereoを終了して`/Applications/HomeStereo.app`へ再デプロイした。署名検証、build成果物との実行ファイルSHA-256一致、bundle identifier `jp.local.HomeStereo.Beta`を確認した。
- 実Libraryの再scanは未実施。
