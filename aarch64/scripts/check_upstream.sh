#!/bin/bash
# ==============================================================================
# 上游修补自检（Upstream Workaround Check）
# ------------------------------------------------------------------------------
# 读 upstream-pins.conf 登记表，逐条比对「上游该路径的最新提交」与「打钉时的
# 基准提交」，直接给出结论：
#     上游未改动 -> 钉子必须保留
#     上游已改动 -> 可能已修复，按登记的「修好后怎么处理」试删
#
# 设计原则：
#   · 恒 exit 0 —— 它只是提示，任何查询失败都不许影响 4 小时的编译
#   · 不依赖 jq，只用 curl + python3（runner 自带）
#   · 有 GITHUB_STEP_SUMMARY 时额外写一张表，Actions 运行页直接可见
#
# 用法：bash check_upstream.sh [登记表路径]
# 环境变量：UPSTREAM_REPO 默认 coolsnowwolf/lede
# ==============================================================================

CONF="${1:-aarch64/Lede2512/upstream-pins.conf}"
REPO="${UPSTREAM_REPO:-coolsnowwolf/lede}"
API="https://api.github.com/repos/${REPO}/commits"

echo ""
echo "====================== 上游修补自检 ======================"
echo "  上游库  : $REPO"
echo "  登记表  : $CONF"

if [ ! -f "$CONF" ]; then
    echo "  !! 找不到登记表，跳过本次自检（不影响编译）"
    echo "========================================================="
    exit 0
fi

SUMMARY="${GITHUB_STEP_SUMMARY:-}"
if [ -n "$SUMMARY" ]; then
    {
        echo "## 上游修补自检"
        echo ""
        echo "| 名字 | 监测路径 | 上游最新 | 结论 |"
        echo "| --- | --- | --- | --- |"
    } >>"$SUMMARY"
fi

pins=0
changed=0
unknown=0

while IFS='|' read -r f_name f_path f_base f_where f_how; do
    # 去首尾空白（同时顺带吃掉可能的 CR）
    f_name=$(printf '%s' "$f_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    f_path=$(printf '%s' "$f_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    f_base=$(printf '%s' "$f_base" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    f_where=$(printf '%s' "$f_where" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    f_how=$(printf '%s' "$f_how" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 跳过空行与注释行
    case "$f_name" in
        '' | '#'*) continue ;;
    esac
    # 字段不全就跳过（写错格式不该让日志变成一团乱码）
    if [ -z "$f_path" ] || [ -z "$f_base" ]; then
        echo "  [跳过] 登记项格式不完整：$f_name（需要 5 个字段，用 | 分隔）"
        continue
    fi

    pins=$((pins + 1))

    line=$(curl -fsSL --max-time 20 "${API}?path=${f_path}&per_page=1" 2>/dev/null \
        | python3 -c "import json,sys;d=json.load(sys.stdin)[0];print(d['sha'][:8], d['commit']['author']['date'], d['commit']['message'].splitlines()[0][:48])" 2>/dev/null)

    if [ -z "$line" ]; then
        unknown=$((unknown + 1))
        echo ""
        echo "  [$f_name] 查询失败（限流或网络），本次无法判断"
        echo "      监测: $REPO/$f_path"
        if [ -n "$SUMMARY" ]; then
            echo "| $f_name | $f_path | 查询失败 | 无法判断 |" >>"$SUMMARY"
        fi
        continue
    fi

    sha=${line%% *}
    case "$sha" in
        "$f_base"*) is_changed=0 ;;
        *) is_changed=1 ;;
    esac

    echo ""
    echo "  [$f_name]"
    echo "      监测: $REPO/$f_path"
    echo "      最新: $line"
    echo "      基准: $f_base"
    if [ "$is_changed" = "1" ]; then
        changed=$((changed + 1))
        echo "      状态: 上游已改动 —— 可能已修复，值得试一次"
        echo "      钉子: $f_where"
        echo "      处理: $f_how"
        if [ -n "$SUMMARY" ]; then
            echo "| $f_name | $f_path | $sha | **已改动，可试删** |" >>"$SUMMARY"
        fi
    else
        echo "      状态: 上游未改动 —— 钉子必须保留，本次不用做任何事"
        if [ -n "$SUMMARY" ]; then
            echo "| $f_name | $f_path | $sha | 未改动，保留 |" >>"$SUMMARY"
        fi
    fi
done <"$CONF"

echo ""
echo "---------------------------------------------------------"
echo "  共登记 $pins 条：$changed 条上游已改动，$unknown 条查询失败"
if [ "$pins" = "0" ]; then
    echo "  【结论】当前没有登记任何上游钉子。"
elif [ "$changed" -gt 0 ]; then
    echo "  【结论】有钉子对应的上游位置被改动了，按上面「处理」那一行做即可。"
    echo "::warning::上游已改动 $changed 项修补位置，可尝试移除对应钉子（详见日志）"
    if [ "$unknown" -gt 0 ]; then
        echo "  （另有 $unknown 条查询失败，未能核对，钉子先不要动。）"
    fi
elif [ "$unknown" -gt 0 ]; then
    # 有查询失败却说「全部未修复」是错话，会让人误以为核对过了
    echo "  【结论】$unknown 条查询失败（限流/网络），这几条没核对上；其余未修复。"
    echo "  钉子全部保留，本次不用做任何事；下次编译会重新查。"
    echo "::warning::上游自检有 $unknown 条查询失败，未能判断是否已修复"
else
    echo "  【结论】全部未修复，所有钉子继续保留，本次不用做任何事。"
fi
echo "========================================================="

exit 0
