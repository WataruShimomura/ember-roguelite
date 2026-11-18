# EMBER Design Lab v3：要求駆動の戦闘デザイン審査

## 位置づけ
このフェーズは「戦闘コードを書く前の設計レビュー」。Codexは**既存実装を守る必要はない**が、今回は**既存ゲームコード・試作コードを変更しない**。Markdown資料・図・検証用表・必要なら計算用の独立スクリプトのみを作る。承認前にGodotの新たな戦闘実装を始めない。

基点: `design/design-lab-v2` / `abf4ac24afff8d62052fc88b4225dea722f754ef`（Ver.0.3やDesign Lab v2の報告と試作を参照可能）。主作業ブランチ `design/design-lab-v3` も同じ基点から作成済み。

## 最重要な考え
- **プレイヤーが何を考え、何を選び、選択によって何が変わるか**から逆算する。
- 「TP最大5→30」「スキル2→7」は解決の候補であり、最初から正解でも採用条件でもない。
- 目的が同じなら少ないルールを優先。複雑にしただけの案を不採用にする根拠も示す。
- 実装工数や既存コードとの互換性を、戦闘体験の質より優先させない。
- **各案が何を解決し、何を悪化させるかを明記**。最終採用はユーザーとアシスタントのレビューで判断。

## 必須参照
1. [DESIGN_CHALLENGES.md](DESIGN_CHALLENGES.md) 3つの検証課題
2. [SCENARIOS_AND_ACCEPTANCE.md](SCENARIOS_AND_ACCEPTANCE.md) 反証局面と具体的な合否
3. [CODEX_TASK.md](CODEX_TASK.md) 提出物・禁止事項・進め方
4. 既存 `docs/design-lab-v2/` と `docs/design-experiments/`、`AGENTS.md`

## 成果物
`docs/design-lab-v3/` 下に `EXPERIENCE_TARGET.md`, `ROOT_CAUSE.md`, `SYSTEM_PROPOSALS.md`, `SCENARIO_WALKTHROUGHS.md`, `ADVERSARIAL_REVIEW.md`, `DECISION_MATRIX.md`, `OPEN_QUESTIONS.md`, `NEXT_PROTOTYPE_SPEC.md`。**設計レビュー用**PRを `design/design-lab-v2` 向けに作成し、コードの本番採用は行わない。
