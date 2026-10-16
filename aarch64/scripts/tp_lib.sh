#!/bin/bash
# ============================================================================
#  tp_lib.sh —— 第三方插件清单的公共函数
#  被 clone_thirdparty.sh 和 2512diy-part2.sh 共同 source
# ============================================================================

# 清单文件位置（可用环境变量 TP_CFG 覆盖）
TP_CFG="${TP_CFG:-${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/aarch64/Lede2512/thirdparty.cfg}"

# tp_block_state <名字>   → 输出 on / off（未在清单中出现的默认 on）
tp_block_state() {
    local name="$1" st=""
    if [ -f "$TP_CFG" ]; then
        st=$(awk -v n="$name" '
            /^[[:space:]]*#/ { next }
            $2 == "block" && $3 == n { r = $1 }
            END { print r }
        ' "$TP_CFG" 2>/dev/null)
    fi
    [ -z "$st" ] && st="on"
    printf '%s' "$st"
}

# tp_block <名字>   → 返回 0 表示启用（on），1 表示关闭（off）
tp_block() {
    [ "$(tp_block_state "$1")" != "off" ]
}
