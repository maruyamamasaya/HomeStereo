# Practical Audit Session

- コード、test、Documentationを13監査項目へ対応付け、結果を`docs/practical-audit-2026-09-24.md`へ記録した。
- Renderer選択中の常時状態同期、同一generation内の古いrefresh破棄、Renderer消失時のunknown同期を最小修正した。
- 埋め込みArtworkを常にdownsample／cache経路へ通し、32 MiBのsource上限を追加した。
- Queueの位置変更から曲開始までを単一遷移として保護し、競合する前／次／再生要求による位置ずれを防止した。
- 外部操作、遅延応答、Renderer消失、UDN再接続、SOAP timeout、mutating SOAP非retry、巨大Artworkのfake testを追加した。
- JSON schema、SQLite schema、音源、Playlist、Favorite、履歴、Queue形式は変更していない。
- SRS-HG1 Wireless Stereo、VPN／複数interface、Firewall、format別再生は実機未確認として残した。
- 通常test 63件、20,000曲性能test、macOS Debug build、ad-hoc署名がすべて成功した。性能再確認値は初回0.562s、差分なし0.099s、load 0.242s、検索0.590s、DB 11,325,440 bytes。
