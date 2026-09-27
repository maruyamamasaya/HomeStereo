# MyMusic relativePath linking

- MyMusic Library v1へoptionalの`relativePath`と`fileSize`を接続し、絶対path、空component、`.`／`..`をHomeStereo Importで拒否する。
- HomeStereoの照合順を、保存済みMyMusic ID、正規化relative path、同候補のsize／duration検証、パス候補がない場合だけfingerprint、一意metadataへ変更した。pathが一致してsize／durationが矛盾する場合は自動fallbackしない。
- HomeStereo内部Track IDは維持し、MyMusicから受け取った`trackID`を`mymusic_track_links`の外部Canonical IDとして保存する。相対pathからHomeStereo IDを再生成しない。
- `./scripts/verify.sh fast`はXCTest 65件中64件成功・性能test 1件skip、Swift Testing 67件成功。対象matcher／JSON contract 21件も成功した。
