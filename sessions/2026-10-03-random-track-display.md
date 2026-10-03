# ランダム表示

- 曲／お気に入り／音源分類のTable、Album詳細、Artist詳細へランダム表示と元の順序への復帰を追加。
- 画面内の表示配列だけを変更。標準shuffleをbackgroundで一度実行し、O(n)時間・追加メモリO(n)。準備中は再操作を抑制し、cancelと世代チェックで古い結果を破棄。詳細は[performance](../docs/performance.md#ランダム表示)。
- 曲Tableは順序変更時にnative tableを再生成。列sortで通常表示へ戻り、browser世代・お気に入り対象・音源更新・画面退出でも解除する。Artistはランダム中に全曲flat表示。
- 既存の未commit変更を維持し、LibraryViews.swift、CURRENT.md、docs/performance.mdへ追記。
- 最初のfast／fullはsandboxによるSwift標準cache書込拒否で停止。許可された通常環境でfull（fastを含む）を実行し、最終版はXCTest 100件中99件成功＋任意性能test 1件skip、Swift Testing 79件成功、Debug build成功。git diff --check成功。
- 実音源2万曲のUI操作時間／メモリ、VoiceOver、狭いwindowの手動確認は未実施。

## デプロイ

- ユーザー依頼により`./scripts/deploy-macos.sh`を実行し、Release clean build、bundle置換、署名・build番号・実行ファイルSHA-256照合を成功。`/Applications/HomeStereo.app`から起動。
- 配置build番号は`20261003114118`、SHA-256は`22264a244fc2cdc10593c70cb0bdb8059787df4f0640cabc744fb8c520440eda`。
