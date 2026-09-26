# 0002 App-managed Sony stereo output

## Decision

HomeStereoのmacOS GUIに、L soundbar（SRS-HG10）をLEFT、R soundbar（SRS-HG1）をRIGHTとする明示的なSonyステレオ出力を持たせる。

選択曲はAVFoundationで左右の16-bit PCM WAVへ分離し、Rendererごとに独立したHTTP serverとUPnP controllerを使う。Play、Stop、Seek、Volumeは2台へ並行送信する。Pauseを拒否する実機仕様に合わせ、ステレオ時のPauseは両方への確認付きStopとして扱う。

## Rationale

標準UPnP情報からSony Wireless Stereoの左右構成は取得できず、今回の実機はHG1とHG10が別Rendererとして広告される。左右の役割を画面へ明示し、アプリがチャンネル分離と2台の操作を所有することで、利用者が1つの出力先として選べる。

## Consequences

- 最初の再生前に曲全体の分離時間と一時ディスク容量が必要になる。
- UPnP commandの同時送信は音響同期を保証しない。開始差とdriftは別途実機測定する。
- HG1／HG10以外の任意ペア選択はこの初期実装の対象外とする。
- 片側のタイミング補正は利用者が1ms刻みで指定し、音源sample rateに応じた整数sampleへ丸めて無音を挿入する。
- 同期改善と音質を分離し、通信ウォームアップと両側のSetURI確認は常時実行する。出力品質は元sample rate／24-bit PCMのハイレゾ維持、または48kHz／16-bit PCMの安定優先から選ぶ。
- Sony MultiChannelのPairIDはHG10=`BarLow1`、HG1=`PasLow1`で、`X_Start(STEREO)`は実機でUPnP 816となった。異機種間のSonyネイティブグループは構成せず、PairID偽装もしない。
- 形式依存の遅延は48kHzを基準とし、元sample rateが48kHzを超えるたびに設定値を階段加算する。既定の段差は180ms。手動値は48kHz基準として加算し、実際のsample rateと総遅延をUIへ返す。
