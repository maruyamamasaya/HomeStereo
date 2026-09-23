# Session: Search and Verification Foundation

Date: 2026-09-23

## Request

既存AI開発基盤を、検索優先・階層rules・小さいcontext・Fast/Full自動検証へ強化する。

## Investigation

基盤文書、source/test、設定を照合した。役割分担は有効だが、検索手段の使い分け、feature別の検索入口、標準Verify commandが不足していた。検索性を阻害する明白な命名問題は見つからなかった。

## Changes

root rulesを検索/context予算中心に整理し、AppCoreとDLNA Kitだけにscope rulesを追加した。SwiftPMでは両文書をtarget入力から除外した。CODEMAPをfeature別入口へ変更し、Fast/Fullを持つ`./scripts/verify.sh`を追加した。CURRENTとsession templateの重複を削減した。

## Validation

- `sh -n scripts/verify.sh`: 成功
- `./scripts/verify.sh fast`: 成功（XCTest 9件、Swift Testing 7件）
- `./scripts/verify.sh`: 成功（同test + macOS Debug build）
- AirPlay/DLNA実機試験: application behavior未変更のため未実施

## Result

concept searchからexact/reference/testへ絞り込み、1 commandで検証へ進める導線を整備した。

## Remaining Issues

semantic index、専用lint/format、CI、UI/E2E、実機検証の自動化は現在のtoolchainにはない。
