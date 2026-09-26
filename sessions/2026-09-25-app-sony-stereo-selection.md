# App Sony Stereo Selection

- HomeStereoのスピーカー画面へ「Sonyステレオ」を追加した。
- L soundbar（SRS-HG10）をLEFT、R soundbar（SRS-HG1）をRIGHTとして画面に明示する。
- 選択曲をAVFoundationで左右の16-bit PCM WAVへ分離し、2台へ独立配信する。
- Play／Stop／Seek／Volumeを2台へ並行送信し、ステレオ時のPauseは確認付きStopとする。
- `swift build`とRelease Xcode buildは成功し、`/Applications/HomeStereo.app`へ配置、署名検証済み。
- 音を出さないprobeでR soundbar（SRS-HG1）とL soundbar（SRS-HG10）、両方のAVTransportを確認した。
- UI自動操作経路が切れたため、画面上の最終クリックと実曲の左右聴感確認は未実施。
- L/R音源チャンネルの交換と、LEFTまたはRIGHTへ1ms刻みで無音を挿入するタイミング補正を追加した。
- 両Rendererの通信ウォームアップ、SetURI読戻し、準備完了後の並行Playを追加した。
- 出力品質をハイレゾ維持（元sample rate／24-bit PCM）と安定優先（48kHz／16-bit PCM）から選択可能にした。
- Sony MultiChannelは両機ともSTEREO対応だがPairIDが異なり、HG10をmasterとする`X_Start(STEREO)`はUPnP 816で拒否された。両機が`IDLE / NONE`のまま変更されていないことを確認した。
- 48kHz基準値にsample rate段数×追加遅延を加える自動補正を追加した。既定は1段180msで、前回適用したsample rateと総遅延を画面表示する。
- 下部再生バーの旧単体RendererメニューをSonyステレオ対応へ更新し、現在の出力先表示、単体切替、左右共通音量スライダーを追加した。
- 実測したLEFT 48kHz=105ms／96kHz=210msを既定値へ反映した。安定優先48kHzで異なるsample rateの変換が失敗する問題を修正し、44.1／48／88.2／96／192kHzの変換テストを追加した。
