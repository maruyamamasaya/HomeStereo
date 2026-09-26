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

## 2026-09-25 10回反復

同一サンプルの4秒クリックWAVを左右へ送り、各回で`SetAVTransportURI`からやり直した。音源ピークは-50.5dBFS、平均は-74.4dBであり、スピーカー本体の保存音量は変更していない。

| Test | Play送信差 RIGHT-LEFT | SOAP完了差 RIGHT-LEFT |
| ---: | ---: | ---: |
| 01 | 0ms | -11ms |
| 02 | 0ms | +21ms |
| 03 | 0ms | +43ms |
| 04 | 0ms | +30ms |
| 05 | 0ms | +6ms |
| 06 | 0ms | +11ms |
| 07 | 0ms | +59ms |
| 08 | 0ms | +18ms |
| 09 | 0ms | 0ms |
| 10 | 0ms | +6ms |

Play送信差は10回すべて0ms。SOAP完了差は最小-11ms、最大+59ms、平均+18.3ms、標準偏差19.9msだった。これはnetwork/control timingであり音響開始時刻ではないため、Excellent等の音響評価には使用しない。全10回で左右とも4秒位置の`STOPPED`を確認した。

この実行環境ではAVFoundation録音入力が列挙されず、内蔵マイクによる自動音響測定は実施できなかった。実音offsetはWeb UIから入力し、中央値からの最大変動でExcellent（5ms以下）、Good（20ms以下）、Usable（40ms以下）、Poor（40ms超）を記録する。

## Phase 3 Web UI

```sh
./scripts/sony-stereo-bridge-web.py
```

`http://127.0.0.1:9875`でLEFT/RIGHT Delayを1ms直接入力でき、-100、-50、-20、-10、-5、-1、0、+1、+5、+10、+20、+50、+100msのpresetを持つ。極小クリック生成、1〜20回の反復、実音offset記録に対応する。正の観測値はRIGHTが遅い、負はLEFTが遅い意味とする。

10分音源は同UIから生成できるが、音響観測者または録音入力なしで再生してもdrift値を得られないため、自動実行していない。
