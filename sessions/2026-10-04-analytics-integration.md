# PC分析機能のHomeStereo統合 Beta

## 期間分析・ランキング・月別振り返り Beta（2026-10-04）

分析で全期間／今月／先月／直近30日／任意期間を選べる。期間指定は開始日以上・終了日の翌日未満の詳細eventから集計し、MyMusic累計playCountを期間へ配分しない。全期間の既存累計優先は維持する。

ランキングは通常曲だけで曲／アーティスト／アルバム／ジャンルを回数／実聴時間で各50位まで表示する。ジャンルプリセットを全種類へ適用し、複数ジャンルはそれぞれへ計上する。アルバムはアルバム名＋曲アーティストで区別する。行から曲一覧を開いて再生・キュー追加できる。既存Queueの上限を使用する。

履歴カレンダーの表示月に通常曲の時間、代表曲・アーティスト（event件数順）、前月との時間差を表示する。期間filterとは独立した全詳細snapshotを使う。前月の記録欠落と未再生は判別できず、記録上の0として説明する。

作業用BGM／ハイレゾはランキング・概要の上位曲から除外し、分析内の別ページで期間別総時間と日別時間を表示する。分類は現在Libraryの既存判定を使い、両属性の曲は両時間ページへ含める。総概要と通常の履歴・評価は従来どおり全分類を対象とする。未解決曲の時間は用途別へ推測配分しない。

検証: ./scripts/verify.sh fastの初回はsandbox cache権限で停止。権限付き./scripts/verify.shでXCTest 134件（3 skip、失敗0）、Swift Testing 85件、macOS Debug BUILD SUCCEEDED。git diff --check成功。Xcode test／Simulatorは実行せず、test端末の作成・削除は0。実画面・再生操作は未検証。PC AnalyticsとiPhone側は変更していない。

2026-10-04、分析統合版Release 20261004234155を既存scripts/deploy-macos.shで/Applications/HomeStereo.appへ更新・起動成功。Release BUILD SUCCEEDED、署名・Bundle ID・実行ファイルSHA-256一致を確認。一時ビルドはscriptで整理。画面操作は未検証。追加testは実行せず、test端末作成・削除0。
