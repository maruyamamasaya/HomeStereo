# データ連携の保全課題

更新: 2026-10-04。共通契約revision 3に対する段階的な実装管理。大きなwire変更・DB統合を前提にしない。完了は対象範囲の対策・検証が揃った時だけ記す。

| ID | 優先 | 状態 | 対策と完了条件 |
| --- | --- | --- | --- |
| DI-001 | P1 | MyMusic対象範囲完了 | Playback EventsのImport確定前に全原本をhash名でatomic保存しread-back確認。失敗時は履歴を変更しない。未照合・期間外も原本保持。HomeStereo側と他文書は未着手 |
| DI-002 | P1 | 未着手 | 原本一覧・手動再適用導線。アプリ再起動後にも未照合原本を再Importできること |
| DI-003 | P1 | Playlist対象範囲完了 | HomeStereo Playlist受信原本のatomic保存・read-back確認をtransaction更新前に追加。他文書は未着手 |
| DI-004 | P1 | 未着手 | 同一event ID異内容の検知・競合保管。重複集計をせず双方の内容を保持 |
| DI-005 | P1 | 設計待ち | Export保存と受領確認を分離。まず再送可能な原本／変更世代を保管し、wire変更は別途レビュー |
| DI-006 | P1 | 部分対策 | 両側で未照合／非互換／競合曲の部分Import・JSON Exportを停止。参照の耐久保留と部分適用は未実装 |
| DI-007 | P1 | Playlist部分対策 | Playlistの旧snapshotと原本を適用前に保管し、確認後の再編集を拒否。差分選択／復元UI、Preference保全は未実装 |
| DI-008 | P2 | 調査待ち | playCount snapshotと詳細Eventsの対象範囲・集計正本を明確化。まず既存文書矛盾を実装と照合 |
| DI-009 | P2 | 部分検証 | 両側の反復Import・タグ・未照合拒否・原本破損／保存失敗を試験。実端末間往復・共通fixture・復元・backup包含は未検証 |
| DI-010 | P1 | 対象範囲完了 | MyMusic Playlist JSONのID保持と同一内容の再Import冪等性。Macタグ編集・filter追加。両側4回の反復fixture試験で件数・ID・tags・曲順を確認。既存重複整理・IDなし形式の冪等化は対象外 |

## DI-001の範囲と制約

MyMusicの有効なPlayback Eventsを利用者がImport確定した場合だけ、Application Support/MyMusic/PlaybackEventImportOriginalsへ元bytesを保存する。SHA-256が同じ原本は1ファイルにまとめる。既存原本は上書きしない。破損が見つかればImportを止める。保存はactorでUIから分離する。Preview／cancelでは原本保存も履歴保存も行わない。

原本の自動削除・容量制限は設けない。保存できない場合はImportを止めるため既存操作が失敗する場合がある。再適用UI、自動送信、受領確認、原本の外部backup、破損修復、Import結果の耐久記録は未実装。内部保管はアンインストール・端末故障から守る外部backupの代替ではない。

DI-001はgeneric Simulator buildと対象XCTest 8件、原本Serviceの独立検証が成功。次の作業は、DI-002またはDI-003を一つずつ進める。両Gitの契約・課題記録の同期を確認する。
