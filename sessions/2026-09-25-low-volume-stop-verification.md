# 2026-09-25 Low-volume / Stop Verification

## 実施内容

- Audio Hijack `Sony Stereo Bridge - BlackHole`をMusic→Channels（No Change）→BlackHole 2ch、Output 2%、Auto Run Off、Stoppedへ更新した。
- Bridge CLIへ`prepare-pair`、0〜10限定の`--test-volume`、左右の`STOPPED`を確認する`stop-pair`を追加した。
- Web UIの既定テスト音量を2/100にし、再生前の設定・読戻し確認と、process group終了後の左右UPnP Stopを追加した。
- HomeStereo本体のPause／Stopを、最大5回の状態確認と1回の再送を行う方式へ変更した。実機でPause非対応が判明したため、Pause不成立時は確認付きStopへfallbackするようにした。

## 検証結果

- Swift build成功。
- Pause／Stop再送、遷移待ち、未停止エラー、PauseからStopへのfallbackのfocused testが成功。
- `./scripts/verify.sh`成功。XCTest 32件（性能1件skip）、Swift Testing 47件、macOS Debug buildが成功した。
- localhost Web UIは内容表示、テスト音量2、Stopボタン、error overlayなし、console errorなしを確認した。
- Web Stopから実際の`stop-pair`経路を実行し、Renderer未検出エラーがUIへ返ることを確認した。
- Pause fallbackを含むRelease buildを`/Applications/HomeStereo.app`へ再配置し、署名を検証した。

## 実機結果

- 電源投入後のSSDP再検索でL soundbar（SRS-HG10）とR soundbar（SRS-HG1）の2台を検出した。固定IPには依存していない。
- `prepare-pair`で左右とも音量2/100の読戻し一致と停止状態を確認した。
- ピーク-50.5dBFSの極小クリックWAVを両方で再生し、HTTP GETと`PLAYING`を確認した。
- 30秒音源の途中で`stop-pair`を実行し、再生位置21／22秒で両方が`STOPPED`へ遷移した。これは自然終了前の実停止確認である。
- Pauseは両方ともHTTP 500／UPnP 701で拒否され、`PLAYING`を継続した。これが再生／一時停止ボタンで止まらない直接原因であり、HomeStereo側のStop fallbackを追加した。
- Pause fallbackを含むデプロイ版HomeStereoで、R soundbarと30秒の極小クリックWAVを選択した。画面から再生し、3秒後に一時停止を押した約15秒後、R／Lとも実機`STOPPED`、音量2/100を確認した。自然終了前のため、アプリ画面操作からのfallback成功と判定した。

## 残件

- Audio Hijack実音、LEFT ONLY／RIGHT ONLY、segment送信、音響同期、長時間driftは未実施。
