#!/usr/bin/env bash
# ==============================================================================
#  重建插件清单（Linux / macOS / Git Bash 版）
#  等价于双击 Windows 版：aarch64/scripts/一键重建插件清单.bat
#
#  用法： bash aarch64/scripts/rebuild_plugins.sh
# ==============================================================================
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

echo "============================================================"
echo "  重建 plugins.cfg   工作目录: $ROOT"
echo "============================================================"

PY=""
for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
    echo "!! 没有找到 python3。可以直接用 GitHub Actions 的「重建插件清单」工作流，无需本地环境。"
    exit 1
fi
echo "使用解释器: $PY"
echo

"$PY" aarch64/scripts/build_plugins_cfg.py "$@"
echo
echo "[完成] aarch64/Lede2512/plugins.cfg 已更新"
