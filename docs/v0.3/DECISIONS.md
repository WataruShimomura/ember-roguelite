# Ver.0.3 設計判断

指示: `33122df11cb0e04332968c47a8515cef415542c8`。Ver.0.2の判断記録は変更せず保持。

| 判断点 | 採用内容 | 変更箇所 |
|---|---|---|
| TP補充の境界 | RunManagerの一度だけの開始操作がsource配列を渡し、BattleState初期化直後に適用 | RunManager.start_battle / BattleEngine.start |
| C方式の仮値 | 開始2・プール4・速度1。OFFはenabled=false。各値は独立に調整可能 | rules.tp_recovery |
| 開始パッシブ | C機構が有効なときだけ開始量+1。OFF比較では開始パッシブも補充なし | RunManager.start_battle |
| KOとプール | KOも戦闘固有プールを持つが、KO中の補充/自然回復はなし。明示蘇生後、次Rから使用可能 | BattleEngine |
| 自然回復の再入防止 | round_startedで同じRのbegin_roundを二重に処理しない | BattleState / BattleEngine |
| 終了時プール | 生死を問わず残量を破棄し記録。次戦では再作成、RunStateへコピーしない | BattleEngine.check_winner |
| Lv増加と確定 | 通常報酬後にLvを更新し、成長画面を必須化。Lv3も確認ボタンで空枠を確定 | RunManager.choose_reward/choose_growth |
| 枠の所有 | 全員3枠目は空。元の所有数からのみ装着。装備や現在HP/TPを自動補充しない | RunState.equipment_slots / equip / CampView |
| 守護の牽制 | 指定味方の追加対象選択ではなく、自身の反撃+10へ代替。指示で認められた簡易案 | growth.options.riposte |
| 延焼 | 本体後の元対象が生存し、他の敵も生存する場合のみ1体。固定行動順で候補決定、別抽選60%、装備確率補正は追加分に乗せない | skill_growth / growth.options.spread |
| 爆ぜる残り火 | 行動前の火傷を先に消費して固定12の追加攻撃→通常火球→新しい火傷抽選。追加攻撃自体に反撃は発生しない | skill_growth / growth.options.detonate |
| 初回追撃 | 各人1戦1回。行動開始時に火傷していた敵への本体ダメージ+8。火傷消費と同時にも成立 | ActionCalculator.calculate |
| 初回反撃TP | 各人1戦1回、実被害を与えた反撃のみ。複数反撃が同時でも1回、満タンでも権利消費 | append_damage / growth.options.counter_order |
| 初回権利とKO | 攻撃後の反撃で死んでも消費済みを記録。蘇生して再取得しない | EffectResolver.growth_trigger |
| 有限効果の再初期化 | 成長IDはラン内永続、消費権利/構えは戦闘内。新戦は未消費、新ランは成長なし | BattleState / RunState |
| 発生源 | 成長はgrowth:ID、開始recovery:entry、自然recovery:round。確率抽選以外は予測と実行が同じリスト | Calculator / Resolver |
| 表示とテンポ | 静止した色/枠/変化ラベル。演出用awaitを戦闘操作へ入れない。強調OFF可 | BattleView / VisualCatalog |
| 比較入力 | 全条件共通の予測スコア。成長を必ず使わせるためのルート別特別操作はしない | tests/run_simulator.gd |
| 比較の分母 | 通常率はアイテムも含む全味方行動。技能数はアイテムを除く。開始TPは補充後、持越TPも元JSONに保持 | battle_stats |
| PRの差分 | Ver.0.2が別PRのため、v0.2機能ブランチをbaseにした積み重ねPR。mainへ直接変更しない | GitHub PR |

追加のXP、恒久育成、成長ツリー、報酬増殖、敵の一律ターン強化は導入していません。
