# HomeStereo Analyzer

HomeStereoの未解析曲と音量未解析曲を解析する独立した個人利用向けworker。MyMusic Semantic v2の評価済みfrontend／mappingを参考にし、隣接repositoryを実行時に参照しない。

## 方式

- 音楽特徴: Discogs-EffNet ONNX embedding＋Jamendo top50／mood-theme＋voice-instrumental／aggressive／relaxed分類head。3×30秒、patch128／hop62、batch8、CPU thread1／同時曲、per-patch平均。前処理だけを解析用コピーのPCMへ行い、音源のrateやファイルを変更しない。
- 音量: FFmpeg loudnormのinput Integrated LUFS／True Peakを全曲から測定。null出力のみ。
- 補正: MyMusicの−14 LUFS基準、−17...−11の維持帯、±4 dB上限を継承。維持帯でもTrue Peak上限−1 dBTPを優先する。互換JSONの下限−4 dBでpeak安全を確保できない入力は保存せず失敗扱いとする。
- MAESTの新モデルを確認したが、既存feature headのembedding契約はEffNet固定であり、同じ版番号で置換しない。現行の全用途で最高精度を証明するものではない。一次資料: [Essentia Models](https://essentia.upf.edu/models.html)、[FFmpeg loudnorm](https://ffmpeg.org/ffmpeg-filters.html#loudnorm)。

## 導入

Apple Silicon、Homebrew Python 3.12、FFmpeg／ffprobeが必要。このMacはこれらが導入済み。

```sh
./scripts/install-analyzer.sh
```

Pythonの独立venv、checksum検証した公式モデル、code、SQLite cacheは`~/Library/Application Support/HomeStereoAnalyzer`へ配置する。`/Applications/HomeStereoAnalyzer.app`は同venvを使うLaunch Services補助アプリ。入口はSwift／AppKitのnative executableとし、JSON documentのopen eventを受け取ってPython子processの終了まで待機する。sandbox本体からcommand-line引数が届かないため、NSWorkspaceのURL openを使う。起動時stderrは専用Application Supportのlauncher-error.logに端末内だけで保持する。HomeStereo本体のsandbox entitlementを変更しない。MTGモデルはCC BY-NC-SA 4.0（非商用）。一般配布への同梱可否は別途確認が必要。

既存の公式modelをread-onlyコピーして初回downloadを省く場合だけ`--models-source /path/to/models`を指定できる。実行時はその元pathを参照しない。Python依存は`requirements-lock.txt`で固定し、全モデルのSHA-256は`models.json`を正とする。解析実行中はinstallerによる環境更新もlockで拒否する。

HomeStereoの専用deploy scriptはこのinstallerを先に実行する。MyMusicのvenv、解析cache、model、出力へ書き込まない。

## 実行と保存境界

SwiftUI → TrackFeatureStore → FeatureAnalysisPlanner → FeatureAnalysisService → NSWorkspace → HomeStereoAnalyzer → worker.py。HomeStereoのApplication Support配下`AnalysisRuns/<UUID>`にversion 1 JSON requestをatomic生成し、Launch ServicesのJSON document open eventとしてURLを渡す。shellへ音源pathを埋め込まない。helperはネットワークAPIを公開せず、生成されたrequestで指定された音源だけを読む。

requestの各taskはlocalTrackID、音源path、内部FeatureRecord、semantic／loudnessの実行指定を持つ。progressはstatus.json、完了／中断の成功結果はresults.json。曲ごとの成功結果はcompleted.jsonlへflush／fsyncし、本体起動時に検証してarchiveへmergeする。末尾の書きかけ行は除外し、復旧原本は保持する。成功結果を既存archiveへatomic mergeする。正常受信時はrun directoryを削除、異常終了時は診断／回復用に保持する。

SQLite cacheは曲ID＋絶対音源path＋size＋mtimeNS＋固定profileごとにsemanticとloudnessを独立checkpointする。音量失敗後もsemanticを再計算しない。解析日時をcacheにも保存し、再利用時に現在日時で捏造しない。音源が解析中に変わった場合はその段階をcommitしない。中断は新規曲の投入を止め、処理中の最大2〜3曲の終了後に行い、完了曲をJSONへまとめる。再開は同じ画面の実行ボタンを再度押す。Embeddingは永続保存せず、巨大な全曲NPZ cacheを増やさない。モデルhead変更時のEmbedding再利用には未対応。

音源pathは端末内のrequest/cacheだけに保持し、文書・診断には残さない。外部交換JSONには端末固有pathを出力しない。解析エラーは曲別件数と種類で報告し、Subprocess command／絶対音源pathをUIへ露出しない。

## 検証

```sh
python3 -m unittest discover -s analyzer/tests -v
HOMESTEREO_ANALYZER_SMOKE=/path/to/synthetic.wav swift test --filter FeatureAnalysis
```

Python testはcache、中断、片方の失敗、再利用時の解析日時、gain／peakを検証。合成5秒stereo音源でモデル9項目と音量3項目の実推論、Launch ServicesとNSWorkspaceの実起動を確認済み。2万実音源の長時間処理、実ライブラリ権限／iCloud未download音源、聴感比較は未確認。

## 同時解析数

画面の「同時解析数」で2曲／3曲／6曲を選ぶ（初期3曲、端末内保存）。3つの解析mode共通で、開始時の値を内部requestのconcurrencyへ渡し、実行中は変更不可。外部MyMusic JSONには含めない。旧内部requestの指定なしは1曲を維持する。

ThreadPoolExecutorの投入数を指定値に制限し、SQLiteはtask別connection、ONNX engineはthread別に保持する。進捗・結果・fsync journalは単一の集約側で書く。ONNX／BLAS／FFmpeg filter threadを各1に抑制し、同時曲数と内部threadの乗算を抑える。CPUコア数や実際の所要時間を保証する設定ではない。中断後は実行中の曲だけを終え、残りは次回に回す。

Python testsは2曲／3曲の実際の同時到達、上限、1曲の失敗、cache日時維持、待機曲を開始しない中断を検証する。合成音源3曲の実モデル／音量解析は両設定で成功。2万実音源の速度比較は未実施。
