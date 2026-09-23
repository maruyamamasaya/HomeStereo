# HomeStereoKit Rules

この領域は旧DLNA CLI向けのSSDP、device XML、LAN HTTP配信、UPnP SOAP primitiveを担当する。macOS Appはこのtargetへ依存しない。

## Before Changing

- `Sources/HomeStereoCLI/main.swift`の呼び出し、`Tests/HomeStereoKitTests/`、`docs/dlna-playback.md`の実測条件を検索する。
- network protocol文字列、URL生成、range境界、rendererが返すservice URLへの影響を確認する。

## Conventions

- device path/portを固定せず、SSDP/Descriptionの値を使う。
- track URLへlocal file pathを露出せず、opaque UUIDとrandom tokenを保つ。
- HTTPは登録した単一fileだけを配信し、8080を使用しない。
- SOAP bodyやtokenなどの秘密性がある値を恒常logへ出さない。
- 実機未確認の挙動を成功済みとして文書化しない。

## Validation

最低限`./scripts/verify.sh fast`を実行する。network behavior変更はFullに加え、可能なら`docs/dlna-playback.md`の対象実機checkを行い、未実施ならsessionへ明記する。
