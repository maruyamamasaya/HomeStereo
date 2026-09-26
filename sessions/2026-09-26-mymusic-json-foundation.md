# Session: MyMusic JSON foundation
Date: 2026-09-26

## Request
iPhone版MyMusicとの将来連携に向け、曲一覧、Preferences、Playback Eventsを別JSONとして扱う基盤を追加する。

## Investigation
現行のTrack、Favorite、PlaybackEvent、既存Backup codecとtransactional mergeを確認した。現行PlaybackEventはMyMusic eventの全属性を保持しないため、JSON DTOを既存modelへ直接混在させず交換modelを設けた。

## Changes
- 3文書のfield名とversionに対応するCodable DTOとUTF-8 JSON codecを追加。
- 未対応version、UTC日時、有限非負秒数、列挙値、重複ID、SHA-256、Preferences値域、completed/skipped矛盾を文書全体で検証。
- JSON非依存の交換modelとImport／Export serviceを追加。Track IDを再生成せず保持する。
- 現行Track／Favorite／PlaybackEventから曲一覧の派生値とmacOS eventを作るadapterを追加。
- 契約testと設計文書を追加。

## Validation
- `swift test --filter MyMusicJSONContractTests`
- `./scripts/verify.sh fast`

## Result
JSON契約と変換境界を追加した。Import serviceは永続化前に文書全体を検証するため、不正文書の部分保存は行わない。

## Remaining Issues
UIからのfile選択とSQLiteへの文書単位mergeは未接続。`playbackPreference`やMyMusic固有event属性を永続化する場合はschema migrationを別途設計する。
