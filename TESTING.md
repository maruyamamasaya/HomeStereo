# Testing

## Standard Entry Points

実装中の短いfeedback:

```sh
./scripts/verify.sh fast
```

完了前の標準検証:

```sh
./scripts/verify.sh
```

`fast`はdiff whitespace checkと全Swift testを実行する。defaultの`full`は同じcheck/testに加え、Xcode macOS Debug buildを実行する。外部依存は追加しない。

## Available Coverage

- Lint/format: 専用toolなし。`git diff --check`のみ
- Type/compile: `swift test`のcompileとXcode build
- Unit: AppCoreはXCTest、KitはSwift Testing
- Integration: `PlaybackStoreTests`がfake service境界まで確認
- E2E/UI: 自動testなし
- Migration/security scanner: DB/専用toolなし
- Manual: sandbox folder access、ローカル再生、AirPlay/DLNA実機

## Change-to-Validation Map

| Change type | Fast | Completion / additional validation |
| --- | --- | --- |
| Markdown only | `git diff --check`とpath/link照合 | 通常はFull不要 |
| AppCore model/store/service | Fast | Full |
| SwiftUI/App entry | Fast | Full +関連画面 |
| bookmark/entitlement | Fast | Full +folder選択・再起動復元 |
| AVFoundation/AirPlay | Fast | Full +ローカル/対応受信機 |
| HomeStereoKit/DLNA CLI | Fast | Full +対象rendererでCLI |
| Xcode/Package/verify script | Fast | Full |

対象が限定できる作業でも、現在のsuiteは短いためFastは全unit testを実行する。実機依存項目を実行できない場合は成功扱いにせず、理由をsessionへ残す。

## Underlying Commands

```sh
git diff --check
swift test
xcodebuild -project HomeStereo.xcodeproj \
  -scheme HomeStereo \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/HomeStereoDerivedData \
  build
```
