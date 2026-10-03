# 分析・よく再生している曲の指標監査

- 要求: 回数以外の完走率、Skip率、合計再生時間を確認。
- AnalyticsService / AnalyticsView、raw eventロード、MyMusic Import、実聴時間記録を確認。稼働版SQLiteをmode=roで参照し、更新しない。
- 回数はMyMusic Library playCount、時間と率は保持するraw eventだけが対象。累計回数と詳細event件数は一致しない。上位10曲のうち4曲は詳細eventなし、4曲は1件だけ。
- 7,975件・4,268 track IDの独立Python集計とSQL集計が一致。負の時間、未知曲長、completed/skipped両方true、94%閾値とcompletedの不一致、同一track/開始日時/時間/flags/platformの重複候補は0件。
- 完走率は有効曲長eventのcompleted割合、Skip率は全eventのskipped割合、時間はplay_durationの合計。未完走かつskipped=falseは存在し、完走率とSkip率は補数ではない。
- 詳細eventなしの合計時間が0分0秒となる表示は、累計実績や実際の0秒と誤認しやすい。全履歴を持たないため累計の時間・率は復元不能。読み取り監査のみでUI／保存データは変更しない。
- iOSにplay_duration=0が1,776件。曲長超過5秒以上はiOS 10件、Mac 6件。seek後の聴き直し等でも時間は曲長を超え得るため、これだけで誤記録とは確定しない。原MyMusicデータや実聴との一致は未検証。
- Mac新規eventは実聴30秒超だけ保存するため短い離脱は集計対象外。iOS Importと既存保存済みeventはその制限を適用しない。
- ./scripts/verify.sh fast成功: XCTest 100件（性能1件skip）、Swift Testing 79件。ソース変更・deployなし。
