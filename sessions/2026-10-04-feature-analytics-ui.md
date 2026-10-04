# 特徴量・分析・JSON編集・ページ操作UI

## 作業
- HomeStereoに対する継続依頼としてMATCH。別Gitのrootを確認して作業。MyMusic側は変更なし。
- 共通交換契約revision 2を両repositoryで照合し、本文一致をcmpで確認。
- 特徴量UIを読み書き／解析・音量／検索・照合filter／広い詳細へ整理。ローカル照合と両方向で一意なCanonical ID一致を別チェックで表示。
- 分析は日／週カレンダー、直近7日のVoice分類、評価−10〜＋10と未設定のdrilldown、専用完走・スキップページを追加。historyDaysだけ500件上限を外し、recentEventsは500件を維持。
- 主要ページの実行ボタンを本文ヘッダーへ移動し、右上はpanel開閉中心にする方針をAGENTS.mdへ記録。
- MyMusic連携から特徴量JSONの入出力を可能にした。JSON加工ツールに特徴量snapshot／Analyzer編集、手順、日本語ラベル、項目検索、特徴量のみfilter、保存時FeatureCodec検証を追加。編集はファイルだけへ保存。
- 起動時の出力をこのMacに変更。再生バーのGood／Badを再生ボタン群へ移動。Artworkとmetadataを中央配置し、960px前後の幅でもsplit panesが収まるよう最小幅を調整。

## 検証
- swift test: XCTest120件（3skip）、Swift Testing84件、失敗0。
- 620件の履歴がcalendarに残る回帰テスト、Voice判定の保留・未解析、Canonical ID競合を緑表示しないテスト、特徴量JSON編集と不正スコア拒否・DB不変更テストを追加。
- Debug Xcode build成功（追加の出力初期値・中央配置変更前）。最終Release buildと配備も成功。
- git diff --check成功。Simulator／XCTestDevicesを使用せず、test端末作成・削除0。

## 制約
- Voice分類は最新解析版のvocalとinstrumentalスコア差0.1を基準にした目安で、確率ではない。
- カレンダー、時間、率は残っている詳細履歴のみ。削除済み履歴をMyMusic playCountから復元しない。
- 同じtitleのAlbum groupingなど前の依頼と、既存の未commit解析並列変更を維持。
- 追加依頼でGood／Badをメイン再生バーだけ44×44pt・21ptアイコンへ拡大。クリック範囲をRectangleで明示し、背景・評価数badgeも拡大。起動ページは曲一覧へ変更し、初期出力の専用テスト成功。
- カレンダーの追加デザイン依頼に対応。正方形grid、月末余白、土日palette、選択枠・gradient、今日indicator、日付・件数のaccessibilityを追加。テーマ別color tokenをHomeStereoThemeへ置き、wide／compactで左右／上下に切り替える。履歴は同一ScrollView内LazyVStackへ変更して狭い画面でも下までスクロール可能にした。
- 再生バーの他の操作も44ptへ統一。再生ボタンをaccent背景、前後／お気に入り／shuffle／repeatを共通styleにし、PlaylistStoreの既存add処理を使う追加選択パネルと読み取り専用の曲情報popoverを追加。compact表示は音量を別行に配置。
- カレンダーの追記要望で日付12pt・件数23pt、wideで700pxのcalendarと230〜340pxのhistoryへ変更。小さい幅では上下に並べる。履歴rowは細い列で読める3段構成に変更。

## 最終配備・表示確認
- Release clean build成功。`/Applications/HomeStereo.app` build `20261004140740`へ配備し、署名・実行ファイルhash一致・正規bundleからの起動を確認。
- 1920×1080の実画面で正方形calendar、日付より大きい件数、土日の配色、選択日、細い履歴列、拡大された再生操作の表示を確認。AXでも日／週picker、4日39件、追加・詳細ボタン、このMac出力を確認。
- CUAのnative入力接続が繰り返し切断されたため、最終版のpopover・各filterの自動クリック検証、および約960pxでの実操作検証は未完了。表示取得とRelease buildは成功しており、app自体のクラッシュとは確認されていない。
- 最終差分チェック成功。Simulator使用なし、test端末作成・削除0。
