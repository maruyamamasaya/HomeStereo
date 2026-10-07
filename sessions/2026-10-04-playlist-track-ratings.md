# プレイリスト内の評価操作

- HomeStereoのプレイリスト曲行にお気に入りとGood／Badを追加。DLNAContentViewから既存の共有ListeningStore・PlaybackPreferenceStoreを受け取る。
- NowPlayingPreferenceControlsの評価操作をTrackPreferenceControlsへ抽出し、再生画面とプレイリストで共有。数値badge、−10〜＋10の上限、保存失敗表示、曲名付きaccessibility labelを維持。
- データモデル・保存経路・MyMusic JSON形式は変更しない。既存の評価保存・Preferences変更検知を使用。ARCHITECTUREの更新は不要。
- 既存の評価上下限・永続化テストを含む全体検証を実施。UIの配線以外に新しい業務ロジックは追加していない。

## 検証・配置
- ./scripts/verify.sh成功。XCTest126件（3件skip・失敗0）、Swift Testing85件成功。Debug BUILD SUCCEEDED。git diff --check成功。
- ./scripts/deploy-macos.sh成功。/Applications/HomeStereo.app、jp.local.HomeStereo.Beta、build 20261004170038。Release Build／Install／Launch成功。
- 実画面で曲行のハート、Good／Badと既存評価badgeを確認。利用者の評価を確認目的で変更していない。
- Simulator testは実施していない。test端末作成／削除0、XCTestDevices UUID folder0、総容量12K（metadataのみ）。
