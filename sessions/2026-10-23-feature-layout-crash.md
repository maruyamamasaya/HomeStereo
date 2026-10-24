# 音楽特徴量画面の制約更新クラッシュ対策

- 提供ログのbuild 20261023034515はmain threadのNSWindow制約更新でSIGABRT。SplitViewChildControllerの最小・最大寸法更新が例外経路に含まれる。一方FeatureCodecのdecodeは別threadで実行中で、decode原因とは断定できない。
- TrackFeatureView内のHSplitViewをHStack＋Dividerへ置換。外側NavigationSplitViewと内側split pane間の寸法伝播を減らす。内部境界のドラッグ調整は廃止し、検索・選択・解析・JSON・保存境界は維持。
- ./scripts/verify.sh成功。XCTest 124件、2 skip、失敗0。macOS Debug BUILD SUCCEEDED。最初のsandbox内検証はcache／macro実行制約で失敗したため、標準cacheへのアクセスを許可して全体検証した。
- git diff --check成功。テスト端末作成・削除0、XCTestDevicesはUUID folderなし、合計12 KiB（実行前後で変化なし）。swift testはmacOS hostで実行、Simulator不使用。
- 原因はstackと構造からの推定。実UIでの再現・再発防止確認、正式配置アプリへの反映は未実施。既存データは操作していない。MyMusic側は変更なし。

## 正式配置への反映

ユーザーの反映依頼で専用scripts/deploy-macos.shを実行。Release BUILD SUCCEEDED、build 20261023104211、jp.local.HomeStereo.Beta。/Applications/HomeStereo.appの署名・実行ファイルSHA-256一致と正式pathからの起動processを確認。一時buildと検証用buildの整理は専用scriptで実施。追加testなし、実UIの音楽特徴量画面の再発防止は未確認。

## 再発と追加対策

前回反映版20261023104211でも再発。正式配置版で音楽特徴量への遷移を操作して再現し、stderrでNSGenericException「Update Constraints in Window passesがview数を超えて繰り返された」を取得。HSplitViewの置換だけでは不十分だった。

TrackFeatureViewをGeometryReaderで受けたviewport寸法に固定し、子の最小寸法が親windowの制約更新へ戻らないようにした。Debug BUILD SUCCEEDED。実UIで画面遷移、読み込み・書き出し欄の展開、解析・音量設定欄の折り畳み、保存済み18,967件／照合済み18,861件／書き出し可能12,312件の読み込み完了を確認。曲詳細選択時にCUA接続が切れ、その後も操作ツールを再接続できなかったが、Debug app processは稼働し新しいcrash reportも見つからなかった。詳細表示・狭いwindowでの確認は未完了。追加unit testなし（UI寸法変更のみ、既存124件は前回検証済み）。Simulator／test端末作成・削除0。

追加修正版も専用deploy scriptでRelease BUILD SUCCEEDED。build 20261023104701を正式配置へ更新し、署名・実行ファイルhash一致・正式pathからのprocess起動を確認。正式配置後のUI再確認はCUA接続断のため未実施。

## UI整理と追加検証

ユーザー依頼で曲閲覧／解析・音量／JSON入出力の3区分へ変更。解析・JSON操作を縦スクロールにまとめ、内容幅760pt未満は一覧／詳細の切替、広い場合は横並びとした。曲一覧をLazyVStackと明示Buttonへ変更し、長い曲名は2行まで表示。Store・解析・JSON契約は変更なし。

./scripts/verify.sh成功（124件、2 skip、失敗0、macOS Debug BUILD SUCCEEDED）。最終Button化後もDebug build成功。git diff --check成功。Simulator不使用、test端末作成・削除0、XCTestDevices合計12 KiB。

実画面: データ18,967件読込、3区分のうち曲閲覧／解析切替、約960ptのウィンドウで特徴量への遷移と1列一覧表示まで確認。曲選択操作でCUA native pipeが繰り返し切断し、アプリのprocessは継続。AX操作・座標操作・再接続・再起動で改善せず、曲詳細の正常表示、詳細を開いたままの連続resizeは未確認。幅縮小のドラッグは反映されず、Windowメニューの左半分配置で検証した。

別件の補助アプリ終了を専用launcher-error.logで確認。Python workerがHomeStereoのcontainer内AnalysisRunsへstatus用一時fileを作成する段階でPermissionError errno 1となる。音源読込前の失敗。OS更新が原因かは未確定。権限設定・cache・音源は変更せず、解析再実行も行っていない。権限の復旧確認は残課題。

UI整理版を専用scriptでRelease build・正式配置・起動（20261023105903）。署名・実行ファイルhash一致を確認。

## 狭い幅での起動再発と外側パネル対策

UI整理版20261023105903の起動後process確認で終了を検出し、10:59:47のcrash reportを確認。SplitViewChildControllerの最小寸法伝播を含む同じNSWindow制約更新例外だった。正式配置への起動要求成功を稼働継続と見なさない。

DLNAContentViewの右キューを.inspectorから.safeAreaInsetの固定幅320ptへ変更。NavigationSplitViewとAppKit inspectorの入れ子を減らした。表示閾値1180pt、表示設定、狭い幅でキューページを開く操作を維持。右パネルのドラッグ幅調整は廃止。macOS Debug BUILD SUCCEEDED、git diff --check成功。変更前の全体verify成功後、追加変更に対してbuild検証を実施。

修正版のDebug appで保存された約960ptのwindowを再開し、曲画面から特徴量へ移動、解析タブ切替、18,967件の読込完了を確認した。曲詳細選択ではCUA native pipe切断が再発し、詳細正常表示の確認は依然できない。繰り返し確認を試みたが操作ツールによる確認範囲の限界として残す。

最終Release 20261023110254を専用scriptで正式配置。BUILD SUCCEEDED、署名・実行ファイルhash一致。起動後正式pathのprocess稼働を確認、最新crash reportは旧UI整理版の10:59:47のまま。
