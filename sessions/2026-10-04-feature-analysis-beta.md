# HomeStereo feature analysis Beta

## 実装
- MyMusic互換JSONの取り込み・曲別詳細に、未解析／音量不足／更新対象の実行ボタン、進捗、中断を追加。
- 独立したPython companionをLaunch Services経由で起動。MyMusic repositoryを実行時参照せず、公式SHA検証モデルと専用venvを使用。
- 評価済みEffNet frontendと分類headを採用。音量はFFmpegのIntegrated LUFS／True Peak。元音源を書き換えない。
- SQLiteで段階別checkpointと実際の計算日時を保持。変更音源を検出し、再実行時の重複計算を抑制。
- このMacでの再生に音量補正toggleを追加（初期OFF、4 dB headroom）。DLNA音量補正は未対応。
- Analyzer JSONは解析version別に書き出す。生成日時はexport時刻、正確な曲別解析日時はarchive／全体snapshotに保持。

## 検証・配置
- Swift package全体: XCTest 111（2 skip）、Swift Testing 79成功。その後の修正は対象テストで確認。
- Xcode Debug／Release build成功。Python workerテスト3件成功。
- 合成音源で実ONNX推論、音量測定、NSWorkspace helper起動、cache／計算日時保持を確認。
- /Applications/HomeStereo.appへ配置・起動。build 20261004002238、Bundle ID jp.local.HomeStereo.Beta。
- git diff --check成功。既存の未コミット変更を保持。MyMusic変更なし。
- Xcode Simulator test未実施。test端末作成／削除0、既存XCTestDevicesは変更なし。

## 制約・ユーザー報告
- 2万実音源の長時間処理、iCloud未download音源、聴感比較は未検証。
- 最新モデルが全用途で最良とは断定せず、既存JSONと評価済み方式の互換性を優先。
- ユーザーの「落ちた」報告は別実行の依頼ではないと訂正あり。HomeStereo動作中、確認範囲にクラッシュ記録なし。追加解析は開始しなかった。
- 889件の既存requestが残っていたがworker起動は確認できず。ユーザーの意向に従ってそのrequestを再起動・変更していない。
