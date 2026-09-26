# 2026-09-26 macOSデプロイ重複対策

## 調査結果

- 標準配置先の実ファイルは`/Applications/HomeStereo.app`の1個だったが、最終確認でSpotlightにXcodeの`DerivedData/.../Build/Products/Debug/HomeStereo.app`も検出された。
- Dockの固定項目も`/Applications/HomeStereo.app`の1個だった。
- アプリ一覧にも同じbundle identifierのHomeStereo履歴が2件あり、XcodeのDebug成果物と正式配置側が別アプリとして起動・登録されたことが重複表示の原因だった。
- 従来手順の`ditto source.app /Applications/HomeStereo.app`は既存bundleへのmergeであり、古いbundle内容を完全に排除する保証がなかった。また、`CFBundleVersion`は常に`1`で、配置物の新旧を画面やInfo.plistから区別できなかった。

## 変更

- `scripts/deploy-macos.sh`を追加した。
- 全HomeStereo processの通常終了、非正式copyの登録解除、Xcode Debug成果物のclean、Release clean build、一意なbuild番号、stage検証、旧bundleのrollback可能な丸ごと置換、署名・実行ファイルhash照合、Deploy用Derived Dataの登録解除と削除、正式pathの再登録・起動を自動化した。
- 手作業の配置手順を`OPERATIONS.md`から削除し、専用scriptを正本にした。

## 検証

- `./scripts/verify.sh`: XCTest 60件中59件成功・性能test 1件skip、Swift Testing 60件成功、Debug build成功。
- 初回実デプロイ: Release build、署名、build番号`20260926202401`、実行ファイルSHA-256一致、正式pathからの起動に成功。
- 最終版scriptでXcode Debug成果物をcleanし、Release build番号`20260926202540`を再配置した。
- Spotlight検索は`/Applications/HomeStereo.app`の1件のみ、Debug copyなし、Deploy用Derived Dataなし、stage／backup残骸なしを確認した。
- 実行processは1件だけで、`/Applications/HomeStereo.app/Contents/MacOS/HomeStereo`から起動している。配置先のad-hoc署名検証も成功した。
