# Preferences Import差分Preview Beta

2026-10-16。ユーザー依頼によりMyMusic／HomeStereoの評価JSON読込前に評価とハートの現在→受信後を表示する。両Git rootと共通契約revision 4の一致を確認して開始し、revision 5へ両方更新した。

## 実装

- MyMusic: TrackPreferenceImportPreviewが照合済みの現在値（未保存は0/OFF）と受信値、未照合を分離。TrackPreferenceStore.prepareImportPreviewはread-only、DataManagementから直接適用せず専用sheetを開く。更新／変更なし／未照合の件数、曲名・Artist・Track ID・評価・ハートを表示し、変更なしはtoggleで任意表示。キャンセルでは保存しない。
- MyMusic適用: 対象IDのLibrary所属と現在entriesのsnapshotを照合。先行save完了後に再検証し、staleなら拒否。保存中の追加評価操作／重複Importを抑止し、atomic保存成功後だけmemoryへ反映。default 0/OFFで変更なしの曲は不要な保存をしない。成功後に結果件数を表示。
- HomeStereo: MyMusicTransferServiceのPreferences Previewに現在値／受信値とsnapshotを追加。既存Previewを拡張し、Preferencesは先頭100件で打ち切らず全明細を保持、変更なしはtoggleで畳む。未照合を0/OFFとは表示しない。
- HomeStereo適用: 対象Canonical IDとhome ID、現在評価、Favoriteを単一SQLでsnapshot化。RepositoryのBEGIN IMMEDIATE transaction直後に同じsnapshotを照合し、不一致でrollback。再編集や新しい照合を拒否し、dirty tokenの解除前に止める。対象外の曲は比較／変更しない。
- JSON wire schema v2・SQLite schema v15・選曲・演出は維持。Preferences原本／更新前状態の耐久保管、受領確認、自動競合merge／差分選択は未実装。
- CURRENT／ARCHITECTURE、共通契約revision 5と保全課題、実機ガイドを更新。直前の文書保存依頼で未コミットだったguide／チェックリスト／CURRENT更新を保持して追記した。実機guideでは導入済みrevisionに今回Previewが未導入であることを区別した。

## 検証

- MyMusic generic iPhone／埋め込みWatch Simulator Debug: BUILD SUCCEEDED。
- MyMusic既存iPhone 17e Simulator（EB3A49ED-6553-4D7E-B933-387951643EAB）1台、parallel-testing-enabled NO、maximum-parallel-testing-workers 1。TrackPreferenceImportPreviewTests 5件、既存TrackPreferencePersistenceTests 7件、WatchPlaybackCoordinatorTests 2件、合計14件成功。最新Viewもこのtest buildでcompile成功。
- 新規iOS test: 評価だけ／ハートだけ／変更なし／未照合、Preview非保存、対象評価／ハート再編集拒否、対象外編集保持、Library所属変更拒否、105件の全件保持、保存失敗で状態保持・gate解除・再試行、default変更なしでsave不要。
- HomeStereo ./scripts/verify.sh成功。XCTest 145件（3件既存skip、失敗0）、Swift Testing 86件成功、macOS Debug BUILD SUCCEEDED。
- 新規Mac test: 差分値とcancel非保存、評価／Favorite再編集後の適用拒否とdirty保持、Preview後の新しい照合拒否、102明細と100件以降の変更、確認snapshotで正常適用→再Preview変更なし。
- 両Git diff --check成功。両方の共通契約・保全課題の本文一致を確認。専用lintなし。
- XCTestDevices開始／終了UUID folder各0、作成0／削除0、残容量12 KiB。新Simulator／runtime作成なし。XCTestDevicesやDerivedDataの削除なし。

## 未実施

実機／画面の目視、VoiceOver、実ユーザーJSONの往復は未実施。実装時点ではVespera再deploy／HomeStereo正式配置、commit／pushは行っていない。後続の明示依頼により下記の配置・コミット作業を実施。


## 後続依頼による配置・コミット（2026-10-16）

- git statusで今回の実装・ガイド・文書のみであることを確認。check-iphone.sh成功後にdeploy-iphone.shを実行。
- MyMusic.xcodeproj／MyMusic scheme／Debug／MyMusic.app／maruyama.MyMusic。Vespera（iPhone 17e）、UDID 00008150-000C54280E33401C。BUILD SUCCEEDED、Install成功、21:49 JST Launch成功。
- HomeStereoはOPERATIONS.mdのdeploy-macos.shでRelease build・正式配置・起動成功。/Applications/HomeStereo.app、jp.local.HomeStereo.Beta、build 20261016214812。
- HomeStereo executable SHA-256: 304c8004e91fca03d00dcb1a6bee7b902e7707b75802bd0ee146dbf89f421c00。専用scriptで成果物と配置先のhash・署名を照合。
- Bundle ID、Team、署名設定、Deployment Targetのソース設定は変更なし。配置は既存の作業ツリーを保持して実施。
- 検証済み同一ソースを配置buildしたため関連testを重複実行していない。今回の配置作業でtest端末の作成0／削除0。
- 実機でのPreview画面目視・実ユーザーJSON往復は未実施。配置成功と区別する。
- 両リポジトリの今回の実装とドキュメントをコミットしてorigin/mainへpushする。
