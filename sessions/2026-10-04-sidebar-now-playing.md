# Sidebar / Now Playing整理

- HomeStereoへの明示依頼により別Git rootを確認して作業。既存の解析同時数関連の未コミット変更を保持。
- DLNAContentView: 音源の特性sectionを廃止しBGM／ハイレゾをライブラリへ。直下にプレイリストsection、音楽特徴量／分析は管理、ジャンルプリセットは設定、MyMusic関連3画面は独立section。
- 下部バーのArtwork／曲名をplain Buttonにし、既存destinationで再生中画面へ遷移。Artworkは210→340pt、曲情報上に配置しScrollViewを維持。
- Store／再生処理／JSON／DB／アーキテクチャ変更なし。CURRENT更新。
- verify.sh成功: XCTest 115件（3 skip、失敗0）、Swift Testing 80件成功、Debug BUILD SUCCEEDED。最初のsandbox内検証はcache書込み権限で失敗、権限付きで成功。
- deploy-macos.sh成功: Release BUILD SUCCEEDED、署名／配置hash検証成功、/Applications/HomeStereo.app、build 20261004115522。
- UI確認で旧processを検出し通常終了後、正式pathで再起動。更新後Sidebar全項目と下部曲情報ButtonをAX treeで確認。Buttonクリック時にUI自動操作接続が切断し、遷移後画面と実曲Artworkの目視確認は未完了。
- xcodebuild test／Simulatorは使用せず、test端末作成・削除0（swift testのみ）。
