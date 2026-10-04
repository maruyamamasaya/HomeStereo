# 音楽特徴量解析の6並列選択

- 既存の未コミット2・3並列対応を保持し、6並列を追加した。
- UI enum、Swift requestの入力検証、Python workerの許可値を2・3・6で整合させた。旧requestの1並列互換と初期3並列は維持。
- 内部request以外の交換JSONとアーキテクチャ境界は変更なし。実行中のジョブを変更しない。
- Pythonの上限・失敗保存・キャッシュ再利用・中断時drainテストに6並列を追加。Swift requestテストにも6を追加。
- 検証: verify.sh fast / verify.sh成功。XCTest 115件（3 skip）、Swift Testing 80件成功。Python 7件成功。macOS Debug BUILD SUCCEEDED。git diff --check成功。
- ユーザーから進行中の解析を停止したと連絡あり。本作業は解析再開、正式アプリの置換、補助アプリ再導入を実施していない。
- 6並列の実音源負荷、UI手動操作、動的並列制御は未検証／未実装。Simulator / XCTestDevicesは使っていない。

## デプロイ

- 明示依頼後に scripts/deploy-macos.sh 成功。本体と補助アプリを更新。Release build・署名・成果物SHA-256照合成功。正式 /Applications/HomeStereo.app 起動。
- Bundle version: 20261004101808。音楽特徴量画面に2・3・6並列の選択肢が表示されることを確認。
