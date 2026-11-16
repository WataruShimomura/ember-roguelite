# 比較プレイ詳細（シード42）

生成元: `Test.ps1 -Render` / `tests/compare_growth.gd`。全8ランでクリア。
全条件でVer.0.3の成長と同じ入力方針を使用。旧Ver.0.2の測定とは入力方針が異なるため直接比較しない。
速攻: 捨身/集中プリセット＋爆ぜる残り火＋残火の追撃。継戦: 吸収/反撃プリセット＋守護の牽制＋迎撃の号令。
第1報酬は装備、以降は小休息。祭壇は回復。Lv3以降は所有装備があれば空の3枠目へ装備。

入力方針: HP30未満で治療薬、僧侶は不足HP24超で回復。それ以外は実予測のダメージ・火傷確率・牽制/反撃価値から固定スコアで選択。同点は固定順。最適プレイを表すものではない。

表のTP/HPの並びは剣士 / 魔術師 / 僧侶。開始TPは開始補充後、開始補充分は実増加の3人合計。自然/吸収/消費も実数量合計。
通常攻撃率は味方の全行動（アイテムを含む）に対する通常攻撃の割合。技能数はアイテムを除く。

## ボス戦まとめ

| ルート | TP方式 | R | 通常率 | 技能数 | 終了TP | 終了HP | アイテム消費 |
|---|---|---:|---:|---:|---|---|---:|
| burst | C | 4 | 18.2% | 9 | 4 / 5 / 5 | 44 / 42 / 55 | 0 |
| burst | entry_only | 4 | 18.2% | 9 | 0 / 0 / 4 | 44 / 42 / 55 | 0 |
| burst | pool_only | 4 | 20.0% | 8 | 2 / 2 / 5 | 63 / 42 / 52 | 0 |
| burst | off | 6 | 68.8% | 5 | 0 / 0 / 2 | 66 / 63 / 52 | 0 |
| sustain | C | 4 | 27.3% | 8 | 3 / 5 / 5 | 94 / 72 / 61 | 0 |
| sustain | entry_only | 4 | 27.3% | 8 | 0 / 1 / 4 | 94 / 72 / 61 | 0 |
| sustain | pool_only | 4 | 27.3% | 8 | 0 / 3 / 5 | 94 / 72 / 61 | 0 |
| sustain | off | 4 | 50.0% | 6 | 0 / 2 / 4 | 70 / 70 / 58 | 0 |

## 全戦闘の資源・行動

| ルート/方式 | 戦闘 | R | 開始TP | 開始補充 | 自然 | 吸収 | 成長TP | TP消費 | 終了TP | 終了HP | 通常率 | 技能数 | アイテム |
|---|---:|---:|---|---:|---:|---:|---:|---:|---|---|---:|---:|---:|
| burst/C | 1 | 2 | 5 / 5 / 5 | 6 | 2 | 0 | 0 | 6 | 4 / 2 / 5 | 82 / 72 / 82 | 20.0% | 4 | 0 |
| burst/C | 2 | 3 | 5 / 4 / 5 | 3 | 5 | 0 | 0 | 5 | 5 / 4 / 5 | 90 / 72 / 82 | 42.9% | 4 | 0 |
| burst/C | 3 | 4 | 5 / 5 / 5 | 0 | 7 | 0 | 0 | 10 | 4 / 3 / 5 | 53 / 66 / 46 | 27.3% | 8 | 0 |
| burst/C | 4 | 4 | 5 / 5 / 5 | 1 | 8 | 0 | 0 | 9 | 4 / 5 / 5 | 44 / 42 / 55 | 18.2% | 9 | 0 |
| burst/entry_only | 1 | 2 | 5 / 5 / 5 | 6 | 0 | 0 | 0 | 6 | 3 / 1 / 5 | 82 / 72 / 82 | 20.0% | 4 | 0 |
| burst/entry_only | 2 | 3 | 5 / 3 / 5 | 4 | 0 | 0 | 0 | 5 | 3 / 1 / 4 | 90 / 72 / 82 | 42.9% | 4 | 0 |
| burst/entry_only | 3 | 4 | 5 / 5 / 5 | 2 | 0 | 0 | 0 | 10 | 1 / 0 / 4 | 53 / 66 / 46 | 27.3% | 8 | 0 |
| burst/entry_only | 4 | 4 | 4 / 3 / 5 | 4 | 0 | 1 | 0 | 9 | 0 / 0 / 4 | 44 / 42 / 55 | 18.2% | 9 | 0 |
| burst/pool_only | 1 | 2 | 3 / 3 / 3 | 0 | 3 | 0 | 0 | 6 | 2 / 0 / 4 | 82 / 72 / 82 | 20.0% | 4 | 0 |
| burst/pool_only | 2 | 2 | 2 / 0 / 4 | 0 | 3 | 0 | 0 | 3 | 1 / 0 / 5 | 75 / 72 / 82 | 50.0% | 3 | 0 |
| burst/pool_only | 3 | 4 | 3 / 2 / 5 | 0 | 6 | 0 | 0 | 8 | 2 / 1 / 5 | 80 / 72 / 73 | 36.4% | 7 | 0 |
| burst/pool_only | 4 | 4 | 3 / 2 / 5 | 0 | 7 | 0 | 0 | 8 | 2 / 2 / 5 | 63 / 42 / 52 | 20.0% | 8 | 0 |
| burst/off | 1 | 2 | 3 / 3 / 3 | 0 | 0 | 0 | 0 | 4 | 1 / 1 / 3 | 82 / 72 / 82 | 50.0% | 3 | 0 |
| burst/off | 2 | 3 | 1 / 1 / 3 | 0 | 0 | 0 | 0 | 2 | 0 / 0 / 3 | 75 / 72 / 82 | 71.4% | 2 | 0 |
| burst/off | 3 | 5 | 2 / 2 / 5 | 0 | 0 | 0 | 0 | 4 | 0 / 0 / 5 | 80 / 72 / 73 | 76.9% | 3 | 0 |
| burst/off | 4 | 6 | 1 / 1 / 5 | 0 | 0 | 0 | 0 | 5 | 0 / 0 / 2 | 66 / 63 / 52 | 68.8% | 5 | 0 |
| sustain/C | 1 | 2 | 5 / 5 / 5 | 6 | 2 | 2 | 0 | 9 | 3 / 2 / 5 | 100 / 72 / 82 | 20.0% | 4 | 0 |
| sustain/C | 2 | 2 | 5 / 4 / 5 | 4 | 2 | 2 | 0 | 4 | 5 / 4 / 5 | 100 / 72 / 82 | 50.0% | 2 | 0 |
| sustain/C | 3 | 3 | 5 / 5 / 5 | 0 | 4 | 4 | 0 | 13 | 3 / 2 / 5 | 100 / 72 / 75 | 33.3% | 6 | 0 |
| sustain/C | 4 | 4 | 5 / 5 / 5 | 3 | 6 | 3 | 1 | 12 | 3 / 5 / 5 | 94 / 72 / 61 | 27.3% | 8 | 0 |
| sustain/entry_only | 1 | 2 | 5 / 5 / 5 | 6 | 0 | 2 | 0 | 9 | 2 / 1 / 5 | 100 / 72 / 82 | 20.0% | 4 | 0 |
| sustain/entry_only | 2 | 2 | 4 / 3 / 5 | 4 | 0 | 2 | 0 | 4 | 3 / 2 / 5 | 100 / 72 / 82 | 50.0% | 2 | 0 |
| sustain/entry_only | 3 | 3 | 5 / 5 / 5 | 1 | 0 | 4 | 0 | 13 | 1 / 0 / 5 | 100 / 72 / 75 | 33.3% | 6 | 0 |
| sustain/entry_only | 4 | 4 | 4 / 3 / 5 | 4 | 0 | 4 | 1 | 12 | 0 / 1 / 4 | 94 / 72 / 61 | 27.3% | 8 | 0 |
| sustain/pool_only | 1 | 2 | 3 / 3 / 3 | 0 | 3 | 2 | 0 | 9 | 1 / 0 / 4 | 100 / 72 / 82 | 20.0% | 4 | 0 |
| sustain/pool_only | 2 | 2 | 1 / 0 / 4 | 0 | 3 | 1 | 0 | 2 | 0 / 2 / 5 | 100 / 72 / 82 | 60.0% | 2 | 0 |
| sustain/pool_only | 3 | 3 | 2 / 4 / 5 | 0 | 4 | 4 | 0 | 13 | 0 / 1 / 5 | 100 / 72 / 75 | 33.3% | 6 | 0 |
| sustain/pool_only | 4 | 4 | 1 / 2 / 5 | 0 | 7 | 4 | 1 | 12 | 0 / 3 / 5 | 94 / 72 / 61 | 27.3% | 8 | 0 |
| sustain/off | 1 | 2 | 3 / 3 / 3 | 0 | 0 | 2 | 0 | 6 | 0 / 2 / 3 | 100 / 72 / 82 | 50.0% | 3 | 0 |
| sustain/off | 2 | 2 | 0 / 2 / 3 | 0 | 0 | 2 | 0 | 2 | 0 / 2 / 3 | 94 / 72 / 82 | 83.3% | 1 | 0 |
| sustain/off | 3 | 4 | 2 / 4 / 5 | 0 | 0 | 5 | 0 | 9 | 0 / 3 / 4 | 100 / 72 / 75 | 50.0% | 5 | 0 |
| sustain/off | 4 | 4 | 1 / 4 / 5 | 0 | 0 | 4 | 1 | 9 | 0 / 2 / 4 | 70 / 70 / 58 | 50.0% | 6 | 0 |

## コマンドと成長の発動

| ルート/方式 | 戦闘 | コマンド使用回数 | 成長の発動回数 |
|---|---:|---|---|
| burst/C | 1 | attack:1, pressure:1, strike:1, wave:2 | なし |
| burst/C | 2 | attack:3, heal:1, pressure:1, strike:1, wave:1 | なし |
| burst/C | 3 | attack:3, fireball:1, heal:1, pressure:2, strike:2, wave:2 | なし |
| burst/C | 4 | attack:2, fireball:3, heal:2, pressure:1, strike:3 | growth:detonate:1, growth:ember_hunt:3 |
| burst/entry_only | 1 | attack:1, pressure:1, strike:1, wave:2 | なし |
| burst/entry_only | 2 | attack:3, heal:1, pressure:1, strike:1, wave:1 | なし |
| burst/entry_only | 3 | attack:3, fireball:1, heal:1, pressure:2, strike:2, wave:2 | なし |
| burst/entry_only | 4 | attack:2, fireball:3, heal:2, pressure:1, strike:3 | growth:detonate:1, growth:ember_hunt:3 |
| burst/pool_only | 1 | attack:1, pressure:1, strike:1, wave:2 | なし |
| burst/pool_only | 2 | attack:3, fireball:1, pressure:1, strike:1 | なし |
| burst/pool_only | 3 | attack:4, fireball:2, pressure:1, strike:3, wave:1 | なし |
| burst/pool_only | 4 | attack:2, fireball:3, heal:1, pressure:1, strike:3 | growth:detonate:1, growth:ember_hunt:3 |
| burst/off | 1 | attack:3, pressure:1, strike:1, wave:1 | なし |
| burst/off | 2 | attack:5, fireball:1, pressure:1 | なし |
| burst/off | 3 | attack:10, pressure:1, strike:1, wave:1 | なし |
| burst/off | 4 | attack:11, fireball:1, heal:3, strike:1 | なし |
| sustain/C | 1 | attack:1, pressure:1, strike:1, wave:2 | なし |
| sustain/C | 2 | attack:2, pressure:1, wave:1 | growth:riposte:1 |
| sustain/C | 3 | attack:3, pressure:2, strike:1, wave:3 | growth:riposte:2 |
| sustain/C | 4 | attack:3, fireball:3, heal:1, pressure:3, strike:1 | growth:counter_order:2, growth:riposte:3 |
| sustain/entry_only | 1 | attack:1, pressure:1, strike:1, wave:2 | なし |
| sustain/entry_only | 2 | attack:2, pressure:1, wave:1 | growth:riposte:1 |
| sustain/entry_only | 3 | attack:3, pressure:2, strike:1, wave:3 | growth:riposte:2 |
| sustain/entry_only | 4 | attack:3, fireball:3, heal:1, pressure:3, strike:1 | growth:counter_order:2, growth:riposte:3 |
| sustain/pool_only | 1 | attack:1, pressure:1, strike:1, wave:2 | なし |
| sustain/pool_only | 2 | attack:3, pressure:2 | growth:riposte:2 |
| sustain/pool_only | 3 | attack:3, pressure:2, strike:1, wave:3 | growth:riposte:2 |
| sustain/pool_only | 4 | attack:3, fireball:3, heal:1, pressure:3, strike:1 | growth:counter_order:2, growth:riposte:3 |
| sustain/off | 1 | attack:3, pressure:1, strike:1, wave:1 | なし |
| sustain/off | 2 | attack:5, fireball:1 | なし |
| sustain/off | 3 | attack:5, heal:1, pressure:2, wave:2 | growth:riposte:2 |
| sustain/off | 4 | attack:6, fireball:3, heal:1, pressure:2 | growth:counter_order:2, growth:riposte:2 |

## ボスTP推移

行動内訳を含む全TPイベントは [comparisons.json](comparisons.json) の `tp_timeline`。以下は各ラウンド終了時点のTPで、R1には開始補充を含む。戦闘終了に達したラウンドも記録する。

| ルート/方式 | ラウンドごとの終了TP 剣/魔/僧 |
|---|---|
| burst/C | R1: 4 / 4 / 4 → R2: 4 / 4 / 5 → R3: 4 / 4 / 4 → R4: 4 / 5 / 5 |
| burst/entry_only | R1: 3 / 2 / 4 → R2: 2 / 1 / 5 → R3: 1 / 0 / 4 → R4: 0 / 0 / 4 |
| burst/pool_only | R1: 2 / 1 / 5 → R2: 2 / 1 / 5 → R3: 2 / 1 / 4 → R4: 2 / 2 / 5 |
| burst/off | R1: 0 / 0 / 5 → R2: 0 / 0 / 5 → R3: 0 / 0 / 4 → R4: 0 / 0 / 3 → R5: 0 / 0 / 2 → R6: 0 / 0 / 2 |
| sustain/C | R1: 5 / 4 / 5 → R2: 3 / 4 / 5 → R3: 3 / 4 / 4 → R4: 3 / 5 / 5 |
| sustain/entry_only | R1: 4 / 2 / 5 → R2: 2 / 1 / 5 → R3: 1 / 2 / 4 → R4: 0 / 1 / 4 |
| sustain/pool_only | R1: 1 / 1 / 5 → R2: 0 / 1 / 5 → R3: 0 / 1 / 4 → R4: 0 / 3 / 5 |
| sustain/off | R1: 1 / 3 / 5 → R2: 0 / 2 / 5 → R3: 0 / 1 / 4 → R4: 0 / 2 / 4 |

## 読み取りと限界

C方式では両ルートともボス4R、通常攻撃率18.2%/27.3%。OFFよりスキル使用機会が多かった。開始補充のみでも同じRで倒せたが、最終TPには差があった。
これは単一シード・固定ヒューリスティックの観測であり、楽しさ・最適戦術・全シードでの優越を証明しない。C方式の回復量が多すぎないか、手動プレイで温存判断が残るかを次に検証する。
プールもアイテムも吸収原資も尽きた場合、通常攻撃しか使えなくなる状況は残る。完全排除とは扱わない。
