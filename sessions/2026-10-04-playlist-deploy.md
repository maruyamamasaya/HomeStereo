# Playlist連携修正版の両アプリ導入

2026-10-04（日本時間15:23）。ユーザーが両方のデプロイを明示依頼。Context Guard MATCH、両Git root／statusを確認し、未コミット変更を保持して既存scriptを実行した。アプリソース・UI・署名・Bundle ID設定を追加変更していない。

## MyMusic

./scripts/check-iphone.shの実機接続・pairing・Developer Mode確認成功後、./scripts/deploy-iphone.shを実行。

- project: MyMusic.xcodeproj、scheme: MyMusic、configuration: Debug、product: MyMusic.app
- Bundle Identifier: maruyama.MyMusic
- device: Vespera / iPhone 17e
- UDID: 00008150-000C54280E33401C
- Build / Install / Launch: 全成功。起動はdevicectlのLaunched applicationで確認。

最初のsandbox内checkはCoreDeviceアクセスのtimeoutで停止したため、実機アクセスを許可した同じcheckを再実行し成功した。アプリ署名や識別子は変更していない。

## HomeStereo

OPERATIONS.mdを確認し./scripts/deploy-macos.shを実行。既存手順のAnalyzer更新、通常終了、Release build、stage、正式bundle交換、署名／hash照合、起動まで成功。

- project: HomeStereo.xcodeproj、scheme: HomeStereo、configuration: Release、product: HomeStereo.app
- Bundle Identifier: jp.local.HomeStereo.Beta
- destination: /Applications/HomeStereo.app
- Bundle version: 20261004152243
- SHA-256: 8b5d7869126c6aeac813e6c37c9843d0a69af8b98e235b6c5af458e4d70a0823
- Build / Install / Launch: 全成功。正式配置の起動後にHomeStereo processを確認。

## 制約

実データを使ったJSON往復・タグ操作・重複整理は行っていない。今回はtest再実行なし。新規test端末0、削除0。Macの既存deploy scriptが管理する一時buildのclean／削除を実行したが、MyMusicのDerivedData／利用者データ／XCTestDevicesは削除していない。両アプリとも今回の修正だけでなく作業ツリーにある既存の未コミット変更を含めてbuildした。commit／pushは行っていない。
