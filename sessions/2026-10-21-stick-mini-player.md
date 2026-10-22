# スティック型ミニプレイヤー

## 作業
- 会話内で調整したスモーク／ブルーメタルのカプセル型をHomeStereoへ実装。金属外周、生成した銀色テクスチャの操作部、スモークガラス表示窓、セラミック風の沈み込みボタンを追加。
- DotGothic16とOFLをMyMusicから同梱し、CoreTextでprocess限定登録。曲名とアーティストを別行表示し、MyMusicの表示幅計測・スクロール方式を移植。非active／Reduce Motion時は停止。
- MiniPlayerViewをMenuBarPlaybackViewから分離。MiniPlayerAppearance、MiniPlayerDisplayText、MiniPlayerWindowへ表示・Window責務を分割。
- 小型Windowだけで標準タイトルバーの操作ボタンを隠し、透明な余白を設定。左端の×はそのWindowを閉じ、−は最小化。表示窓のnative dragで移動する。フレーム保存keyをStickV2へ変更。
- Good／Badは既存PlaybackPreferenceStore、お気に入りはListeningStore、再生はQueueStoreを共有。連打中の非同期保存を重ねず、上限と保存エラー表示を維持。Badとメイン画面は右クリックメニューにも配置。
- 設定／メニューバー／右クリックに外観選択。appearance.mini-player-styleへ端末内保存し、全体テーマから独立。
- Xcodeの明示的なsource/resource参照とSwiftPMのresource宣言を追加。外部依存、DB、交換JSON、署名は変更なし。

## 素材
- Sources/HomeStereoDLNAApp/Resources/StickSilver.jpg: この会話でbuilt-in image_genにより生成した銀色素材をJPEGとして同梱。
- 生成prompt: Use case: product-mockup. Asset type: reusable brushed silver metal UI texture for the narrow frame and end caps of a miniature music player. Generate only a flat front-facing rectangular material swatch filling the entire square canvas edge to edge. Satin anodized silver aluminum with extremely fine horizontal brushing, subtle microscopic grain, softly varying silver values, restrained top softbox reflection. No objects, no perspective, no text, no logos, no borders, no buttons, no shadows outside the material. Neutral silver, not blue. This will be clipped into a code-defined shape, so make a continuous clean material surface, not a picture of a player.
- DotGothic16-Regular.ttfとDotGothic16-OFL.txtを同梱し、runtimeのMyMusic path依存は持たない。

## 検証
- 最終./scripts/verify.sh 成功。XCTest 145件（3 skip）、Swift Testing 86件成功、macOS Debug BUILD SUCCEEDED。
- build済みapp内のfont／OFL／textureがsourceとhash一致することを確認。
- git diff --check 成功。
- AppIntents.framework未使用に伴うmetadata extraction skipのwarningのみ。Swiftのcompile error／warningなし。
- SwiftPM testのみでSimulator／XCTestDevicesのtest端末は作成0・削除0。Xcode testは未実行。

## 未確認・運用
- ユーザー指定によりアプリ起動、/Applications配置、実曲再生は実施していない。
- 実Windowでの透明背景、×／−、drag、メニュー、VoiceOver、外観復元、長い曲名の手動確認は未実施。build／自動testをUI手動確認済みとして扱わない。


## 正式配置（追加依頼）
- ユーザーから通常利用版へ反映・起動、および複製削除の明示依頼。
- ./scripts/deploy-macos.sh --no-launch 成功。Analyzer更新、Release BUILD SUCCEEDED、ad-hoc署名検証、stage／正式配置の実行ファイルhash一致を確認。
- 正式配置: /Applications/HomeStereo.app、bundle jp.local.HomeStereo.Beta、build 20261021132817。
- SHA-256: e90b59ff3d485c609e0de0990bec3b9ebb519a03069bc9362904790b23e3c162。
- CUAで正式pathを起動し、既存ライブラリ（18887曲）の画面を確認。再生は開始していない。以後のCUA menu操作はtimeoutし、この起動での小型Window再表示は未確認。
- /tmp/HomeStereoDerivedDataと/tmp/HomeStereoDeployDerivedDataはscriptが削除。旧版20260929220132の/Applications/.HomeStereo.previous.97807も、bundle ID確認後にユーザーの複製削除依頼に従って登録解除・削除。
