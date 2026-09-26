# 曲一覧の音源metadata列

- 曲一覧へジャンル、年、音質、サイズ、ファイルパス列を追加した。
- 音質列には形式、bit rate、sample rateをまとめ、macOS 14.0のTable最大10列に収めた。
- ファイルパスは中央省略し、pointer hoverで全文を確認できる。
- scan時にgenre、release year、音声trackのestimated data rateを取得するようにした。
- Track metadata schemaをv3へ更新し、既存曲は次回scanで新しいmetadataを再取得する。
- SQLite schema v8へbit rateを追加し、旧schemaからTrackを失わずmigrationする。
- `./scripts/verify.sh`は成功した。XCTest 50件（1件skip）、Swift Testing 59件、macOS Debug buildを確認した。
- デプロイは行わない。
