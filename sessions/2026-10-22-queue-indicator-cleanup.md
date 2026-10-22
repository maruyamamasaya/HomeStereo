# キュー挿入線の残留対策

- HomeStereo UI修正としてMATCH。Git root、AGENTS、現在状態とキュー構成を確認。別作業の再生診断等を含む既存変更は保持。
- 行のdropExited／performDropだけではdrag中止や領域外終了時に挿入線が残り得るため、表示中だけAppKitで左ボタン・画面座標・Escを監視するbackground viewを追加。入力のhitTestはnil、eventはそのまま返す。監視は解除／view破棄で停止する。
- 末尾追加領域への移動・画面離脱でもdropOffsetを解除。現在状態・構成文書を更新。Queue保存／挿入順序は変更なし。
- ./scripts/verify.sh成功。XCTest 145件（3件skip、失敗0）、Swift Testing成功、macOS Debug BUILD SUCCEEDED。git diff --check成功。実UIでのdrag終了／領域外移動／Esc確認は未実施。/Applicationsへの配置は未実施。
- XCTestDevicesは前後ともUUID folderなし、12K（.DS_Storeのみ）。test端末作成0／削除0。DerivedData削除なし。
