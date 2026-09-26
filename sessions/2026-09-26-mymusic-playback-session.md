# MyMusic playback session

- Rendererで実際に再生開始したHomeStereo曲に対し、一時的な`MyMusicPlaybackSession`を開始する経路を追加した。
- 位置通知の5秒以下の正差分だけを実聴時間へ加え、pause、resume、seek、自然終了、明示的移動、stop、error、shutdownを共通finalizeへ接続した。
- SQLite schemaをv9へ更新し、HomeStereo生成eventはMyMusic Track ID未解決でもHomeStereo Track IDで保持する。export時に最新linkを遅延解決し、未解決件数を報告する。
- `completed`は94%か3秒、`skipped`は未完了の明示的曲移動だけ、再生回数は30秒か曲長50%の短い方を基準とする。
- `swift test`でXCTest 54件（performance 1件skip）とSwift Testing 60件が成功した。
