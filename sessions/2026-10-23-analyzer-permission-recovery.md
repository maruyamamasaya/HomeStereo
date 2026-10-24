# 解析補助アプリのアクセス復旧

- システム設定 → プライバシーとセキュリティ → ファイルとフォルダ → HomeStereoAnalyzer.appを確認。「HomeStereo」はoff、iCloud Driveはonだった。
- 実行直前の本人確認を得て「HomeStereo」をonへ変更。フルディスクアクセス等は追加しない。アプリや補助アプリのコード・署名・cacheは変更しない。
- 正式配置のHomeStereoから未解析258曲を開始。進捗を確認後に中断要求。86曲処理、失敗63件、成功23件。本体の「完了済み23件を保存しました」を確認。保存済み18,967→18,990件、未解析258→235件、音量未解析309→286件。
- 検証解析は中断済み。既存cache保持。OS更新が権限offの原因かは不明。63件の個別失敗は理由未確定。workerは型名のみを結果failuresへ記録するが、通常完了／中断時に本体がrun directoryを削除するため、画面では内訳を確認できない。
- CodexのPythonからcontainer内runへのreadはmacOSのOperation not permittedで拒否された。Codexへの権限追加や保護回避は行わない。
- 設定変更と実動作確認のみ。build／unit testなし。Simulator／test端末作成・削除0。
