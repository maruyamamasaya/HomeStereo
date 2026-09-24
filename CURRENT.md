# Current State

HomeStereoは、Mac上で選択した1音源をLAN内DLNA RendererへHTTP配信し、UPnP SOAPで操作するmacOS 14以降向け技術検証である。MyMusicとは独立し、AirPlayやMacローカル再生は現行Xcode targetで使用しない。

## Current Phase

要求されたDLNA単曲再生からTrack Identityまでの実装と全体監査は完了。SRS-HG1 Wireless Stereo実機確認が残っている。

独立したSony Stereo Bridge PoCは、HG1/HG10のUPnP能力probe、HG1単体PCM WAV、2台別PCM WAVまで実機成功。音響的な初期同期と10分driftを手動評価するPhase 3で停止しており、Audio Hijack／BlackHole／ライブ配信／Web UIには進んでいない。

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
- 20,000曲fixture計測、DB index／未変更upsert省略、150件段階表示、検索debounce、Artwork downsample
- generation ID、古いpolling破棄、終端位置を含む完走判定、操作直列化、有限SOAP read retry
- Renderer側の外部曲変更検知、通信失敗時のunknown同期、旧HTTP serverのgrace period
- 再生中のidle sleep抑止、匿名化された有限件数の診断JSON Export
- 曲／Album／Artist／Playlistの複数選択、Queue／Playlistへのdrag & dropとcontext menu
- Queue Inspector、小型プレイヤーWindow、window／Sidebar／Inspector状態復元
- 用途別SidebarとArtwork／基本操作／出力先を備えた常設Now Playingバー
- 幅820pxを基準にしたメインWindowと、狭い幅では2段になるRenderer選択付きNow Playingバー
- ⌘F、Space、⌘O、参照だけを消すDelete、確認付きdestructive操作、VoiceOver補助
- folder＋relativePath、file resource identifier、保守的metadataの順で判定するTrack Identity
- rename／同一folder内移動／missing復帰時のTrack ID維持、曖昧候補の非統合、schema v6 transaction
- 選択中Rendererの常時polling、同一generation内の古いrefresh破棄、Renderer消失時のunknown同期
- 巨大Artwork source上限、常時downsample／容量上限cache
- Unit Test 63件＋性能test 1件、ad-hoc署名Debug build

## Known Issues

- 新macOS AppでのSRS-HG1探索、HTTP取得、Wireless Stereo L/R出力は未検証。
- GENAは未実装。Transport／Position／Volumeはpollingする。
- Sony Stereo Bridgeの`GetPositionInfo`は実機で整数秒粒度。ms単位の同期とdriftは外部マイクまたは聴感で別途測定が必要。

## Next Actions

1. [`docs/ui-improvement-backlog.md`](docs/ui-improvement-backlog.md)をUI改善の作業台帳として、P0から小さく消化する。
2. [`docs/practical-audit-2026-09-24.md`](docs/practical-audit-2026-09-24.md)のUNKNOWNをWireless Stereo実機で確認する。
3. 長時間・50曲以上・切断復帰・VPN／複数interfaceを実測する。
4. [`docs/sony-stereo-bridge/synchronization.md`](docs/sony-stereo-bridge/synchronization.md)に沿って開始・1・3・5・10分の同期を測定し、成功時だけAudio Hijack入力へ進む。
