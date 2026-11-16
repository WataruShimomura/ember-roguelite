# EMBER Ver.0.2 実装指示（履歴管理用）

このディレクトリは Ver.0.2 の**実装指示のスナップショット**です。ゲームコードではありません。
対象ベース: `main` のコミット `9e8461baf2a2b1ab35ada23dd896638941671d65`（2026-11-15 時点）。
指示ブランチ: `instructions/v0.2`。

## 読む順番
1. [CODEX_TASK.md](CODEX_TASK.md) 実装依頼・作業順序
2. [V02_GAME_SPEC.md](V02_GAME_SPEC.md) ゲーム仕様・検証対象
3. [ARCHITECTURE_AND_TESTS.md](ARCHITECTURE_AND_TESTS.md) 設計・検収・テスト

リポジトリルートの `AGENTS.md` と `BATTLE_PROTOTYPE_SPEC.md` も参照する。ただし Ver.0.2 で明示的に変更した内容（個別TP、共通防御廃止、冒険進行）は本ディレクトリが優先する。

## 推奨フロー
- 本指示ブランチは資料専用のまま残す。実装は `main` をベースに別ブランチ `feature/v0.2-roguelite-loop` を作り、指示書を `git show instructions/v0.2:instructions/v0.2/CODEX_TASK.md` などで参照する。
- Codexは**指示ブランチからゲームコードを実装しない**。機能ブランチでコード変更・テスト・報告書作成。
- 実装PRの説明に本ブランチと指示コミットSHAを記載し、どの指示を実装したか追跡可能にする。
- 実装後は `IMPLEMENTATION_REPORT.md` / `TEST_REPORT.md` / `DECISIONS.md` の更新または `docs/v0.2/` 下に同等の資料を残す。既存のVer.0.1報告を消さない。
- デザイン変更を議論したら指示は新コミットまたは別版（`instructions/v0.2.1` 等）に残す。後から書き換えて歴史を失わない。

## 出来上がったら確認したい問い
1. 1周するゲームの流れが理解でき、再挑戦したくなるか？
2. 個別TPを戦闘間で温存・消費する判断があるか？
3. 速攻・防御/反撃・吸収/継続戦闘で選ぶ行動が変わるか？
4. 敵を残した回復稼ぎが最適行動にならないか？
5. テンポと情報公開が保たれているか？
