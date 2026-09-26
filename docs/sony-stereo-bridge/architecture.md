# Sony Stereo Bridge Architecture

Sony Stereo BridgeはMyMusicおよびHomeStereoのmacOS GUIから独立した段階的PoCである。固定ファイルのPhase 3に加え、Phase 4のBlackHole device probe、AUHAL PCM capture、固定長L/R WAV segment、検証済みcaptureの順次Sony送信まで実装した。ライブHTTP配信はまだ実装しない。操作用Web UIはloopback `127.0.0.1:9875`だけで提供する。

実装経緯、現在の成功／未検証matrix、優先課題は[`status-and-history.md`](status-and-history.md)を正本とする。

```text
stereo input
  -> fixed file: ffmpeg channel split
      -> left.wav  -> LAN-only HTTP server -> SRS-HG1  (LEFT)
      -> right.wav -> LAN-only HTTP server -> SRS-HG10 (RIGHT)
  -> realtime input: AUHAL single callback -> L/R mapping -> WAV segments
      -> validated capture report -> per-segment HTTP + SetURI/Play -> HG1/HG10
  -> two independent AVTransport controllers
```

機器はSSDPで探索し、IPではなくDevice Descriptionの`modelName`とUDNで識別する。Device Description、SCPD URL、control URLは機器の広告値を使い、pathやportを固定しない。HTTPはMacのRenderer到達用LAN IPv4だけへbindし、既定portは9876、2本目は次の空きportを使う。8080、localhost、外部公開、ルータ設定変更は使用しない。

## Phase gate

1. `probe`: SSDP、Device Description、SCPD、`GetProtocolInfo`
2. `play-one`: 1台へ固定PCM WAV
3. `play-pair`: 2台へ別々の固定PCM WAV
4. L/R分離ファイルと開始同期・長時間ドリフトの実測
5. BlackHole probe／無音PCM capture／segment生成
6. Audio HijackのLEFT ONLY／RIGHT ONLY実音入力
7. segmentのSony送信、長尺、chunked、リアルタイムPCMの順に検証

2026-09-25時点で1〜3はプロトコル上成功。4は10回のcommand timing取得まで完了したが、音響的な手動評価と10分driftが未完了。5は無音入力で成功した。6は未実施。7の送信経路は実装済みだが、安全条件により実音captureが合格するまで実行しない。

`play-capture`はcapture reportに列挙されたWAVだけを順番に配信する。無音、読み取れないWAV、既定で-6dBFSを超えるpeakを拒否し、`--confirm-routing`と`--confirm-low-volume`の両方を必須にする。各segmentでHTTP serverと`SetAVTransportURI`／`Play`を作り直すため、連続streamではなくgap測定用の段階である。
