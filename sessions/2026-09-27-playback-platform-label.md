# 再生履歴のApp／Mac判別

- Playback Events JSON v1に既存の`platform`を利用し、JSON契約とMyMusicアプリ側を変更せずHomeStereoの分析履歴へ再生元を表示した。
- `macOS`は「Mac」、`iOS`／`iPhone`／`iPad`は「App」、未知値は元の文字列として表示する。
- Library JSONの`playCount`にはevent単位の再生元がないため、App／Mac判別はPlayback Eventsの詳細履歴だけを対象とする。
- `./scripts/verify.sh fast`と`./scripts/verify.sh`に成功。XCTest 83件中82件成功、性能test 1件skip、Swift Testing 77件成功、macOS Debug build成功。
- `/Applications/HomeStereo.app`へbundle version `20260927142335`を配備した。配備後の分析履歴でHomeStereo eventに「Mac」バッジが表示されることを確認した。
- 稼働DBには`iOS` 7,180件、`macOS` 139件が保持されており、取り込んだMyMusic eventも同じ分類処理で「App」と表示できることを確認した。
