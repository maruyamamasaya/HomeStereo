# ジャンル表示プリセット

- Sidebarへ専用管理画面を追加し、作成、編集、削除、上下移動、ジャンル検索、全選択／解除、ジャンル未設定を実装した。
- 曲一覧上部へ「すべて」と各プリセットのタグを表示し、複数ジャンルをOR条件で即時filterする。既存の単一ジャンルfilterとは排他的に切り替える。
- SQLite schema v13の`genre_display_presets`へ配列順と編集内容をtransaction保存する。
- iPhone互換の`mymusic.genre-display-presets` version 1を未知fieldを含めて全体検証し、`MyMusic-Genre-Display-Presets.json`としてImport／Exportする。同名Importは既存IDを維持して更新し、新規項目は末尾へ追加する。
- `作業用BGM`と`ハイレゾ`は固定分類として編集候補から除外し、preset filterでは常に表示対象に含める。LibraryにないImport済みジャンルは再編集・再出力時も保持する。
- Mac AnalyticsやiPhoneのApplication Supportへ直接書き込まず、versioned JSONだけを交換境界とする。
- `./scripts/verify.sh`で自動testとmacOS Debug buildが成功した。
- デプロイ後の実画面で、Sidebarの専用ページ、空状態、Library由来のジャンル候補を使う新規作成editor、検索・全選択／解除・未分類設定を確認した。利用者データを変更しないため、実データの作成とfile panelを伴うImport／Export操作は行っていない。
- `./scripts/deploy-macos.sh`でRelease build、署名検証、`/Applications/HomeStereo.app`への置換、起動まで成功した。bundle versionは`20260927213450`、実行fileのSHA-256は`1019d00e77ab5beef28c81496d76374e146bca38b8bec74f27bcc9319c21dee4`。
