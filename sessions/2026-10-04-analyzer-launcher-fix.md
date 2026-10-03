# Analyzer起動修正

- ユーザー報告: 解析用補助アプリが途中終了。
- 最新jobは889件、status／results／journalなし、cancelのみ。音源解析開始前の終了と確認。既存解析結果は維持。
- shell entryをnative Swift launcherに変更し、Processで専用Pythonを起動してwaitUntilExit。stderrと起動例外を端末内launcher-error.logへ記録。
- 専用installerで補助アプリ更新・署名検証。本体／MyMusic／sandbox entitlementは変更なし。
- NSWorkspace実起動＋合成音源解析と部分journal復旧の2テスト成功。実containerの中断済みrequestも同APIでstatus更新を確認。大量実音源解析は再開しなかった。
- git diff --check成功。Simulator testなし、test端末作成／削除0。20,000曲長時間処理は未検証。
