# Current State

HomeStereoは、Mac上で選択した音源をLAN内DLNA RendererへHTTP配信してUPnP SOAPで操作するか、macOSのシステム出力でローカル再生するmacOS 14以降向け技術検証である。MyMusicとは独立する。

## Current Phase

要求されたDLNA単曲再生からTrack Identityまでの実装と全体監査は完了。SRS-HG1／HG10の探索、低音量固定ファイル再生、再生中Stop、Audio Hijack経由のL/R分離と1秒segment送信まで実機確認済みで、音響同期と長時間driftの確認が残っている。

独立したSony Stereo Bridge PoCは、HG1/HG10のUPnP能力probe、固定L/R PCM WAV、極小クリック10回のcommand timingまで実機成功。Phase 3 Web UIと1ms単位Delayに加え、BlackHole 2chのAUHAL probe／PCM取得／固定長L/R WAV segment、安全確認後のsegment順次送信経路を実装した。Music→Audio Hijack→BlackHoleのLEFT ONLY／RIGHT ONLY分離と、音量5/100でのHG1=LEFT／HG10=RIGHT各1秒segment送信を実機確認した。音響同期、10分drift、ライブHTTPは未評価。

Audio Hijackの`Sony Stereo Bridge - BlackHole`はMusic→Channels（No Change）→BlackHole 2ch、全ブロック有効、Output 2%、Auto Run Off、Stoppedまで設定済み。LEFT ONLYは左−54.0dBFS／右−160dBFS、RIGHT ONLYは左−160dBFS／右−54.0dBFSで、反転・漏れ・clippingなしを確認した。検証済みsegmentは音量5/100で両RendererがHTTP GET、Play、1秒完走、`STOPPED`まで成功した。詳細な現在地と課題は[`docs/sony-stereo-bridge/status-and-history.md`](docs/sony-stereo-bridge/status-and-history.md)を正本とする。

## Implemented

- SSDP全件探索、重複排除、Device Descriptionとservice URL解析
- 単一ファイルのtoken付きHTTP配信（GET/HEAD/Range）
- AVTransport／RenderingControl SOAP操作と診断
- `NavigationSplitView`のデバイス／再生UI、`⌘O`、Space
- sandbox read-only file access、network client/server entitlement
- 複数folder bookmark、SQLite index、差分scan、missing／notice／進捗、LibraryからDLNA単曲再生
- 検索／sort可能な曲・Album・Artist画面、詳細収録曲、上限付きArtwork cache
- 永続Queue、編集、前後移動、Shuffle／Repeat、AVTransport完走連携
- ローカルPlaylist、順序編集、missing参照保持、M3U8 Import／Export
- Favorite、完走／途中停止を含む再生履歴、最近／頻繁／未再生一覧
- Sidebarの「分析」で、概要、上位曲、日別event履歴、理由付き傾向、FavoriteとGood／Bad別の完走／Skip傾向を端末内だけで集計・表示する。schema v12でMyMusic Library JSONの`playCount`全件を紐付け不能曲も含めた正本として保存し、総再生回数・曲別回数・ランキングへ使う。期間別回数・再生時間・完走／Skip率はraw eventから集計し、履歴削除はMyMusic集計、Preference、Playlist、曲情報を維持する
- 分析の再生履歴ではPlayback Events JSON既存の`platform`を使い、MyMusicアプリ由来を「App」、HomeStereo由来を「Mac」と曲ごとに表示する。Library JSONのみの累計値は再生元を判定しない
- media key／MPRemoteCommandCenter、Now Playing、MenuBarExtra
- sleep／wake・network監視、UDN再発見、有限backoff、明示的な再開確認
- FSEvents変更監視、debounce、自動差分scan、sleep停止／復帰scan
- schema v1 JSON Export／preview／transactional Import、Track hint照合、rollback
- MyMusic連携用の曲一覧v1、Preferences v2、Playback Events v1を独立文書として扱うCodable DTO、全体検証、JSON非依存交換model、Import／Export service
- SQLite schema v10のMyMusic Canonical Track ID、snapshot在籍状態、Canonical Playlist ID、Preferences、互換Playback Events永続化。実再生Session、位置差分による実聴時間、終了理由判定、未連携eventの保持とexport時の遅延解決に対応
- 管理Sidebarの「MyMusic連携」からLibrary／Playlist／Preferences／Playback Eventsの4種類を個別にPreview／確認Importし、標準保存panelへExportする手動連携画面
- 管理Sidebarの「MyMusic適用状況」で全HomeStereo曲のローカルTrack ID、MyMusic TrackID、snapshot在籍、照合方法、Library JSON出力可否、Preferences／Events／MyMusic Playlist適用を曲単位で確認可能。Playlist／Preferences Import後は対応する画面Storeを即時再読込する
- 管理Sidebarの臨時「開発者」で、MyMusic向け4種類のJSONを現在値から生成または既存ファイルから開き、文書設定と曲／イベント／プレイリストを1件ずつ表形式で編集して、形式検証後に別ファイルへ書き出せる。編集はSQLiteへ反映しない
- MyMusic Playlist JSON v1の単一／複数形式、Canonical Track ID完全一致による部分Import、playlistID単位の冪等更新、MyMusic未接続曲を除外するExport。`kind`を維持し、通常と作業用をSidebarの別画面へ分離する。作業用曲は再生時間で推測せずgenreの「作業用BGM」だけで判定する
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
- Queue Inspectorは初回起動時に開いた状態とし、Toolbarから閉じた状態も以後復元する。キュー全消去の管理メニューは非表示。
- 曲一覧とアルバム／アーティスト詳細は、行のシングルクリックでは選択だけを行い、ダブルクリックで現在再生を変えずキュー末尾へ1回追加する。行とは独立した再生ボタンだけが現在曲へ割り込み、元の再生を終了してクリック曲を現在位置の直後へ挿入し、既存の待ち曲を保持したまま1段下げる。
- 曲一覧の左端には、今すぐ再生、キュー末尾へ追加、追加先を選べるプレイリストメニュー、お気に入り、MyMusic互換のGood／Badボタンをコンパクトに並べる。Goodは1クリックごとに`+1`、Badは`-1`し、`-10...+10`で上限・下限を設けてSQLiteへ保存する。正のGood／負のBadには現在の強度を小さなバッジで表示する。
- 用途別SidebarとArtwork／基本操作／出力先を備えた常設Now Playingバー
- 設定または「表示」メニューから、システム／シンプルダーク／Living Aurora／Pulse Neon／Blue Cosmosを選択し、端末内へ保存できるテーマ設定。GitHub `maruyamamasaya/living-aurora-ui` commit `7138d4a…`のtokenと光を面として扱う設計をmacOS向けに縮小し、Reduce Transparency／increased contrastでは装飾光を外す
- 1280×760pxを初期値とし、1920×1080の全画面から960×540級までを対象にしたメインWindow。狭い幅ではQueue Inspectorを自動退避してメイン領域を確保し、ToolbarからQueue画面へ移動できる。短い高さではSidebarのセクション見出しだけを省略して全項目を表示する。Renderer選択付きNow Playingバーは文字を縮小せず幅に応じて2段になる
- スピーカー選択から曲選択へ進む初回ガイドと、無効な再生操作の理由表示
- Queue曲／直接ファイル／Renderer変更を統合するNow Playing表示modelと6状態表示
- 行内再生と選択曲メニューを備えた曲一覧、検索件数と検索0件の専用表示
- 曲一覧の全件表示、曲名／アーティスト／アルバム／ジャンル／年／時間ヘッダーの昇順・降順、ジャンル絞り込み。音質／サイズ／ファイルパスは初期非表示とし、「表示項目」から個別に表示して選択状態を保存できる
- Sidebarの「ジャンルプリセット」で、複数ジャンルと「ジャンル未設定」をまとめたプリセットを作成・編集・削除・並べ替えできる。SQLite schema v13で順序を永続化し、曲一覧上部のタグから即時適用する。iPhone互換の`mymusic.genre-display-presets` version 1 JSONを厳格検証してImport／Exportする
- 曲一覧の任意列に形式・ビットレート・サンプルレート、サイズ、ファイルパスを表示。metadata schema v3の再スキャンでジャンル、年、ビットレートを取得し、SQLite schema v8へ保存
- FLACのVorbis Commentをformat固有metadataから正規化し、タイトル、アーティスト、アルバム、アルバムアーティスト、ジャンル、年、作曲者、曲番号／総曲数、ディスク番号／総ディスク数を取得。metadata version 5で既存曲も再スキャン
- Artworkグリッドのアルバム一覧と、Artwork／主要操作／曲番号を備えたアルバム詳細
- Artworkグリッドのアーティスト一覧と、アルバム単位の収録曲／全曲再生／Shuffleを備えたアーティスト詳細
- Artwork付きのお気に入り／再生履歴と、再生中・利用不可・空・エラー状態の非モーダル表示
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
- XCTest 87件中86件成功＋任意実行の性能test 1件skip、Swift Testing 77件成功、ad-hoc署名Debug build
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
