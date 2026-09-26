# 2026-09-26 Sonyステレオ同期チェック

## 変更

- Sonyステレオの出力品質初期値を「安定優先 48kHz」（16-bit PCM）へ変更した。
- Sonyステレオ選択中だけ、下部Now Playingバーへ「遅延チェック」ボタンを表示する。
- 48kHz、16秒、ピーク約-18dBFSの同一broadband tickを3回ずつ8群、アプリ内で生成する。現在の遅延方向・遅延値・出力品質を通常曲と同じ分離処理へ通し、2台のRendererへ送る。
- 揃っていれば中央で締まった1音、ずれていれば二重打ちまたは左右への広がりとして聞き分ける。これは聴感チェックであり、自動計測ではない。
- チェック中はNow Playingを「同期チェック音」と表示し、ライブラリ曲・お気に入り・再生履歴・Queue完走処理へ混入させない。

## 自動検証

- 既定品質が48kHzであることをmodel／storeの両方で確認。
- 生成ファイルが48kHz、左右同一長で、指定した25msが1,200 frameの差として適用されることを確認。
- チェック再生が左右へSetURI／Playし、終了しても通常曲の完走callbackを呼ばないことを確認。

## 完了確認

- `./scripts/verify.sh fast`と`./scripts/verify.sh`が成功。XCTest 60件中59件成功、明示実行の性能test 1件skip、Swift Testing 64件成功、macOS Debug build成功。
- `./scripts/deploy-macos.sh`でRelease版を`/Applications/HomeStereo.app`へ配置。bundle versionは`20260926204129`、実行ファイルSHA-256は`63507667a43d20f22809ff14712ff970e89557f5c760310548c67adba9a46dbf`。
- Launch Services検索結果と実行中processはいずれも`/Applications/HomeStereo.app`の1件だけ。検証・deploy用DerivedDataとstage directoryは削除済み。
- 実スピーカーでの音出しは予期しない再生を避けるため未実施。最終的な物理同期は低音量から手動確認する。

## 追加調整

- 聴き比べ時間を確保するため8秒から16秒へ延長し、クリックを4群から8群へ増やした。
- 聞き取りやすさを上げるためピークを約-24dBFSから約-18dBFSへ6dB上げた。
- 全検証を再実行し、Release版`20260926215729`を`/Applications/HomeStereo.app`へ再配置した。実行ファイルSHA-256は`f13934eab2c9efedecd23d510b20adbe1908138af2fd3d38682d266e61c6658a`。
