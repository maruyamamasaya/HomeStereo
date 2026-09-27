# 曲一覧filter解除時の応答停止対策

- 曲一覧のジャンルfilter解除が全曲のfilterとsortを毎回作り直し、cancel済みの`Task.detached`も計算を継続していた。
- 曲集合revisionとsort条件ごとの全件sort済みbaseをbackground actorで保持し、filter／検索では順序を保った線形抽出だけを行うようにした。古い要求は直列化され、cancel後の結果を反映しない。
- 絞り込み結果の反映時にnative `Table`を世代単位で置き換え、狭いfilterから全曲へ戻す際の大量行差分insertを避けた。
- 30,000曲fixtureでは全件sort約0.387秒に対し、base再利用後のfilter解除は約0.023秒だった。
- `LibraryBrowserBase`のfilter適用／解除後もsort順とgenre一覧を維持するtestを追加した。
- `./scripts/verify.sh`成功。XCTest 92件中91件成功＋性能test 1件skip、Swift Testing 77件成功、macOS Debug build成功。
