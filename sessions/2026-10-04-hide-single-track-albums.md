# 1曲Albumの非表示切替

- HomeStereo継続依頼（MATCH）。Git root確認。既存変更を保持。
- LibraryViewsに端末内AppStorage設定「1曲のアルバムを隠す」を追加（既定OFF）。ジャンルfilter後のAlbum.tracks.count > 1だけを表示。
- 表示件数、検索0件判定、一覧からのキュー生成候補も表示Albumへ統一。全Albumが隠れた場合は解除button付きempty state。
- 元音源／SQLite／Playlist／曲一覧／Artistを変更しない。アーキテクチャ変更なし。CURRENT更新。
- 単純な可逆UI filterのため専用unit testは追加せず、既存全testとDebug build、実UIで検証。
- xcodebuild test／Simulator不使用。test端末作成0・削除0（swift testのみ）。
- verify.sh成功: XCTest116（3 skip、失敗0）、Swift Testing84成功、Debug BUILD SUCCEEDED。
- Release BUILD SUCCEEDED、deploy-macos.sh成功、正式配置/Applications/HomeStereo.app build20261004130718。署名／hash検証成功。
- 実UI: 全ジャンル944Album→ONで531→OFFで944→ONで531を確認。非表示ONで残し、音源／Queueには触れていない。狭いwindow／VoiceOver／再起動後の保存復元の実操作は未確認。
