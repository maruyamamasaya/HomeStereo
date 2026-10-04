# 1曲Artistの非表示切替

- HomeStereo継続依頼（MATCH）、Git root確認、既存未コミット変更を保持。
- LibraryViews: Artist一覧へ端末内保存の「1曲のアーティストを隠す」を追加（既定OFF、Album設定と独立）。通常曲・genre条件適用後の曲数で判定。
- 表示件数／検索0件判定／最大100曲キュー候補を表示Artistへ揃える。全件非表示時は解除button付きempty state。
- 元音源／SQLite／JSON／アーキテクチャ変更なし。CURRENT更新。
- 可逆の単純なUI filterのため専用unit testは追加せず、既存全testとDebug build、実UIで確認する。
- xcodebuild test／Simulator不使用。test端末作成0・削除0（swift testのみ）。
- 作業中の追加依頼: 同名AlbumをTrack Artist／Album Artist差にかかわらず統合。LibraryBrowserのgroupingとLibraryAlbum表示ID、Artist画面内のAlbum groupingをtitle基準へ変更。mixed Albumは複数のアーティストと表示、収録Artist／Album Artist名検索にも対応。完全同名の別作品も統合する仕様をユーザーへ説明。
- Album統合テストを旧composite仕様から更新し、filter前後のID維持／混在Artist／収録Artist名検索を検証。CURRENT／ARCHITECTURE更新。元metadata・DB・JSONは維持。
- verify.sh成功: XCTest117（3 skip、失敗0）、Swift Testing84成功、Debug BUILD SUCCEEDED。検索追加後のLibraryBrowserTestsも成功。
- Release BUILD SUCCEEDED、deploy-macos.sh成功、署名／hash照合成功。/Applications/HomeStereo.app build20261004132358起動。
- 実UI: Artist1263組→非表示ONで479組を確認、ONで保存。Album画面ではユーザーが選択したインストpresetを保持し、同名mixed Albumが「複数のアーティスト、26曲」で統合表示されることを確認。全filter／狭いwindow／VoiceOver／再起動後Artist設定復元は未確認。
