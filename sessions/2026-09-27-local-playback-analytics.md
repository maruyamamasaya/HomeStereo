# ローカル再生分析

- `ListeningStore`の既存再生callbackと`MyMusicPlaybackSession`を拡張し、終了日時、終了種別、完走率、Early Skipを共通Policyで扱うようにした。
- SQLite schemaをv11へ更新し、raw eventとTrack／日別／入口別集計、独立したGood／Bad Preferenceをtransaction保存する。重複eventは集計せず、Track削除後もraw履歴を保持する。
- `AnalyticsService`、cancel可能な`AnalyticsStore`、Sidebarの「分析」画面を追加した。概要、上位曲、日別履歴、理由付き傾向、評価別傾向、曲単位／全履歴resetを提供する。
- MyMusic Preferences／Playback Events適用後とLibrary／履歴revision変更時にsnapshotを更新する。履歴resetはFavorite、評価、Playlist、Track metadataを維持する。
- `./scripts/verify.sh`成功。XCTest 78件中77件成功、性能test 1件skip、Swift Testing 70件成功、macOS Debug build成功。
- `./scripts/deploy-macos.sh`でRelease build `20260927101204`を`/Applications/HomeStereo.app`へ配置し、署名・SHA-256照合後に正式配置から起動した。
