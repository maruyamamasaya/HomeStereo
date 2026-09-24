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
- 同一path、rename、同一folder内移動、missing復帰、同サイズ別曲、曖昧metadata、参照ID維持
- schema v5→v6 migration、path／Track ID transaction rollback

2026-09-24時点で通常test 63件（XCTest 31件＋Swift Testing 32件）は成功。20,000曲性能testは環境変数で明示実行する。

macOS UIはKeyboard、VoiceOver、Light／Dark、Reduce Motion、狭いwindow、drag & dropをREADMEに沿って手動確認する。物理UI操作を実施していないrunでは自動test成功を手動確認済みとして扱わない。

## Manual SRS-HG1

READMEと[`docs/practical-audit-2026-09-24.md`](docs/practical-audit-2026-09-24.md)の手順を実施し、発見結果、全service、HTTP request、SOAP error、Wireless Stereo L/R出力を記録する。物理機器未接続なら未検証とする。

## Sony Stereo Bridge

2026-09-24に実機で両モデルのprobe、HG1単体5秒PCM WAV、HG1/HG10別8秒PCM WAVを確認した。HTTP取得、SOAP 200、Transport／Position進行を成功条件とした。実際の左右定位、ms単位の開始差、10分driftは自動test成功で代替せず、[`docs/sony-stereo-bridge/synchronization.md`](docs/sony-stereo-bridge/synchronization.md)へ手動結果を記録する。
