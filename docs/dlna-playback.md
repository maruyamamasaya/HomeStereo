# DLNA Playback Phase 1

## 現在の範囲

これはMyMusic本体から独立したmacOS向け検証パッケージである。MyMusicのiOS再生、Queue、History、Now Playing、Visualizer、Playback Session、UIには統合していない。Phase 1ではMac上にローカル保存済みの1曲をHTTP公開し、既知IPのSRS-HG1へ再生指示する。

```text
iCloud Drive（事前にMacへダウンロード済み）
  -> HomeStereo Phase 1 HTTP server
  -> SRS-HG1がHTTP GET / Range GET
  -> HG1本体がデコード・再生
```

iCloudからの直接配信、Macのオーディオ出力転送、トランスコード、L/R別ストリーム送信は行わない。

## 実測した機器構成（2026-09-23）

| IP | Friendly Name | Model | UDN |
| --- | --- | --- | --- |
| 192.168.0.54 | L soundbar | SRS-HG10 | `uuid:00000000-0000-1010-8000-e037bfd95be2` |
| 192.168.0.105 | R soundbar | SRS-HG1 | `uuid:00000000-0000-1010-8000-8c579b23386c` |

両方とも`MediaRenderer:1`、`AVTransport:1`、`RenderingControl:1`、`ConnectionManager:1`を広告した。Sony固有のGroup、MultiChannel、ScalarWebAPIサービスも存在する。L側は筐体名の想定と異なりDescription上の`modelName`が`SRS-HG10`なので、将来の自動探索では`SRS-HG1`との完全一致だけで除外しないこと。安定識別子にはIPではなくUDNを用いる。

実測Control URLは両方ともDescription URLを基準とする相対URLだった。本実装は文字列を固定せず、XML内の`serviceType`を選び、Description URLに対して解決する。

R側へのPhase 1実機試験では、MacのLAN address `192.168.0.35` とTCP 8765を確保し、HG1が音源URLへ`HEAD`、`HEAD`、`GET`の順でアクセスした。`SetAVTransportURI`と`Play`はいずれもHTTP 200を返し、ユーザーがR側から音が流れたことを確認した。その後ユーザーがHG1本体の電源を切ったため、続けて送った`Pause`と`Stop`はUPnP error 701、`GetTransportInfo`は`NO_MEDIA_PRESENT`だった。これはPause/Stop機能の成否判定には使用せず、未評価として残す。

## SSDPとDevice Description

Phase 1 CLIは既知IPを引数に取るが、Descriptionのパスやポートは決め打ちしない。`urn:schemas-upnp-org:device:MediaRenderer:1`にM-SEARCHし、応答元IPが指定IPと一致するレスポンスの`LOCATION`を使用する。そのXMLからFriendly Name、Manufacturer、Model、UDN、AVTransport、RenderingControlを抽出する。

Phase 3ではこの探索結果を全件保持し、UDNをrenderer IDとしてUI非依存のdestinationモデルへ渡せる。

## HTTP Streaming

- TCP 8080は予約済みとして使用しない。調査時点でNodeが実際に8080を待受中だった。
- LAN到達経路からMacのIPv4アドレスを決定し、そのアドレスだけへbindする。`localhost`はHG1へ渡さない。
- 8765を第一候補とし、bindに失敗したら既存プロセスを停止せず8766以降を試す。
- 実際にbindできたportを`TrackHTTPServer.port`へ保持し、そのportから音源URLを生成する。
- URLは`/tracks/<opaque UUID>?token=<random token>`。ファイルパスは公開せず、登録した単一ファイル以外を取得できない。
- `GET`／`HEAD`、`Content-Type`、`Content-Length`、`Accept-Ranges`、単一byte range、`206`、`Content-Range`に対応する。
- UPnP IGD操作やルータのport mappingは行わない。

対応MIMEはMP3、M4A/MP4/ALAC、AAC、FLAC、WAV、AIFF。これはHTTP配信対応であり、実際のデコード可否はHG1のfirmwareと音源仕様に依存する。未対応時のトランスコードはPhase 1に含まない。

## UPnP AVTransport

起動時にDIDL-Lite metadataと実際のHTTP URLを`SetAVTransportURI`へ渡し、その成功後に`Play`する。対話コマンドとして`Pause`、`Stop`、`Seek(REL_TIME)`、再`Play`、RenderingControlの`SetVolume(Master)`も利用できる。SOAPActionとservice typeは取得したService Descriptionを使う。

## Wireless Stereo

現時点で2台はそれぞれRendererとして応答し、Friendly Name、UDN、IPが異なる。Wireless Stereo状態で代表Rendererがどちらか、両方が見え続けるか、Group／MultiChannel情報がどう変わるかは未確認である。本ツールは1台だけへURIを渡し、L/Rへ別々の音声を送らない。Wireless Stereoの前後で同じ診断を再実行し、IP、Friendly Name、UDN、Device Type、全Service、AVTransport URL、RenderingControl URLを比較する。

## macOS権限

Swift PackageのCLIにはApp Sandbox entitlementはない。将来macOS Appへ組み込む際はLocal Network利用説明、outgoing network、incoming network、multicastのsandbox entitlementを実機確認する。今回MyMusic本体のentitlementやproject設定は変更していない。

## デバッグ

```sh
swift test
swift run home-stereo --renderer 192.168.0.105 --file '/absolute/path/to/song.m4a'
```

ログは`[DLNA]` prefixで、SSDP開始、機器検出、Description読込、AVTransport抽出、選択port、SetURI、Play、renderer HTTP応答、HG1からのHTTP request、Rangeを出力する。SOAP bodyやtokenは常時ログに出さない。

## 手動実機チェックリスト

- [x] 192.168.0.54へ疎通可能
- [x] 192.168.0.105へ疎通可能
- [x] Device Description取得成功
- [x] AVTransport取得成功
- [x] MacのHTTP音源URLへHG1からアクセス
- [x] 1曲再生成功（R soundbar / MP3 44.1kHz 128kbps）
- [ ] Pause成功
- [ ] Resume成功
- [ ] Stop成功
- [ ] Queue Next成功（Phase 1範囲外）
- [x] SSDPで既知IPを検出
- [ ] IP変更後も再検出できる（Phase 3）
- [ ] Wireless Stereo状態で再生できる（Phase 4）
- [ ] L/R両方から正しくステレオ再生される（Phase 4）

## 既知の制約と次段階

- Phase 1は1曲・1rendererのみ。Queueや状態polling、GENA、UIはない。
- HG1の実HTTP取得と音出しはR側のMP3で確認済み。FLAC、M4A/ALAC、WAV、AIFFの実機対応は未確認。
- 次は電源ONを維持した実機試験でPause、Resume、Stopを確認してからTransportInfo、PositionInfo、Volume取得を追加する。
- その後にSSDP全件探索、UDNベースの永続識別、Wireless Stereo状態比較へ進む。
- MyMusic本体へのPlaybackDestination統合は、それらが安定した後の別Phaseとする。
