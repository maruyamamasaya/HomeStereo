# 曲一覧アイコンのクリック範囲

- HomeStereo側の変更を明示依頼されたため、HomeStereoのGit rootとAGENTS.mdを確認して作業。
- `SongsTable`の再生／キュー追加／プレイリスト追加／お気に入り／Good／Badのlabelに`contentShape(Rectangle())`を追加。22×24ptの既存透明枠全体をクリック対象にし、アイコン・行・間隔・badgeの描画は維持。
- 既存の未コミット変更は保持。Store、永続化、アーキテクチャ変更なし。
- `swift test`: XCTest 145件（3件skip）、Swift Testing 92件、失敗なし。
- 実UIの周辺クリック、VoiceOverの手動確認と正式アプリへの配置は未実施。
- `./scripts/verify.sh`完了、macOS Debug buildは`BUILD SUCCEEDED`。`git diff --check`成功。Simulator／XCTestDevicesの作成・削除なし。
