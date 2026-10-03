# 共通データ交換・保全契約

- ユーザーの両repositoryへの文書化依頼により、rootとAGENTS／現在状態／architecture／交換コード・文書を確認した。
- MyMusicと同一本文・revision 1のdocs/data-interchange-contract.mdを追加し、AGENTSから参照した。
- 粒度とID、原本保持、未解決保留、競合、再送・受領確認、復元の要件を定義。現行dirty解除はExport成功であり受領保証ではないこと、playCount正本に関する既存文書矛盾を記録した。
- 実装は変更しない。耐久保留・受領確認・無欠落往復・障害復元は未検証。検証は契約本文一致とdiff空白確認のみ。文書変更のためbuild／testは実行していない。既存変更は保持。
