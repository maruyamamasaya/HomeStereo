# Playlist JSON往復保全・Macタグ管理修正

2026-10-04。MyMusic／HomeStereo横断の修正。Context Guard MATCH、両Git rootと共通契約revision 2の一致を確認して開始。共通契約・課題文書は同一本文のrevision 3へ更新した。MyMusicの開始前から存在したHome／再生時間カレンダー等の変更は保持した。commit／push／実機deployは行っていない。

## 変更

- MyMusic Import DraftがplaylistID、日時、tagsの存在を保持する。同じID・同じ内容は追加／書換えしない。IDなし旧形式は新規追加。異内容は利用者へ更新を確認し、確認後の再編集をsnapshot比較で拒否する。既存の検索条件・説明・画像はJSON更新で維持する。
- MyMusic Storeは保管と候補全体の保存成功後にだけmemoryへ反映し、その間の編集を抑止する。受信原本と更新前の全PlaylistはPlaylistImportArchiveServiceがhash名でatomic保存しread-back確認する。load失敗後にはImportを許可しない。
- Macの既存ID照合は維持。DB transaction内でPreview snapshotを照合し、受信原本と更新前の全ローカルPlaylistをPlaylistImportArchiveへ保管する。保管失敗はrollback。Previewには受信内容への更新を明示する。
- 両側のJSON Importは未照合／種別非互換（MyMusic）／ID競合（Mac）を含む文書全体を拒否する。JSON Exportも未解決参照を除外せず停止する。MyMusic個別Exportのエラーは共有エラーalertへ表示する。
- Macのタグ編集sheetで追加・削除・既存タグ選択ができる。PlaylistTagRulesでMyMusic互換の20個／40文字と重複正規化を行い、上限超過は黙って切り捨てない。PlaylistStoreを通してSQLiteのtags_jsonへ保存する。
- Mac上部で通常／作業用BGMをkindで切り替え、そのkindにあるタグボタンを横スクロールで切り替えられる。新規作成／M3U8 Importは選択kind。種類変更時に別種類の選択を解除する。既存kind／曲は変更せず、混在している曲も自動除去しない。
- wire v1、SQLite schema v14、署名・Bundle IDは維持する。Mac Xcode projectには新規Swift 3ファイルの必要な参照だけを追加した。

## 検証

- MyMusic generic iPhone／Watch Simulator Debug build成功。既存iPhone 17e Simulatorを1台だけ使用し、parallel-testing-enabled NO／maximum-parallel-testing-workers 1でPlaylistInterchangeTests・既存タグtestsを実行。最終15件成功。
- MyMusic: 4回のencode→parse→Store保存→encodeでID・件数・タグ・曲順・日時が維持されること、更新確認、tags欠落、未照合拒否、invalid ID／不正末尾／重複ID、保存失敗・原本保管失敗・確認後再編集を検証。
- Mac ./scripts/verify.sh: XCTest 123件（3件skip、失敗0）、Swift Testing 84件成功、macOS Debug build成功。その後、ユーザー追加要望の種類／上部タグfilterについてStore経由testを追加・実行し1件成功、最終macOS buildも成功。意味のある追加変更以外で同じtestを繰り返していない。
- Mac: 4回のImport→DB保存→ExportでID・タグ・曲順を確認。部分Import／Export拒否、原本破損・Preview後編集によるrollback、タグ上限と保存、種類×タグfilter、kind切り替えでの選択解除を検証。
- 初回Mac testでは従来の部分Importを期待するtestが失敗し、新しい保全仕様を検証するtestへ変更した。初回iOS testは追加testのoptional比較のコンパイルエラーで停止し修正。Mac初回Xcode buildは新規ファイル未登録で停止し、必要な3参照を追加して解消。
- 両Gitのdiff --checkと意図した差分を確認。共通契約・課題文書はcmpで一致。専用lint設定は確認されていない。

## ストレージ

XCTestDevicesの事前UUID一覧は空、合計0 KiB。完了後も空、合計0 KiB。新規test端末0、削除0、既存Simulator 1台のみ使用。runtimeの追加・download、DerivedDataの削除は行っていない。Mac SwiftPM testはSimulatorを作らない。

## 制約・未解決

利用者の実JSON／実DBを操作していない。実端末間の操作、Macタグsheetの手動UI、既存重複の整理は未検証。両側の同じwire契約で個別の反復fixtureを検証したが、共通fixtureによる両binary間の完全往復は未実施。既存重複の名前だけによる自動統合はしない。

未照合参照を耐久保留して部分適用するDI-006は未完了。今回は欠落を生む部分操作を停止する対策。原本・旧snapshotの復元UI、外部backup包含、原本とsnapshotを組にした受領記録、3者mergeによる編集競合解決は未実装。確認して更新すると受信値が現在値となり、旧値は内部保管へ残る。原本は自動削除しないが、端末故障への外部backupの代替にはならない。IDなし旧JSONの反復Importは新規追加を維持するため同期にはID付きJSONを使う。Macの混在PlaylistはMyMusicでkind非互換ならImportが停止する。
