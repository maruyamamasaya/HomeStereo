# 再生・読み込み負荷の改善

## 実装

- Library読込時にTrack ID辞書を構築し、Queue、Playlist、履歴、分析Artworkの現在曲解決をO(1)化した。
- `QueueStore.nowPlaying`を保存済み表示modelとし、同じ状態の再公開を抑止した。macOS Now PlayingはArtworkを一度だけ画像化し、状態変化時または5秒ごとの位置補正だけを公開する。
- 再生位置は5秒ごとに`queue_state.position`だけを更新し、Queue全件の書き直しを廃止した。
- 履歴の再生途中保存を10秒checkpointへ変更し、終了時は即時保存する。途中経過では公開履歴配列を書き換えない。
- Analyticsは画面外ではdirty flagだけを立て、画面表示中は500ms debounce後に再集計する。
- scan進捗を100曲または250msごとに間引き、scan taskをutility priorityへ下げた。FSEvents由来の自動scanは再生中に開始せず、停止後に実行する。

## 検証

- Queue位置だけの更新が曲順、現在位置、Repeat、Shuffleを保持するtestを追加した。
- 250件未変更scanで進捗callbackが50回未満になるtestを追加した。
- 自動scanが再生停止まで待機するtestを追加した。
- Analyticsが非表示中に再読込せず、再表示時に1回だけ更新するtestを追加した。
- `./scripts/verify.sh fast`成功。
- `./scripts/verify.sh`成功。XCTest 80件中79件成功＋性能test 1件skip、Swift Testing 72件成功、macOS Debug build成功。

デプロイは実施していない。
