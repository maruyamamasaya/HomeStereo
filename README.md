# HomeStereo DLNA macOS Beta

Sony h.ear go系Rendererへ、Mac上で選択した音源をDLNA／UPnP経由で再生するネイティブmacOS技術検証です。単体出力に加え、L soundbar（SRS-HG10）をLEFT、R soundbar（SRS-HG1）をRIGHTとして選ぶSonyステレオ出力を備えます。ステレオ時はアプリが曲を左右のPCM WAVへ分離し、2台がMacから個別にHTTP取得します。AirPlay、`AVRoutePickerView`、Macローカル音声出力は使いません。

既存iPhoneアプリ「MyMusic」とは別製品で、コード、Bundle Identifier、DB、永続化データ、Cloudに依存しません。

## 動作環境と起動

- macOS 14以降、Xcode 26
- 外部依存なし
- Bundle Identifier: `jp.local.HomeStereo.Beta`
- `HomeStereo.xcodeproj`の`HomeStereo` schemeをMy Macで実行
- Sign to Run Locally（ad-hoc）、App Sandbox有効

権限はユーザー選択ファイルのread-only、outgoing network、incoming networkだけです。生成Info.plistにはローカルネットワーク利用説明を設定しています。インターネット上へ音源や機器情報を送信しません。

標準検証:

```sh
./scripts/verify.sh
```

## 使い方

1. SRS-HG1側でWi-FiとWireless StereoのL/R構成を完了し、Macを同じLANへ接続します。
2. アプリの「スピーカー」で再検索し、単体Rendererまたは「Sonyステレオ」を選択します。
3. Sonyステレオでは下部バーの「遅延チェック」を押し、3連クリックが中央で締まった1音に聞こえるか確認します。二重打ちや左右への広がりがあれば、停止後に「スピーカー」の遅延値／遅らせる側を調整して再確認します。
4. Device Description診断で`AVTransport`、`RenderingControl`、`ConnectionManager`を確認します。
5. 「フォルダ」で音楽フォルダを登録してscanするか、「再生中」で音源を1つ選択します。
6. 「ライブラリ」で曲を選び、再生を押します。`⌘O`でフォルダ登録、`⇧⌘O`で単曲選択、`⌘F`で検索、Spaceで再生／一時停止できます。

外観はアプリの「設定」またはメニューバーの「表示」→「テーマ」から変更できます。システム外観のほか、シンプルダーク、Living Aurora、Pulse Neon、Blue Cosmosを選べます。

再生時だけ、Rendererへ到達するMacのLANアドレスへ小さなHTTP serverをbindします。URLはopaque UUIDと一時tokenを含み、選択した1ファイルだけを`GET`／`HEAD`／byte Rangeで配信します。ファイル変更、Renderer変更、window終了で旧serverとURLを無効化します。

## 実装範囲

- SSDP `M-SEARCH`（`MediaRenderer:1`と`ssdp:all`）、USN／LOCATION重複排除
- Device DescriptionのfriendlyName、manufacturer、model、UDN、presentation URL、全service URL表示
- 相対service URLの解決
- `SetAVTransportURI`、Play、Pause、Stop、Seek、GetTransportInfo、GetPositionInfo
- GetVolume、SetVolume
- SOAP faultのaction、HTTP status、UPnP code、description表示
- SwiftUI `NavigationSplitView`の「デバイス」「再生」画面
- 複数音楽フォルダのsecurity-scoped bookmark保存、再起動復元、個別／全件再scan
- SQLite Library index、差分scan、missing保持、進捗・notice表示
- Library曲から既存の単曲HTTP／AVTransport経路への受け渡し
- 曲／Album／Artistの検索・並び替え・詳細表示（AlbumはAlbum Artist＋Album名で識別）
- 埋め込みArtworkの遅延読込と上限付きメモリcache
- 永続Queue、今すぐ／次／末尾追加、並べ替え／削除、前後移動、Shuffle、Repeat
- AVTransport完走検知による連続再生（通信失敗時は自動進行しない）
- 通常／作業用を分離したローカルPlaylistの作成／名称変更／削除、曲順編集、通常／Shuffle再生
- 曲／Album／Artist／現在QueueからのPlaylist追加、missing曲の参照保持
- M3U8 Import／Export（曖昧な相対pathは自動接続しない）
- MyMusicを正本とするCanonical Track IDとPlaylist JSONのPreview付きImport／Export
- Favorite登録／解除と通常／Shuffle再生
- 実再生時間、完走／途中停止をTrack IDで保持する再生履歴、最近／頻繁／未再生一覧
- media key／MPRemoteCommandCenterによる既存Queue操作、Now Playing同期
- 現在曲と基本操作、メイン画面表示を備えたMenuBarExtra
- スピーカー選択→曲選択→再生を案内する初回導線と、無効な再生操作の理由表示
- Queue曲と直接選択ファイルで共通のNow Playing状態（曲なし／読込中／停止中／再生中／一時停止／通信不明）
- 行内再生と選択曲操作を備えた曲一覧、Artworkグリッドのアルバム／アーティスト一覧と詳細ヘッダー
- 編集・並べ替え・JSON Import／Exportに対応したジャンル表示プリセットと、曲一覧上部のタグ型切り替え
- Artwork、再生状態、空状態を揃えたお気に入り／最近再生／よく聴く／未再生画面
- 曲順編集と「次に再生」へ集中した再生キュー、代表Artworkと概要を備えたプレイリスト
- 下部プレイヤーと再生中画面から操作できるShuffle／Repeat
- Sonyステレオの既定出力を48kHz／16-bit PCMへ統一し、現在の遅延設定を通した16秒の3連クリック同期チェックを下部プレイヤーから実行
- Artworkと再生操作を中心にした再生中画面、利用者向け表示と技術情報を分離したスピーカー画面
- sleep／wake・Wi-Fi切断検知、UDNによるRenderer再発見、有限の指数backoff
- 復帰後のTransport／Position／Volume同期と、明示確認後だけ行う再開
- 登録folderのFSEvents監視、通知debounce、未変更metadataを読まない自動差分scan
- sleep中の監視停止、wake後の安全な再scan、自動更新ON／OFFと最終更新日時
- Playlist／Favorite／履歴／設定のversioned JSON Backup、preview付きtransactional Import
- 30,000曲合成fixture、全曲Table表示、background並び替え／debounced検索、downsample Artwork cache
- 再生session generation、古いpolling破棄、終端位置を加味した重複しない曲終了判定
- Play／Pause／Seek／曲切替の直列化、read-only SOAPのtimeout時1回だけの再試行
- Renderer側の曲変更／停止／切断同期、再生中のidle sleep抑止と確実な解除
- IP、token、絶対pathを含めない診断JSONの書き出し
- 曲／Album／Artist／Playlistの複数選択、Queue／Playlistへのdrag & drop、右クリック操作
- 開閉と状態復元が可能なQueue Inspector、Artwork付き小型プレイヤーWindow
- window size／Sidebar状態復元、VoiceOver label、system文字サイズ／contrast／Reduce Motion準拠。960px級の狭い幅ではQueue Inspectorを自動退避し、文字を縮小せずメイン領域を確保
- DeleteはQueue／Playlist参照だけを対象とし、folder解除やresetを含むdestructive操作は確認後に実行
- rename／同一folder内移動／missing復帰で参照を保つ保守的Track Identity（SQLite schema v8）

View → `RendererPlaybackStore` → protocol化したService → `HomeStereoKit`／Network.frameworkの方向です。主要コードは`Sources/HomeStereoDLNAApp`、`Sources/HomeStereoDLNAAppCore`、`Sources/HomeStereoKit`にあります。

## 2026-09-24 検証結果

| 項目 | 結果 |
| --- | --- |
| Unit Test | 63件成功、失敗0＋20,000曲性能test成功 |
| macOS Debug build | 成功 |
| Sign to Run Locally | 成功 |
| 署名済みentitlement | sandbox、user-selected read-only、network client/serverを確認 |
| SRS-HG1単体への旧CLI再生 | 過去にR側／MP3で成功。詳細は[`docs/dlna-playback.md`](docs/dlna-playback.md) |
| 新macOS Appでの探索・再生 | 未検証 |
| Wireless StereoのL/R両方 | 未検証 |

Library indexは`~/Library/Application Support/HomeStereo/Library.sqlite3`に保存します。音源本体は保存・変更・移動・削除しません。対応候補はMP3、M4A、音声として読めるMP4、AAC、WAV、AIFF/AIF、FLAC、ALACです。拡張子だけで採用せず、AVFoundationが読めない候補はnoticeとして扱います。

JSON Backupの正式なschema、完全なsample、migration方針は[`docs/json-backup.md`](docs/json-backup.md)を参照してください。
性能の変更前後の測定値は[`docs/performance.md`](docs/performance.md)を参照してください。
実用性監査のPASS／UNKNOWN、修正内容、実機でUNKNOWNを解消する手順は[`docs/practical-audit-2026-09-24.md`](docs/practical-audit-2026-09-24.md)を参照してください。
段階的なUI改善の課題、優先度、完了条件は[`docs/ui-improvement-backlog.md`](docs/ui-improvement-backlog.md)を参照してください。

## Sony Stereo Bridge PoC

SRS-HG1とSRS-HG10を別Rendererとして扱う独立CLIもあります。UPnP能力probe、固定L/R WAV、極小click、BlackHole 2ch captureとsegment送信の診断に使用します。通常曲のSonyステレオ再生はmacOS GUIへ統合済みです。音響開始差と長時間driftは未評価です。

入口と現在の判定は[`docs/sony-stereo-bridge/architecture.md`](docs/sony-stereo-bridge/architecture.md)、実装経緯と未解決課題は[`docs/sony-stereo-bridge/status-and-history.md`](docs/sony-stereo-bridge/status-and-history.md)、実機能力は[`docs/sony-stereo-bridge/sony-upnp-research.md`](docs/sony-stereo-bridge/sony-upnp-research.md)、同期手順は[`docs/sony-stereo-bridge/synchronization.md`](docs/sony-stereo-bridge/synchronization.md)を参照してください。

## 実機確認

Wireless Stereo構成済みの実機で、次を順番に確認してください。

1. 2台のNETWORK表示、同一SSID/LAN、L/R割り当てを確認。
2. アプリでSRS-HG1を発見し、Device DescriptionとAVTransport URLを確認。
3. 代表Rendererが1つか、L/Rが別Rendererとして見えるかを記録。
4. MP3またはM4Aを選び、SetURI／Play後にL/R両方から正しいステレオ音声が出るか確認。
5. Pause、再Play、Stop、Seek、音量を確認。
6. アプリ終了後、同じ音源URLへ接続できないことを確認。
7. Album／Playlistを50曲以上連続再生し、曲間で二重開始がないことを確認。
8. 再生中に本体／Sony Music CenterからPause、Seek、別曲選択を行い表示とQueue維持を確認。
9. Wi-Fi切断、Renderer電源OFF、応答遅延から復帰しても自動再生・音量変更しないことを確認。
10. MP3、M4A、FLAC、WAVを再生し、非対応音源は警告後もQueueが保持されることを確認。

L/Rが別Rendererとしてしか見えない場合、AVTransportがない場合、またはRendererからMacのHTTP serverへ到達できない場合は停止条件です。独自同期や別方式へ自動fallbackしません。

## 既知の制約

- Rendererへ同時配信するのは1ファイルだけです。Queueは順次URIを更新します。MyMusic連携は手動JSON受け渡しで、自動同期は行いません。
- Track ArtistとAlbum Artistは別fieldとして扱います。metadataにAlbum Artistがない場合は補完せず「不明なAlbum Artist」と表示します。
- Track Identityは同一folder内だけで、relative path、macOS file resource identifier、file size＋duration＋codec／sample rate／bit depth／channel＋metadataの一意一致の順に判定します。曖昧候補、folder間／volume間移動は統合せず、通常scanでfull-file hashを計算しません。
- JSON Backup schema v1は変更していません。Track IDを維持できない場合も既存のrelativePath／metadata hint照合と互換です。
- 対応拡張子でもcodec、DRM、firmware仕様によりRendererが拒否する場合があります。
- GENA event subscriptionは未実装で、状態はSOAP pollingです。
- Wireless Stereo代表RendererとL/R出力は実機未確認です。
- 旧ローカル再生／AirPlay試作コードは作業ツリーに残っていますが、Xcodeの`HomeStereo` targetには含めていません。
