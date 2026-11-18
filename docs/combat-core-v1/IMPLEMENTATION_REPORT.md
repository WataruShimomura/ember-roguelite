# Combat Core v1 — 実装と起動

試作のみ・未採用。実装は `combat_core_v1/` の独立シーン。基点 c21c5bc4d42ff83602d2f74bd4d5f18c1678eed5、更新指示 37ae0259ef66118069c2c2957db64af16b67838d。

- 3人、各6候補・持込4、通常攻撃は別枠。速度順の1手番1入力。盾兵、詠唱士、治癒兵、ボスの詠唱王。2〜3体編成と固定予告、戦術装備は各人2種類。
- TP18開始・上限30。敵ごとの75/50/25%の初到達ごとに生存味方全員+2。戦闘内供給なしを切替。応急・魔力転換は実回復、戦闘・戦間の通算で各戦1回。初期傷薬は1個。
- 通常→強敵→ボスの3戦。成長条件U0〜U3、2回の戦後成長、3ビルド、同じシードでの再戦。準備画面のF1〜F6で固定局面に入り、途中状態の保存・復元もできる（画面を閉じるまで）。
- データは [content.json](../../combat_core_v1/content.json)。[Battle](../../combat_core_v1/battle.gd) が順序・状態・予告を持ち、[Effects](../../combat_core_v1/effects.gd) が予測と本実行の共通計算を担当する。[Route](../../combat_core_v1/route.gd) が持越と成長、画面は入力と表示を担当する。Ver.0.3のコード・データ・シーンは差分外。

## 起動

PowerShellでプロジェクト直下から実行。既存ゲームは `Play.cmd`。

```powershell
$godot = ".\tools\Godot_v4.6-stable_win64_console.exe"
& $godot --path . res://combat_core_v1/main.tscn
```

出撃準備で成長条件・シード・閾値TPを選ぶ。3戦ルートは各人の持込を選び「戦闘 1 / 3 を開始」。戦闘では技→対象→予測→実行。勝利後には必要なら治療して、成長を選んで次戦へ。検証局面を選ぶとTP・ビルド・追加条件A/Bを切り替えられる。 [出撃準備](screenshots/preparation.png) · [敵予告と技の予測](screenshots/forecast.png)

## 再実行

```powershell
$godot = ".\tools\Godot_v4.6-stable_win64_console.exe"
powershell -ExecutionPolicy Bypass -File .\Test.ps1 -Render

New-Item -ItemType Directory -Force tests/artifacts | Out-Null
$log = Join-Path $PWD "tests/artifacts/combat_core_full.log"
& $godot --headless --path . --log-file $log --script combat_core_v1/evaluate.gd
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|FAIL:' -Quiet)) { throw "通常比較失敗" }
$log = Join-Path $PWD "tests/artifacts/combat_core_off.log"
& $godot --headless --path . --log-file $log --script combat_core_v1/evaluate.gd -- --off
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|FAIL:' -Quiet)) { throw "対照比較失敗" }
python combat_core_v1/summarize.py

& $godot --path . --script combat_core_v1/smoke_ui.gd
```

`--quick` はシード42〜44と速攻・状況判断・温存の校正用。全結果は [成長](PROGRESSION_REPORT.md) と [検証](TEST_REPORT.md)。手触りの判断は [未解決点と提案](ISSUES_AND_PROPOSALS.md)。
