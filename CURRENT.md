# Current State

HomeStereoは、Mac上で選択した音源をLAN内DLNA RendererへHTTP配信してUPnP SOAPで操作するか、macOSのシステム出力でローカル再生するmacOS 14以降向け技術検証である。MyMusicとは独立する。

## Current Phase

要求されたDLNA単曲再生からTrack Identityまでの実装と全体監査は完了。SRS-HG1／HG10の探索、低音量固定ファイル再生、再生中Stop、Audio Hijack経由のL/R分離と1秒segment送信まで実機確認済みで、音響同期と長時間driftの確認が残っている。

独立したSony Stereo Bridge PoCは、HG1/HG10のUPnP能力probe、固定L/R PCM WAV、極小クリック10回のcommand timingまで実機成功。Phase 3 Web UIと1ms単位Delayに加え、BlackHole 2chのAUHAL probe／PCM取得／固定長L/R WAV segment、安全確認後のsegment順次送信経路を実装した。Music→Audio Hijack→BlackHoleのLEFT ONLY／RIGHT ONLY分離と、音量5/100でのHG1=LEFT／HG10=RIGHT各1秒segment送信を実機確認した。音響同期、10分drift、ライブHTTPは未評価。

Audio Hijackの`Sony Stereo Bridge - BlackHole`はMusic→Channels（No Change）→BlackHole 2ch、全ブロック有効、Output 2%、Auto Run Off、Stoppedまで設定済み。LEFT ONLYは左−54.0dBFS／右−160dBFS、RIGHT ONLYは左−160dBFS／右−54.0dBFSで、反転・漏れ・clippingなしを確認した。検証済みsegmentは音量5/100で両RendererがHTTP GET、Play、1秒完走、`STOPPED`まで成功した。詳細な現在地と課題は[`docs/sony-stereo-bridge/status-and-history.md`](docs/sony-stereo-bridge/status-and-history.md)を正本とする。

## Implemented

- 分析の「ランキング」にアーティスト別再生回数／実聴時間とジャンル別再生回数を追加。アーティストは現在のジャンルプリセットを初期選択し、分析内で切替可能。上位20件／全件を比較バーで閲覧する。

- MyMusic向けプレイリストJSONの書き出しで重複Track IDがある場合は件数を表示して確認する。承認した場合だけJSON内を最初の1回にまとめ、元のMacプレイリストは変更しない。

- 再生キュー下部の空き領域に末尾追加用drop targetを追加。曲のdropで追加、キュー内項目のdropで末尾移動。drag中は強調表示し、空のキューでも受け付ける。

- プレイリスト詳細の「キューに追加」で全体を末尾追加し、各曲の＋で個別追加できる。既存QueueStoreの利用可能曲判定と100曲上限を使用する。

- 曲テーブルの追加アイコンと選択曲の一括追加は追加先選択シートを開く。通常／作業用、タグ／タグなしで絞り込み、複数追加先を選択。追加済み件数を表示し、未追加の曲だけを全追加先へ単一transactionで保存する。既存の重複は削除しない。

- プレイリスト内の曲行にお気に入り・Good／Badボタンを追加。共有ListeningStore／PlaybackPreferenceStoreを使い、評価表示・上下限・MyMusic Preferencesの変更検知を既存操作と共有する。

- プレイリスト管理メニューに2件の統合画面を追加。同じ種類のリストから新規IDで作成し、曲順・タグを引き継ぐ。重複曲の集約と元リストの保持／削除を選択できる。削除時は元リストをJSON保全し、新規保存と2件削除を単一transactionで実施する。

- SSDP全件探索、重複排除、Device Descriptionとservice URL解析
- 単一ファイルのtoken付きHTTP配信（GET/HEAD/Range）
- AVTransport／RenderingControl SOAP操作と診断
- `NavigationSplitView`のデバイス／再生UI、`⌘O`、Space
- sandbox user-selected read/write file access、network client/server entitlement。write権限は標準保存panelのJSON出力に使い、音源は実装上読み取り専用
- 複数folder bookmark、SQLite index、差分scan、missing／notice／進捗、LibraryからDLNA単曲再生
- 検索／sort可能な曲・Album・Artist画面、詳細収録曲、上限付きArtwork cache
- 永続Queue、編集、前後移動、Shuffle／Repeat、AVTransport完走連携
- ローカルPlaylist、順序編集、missing参照保持、M3U8 Import／Export
- Favorite、完走／途中停止を含む再生履歴、最近／頻繁／未再生一覧。Macで新規生成する履歴・Playback Eventsは実聴時間が30秒を超えた場合だけ保存する（30秒以下は完走も除外）。MyMusic Importと既存保存済み履歴は維持する
- Sidebarの「分析」で、概要、上位曲、日別event履歴、理由付き傾向、FavoriteとGood／Bad別の完走／Skip傾向を端末内だけで集計・表示する。schema v12でMyMusic Library JSONの`playCount`全件を紐付け不能曲も含めた正本として保存し、総再生回数・曲別回数・ランキングへ使う。期間別回数・再生時間・完走／Skip率はraw eventから集計し、履歴削除はMyMusic集計、Preference、Playlist、曲情報を維持する
- 分析の再生履歴ではPlayback Events JSON既存の`platform`を使い、MyMusicアプリ由来を「App」、HomeStereo由来を「Mac」と曲ごとに表示する。Library JSONのみの累計値は再生元を判定しない
- media key／MPRemoteCommandCenter、Now Playing、MenuBarExtra。メニューバーから現在曲のGood／Bad（−10〜+10）を操作でき、下部再生バー右側と小型プレイヤーにも数値バッジ付き評価アイコンを表示する
- sleep／wake・network監視、UDN再発見、有限backoff、明示的な再開確認
- FSEvents変更監視、debounce、自動差分scan、sleep停止／復帰scan
- schema v1 JSON Export／preview／transactional Import、Track hint照合、rollback
- MyMusic連携用の曲一覧v1、Preferences v2、Playback Events v1を独立文書として扱うCodable DTO、全体検証、JSON非依存交換model、Import／Export service
- SQLite schema v10のMyMusic Canonical Track ID、snapshot在籍状態、Canonical Playlist ID、Preferences、互換Playback Events永続化。実再生Session、位置差分による実聴時間、終了理由判定、未連携eventの保持とexport時の遅延解決に対応
- MyMusic連携Sidebarの「MyMusic連携」からLibrary／Playlist／Preferences／Playback Eventsの4種類を個別にPreview／確認Importし、標準保存panelへExportする手動連携画面。PreferencesはJSON schemaを変えず、MyMusic ImportでMacを同じ状態へ揃えた後、schema v14で記録するMac側のFavorite／Good／Bad変更曲だけを件数・一覧Preview付きで差分Exportする。保存成功時だけ同じ変更tokenを送信済みにし、Preview後の再編集は次回分へ残す。Playback Eventsは既定の直近1か月または任意の開始日〜終了日、全期間を選んで書き出せる。Import Preview表示中でも別のImport／Exportへ切り替えられる
- MyMusic連携Sidebarの「MyMusic適用状況」で全HomeStereo曲のローカルTrack ID、MyMusic TrackID、snapshot在籍、照合方法、Library JSON出力可否、Preferences／Events／MyMusic Playlist適用を曲単位で確認可能。Playlist／Preferences Import後は対応する画面Storeを即時再読込する
- MyMusic連携Sidebarの臨時「開発者」で、MyMusic向け4種類のJSONを現在値から生成または既存ファイルから開き、文書設定と曲／イベント／プレイリストを1件ずつ表形式で編集して、形式検証後に別ファイルへ書き出せる。編集はSQLiteへ反映しない
- MyMusic Playlist JSON v1の単一／複数形式、Canonical Track ID完全一致による部分Import、playlistID単位の冪等更新、MyMusic未接続曲を除外するExport。`kind`は交換互換用metadataとして維持しつつ、Sidebarではkindで通常／作業用BGMを切り替える。既存の曲の混在は保持する。作業用曲は再生時間で推測せずgenreの「作業用BGM」だけで判定する
- MyMusic Library v1の`relativePath`を両端末の共通音楽ルート以下に限定し、保存済みMyMusic ID→正規化path＋size／duration→移動時fingerprint→一意metadataの順で既存HomeStereo曲へ外部IDを関連付ける。端末固有絶対pathとHomeStereo ID再生成は行わない
- 30,000曲fixture計測、DB index／未変更upsert省略、全曲Table表示、background並び替え、検索debounce、Artwork downsample
- 曲一覧のfilter／検索では同じ曲集合・sort条件の全件sort済みbaseを再利用し、再構築をbackground actorで直列化する。filter解除時はnative tableを世代単位で置き換え、大量行の差分insertによる応答停止を避ける
- 再生中のTrack ID辞書参照、「よく聴く」の差分集計、Now Playing更新抑制、Queue位置の差分保存、履歴checkpoint間引き、分析の表示時遅延集計、scan進捗間引きと再生中の自動scan延期
- generation ID、古いpolling破棄、Transport／Position並列取得、Volume 5秒間引き、3回連続失敗までの猶予、終端位置を含む完走判定、操作直列化、有限SOAP read retry
- Sonyステレオ選曲時のutility優先先行変換、同一音源・設定の最大2件cache、Queue次曲の先読み
- Renderer側の外部曲変更検知、通信失敗時のunknown同期、旧HTTP serverのgrace period
- 再生中のidle sleep抑止、匿名化された有限件数の診断JSON Export
- 曲／Album／Artist／Playlistの複数選択、Queue／Playlistへのdrag & dropとcontext menu
- Queue Inspector、小型プレイヤーWindow、window／Sidebar／Inspector状態復元
- Queue Inspectorは初回起動時に開いた状態とし、Toolbarから閉じた状態も以後復元する。キュー上部の「すべてクリア」から確認後に全項目をクリアでき、再生中の曲と履歴sessionは継続する。
- 曲一覧とアルバム／アーティスト詳細は、行のシングルクリックでは選択だけを行い、ダブルクリックで現在再生を変えずキュー末尾へ1回追加する。行とは独立した再生ボタンだけが現在曲へ割り込み、元の再生を終了してクリック曲を現在位置の直後へ挿入し、既存の待ち曲を保持したまま1段下げる。
- 曲一覧の左端には、今すぐ再生、キュー末尾へ追加、追加先を選べるプレイリストメニュー、お気に入り、MyMusic互換のGood／Badボタンをコンパクトに並べる。Goodは1クリックごとに`+1`、Badは`-1`し、`-10...+10`で上限・下限を設けてSQLiteへ保存する。正のGood／負のBadには現在の強度を小さなバッジで表示する。
- 用途別SidebarとArtwork／基本操作／出力先を備えた常設Now Playingバー。通常の「曲」一覧から作業用BGMとハイレゾを除外し、Sidebarの「ライブラリ」にgenreの「作業用BGM」による用途filterと、genreが「ハイレゾ」または「44.1kHz・16bit以上」かつ「24bit以上または48kHz超」によるハイレゾfilterを置く。曲データとAlbum／Artist参照は共通ライブラリのまま維持する
- 設定または「表示」メニューから、システム／シンプルダーク／Living Aurora／Pulse Neon／Blue Cosmosを選択し、端末内へ保存できるテーマ設定。GitHub `maruyamamasaya/living-aurora-ui` commit `7138d4a…`のtokenと光を面として扱う設計をmacOS向けに縮小し、全detail画面、sidebar、inspector、案内barをテーマ背景＋半透明surfaceで統一する。曲TableのmacOS標準交互行背景は無効化し、Reduce Transparency／increased contrastでは装飾光を外す
- 1280×760pxを初期値とし、1920×1080の全画面から960×540級までを対象にしたメインWindow。狭い幅ではQueue Inspectorを自動退避してメイン領域を確保し、ToolbarからQueue画面へ移動できる。短い高さではSidebarのセクション見出しだけを省略して全項目を表示する。Renderer選択付きNow Playingバーは文字を縮小せず幅に応じて2段になる
- スピーカー選択から曲選択へ進む初回ガイドと、無効な再生操作の理由表示
- Queue曲／直接ファイル／Renderer変更を統合するNow Playing表示modelと6状態表示
- 行内再生と選択曲メニューを備えた曲一覧、検索件数と検索0件の専用表示
- 曲・お気に入り・音源分類の一覧とAlbum／Artist詳細に「ランダム表示」「元の順序に戻す」を追加。表示順だけをbackgroundでO(n) shuffleし、結果を画面内で再利用する。曲一覧の列sort／絞り込み変更や詳細の音源更新で解除する。Artistのランダム表示中はアルバム区切りを外して全曲を表示する
- 曲一覧の全件表示、曲名／アーティスト／アルバム／ジャンル／年／時間ヘッダーの昇順・降順、ジャンル絞り込み。音質／サイズ／ファイルパスは初期非表示とし、「表示項目」から個別に表示して選択状態を保存できる
- Sidebarの「ジャンルプリセット」で、複数ジャンルと「ジャンル未設定」をまとめたプリセットを作成・編集・削除・並べ替えできる。SQLite schema v13で順序を永続化し、曲・アルバム・アーティスト一覧上部のタグから共通条件として即時適用する。iPhone互換の`mymusic.genre-display-presets` version 1 JSONを厳格検証してImport／Exportする
- 曲一覧の任意列に形式・ビットレート・サンプルレート、サイズ、ファイルパスを表示。metadata schema v3の再スキャンでジャンル、年、ビットレートを取得し、SQLite schema v8へ保存
- FLACのVorbis Commentをformat固有metadataから正規化し、タイトル、アーティスト、アルバム、アルバムアーティスト、ジャンル、年、作曲者、曲番号／総曲数、ディスク番号／総ディスク数を取得。metadata version 5で既存曲も再スキャン
- Artworkグリッドのアルバム一覧と、Artwork／主要操作／曲番号を備えたアルバム詳細
- Artworkグリッドのアーティスト一覧と、アルバム単位の収録曲／全曲再生／Shuffleを備えたアーティスト詳細
- お気に入りはライブラリと共通の曲Tableで表示し、検索、列sort、表示項目、ジャンル絞り込みとジャンルプリセットを利用できる。再生／Shuffleは絞り込み後の利用可能曲が対象
- Artwork付きの再生履歴と、再生中・利用不可・空・エラー状態の非モーダル表示
- 再生済み／再生中／次／その後を区別し、並べ替えと「次に再生」へ集中した再生キュー
- 再生済みのキュー項目は既定で非表示とし、キュー上部のボタンで表示を切り替える。キューが100曲を超える追加では先頭の古い項目から自動削除する。
- 再生キュー下部の操作不能な一括選択バーは表示せず、各行右端の専用ドラッグハンドルから並べ替える。再生中の行は固定し、ハンドル手前のマイナスボタンで確認なしに1曲だけ削除できる。左側の「次」「その後」と曲の時間は表示せず、再生中だけArtwork上のスピーカーアイコンで示す。
- 通常／シャッフル再生で最大100曲のキュー生成、ドラッグと1曲単位の上下移動、最近再生履歴の曲単位重複排除
- 代表Artwork、曲数、合計時間、利用不可件数を備え、作成／名称変更／管理操作をToolbarへ整理したプレイリスト
- プレイリスト詳細の「曲を追加」から、種類に適合するライブラリ曲を検索・複数選択して一括追加できる選択画面
- 下部バーと再生中画面で共通表示・操作できるShuffle／Repeat
- Artwork、進捗、再生操作、音量を中心にした「再生中」画面と折りたたみ診断情報
- 利用者向けのスピーカー選択画面と、折りたたみ式のIP／UPnP技術情報
- 選択中を優先した安定順、最終検索時刻、再接続状態、非モーダル通信エラーを備えたスピーカー画面
- Sony Wireless Stereoの左右構成を取得できない場合に推測せず「確認できません」と示す状態表示
- 概要、空・更新・アクセス失敗状態と折りたたみ詳細を備えた音楽フォルダ管理
- 保存対象／対象外と安全な復元previewを示す日本語のバックアップ画面
- 狭いwindowで折り返すQueue／Playlist操作と、一覧・詳細の共通余白
- ⌘F、Space、⌘O、参照だけを消すDelete、確認付きdestructive操作、VoiceOver補助
- folder＋relativePath、file resource identifier、保守的metadataの順で判定するTrack Identity
- rename／同一folder内移動／missing復帰時のTrack ID維持、曖昧候補の非統合、schema v8 transaction
- 選択中Rendererの常時polling、同一generation内の古いrefresh破棄、Renderer消失時のunknown同期
- 巨大Artwork source上限、常時downsample／容量上限cache
- capture reportの無音／過大peak／WAV欠落／短すぎるtailを拒否し、明示確認後だけHG1/HG10へ順次送る`play-capture`
- renderer指定、安全確認、capture再生、停止を備えたloopback Sony Stereo Bridge Web UI
- Bridgeの再生前に左右音量を0〜10へ明示設定・読戻し確認する`--test-volume`と、両RendererへStopを送りSTOPPEDまで確認する`stop-pair`
- HomeStereo本体のPause／Stop指示後にRenderer状態を確認し、未反映時は1回再送して最大5回確認する操作処理。Pauseを拒否するRendererでは確認付きStopへfallback
- HomeStereo本体でL soundbar（SRS-HG10）をLEFT、R soundbar（SRS-HG1）をRIGHTとして選ぶSonyステレオ出力。選択曲をAVFoundationで左右のPCM WAVへ分離し、2つのHTTP server／UPnP controllerから同時送信する
- Sonyステレオの既定出力品質を安定優先48kHz／16-bit PCMとし、下部バーから現在の遅延設定を通した16秒・ピーク約-18dBFSの3連クリック群を再生する聴感同期チェック。通常曲選択とQueue完走処理には影響しない
- Sonyステレオ再生中に下部バーの通信リセットから、遅延・L/R・音量・選択曲を保持したまま両Rendererを停止し、左右のHTTP配信と再生URIを破棄して新規接続する。再生中だった場合は現在曲を先頭から同期再開する
- XCTest 98件中97件成功＋任意実行の性能test 1件skip、Swift Testing 77件成功、ad-hoc署名Debug build
- このMac向けad-hoc署名Release版を、実行中copyの終了、clean build、bundle単位の置換、署名・build番号・SHA-256照合、一時成果物削除を行う`./scripts/deploy-macos.sh`で`/Applications/HomeStereo.app`へ一意に配置

## Current Issues

優先度は、`P0`を再生の正しさ・安全性を確定するための必須項目、`P1`を常用前に信頼性を確認する項目、`P2`を回避策があり後回しにできる項目とする。

### 再生基盤

- **P0:** Sonyステレオの物理的な左右定位、segment境界のgap／click、実音の開始差、1〜10分のdriftが未測定。`GetPositionInfo`は整数秒粒度のため、聴感または外部マイクによる評価が必要。
- **P0:** Renderer消失、DHCPによるIP変更、Wireless Stereo解除・再構成後のUDN／service変化と、復帰時にQueueを進めず自動Play／SetVolumeもしないことが実機未確認。
- **P0:** Wi-Fi切断、VPN、Ethernet＋Wi-Fiの複数interface、macOS Firewall下でのSSDPとRenderer→Mac HTTP到達性が実環境未確認。
- **P1:** Sony Stereo Bridgeは検証済みsegmentの順次送信までで、chunked HTTPや終端なしPCMによる連続streamが未実装。segment長ごとのlatency、途切れ、Renderer再設定時間も未評価。
- **P1:** 50曲以上の連続切替、長時間再生、format別のRenderer互換性、巨大Artwork／壊れたmetadata／外付けdisk切断を混在させた実機運用が未確認。
- **P1:** Sony Stereo Bridgeのsource切替、Start／Stop、異常終了、sleep／wake、BlackHole消失、sample rate／buffer size変更時の失敗処理が未確認。Web UIのlatency、sync offset、driftにも未測定表示が残る。
- **P2:** GENAは未実装で、Transport／Positionは毎秒、Volumeは5秒ごとのpollingに依存している。並列取得と3回連続失敗までの猶予は実装済みだが、遅いWi-Fi／Rendererでの実機確認は未実施。
- **P2（既知の制約）:** SRS-HG1／HG10はPauseをHTTP 500／UPnP 701で拒否する。確認付きStopへのfallbackは動作するが、一時停止位置を保持できない。
- **P2（既知の制約）:** 標準UPnP情報ではSony Wireless StereoのL/R構成を確定できず、異機種のHG1／HG10はSony独自`X_Start(STEREO)`もUPnP 816で拒否するため、Sonyネイティブ同期を利用できない。

### UI基盤

- **P0:** 通信切断、再接続、Renderer消失時の非モーダルエラーと状態遷移が実機未確認。誤った再生可能表示や回復操作の不整合がないことを確認する必要がある。
- **P1:** 曲、アルバム、アーティスト、お気に入り、履歴、Queue、Playlistの選択中／再生中／missing表示と主要操作が、実データを使った一連の操作で未確認。
- **P1:** 下部再生バー、再生中画面、Queue、Inspector、小型プレイヤー間の再生状態、Seek、音量、Shuffle／Repeatの同期が実機で未確認。
- **P1:** 狭いwindowでの折り返し、Toolbar配置、空／読込中／失敗状態、画面密度の通し確認が未完了。
- **P1:** VoiceOver、Full Keyboard Access、Space、Command-F、Command-Oを含むキーボード操作の通し確認が未完了。

UI項目の個別状態と完了条件は[`docs/ui-improvement-backlog.md`](docs/ui-improvement-backlog.md)の「確認待ち」を正本とする。

## 音楽特徴量 Import Beta（2026-10-03）

- Sidebar「音楽特徴量」でMyMusic snapshot v1／Analyzer schema v1の全件検証、確認Import、未照合保持、再照合、曲別詳細、全件保存用／解析グループ別iPhone互換JSON Exportに対応。解析実行は次段階。
- 独立actorのatomic JSON保存でSQLite schemaと再生経路を変更しない。モデル名は既存JSONにないため不明として表示する。
- 提供された9,283件のround-trip、2万件の重複しない保存を含む追加7テストが成功。全体はXCTest 107件（1 skip）、Swift Testing 79件成功、macOS Debug build成功。実際のアプリ画面操作と実ライブラリへの照合件数は未確認。詳細は[特徴量](docs/track-features.md)。

## 音楽特徴量の実行・音量補正 Beta（2026-10-04）

- 未解析曲、音量未解析、旧版・変更曲の実行ボタンと件数、進捗、中断、完了結果のImportを追加。既存の解析済みJSONを対象判定に使う。
- 独立HomeStereoAnalyzerをLaunch Servicesで起動し、評価済みEffNet＋分類headとFFmpeg LUFS／True Peakを実行。独立venv／検証済みmodel／component別SQLite cacheを用意し、MyMusic repositoryへ実行時依存しない。本体sandboxは変更なし。
- 「このMac」出力に既定OFFの音量補正を追加。全曲−4 dB headroomを使う固定gain方式で音源を変更しない。DLNAへの適用は未対応。
- 合成音源の実推論、NSWorkspace実起動、差分判定、cache／日時保持／中断、再生開始時gain適用を検証。実ライブラリ全件解析と実聴感は未確認。[詳細](analyzer/README.md)。

音楽特徴量の解析画面は総曲数・処理済み曲数・割合・失敗件数と進捗バーを表示する。成功結果は1曲ごとに復旧journalへ保存し、中断／異常終了時とアプリ再起動後にarchiveへ取り込む。未完了分は実行ボタンから再実行できる。

解析補助アプリへのjob受け渡しをJSON document open eventへ変更。本体と同じsandbox制限の検証アプリで、container内requestの到達と完了を確認した。

音楽特徴量の「同時解析数」で2曲／3曲／6曲を選べる（初期3曲、設定保存）。全解析mode共通、実行中は固定。中断は処理中の曲を完了・保存してから終了する。

## Sidebarと再生中画面の整理（2026-10-04）

ライブラリに作業用BGM／ハイレゾを統合し、その直下にプレイリストsectionを配置。音楽特徴量と分析は管理、ジャンルプリセットは設定、MyMusic連携／適用状況／開発者は独立したMyMusic連携sectionへ配置した。下部再生バーの曲名・Artwork領域から再生中画面を開ける。再生中画面のArtworkは340ptで曲情報の上に表示し、短いwindowではscrollできる。

## 最大100曲のキュー作成（2026-10-04）

曲／アルバム／アーティスト／お気に入り／履歴の各一覧とAlbum／Artist詳細に「最大100曲でキュー作成」を追加。表示中の集合（検索・filter、履歴の選択tab）から利用可能曲だけを重複なく選び、待ち曲を置き換える。再生中／pause中の曲は維持して合計100曲以下、自動再生はしない。候補超過時はGood値の正の部分＋1を重みとして非復元抽選する（+10は11、未評価／Badは1）。上限内は候補順を維持。キュー上部に確認付き全クリアを配置し、音源・Playlist・履歴は保持する。

## ジャンルプリセットの共通適用（2026-10-04）

曲／アルバム／アーティストでジャンルプリセットと単一ジャンル選択を共有し、すべての一覧に選択欄と選択名を表示する。Album／Artistはジャンル条件に合う曲集合から構築し、収録曲・曲数・再生／キュー作成にも同条件が反映される。プリセット適用・解除・単一ジャンル変更・列sortを続けて操作しても、曲とcollectionを同じbackground生成結果で更新する。全曲sort済みbaseの再利用、actorによるbackground処理、検索debounceを維持。固定分類とジャンル未設定の既存プリセット契約は維持。

## 1曲Albumの表示切替（2026-10-04）

Album一覧の「1曲のアルバムを隠す」で現在のジャンル条件適用後の収録曲が1曲のAlbumを非表示にできる。既定OFF、端末内設定を保存し解除可能。表示件数とAlbum一覧からの最大100曲キュー候補も表示Albumに揃える。曲／Artist／元音源／DBを変更しない。全件非表示時に解除buttonを表示する。

## Album／Artistの通常曲限定（2026-10-04）

Album／Artistの一覧・収録曲・曲数・再生・キュー作成は通常曲だけを対象とし、作業用BGM／ハイレゾを除外する。専用曲一覧と元音源は保持。通常曲が残らないcollectionは非表示。1曲Albumの非表示設定も通常曲とジャンル条件を適用した後の曲数で判定する。

## 1曲Artistの表示切替（2026-10-04）

Artist一覧にも「1曲のアーティストを隠す」を追加。通常曲・genre条件適用後の曲が1曲だけのArtistを非表示にし、件数とキュー候補を表示集合へ揃える。既定OFF、端末内保存。Albumの非表示設定とは独立。全件非表示時に解除buttonを表示。元音源／曲一覧を変更しない。

## 同名Albumの統合表示（2026-10-04）

同じAlbum名の曲はTrack Artist／Album Artistが異なっても同じAlbumに表示。表示上のAlbum IDはtitleを正本としgenre絞込でも維持する。共通Album Artistがない場合は収録曲のArtistから単一名／複数のアーティストを表示。Artist内のAlbum区切り・Album数もtitle基準。元metadata・Track ID・DB・JSONは変更しない。同名の別作品も同じ表示Albumにまとまる仕様。

### 2026-10-04 特徴量・分析・操作配置

- 音楽特徴量は読み書き／解析セクション、検索、照合済みfilter、広い詳細表示へ整理。ローカル曲照合とMyMusic Canonical Track IDの一致を別のチェックで表示。
- 分析は概要／カレンダー履歴（日・週）／最近の傾向（ボーカル・インスト・判定保留・未解析）／評価（＋10〜−10・未設定から詳細）／完走・スキップへ分割。カレンダーは500件より古い詳細履歴も対象。
- バックアップを含む主要操作をページ内へ移動。右上はパネル開閉中心の方針をAGENTS.mdへ追記。
- MyMusic連携から特徴量JSONを読み書き可能。JSON加工ツールは手順表示、項目検索、日本語ラベル、特徴量文書の値編集と検証保存に対応。
- 再生バーのGood／Badを再生・お気に入りの操作群へ統合。起動時の既定出力はこのMac、最初のページは曲一覧。再生中のArtwork・metadataを中央配置し、特徴量／JSON編集のsplit paneは約960px幅でも使える最小幅へ調整。
- メイン再生バーのGood／Badは44×44ptのクリック範囲、21ptアイコン、評価数badgeと背景を設けて押しやすくした。Mini Player／Menu Barの寸法は従来通り。
- 再生カレンダーを正方形カード、土日別の文字・枠色、選択日／週の強調、今日の点表示へ刷新。テーマ別の週末色・角丸・選択背景を適用し、ワイド画面はカレンダーと履歴を左右、狭い画面は上下に配置。
- 再生バーの再生／一時停止・前後・お気に入り・シャッフル・リピートも44ptへ統一し、プレイリスト追加ボタン（選択パネル）と曲の詳細popoverを追加。狭い幅では操作群と音量を別行に配置。
- カレンダーの日付は12pt、再生件数は23ptを主表示に変更。ワイド表示では700px幅のカレンダーと細い履歴列、狭い画面では最大680pxのカレンダーを上下配置。履歴rowも細い列向けに曲名／時刻／状態を分けた。


## Playlist連携・タグ管理 Beta（2026-10-04）

上部で通常／作業用BGMを切り替え、その種類に属するタグボタンで一覧を絞れる。新規作成とM3U8 Importは選択したkindで作る。プレイリスト詳細の「タグを編集」で追加・削除・既存タグ選択ができる。20個／40文字と重複正規化はMyMusic互換。タグ編集はID・曲順・kindを変更せずSQLiteへ保存しJSONへ出力する。

Playlist JSON Importは未照合／ID競合曲があれば文書全体をrollbackする。Exportも未接続／競合曲を除外せず停止する。受信原本と置換前の全ローカルPlaylistをDBと同じdirectoryのPlaylistImportArchiveへatomic保存・read-back確認し、保管失敗では更新しない。Preview後の再編集はtransaction内でsnapshot比較して拒否する。受信内容への更新は確認画面に明示する。

MyMusic側もplaylistIDを保持して再Importで複製を作らない。既に増えた重複は自動整理しない。原本の復元UI・外部backup包含、未照合参照の耐久保留と部分適用は未実装。全回帰testとmacOS build成功、実端末間の手動往復とタグUI操作は未検証。詳細はsessions/2026-10-04-playlist-interchange-fix.md。

2026-10-04、既存deploy scriptでRelease 20261004152243を/Applications/HomeStereo.appへ導入・起動成功。MyMusicもVesperaへ導入・起動成功。記録: sessions/2026-10-04-playlist-deploy.md。


## Playlist上部の重なり修正・タグなしfilter

操作欄をsafeAreaInsetから一覧上のVStackへ移し、最上段Playlistが操作欄の下へ隠れる経路を除去した。種類・操作・タグを別行にし、狭い幅では操作ボタンが縦へ切り替わる。横スクロールのタグ欄は36ptで高さを確定する。「タグなし」は実際のタグ名と別状態で、選択kindのtags空Playlistだけを絞る。MyMusic側の一覧・曲追加先sheetにも同じfilterを追加した。XCTest 123件（3件skip、失敗0）、Swift Testing 85件、macOS build成功。詳細はsessions/2026-10-04-playlist-layout-untagged.md。

2026-10-04、修正版Release 20261004153507を正式配置へ更新・起動し、最上段の欠け解消とタグなしfilterを実画面で確認した。

## 期間分析・ランキング・月別振り返り Beta（2026-10-04）

分析で全期間／今月／先月／直近30日／任意期間を選べる。期間指定は開始日以上・終了日の翌日未満の詳細eventから集計し、MyMusic累計playCountを期間へ配分しない。全期間の既存累計優先は維持する。

ランキングは通常曲だけで曲／アーティスト／アルバム／ジャンルを回数／実聴時間で各50位まで表示する。ジャンルプリセットを全種類へ適用し、複数ジャンルはそれぞれへ計上する。アルバムは後続のランキング専用ページ変更でライブラリと同じアルバム名単位へ統一した。行から曲一覧を開いて再生・キュー追加できる。既存Queueの上限を使用する。

履歴カレンダーの表示月に通常曲の時間、代表曲・アーティスト（event件数順）、前月との時間差を表示する。期間filterとは独立した全詳細snapshotを使う。前月の記録欠落と未再生は判別できず、記録上の0として説明する。

作業用BGM／ハイレゾはランキング・概要の上位曲から除外し、分析内の別ページで期間別総時間と日別時間を表示する。分類は現在Libraryの既存判定を使い、両属性の曲は両時間ページへ含める。総概要と通常の履歴・評価は従来どおり全分類を対象とする。未解決曲の時間は用途別へ推測配分しない。

2026-10-04、分析統合版Release 20261004234155を既存scripts/deploy-macos.shで/Applications/HomeStereo.appへ更新・起動成功。Release BUILD SUCCEEDED、署名・Bundle ID・実行ファイルSHA-256一致を確認。一時ビルドはscriptで整理。画面操作は未検証。追加testは実行せず、test端末作成・削除0。

## ランキングの専用ページ・代表画像・比較バー（2026-10-04）

ランキング入口から曲／アーティスト／アルバム／ジャンルの専用ページへ進む。各ページに再生回数と実聴時間の比較バーを各50位まで表示し、幅が十分なら2列、狭ければ1列にする。行から曲一覧・再生・キュー追加を維持する。

曲のアートワークは既存CachedArtwork／ArtworkCacheを使用。Artist／Album／Genreは対象曲のID順で画像ありの先頭曲（なければ先頭曲）を固定選択する。未再生曲も代表選択のmembershipへ含め、同じ曲集合なら期間・指標変更で画像を変えない。画像未取得は既存music.note fallback。画像抽出の全曲事前実行や乱数は追加しない。

ランキング用集計はAnalyticsService.rankingPageがMainActor外で行い、完成した上位50件だけを表示する。バー値・合計・代表IDを保持し、SwiftUI描画時に全曲を再集計しない。Albumは既存ライブラリと同じアルバム名単位へ統一し、異なるTrack Artistで分割しない。用途除外と期間集計の契約は維持する。

ランキング画面版Release 20261004235246を正式配置へ更新・起動成功。XCTest 136件（3 skip）、Swift Testing 85件、Debug／Release build成功。実画面で専用ページ入口とArtistの画像・比較バーを確認。詳細: sessions/2026-10-04-ranking-artwork-pages.md。
