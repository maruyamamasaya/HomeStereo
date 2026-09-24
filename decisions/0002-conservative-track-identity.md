# 0002 Conservative Track Identity

Status: Accepted
Date: 2026-09-24

## Context

音源のrenameやfolder内移動で新しいTrack IDを発行すると、Playlist、Favorite、履歴、Queueの参照が失われる。一方、同サイズや同じmetadataだけで統合すると別音源を誤接続する。

## Decision

同一登録folder内だけで、次の順に照合する。

1. folder ID＋正規化relative path
2. macOS file resource identifierの一意一致
3. file size、duration、拡張子、codec、sample rate、bit depth、channel count、title、artist、album artist、albumの一意一致
4. 一意でなければ新規Track

resource identifierは補助証拠であり永続的絶対保証とはしない。full-file hashは通常scanで計算しない。判定はscan結果にのみ反映し、pathとIDはSQLite transaction成功時に同時確定する。

## Consequences

- 同一folder内の通常rename／移動はTrack IDと全参照を維持できる。
- hard link、複製、同一metadataの複数候補は自動統合しない。
- folder間／volume間移動は別Trackになり得る。
- JSON Backup schema v1は変更せず、従来hint照合を維持する。
