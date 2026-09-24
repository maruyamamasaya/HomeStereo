# Sony Stereo Bridge Architecture

Sony Stereo BridgeはMyMusicおよびHomeStereoのmacOS GUIから独立した段階的PoCである。現段階では固定ファイルによる実機検証だけを扱い、Audio Hijack、BlackHole、ライブHTTP配信、Web UIはまだ実装しない。

```text
stereo input
  -> ffmpeg channel split
      -> left.wav  -> LAN-only HTTP server -> SRS-HG1  (LEFT)
      -> right.wav -> LAN-only HTTP server -> SRS-HG10 (RIGHT)
  -> two independent AVTransport controllers
```

機器はSSDPで探索し、IPではなくDevice Descriptionの`modelName`とUDNで識別する。Device Description、SCPD URL、control URLは機器の広告値を使い、pathやportを固定しない。HTTPはMacのRenderer到達用LAN IPv4だけへbindし、既定portは9876、2本目は次の空きportを使う。8080、localhost、外部公開、ルータ設定変更は使用しない。

## Phase gate

1. `probe`: SSDP、Device Description、SCPD、`GetProtocolInfo`
2. `play-one`: 1台へ固定PCM WAV
3. `play-pair`: 2台へ別々の固定PCM WAV
4. L/R分離ファイルと開始同期・長時間ドリフトの実測
5. 4が実用レベルの場合だけAudio Hijack / BlackHole入力
6. 固定長segment、長尺、chunked、リアルタイムPCMの順に検証

2026-09-24時点で1〜3はプロトコル上成功。4は音響的な手動評価が未完了である。
