# キュー修正版の配置・起動

- 明示依頼によりHomeStereoのGit rootとstatus、OPERATIONSを確認し、既存の未コミット変更を含む作業ツリーをscripts/deploy-macos.shで配置。コード変更なし。
- Release BUILD SUCCEEDED、/Applications/HomeStereo.app更新・起動成功。bundle jp.local.HomeStereo.Beta、build 20261022133419。
- build／stage／配置先の署名検証成功。実行ファイルSHA-256一致: b5a020a6cc82f3e57b6dc9fa3bab26395632b10d0451f60ae8b902ab1013e7dc。正式pathからprocess起動を確認。
- 専用scriptによるAnalyzer更新、一時build・旧bundleのcleanup完了。一時Deploy DerivedDataの不存在を確認。
- 実画面でのドラッグ操作・挿入線解除は未確認。今回testの再実行なし、test端末の作成／削除なし。git diff --check成功。
