#!/bin/bash
# スクリプトの解析エラーだけを表示する
# Godot の実行ファイル（環境変数 GODOT で指定、無ければ PATH の godot）
GP="${GODOT:-godot}"
cd "$(dirname "$0")/.."
timeout 200 "$GP" --headless --path . --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|at: GDScript|ERROR" | grep -v "^$" | head -${1:-30}
