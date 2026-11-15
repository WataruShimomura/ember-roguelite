# ローカル実行用のGodot

Godot本体はサイズの大きい外部ツールなのでGit管理から除外しています。開発フォルダーに配置済みのバイナリもpushされません。

1. [Godot 4.6の公式ダウンロード](https://godotengine.org/download/archive/4.6-stable/) からWindows通常版（.NET不要）のZIPを取得します。
2. 次の2ファイルをこのフォルダーへ展開します。

```text
tools/
  Godot_v4.6-stable_win64.exe
  Godot_v4.6-stable_win64_console.exe
```

プロジェクト直下の `Play.cmd` でゲーム、`Test.ps1` で自動テストを実行できます。別の場所にGodotを配置した場合は、Godotから `project.godot` を開くか、`Test.ps1 -Godot 'C:\path\godot_console.exe'` を使用します。

このフォルダーの `.gdignore` はGodotのリソーススキャンから実行ツールを除外するためのものです。Gitの除外はルートの `.gitignore` が担当します。
