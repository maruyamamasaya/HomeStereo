# Operations

## Run

1. MacとWireless Stereo構成済みSRS-HG1を同じLANへ接続する。
2. `HomeStereo.xcodeproj`を開き、`HomeStereo` scheme／My Macを実行する。
3. ローカルネットワーク利用を許可し、「デバイス」で再検索する。
4. 単体Renderer、またはSRS-HG1／HG10の両方が見つかったときに表示される「Sonyステレオ」を選び、曲を選ぶ。

環境変数、外部account、DB setupは不要。CLIは次で使える。

```sh
swift run home-stereo --renderer <renderer-ipv4> --file '/absolute/path/to/audio-file'
```

## Local macOS Install

このMacだけで使うRelease版は、ad-hoc署名でbuildして`/Applications`へ配置する。公開配布用のDeveloper ID署名やnotarizationは行わない。手作業の`ditto`は既存bundleへ古いファイルを残す可能性があるため、必ず専用scriptを使う。

```sh
./scripts/deploy-macos.sh
```

scriptは次を一連で行う。

1. 名前が`HomeStereo`の実行中processをすべて通常終了し、終了できなければ配置を中止する。
2. 同じbundle identifierの非正式copyをLaunch Servicesから解除し、XcodeのDebug build成果物をcleanする。
3. 固定のDerived Dataを`clean build`し、時刻由来の一意な`CFBundleVersion`を付ける。
4. 署名とbundle identifierを検証したbundleをstageし、`/Applications/HomeStereo.app`をbundle単位で置き換える。失敗時は旧bundleを復元する。
5. 配置先の署名、build番号、実行ファイルSHA-256をbuild成果物と照合する。
6. 一時buildと旧bundleを削除・登録解除し、Launch Servicesへ正式配置だけを再登録して、その絶対pathから起動する。

起動しない場合は`./scripts/deploy-macos.sh --no-launch`を使う。現在のbundle identifierは`jp.local.HomeStereo.Beta`で、Library databaseや設定は同じidentifierのまま引き継ぐ。XcodeからDebug版を実行すると、固定済みの`/Applications`版とは別processとしてDockに一時的な2個目のアイコンが出る。通常利用ではXcodeの実行を停止し、`/Applications/HomeStereo.app`だけを起動する。

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
  --test-volume 2 \
  --left-delay 0 --right-delay 0 \
  --timeout 8 --http-port 9876 --hold 600
```

`--test-volume`は0〜10だけを許可し、Play前に左右へ設定して読戻し値が一致しなければ再生しない。音を出さず音量とTransport状態だけ確認する場合は`prepare-pair --left SRS-HG1 --right SRS-HG10 --test-volume 2`を使う。`--left-delay`と`--right-delay`は-5000〜5000ms。小さい側を基準に、相対差だけ大きい側のPlay送信を遅らせる。これは音響開始を保証せず、固定ファイル同期評価用である。

Phase 3の極小クリック音源とlocalhost Web UI:

```sh
./scripts/sony-stereo-bridge-sync-click.sh /tmp/sony-stereo-bridge-sync 4 1
./scripts/sony-stereo-bridge-web.py
```

ブラウザで`http://127.0.0.1:9875`を開く。クリック音源はピーク-50.5dBFS。UIのテスト音量は既定2/100で、Play前に左右へ設定・読戻し確認する。Stopは実行中process groupの終了に加えて左右へUPnP Stopを送り、両方の`STOPPED`を確認する。Web serverはloopbackだけへbindし、外部公開しない。

Phase 4のBlackHole入力確認（Sonyへは送信しない）:

```sh
swift run sony-stereo-bridge audio-probe --output /tmp/sony-stereo-bridge-audio-probe.json
swift run sony-stereo-bridge capture-segments \
  --device BlackHole --output-dir /tmp/sony-stereo-bridge-realtime \
  --duration 5 --segment-seconds 1 \
  --left-channel 1 --right-channel 2 --buffer-frames 1024 \
  --output /tmp/sony-stereo-bridge-capture-report.json
```

Web UIの`Realtime Input`も同じcaptureだけを実行する。speaker volume、macOS既定入出力、Audio MIDI設定は変更しない。Audio Hijack block構成は[`docs/sony-stereo-bridge/audio-hijack-setup.md`](docs/sony-stereo-bridge/audio-hijack-setup.md)を参照する。

LEFT ONLY／RIGHT ONLY確認後は、Web UIの安全確認checkboxを入れて`Play Captured Segments`を使う。CLIでは`play-capture`に`--confirm-routing --confirm-low-volume --test-volume 2`を指定する。無音または既定で-6dBFSを超えるcaptureは拒否する。これは短いsegmentのgap／同期評価用であり、連続streamではない。

## Permissions

- App Sandbox
- User Selected File: Read/Write（標準保存panelのJSON書き出し用。音源は実装上読み取り専用）
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
- Pause失敗: 検証したHG1／HG10はUPnP 701でPauseを拒否する。HomeStereoは停止確認付きStopへfallbackし、再開位置は保持しない。
- Sonyステレオが表示されない: SRS-HG1とSRS-HG10の両方がAVTransport付きで検出されているか確認し、再検索する。
- Sonyステレオの最初の再生が遅い: 選曲直後とQueue再生中の次曲を先行変換する。先読み前に再生した直接選曲は左右WAV生成完了まで待つ。同一音源・設定の直近2件は再利用する。
