# 最大100曲のキュー作成・全クリア

- HomeStereoへの継続依頼（MATCH）。別Git rootを確認。既存の音楽解析とSidebar変更を保持。
- LibraryViews／ListeningView: 曲・Album・Artist・お気に入り・履歴の表示中集合、Album／Artist詳細へ共通「最大100曲でキュー作成」を追加。
- QueueStore: 利用可能曲だけを重複排除して待ち曲を置換。再生中／pause中のQueueItemを保持して全体100曲以内。自動再生なし。候補超過時、重み1+max(0, Good)、上限Good10の非復元抽選（exponential race）を採用。上限内は候補順維持。
- QueueView: 狭いInspector向け2段header、確認付き「すべてクリア」。clearで現在曲の履歴を終わらせるcallbackを除去し、先読みtaskだけcancel。音源／Playlist／履歴を削除しない。
- CURRENT／ARCHITECTURE更新。DB／交換JSON／依存変更なし。
- fast成功。full成功: XCTest115（3 skip、失敗0）、Swift Testing83成功、Debug BUILD SUCCEEDED。追加3テストで上限／重複／Good優先／他曲の抽選余地、missing除外、非自動再生、現在曲保持、clear後の継続とSQLite保存を確認。初回追加テストの仮音源ファイル不足を修正。単一の現在曲候補を追加後、対象3テストも再成功。
- Release BUILD SUCCEEDED、deploy-macos.sh成功。/Applications/HomeStereo.app build20261004125127、署名／hash検証成功。
- UI: 曲一覧のbuttonから実候補12,113曲→100曲のキュー作成を確認。Inspectorにすべてクリアを表示し確認dialog／cancel成功。生成100曲を保持、再生は開始していない。各画面全体、実音再生継続、VoiceOver／狭いwindow通し確認は未実施。
- xcodebuild test／Simulator不使用。test端末作成0・削除0（swift testのみ）。
