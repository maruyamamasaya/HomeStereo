# Synchronization

## 2026-09-24開始試験

SRS-HG1をLEFT、SRS-HG10をRIGHTとして、別々の8秒PCM WAVを配信した。2本の`SetAVTransportURI`と`Play`はそれぞれ並列に送った。

- LEFT / RIGHT `Play sent`: 同一ミリ秒のアプリログ
- `Play` SOAP完了: RIGHTが先、LEFTとの差は26ms
- 両機とも1秒後から`PLAYING`
- 両機とも8秒位置で`STOPPED`
- `GetPositionInfo`は整数秒粒度で、途中の1サンプルだけLEFT 6秒 / RIGHT 7秒を返した

この結果は「ほぼ同時に制御できる」ことを示すが、実際の音の立ち上がり差や1秒未満のズレを証明しない。SOAP完了時刻も音響開始時刻ではない。

## Delay semantics

`play-pair`は左右それぞれ`-5000...5000ms`を受け付ける。小さい値を基準0msに正規化し、大きい側の`Play`送信を差分だけ遅らせる。

```sh
swift run sony-stereo-bridge play-pair \
  --left SRS-HG1 --left-file /absolute/path/to/left.wav \
  --right SRS-HG10 --right-file /absolute/path/to/right.wav \
  --left-delay 0 --right-delay 80 \
  --timeout 8 --http-port 9876 --hold 600
```

## 次の実測

同じclick trackを左右へ送り、中央定位または二重clickを耳または外部マイクで、開始、1分、3分、5分、10分に記録する。評価表には推定差ms、途切れ、状態、ネットワークイベントを残す。`GetPositionInfo`は1秒粒度なのでms同期の測定器として使わない。

初期ズレが一定ならDelayで補正する。試行ごとに変動する場合、`Play`送信delayでは解決しないため、WAV先頭へのサンプル精度の無音追加を次に試す。時間とともにズレる場合は独立クロック由来であり、固定delayでは補正不能。ライブ化へ進まず、実用不可または周期的な再同期／resamplingが必要と判定する。
