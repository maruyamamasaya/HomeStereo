# HomeStereoAppCore Rules

この領域はmacOS Appのmodel、observable state、folder/library/playback service境界を担当する。UI表示とDLNA実装を持ち込まない。

## Before Changing

- 対象型のprotocol、`PlaybackStore`からのreference、対応する`Tests/HomeStereoAppCoreTests/`を検索する。
- main-actor境界、security-scoped resourceの開始/終了、`AVQueuePlayer`所有権を確認する。

## Conventions

- ViewからOS serviceを直接操作させず、既存protocol境界を維持する。
- test可能な処理はfake/in-memory実装へ差し替えられる形を保つ。
- user-facing failureは`UserFacingError`または既存callback経由で扱う。
- folderは読み取り専用とし、音源をcopy、変更、削除しない。
- `AudioPlaybackService`だけがplayer/queueを所有する。

## Validation

最低限`./scripts/verify.sh fast`を実行する。UI、entitlement、Xcode構成へ影響する変更はFullと`TESTING.md`の手動確認も行う。
