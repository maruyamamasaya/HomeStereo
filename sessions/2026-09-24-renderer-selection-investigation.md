# Renderer選択表示の調査

- 現行実装と同じ`SSDPDiscovery.discover(timeout:)`でLANを確認し、25応答中SRS-HG1 2台（192.168.0.54、192.168.0.105）を検出した。
- 現行sourceから署名付きDebug Appをbuildして起動し、`R soundbar`と`L soundbar`が一覧表示され、行選択後にDevice Descriptionが表示されることを確認した。
- unit／fake testは通常32件＋Swift Testing 32件が成功（20,000曲性能test 1件は明示指定なしのためskip）。
- 現行コードでは探索結果0件を正常な空配列として扱い、空状態の説明や診断を表示しない。このため権限、別build、探索タイミングなどで0件になると「Rendererを選択」だけが残り、原因をUIから判別できない。
- 修正は行っていない。
