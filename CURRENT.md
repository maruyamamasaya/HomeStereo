# Current State

HomeStereoは、ローカル音源とApple標準出力先UIを使うmacOS 14以降向け技術検証である。MyMusicとは独立し、旧DLNA CLIも別targetとして保存されている。構造の詳細は`ARCHITECTURE.md`を参照する。

## Current Phase

macOSローカル再生MVPの実装と基本検証は完了。AirPlay受信機を使う実機確認が残っている。DLNA CLIはPhase 1検証の状態で、macOS Appには統合されていない。

## Implemented

- SwiftUIの曲一覧・設定・player UI、folder選択とbookmark復元
- AVFoundationによるscan/metadata取得と`AVQueuePlayer`再生
- `AVRoutePickerView`による標準出力先選択
- sandbox/read-only file accessとAppCore/Kit自動test
- 独立DLNA CLIのSSDP、device XML、HTTP配信、SOAP操作

## In Progress

- コード上で進行中の機能はない。
- 運用上はAirPlay実機での最終確認待ち。

## Known Issues

- Apple標準出力先UIでの実AirPlay機器表示と、接続中の再生操作・転送形式は未確認。
- DLNA CLIのPause/Resume/Stop、IP変更後の再探索、Wireless Stereoは未確認。
- 対応拡張子でもcodec、破損、DRMにより一覧から除外される場合がある。
- lint、独立typecheck、CI、UI testはなく、Xcode projectとSwiftPMでsource構成を二重管理している。

## Next Actions

1. 同一Wi-Fi上の対応受信機でAirPlay表示と基本操作を手動確認する。
2. 結果をREADME、`OPERATIONS.md`、該当sessionへ記録する。
3. DLNAを継続する場合は`docs/dlna-playback.md`の未評価項目から着手し、App統合は別判断として扱う。
