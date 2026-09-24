# Operations

## Run

1. MacとWireless Stereo構成済みSRS-HG1を同じLANへ接続する。
2. `HomeStereo.xcodeproj`を開き、`HomeStereo` scheme／My Macを実行する。
3. ローカルネットワーク利用を許可し、「デバイス」で再検索する。
4. Rendererを選び、「再生」で1ファイルを選ぶ。

環境変数、外部account、DB setupは不要。CLIは次で使える。

```sh
swift run home-stereo --renderer <renderer-ipv4> --file '/absolute/path/to/audio-file'
```

## Sony Stereo Bridge PoC

読み取り専用の実機能力probe:

```sh
swift run sony-stereo-bridge probe --timeout 8 --output /tmp/sony-stereo-bridge-probe.json
```

ステレオ音源を左右PCM WAVへ分離し、要求どおりHG1をLEFT、HG10をRIGHTとして再生する:

```sh
./scripts/sony-stereo-bridge-split.sh '/absolute/path/to/input.flac' /tmp/sony-stereo-bridge

swift run sony-stereo-bridge play-pair \
  --left SRS-HG1 --left-file /tmp/sony-stereo-bridge/left.wav \
  --right SRS-HG10 --right-file /tmp/sony-stereo-bridge/right.wav \
  --left-delay 0 --right-delay 0 \
  --timeout 8 --http-port 9876 --hold 600
```

`--left-delay`と`--right-delay`は-5000〜5000ms。小さい側を基準に、相対差だけ大きい側のPlay送信を遅らせる。これは音響開始を保証せず、固定ファイル同期評価用である。

## Permissions

- App Sandbox
- User Selected File: Read Only
- Outgoing Connections (Client)
- Incoming Connections (Server)
- `NSLocalNetworkUsageDescription`

HTTP serverはRendererへの経路上のLAN IPv4へbindし、8765から空きportを探す。8080、localhost、router port mappingは使わない。

## Troubleshooting

- 見つからない: 電源、NETWORK表示、同一SSID/LAN、AP isolation、VPN、multicast filteringを確認。
- Description失敗: 一覧のLOCATIONへMacから到達可能か確認。
- AVTransportなし: 診断を保存し、別方式へfallbackしない。
- HTTP取得なし: macOS firewall、incoming entitlement、Mac/Renderer間の到達性を確認。
- SOAP失敗: 画面のaction、HTTP status、UPnP code、descriptionを記録。
- macOS GUIでL/R別Rendererのみ: GUIは個別同期再生を実装しない。独立PoCは`sony-stereo-bridge play-pair`を使う。
