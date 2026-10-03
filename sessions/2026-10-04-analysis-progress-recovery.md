# 解析進捗と途中結果の復旧

- 未解析／音量未解析／旧版・変更曲の3経路共通で、総曲数、処理済み件数、割合、失敗件数と進捗バーを表示。
- workerは成功曲をcompleted.jsonlへ逐次flush/fsync。通常中断だけでなく異常終了の部分結果もarchiveへmergeする。
- 本体再起動時は残存journalの完全な行を検証してmerge。書きかけの最終行を除外し、復旧原本は保持する。自動で残りの解析は開始しない。
- Python4件成功（2曲目で急終了しても1曲目が残るテストを追加）。Swift全体113件／3skip、Swift Testing80件成功。追加のjournal復旧テスト成功（対象2件／1skip）。Debug／Release build成功。
- /Applications/HomeStereo.app更新・起動、build 20261004003656。git diff --check成功。MyMusic変更なし。Simulator testなし、端末作成／削除0。
- 2万曲長時間処理と実音源の強制終了は未実施。復旧journalの自動整理は未対応。共通契約のMyMusic側同名文書は確認できず、wire形式は変更しなかった。
