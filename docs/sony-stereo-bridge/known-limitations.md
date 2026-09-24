# Known Limitations

- 実音の左右分離と定位は人間または外部マイクで未確認。現在の成功判定はHTTP取得とUPnP状態に限る。
- 10分のクロックドリフト、開始ごとのばらつき、Wi-Fi混雑時の音切れは未測定。
- `GetPositionInfo`は実機上で整数秒粒度のため、ms単位同期の観測には使えない。
- `Play` SOAPの送信・完了時刻は、スピーカーDACの音響開始時刻ではない。
- Delayは現在`Play`送信時刻だけをずらす。音源への無音追加は未実装。
- Pause、resume、Stop、SeekはSCPD公開を確認したが、この2台同時PoCでは未検証。
- ライブHTTP PCM、chunked transfer、終端のないstreamは未検証。対応を仮定しない。
- Audio Hijack、BlackHole、Core Audio入力、Web UIはPhase gate待ちで未実装。
- 自動探索はmulticast、同一LAN、AP isolation、VPN、macOS firewallの影響を受ける。IP固定は前提にしない。
- 2台のfriendly nameはモデルの意図したL/Rと逆に見える。割当はmodelNameで行うが、実際の設置位置は利用者が確認する必要がある。
