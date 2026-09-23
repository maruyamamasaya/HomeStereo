# HomeStereo macOS Beta

Mac上のローカル音源を再生し、Apple標準の出力先選択UIからAirPlay対応機器を選ぶための、小さなネイティブmacOS技術検証です。既存のiPhoneアプリ「MyMusic」とは別製品であり、MyMusicのコード、Bundle Identifier、Store、データベース、永続化データには依存しません。

## 動作環境と起動

- macOS 14以降
- Xcode 26で検証
- 外部依存なし
- Bundle Identifier: `jp.local.HomeStereo.Beta`

`HomeStereo.xcodeproj`をXcodeで開き、`HomeStereo` schemeをMy Macで実行します。署名は`Sign to Run Locally`（ad-hoc）で動作し、無料のApple Developerアカウントも不要です。App Sandboxは有効で、User Selected FileはRead Onlyだけを許可しています。

コマンドラインでの検証:

```sh
swift test
xcodebuild -project HomeStereo.xcodeproj \
  -scheme HomeStereo \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/HomeStereoDerivedData \
  build
```

## MVPの使い方

1. `⌘O`、ツールバー、または空状態のボタンから音楽フォルダを選びます。
2. `m4a`、`mp3`、`aac`、`wav`、`aiff`、`flac`の候補を再帰的に走査します。AVFoundationが再生可能と判断できないファイルは一覧から安全に除外します。
3. 曲をクリックすると再生します。画面下部で再生／一時停止、前後移動、seekを操作できます。Spaceでも再生／一時停止できます。
4. プレイヤーバー右端のAirPlayボタンを押し、Apple標準UIから出力先を選択します。アプリは機器を独自探索せず、自動接続もしません。

選択フォルダはsecurity-scoped bookmarkとしてUserDefaultsへ保存し、次回起動時にアクセスを復元します。音源のコピー、移動、変更、変換は行いません。

## 構成

- `Sources/HomeStereoApp`: SwiftUI画面と`AVRoutePickerView`の小さなAppKit bridge
- `Sources/HomeStereoAppCore`: Model、`PlaybackStore`、folder／library／playback service
- `Tests/HomeStereoAppCoreTests`: folder scan、拡張子、queue、bookmark境界、fake playback storeのXCTest
- `HomeStereoApp.entitlements`: App Sandboxと読み取り専用folder access

データの流れはView → Store → Service → Model / Apple Frameworkです。`AudioPlaybackServicing`、`LibraryScanning`、`FolderAccessServicing`を差し替え可能にし、ViewはAVPlayerやFileManagerを直接操作しません。`AudioPlaybackService`だけが`AVQueuePlayer`とqueueを所有し、そのplayerを`AVRoutePickerView`に関連付けます。

## 2026-09-23 検証結果

| 項目 | 結果 |
| --- | --- |
| XCTest | 成功（新MVP 9件、既存CLI 7件、失敗0件） |
| macOS Debug build | 成功 |
| Sign to Run Locally | 成功 |
| Sandbox entitlement | `app-sandbox=true`、`user-selected.read-only=true`を署名済みappで確認 |
| フォルダ選択／一覧 | 成功。一時フォルダのWAV／AIFFを表示 |
| ローカル再生 | 成功。3秒WAVで再生、一時停止、seek、次の曲、終端後の再再生、Space操作を画面状態で確認 |
| AVRoutePickerView | 成功。Apple標準の出力先ポップオーバーを表示 |
| AirPlayステレオ表示 | 未確認／未解決。検証時はローカルMac「まるま」だけを表示 |
| AirPlay中の再生／pause／seek／next | 未確認。選択可能なAirPlay機器が表示されなかったため |

AirPlay実機の最終確認では、Macと受信機を同じホームWi-Fiに接続し、受信機側でAirPlayが有効であることを確認してください。検証対象候補として以前の試作に記録されていた機器名はSony `SRS-HG1`ですが、この機器のAirPlay対応有無、現在のネットワーク参加状態、表示名は本MVPでは確認できていません。Apple標準UIに表示されない場合はAirPlay非対応、別プロトコル、またはネットワーク条件の可能性として扱い、DLNA／UPnP等を推測で追加しません。

## 既知の制約／未対応

- 対応拡張子でも、codec、破損、DRM等によりAVFoundationが読めないファイルは表示されない場合があります。
- metadataがない場合、曲名はファイル名、Artist／Albumは空欄になります。
- ファイル消失、bookmark失効、folder権限消失、再生失敗はアプリ内メッセージで説明します。
- AirPlayの実際の転送形式、sample rate、変換有無はmacOSと受信機に依存します。bit-perfect、ハイレゾ、無変換は表示・保証しません。
- Playlist、Favorite、履歴、EQ、音量ノーマライズ、クロスフェード、Visualizer、同期、Import、USB DAC直接制御、サーバー、音源変換は未実装です。
- iPhone／Watch、iCloud／CloudKit、MyMusicとの共有Package／submodule／データ同期はありません。

## 既存のPhase 1 CLIについて

着手時に存在したDLNA実機検証CLIは、無関係な既存コードを壊さないため`HomeStereoKit`／`HomeStereoCLI`として温存しています。新しいmacOS Appからは一切参照せず、製品機能にも含めていません。旧CLIの資料は[`docs/dlna-playback.md`](docs/dlna-playback.md)にあります。
