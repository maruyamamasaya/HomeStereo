# SandboxからのAnalyzer job受け渡し

- 前回のnative launcherだけの修正では再発。最新jobは889件、status／journalなし。launcher-error.logでworkerのargv[1]欠落（IndexError）を確認。
- 本体がsandbox下でOpenConfiguration.argumentsを使った起動ではrequest指定が届いていなかった。前回の非sandboxテスト成功は本体経路の保証にならなかった。
- FeatureAnalysisServiceをNSWorkspace.open(document URLs, withApplicationAt:)へ変更。companionはAppKit delegateのopen eventを受け、request URLをPythonへ渡す。JSON document typeはViewer／LSHandlerRank None。
- 本体と同じapp-sandbox＋user-selected read/writeの専用検証アプリを/tmpに作成。container内requestで空job成功、さらに合成音源1曲のsemantic／loudnessがcompleted=1,total=1,failed=0まで成功。
- 起動＋部分復旧対象テスト2件成功。Python4件成功。全体XCTest114件（3skip）、Swift Testing80件成功。Debug／Release build成功。
- 本体とcompanionを再デプロイし起動。build 20261004004858、jp.local.HomeStereo.Beta。git diff --check成功。
- MyMusic／署名設定／entitlementは変更なし。Simulator testなし、test端末作成／削除0。ユーザーの大量解析は自動再開せず。2万曲長時間処理は未検証。
