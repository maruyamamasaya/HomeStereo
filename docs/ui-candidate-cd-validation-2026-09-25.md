# UI候補C・D 検証結果

2026-09-25時点の、スピーカー状態／通信エラーと管理画面改善の検証記録。

## 実装した範囲

- スピーカーを選択中優先＋名称順で安定表示し、最終検索時刻と検出台数を表示
- 検出済み、選択中、通信不明、network待機、再接続中、再接続済み、切断を文言とiconで区別
- 通信失敗を操作を遮らないバナーで表示し、再試行と閉じる操作を提供
- Sony機のWireless Stereo構成は、標準UPnP情報で確定できない場合に推測せず未確認と表示
- 音楽フォルダ画面を、概要、空状態、フォルダ単位の更新、進捗、アクセス失敗、詳細へ再構成
- バックアップ画面を、保存対象／対象外、手順、復元前確認、結果表示へ再構成
- 利用者向け画面では「Renderer」「scan」「missing」「Import／Export」などを日本語へ整理
- 主要操作をToolbarへ、低頻度またはdestructive操作をmenu／確認dialogへ整理

## 自動検証

- `./scripts/verify.sh`: 成功
- XCTest 32件成功、Swift Testing 41件成功、macOS Debug build成功
- スピーカーの安定順、選択中優先、最終検索時刻を確認するtestを追加
- 通信エラーのdismissと、正常応答後のerror解消を確認するtestを追加

## 画面確認

- 別Bundle IDの一時プレビューで、スピーカー未検出状態、最終検索時刻、再検索、出力先の日本語表示を確認した。
- 同プレビューで、音楽フォルダの概要、自動更新、空状態、追加操作、無効な一括更新を確認した。
- どちらもアクセシビリティ階層にbutton description、help、状態文言が現れることを確認した。

## 実施できなかった検証

- SRS-HG1／HG10実機での切断、再接続、電源状態遷移とエラーバナーの目視確認
- Sony固有serviceからWireless Stereoのgroup／L／Rを取得できるかの実機調査
- 複数の実機Rendererを同時検出した状態での並び順と選択維持
- VoiceOverでSidebarから曲選択、再生、フォルダ管理、復元確認まで進む通し操作
- macOS Full Keyboard AccessですべてのToolbar／menu／Disclosureへ到達できるかの通し操作
- 実ユーザーデータを使った音楽フォルダの長時間scan、アクセス権喪失、notice大量表示
- バックアップ画面は切替時にUI自動操作基盤の接続が切れたため、build成功までの確認。実ファイルpanelを使った書き出し／preview／復元も未実施
- Light／Dark、文字サイズ変更、狭いwindowでの全対象画面の目視確認

## 残る課題

- Wireless StereoのL/R表示は、安全に読めるSony固有情報が確認できるまで追加しない。
- 実機やVoiceOverを必要とする項目は、[`ui-improvement-backlog.md`](ui-improvement-backlog.md)で`確認待ち`として扱う。
- 下部バーのシーク（UI-015）と音量（UI-016）は候補C・Dの対象外で未着手。
