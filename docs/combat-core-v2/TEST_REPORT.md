# Godot検証と再現方法

Godot 4.6.stable.official.89cea1439 / Windows。利用可能なツールにGodot MCPが見つからなかったため、描画付きGodotスクリプトで操作を再現した。人間による理解度や手触りは未評価。

## 起動

PowerShellでプロジェクト直下から実行。

~~~powershell
$godot = ".\tools\Godot_v4.6-stable_win64_console.exe"
New-Item -ItemType Directory -Force tests/artifacts | Out-Null
& $godot --path . --log-file (Join-Path $PWD "tests/artifacts/v2_play.log") res://combat_core_v2/main.tscn
~~~

準備画面の「3戦ルート」は成長付き連戦。F1〜F6を選ぶと固定局面を復元でき、条件と開始TPを変更できる。v1は res://combat_core_v1/main.tscn。

## 再実行

上の準備後に実行。ログ中の SCRIPT ERROR・FAIL も確認する。

~~~powershell
& $godot --headless --path . --log-file (Join-Path $PWD "tests/artifacts/v2_rules.log") --script combat_core_v2/check_rules.gd
& $godot --headless --path . --log-file (Join-Path $PWD "tests/artifacts/v2_threshold.log") --script combat_core_v2/evaluate.gd
& $godot --headless --path . --log-file (Join-Path $PWD "tests/artifacts/v2_none.log") --script combat_core_v2/evaluate.gd -- --off
foreach ($size in '1280x720','1600x900') {
    & $godot --path . --resolution $size --log-file (Join-Path $PWD "tests/artifacts/v2_ui_$size.log") --script combat_core_v2/smoke_ui.gd
}
& $godot --headless --path . --log-file (Join-Path $PWD "tests/artifacts/v2_v1_quick.log") --script combat_core_v1/evaluate.gd -- --quick
& $godot --path . --log-file (Join-Path $PWD "tests/artifacts/v2_v1_ui.log") --script combat_core_v1/smoke_ui.gd
powershell -ExecutionPolicy Bypass -File .\Test.ps1 -Render
~~~

比較JSONの再生成には、上の最終版ログに加えて、初回コミット 971e32a、1回目調整後 f6a00a7 のそれぞれの独立作業ツリーで、同じ Godot 実行ファイルを絶対パスで指定し evaluate.gd を閾値ありで実行する。両ツリーの tests/artifacts/v2_threshold.json を現在の tests/artifacts/v2_stage2_before.json と tests/artifacts/v2_stage2_mid.json にコピーし、python combat_core_v2/summarize.py を実行。集計は同版内の敵・シードと資源引継ぎ、レベル・所持の独立性も照合する。

初回の旧v1実行ではサンドボックスから既定ユーザーログに書けず、Godotが停止した。以後はプロジェクト内の絶対ログパスで再実行。GPUシェーダー初期化の警告が初回の描画、OS証明書ストアの読取警告がサンドボックス実行に出たが、再実行のキャプチャ・検証は完了した。旧Ver.0.3の冒険ログ保存を含む検証はユーザーデータ領域へ書ける実行で確認した。 [旧v1の比較画面](screenshots/v1-boss.png)

## 合否

最終版では固定局面158検査、描画1280×720・1600×900各43検査、閾値あり960連戦の13,746検査と閾値なし960連戦の13,513検査が失敗0。回帰確認はv1の72連戦・976検査と描画20検査、旧Ver.0.3の727検査が失敗0。連戦での敗北は難度の観測として集計した。

| ケース | 判定 | 根拠 |
|---|---|---|
| T1 共通構え | PASS | 盾と将に同じ破甲。非構えで通常攻撃の方が高打点。 |
| T2 キャラ横断 | PASS | 術師→剣士、衛士→術師の別経路で火傷の付与者と計算が一致。 |
| T3 維持と消費 | PASS | TPを温存するHP83と、攻撃を止めるHP19で選択が異なる。 |
| T4 有限回復 | PASS | HP5で即撃破と3周期遅延は術師HP64・在庫0で一致。遅延側のTPは減少。 |
| T5 個別報酬 | PASS | 物品・学習・回復と出撃準備を分離。2回目で既存の組合せは維持。 |
| T6 非専用鍵 | PASS | 火傷不使用のボス戦を別に実行し、勝利を確認。 |
| T7 UI | PASS（スクリプト検査） | 2解像度でTab・Enter・マウスと結果→2回の成長→ボス結果。初見の理解は未確認。 |
| T8 成長 | PASS | 同じ敵・シードと共通攻略方針でU0とU3の差。3種以上の経路でコマンド・残余資源が異なる。 |
| T9 TP偏り | RISK | 0TPでも減衰・分散が残る。全連戦で閾値供給を切ると通常攻撃寄り。長い固定局面も要確認。 |
| T10 説明 | PASS（スクリプト検査） | 不発条件、火傷2→0、TP/HP差、レベル前後と次段階を表示。初見プレイヤーの理解は未確認。 |

固定ケースは [戦闘検証](COMBAT_REPORT.md)。定量結果と残った反例は [成長](PROGRESSION_REPORT.md) と [未解決点](OPEN_ISSUES.md)。実測値は [JSON](metrics.json)。
