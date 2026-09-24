# Audio Hijack / BlackHole Setup

このPhaseは未実施である。固定L/Rファイルの長時間同期が実用レベルと確認できるまで、既存Audio Device設定は変更しない。

進行条件を満たした場合は、複数の2ch仮想deviceより構成が一箇所にまとまるBlackHole 16chを第一候補にする。ただし実機での安定性は未確認である。

想定するAudio Hijack sessionは次の通り。

```text
Application または System Audio
  -> Channels（LEFTだけをch 1/2へ複製） -> BlackHole 16ch ch 1-2
  -> Channels（RIGHTだけをch 3/4へ複製） -> BlackHole 16ch ch 3-4
```

Audio HijackではSourceブロックの後を2系統へ分岐し、それぞれChannelsブロックで片チャンネルを左右へ複製してOutput Deviceへ送る。Output Deviceは同じBlackHole 16chを選び、上流のchannel mappingをch 1-2とch 3-4へ分ける。Macの既定出力、既存Aggregate Device、Audio MIDI設定はPoCが自動変更しない。

Bridge側のCore Audio入力、device UID選択、channel mapping、入力断検知はPhase 4で実装する。現時点でAudio Hijackとの相性や安定性を成功扱いにしない。
