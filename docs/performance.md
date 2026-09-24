# Library performance

2026-09-24、Apple Silicon／Debug buildで、音源本体を作らず20,000件の合成`Track` metadataをSQLiteへ投入する`LibraryPerformanceTests`を計測した。再実行は次の通り。

```sh
HOMESTEREO_RUN_PERFORMANCE=1 /usr/bin/time -l swift test --filter LibraryPerformanceTests/testTwentyThousandTrackMetadataFixture
```

| 指標 | 変更前 | 変更後 | 備考 |
| --- | ---: | ---: | --- |
| 初回SQLite scan適用 | 0.319s | 0.434s | 検索index追加の書込costで増加 |
| 差分なしscan適用 | 0.383s | 0.036s | fingerprint比較で未変更upsertを省略、約90%短縮 |
| 20,000件load | 0.232s | 0.243s | ほぼ同等 |
| in-memory検索／集計 | 0.602s | 0.594s | ほぼ同等。UIではbackground実行＋300ms debounce |
| DB容量 | 7,991,296 bytes | 11,325,440 bytes | Artist／Album／title等のindex分増加 |
| peak memory footprint | 17,564,368 bytes | 16,302,776 bytes | `/usr/bin/time -l`の同指標、約7%減 |

ビルドcache状態に左右される`maximum resident set size`と実行全体時間は比較対象にしない。初回書込とDB容量はindexとの明示的なtrade-offである。

## Applied safeguards

- `(folder_id, relative_path)`、Artist、Album Artist＋Album、titleへSQLite indexを追加。
- 未変更fileはmetadata／Artworkを再解析せず、DB upsertも省略。
- metadata解析は現在1並列に制限し、SQLite更新はscan単位のatomic transactionで行う。
- 曲表示は150件ずつ増分表示し、検索は300ms debounce、古いTaskをcancelする。
- filter／sort／Album／Artist集計はSwiftUI body外かつbackground taskで一度だけ構築する。
- scan世代IDで古い結果を破棄し、再生／Queue／DLNAのMainActor処理とは分離する。
- Artworkは要求pixel sizeへdownsampleし、48件／24MiB上限cacheへ保存する。画面外へ出たSwiftUI taskはcancelされ、cancel後の結果は反映しない。

実音源20,000曲での起動、scroll、Artwork scroll、scan中のSRS-HG1操作は実機確認項目として残す。

最終監査後の再確認では、初回適用0.562s、差分なし0.099s、load 0.242s、検索／集計0.590s、DB 11,325,440 bytesでtest成功。環境差を含むため上表の基準値は置き換えない。
