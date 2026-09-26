# Session: Sony Stereo Bridge Phase 3

Date: 2026-09-25

## Request

2台の実音同期、Delay補正、10回反復、10分driftを検証する。音量は非常に小さくする。

## Investigation

MacのAVFoundation録音入力を確認したがdeviceが列挙されず、実音の自動収録はできなかった。UPnPの位置は整数秒粒度なのでms測定には使えない。

## Changes

- ピーク-50.5dBFSの同一click WAVを自動生成するscript
- `play-pair --runs`、1ms Delay、status interval、JSON timing report
- loopback限定Web UI、Delay preset、反復、極小click生成、実音offsetと評価の記録

## Validation

- 4秒clickを0ms Delayで10回実機再生
- Play送信差は全10回0ms
- SOAP完了差は-11〜+59ms、平均+18.3ms、標準偏差19.9ms
- 全10回で左右ともHTTP取得、4秒完走、STOPPED
- Web UIの表示、preset、click生成、status/logをブラウザ確認

## Result

control timingの10回反復は安定したが、SOAP完了は音響開始ではないためPhase 3成功とはまだ判定しない。

## Remaining Issues

利用者または外部マイクによる実音offset入力、Delay補正後の二重音低減、開始・1・3・5・10分のdrift記録が必要。完了までPhase 4へ進まない。
