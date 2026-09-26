# Known Limitations

- Audio Hijack→BlackHoleのWAV上の左右分離は確認済みだが、スピーカー実音の物理的な左右定位は人間または外部マイクで未確認。
- sandbox内のAVFoundation列挙は0件だったが、権限付きAUHALではBlackHoleを含む入力を列挙できた。実音開始差の自動収録は未実装。
- 10分のクロックドリフト、開始ごとのばらつき、Wi-Fi混雑時の音切れは未測定。
- `GetPositionInfo`は実機上で整数秒粒度のため、ms単位同期の観測には使えない。
- `Play` SOAPの送信・完了時刻は、スピーカーDACの音響開始時刻ではない。
- Delayは現在`Play`送信時刻だけをずらす。音源への無音追加は未実装。
- HG1／HG10はStopを受理して再生途中でも`STOPPED`へ遷移する。一方、Pauseは両方ともHTTP 500／UPnP 701で拒否して再生を継続した。HomeStereoは確認付きStopへfallbackするため、一時停止位置からのresumeはできない。Seekは未検証。
- ライブHTTP PCM、chunked transfer、終端のないstreamは未検証。対応を仮定しない。
- BlackHole 2chのAUHAL入力、LEFT ONLY／RIGHT ONLY、固定長WAV segment、検証済みsegmentのSony実機送信は確認済み。chunked／continuous HTTPは未検証。
- segment送信は各WAVごとにHTTP serverとSetURI／Playを作り直すため連続再生ではなく、境界gapとclickが予想される。実測前に音楽用途で使用可能とは扱わない。
- 2026-09-25の5秒captureは入力が無音で、levelは左右とも-160dBFS。PCM経路の成立だけを示し、channel分離成功は示さない。
- 自動探索はmulticast、同一LAN、AP isolation、VPN、macOS firewallの影響を受ける。IP固定は前提にしない。
- 2台のfriendly nameはモデルの意図したL/Rと逆に見える。割当はmodelNameで行うが、実際の設置位置は利用者が確認する必要がある。
