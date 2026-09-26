# Sample-rate family delay

- Sonyステレオの基準遅延を44.1kHz系と48kHz系で個別に設定できるようにした。
- 88.2／176.4kHzは44.1kHz基準、96／192kHzは48kHz基準へ倍レート加算を適用する。
- 安定優先48kHz出力は音源のsample rateにかかわらず48kHz基準を使う。
- 自動testで両系列の基準値と倍レート加算を確認する。
