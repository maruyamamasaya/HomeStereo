# Sony Stereo Bridge Status and History

この文書は、Sony純正Wireless Stereoでは組み合わせられないSRS-HG1とSRS-HG10を、Mac側から独立したLEFT／RIGHT Rendererとして扱うPoCの実装経緯、現在地、未解決課題の正本である。MyMusicへは統合せず、`sony-stereo-bridge`として分離を維持する。

## 現在地

2026-09-25時点で、固定ファイル再生、BlackHoleからの固定長PCM segment生成、capture reportを検証してsegmentをSonyへ順次送る経路まで実装済み。Music→Audio Hijack→BlackHoleのL/R分離と、検証済み各1秒segmentのHG1／HG10実機送信まで確認した。連続stream、物理的な左右定位、音響同期、長時間driftは未検証である。

```text
固定L/R WAV -> HTTP -> HG1/HG10       : 成功
10回のPlay command同時送信             : 成功
BlackHole device probe                 : 成功
BlackHole -> AUHAL -> L/R WAV segment  : 成功
Audio Hijack -> BlackHole test signal   : 成功（L/R分離確認）
segment -> HG1/HG10                    : 1秒×2で実機成功
chunked / live PCM                     : 未実装
音響同期 / 10分以上のdrift             : 未測定
```

## 実装経緯

### Phase 0: 独立PoC化

- HomeStereo macOS GUIおよびMyMusicから分離したCLIとして開始した。
- HG1とHG10をSony Wireless Stereo pairとしてではなく、独立した2つのDLNA Rendererとして扱う方針にした。
- deviceの固定IPではなく、SSDP、Device Description、`modelName`、UDNを識別の正本にした。

### Phase 1: 能力調査

- SSDP discovery、Device Description、SCPD action、ConnectionManager `GetProtocolInfo`を収集する`probe`を実装した。
- HG1／HG10のAVTransportとPCM WAV受信能力を実機で確認した。
- advertised URLとcontrol URLを使用し、Sony固有の固定pathやportを前提にしない設計にした。

### Phase 2: 固定L/Rファイル

- `play-one`で単体再生、`play-pair`でHG1=LEFT／HG10=RIGHTの別ファイル再生を実装した。
- RendererごとにLAN到達用HTTP serverとAVTransport controllerを分離した。
- 左右PCM WAVのHTTP GET、SOAP 200、Transport進行、完走を確認した。

### Phase 3: 同時開始とDelay

- 左右の`SetAVTransportURI`と`Play`を並列送信し、1ms単位の相対Delayを追加した。
- ピーク-50.5dBFSの極小clickを生成し、10回の再生でPlay送信差0msを確認した。
- SOAP完了差にはばらつきがあったため、command timingを音響同期とは扱わないことにした。
- loopback Web UIへDelay preset、反復、測定値記録、同期評価を追加した。
- 外部マイク測定ができず、実音offsetと10分driftは未評価のまま残した。

### Phase 4: リアルタイム入力の入口

- BlackHole 2ch v0.6.1を検出し、96kHz、2ch、512-frame bufferを確認した。
- AVAudioEngineでは任意device選択後も既定マイクのformatが残ったため、AUHALへ変更した。
- AUHALでOS既定入力を変えずにBlackHoleのdevice IDを直接選択した。
- 1つのcallbackと共通frame timelineからL/Rを抽出し、1／2／5秒のmono PCM WAV segmentを生成する`SonyStereoBridgeAudio` targetを追加した。
- CLI 2秒、Web UI 5秒のcaptureに成功し、WAVをPCM 16-bit、96kHz、monoとして確認した。
- capture時は無音だったため、左右分離やAudio Hijack実音経路の成功とは扱っていない。

### Phase 5: 検証済みsegmentの安全な送信

- capture reportからsegment順、左右WAV、frame数、peakを検証する`CapturePlaybackPlan`を追加した。
- 無音、WAV欠落、重複segment、既定で-6dBFSを超える入力をspeaker送信前に拒否する。
- `play-capture`は左右routing確認と本体低音量確認の明示flagを必須にし、`--test-volume`指定時は0〜10の範囲だけを左右へ設定して読戻し確認する。
- Web UIへrenderer指定、確認checkbox、`Play Captured Segments`、Stop、既定2/100のテスト音量を追加した。
- Stopはローカルprocess groupだけでなく左右へUPnP Stopを並行送信し、最大5回の状態確認で両方が`STOPPED`になったことを確認する。
- 各segmentは既存の固定WAV HTTP＋AVTransport経路で順次再生する。連続streamではなく、境界gapと同期を測るための実装である。
- Audio HijackのApplication／Channels／Output Device blockをすべて有効化し、Musicのtest signalをBlackHoleへ入力した。
- Output 2%でLEFT ONLYは左−54.0dBFS／右−160dBFS、RIGHT ONLYは左−160dBFS／右−54.0dBFSとなり、反転・漏れ・clippingなしを確認した。
- 各1秒の検証済みsegmentを本体音量5/100でHG1=LEFT／HG10=RIGHTへ送信し、両方のHTTP GET、Play、位置1.000秒、`STOPPED`を2segmentで確認した。

### 2026-09-25 安全な開始直前状態と停止補強

- Audio HijackをMusic→Channels（No Change）→BlackHole 2ch、Output 2%、Auto Run Off、Stoppedへ更新した。
- HomeStereo本体もPause／Stop成功を即時表示せず、Rendererの`PAUSED_PLAYBACK`／`STOPPED`を確認する。未反映なら指示を1回再送し、確認失敗時は元の表示を維持してエラーを示す。
- localhost UIの表示、テスト音量2、Stopボタン、console errorなしをブラウザ確認した。
- スピーカー電源投入後、HG1／HG10を再検出した。左右を2/100へ設定して読戻し一致を確認し、ピーク-50.5dBFSの固定WAVを両方で再生した。
- 30秒音源の途中で`stop-pair`を実行し、再生位置21／22秒で両方が`STOPPED`へ遷移することを確認した。
- Pauseは両方ともHTTP 500／UPnP 701で拒否され、`PLAYING`のままだった。この実機仕様に合わせ、HomeStereoはPause不成立時に確認付きStopへfallbackする。
- デプロイ版HomeStereoでR soundbarと30秒の極小クリックWAVを選択し、再生3秒後に画面の一時停止操作を実施した。約15秒後の実機読取りでR／Lとも`STOPPED`、音量2/100を確認した。自然終了前のため、HomeStereoのPause→Stop fallbackが実機で成立した。

## Audio Hijack準備状態

新規session `Sony Stereo Bridge - BlackHole`を次の停止状態で作成した。

```text
Application: Music
  -> Channels: No Change
  -> Output Device: BlackHole 2ch
     Output Volume: 2%

Auto Run: Off
Status  : Stopped
```

test signalでRunとL/R captureを実施済み。終了後はStoppedへ戻した。既存の`Untitled Session`は逆向きかつ160% gainだったため変更していない。

## 未解決課題

### P0: 次の実機ゲート

1. 物理的な左右定位を聴感または外部マイクで確認する。
2. Phase 3の実音offsetと開始時・1・3・5・10分のdriftを測る。

### P1: Segment配信

1. 各segment境界のgap、click、AVTransport再設定時間、実音同期を記録する。
2. 1秒、2秒、5秒を比較し、latencyと途切れの妥協点を決める。
3. speaker本体音量は最小付近にし、実行ごとに`--test-volume`で明示・読戻し確認する。

### P1: Rendererのstream対応調査

固定WAV、短時間WAV、長尺WAV、chunked HTTP、Content-Length不明、終端なしPCMの順に進める。前段が失敗した場合、後段を成功扱いにしない。各段階でHTTP request、Sony response、UPnP state、再生位置を残す。

### P1: Latencyと同期

- capture buffer、segment待ち、HTTP開始、Renderer buffer、DAC開始を分けて測る。
- Phase 3の固定Delayがsegment方式でも再現するか確認する。
- command時刻ではなく、可能なら外部マイクまたはloopback収録した実音を評価対象にする。

### P2: Drift補正

driftが安定して観測された場合だけ、sample追加／削除、微小resampling、定期再同期の順で比較する。補正前の測定値を保存し、補正によるclick、pitch変化、音切れも記録する。

### P2: 運用性

- source application切替、Start／Stop、異常終了、sleep／wakeを確認する。
- BlackHole消失、sample rate変更、buffer size変更を検知し、無音のまま成功表示しない。
- Web UIのlevel、latency、sync offset、driftを実測値へ接続する。現在のlatencyとdrift表示には未測定項目がある。

## 安全条件

- 新規Audio Hijack sessionはAuto Run Off、Output 2%、停止状態を維持する。
- テスト開始時はBridgeがSony左右を明示値2/100へ設定し、読戻し一致を確認する。
- Bridgeは`--test-volume`指定時だけ0〜10の範囲でspeaker volumeを変更する。macOS既定入出力とAudio MIDI設定は変更しない。
- BlackHole capture確認前にSony送信を開始しない。
- 無音、HTTP取得、command timingだけで音響同期成功と判定しない。

## 再開地点

次回は1秒segmentの物理的な左右定位と境界gap／clickを記録する。その後2秒、5秒segmentを比較し、外部マイクまたはloopback収録で開始offsetと10分driftを測定する。
