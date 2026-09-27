# Sonyステレオ通信リセット

## 実装

- 下部の常設Now Playingバーへ「ステレオ通信をリセット」ボタンを追加した。
- 遅延、L/R入れ替え、出力品質、音量、選択曲を保持し、両RendererへStopを送って左右のHTTP serverとURIを破棄する。
- Stop応答がない場合も回復操作を中断せずローカル接続を破棄し、新しいHTTP URLとURIで接続し直す。
- 再生中だった場合は現在曲を先頭から同期再開する。停止中は接続をクリアするだけで自動再生しない。

## 自動検証

- 設定保持、左右のStop→SetURI→Play、左右音源の再生成、先頭からの再開をtestへ追加した。
- `./scripts/verify.sh fast`成功。XCTest 82件中81件成功＋性能test 1件skip、Swift Testing 77件成功。
- `./scripts/verify.sh`成功。同じ全testに加えてad-hoc署名Debug app build成功。

## 未確認

- HG1／HG10実機で、曲送り後に発生したずれが通信リセット後に解消することと、ボタン操作から再開までの所要時間を確認する。

## デプロイ

- `./scripts/deploy-macos.sh`成功。
- `/Applications/HomeStereo.app`へRelease build `20260927135647`を配置した。
- ad-hoc署名、bundle version、実行ファイルSHA-256のbuild成果物一致を確認し、正式配置pathからアプリを起動した。
