# UI再生導線とNow Playing統合

- スピーカー未選択時の説明、選択後の「曲を選ぶ」導線、無効な再生操作の理由を追加した。
- Queue曲と直接選択ファイルを`NowPlayingPresentation`へ集約し、曲なし、読込中、停止中、再生中、一時停止、通信不明を区別した。
- 下部バー、小型プレイヤー、MenuBarExtra、macOS Now Playing／media keyが同じ表示modelと操作可否を参照するようにした。
- 直接ファイルの状態遷移、通信失敗、Renderer側の曲変更を自動testへ追加した。
- `./scripts/verify.sh`成功。別Bundleで初回導線、曲画面への遷移、下部バー、小型プレイヤーを目視確認した。
