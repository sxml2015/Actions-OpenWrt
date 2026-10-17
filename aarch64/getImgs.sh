#!/bin/bash
# ============================================================================
#  getImgs.sh —— 下载「Files」标签里的内核文件（供 openwrt_packit 打包用）
#
#  2026-10-16 改造：不再需要手动去 https://api.github.com/... 查 release 数字 ID，
#  改成按标签名自动解析。要换标签时只需设置环境变量 FILES_TAG。
#
#  环境变量：
#     FILES_TAG   资源所在的标签名（默认 Files）
#     KERNEL_DIR  下载到哪个目录（默认 /opt/kernel）
#     REPO_FULL   owner/repo（默认取 GITHUB_REPOSITORY，否则 sxml/Actions-OpenWrt）
#     TOKEN       需要鉴权时提供（公开仓库可不填）
# ============================================================================
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TAG="${FILES_TAG:-Files}"
DEST="${KERNEL_DIR:-/opt/kernel}"
REPO="${REPO_FULL:-${GITHUB_REPOSITORY:-sxml/Actions-OpenWrt}}"

mkdir -p "$DEST"
bash "$HERE/scripts/dl_release.sh" "$TAG" "$DEST" "$REPO"
