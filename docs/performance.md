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
- 曲表示は仮想化された`Table`へ全件を渡し、検索は300ms debounceする。曲集合とsort条件が同じ間は全件sort済みbaseを再利用し、ジャンルfilter解除で全件sortを繰り返さない。browser buildはactorで直列化し、cancel済み要求の結果を反映しない。絞り込み結果の世代が変わるとnative tableを置き換え、大量行の差分insertと自動行計測を避ける。
- filter／sort／Album／Artist集計はSwiftUI body外かつbackground taskで一度だけ構築する。
- scan世代IDで古い結果を破棄し、再生／Queue／DLNAのMainActor処理とは分離する。
- Artworkは要求pixel sizeへdownsampleし、48件／24MiB上限cacheへ保存する。画面外へ出たSwiftUI taskはcancelされ、cancel後の結果は反映しない。
- Track IDからTrackへの参照はLibrary読込時に辞書化し、1秒周期の再生状態更新から全曲線形探索を除外する。Now Playing表示modelもStoreで一度だけ構築し、OSのNow Playing公開は状態変化時と5秒ごとの位置補正に限定する。
- 再生位置は5秒ごとに`queue_state.position`だけを更新し、最大100件のQueue全削除・再挿入を行わない。再生履歴の途中checkpointは10秒ごと、終了時は即時保存する。
- 分析snapshotは分析画面が表示中のときだけ無効化後500ms debounceで再構築し、画面外の曲終了では次回表示まで全曲再集計しない。
- scan進捗は最大100曲または250msごとに間引き、自動差分scanは再生中に開始せず停止後に実行する。scan task自体はutility priorityで動かす。
- 「よく聴く」は履歴load時に一度だけ集計し、再生event更新後は再生回数閾値を跨いだ曲だけ差分更新する。
- DLNA pollingはTransportとPositionを並列取得し、Volumeは5秒ごとに間引く。一時的なread失敗は3回連続まで現在状態を維持する。
- Sonyステレオは選曲時とQueueの次曲をutility priorityで先行変換し、sourceと出力設定が一致する左右WAVを最大2件再利用する。

実音源20,000曲での起動、scroll、Artwork scroll、scan中のSRS-HG1操作は実機確認項目として残す。

最終監査後の再確認では、初回適用0.562s、差分なし0.099s、load 0.242s、検索／集計0.590s、DB 11,325,440 bytesでtest成功。環境差を含むため上表の基準値は置き換えない。

## 30,000曲の全件表示評価

2026-09-26、曲一覧の150件段階表示を廃止する変更に合わせ、同じ方式のfixtureを30,000件へ拡張して計測した。

```sh
HOMESTEREO_RUN_PERFORMANCE=1 /usr/bin/time -l swift test --filter LibraryPerformanceTests/testThirtyThousandTrackMetadataFixture
```

| 指標 | 30,000件 |
| --- | ---: |
| 初回SQLite scan適用 | 1.214s |
| 差分なしscan適用 | 0.142s |
| 30,000件load | 0.364s |
| 全30,000件sort／集計 | 0.750s |
| 曲ヘッダー並び替えのみ | 0.381s |
| in-memory検索／集計 | 0.744s |
| DB容量 | 17,367,040 bytes |
| peak memory footprint | 18,154,192 bytes |
| swap | 0 |

`maximum resident set size`はSwift build／test runnerを含む369,164,288 bytesであり、アプリの曲一覧だけの値ではないため比較指標にはしない。`Table`は表示行を仮想化し、Artworkは画面内の要求時だけ読み込んで48件／24MiB上限cacheへ保存する。SQLiteへArtwork本体を保持せず、`Track`の全件読込時も画像を展開しない。この条件では全件表示を止めるメモリ増加は観測されなかった。

曲一覧は全30,000件をsort済み配列として渡す。検索、ジャンル絞り込み、ヘッダー並び替えはbackground actorで構築し、検索だけ300ms debounceする。同じ曲集合・sort条件では全件sort済みbaseを再利用するため、ジャンルfilter解除は線形filterだけで全件再sortしない。今回のfixtureでは従来の全件sortが約0.387秒、base再利用後のfilter解除が約0.023秒だった。結果反映時はnative tableを世代単位で置き換え、AppKitが数万行の差分insertを一括計測する経路を避ける。ヘッダー並び替えは曲名、アーティスト、アルバム、ジャンル、年、時間に限定し、Album／Artist一覧の再集計を省略する。音質、サイズ、ファイルパスは表示専用である。再生キューは永続化・並び替え・UI更新の対象になるためライブラリ一覧とは分離し、通常再生／シャッフルとも生成上限を100曲とする。
