# 既存の短時間Mac履歴の削除

- ユーザーの明示依頼で、稼働Appのsandbox内Library.sqlite3を一度限り整理した。HomeStereoを通常終了し、SQLite backup APIで同じディレクトリに`Library-before-short-mac-cleanup-20261001.sqlite3`を保存してから更新、終了後にApplications版を再起動。
- RepositoryにdeleteShortMacPlaybackHistoryを追加。playback_eventsのplayed_seconds<=30、交換イベントのplatform=macOSかつevent_id=mac-*かつplay_duration<=30をtransactionで削除し、既存処理で分析集計を再構築。起動時自動削除はしない。
- 実DB: 再生履歴23件・Macイベント67件削除。残り履歴88件、Macイベント120件、iOSイベント7,358件。終了直前の保存で事前確認からMacイベントが1件増えた。
- Favorite、Good／Bad、MyMusic Preferences／Library集計、Playlist、曲、外部イベント、30秒超のMacイベントを削除前後で全行比較し、不変を確認。integrity_check=ok。
- fast/full成功。XCTest 100件中99件成功＋性能1件skip、Swift Testing 79件成功、macOS Debug build成功。削除境界、外部イベント／評価維持、繰り返し実行を検証。
- 新版のApplications配備は未実施。再起動したインストール済み版に新規短時間記録の抑止変更が含まれることは確認していない。
