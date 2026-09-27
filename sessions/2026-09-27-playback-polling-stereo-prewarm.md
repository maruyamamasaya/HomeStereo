# 履歴・DLNA polling・Sonyステレオ先読み改善

## 実装

- 「よく聴く」は履歴load時に一度だけ全件集計し、その後は再生eventが再生回数閾値を跨いだときだけ対象曲を差分更新する。
- DLNAのTransportとPositionを並列取得し、Volumeは初回と5回ごとに取得する。
- Transport／Positionの一時失敗では現在状態を保ち、3回連続失敗時に`unknown`と通信診断を公開する。
- Sonyステレオは選曲直後にutility優先度で左右WAV変換を開始し、source path／size／更新日時／出力設定が同じ結果を最大2件再利用する。
- Queue再生開始後に次曲へ一時的なsecurity-scoped accessを取得して先読みし、曲切替時の変換待ちを避ける。

## 自動検証

- 履歴の頻繁再生count、polling並列数、Volume call数、一時失敗猶予、先行変換とcache再利用のtestを追加した。
- `./scripts/verify.sh fast`成功。
- `./scripts/verify.sh`成功。XCTest 82件中81件成功＋性能test 1件skip、Swift Testing 75件成功、macOS Debug build成功。

## 未確認

- HG1／HG10実機で、長尺FLACを含むQueue曲切替時の開始遅延、再生中先読みのディスクI/O影響、左右同期、Wi-Fi遅延時の状態追従を確認する。
- GENAと逐次PCM streamは未実装。現在のRange対応WAV配信互換性を維持している。

## デプロイ

- `./scripts/deploy-macos.sh`成功。
- `/Applications/HomeStereo.app`へRelease build `20260927105033`を配置し、ad-hoc署名と実行ファイルSHA-256のbuild成果物一致を確認した。
- 正式配置pathからアプリを起動した。
