# 曲一覧スクロール領域の修正

- 症状: 曲数が多いライブラリで曲一覧をスクロールできない。
- 原因: 曲一覧の`Table`と「さらに表示」だけでなく、画面全体の常設再生バーも`safeAreaInset`で挿入していたため、`NavigationSplitView`の詳細領域が再生バーの下まで伸びていた。
- 対応: `Table`と「さらに表示」バーを別領域に分離し、さらに`NavigationSplitView`と常設再生バーをroot `VStack`の別領域にした。一覧の実高さが再生バーを除外するため、最終行と「さらに表示」が常に再生バーの上へ表示される。
- 検証: `./scripts/verify.sh fast`と`./scripts/verify.sh`が成功。XCTest 59件成功（性能fixture 1件skip）、Swift Testing 60件成功、Xcode macOS Debug build成功。
- 配置: Release build成功後、実行中のHomeStereoを終了して`/Applications/HomeStereo.app`へ配置。署名検証、build成果物との実行ファイルSHA-256一致、bundle identifier `jp.local.HomeStereo.Beta`を確認した。
- 再修正版をRelease buildして`/Applications/HomeStereo.app`へ配置し、署名とbuild成果物とのSHA-256一致を確認した。
- 配置版を3,923曲の実Libraryで起動し、「さらに表示（150／3,923）」が再生バーの上に見えることと、曲一覧をスクロールしても両方が固定表示されることを画面上で確認した。
