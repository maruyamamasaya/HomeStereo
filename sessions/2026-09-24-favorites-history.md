# Favorite and playback history phase

- FavoriteをTrack IDと登録日時で永続化し、通常／Shuffle再生と個別リセットを追加。
- 再生イベントを一意ID、開始日時、実再生秒数、完走／途中停止で保存。
- 同一event IDはupsertして重複せず、missing Track参照も自動削除しない。
- 最近再生、よく聴く、未再生画面と履歴の個別リセットを追加。
- 非アクティブ化、通信失敗、停止時に途中の履歴を保存する。
- `./scripts/verify.sh`: 38 tests passed、macOS Debug build succeeded。
- SRS-HG1での履歴記録は実機確認まで保留。
