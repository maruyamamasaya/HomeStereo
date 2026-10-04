# AI Agent Guide

ソースコード・設定・テストを実装事実の正本とする。文書との矛盾は実装で確認し、実装事実・意図された仕様・不具合を混同しない。不明点は推測で確定しない。

## Navigation and Context Budget

必要な範囲だけを段階的に読む。

```text
Level 1  このAGENTS.md + CURRENT.md
Level 2  関連するARCHITECTURE.md / CODEMAP.md
Level 3  semantic / exact / symbol search結果
Level 4  対象ファイルと最も近いAGENTS.md
Level 5  references、依存、関連テスト、設定
```

基本フローは`Task -> rules/current -> code map -> search -> target -> references/tests -> change`。全ファイルの順次読みは行わない。起動・署名・実機・networkは`OPERATIONS.md`、検証は`TESTING.md`、重要判断は`decisions/`を参照する。

## Search Strategy

- 概念だけ分かる: 利用可能ならsemantic/repository searchで候補を得る。
- symbolが分かる: symbol definition/reference search、なければ`rg`/`git grep`で完全一致する。
- path、error、key、option、HTTP文字列: `rg`/`git grep`を使う。
- 影響範囲: definition、references、tests、configuration、data/OS dependenciesを確認する。

semantic searchの結果は確定情報ではない。正確なsymbolや文字列を得た後、exact/reference searchで実コードへ着地する。具体的な入口と検索語は`CODEMAP.md`を正本とする。

## Scoped Rules

対象ファイルに近い`AGENTS.md`を追加ルールとして読む。

- `Sources/HomeStereoAppCore/AGENTS.md`: App state、folder/library/playback境界
- `Sources/HomeStereoKit/AGENTS.md`: DLNA discovery、HTTP、SOAP、network安全性

macOS Appと旧DLNA CLIは混同しない。分離理由は`decisions/0001-separate-app-and-dlna-cli.md`を参照する。

## Change Rules

MyMusicとの連携変更では、[共通データ交換・保全契約](docs/data-interchange-contract.md)を読む。別GitのMyMusic側の同契約とrevision・本文を照合し、未照合データ、競合、部分snapshotを削除扱いしない。文書の要件と実装済み保証を区別する。

段階的な対策と未解決事項は[データ連携の保全課題](docs/data-interchange-issues.md)で管理する。

- 要求範囲だけを小さく変更し、検索性だけを理由に大規模rename/refactorしない。
- 変更前にdefinition、呼び出し元、呼び出し先、test、設定を確認する。
- 既存のprotocol境界とsandbox制約を尊重する。
- 秘密情報、実token、password、個人音源pathを文書やlogへ残さない。
- 将来の理解に必要な重要判断だけを`decisions/`へ追加する。

## Validation

実装中は`./scripts/verify.sh fast`、完了前は原則`./scripts/verify.sh`を使う。実機依存項目を実行できない場合は成功扱いにせずsessionへ残す。詳細と変更別mapは`TESTING.md`を参照する。

## Documentation Updates

同じ説明を複製せず、詳細の正本へlinkする。更新条件は次の通り。

- `CURRENT.md`: 現在状態が変わったとき
- `ARCHITECTURE.md`: system構造やdata flowが変わったとき
- `CODEMAP.md`: 主要入口、配置、検索語が変わったとき
- `TESTING.md`: commandや検証方針が変わったとき
- `OPERATIONS.md`: 起動、設定、運用、deployが変わったとき
- `decisions/`: 重要な設計判断が発生したとき
- `sessions/`: AI作業終了時に短い結果を残す

`README.md`は人間向け利用方法、`sessions/`は履歴、`CURRENT.md`は現在地に限定する。

## ページ内の操作ボタン

- 読み込み、書き出し、バックアップ、復元、作成、更新、キュー生成などの実行操作は、対象ページ内のヘッダーまたは関連セクションへ配置する。
- メインウィンドウ右上のtoolbarは、再生キューなどのパネル／インスペクタを開閉する操作を中心にする。主要な実行操作をtoolbarだけに置かない。
- シート／ダイアログの完了・キャンセルは、そのシート内の標準配置を使用する。
- 操作の順序、対象件数、結果やエラーをページ内で確認できるようにする。
