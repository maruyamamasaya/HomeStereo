# 通常／作業用プレイリスト分離

## 実装

- MyMusic Playlist JSONの`kind: regular`／`work`を維持し、Sidebarで「プレイリスト」と「作業用プレイリスト」を別画面にした。
- `MyMusic-Playlists.json`、`MyMusic-Regular-Playlists.json`、`MyMusic-Work-Playlists.json`は同じJSON契約としてImportでき、ファイル名ではなく各Playlistの`kind`で分類する。
- HomeStereoからのPlaylist JSON Exportでも保存済み`kind`を維持する。
- HomeStereo Backupでも`kind`を保存し、旧schema v1で省略された場合は`regular`として復元する。
- ローカル作成、M3U8 Import、drag & drop、曲のcontext menuで種類を混在させない。作業用曲はdurationを使わず、genre集合に「作業用BGM」が含まれるかだけで分類する。

## データ整理

- 利用中DBの既存Playlist 54件とPlaylist item 497件を削除した。
- 削除前DBは`Library-before-playlist-reset-20260927-1627.sqlite3`としてApplication Support内に保存した。

## 検証

- `./scripts/verify.sh`成功。XCTest 85件中84件成功＋性能test 1件skip、Swift Testing 77件成功、macOS Debug build成功。
- `./scripts/deploy-macos.sh`でRelease build `20260927162854`を`/Applications/HomeStereo.app`へ配置し、署名・bundle・実行ファイルSHA-256照合後に起動した。
