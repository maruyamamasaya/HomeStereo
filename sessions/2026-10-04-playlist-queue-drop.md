# プレイリストからのキュー追加と末尾drop

- HomeStereoプレイリスト詳細に全体の「キューに追加」、曲行に個別の＋を追加。全体は利用可能Track IDを曲順どおり既存appendへ渡し、個別はmissing時に無効化。
- QueueViewは表示項目数に応じてListの高さを調整し、下部の空き領域を独立した末尾drop targetへ変更。常時hintと破線枠を表示、drag中は強調。項目が多い場合も最低90ptの領域を確保。
- ライブラリ曲のdropはavailable曲だけを末尾追加し、キュー内のitem payloadは既存moveへ渡して末尾移動する。再生中itemは移動しない。空キューもdropを受け付ける。
- 既存QueueStore・payloadを使用。保存境界・再生処理・100曲上限は変更しない。ARCHITECTUREの更新は不要。

## 検証・配置
- ./scripts/verify.sh最終実行成功。XCTest128件（3件skip・失敗0）、Swift Testing85件成功。Debug BUILD SUCCEEDED。git diff --check成功。
- ./scripts/deploy-macos.sh成功。Release build 20261004204555、/Applications/HomeStereo.app、jp.local.HomeStereo.Beta、Build／Install／Launch成功。
- 実画面でプレイリスト全体のボタン、各曲の＋、Inspector下部のdrop areaを確認。利用者がアプリ操作中のため、native dragはツールから拒否された。再確認も「user is still interacting」で終了。実ドロップ完了とhover強調は未検証。既存append／moveの自動テストは成功。
- このタスクのテスト端末作成・削除0。Simulator testなし。XCTestDevices総容量12K（metadataのみ）。
