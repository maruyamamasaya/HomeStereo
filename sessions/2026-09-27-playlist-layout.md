# Playlist layout fix

- 実画面で、`PlaylistsView`の`HSplitView`が内容の高さに縮み、Playlist一覧が横幅の大半を占有して詳細欄が狭くなることを確認した。
- 分割画面と詳細欄を利用可能領域いっぱいに広げ、Playlist一覧幅を220〜320ptへ制限した。
- `./scripts/verify.sh fast`はXCTest 74件中73件成功・性能test 1件skip、Swift Testing 70件成功。
- `./scripts/verify.sh`も同じtest結果とmacOS Debug build成功を確認した。
- Release配置は、並行中の未完成Analytics変更にある未定義repository補助処理でclean buildが失敗したため未実施。既存の`/Applications/HomeStereo.app`は置換されておらず、停止後に再起動した。
