# Audio Hijack / BlackHole Setup

2026-09-25にAudio HijackとBlackHole 2ch v0.6.1の存在を確認し、BridgeがBlackHoleをOS既定入力へ切り替えずに直接選択できるようにした。実機の現在値は96,000 Hz、2ch、32-bit float入力、512 frames、HAL報告入力latency 0 framesである。

## 現在の推奨構成: BlackHole 2ch

2ch deviceはL/Rが同じdevice clockとcallbackに載るため、このMacではまず次を使う。

```text
Application / System Audio
        │
     Channels（通常はL/Rをそのまま）
        │
 Output Device: BlackHole 2ch
        │
 Sony Stereo Bridge: ch 1 = LEFT / ch 2 = RIGHT
```

Audio HijackでBlank Sessionを作成し、次の順でblockを配置する。

1. `Application` blockで対象アプリを1つ選ぶ。全Mac音声を試す場合だけ`System Audio`を使う。
2. `Channels` blockを置き、通常テストではL→L、R→Rの標準stereo mappingにする。
3. L/R検査では、最初にRIGHTをmuteしてLEFT ONLY、次にLEFTをmuteしてRIGHT ONLYにする。
4. `Output Device` blockで`BlackHole 2ch`を選ぶ。Macの既定出力やAudio MIDI設定は変更しない。
5. Audio Hijack sessionを開始し、Web UIの`Capture PCM Only (5 s)`でlevelとsegmentを確認する。
6. LEFT ONLY／RIGHT ONLYが合格し、Sony本体音量を最小付近にした後だけ、確認checkboxを入れて`Play Captured Segments`を実行する。

準備済みsessionは`Sony Stereo Bridge - BlackHole`。MusicをApplicationとして設定し、Application／Channels／Output Deviceの全ブロックを有効、`Channels: No Change`、`Output Device: BlackHole 2ch`、Output Volume 2%、Auto Run Off、Stoppedで保存している。ブロックがOffだとSessionがRunningでもcaptureは完全無音になるため、各blockの`Enable block: On`を開始前に確認する。

BlackHoleは仮想deviceなので、この段階では物理speakerから音を出さない。Sonyへ送る後続試験では、Bridgeの`--test-volume 2`で左右を2/100へ設定・読戻し確認してから行う。0〜10以外の値は拒否する。

## 16chへ変更する場合

2chでclockやrouting上の問題が出た場合だけBlackHole 16chを比較する。

```text
LEFT  -> BlackHole ch 1-2
RIGHT -> BlackHole ch 3-4
```

Bridgeでは16ch時に`--left-channel 1 --right-channel 3`を指定する。左右は1つのAUHAL callbackから同じframe countで取り出すため、別々のcapture clockは持たない。

## Bridge操作

```sh
swift run sony-stereo-bridge audio-probe --output /tmp/sony-stereo-bridge-audio-probe.json

swift run sony-stereo-bridge capture-segments \
  --device BlackHole \
  --output-dir /tmp/sony-stereo-bridge-realtime \
  --duration 5 \
  --segment-seconds 1 \
  --left-channel 1 \
  --right-channel 2 \
  --buffer-frames 1024 \
  --output /tmp/sony-stereo-bridge-capture-report.json

swift run sony-stereo-bridge play-capture \
  --capture-report /tmp/sony-stereo-bridge-capture-report.json \
  --left SRS-HG1 --right SRS-HG10 \
  --confirm-routing --confirm-low-volume \
  --test-volume 2 \
  --safety-ceiling-dbfs -6 \
  --segment-tail 0.25 \
  --output /tmp/sony-stereo-bridge-captured-playback-report.json
```

出力は`segment-left-0001.wav`と`segment-right-0001.wav`のような16-bit mono PCM WAVになる。`buffer-frames`はcapture用memory上限であり、deviceのbuffer sizeを変更しない。実bufferはreportの`actualBufferFrames`を正本とする。

## 現在の判定

```text
BlackHole device probe : 成功
PCM capture             : 成功（無音入力で5秒）
固定1秒L/R WAV生成      : 成功
LEFT ONLY / RIGHT ONLY  : 成功（反対側−160dBFS）
Audio Hijack実音入力    : test signalで成功
短時間WAVのSony送信     : 1秒×2 segmentで実機成功
chunked HTTP            : 未実装
live PCM                : 未実装
```

Musicからのtest signalをOutput 2%で流し、LEFT ONLYは左−54.0dBFS／右−160dBFS、RIGHT ONLYは左−160dBFS／右−54.0dBFSを確認した。反転、反対channelへの漏れ、clippingは観測されなかった。

`play-capture`は連続再生ではない。各segmentごとにSetURI／Playするため、境界gap、click、音響同期は実機で測定する。実装経緯と課題一覧は[`status-and-history.md`](status-and-history.md)を正本とする。
