# 解析同時数の選択

- 音楽特徴量に2曲／3曲の選択UIを追加。初期3曲、UserDefaultsで保持、実行中は固定。3種類の解析modeに共通。
- 内部requestへconcurrencyを渡す。旧requestの指定なしは1曲。外部MyMusic JSONは変更なし。
- 上限付きthread pool、task別SQLite connection、thread別ONNX engine。集約側だけがprogress／journalを書く。ONNX／BLAS／FFmpeg filterの内部並列を1に抑える。
- 中断後は新しい曲を投入せず、処理中の最大2〜3曲を保存して終了。
- Python7件成功（実同時到達／上限、失敗、cacheと日時、中断後の未投入を追加）。Swift全体115件／3skip、Swift Testing80件成功。Debug／Release build成功。
- 合成音源3曲の実モデル＋音量は2曲同時・3曲同時とも成功、各3件保存／失敗0。初回JITの影響があり、その時間を実ライブラリ高速化率とは扱わない。
- ユーザー承認後、実行中だった音量解析138件処理／137件保存の中断をUIとlockで確認。本体・companionデプロイ、build 20261004010713。
- 更新後、アプリから旧版・変更曲883件のjobが開始された。request concurrency=3、実ffmpeg3process、画面27/883（失敗0）を確認。別の音量jobを重ねて開始しなかった。
- 完了／中断時にボタン対象数・曲詳細が更新される。実行中の分母は固定。再実行は成功段階cacheを使う。行の照合済みは解析状態と異なる。
- git diff --check成功、意図した12ファイル＋本sessionのみ。MyMusic変更なし。Simulator testなし、test端末作成／削除0。2万曲の速度・長時間負荷は未検証。

## ユーザー依頼の短時間負荷確認

3曲設定の旧版・変更曲解析を45秒、15秒間隔で4回読み取り監視。解析CPU197〜313%（約2〜3.1コア分）、解析RSS848〜898 MiB、本体RSS約359 MiB。メモリ空き指標67〜68%、swap使用量2511.69 MiBから変化なし。52→67／883曲へ進行、失敗3件から増加なし。pmsetに熱／性能warning記録なし。温度そのもの・長時間挙動は未測定。解析を停止・設定変更せず短時間監視を終了。
