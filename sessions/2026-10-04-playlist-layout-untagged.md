# Playlist上部の重なり修正とタグなしfilter

2026-10-04。HomeStereoの上部UIが一覧を隠す報告を修正し、追加要望のタグなしfilterを両アプリへ実装した。Context Guard MATCH。両Git rootを確認し、作業中の既存変更を保持した。

## 変更

- HomeStereo実画面で、最上段のPlaylistがsafeAreaInsetの操作欄の背後へ入り込むことを確認。PlaylistsViewをVStack（header、Divider、HSplitView）へ変更し、操作欄と一覧に別の高さを割り当てた。
- 種類、操作、タグを3行へ分け、ViewThatFitsで狭い幅では操作ボタンを縦にする。横スクロールするタグ欄は36ptの高さを確保し、タグ文字列を圧縮しない。
- Mac／MyMusicのPlaylistStoreにuntaggedOnly filterを追加。Stringの特別値を使わずBoolでtags空を選ぶため、実際のタグ名「タグなし」と区別できる。
- Macの上部filter、MyMusicの通常／作業用Playlist一覧、MyMusicの曲追加先sheetに「タグなし」を追加。タグのないPlaylistしかない場合もfilterを表示する。Macはfilterで対象外になった選択を解除する。
- ID、曲順、保存形式、JSONは変更していない。architecture変更・ADR追加は不要。CURRENTへ記録。

## 検証

- MyMusic既存iPhone 17e Simulatorを1台だけ使用、parallel-testing-enabled NO／maximum-parallel-testing-workers 1。Playlist関連のXCTest 16件成功。通常／作業用、未設定と文字列タグ「タグなし」の区別を確認。
- Mac ./scripts/verify.sh成功。XCTest 123件、3件skip、失敗0。Swift Testing 85件成功。macOS Debug build成功。
- 途中で原本保管testの厳密Date比較がSQLite doubleの丸め差により失敗。保存後にDBから読み戻したsnapshotと比較するようtest fixtureを修正し、実装の保全動作を変更せず解消した。空白checkのtrailing whitespaceも修正。
- 更新後Macの実画面で最上段がheaderと重ならず表示されることを確認。「タグなし」ボタンを押し、taggedなPlaylistが一覧から除かれることも確認した。狭い幅での縦配置はbuild確認のみで手動resizeは未実施。iPhoneのfilter操作は実機未確認。
- 両Gitでdiff --check成功。専用lint設定は確認されていない。

## 導入

既存の両アプリ導入依頼に従い、既存scriptで更新した。

MyMusic: check-iphone.sh成功後deploy-iphone.sh。MyMusic.xcodeproj / scheme MyMusic / product MyMusic.app / Debug / Bundle ID maruyama.MyMusic。Vespera（iPhone 17e、UDID 00008150-000C54280E33401C）へBuild・Install・Launchすべて成功。

HomeStereo: deploy-macos.sh。HomeStereo.xcodeproj / scheme HomeStereo / product HomeStereo.app / Release / Bundle ID jp.local.HomeStereo.Beta。/Applications/HomeStereo.app、build 20261004153507。Build・Install・Launch成功。配置とbuild成果物の署名・hash一致をscriptで確認。実行ファイルSHA-256は3457ed0a4925dedb8f3890f03a51f6eed7f6e3674b90e15751ef049a076ec58c。

## ストレージ・範囲

XCTestDevicesは事前／完了後ともUUID folderなし、合計0 KiB。新規test端末0、削除0。既存Simulator1台のみ、runtime追加なし。Macの既存deploy scriptが管理する一時build以外は削除していない。利用者のPlaylist／タグ／JSONを編集・削除していない。画面のfilter操作だけを確認した。commit／pushなし。
