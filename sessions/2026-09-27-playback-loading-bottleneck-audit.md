# 再生・読み込みボトルネック監査

## 範囲

20,000曲前後で発生する再生中のかくつき、読込遅延、再生不安定化について、現行実装と既存testを静的監査した。修正は行っていない。

## 確認結果

- 1秒周期の再生状態pollingが、`QueueStore.nowPlaying`、履歴更新、Now Playing公開を連鎖させる。現在曲の解決は毎回`library.tracks.first`であり、複数Window／MenuBarの再評価ごとに全曲線形探索となる。
- 位置更新はQueue保存を1秒debounceするが、保存時は最大100件の`playback_queue`を全削除・全挿入する。`ListeningStore`も位置更新ごとに250ms debounceで再生eventをupsertするため、再生中にSQLite書込が継続する。
- 曲終了時はraw eventと集計をtransaction保存した後、画面表示中かに関係なく`AnalyticsStore.refresh()`を起動する。30,000曲全件、全event、Favorite、Playlist、Preferenceを再読込して全Track summaryを再構築するため、曲切替時のDB lock／CPU競合候補である。
- 自動scanは全候補ごとに`ScanProgress`をMainActorへ通知する。30,000曲では未変更scanでも約30,000回のObservable更新となり、scan後に全曲再読込とBrowser index再構築も行う。
- 履歴画面の`frequentTracks`は各eventごとに全曲線形探索するため、event数×曲数になる。`recentEvents`、`unplayedTracks`もView評価のたびにsort／全件filterを行う。
- Now Playingは位置更新ごとにRemote Command可否と`MPNowPlayingInfoCenter`全体を更新し、Artwork Dataから`NSImage`を再生成する。
- DLNAは1秒ごとにTransport、Position、VolumeをSOAP取得する。直列要求と最大5秒timeout／read retryにより、遅いRendererやWi-Fiでは表示更新周期が伸び、失敗2回で状態が`unknown`へ遷移する。
- Sonyステレオは再生開始前に曲全体を左右mono PCM WAVへ変換・一時保存する。長尺／高sample rate音源では開始遅延とCPU／disk I/Oが大きい。曲数とは独立だが「読み込みが遅い」直接要因である。

## 実測と不足

`HOMESTEREO_RUN_PERFORMANCE=1 swift test --filter LibraryPerformanceTests/testThirtyThousandTrackMetadataFixture`は成功した。30,000件で初回DB適用1.214s、未変更適用0.148s、全件load 0.366s、browse 0.758s、sort 0.389s、search 0.764sだった。

既存性能testは単発のDB／Browser処理のみで、再生pollingとの同時実行、Queue定期保存、履歴増加、Artwork／Now Playing、end-to-end scan、Sonyステレオ変換を測っていない。実際の症状との因果確定には`os_signpost`等でこれらの区間を計測し、20,000〜30,000曲＋長期履歴で再生しながら確認する必要がある。

## 優先順位

1. Track ID辞書化とNow Playing公開頻度の抑制
2. Queue位置だけの差分保存と再生event保存頻度の削減
3. Analyticsのlazy／差分更新
4. scan進捗通知の間引きと再生中の負荷制御
5. 履歴派生値のcache化
6. Sonyステレオの逐次変換／streaming方式の検討
