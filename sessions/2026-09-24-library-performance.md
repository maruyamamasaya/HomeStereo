# 20k Library performance phase

- 20,000件の合成metadata fixtureで変更前を測定後に最適化。
- 差分なしDB適用を0.383sから0.036sへ短縮し、peak footprintを約7%削減。
- SQLite index追加のため初回適用とDB容量は増加するtrade-offを記録。
- 曲を150件ずつ表示し、検索debounce／cancel、background集計、Artwork downsample／上限cacheを追加。
- 全回帰testとmacOS Debug build成功。詳細は`docs/performance.md`。
