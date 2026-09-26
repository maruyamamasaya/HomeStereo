# MyMusic manual transfer

- 管理Sidebarへ「MyMusic連携」を追加し、Library、Preferences、Playback Eventsの個別手動Import／Exportを実装した。
- Importは標準open panel、security-scoped read、root／version検証、最大100件のPreview、確認後のPersistence Service適用という順序にした。
- Exportは標準save panelと既存Serviceを利用し、Playback Eventsのexport件数、未解決除外件数、保存先、再接続案内を表示する。
- 自動同期、folder監視、iCloud同期は追加していない。MyMusic側のPlayback Events Importは未実装として文書化した。
- `./scripts/verify.sh`でXCTest 59件（performance 1件skip）、Swift Testing 60件、Xcode Debug buildを確認した。
- ビルド済みアプリでSidebarへの「MyMusic連携」追加と起動を確認した。詳細画面の自動目視取得は、同一bundle IDのインストール版と検証版が同時起動している環境でUI検証接続が切れたため未完了とした。
