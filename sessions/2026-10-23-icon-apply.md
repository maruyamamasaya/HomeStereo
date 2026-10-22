# AppIcon適用

- 承認されたネイビー・黒いレコード・アイボリーのトーンアーム候補から、画像生成で外側背景を透過化。
- AppIcon.appiconsetの全10 PNG（16〜1024px）をsipsで生成して置換。Contents.json・project設定・アーキテクチャ変更なし。
- 全画像の寸法・alpha channel、128pxでの外観、git diff --checkを確認。
- macOS Debug build成功。初回はsandbox内でSwiftマクロ実行に失敗し、権限付き再実行で成功。
- 画像のみの変更のためswift test／verify.shは省略し、実際のXcode buildで検証。test端末の作成・削除なし。
- /Applicationsへの配置・実Dock/Finder表示の確認は未実施。Analyzerも次回installer実行時に共通画像から更新される。
