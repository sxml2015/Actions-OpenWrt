#!/bin/bash
# ============================================================================
#  dl_release.sh —— 按「标签名」自动解析 Release 并下载它的全部资源
#
#  用法：
#     dl_release.sh <标签名> <目标目录> [owner/repo]
#
#  说明：
#     · 以前 getImgs.sh / Flippy 工作流里写死了 release 数字 ID，每次都要手动改；
#       本脚本改成按标签名查询，不用再改 ID。
#     · 私有仓库/需要鉴权时，把令牌放进环境变量 TOKEN / GH_TOKEN / GITHUB_TOKEN /
#       RELEASES_TOKEN 任意一个即可（仓库公开时不填也能用）。
#
#  例子：
#     dl_release.sh Files /opt/kernel
#     dl_release.sh Build2512-N1 /opt/openwrt_packit
# ============================================================================
set -u

TAG="${1:-}"
DEST="${2:-}"
REPO="${3:-${GITHUB_REPOSITORY:-sxml/Actions-OpenWrt}}"

if [ -z "$TAG" ] || [ -z "$DEST" ]; then
    echo "用法: dl_release.sh <标签名> <目标目录> [owner/repo]"
    exit 2
fi

TOKEN="${TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-${RELEASES_TOKEN:-}}}}"

mkdir -p "$DEST" || exit 1
cd "$DEST" || exit 1

API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
AUTH=()
[ -n "$TOKEN" ] && AUTH=(-H "Authorization: Bearer $TOKEN")

echo "=============================================================="
echo " 下载 Release 资源"
echo "   仓库 : $REPO"
echo "   标签 : $TAG"
echo "   目录 : $DEST"
echo "=============================================================="

JSON="$(curl -fsSL "${AUTH[@]}" -H "Accept: application/vnd.github+json" "$API")" || {
    echo "[下载] !! 查询失败：$API"
    echo "[下载]    请确认标签名是否正确、令牌是否有效。"
    exit 1
}

URLS="$(printf '%s' "$JSON" | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4)"
if [ -z "$URLS" ]; then
    echo "[下载] !! 标签 $TAG 下没有任何资源文件"
    exit 1
fi

# 从 URL 末段取文件名时必须做 URL 解码。
#   GitHub 会把资产名里的 "+" 编码成 "%2B"：
#     资产名  boot-6.12.113-flippy-95+o.tar.gz
#     下载 URL .../download/Files/boot-6.12.113-flippy-95%2Bo.tar.gz
#   直接拿 URL 末段当文件名，落盘就成了 "...-95%2Bo.tar.gz"，
#   scripts/respawn_mks.sh 里的 find -name "boot*+o.tar.gz" 匹配不到，
#   KERNEL_VERSION 被写成空串，打包时报 "文件: [/opt/kernel/modules-.tar.gz] 不存在!"。
url_decode() {
    printf '%b' "${1//%/\\x}"
}

FAILED=0
for u in $URLS; do
    f="${u%%\?*}"
    f="${f##*/}"
    f="$(url_decode "$f")"
    echo "[下载]   $f"
    if ! curl -fL --retry 3 --retry-delay 3 "${AUTH[@]}" -o "$f" "$u"; then
        echo "[下载]   !! 下载失败：$u"
        FAILED=$((FAILED + 1))
    fi
done

echo "--------------------------------------------------------------"
ls -la "$DEST"
echo "--------------------------------------------------------------"

if [ "$FAILED" -ne 0 ]; then
    echo "[下载] !! 有 $FAILED 个文件下载失败"
    exit 1
fi

echo "[下载] 完成"
exit 0
