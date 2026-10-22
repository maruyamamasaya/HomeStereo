# このMacの状態監視と診断

- HomeStereo側への明示依頼により実装。開始時の既存未コミット変更は保持した。
- SystemAudioPlayerに匿名snapshotとstall通知カウントを追加。既存pollingから準備／待機／再生／失敗を反映し、診断JSONへ状態変化・位置停滞／復帰を記録する。Pause／Stop／sleep／seek・generation切替を保護した。
- 設定項目、DLNA送信経路、出力routing、音源変換は追加／変更していない。
- 新規test: 待機→再生→stall待機→復帰→失敗、明示pause／stop、診断重複抑制・匿名性・SOAP非呼出、位置停滞判定。
- 検証結果は下記へ追記する。初回swift testはsandboxの既定module cache書込で失敗し、cacheを/tmpへ変更した。Swift 6のnotification捕捉errorはUUID照合へ修正した。
- Bluetooth実機、音響的な途切れ、出力切替は未検証。診断はOS出力後の電波損失を断定できない。監視は既存1秒pollingの分解能。

## 検証結果

- 最終 `./scripts/verify.sh` 成功（sandbox外の許可済み実行）。XCTest 145件・3件skip・失敗0、Swift Testing 92件成功、macOS Debug `BUILD SUCCEEDED`。
- 初回sandbox内の全体testはApplication Support書込とsecurity-scoped bookmarkの環境制限で既存2件が失敗。権限を確保した標準検証で解消した。最終実行は待機中キューの開始・保持・一時停止とDLNA非干渉の追加testを含む。
- バッファ待機をローカルの有効なPlay要求としてQueueStoreへ渡し、開始失敗扱い・現在項目の喪失・toggle時の再読込を防止。既存の未コミットQueueStore変更は保持。
- `git diff --check`成功。専用lint設定はなく標準検証を使用。物理Bluetooth／音声出力の試聴、Release配置は未実施。
- iOS／Simulator／xcodebuild testは未実行。macOSのswift testのみ。test端末の作成0／削除0、XCTestDevices容量は確認時12Kで変化なし（UUID folderなし）。DerivedData削除は行っていない。

## Release配置

- 明示依頼で `./scripts/deploy-macos.sh` を実行し、現在の未コミット作業ツリーを含めてRelease build成功。
- `/Applications/HomeStereo.app`へ配置し起動。build `20261022132817`、bundle `jp.local.HomeStereo.Beta`。
- ad-hoc署名検証とbuild成果物／配置先の実行ファイルSHA-256一致をscriptで確認。SHA-256 `73d24db57102fd59abac4fd6151d5e1e6f4858b2b0b7c826cef8d798c07f7681`。
- process 98413が正式pathの実行ファイルで起動していることを確認。専用scriptによるAnalyzer確認・更新、一時build・旧bundle整理も完了。
- この配置作業ではtest未実行、test端末作成／削除0。Bluetooth出力選択・試聴は利用者が実施する。システム出力設定や再生開始の操作は行っていない。
