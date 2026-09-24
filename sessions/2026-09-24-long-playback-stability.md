# Long Playback Stability

再生session generation、await後の古いpolling破棄、終端位置とURIを含む完走判定、重複防止、command直列化を追加した。Renderer側の別URI、timeout／切断ではQueueを進めず、表示を安全側へ同期する。read-only SOAPだけtimeout時に1回再試行し、SetURI／Playは再送しない。旧HTTP serverは30秒保持し、再生中だけidle sleepを抑止する。匿名化した診断JSON Exportも追加した。

fakeで途中STOPPED、重複終了、遅延した旧generation、外部曲変更、timeout、操作競合、診断logのpath／IP／token非包含を確認した。macOS Debug buildと全testを実行する。SRS-HG1での50曲以上、各format、遅延・電源OFF・Wi-Fi復帰は未実施。
