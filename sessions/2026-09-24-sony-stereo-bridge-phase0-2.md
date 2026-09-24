# Session: Sony Stereo Bridge Phase 0-2

Date: 2026-09-24

## Request

Sony純正では異機種pairにできないSRS-HG1とSRS-HG10を、Mac側で独立L/R Rendererとして使えるか段階的に検証する。MyMusicへは統合しない。

## Investigation

実機2台をSSDPで検出し、Device Description、全SCPD、ConnectionManager `GetProtocolInfo`を取得した。両機は要求されたAVTransport action、Linear PCM、WAV、FLACを申告した。

## Changes

- 独立`sony-stereo-bridge` CLI target
- 読み取り専用`probe`
- 単体固定WAV用`play-one`
- 2台別固定WAV、左右delay、時刻・状態log用`play-pair`
- ffmpeg L/R分離script
- architecture、UPnP調査、Audio Hijack予定、同期、制約文書

## Validation

- `swift test`: XCTest 32件（性能1件skip）とSwift Testing 34件が失敗0
- HG1単体5秒PCM WAV: HEAD/HEAD/GET、SetURI/Play HTTP 200、0→5秒、STOPPED
- HG1 LEFT / HG10 RIGHTの別8秒PCM WAV: 両HTTP取得、両PLAYING、8秒で両STOPPED
- 同時Play送信logは同一ms、SOAP完了差26ms。ただし音響同期の根拠にはしない

## Result

Phase 0、単一機固定WAV、2台別固定WAVはプロトコル上成功した。

## Remaining Issues

実音のL/R、開始同期、1・3・5・10分driftは手動未評価。これが成功するまでAudio Hijack、BlackHole、ライブHTTP、Web UIへ進まない。
