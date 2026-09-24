# Track Identity

TrackへopaqueなmacOS file resource identifierを追加し、SQLiteをschema v6へtransactional migrationした。同一folder内でpath、resource identifier、音源仕様＋metadataの一意一致を順に評価し、rename／移動／missing復帰時は既存Track IDを維持する。曖昧候補は新Trackにし、理由をscan noticeへ残す。full-file hash、folder間統合、JSON schema変更は行っていない。

同一path、rename、folder内移動、同サイズ別曲、metadata重複、missing復帰、v5 migration、transaction rollback、Queue／Playlist／Favorite／履歴の参照維持をtestした。macOS Debug buildと全testを実行する。
