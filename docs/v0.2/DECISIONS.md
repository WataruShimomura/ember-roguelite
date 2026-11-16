# Ver.0.2 設計判断

参照: `c2921672a4679ecc9e5c9e439c98278b56960db8`。Ver.0.1の `DECISIONS.md` は変更せず保持しています。

| 未指定事項 | 採用した判断・理由 | 変更箇所 |
|---|---|---|
| 出撃時装備 | 全定義から2枠を選べる検証用準備。開始後は所有装備のみ交換 | PreparationView / RunManager |
| 初期装備の所有 | 装備中の個数を所有とし、外すと予備へ戻る。報酬1回で1個増加。複数キャラで同じ定義を所有できる | RunManager.equip |
| 最大値変化 | 出撃初期化時だけ初期資源設定。以後増加時は補充なし、減少時だけclamp。HP0を維持 | RunManager.new_run/equip、BattleState |
| 個別コスト | 支払本人のみ。軽減は加算、元が有料なら最低1、元が0なら0 | ActionCalculator.cost |
| 防御の代替 | 剣士の牽制へ自身の軽減を付ける。全員共通の防御は廃止。敵盾兵の防御は残す | skills.pressure/guard |
| アイテム | 種類ごと1枠、3枠。治療/TPは3個、蘇生は2個まで。満杯の報酬は選択不可、必ず別カテゴリを選べる | items / rules / RunManager.can_add_item |
| アイテム対象 | HP/TP回復は生存者のみ、蘇生薬は戦闘不能者のみ。使用者の1手番を消費。戦間の即時使用は実装しない | BattleEngine.submit、ActionCalculator.targets |
| 報酬3択 | 装備・有限アイテム・小休息の3カテゴリから各1候補。多様な資源を必ず比較可能にする | reward_groups、RunManager |
| 有限イベント | 2戦目報酬後に1回だけ。回復と、HPを払う装備獲得の選択 | event、RunManager.choose_event |
| 乱数 | ルート・報酬は異なるsalt、各戦はランシードと戦番号から派生。予測でいずれも消費しない | RunManager.new_run/start_battle |
| 計算と実行 | 状態の深いコピー上で、対象順/効果定義順にダメージ・反撃・吸収まで予測し、同一リストを適用。火傷抽選だけ実行時 | ActionCalculator / EffectResolver |
| ダメージ丸め | 基礎POWER・スキル・装備・バフの加算を0以上→軽減乗算→最後にfloor→現在HPまで | append_damage |
| 新規削減HP | damage_beforeの実HPと過去最低HPから差分を1回計算。敵ごとの最低値は単調減少。回復・同一IDの復活で戻さない | BattleState.low_water、append_damage |
| 複数吸収 | 1ダメージのクレジットを全装備が参照。効果ごとにfloor(credit×率)、不足量でclamp。小数繰越なし | append_damage/append_recovery |
| 吸収順 | 攻撃→HP吸収→TP吸収→反撃。本人のコスト支払い後のTP空きを予測に使用 | ActionCalculator、BattleEngine.execute |
| 継続ダメージ | 火傷も同じ敵クレジットを消費。付与者へ帰属、生存している付与者のみ吸収。反撃は発生しない | EffectResolver.round_end |
| 反撃 | 実被害>0、双方生存時のみ。固定値を軽減込みで計算し、反撃への反撃は禁止。吸収は反撃でも有限クレジットから発生 | append_damage |
| 効果連鎖 | 反撃の深さは1。平坦な計算リストは最大128効果をassert。召喚等の未対応種は定義検証で拒否 | ActionCalculator、EffectResolver、ContentCatalog |
| 全滅 | 全員HP0なら敗北。敵味方同時全滅でもプレイヤー敗北を優先 | BattleEngine.check_winner |
| 死亡後の予告 | 無予告の付け替えはしない。全体予告は当初の対象の生存者だけ、全滅なら中止 | BattleEngine.intent_preview/advance |
| 戦闘取込 | RunManagerのbattle→battle_resultで一度だけ。資源/装備/アイテムをコピーして戦闘側と共有しない | RunManager.collect_battle |
| ログ | バトルの実HP/TP変化・クレジット・発生源、ランの報酬/装備交換/イベント/戦前後を保存。途中再開はしない | BattleState、RunState、RunManager.result |
| 画面分割 | Viewごとに分割し、外見部品だけ基底Viewへ。ゲームルールをUIに置かない | ui/*_view.gd |

敵編成の各候補に同じ敵IDを複数同時配置することは検証で拒否します。新たな同型敵個体・召喚システムが必要になった場合は、テンプレートIDと個体IDを分離し、同一個体のlow-water markを維持する設計へ拡張します。
