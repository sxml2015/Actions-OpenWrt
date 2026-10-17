#!/bin/bash
# ============================================================================
#  clone_thirdparty.sh —— 按 thirdparty.cfg 克隆「新增的第三方插件源」
#
#  用法：
#     cd openwrt
#     bash <仓库根>/aarch64/scripts/clone_thirdparty.sh
#
#  环境变量：
#     GITHUB_WORKSPACE  仓库根目录（默认由脚本位置推断）
#     OPENWRT_DIR       源码目录（默认当前目录）
#     TP_CFG            清单文件（默认 aarch64/Lede2512/thirdparty.cfg）
#
#  说明：
#     本脚本只处理 thirdparty.cfg 里的 "repo" 行；
#     2512diy-part2.sh 里已有的那些「内置克隆块」由 tp_block 开关控制。
# ============================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/tp_lib.sh"

WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$HERE/../.." && pwd)}"
OPENWRT_DIR="${OPENWRT_DIR:-$PWD}"
CFG="$TP_CFG"

echo "=============================================================="
echo " 克隆第三方插件源"
echo "  清单     : $CFG"
echo "  源码目录 : $OPENWRT_DIR"
echo "=============================================================="

if [ ! -f "$CFG" ]; then
    echo "[第三方] 找不到清单文件，跳过。"
    exit 0
fi

cd "$OPENWRT_DIR" || { echo "[第三方] 无法进入 $OPENWRT_DIR"; exit 1; }

count=0
skip=0
while IFS= read -r raw || [ -n "$raw" ]; do
    # 去掉 CR 与行尾注释
    line="$(printf '%s' "$raw" | sed -e 's/\r$//' -e 's/[[:space:]]*#[^:]*$//')"
    # 去掉行首/行尾空白；空行或以 # 开头的行跳过
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    # shellcheck disable=SC2086
    set -- $line
    state="$1"
    kind="$2"
    [ "$kind" = "repo" ] || continue
    shift 2

    url="$1"
    branch="$2"
    dest="$3"
    maps="$4"

    if [ -z "$url" ] || [ -z "$dest" ]; then
        echo "[第三方] !! 条目字段不足，跳过：$line"
        continue
    fi

    if [ "$state" = "off" ]; then
        echo "[第三方] off 跳过：$dest"
        skip=$((skip + 1))
        continue
    fi

    echo "--------------------------------------------------------------"
    echo "[第三方] 克隆 $url  ($branch)  →  $dest"
    rm -rf "$dest"
    if [ -z "$branch" ] || [ "$branch" = "-" ]; then
        git clone --depth=1 "$url" "$dest" || { echo "[第三方] !! 克隆失败：$url"; continue; }
    else
        git clone --depth=1 -b "$branch" "$url" "$dest" || { echo "[第三方] !! 克隆失败：$url ($branch)"; continue; }
    fi
    [ -d "$dest" ] || { echo "[第三方] !! 克隆目录不存在，跳过复制映射"; continue; }

    if [ -n "$maps" ]; then
        old_ifs="$IFS"
        IFS=','
        for item in $maps; do
            IFS="$old_ifs"
            src="${item%%:*}"
            dst="${item#*:}"
            if [ -z "$src" ] || [ -z "$dst" ] || [ "$src" = "$dst" ] && [ "$item" = "$src" ]; then
                echo "[第三方]   !! 复制映射写法有误：$item"
                IFS=','
                continue
            fi
            echo "[第三方]   复制 $dest/$src  →  $dst"
            mkdir -p "$(dirname "$dst")"
            rm -rf "$dst"
            cp -rf "$dest/$src" "$dst" || echo "[第三方]   !! 复制失败：$src"
            IFS=','
        done
        IFS="$old_ifs"
        # 有复制映射时，克隆目录视为临时目录，复制完删掉
        rm -rf "$dest"
    fi
    count=$((count + 1))
done < "$CFG"

echo "=============================================================="
echo " 第三方插件源处理完成：克隆 $count 个，跳过 $skip 个"
echo "=============================================================="

exit 0
