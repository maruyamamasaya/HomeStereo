# Testing

## Standard Commands

```sh
./scripts/verify.sh fast
./scripts/verify.sh
```

基礎commandは`git diff --check`、`swift test`、Xcode macOS Debug build。network変更は実機確認を追加し、自動test成功を実機成功として扱わない。

## DLNA Coverage

- SSDP response parsing、USN/LOCATION重複排除
- Device Description、presentation URL、相対service URL
- SCPD action list、ConnectionManager `GetProtocolInfo`
- SOAP envelope、fault、UPnP time
- MIME、opaque URL、HEAD、GET、Range、invalid Range、path traversal
- fake serviceを使うRendererPlaybackStore状態遷移
- 終端近傍／途中STOPPED、重複完走通知、古いgenerationの遅延応答
- 同一generation内の後着応答破棄、選択中の常時polling、Renderer消失
- command直列化、Renderer側の曲変更、read timeoutの有限retry、mutating SOAP非retry、匿名診断Export
- 再接続時のPlay／SetVolume禁止、巨大埋め込みArtworkのdecode前拒否
- 複数選択したQueue／Playlist参照の削除（音源は対象外）
- 曲一覧の昇順／降順、ジャンル絞り込み、3万候補からの100曲キュー上限、キュー単項目移動、最近再生履歴の最新1件表示
- 同一path、rename、同一folder内移動、missing復帰、同サイズ別曲、曖昧metadata、参照ID維持
- schema v5／v6／v7／v8／v9→v13 migration、拡張音源metadata round trip、path／Track ID transaction rollback
- 実FLAC fixtureのVorbis Comment（基本情報、作曲者、曲／ディスク番号）読取とformat固有metadata正規化
- MyMusic 4文書のversion、field名の`trackID`／`trackId`差、UTC日時、値域、重複ID、optional省略、内部交換model round-trip
- MyMusic Track ID対応の再読込、再Import、fingerprint／曖昧metadata照合、Preferences merge／未解決報告、Mac側Favorite／Good／Badのdirty曲限定Canonical ID Export、Import時dirty解除、Preview世代token一致時だけ送信済み化、event重複排除／platform維持、transaction rollback
- MyMusic実再生Sessionのpause／resume／seek、completed／skipped、selectionType、実Queue再生からSQLite保存、未連携eventの遅延解決export
- ローカル分析のMyMusic集計済み再生回数（未紐付け曲を含む）優先、event fallback、完走／Early Skip境界、期間集計、ランキング、入口／選択種別、Good／Bad未設定の分離、曲一覧からのMyMusic互換`±1`累積と`-10...+10`境界保存、空／不明duration、event冪等保存と集計非重複、履歴reset時のMyMusic集計／Favorite／Preference／Playlist保持、Track削除後の未解決履歴、schema v12再起動復元
- MyMusic手動Importの4文書Preview、Preferences差分Exportの対象件数／曲一覧Previewと保存成功後だけの解除、文書種別／version拒否、Preview／cancel非更新、確認後適用、二重操作防止、Previewから別Exportへの切替、適用後の画面Store再読込hook、曲単位のTrack ID／snapshot適用状況、event期間指定export／期間内未解決件数／空配列、既定file名、failed状態
- MyMusic Playlist JSONの単一／複数形式、NFCかつcase-sensitiveなrelative path、保存済みCanonical ID優先、曖昧／競合保留、部分Import、playlistID冪等更新、ローカルTrack ID非出力、snapshot除外後の参照保持、transaction rollback
- ジャンルプリセットversion 1 JSONのstrict decode／round-trip、未分類の新旧意味、順序永続化、transaction rollback、複数ジャンル／未分類／固定分類filter
- Sonyステレオの48kHz既定値、同期チェック音の16秒・約-18dBFS・48kHz PCM生成、左右同一波形、指定側へのframe単位遅延、通常曲／Queue完走非干渉
- DLNA pollingのTransport／Position並列取得、Volume間引き、3回連続失敗時のunknown遷移と成功時復帰
- Sonyステレオの選曲時先行変換、同一音源・設定cache再利用、次曲prewarm境界
- 「このMac」出力の選択、AVPlayer境界へのload／play／pause／seek、位置更新、完走通知、macOS側へ委ねる音量制御

性能testは環境変数で明示実行する。2026-09-26に30,000曲fixtureを成功し、詳細は[`docs/performance.md`](docs/performance.md)へ記録した。

2026-09-28時点で`./scripts/verify.sh`は成功。XCTest 97件中96件成功＋性能test 1件skip、Swift Testing 77件成功。macOS Debug build成功。

macOS UIはKeyboard、VoiceOver、Light／Dark、Reduce Motion、狭いwindow、drag & dropをREADMEに沿って手動確認する。物理UI操作を実施していないrunでは自動test成功を手動確認済みとして扱わない。

## Manual SRS-HG1

READMEと[`docs/practical-audit-2026-09-24.md`](docs/practical-audit-2026-09-24.md)の手順を実施し、発見結果、全service、HTTP request、SOAP error、Wireless Stereo L/R出力を記録する。物理機器未接続なら未検証とする。

## Sony Stereo Bridge

2026-09-24に実機で両モデルのprobe、HG1単体5秒PCM WAV、HG1/HG10別8秒PCM WAVを確認した。HTTP取得、SOAP 200、Transport／Position進行を成功条件とした。実際の左右定位、ms単位の開始差、10分driftは自動test成功で代替せず、[`docs/sony-stereo-bridge/synchronization.md`](docs/sony-stereo-bridge/synchronization.md)へ手動結果を記録する。

2026-09-25にピーク-50.5dBFSの4秒clickを10回再生し、Play送信差0msを10回、左右のHTTP取得と4秒完走を10回確認した。localhost Web UIは内蔵ブラウザで表示、Delay preset、1ms入力、click生成、status/log表示を確認した。AVFoundation録音入力が列挙されないため、音響offsetと10分driftは未評価のまま残す。

2026-09-25に権限付きAUHAL probeでBlackHole 2ch（96kHz、2ch、512 frames）を確認し、2秒CLI captureと5秒Web UI captureから1秒単位の左右mono PCM WAVを生成した。入力は無音で左右とも-160dBFSだったため、L/R分離やAudio Hijack互換性は成功扱いにしない。WAVは`pcm_s16le`、96kHz、mono、1.000秒を`ffprobe`で確認した。
