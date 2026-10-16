#!/bin/bash
# ============================================================================
#  thirdparty.sh —— 第三方插件的「特殊处理」钩子
#  由 2512diy-part2.sh 在「所有第三方源码克隆完成之后」调用一次。
#  用途：编译工具、打补丁、改文件等无法用 thirdparty.cfg 一行描述的事情。
#  开关沿用 thirdparty.cfg 里的 block / repo 名字，例如 tp_block openclash
# ============================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/../scripts/tp_lib.sh" ]; then
    # shellcheck source=/dev/null
    . "$HERE/../scripts/tp_lib.sh"
else
    echo "[第三方] !! 找不到 tp_lib.sh，开关一律按 on 处理"
    tp_block() { return 0; }
    tp_block_state() { echo on; }
fi

echo "--------------------------------------------------------------"
echo "[第三方] 特殊处理"
echo "--------------------------------------------------------------"

# ---- OpenClash：需要先编译 po2lmo（LuCI 编译期会用到）--------------------
if tp_block openclash; then
    if [ -d package/luci-app-openclash/tools/po2lmo ]; then
        echo "[第三方] 编译 OpenClash 的 po2lmo"
        pushd package/luci-app-openclash/tools/po2lmo >/dev/null
        make && sudo make install
        popd >/dev/null
    else
        echo "[第三方] 未找到 OpenClash 的 po2lmo 目录，跳过"
    fi
else
    echo "[第三方] openclash 已关闭，跳过 po2lmo"
fi

echo "[第三方] 特殊处理完成"
exit 0
