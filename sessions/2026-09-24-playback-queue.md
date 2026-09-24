# Session: playback queue
Date: 2026-09-24

## Request
永続Queue、編集、連続再生、Shuffle／Repeat、通信切断時の安全性。

## Changes
- Queue snapshotをSQLite schema v2へ追加した。
- 曲／Album／Artistのcontext menuから今すぐ／次／末尾追加を可能にした。
- AVTransportがPLAYINGからSTOPPEDへ遷移した時だけ次曲へ進む。
- Queue編集は現在のHTTP serverを停止しない。

## Validation
- Unit Test 33件、失敗0。
- macOS Debug build成功。

## Remaining Issues
- SRS-HG1で2曲以上の連続再生は未確認。
