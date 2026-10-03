# お気に入りのライブラリ共通表示

- お気に入りをLibraryView / SongsTableで表示。検索、列sort、表示項目、ジャンルfilter、ジャンルプリセット、行内Good/Bad等を共用する。
- favorite ID集合で対象を限定し、作業用BGM／ハイレゾもお気に入りなら表示。今すぐ再生はfavorite sourceを維持する。
- 再生／Shuffleは検索・ジャンル絞り込み後の利用可能曲を対象にする。全解除確認とエラー表示は維持。
- ライブラリと検索／ジャンル／sort状態を共有する。ライブラリから解決できないfavorite参照は保存を維持するが、Tableには表示しない。
- verify fastはsandbox外cacheへの書込制限で失敗。許可付きの `./scripts/verify.sh` は成功（XCTest 100件、うち性能test 1件skip、Swift Testing成功、macOS Debug build成功）。git diff --check成功。
- 実画面操作は未確認。既存の作業中変更は保持した。配布版へのdeployは実施していない。

## 配布版への反映

- ユーザーの追加依頼で `./scripts/deploy-macos.sh` を実行し成功。
- Release build `20261003081949` を `/Applications/HomeStereo.app` へ配置。署名、build番号、実行ファイルSHA-256照合成功。正式配置から起動。
