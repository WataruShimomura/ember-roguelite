# 仕様の未指定事項と採用した判断

設計資料の範囲内で、小さく検証できるルールを採用しました。

| 判断 | 採用内容 | 後から変える場所 |
|---|---|---|
| 定義形式 | 手編集・差分比較しやすいJSON。共有定義を戦闘中に変更せず、状態へ深いコピーを作成 | `data/content.json`, `ContentCatalog`, `BattleState` |
| 能力と表示 | 能力はIDを保持。表示名・配色・素材は別JSON。追加した数値項目をループで表示 | `data/visuals.json`, 各ユニットの`stats` |
| 丸め | POWERの基礎値・装備・バフとスキル基礎値を加算 → 0以上 → 防御倍率を乗算 → 最後に1回floor → 現在HP/不足HPで上限適用 | `ActionCalculator.calculate` |
| 回復 | 生存者のみ、POWERとスキル基礎値の合計。HP上限で制限。蘇生なし | 同上 |
| 予告と実行 | ラウンド開始に行動・対象IDを固定。数値は現在の状態で再計算し即座に更新。死亡した対象へ付け替えない。全体攻撃は予告対象の生存者だけに解決 | `EnemyIntentPolicy`, `BattleEngine.intent_preview/advance` |
| 敵の通常対象 | 固定行動順で並ぶ生存味方から、ラウンド番号で循環。乱数を使わず再現可能 | `EnemyIntentPolicy.build` |
| 敵術士の周期 | R1通常、R2準備、R3大技。以後3ラウンド周期。大技の追加威力は12 | `policies.caster`, `skills.nova` |
| 敵盾兵 | 奇数ラウンドに通常、偶数に防御 | `policies.shield` |
| 防御 | 自身の次の手番に入る直前に解除。火傷には作用しない | `BattleEngine.advance`, `ActionCalculator.guard_info` |
| 激励・牽制 | 次の行動解決まで。防御・回復等も1行動として消費。自分に新たに付けた激励はその発動では消えない。同じスキル由来は再付与で更新、異なる発生源は加算 | `EffectResolver`, `BattleEngine.execute` |
| 火傷 | 成功時に残り2回へ更新。付与したラウンドの終了から毎回4ダメージ。防御無視。死亡対象には付与しない。付与者に与ダメージを帰属 | `statuses.burn`, `EffectResolver.round_end` |
| 火傷の抽選 | 有効な生存対象ごとに実行時だけ1回。プレビューは乱数に触らない | `EffectResolver.apply` |
| 装備重複 | 同じ装備を同キャラの2枠にも設定可能。能力・TP・火傷率は加算。火傷率は0〜100%。守護の石は倍率の最小値を採用し重複乗算しない | `ContentCatalog`, `ActionCalculator` |
| 効果順序 | TP消費 → 定義の対象順×効果配列順 → TP獲得 → 旧バフ期限 → 勝敗判定。各効果の発生源寄与は適用直前に記録 | `BattleEngine.execute`, `EffectResolver.apply` |
| 効果連鎖 | フラットな効果リストを1回処理。効果から新しい行動を再帰発行しない。1計算128効果を上限として検査 | `EffectResolver.MAX_EFFECTS` |
| 二重入力防止 | 手番・味方・所有スキル・対象・TP・フェーズに加え、UIが保持するrevisionを検査。古いボタンの再発火を拒否 | `BattleEngine.submit`, `BattleView.commit` |
| 集計 | 実HP変化を数え、オーバーキル・過剰回復は含めない。火傷を含む。装備発動数は初期能力適用と、行動計算・TP・防御に寄与した回数（対象ごと） | `ResultAggregator`, 装備イベント |
| リザルト | 最終ラウンド番号を「経過ラウンド」とする。履歴の内訳は実行当時の計算結果を保持 | `ResultAggregator`, `BattleState.record` |
| 再戦 | BattleStateと乱数生成器を新規生成。同じ装備とシードなら同じ入力列を再現。別シードは出撃準備で設定 | `BattleEngine.start` |
| 表示の分割 | 小規模なため3画面と内訳は1つのUIスクリプトにまとめる。戦闘ロジックと表示整形は独立 | `ui/main.gd`, `ui/visual_catalog.gd` |

物理/魔法攻撃力・防御力・命中・回避・会心などの追加能力は導入していません。
