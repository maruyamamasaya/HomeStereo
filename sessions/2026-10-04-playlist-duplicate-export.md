# プレイリストJSON重複エラー

- 利用者報告はHomeStereo書き出し時のtrackID重複。読取専用で実DBを集計し、46プレイリスト中2件・重複track group3件を確認。名前・音源pathを出力せず、実DBは変更していない。
- Mac内は既存重複や統合時の重複保持を許容する一方、追加したJSON validatorは重複参照を拒否していた。MyMusic importerも重複を拒否するためvalidatorの単純な緩和では解決しない。
- 重複がある場合は専用エラーをStoreで受け、件数と「JSON内だけ各曲を最初の1回にまとめる」確認を表示。承認後に最新値を取得してJSONを生成し、保存panelを開く。通常操作で黙って重複を削らない。
- 元プレイリスト・曲順・重複・identity・タグは変更しない。未知曲やcanonical ID競合の全体拒否は維持。JSON形式とMyMusic側は変更しない。共通契約revision3の本文一致を確認。

## 検証
- ./scripts/verify.sh成功。XCTest129件（3件skip・失敗0）、Swift Testing85件成功。Debug BUILD SUCCEEDED。
- 最後のID競合対策は専用testを再実行し成功。承認なしの専用error、承認後のdecode、最初の曲順、tags・identity、元DB無変更、同じ出力の再生成、異なるHome TrackのCanonical ID競合拒否を確認。
- Simulator testなし、test端末作成・削除0。

## 配置
- ./scripts/deploy-macos.sh成功。Release build 20261004213349、/Applications/HomeStereo.app、jp.local.HomeStereo.Beta、Build／Install／Launch成功。
- 起動確認済み。確認dialogのnative操作は利用者がアプリを操作中のためツールが拒否し、再操作しなかった。実利用者JSONの保存は行っていない。dialog表示の手動検証は未完了。
- XCTestDevices合計12K（metadataのみ）。
