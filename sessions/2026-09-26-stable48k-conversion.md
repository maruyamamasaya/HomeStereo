# Stable 48kHz Conversion Fix

- 実測値LEFT 48kHz=105ms、96kHz=210msを受け、既定をLEFT／48kHz基準105ms／倍レート追加105msへ更新した。
- 安定優先48kHzで48kHz以外の音源が再生できない問題を再現した。AVAudioConverterへの入力供給と終端drainを修正した。
- 44.1／48／88.2／96／192kHzの短いステレオWAVを48kHzへ変換し、sample rateと長さを確認する自動テストを追加した。
- `./scripts/verify.sh fast`は性能テスト1件skipを除き全件成功。Release buildと署名検証後、`/Applications/HomeStereo.app`を更新した。
- 再起動後はスピーカーが未検出で`No route to host`だったため、実機再生確認は未実施。
- 片側だけ遅れて鳴り始める実機報告を受け、Play前の準備確認をURI一致だけから「URI一致＋停止系transport stateが3回連続」へ強化した。Play後は左右のHTTP GETを共有ゲートで待ち合わせてresponse bodyを同時解放する。片側未到達時は2秒でfallbackする。
- 接続後に一時エラーと開始ラグが出る報告を受け、local address解決を最大4回、読取SOAPの一時的network errorを最大3回確認するようにした。HTTP server準備はbackgroundへ移し、UIのmain actorを待たせない。
- 接続済みなのにアラート／未接続になる制御を監査し、SSDP 3回連続miss、Transport 2回連続失敗を切断判定の閾値にした。Volume単独失敗は診断記録だけに留め、Description取得失敗時のIDをUSNのUDN部分へ統一した。
- 更新版起動直後にもSSDPが`No route to host`で失敗することを画面確認したため、検索エラーを400ms間隔で最大3回自動再試行してからアラートへ昇格するようにした。
- 実機で左右とも`PLAYING`なのに準備未完了となる報告を受け、SetURI後に新URIが一致している場合は`PLAYING`も準備完了として扱うよう修正した。旧URIの`PLAYING`は引き続き拒否する。
- 全検証（XCTest 32件、Swift Testing 56件、性能test 1件skip）とRelease build、署名検証に成功し、`/Applications/HomeStereo.app`を更新した。起動後はSonyステレオ選択を復元し、起動直後の接続アラートがないことを確認した。実音を伴う再試行は未実施。
- 追加実測に基づき、標準遅延を44.1kHz系=99ms、48kHz系=108ms、倍レートごとの追加=108msへ更新した。
- 新しい標準値の系列（44.1/48/88.2/96/176.4/192kHz）を自動テストし、全検証（XCTest 32件、Swift Testing 57件、性能test 1件skip）、Release build、署名検証後に`/Applications/HomeStereo.app`を更新した。
- 調整パラメータを1つへ集約した。48kHz系基準を利用者が設定し、44.1kHz系は基準×11/12、倍レートごとの追加は基準値として自動計算する。
- 利用者が設定する基準値は従来どおり1ms単位とし、44.1kHz系の自動計算値と実適用値の表示は0.1ms単位へ統一した。PCM生成時はsample rateに応じた最寄りsample frameへ丸める。
- 1パラメータ・0.1ms自動計算版を全検証（XCTest 32件、Swift Testing 57件、性能test 1件skip）し、Release buildと署名検証後に`/Applications/HomeStereo.app`へ配置・起動した。
