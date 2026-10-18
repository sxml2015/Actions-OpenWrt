#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_plugins_cfg.py —— 生成 / 重建 plugins.cfg 插件清单

它把两样东西合并成一份可读、可手改的插件清单：
  1) 批处理字典 TSV（每行 = 一个 CONFIG 项的启用/禁用写法 + 中文分组标签）
  2) 现有 .config 的真实 on/off 状态（并读取 .config 里自带的 "#注解" 作为分组标签）

一键用法（不带任何参数，自动用仓库里的默认路径）：
  python3 aarch64/scripts/build_plugins_cfg.py

手工指定路径的用法：
  python3 aarch64/scripts/build_plugins_cfg.py \
      --tsv    aarch64/Lede2512/插件字典.tsv \
      --config aarch64/Lede2512/Lede2512_FOL.config \
      --out    aarch64/Lede2512/plugins.cfg

说明：
  · 只在「想从零重建清单」或「字典更新了」时运行；
    平时直接手改 plugins.cfg 即可，不需要跑这个脚本。
  · --tsv 找不到时只用 .config 生成（LuCI 插件 + 注解分组），并给出提示。
  · luci-app-docker（老版 Python 界面）及其配套条目默认被排除，见 EXCLUDE_SYMBOLS；
    实际使用的 Docker 界面是 luci-app-dockerman，见 FORCE_GROUP。
"""
import argparse
import os
import re
import sys
from collections import OrderedDict

# 仓库根目录（本脚本在 aarch64/scripts/ 下）
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

KEY = r"CONFIG_[A-Za-z0-9_\-]+"
RE_ON = re.compile(r"^(%s)=y\b" % KEY)
RE_MOD = re.compile(r"^(%s)=m\b" % KEY)
RE_OFF = re.compile(r"^#\s*(%s) is not set\b" % KEY)
RE_KV = re.compile(r"^(%s)=y$" % KEY)

# ------------------------------------------------------------------------------
# 默认排除：luci-app-docker —— 老版 Docker 界面（Python 实现），
#   2026-10-16 按需求移除。它和 luci-app-dockerman 是两个不同的插件：
#     · luci-app-docker     ← 不要（就是本表这几项）
#     · luci-app-dockerman  ← 要，见下面的 FORCE_GROUP
#   想恢复就在本表里删掉对应项，再重建清单。
# ------------------------------------------------------------------------------
EXCLUDE_SYMBOLS = [
    "CONFIG_PACKAGE_luci-app-docker",
    "CONFIG_PACKAGE_luci-i18n-docker-zh-cn",
    "CONFIG_PACKAGE_python3-docker",
    "CONFIG_PACKAGE_python3-dockerpty",
]

# ------------------------------------------------------------------------------
# 关于「某个插件不想要了」——不需要在这里加任何表（2026-10-18 简化）
#
#   直接在 plugins.cfg 末尾的「自定义追加区」写一行：
#       off   luci-app-mosdns
#
#   这一行会：① 在最终 .config 里压掉基线的 =y（# CONFIG_xxx is not set）；
#             ② 重建清单时被原样保留，并且自动回写到上面的分组里（显示成 off），
#                所以不需要改这个脚本、也不会被基线还原成 on。
#   注意 off 只决定「编不编进固件」，第三方源码要不要克隆由 thirdparty.cfg 控制。
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# 强制归组：Docker（dockerman）整套。
#   这些项在字典里已经不再收录、在基线 .config 里也是散落的，
#   统一归到一个组里，方便集中开关。默认值以基线 .config 为准。
# ------------------------------------------------------------------------------
FORCE_GROUP = OrderedDict()
FORCE_GROUP["Docker（dockerman）"] = [
    "CONFIG_PACKAGE_luci-app-dockerman",        # 新版 LuCI 界面
    "CONFIG_PACKAGE_luci-lib-docker",           # dockerman 的必需依赖
    "CONFIG_PACKAGE_luci-i18n-dockerman-zh-cn",  # 中文语言包
    "CONFIG_PACKAGE_dockerd",                   # Docker 引擎守护进程
    "CONFIG_PACKAGE_docker",                    # Docker CLI
    "CONFIG_PACKAGE_docker-compose",            # docker-compose
    "CONFIG_DOCKER_CGROUP_OPTIONS",
    "CONFIG_DOCKER_NET_OVERLAY",
    "CONFIG_DOCKER_NET_MACVLAN",
    "CONFIG_DOCKER_NET_TFTP",
    "CONFIG_DOCKER_STO_EXT4",
    "CONFIG_DOCKER_STO_BTRFS",
]
GROUP_MAP = {k: g for g, ks in FORCE_GROUP.items() for k in ks}

# ------------------------------------------------------------------------------
# 必进清单：来自「目前在用需要的插件」清单，但既不在字典、
#   也不是 luci-app-/theme-/proto- 前缀，所以默认规则抓不到。
#   列在这里保证它们在 plugins.cfg 里可见、可开关。
#     基线值是 =y 的 → 清单里写成 on
#     基线值是 =m 的 → 清单里写成 skip（保持 =m 原样：只编成 ipk，不装进固件）
#   想装进固件就把对应的 skip 改成 on。
# ------------------------------------------------------------------------------
INCLUDE_EXTRA = [
    "CONFIG_PACKAGE_luci-app-cpe",
    "CONFIG_PACKAGE_luci-i18n-cpe-zh-cn",
    "CONFIG_PACKAGE_iptables-mod-tproxy",
    "CONFIG_PACKAGE_iptables-mod-extra",
    "CONFIG_PACKAGE_ipset",
]
INCLUDE_EXTRA_GROUP = "目前在用（必需）"


def decode(path):
    data = open(path, "rb").read()
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return data.decode("utf-16")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("utf-16")


# 纯装饰用分隔线，例如 "# ====..." / "# ----..."，用来切分清单里的各个区
RE_SEP = re.compile(r"^#\s*[=\-]{10,}\s*$")


def is_separator(line):
    return bool(RE_SEP.match(line.strip()))


def read_append_zone(path):
    """读出现有 plugins.cfg 里「自定义追加区」手写的条目。

    重建是整份覆盖，但追加区里手写的新插件（基线 config 里没有的项）
    重建一次就会消失——那份手写内容生成器无从推导，只能从旧文件里捞回来。
    这里只取「自定义追加区」那一段，遇到下一个分隔线（如「已排除」区）就停。
    """
    if not path or not os.path.isfile(path):
        return []
    lines = decode(path).splitlines()

    # 1) 定位「自定义追加区」标题行
    #    注意：文件顶部的使用说明里也提到这四个字（「自定义追加区」按 <on|off> …），
    #    所以取「最后一个」匹配，并且优先匹配带全角括号的正式标题。
    start = None
    for i, ln in enumerate(lines):
        if "自定义追加区（" in ln:
            start = i
    if start is None:
        for i, ln in enumerate(lines):
            if "自定义追加区" in ln:
                start = i
    if start is None:
        return []

    # 2) 跳过标题块（标题行 + 示例注释），直到结束分隔线
    i = start
    while i < len(lines) and not is_separator(lines[i]):
        i += 1
    if i >= len(lines):
        return []
    i += 1                      # 越过标题块的结束分隔线

    # 3) 收集到下一个分隔线（「已排除」区开头）或文件末尾
    raw = []
    while i < len(lines) and not is_separator(lines[i]):
        raw.append(lines[i].rstrip())
        i += 1

    # 4) 只保留「注释」和「合法的 on/off/skip 条目」，其余视为脏行
    kept = []
    for ln in raw:
        s = ln.strip()
        if not s:
            continue
        if s.startswith("#"):
            kept.append(ln)
            continue
        parts = s.split("#", 1)[0].split()
        if len(parts) >= 2 and parts[0].lower() in ("on", "off", "skip"):
            kept.append(ln)
        else:
            print("  ! 追加区这一行无法识别，重建时未保留：%s" % s)
    return kept


def short_name(key):
    for p in ("CONFIG_PACKAGE_luci-app-", "CONFIG_PACKAGE_luci-theme-",
              "CONFIG_PACKAGE_luci-i18n-", "CONFIG_PACKAGE_luci-proto-",
              "CONFIG_PACKAGE_luci-", "CONFIG_PACKAGE_", "CONFIG_DEFAULT_", "CONFIG_"):
        if key.startswith(p):
            return key[len(p):]
    return key


def clean_tag(t):
    t = (t or "").strip().lstrip("#=- ").rstrip("= ").strip()
    if not t or "===" in t or t.startswith("CONFIG_") or len(t) > 20:
        return ""
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", default=os.path.join(REPO_ROOT, "aarch64/Lede2512/插件字典.tsv"),
                    help="批处理字典 TSV（可省略）")
    ap.add_argument("--config", default=os.path.join(REPO_ROOT, "aarch64/Lede2512/Lede2512_FOL.config"),
                    help="现有 .config（基线配置）")
    ap.add_argument("--out", default=os.path.join(REPO_ROOT, "aarch64/Lede2512/plugins.cfg"),
                    help="输出的 plugins.cfg")
    ap.add_argument("--title", default="Lede2512 插件清单")
    ap.add_argument("--exclude", default=None,
                    help="额外要排除的 CONFIG 名（逗号分隔），与内置排除合并")
    ap.add_argument("--keep-excluded", action="store_true",
                    help="不做任何排除（Docker 条目会重新出现在清单里）")
    ap.add_argument("--keep-from", default=None,
                    help="从哪个旧 plugins.cfg 里保留「自定义追加区」的手写条目（默认 = --out 指向的文件）")
    ap.add_argument("--no-keep", action="store_true",
                    help="不保留追加区手写条目（整份覆盖，旧的覆盖行为）")
    args = ap.parse_args()

    if not os.path.isfile(args.config):
        print("!! 找不到基线 config：%s" % args.config)
        return 2
    if args.tsv and not os.path.isfile(args.tsv):
        print("!! 提示：找不到字典 %s，将只用 .config 生成清单" % args.tsv)

    excluded = set()
    if not args.keep_excluded:
        excluded.update(EXCLUDE_SYMBOLS)
        if args.exclude:
            excluded.update(x.strip() for x in args.exclude.split(",") if x.strip())

    # ---------- 0. 追加区手写条目的继承 ----------
    #  没有这一条，重建一次就把你手写的 `on luci-app-xxx` 冲掉了。
    keep_path = None if args.no_keep else (args.keep_from or args.out)
    kept_appendix = read_append_zone(keep_path)

    # ---------- 1. 基线 config 的真实状态 ----------
    #   on   = CONFIG_xxx=y          编译进固件
    #   mod  = CONFIG_xxx=m          只编成 ipk，不装进固件（清单里对应 skip）
    #   off  = # CONFIG_xxx is not set
    state = OrderedDict()
    annotated = OrderedDict()
    for line in decode(args.config).splitlines():
        s = line.strip()
        m = RE_ON.match(s) or RE_MOD.match(s) or RE_OFF.match(s)
        if not m:
            continue
        key = m.group(1)
        if s.startswith("CONFIG_"):
            val = s.split("=", 1)[1].split()[0] if "=" in s else "y"
            state[key] = "mod" if val == "m" else "on"
        else:
            state.setdefault(key, "off")
        rest = s[m.end():].strip()
        if rest.startswith("#"):
            annotated[key] = rest[1:].strip()

    # ---------- 1.5 追加区手写开关回写到分组 ----------
    #   你在「自定义追加区」写的 on/off 是「最终指令」，分组里那一行要跟着显示成同样
    #   的状态，否则会出现「分组里 on、实际是 off」的误导画面。
    #   语义与 gen_config.py 完全一致：后面的覆盖前面的；skip = 保持基线原值。
    override = OrderedDict()
    for raw in kept_appendix:
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        body = s.split("#", 1)[0].strip()
        parts = body.split()
        if len(parts) < 2:
            continue
        st, name = parts[0].lower(), parts[1]
        if st not in ("on", "off", "skip"):
            st = "on"
        key = name if name.upper().startswith("CONFIG_") else "CONFIG_PACKAGE_" + name
        key = re.sub(r"=.*$", "", key)
        override[key] = st
    applied = [(k, st) for k, st in override.items() if st != "skip" and k in state]
    for k, st in applied:
        state[k] = st

    # ---------- 2. 字典 ----------
    tsv_entries = []
    if args.tsv and os.path.isfile(args.tsv):
        section = ""
        for row in (l.split("\t") for l in decode(args.tsv).splitlines() if l.strip()):
            if len(row) == 1:
                section = clean_tag(row[0])
                continue
            if len(row) < 3:
                continue
            m = RE_KV.match(row[1].strip())
            if not m:
                continue
            tag = row[2].rsplit("#", 1)[1].strip() if "#" in row[2] else ""
            tsv_entries.append((m.group(1), clean_tag(tag), section))

    tsv_tag = {}
    for key, tag, section in tsv_entries:
        tsv_tag.setdefault(key, tag or section or "其他")
    for key, tag in annotated.items():
        t = clean_tag(tag)
        if t:
            tsv_tag[key] = t

    # ---------- 3. 合并 ----------
    def tag_of(key):
        if key in GROUP_MAP:
            return GROUP_MAP[key]
        if key in INCLUDE_EXTRA:
            return INCLUDE_EXTRA_GROUP
        t = tsv_tag.get(key, "")
        if t and not re.match(r"^[Ll][Ee][Dd][Ee]\s*\d+", t):
            return t
        if key.startswith("CONFIG_PACKAGE_luci-app-"):
            return "LuCI 应用插件"
        if key.startswith("CONFIG_PACKAGE_luci-theme-"):
            return "LuCI 主题"
        if key.startswith("CONFIG_PACKAGE_luci-proto-"):
            return "LuCI 协议"
        if key.startswith("CONFIG_DEFAULT_"):
            return "默认包（DEFAULT）"
        return "其他 / 服务包"

    keys = OrderedDict()
    for key, _t, _s in tsv_entries:
        if key in state and key not in excluded:
            keys.setdefault(key, None)
    for key in state:
        if key in excluded:
            continue
        if re.match(r"^CONFIG_PACKAGE_luci-(app|theme|proto)-", key):
            keys.setdefault(key, None)
    for key in annotated:
        if key not in excluded:
            keys.setdefault(key, None)
    # 必进清单的额外条目（基线里有才加）
    for key in INCLUDE_EXTRA:
        if key in state and key not in excluded:
            keys.setdefault(key, None)
    # Docker（dockerman）整套（基线里有才加）
    for _g, _ks in FORCE_GROUP.items():
        for key in _ks:
            if key in state and key not in excluded:
                keys.setdefault(key, None)

    # 实际被排除掉、且基线里确实存在的条目（写进文件末尾的说明区）
    excluded_hit = [k for k in state if k in excluded]

    groups = OrderedDict()
    for key in keys:
        groups.setdefault(tag_of(key), []).append(key)

    PRIORITY = [INCLUDE_EXTRA_GROUP] + list(FORCE_GROUP) + \
               ["LuCI 应用插件", "LuCI 主题", "LuCI 协议", "默认包（DEFAULT）"]
    ordered = OrderedDict((g, groups[g]) for g in PRIORITY if g in groups)
    for g, ks in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        ordered.setdefault(g, ks)
    groups = ordered

    groups = OrderedDict(
        (g, sorted(ks, key=lambda k: (state[k] != "on", short_name(k).lower())))
        for g, ks in groups.items()
    )

    width = min(max((len(k) for k in keys), default=32) + 2, 62)
    width = max(width, 30)
    n_on = sum(1 for k in keys if state[k] == "on")

    buf = []
    buf.append("# " + "=" * 86)
    buf.append("#  %s  plugins.cfg" % args.title)
    buf.append("# " + "-" * 86)
    buf.append("#  【怎么用】改完直接提交到 GitHub，再运行 Actions →「编译Lede2512_FOL」即可，无需本地环境。")
    buf.append("#    1) 行首 on   → 编译进固件     （config 里没有会自动补上代码）")
    buf.append("#    2) 行首 off  → 不编译该插件     （自动写入 \"# CONFIG_xxx is not set\"）")
    buf.append("#    3) 行首 skip → 脚本不干预       （保持基线 config 原值）")
    buf.append("#       基线里是 CONFIG_xxx=m（只编成 ipk、不装进固件）的项，默认就是 skip；")
    buf.append("#       想把它装进固件，把 skip 改成 on 即可。")
    buf.append("#    4) 新增 / 关闭插件：在文件最末尾「自定义追加区」按 <on|off> <包名或 CONFIG 名> 加一行")
    buf.append("#       例： on   luci-app-xxx        → 自动变成 CONFIG_PACKAGE_luci-app-xxx=y")
    buf.append("#           off  luci-app-yyy        → 自动变成 # CONFIG_PACKAGE_luci-app-yyy is not set")
    buf.append("#           on   CONFIG_PACKAGE_zzz  → 原样使用")
    buf.append("#       同一个条目写多次时，以「后面那一行」为准，所以追加区可以覆盖上面的分组开关。")
    buf.append("#    5) \"#\" 开头的是注释；行尾 \"#\" 后面是说明，随便改")
    buf.append("#")
    buf.append("#  【依赖保护】某个 off 的项如果被某个 on 的插件依赖（OpenWrt 的 select 依赖），")
    buf.append("#     make defconfig 会自动把它重新打开，编译日志里会打印「已自动保留」——")
    buf.append("#     这就是「依赖有关联其他功能需要就不能禁」的实现，不会把固件搞坏。")
    buf.append("#")
    buf.append("#  【重建】本文件可用 aarch64/scripts/build_plugins_cfg.py 从字典 + .config 重新生成。")
    buf.append("#     · 一键重建：GitHub → Actions →「重建插件清单」→ Run workflow")
    buf.append("#     · 有 python 的电脑：python3 aarch64/scripts/build_plugins_cfg.py （不带参数即可）")
    buf.append("#     初始 on/off = 生成时 .config 的真实状态：共 %d 组 / %d 项，当前 on %d 项。" % (len(groups), len(keys), n_on))
    buf.append("# " + "=" * 86)

    TOKEN = {"on": "on", "mod": "skip", "off": "off"}

    for gi, (gname, ks) in enumerate(groups.items(), 1):
        on_cnt = sum(1 for k in ks if state[k] == "on")
        mod_cnt = sum(1 for k in ks if state[k] == "mod")
        buf.append("")
        buf.append("# " + "-" * 86)
        buf.append("#  [%d/%d] %s   （%d 项，当前 on: %d%s）"
                   % (gi, len(groups), gname, len(ks), on_cnt,
                      "，=m 保持原样: %d" % mod_cnt if mod_cnt else ""))
        if gname == INCLUDE_EXTRA_GROUP:
            buf.append("#     这一组是「目前在用需要的插件」里、字典没收录但必须保留的项。")
            buf.append("#     带 skip 的是基线里的 =m（只编成 ipk，不装进固件）——想装进固件就改成 on。")
        if gname in FORCE_GROUP:
            buf.append("#     这一组是 luci-app-dockerman（新版 Docker 界面）整套；")
            buf.append("#     luci-lib-docker 是 dockerman 的必需依赖，关闭会导致 dockerman 不可用。")
        buf.append("# " + "-" * 86)
        for k in ks:
            buf.append("%-5s %-*s # %s" % (TOKEN[state[k]], width, k, short_name(k)))

    buf.append("")
    buf.append("# " + "=" * 86)
    buf.append("#  自定义追加区（基线 config 里没有的条目，脚本会自动补到 .config 末尾）")
    buf.append("#  例： on   luci-app-xxx              # 新增插件（包名直接写，会自动加 CONFIG_PACKAGE_ 前缀）")
    buf.append("#      on   CONFIG_PACKAGE_yyy         # 也可以直接写完整 CONFIG 名")
    buf.append("#      off  luci-app-bar               # 关闭某个插件（会压掉上面分组里的 on）")
    buf.append("#  两条规则：")
    buf.append("#    1) 这里写的 on/off 会「覆盖」上面分组里的同名项（后面的覆盖前面的）。")
    buf.append("#       重建清单时会自动回写，所以分组那边也会跟着显示成同样的状态。")
    buf.append("#    2) 这一区的内容重建时不会被清掉，手写的行会原样带过来。")
    buf.append("#  所以「不想要某个插件」只需在这里写一行 off，不用改任何脚本。")
    if kept_appendix:
        buf.append("#  ↓↓↓ 上次保留下来的手写条目有 %d 行，紧跟在下面的分隔线之后 ↓↓↓" % len(kept_appendix))
    buf.append("# " + "=" * 86)
    buf.append("")

    if kept_appendix:
        buf.extend(kept_appendix)
        buf.append("")

    if excluded_hit:
        buf.append("# " + "=" * 86)
        buf.append("#  【已排除】下面这些条目不参与本清单（保持基线 config 原值，不会被打开）。")
        buf.append("#     2026-10-16 按需求移除 luci-app-docker（老版 Python 界面）及其中文包。")
        buf.append("#     实际使用的 Docker 界面是 luci-app-dockerman，见上面的「Docker（dockerman）」组。")
        buf.append("#     想恢复：编辑 aarch64/scripts/build_plugins_cfg.py 里的 EXCLUDE_SYMBOLS，再重建清单。")
        buf.append("# " + "-" * 86)
        for k in excluded_hit:
            buf.append("#   %-58s # %s" % (k, short_name(k)))
        buf.append("# " + "=" * 86)
        buf.append("")

    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(buf) + "\n")

    print("生成:", args.out)
    print("组数: %d  总项: %d  on: %d  off: %d" % (len(groups), len(keys), n_on, len(keys) - n_on))
    if excluded_hit:
        print("已排除 %d 项：%s" % (len(excluded_hit), ", ".join(excluded_hit)))
    if applied:
        print("追加区覆盖 %d 项：%s"
              % (len(applied), ", ".join("%s=%s" % (short_name(k), st) for k, st in applied)))
    if kept_appendix:
        print("追加区保留 %d 行：来自 %s" % (len(kept_appendix), keep_path))
    elif not args.no_keep:
        print("追加区：没有手写条目需要保留")
    for g, ks in groups.items():
        print("  %-24s %4d  (on %d)" % (g, len(ks), sum(1 for k in ks if state[k] == "on")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
