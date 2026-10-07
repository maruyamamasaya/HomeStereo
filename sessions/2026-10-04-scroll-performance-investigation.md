# 曲スクロール性能の調査

## 範囲と方法
HomeStereoの曲テーブルと最近追加したプレイリスト操作を対象にコード、差分、既存性能資料を調査。アプリの実データや操作状態は変更しない。製品コードの修正・build・deployは実施していない。

## 課題
1. 優先高: LibraryViews.swiftのSongsTableでselectedTrackIDs computed propertyが全表示曲のmap＋filterを毎回実行。最近追加した選択バーでは未選択時も1回、選択時は表示だけで3回評価。selectedTrackIDs(for:)も選択行のdraggable payload作成時に同じ全件処理を繰り返す。全件配列の確保とMainActor処理を避け、表示世代／選択変更時に一度だけ順序付き選択IDを計算すべき。未選択時は即時returnが可能。先の機能追加に伴う負荷増加箇所。
2. 優先中: ListeningStore.isFavoriteは配列contains。曲行では同じIDを4回判定。お気に入りIDをSetとして保持し、行内は一度だけ判定する余地がある。既存課題で、プレイリストにも同じ判定を追加した。
3. 優先中・影響未計測: CachedArtwork.bodyは再評価ごとにNSImage(data:)を生成。actor側はJPEG Dataだけをcacheするため、この画像オブジェクト再生成を防いでいない。実際のdecode回数や描画時間は未測定。Artworkのない結果や同時要求もcache／統合しておらず、再表示でAVURLAsset metadataを再取得し得る。missingを永久にcacheせず、scan世代・metadata更新時の失効設計が必要。
4. 検証不足: docs/performance.mdの2万／3万曲性能検証はmetadata・DB・sort主体で、音源とArtworkを含むスクロールFPS、MainActor stallの計測は未実施。既存数値では今回の体感低下を否定できない。

## 合成計測
/tmp/homestereo-scroll-probe.swiftをswiftc -Oで実行。個人音源・DBを使わずUUIDの合成データを使用。数値は処理単体であり、SwiftUIの実再描画回数やFPSではない。
- 12,000曲・未選択・map/filter 1回: 0.1324ms
- 12,000曲・5曲選択・map/filter 3回: 1.7791ms
- 12,000曲・30曲選択・map/filterを30回繰返し: 18.6625ms。選択行が毎回30行評価されると仮定した処理量の例であり、実画面の観測値ではない。
- 3,000お気に入り・未登録30行・4回判定: 1.4338ms

## 判断・次の検証
全件選択抽出の重複処理を最優先、その次にfavorite Set化。ArtworkはMainActor／画像ロードのprofile後に改善範囲を決める。実スクロールを停止／再生中、選択なし／複数選択、初回／往復で比較し、frame時間・MainActor stack・音源I/Oを測る必要がある。スクロール遅延の主因は未確定。テスト端末作成・削除0、Xcode test未実施。
