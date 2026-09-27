# ローカル再生分析

## 境界

分析はHomeStereo内のSQLiteだけで完結し、外部通信、account、telemetryを使わない。再生経路は`QueueStore`から`ListeningStore`へ開始、位置、状態、終了理由を通知する。Viewは再生判定を行わず、`AnalyticsSnapshot`だけを表示する。

```text
QueueStore callbacks
  -> ListeningStore / MyMusicPlaybackSession
  -> SQLiteLibraryRepository
  -> AnalyticsService
  -> AnalyticsStore
  -> AnalyticsView
```

Favoriteは`favorites`、Good／Badは`track_preferences`を正本とし、再生履歴と分離する。MyMusic Preferencesを取り込んだ場合は同じローカルPreferenceへ反映する。

## 判定

- 正式再生: 自然終了、または`min(30秒, 曲長の50%)`以上の実聴
- 完走: 有効な曲長の94%以上
- Early Skip: ユーザー離脱かつ実聴30秒以下
- 曲長が0、NaN、不明の場合は完走にしない。正式再生は30秒以上だけを数える
- pause中とseek距離は実聴時間へ含めない
- repeatもsessionごとに別event IDを持つ

閾値は`MyMusicPlaybackPolicy`へ集約する。開始入口はlibrary／album／artist／search／playlist／queue／shuffle／favorite／history／station／unknown、選択種別はmanual／userAdvanced／automatic、終了種別はnatural／userSkipped／otherを保存する。

## 集計値の正本

MyMusic Library JSONに1件でも`playCount`がある場合、総再生回数、曲別再生回数、上位曲、評価別再生回数はそのsnapshotを正本にする。紐付け不能のMyMusic曲も総再生回数には含める。これにより、詳細eventを持たない旧MyMusic履歴もMyMusicアプリと同じ回数になる。

今日／直近7日／直近30日の回数、総再生時間、完走率、Skip率、履歴一覧は詳細eventを正本にする。Library JSONには日別内訳と実聴時間がないため、全期間の集計済み回数から推測しない。Library JSONに`playCount`が1件もない場合だけ、従来どおり詳細eventの正式再生数へfallbackする。

## Schema v12

- `mymusic_playback_events`: raw session event。`event_id`が主キー。`ended_at`と`end_kind`を追加し、Track削除でcascadeしない
- `playback_track_summaries`: Track単位の回数、期間、時間、完走、Skip、連続／repeat集計
- `playback_daily_summaries`: 再生開始日単位の回数、時間、完走、Skip、Early Skip
- `playback_source_summaries`: 日付・Track・入口単位のsession／正式再生数
- `track_preferences`: `-10...10`のローカルGood／Bad評価
- `mymusic_library_play_counts`: Library JSONから取り込んだMyMusic Track ID単位の`playCount`、`lastPlayedAt`、取込日時。HomeStereo Trackとの対応はlink表から読み取り時に解決し、未紐付け行も保持する

raw event挿入と3種の集計更新は単一transactionで行う。同じevent IDの再挿入は無視し、集計も増やさない。v10以前からのmigrationでは終了日時・終了種別を補完し、既存eventから集計を再構築する。migration全体はtransaction内で実行する。

## UIと更新

Sidebarの「分析」に概要、上位10曲、日別履歴、理由付き傾向、評価別集計を表示する。履歴は直近500件をsnapshotへ載せる。Libraryまたは履歴revision、Preference変更、MyMusic Importでsnapshotを再構築し、先行taskはcancelする。曲を解決できないeventは「不明な曲」として残す。

履歴の再生元はPlayback Events JSON v1の既存`platform`を変更せず利用する。`macOS`は「Mac」、`iOS`／`iPhone`／`iPad`は「App」、未知値は元の文字列を表示する。HomeStereo生成eventは従来どおり`macOS`なのでMyMusicアプリ側の変更は不要。Library JSONの`playCount`はeventごとの`platform`を持たないため、Library JSONだけから過去のApp／Mac内訳は復元できない。

曲単位または全履歴を削除できるが、Favorite、Good／Bad、Playlist、Track metadataは削除しない。

## 既知の制約

- 初期版の履歴UIは日別リストで、月カレンダー表示は含まない
- 傾向は説明可能な期間差・回数・空白期間だけを使い、推薦や自動選曲にはまだ利用しない
- snapshotはraw eventから生成する。永続集計は高速参照と将来の選曲利用向けに保持する
