# Good 8〜15の演出と正式配置

2026-10-16。ユーザーの依頼によりMyMusicのみGood 8〜15を段階的に豪華にし、Vesperaへ導入。HomeStereoは前タスクの評価範囲拡張を正式配置した。

## MyMusic

- PreferenceSparklesViewへlevelを渡す。5〜7は従来の3つの光。8〜15は30fps上限のTimelineView/Canvasで7〜21個の星、大きさ、6〜20ptのはみ出し、光量を段階的に増やす。10以降は周回する輪、11以降は虹色が加わり、輪も段階的に増える。
- 通常／小型／ハイライトの共通PlaybackPreferenceButtonとVisualWorldControllerに適用。共通ボタンのタップ時の波紋とアイコン拡大も段階的に強めた。常時opacity 0だった旧波紋をkeyframe式へ置換。
- Reduce Motion、scene非active、非表示時は連続Canvas更新を止める。装飾はaccessibilityHidden／allowsHitTesting(false)で操作領域を変えない。保存形式・選曲上限10は維持。HomeStereo／Watchへこの演出は追加しない。
- generic iPhone／埋め込みWatch Simulator Debug build: BUILD SUCCEEDED。実ソースをmacOS ImageRendererで8〜15に並べて描画し、星と光の広がり・段階差を目視確認（/tmp/mymusic-effects-preview.png）。実機アニメーション、狭い画面の重なり、長時間負荷は未確認。
- git status確認→check-iphone.sh成功→deploy-iphone.sh実行。初回sandbox内checkはCoreDevice接続timeout、端末アクセス可能な環境で成功した。
- MyMusic.xcodeproj／MyMusic scheme／Debug／MyMusic.app／maruyama.MyMusic。Vespera（iPhone 17e）、UDID 00008150-000C54280E33401C。Build・Install成功。Launchは当初画面ロックで拒否（Locked）。ユーザーのロック解除後、2026-10-16 19:55 JSTにdevicectlでmaruyama.MyMusicの起動成功を確認。実機演出の目視確認は未実施。
- Bundle ID、Team、署名設定、Deployment Targetを変更していない。未コミット変更を保持。

## HomeStereo

- OPERATIONS.mdに従いscripts/deploy-macos.shを実行。Analyzer更新、Release build、署名検証、正式bundle置換、実行ファイルSHA-256一致、正式path起動が成功。
- /Applications/HomeStereo.app、jp.local.HomeStereo.Beta、build 20261016185415。
- executable SHA-256: 61f10f4d099ffc16abc05bd227020d32e30a91ccc44df5cb685d66cc80fd4f75。
- 正式pathのprocess稼働も確認。既存scan通知変更もユーザー作業ツリーのまま含む。評価範囲・互換性の自動検証は直前のpreference-range sessionを参照。実データ復元操作は行っていない。

## その他

UI装飾変更はbuildと静止描画で検証し、新規XCTestは実行していない。test端末の作成0／削除0、XCTestDevices残容量12 KiB。両Gitのdiff --check成功。実機deploy／正式配置を明示依頼されたため専用scriptの通常cleanupを含め実行し、追加のストレージ削除はしていない。
