# FLAC Vorbis metadata

- FLACで`commonMetadata`が空になるmacOSの挙動に対し、format固有のVorbis Commentも同じ正規化処理へ通すようにした。
- タイトル、アーティスト、アルバム、アルバムアーティスト、ジャンル、年、作曲者、曲番号／総曲数、ディスク番号／総ディスク数を取り込む。
- metadata versionを5へ更新し、既存曲を次回スキャンで再解析する。
- タグ付きの実FLAC fixtureを含む自動テストを追加した。
