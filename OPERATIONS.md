# Operations

## Local Development

必要環境はmacOS 14以降とXcode。外部packageのinstallは不要。

GUI App:

1. `HomeStereo.xcodeproj`をXcodeで開く。
2. `HomeStereo` schemeと`My Mac`を選ぶ。
3. 実行後、`⌘O`または画面のbuttonから音楽folderを選ぶ。

標準検証は`./scripts/verify.sh`を使う。DLNA CLIは次で起動する。

```sh
swift run home-stereo --renderer <renderer-ipv4> --file '/absolute/path/to/audio-file'
```

## Environment Variables

必須・任意ともに環境変数はない。renderer IPと音源pathはCLI optionで渡す。秘密情報を設定ファイルへ追加しない。

## Database / Persistent Data

DB setupは不要。Appは選択folderのsecurity-scoped bookmarkだけを`UserDefaults` key `musicFolderBookmark`へ保存する。音源をcopy、move、modifyしない。

## External Services / Network

Appのローカル再生に外部サービスは不要。AirPlay検証ではMacと対応受信機を同一networkへ接続し、受信機側のAirPlayを有効にする。

DLNA CLIはLAN内rendererへSSDP/HTTP/SOAPで接続する。Mac側はrendererへ到達するIPv4 addressへbindし、TCP 8765から利用可能なportを探す。8080は使用しない。詳細は`docs/dlna-playback.md`を参照する。

## Build / Deploy

build/検証commandは`TESTING.md`を正本とする。現在はad-hocの`Sign to Run Locally`構成で、App Sandbox、Hardened Runtime、user-selected read-only entitlementが有効。

App Store/Developer ID配布、archive upload、notarization、自動deploy、CI/CDは設定されていない。

## Troubleshooting

- folderが復元できない: 移動・削除・権限変更を確認し、folderを再選択する。
- 曲が出ない: 対応拡張子でもAVFoundationがcodec/DRM/破損を理由に除外し得る。
- 再生できない: fileの存在と読み取り権限を確認する。
- AirPlay機器が出ない: 同一network、受信機のAirPlay対応・有効状態、macOS標準UIでの可視性を確認する。推測でDLNA機能をAppへ追加しない。
- DLNAが見つからない: IP、電源、同一LAN、multicast到達性を確認し、`[DLNA]` logと`docs/dlna-playback.md`を参照する。tokenやSOAP bodyを恒常的にlogへ追加しない。
