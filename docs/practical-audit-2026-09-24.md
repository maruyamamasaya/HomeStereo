# 実用性監査（2026-09-24）

この表はコード、fake test、Documentationを根拠にした監査結果である。`PASS`は記載した境界で自動確認済み、`UNKNOWN`はSRS-HG1、Wireless Stereo、実ネットワークまたは実ファイルが必要で未確認を表す。自動testを実機成功とは扱わない。

| 確認項目 | 判定 | 根拠と結果 |
| --- | --- | --- |
| Rendererを再生状態の正本として同期 | PASS | 選択中は停止後もTransport／Position／Volumeをpollingし、アプリの推測値ではなく応答値を反映する。後着した古いrefreshはgenerationとrefresh sequenceで破棄する。 |
| 本体ボタン／Sony Music Centerの変更 | PASS | 外部Pause／Play／Seekはpollingで反映し、Track URI変更はローカルNow Playingを解除してQueueを維持するfake testが成功。実機挙動は下記UNKNOWNに含む。 |
| STOPPED、Seek、曲終了、次曲開始 | PASS | playing/transitioning→STOPPED、同一URI、終端3秒以内を組み合わせ、generationごとに一度だけ完走通知する。途中STOPPED、重複通知、前曲の遅延応答、command直列化をfakeで確認。Queue位置変更から曲開始完了までを単一遷移として競合を抑止する。 |
| Renderer消失、IP変更、Wireless Stereo解除 | UNKNOWN | 探索結果から選択Rendererが消えた場合はUNKNOWNへ遷移しQueueを進めない。UDN再発見と有限backoffは実装済みだが、DHCP変更とWireless Stereo解除時のHG1広告変化は実機未確認。 |
| Wi-Fi、VPN、複数interface、Firewall、HTTP到達失敗 | UNKNOWN | `NWPathMonitor`で切断を検知し、HTTP bindアドレスはRendererへのrouteから選ぶ。VPN／複数interfaceでSSDP multicastがどのinterfaceから出るか、FirewallによるRenderer→Mac HTTP遮断は実環境確認が必要。 |
| HTTP bind、token、Range、path traversal | PASS | route上の単一LAN IPv4へbindし、opaque Track UUID＋一時tokenの完全一致だけを許可する。GET／HEAD／単一Range、416、traversal拒否をtest済み。絶対pathはURLに含めない。 |
| 再生中のMac sleep防止と解除 | PASS | `.idleSystemSleepDisabled` activityをPLAYINGだけで保持し、Pause／Stop／UNKNOWN／shutdownで解放する。状態遷移fakeで開始・解除を確認。 |
| 再接続時の自動再生・音量変更禁止 | PASS | 再接続はSSDP、Description再取得、GetTransport／Position／Volumeだけを行い、再生中だった場合も確認画面で待機する。UDN再接続でPlay／SetVolumeを呼ばないfake testを追加。 |
| 非対応format、壊れたmetadata、巨大Artwork | PASS | 拡張子とAVFoundation playable判定で拒否し、metadata失敗はnotice／unreadable扱い。Artworkは表示sizeへdownsampleし、48件／24 MiB cache、source 32 MiB上限を適用する。Renderer firmware固有のformat対応は実機UNKNOWN。 |
| 外付けdisk／folder一時切断 | PASS | folder解決・列挙失敗時はscan transactionを適用せず既存Libraryを保持し、access stateだけを再選択待ちにする。削除検出は正常scan完了時だけmissing確定する。 |
| SQLite migration／JSON Import rollback | PASS | migration、scan確定、backup mergeはいずれも`BEGIN IMMEDIATE`／`ROLLBACK`境界を持つ。schema v5→v6、重複によるscan失敗、JSON merge途中失敗をtest済み。 |
| 曖昧なTrack Identityの自動統合禁止 | PASS | path、file resource identifier、保守的metadataの各候補が一意な場合だけ既存IDを使い、複数候補は別Trackにする。曖昧候補、同サイズ別曲、rollbackをtest済み。 |
| 診断logの絶対path／個人情報 | PASS | export JSONは時刻、generation、action、outcome、HTTP／UPnP codeだけを含む。絶対path、機器IP、token、曲名が含まれないtestが成功。通常画面の機器診断表示はexport対象外。 |

## 監査で修正した問題

1. Renderer選択時の一度きりの同期と手動Stop後のpolling停止を修正し、選択中は外部状態を継続同期するようにした。
2. 同一再生generation内で重なったrefreshの古い応答、および再探索で選択Rendererが消えた場合の古い表示を破棄するようにした。
3. 埋め込みArtworkの直接返却を廃止し、downsample／cache経路と32 MiB source上限を常に適用した。
4. Queueの現在位置変更から曲開始までを遷移中として保護し、連続した前／次／再生操作で表示位置と実再生曲がずれる競合を解消した。

JSON契約、音源ファイル、Playlist、Favorite、履歴、Queueの永続形式は変更していない。

## 実機確認手順（UNKNOWNの解消）

1. Wireless Stereo構成で代表RendererのUDN、IP、公開serviceを記録し、MP3を開始する。本体とSony Music CenterからPause、再開、Seek、Stop、別曲選択を順に行い、2秒以内の表示同期、Queue非進行、二重開始なしを確認する。
2. 再生中にHG1を電源OFFし、Queue保持とUNKNOWN表示を確認する。電源ON後にIPが変わる条件を作り、手動再接続がUDNで同じ機器を選び、自動Play／SetVolumeを送らないことを確認する。
3. Wireless Stereoを解除・再構成し、代表UDNやservice URLの変化、L/R出力を記録する。解除中にQueueが勝手に進まないことを確認する。
4. Wi-Fi切断、VPN ON/OFF、Ethernet＋Wi-Fi併用、macOS Firewallでincoming拒否を個別に試す。RendererからHEAD／GETが届くinterfaceと、失敗時のUNKNOWN／再接続表示を確認する。
5. MP3、M4A、FLAC、WAV、巨大Artwork付き曲、壊れたmetadataの曲をQueueへ混在させ、対応曲の継続再生と警告を確認する。
6. 再生中に外付けdiskを外し、Libraryと参照が残ることを確認する。再接続・差分scan後に同じTrack IDへ戻るかを確認する。

## 次の優先課題

最優先はVPN／複数interface環境を含むSSDPとRenderer→Mac HTTP到達性の実測である。次にWireless Stereo解除・再構成時のUDN／service変化、50曲以上の連続切替、format別の実機対応表を確認する。結果がFAILになった項目だけ、再現ログを基に小さく修正する。
