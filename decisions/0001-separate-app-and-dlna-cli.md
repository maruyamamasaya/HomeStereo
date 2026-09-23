# 0001 Separate the macOS App and DLNA CLI

Status: Accepted  
Date: 2026-09-23

## Context

リポジトリには、Apple標準出力先UIを使うmacOS Appと、LAN内rendererへ直接配信・制御する旧Phase 1 DLNA CLIが共存する。protocol、sandbox/network権限、検証条件が異なる。

## Decision

`HomeStereoApp`/`HomeStereoAppCore`と`HomeStereoCLI`/`HomeStereoKit`を別target・別実行経路として維持する。現在のAppからDLNA Kitへ依存させない。

## Reason

AppのMVPはAVFoundationとmacOS標準routingに限定でき、実機依存のDLNA探索・HTTP server・SOAP制御を製品挙動や権限へ混入させずに済む。旧実証コードと実測知識は失わず保持できる。

## Alternatives

- DLNAコードを削除する: 実測済みの検証資産を失う。
- Appへ直ちに統合する: 要求外のnetwork権限・UI・状態管理が増え、未確認挙動を製品へ持ち込む。
- 共通抽象へ先に統合する: 現時点では利用経路と要件が異なり、抽象化の根拠が不足する。

## Consequences

- build/test/documentationでは2経路を明示的に区別する。
- DLNA統合には別の要求、実機検証、権限設計、Decisionが必要になる。
- 一部の音源形式や再生概念が重複しても、必要性が出るまで共通化しない。
