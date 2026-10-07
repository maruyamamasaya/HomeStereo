# 閲覧用アーティスト・ジャンルランキング

- 分析へ独立したランキングtabを追加。アーティスト再生回数、アーティスト実聴時間、ジャンル再生回数をカード表示。順位・比較バー・数値を表示し、上位20件と全件を切替。再生や編集の操作は持たない。
- アーティスト集計は現在Libraryで選択しているジャンルプリセットを初期値とし、分析内で独立切替。ジャンルランキングは全体集計。既存presetの固定genre常時表示と未分類settingを尊重。Artistを分割せず、metadataのartist値を空白trimして集計する。
- 回数は既存summaryのMyMusic authoritative snapshot、時間は詳細履歴の実聴時間を使用。曲の長さ×回数から時間を推計しない。欠落した詳細履歴の時間は補完しない。現ライブラリの曲を対象とするため未接続曲の内訳は不明。
- 集計／sortはserviceでbackground実行し、snapshot・preset変更で再計算。UI body内で全曲sortしない。DB schemaとJSON形式は変更しない。

## 検証
- ./scripts/verify.sh成功。XCTest131件（3件skip・失敗0）、Swift Testing85件成功。Debug BUILD SUCCEEDED。
- Artist合算、回数／時間の順位分離、ジャンル合算、プリセットによる曲単位filter、未分類genre／artist、ゼロ値除外、同率時の安定順、空データをテスト。
- Simulator testなし、検証端末作成・削除0。

## 配置・実画面
- ./scripts/deploy-macos.sh成功。Release build 20261004224035、/Applications/HomeStereo.app、jp.local.HomeStereo.Beta。Build／Install／Launch成功。
- 実アプリの分析→ランキングで、3カード、順位、回数／時間、比較バー、プリセット選択、全件switchを確認。3カードが横並びに表示されるwindowでスクリーンショット確認。
- プリセットの実画面切替操作は利用者がアプリ操作中のためツールが拒否。filterの集計は自動testで確認済み。現在の画面をそのまま残した。
