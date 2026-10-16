# 評価範囲-10〜15、選曲効果10で最大

2026-10-16。ユーザーの明示依頼によりMyMusic・HomeStereo・Analyticsを実装。両Git rootを確認し、共通契約revision 3の本文一致を確認してから作業した。実機deploy・正式配置・commit・pushは実施していない。

## 実装

- MyMusic: TrackPreferenceRangeで保存範囲-10〜15を定義し、従来PlaybackPreferenceWeightPolicyの-10〜10・21要素表を維持。Storeの下限を上限の負数から分離。JSON Import、Watch通信、VoiceOverを拡張し、11〜15の色は10と同等にした。
- HomeStereo: TrackPreferenceとJSON検証、曲行／Playlist行共通操作、分析、メニューバー、再生バー・小型playerの上限を拡張。分析の未設定sentinel 11をInt?のnilへ変更。
- HomeStereo DB v15: track_preferences・mymusic_preferencesのCHECKをtransaction内でテーブル再構築して更新。他テーブル・ID・日時・Favorite・未送信tokenを維持。既存の新規DB作成／旧版移行経路へ組み込んだ。
- HomeStereo保存状態backup v2はDB v14とv15を受理。宣言と実DBのversion一致・checksum・integrity・外部キー検証を維持。旧v14はpending復元後、repository open時にv15へ移行する。backup JSON v1の既存merge経路は維持。
- Analytics Local/Desktop: Pydantic入力、API、編集UI、SQLite CHECKを更新。旧テーブルの定義と全列を保ちながらSAVEPOINT内で再構築。Static版も15を受理。
- 選曲式は両アプリとも変更しない。MyMusicの10〜15は42、HomeStereoの候補抽選では11。Analyticsおすすめ加点も元から10で飽和する。Mood Stationは評価値に直接依存しない。
- CURRENT、ARCHITECTURE、連携／backup説明と共通契約revision 4を更新。契約本文は両Gitで一致。

## 検証

- MyMusic generic iPhone／埋め込みWatch Simulator Debug build: BUILD SUCCEEDED。
- MyMusic既存iPhone 17e Simulator 1台、parallel-testing-enabled NO／maximum-parallel-testing-workers 1: XCTest 41件＋Swift Testing ExternalBackupServiceTests 12件成功。既存重み表、10〜15のshuffle／quick play重み同一、上限／下限、15保存再読込、旧履歴移行、15のImport、Watch通信、新旧manifest backup v1/v2復元を含む。
- 最初のSimulatorテストはrunner起動Mach -308で未実行。同じ既存端末をbootstatusで起動回復して再実行し成功。新Simulator/runtimeは作成・downloadしていない。
- HomeStereo ./scripts/verify.sh: XCTest 141件（3件既存skip、失敗0）、Swift Testing 86件成功、macOS Debug BUILD SUCCEEDED。旧v14実CHECK制約付きbackupを復元し、代表12テーブルのfield一致（評価・ID・日時・未送信token含む）を確認後、repository起動移行で15の書込みと16/-11拒否を検証。-10/0/10/11/15の4回反復JSON Import/Export、同seedで10と11〜15の選曲結果同一も検証。
- Analytics Python全61件成功。旧SQLite全列保持・再起動再移行の冪等性・15保存・境界拒否を追加。APIの15編集→Export→再Import・他source非変更テストも46件の対象suiteで再確認成功。
- Analytics JavaScript全20件成功。Static版-10/0/10/11/15の保持、-11/16拒否を含む。
- 両Git diff --check成功。HomeStereoの作業開始時に存在したscan通知関連未コミット変更を保持。LibraryViewsは既存変更と同ファイルのため評価ボタン部分だけ追加編集した。

## 制約・残る確認

- 旧文書／旧backupを新アプリで読む互換性を維持。旧版受信側は11以上を拒否し、新DB／15入りbackupの旧版への逆互換は保証しない。値を黙って10に丸める処理は追加しない。
- 15からBadを押すと14。9で選曲weightが下がる。生の評価順は15が10より上。ホーム再計算・保存通知は維持し、おすすめ表示の固定を保証する変更ではない。
- 同曲の両端末編集をクリック数として加算しない。既存の競合／原本保全未実装事項は共通課題管理を参照。
- 実ユーザーDB、実端末間JSON往復、実機Watch表示、UI目視・VoiceOver実操作、実データbackup復元は未実施。これらを自動テスト成功から推定しない。
- XCTestDevices開始時UUID folder 0、終了時UUID folder 0。作成0／削除0。残容量12 KiB（既存.DS_Store）。Simulator.app稼働中のため削除操作なし。DerivedData等も削除していない。
