# Sony UPnP Research

## 2026-09-24実機probe

同一LAN上でSRS-HG1とSRS-HG10を別々の`MediaRenderer:1`としてSSDP検出した。IPとUDNは診断JSONには出力するが、DHCP変更と個人ネットワーク情報の固定化を避けるため、この文書には保存しない。

両機とも次を広告した。

- `RenderingControl:1`
- `ConnectionManager:1`
- `AVTransport:1`
- Sony `Group:1`、`MultiChannel:1`、`ScalarWebAPI:1`
- Tencent `QPlay:2`

AVTransport SCPDは両機で同じactionを公開した。要求対象の`SetAVTransportURI`、`Play`、`Pause`、`Stop`、`Seek`、`GetPositionInfo`、`GetTransportInfo`はすべて含まれる。ほかに`SetNextAVTransportURI`、`GetMediaInfo`、`GetDeviceCapabilities`、`GetTransportSettings`、`Next`、`Previous`、`SetPlayMode`、`GetCurrentTransportActions`がある。

RenderingControlは`GetVolume`、`SetVolume`、`GetMute`、`SetMute`、`ListPresets`、`SelectPreset`を公開した。

`ConnectionManager.GetProtocolInfo`は両機でHTTP 200となり、Sinkに少なくとも次を申告した。

- Linear PCM: `audio/L16`
- WAV: `audio/wav`、`audio/x-wav`
- FLAC: `audio/flac`、`audio/x-flac`
- MP3、WMA、AAC、ALAC、AIFF、DSD

Sony公式Help Guideも両機についてMP3、Linear PCM、WMA、AAC、WAV、FLAC、ALAC、AIFFのDLNA再生対応を記載している。ただし全ファイルの再生保証ではない。

PoCの第一形式は44.1kHz / 16-bit PCM WAVとする。理由は、両機が明示的にSink申告し、無音追加やサンプル単位の遅延生成が容易で、圧縮デコード時間の差を避けやすいためである。FLACは帯域削減候補だが、まず安定性を優先する。

## 固定WAVの結果

- SRS-HG1単体: `HEAD`、`HEAD`、`GET`を受信し、5秒のPCM WAVが0秒から5秒まで進行後`STOPPED`。
- 2台同時: 各機が別URLを取得し、8秒の別PCM WAVが両方で`PLAYING`から`STOPPED`へ遷移。
- friendly nameは`R soundbar`がSRS-HG1、`L soundbar`がSRS-HG10だった。PoCのLEFT/RIGHT割当はfriendly nameではなく要求どおりmodelNameで行う。

## 再現

```sh
swift run sony-stereo-bridge probe --timeout 8 --output /tmp/sony-stereo-bridge-probe.json

swift run sony-stereo-bridge play-one \
  --renderer SRS-HG1 \
  --file /absolute/path/to/test.wav \
  --timeout 8 --http-port 9876 --hold 10
```

probeは読み取り専用であり、再生や音量変更を行わない。
