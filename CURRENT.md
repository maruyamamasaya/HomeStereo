# Current State

HomeStereoは、Mac上で選択した1音源をLAN内DLNA RendererへHTTP配信し、UPnP SOAPで操作するmacOS 14以降向け技術検証である。MyMusicとは独立し、AirPlayやMacローカル再生は現行Xcode targetで使用しない。

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
- media key／MPRemoteCommandCenter、Now Playing、MenuBarExtra
- sleep／wake・network監視、UDN再発見、有限backoff、明示的な再開確認
- FSEvents変更監視、debounce、自動差分scan、sleep停止／復帰scan
- schema v1 JSON Export／preview／transactional Import、Track hint照合、rollback
- MyMusic連携用の曲一覧v1、Preferences v2、Playback Events v1を独立文書として扱うCodable DTO、全体検証、JSON非依存交換model、Import／Export service
- SQLite schema v9のMyMusic外部Track ID対応、Preferences、互換Playback Events永続化。実再生Session、位置差分による実聴時間、終了理由判定、未連携eventの保持とexport時の遅延解決に対応
- 管理Sidebarの「MyMusic連携」から3種類のJSONを個別にPreview／確認Importし、標準保存panelへExportする手動連携画面
- 20,000曲fixture計測、DB index／未変更upsert省略、150件段階表示、検索debounce、Artwork downsample
- generation ID、古いpolling破棄、終端位置を含む完走判定、操作直列化、有限SOAP read retry
- Renderer側の外部曲変更検知、通信失敗時のunknown同期、旧HTTP serverのgrace period
- 再生中のidle sleep抑止、匿名化された有限件数の診断JSON Export
- 曲／Album／Artist／Playlistの複数選択、Queue／Playlistへのdrag & dropとcontext menu
- Queue Inspector、小型プレイヤーWindow、window／Sidebar／Inspector状態復元
- 用途別SidebarとArtwork／基本操作／出力先を備えた常設Now Playingバー
- 幅820pxを基準にしたメインWindowと、狭い幅では2段になるRenderer選択付きNow Playingバー
- スピーカー選択から曲選択へ進む初回ガイドと、無効な再生操作の理由表示
- Queue曲／直接ファイル／Renderer変更を統合するNow Playing表示modelと6状態表示
- 行内再生と選択曲メニューを備えた曲一覧、検索件数と検索0件の専用表示
- 曲一覧にジャンル、年、形式・ビットレート・サンプルレート、サイズ、ファイルパスを表示。metadata schema v3の再スキャンでジャンル、年、ビットレートを取得し、SQLite schema v8へ保存
- Artworkグリッドのアルバム一覧と、Artwork／主要操作／曲番号を備えたアルバム詳細
- Artworkグリッドのアーティスト一覧と、アルバム単位の収録曲／全曲再生／Shuffleを備えたアーティスト詳細
- Artwork付きのお気に入り／再生履歴と、再生中・利用不可・空・エラー状態の非モーダル表示
- 再生済み／再生中／次／その後を区別し、並べ替えと「次に再生」へ集中した再生キュー
- 代表Artwork、曲数、合計時間、利用不可件数を備え、作成／名称変更／管理操作をToolbarへ整理したプレイリスト
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
- XCTest 60件中59件成功＋任意実行の性能test 1件skip、Swift Testing 64件成功、ad-hoc署名Debug build
- このMac向けad-hoc署名Release版を、実行中copyの終了、clean build、bundle単位の置換、署名・build番号・SHA-256照合、一時成果物削除を行う`./scripts/deploy-macos.sh`で`/Applications/HomeStereo.app`へ一意に配置

## Known Issues

- SRS-HG1／HG10はAudio Hijack経由のL/R WAV分離とsegment配信まで確認済みだが、物理的な左右定位、segment境界のgap／click、音響開始差とdriftは未検証。
- 実機では両RendererともPauseをHTTP 500／UPnP 701で拒否し、再生を継続する。HomeStereoはこの場合、確認付きStopへfallbackするため一時停止位置は保持しない。
- 標準UPnP Device DescriptionだけではSony Wireless StereoのL/R構成を確定できず、アプリでは未確認として扱う。
- Sonyステレオ出力はfriendly nameどおりHG10（L soundbar）=LEFT／HG1（R soundbar）=RIGHTへ明示割り当てする。アプリ内分離と2台への指示は実装済みだが、開始差・長時間driftは引き続き調整対象。
- Sony独自`MultiChannel:1`は両機ともSTEREO対応を広告するが、PairIDはHG10=`BarLow1`、HG1=`PasLow1`。`X_Start(STEREO)`はUPnP 816で拒否され、状態は両方`IDLE / NONE`のまま。異機種間のSonyネイティブ同期は利用できない。
- アプリ管理ステレオは既定の「安定優先（48kHz／16-bit PCM）」と「ハイレゾ維持（元sample rate／24-bit PCM）」から選べる。どちらも事前通信、SetURI読戻し、両側準備完了後Playを行う。
- 遅延設定は1ms単位の48kHz系基準値1つに集約し、44.1kHz系は基準値×11/12を0.1ms単位へ丸め、倍レートごとは基準値を加算する。標準108msでは実測値の44.1kHz系=99ms／48kHz系=108msとなり、倍レートごとに+108msする。前回の読取sample rateと総適用遅延も0.1ms単位で表示する。
- 安定優先48kHzのsample rate変換で変換器への入力供給が失敗していた問題を修正し、44.1／48／88.2／96／192kHzから48kHz PCMへ変換できる自動テストを追加した。
- Sonyステレオ開始時は両RendererのURI一致とSTOPPED／PAUSED／PLAYING状態を3回連続確認してからPlayする。Sony実機はSetURI後のHTTP取得時点でPLAYINGへ進むため、新URIと一致していれば正常な準備完了として扱う。左右HTTP GETは共有開始ゲートで両方揃うまで待って同時解放し、片側未到達時は2秒で解除する。
- 一時的なLAN経路未確立に対してHTTP serverのlocal address解決を最大4回再試行する。Transport／Position／Volumeなど読取SOAPは一時的なtimeout・接続不能・network断を最大3回確認し、Play／Stopなど変更操作は重複防止のため再送しない。server準備はbackgroundで行いUIを停止させない。
- 接続状態にはhysteresisを設け、選択中RendererはSSDPで3回連続して見失った場合だけ選択解除する。Transport読取は2回連続失敗で初めて通信切断とし、単独のVolume読取失敗では接続状態を落とさない。Description一時失敗時もUSN由来UDNで同一性を維持する。
- 起動・手動再検索時のSSDP自体が`No route to host`などで失敗した場合は400ms間隔で最大3回自動再試行し、全試行失敗時だけアラートを表示する。
- 下部再生バーの出力先メニューはSonyステレオを独立項目として表示し、単体スピーカーとの切り替え状態を正しく示す。同じバーから1%刻みで音量を変更でき、Sonyステレオ時は左右両方へ反映する。
- Sonyステレオ選択時は下部再生バーと「再生中」画面でL/R音量バランスを調整できる。寄せた側をマスター音量に保ち、反対側を段階的に下げ、左右の実音量も表示する。
- 下部再生バーから、再生中のライブラリ曲をお気に入りへ追加／解除できる。直接開いた未登録ファイルでは操作を無効化し、理由を表示する。
- 下部再生バーから再生位置を操作できる。経過時間／総時間を併記し、ドラッグ中はpollingによる位置更新を保留して操作完了時にSeekする。
- GENAは未実装。Transport／Position／Volumeはpollingする。
- Sony Stereo Bridgeの`GetPositionInfo`は実機で整数秒粒度。ms単位の同期とdriftは外部マイクまたは聴感で別途測定が必要。
- アプリ内の遅延チェックは聴感用であり、ms値を自動測定しない。中央に締まった単音か、二重打ち／左右への広がりがあるかで調整する。

## Next Actions

1. [`docs/ui-improvement-backlog.md`](docs/ui-improvement-backlog.md)をUI改善の作業台帳として、P0から小さく消化する。
2. [`docs/practical-audit-2026-09-24.md`](docs/practical-audit-2026-09-24.md)のUNKNOWNをWireless Stereo実機で確認する。
3. 長時間・50曲以上・切断復帰・VPN／複数interfaceを実測する。
4. 1秒、2秒、5秒segmentの境界gap／clickと実音開始差を聴感または外部マイクで記録する。
5. [`docs/sony-stereo-bridge/synchronization.md`](docs/sony-stereo-bridge/synchronization.md)に沿い、開始時・1・3・5・10分の音響offsetとdriftを測定する。
