# 非Renderer探索行の除外

- `ssdp:all`で受信した非Renderer機器のDevice Description取得失敗が、Renderer一覧にIPアドレスだけの行として残る問題を修正した。
- Description取得失敗を一覧へ残すのは、SSDPのsearch targetが`MediaRenderer`の応答だけに限定した。
- 非Renderer失敗を除外し、真正のMediaRenderer失敗は診断用に保持するtestを追加した。
- `./scripts/verify.sh fast`と`./scripts/verify.sh`が成功。実行中アプリは音楽再生中だったため再起動していない。
