# Ver.0.2 作業計画と基準点

参照指示: `instructions/v0.2` / `c2921672a4679ecc9e5c9e439c98278b56960db8`。
ベース: `main` / `9e8461baf2a2b1ab35ada23dd896638941671d65`。
実装先: `feature/v0.2-roguelite-loop`。指示ブランチは変更しない。

変更前に `Test.ps1` を実行。Ver.0.1戦闘157検証、UI16検証、終了コード0。
既存はContentCatalog→BattleState/Calculator/Resolver/Policy→BattleEngineとResultAggregator、UIはmain.gdに集約されていた。

1. 個別TP・アイテム・low-water mark・吸収/反撃をデータと戦闘の各責務へ追加。入力revisionと予告固定を保持。
2. RunState/RunManagerで4戦・報酬・イベント・装備交換・資源引継ぎを管理。用途別シード、戦闘結果の一度だけの取込。
3. 画面ごとのViewと小さな共通UI部品へ分割。UIはスナップショットとコマンドのみ。
4. 変更ルールに合わせた回帰/悪用防止テスト、2ビルドの通しプレイ、描画スモーク。
5. 旧報告を保持しdocs/v0.2へ報告、参照SHA付きPRを作成。
