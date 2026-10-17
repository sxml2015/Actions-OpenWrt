#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_config.py —— Lede2512 固件配置生成器

作用：
  把「基线 config」+「插件清单 plugins.cfg」+「设备参数」合成出该设备最终使用的 .config。

核心行为：
  1. on   → 写入 CONFIG_xxx=y            （基线里没有的会自动追加到文件末尾）
  2. off  → 写入 # CONFIG_xxx is not set  （同样会自动追加）
  3. skip → 完全不碰，保持基线原值
  4. 依赖保护：被依赖项交给 `make defconfig` 处理（OpenWrt 的 select 依赖会自动把它重新打开），
     本脚本在 --verify 阶段把「被自动保留」的项打印出来，便于确认没有被误禁。
  5. 平台锁定：`CONFIG_TARGET_*` 平台身份行（armsr / armv8 / aarch64_generic）由脚本强制写入。
     换一份别人的基线 config 时，即使他原来是 x86 或别的板子，也不需要手工改 ——
     输出一定是本项目固定的平台。用 --no-lock-target 可关闭（一般不要关）。

用法：
  生成：
    gen_config.py --base <基线.config> --plugins <plugins.cfg> --device n1|x96 \
                  --out <输出.config> [--opt "<优化参数>"] [--report <报告.txt>]
  校验（make defconfig 之后运行）：
    gen_config.py --plugins <plugins.cfg> --verify <defconfig后的.config>
"""
import argparse
import json
import os
import re
import sys

KEY_RE = r"[A-Za-z0-9_\-]+"
RE_ON = re.compile(r"^(CONFIG_(?:%s))=y\b" % KEY_RE)
RE_OFF = re.compile(r"^#\s*(CONFIG_(?:%s)) is not set\b" % KEY_RE)
RE_ANY = re.compile(r"^#?\s*(CONFIG_(?:%s))[= ]" % KEY_RE)

# 两个设备的编译参数（CONFIG_TARGET_OPTIMIZATION）
DEVICES = {
    "n1": {
        "label": "Phicomm N1 (s905d)",
        "short": "N1",
        "opt": "-Os -pipe -mcpu=generic",
    },
    "x96": {
        "label": "X96 Max+ (s905x3)",
        "short": "X96",
        # S905X3 是 4x Cortex-A55（不是 A53）。
        # -march 保持不变（armv8-a+crypto，决定兼容性下限）；
        # -mtune=cortex-a55 只影响指令调度，不改变指令集，所以不降低兼容性。
        # 末尾那个空格是原有约定，保留。
        "opt": "-Os -pipe -march=armv8-a+crypto -mtune=cortex-a55 ",
    },
}

OPT_KEY = "CONFIG_TARGET_OPTIMIZATION"
OPT_ENABLE_KEY = "CONFIG_TARGET_OPTIONS"

# ------------------------------------------------------------------------------
# 平台锁定（2026-10-17）
#   N1 / X96 都是 Amlogic 盒子，走 Lede 的通用 ARM 平台 armsr / armv8 / aarch64_generic。
#   目的：换一份别人的基线 config 时，不管他原来是 x86、树莓派还是别的板子，
#         平台身份一律被强制改写成本项目固定的这套，**不需要再手工改 config**。
#
#   只锁「平台身份」这几行；CONFIG_TARGET_ROOTFS_* / PARTSIZE / 内核选项等用户偏好
#   仍然按基线 config 原样保留。
# ------------------------------------------------------------------------------
TARGET_BOARD = "armsr"
TARGET_SUBTARGET = "armv8"
TARGET_ARCH_PACKAGES = "aarch64_generic"

# 顶层板子启用行，例如 CONFIG_TARGET_x86=y / CONFIG_TARGET_bcm27xx=y
# 只匹配「全小写字母数字」的板名，避免误伤 CONFIG_TARGET_OPTIONS=y 这类大写选项。
RE_BOARD_ON = re.compile(r"^CONFIG_TARGET_([a-z][a-z0-9]*)=y$")


def target_lock_lines(board=TARGET_BOARD, subtarget=TARGET_SUBTARGET,
                      arch=TARGET_ARCH_PACKAGES):
    """平台身份的规范写法（顺序有意义，照 Lede 生成的顺序排）。"""
    return [
        "CONFIG_TARGET_%s=y" % board,
        "# CONFIG_TARGET_%s_armv7 is not set" % board,
        "CONFIG_TARGET_%s_%s=y" % (board, subtarget),
        "# CONFIG_TARGET_MULTI_PROFILE is not set",
        "CONFIG_TARGET_%s_%s_DEVICE_generic=y" % (board, subtarget),
        'CONFIG_TARGET_BOARD="%s"' % board,
        'CONFIG_TARGET_SUBTARGET="%s"' % subtarget,
        'CONFIG_TARGET_ARCH_PACKAGES="%s"' % arch,
        'CONFIG_TARGET_ROOTFS_DIR=""',
    ]


def key_of(line):
    """取出一行里的 CONFIG 名；不是配置行则返回 None。"""
    s = line.strip()
    m = RE_ON.match(s) or RE_OFF.match(s) or RE_ANY.match(s)
    return m.group(1) if m else None


def lock_target(lines, board=TARGET_BOARD, subtarget=TARGET_SUBTARGET,
                arch=TARGET_ARCH_PACKAGES):
    """强制把平台身份行改写成项目固定值，并清除其它板子的启用行。

    返回 (new_lines, foreign_boards)
      foreign_boards：基线里检测到的「别的板子」名字，供调用方打印警告。
    """
    lock = {}
    for ln in target_lock_lines(board, subtarget, arch):
        k = key_of(ln)
        if k and k not in lock:
            lock[k] = ln

    # 1) 基线里其它板子的启用行，例如换成 x86 的 config 会有 CONFIG_TARGET_x86=y
    foreign = sorted({
        m.group(1)
        for m in (RE_BOARD_ON.match(ln.strip()) for ln in lines)
        if m and m.group(1) != board
    })

    # 1.5) 已经合规（锁定行都在、且没有外来板子）→ 原样返回。
    #      这样现有基线生成出来的 config 逐字节不变，只在外来 config 上才动手。
    have = {ln.strip() for ln in lines}
    if not foreign and all(ln in have for ln in lock.values()):
        return lines, []

    # 2) 过滤：删掉平台锁定 key 的所有旧行 + 其它板子的行（含其子目标 / 设备行）
    kept = []
    insert_at = None
    for line in lines:
        k = key_of(line)
        drop = False
        if k in lock:
            drop = True
        elif k and any(k == "CONFIG_TARGET_" + b or k.startswith("CONFIG_TARGET_" + b + "_")
                       for b in foreign):
            drop = True
        if drop:
            if insert_at is None:
                insert_at = len(kept)
            continue
        kept.append(line)

    # 3) 插回锁定块：优先放回原来目标区的位置；找不到就放到文件头部注释之后
    if insert_at is None:
        insert_at = 0
        while insert_at < len(kept) and (not kept[insert_at].strip()
                                        or kept[insert_at].lstrip().startswith("#")):
            insert_at += 1

    block = [lock[k] for k in lock]
    out = kept[:insert_at] + block + [""] + kept[insert_at:]
    return out, foreign


def log(msg=""):
    sys.stdout.write(str(msg) + "\n")


def read_lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read().split("\n")


def parse_manifest(path):
    """返回 (entries, skipped_lines)；entry = (state, key, raw, lineno)"""
    entries = []
    for no, raw in enumerate(read_lines(path), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("[") or line.startswith("//"):
            continue
        # 去掉行尾注释（只处理 " #" 之后的内容，避免误伤 CONFIG 名）
        body = line.split("#", 1)[0].strip() if "#" in line else line
        if not body:
            continue
        parts = body.split()
        if len(parts) < 2:
            log("  ! 第 %d 行格式无法识别，已跳过：%s" % (no, raw.strip()))
            continue
        state, name = parts[0].lower(), parts[1]
        if state not in ("on", "off", "skip"):
            log("  ! 第 %d 行状态必须是 on/off/skip，已按 on 处理：%s" % (no, raw.strip()))
            state = "on"
        if name.upper().startswith("CONFIG_"):
            key = name
        else:
            key = "CONFIG_PACKAGE_" + name
        key = re.sub(r"=.*$", "", key)
        entries.append((state, key, raw, no))
    return entries


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--base")
    ap.add_argument("--plugins")
    ap.add_argument("--device", default="x96")
    ap.add_argument("--opt", default=None)
    ap.add_argument("--out")
    ap.add_argument("--report", default=None)
    ap.add_argument("--verify", default=None)
    ap.add_argument("--print-opt", action="store_true",
                    help="只打印该设备的 CONFIG_TARGET_OPTIMIZATION 取值，供工作流复用")
    ap.add_argument("--list-devices", action="store_true",
                    help="输出 GitHub Actions matrix 用的 JSON（含设备/标签/编译参数）")
    ap.add_argument("--only", default="all",
                    help="配合 --list-devices：all / n1 / x96，只输出部分设备")
    ap.add_argument("--build-prefix", default="Build2512", help="编译产物标签前缀")
    ap.add_argument("--lede-prefix", default="Lede2512", help="最终固件标签前缀")
    ap.add_argument("--dump", action="store_true", help="只打印将要做的改动，不写文件")
    ap.add_argument("--no-lock-target", action="store_true",
                    help="不锁定平台（默认会把 CONFIG_TARGET_* 强制改写成 %s/%s/%s）"
                         % (TARGET_BOARD, TARGET_SUBTARGET, TARGET_ARCH_PACKAGES))
    args = ap.parse_args()

    # 统一输出为 LF：脚本会输出 JSON/编译参数供工作流解析，
    # 在 Windows 上默认会带 \r，容易被误当成参数的一部分。
    try:
        sys.stdout.reconfigure(newline="\n")
    except Exception:
        pass

    # ---------------- 输出编译矩阵（供工作流使用）----------------
    if args.list_devices:
        only = (args.only or "all").lower()
        inc = []
        for key, prof in DEVICES.items():
            if only not in ("all", "", key):
                continue
            inc.append({
                "device": key,
                "short": prof["short"],
                "label": prof["label"],
                "opt": args.opt if args.opt is not None else prof["opt"],
                "tag": "%s-%s" % (args.build_prefix, prof["short"]),
                "aml": "%s-%s" % (args.lede_prefix, prof["short"]),
            })
        sys.stdout.write(json.dumps({"include": inc}, ensure_ascii=False) + "\n")
        return 0

    # ---------------- 只打印设备编译参数 ----------------
    if args.print_opt:
        dev = args.device.lower()
        if dev not in DEVICES:
            log("!! 未知设备：%s" % args.device)
            return 2
        sys.stdout.write(args.opt if args.opt is not None else DEVICES[dev]["opt"])
        sys.stdout.write("\n")
        return 0

    if not args.plugins:
        log("!! 缺少 --plugins 参数")
        return 2
    if not os.path.isfile(args.plugins):
        log("!! 插件清单不存在：%s" % args.plugins)
        return 2

    entries = parse_manifest(args.plugins)
    if not entries:
        log("!! 插件清单里没有解析到任何条目：%s" % args.plugins)
        return 2

    # ---------------- 校验模式 ----------------
    if args.verify:
        real = {}
        for line in read_lines(args.verify):
            s = line.strip()
            m = RE_ON.match(s)
            if m:
                real[m.group(1)] = "on"
                continue
            m = RE_OFF.match(s)
            if m:
                real.setdefault(m.group(1), "off")
        # 清单同样按「后面的覆盖前面的」聚合
        want = {}
        for state, key, raw, no in entries:
            if state != "skip":
                want[key] = state
        auto_kept, missing = [], []
        for key, state in want.items():
            if state == "off" and real.get(key) == "on":
                auto_kept.append(key)
            elif state == "on" and real.get(key) != "on":
                missing.append(key)
        log("")
        log("=" * 78)
        log("[配置校验] 插件清单 vs $( make defconfig ) 之后的最终 .config")
        log("=" * 78)
        if auto_kept:
            log("· 清单里标 off，但因为「被其它已启用插件依赖」被自动重新打开（%d 项，属正常）：" % len(auto_kept))
            for k in auto_kept:
                log("    + " + k)
        else:
            log("· 没有被依赖强制保留的项。")
        if missing:
            log("")
            log("· !! 清单里标 on，但最终没能启用（%d 项，请检查包名/源是否存在）：" % len(missing))
            for k in missing:
                log("    - " + k)
            log("")
            log("  常见原因：包不在 feeds 里（需要在 thirdparty.cfg 增加第三方插件源）、")
            log("            或依赖不满足导致 Kconfig 隐藏该项。")
        else:
            log("· 清单里标 on 的项全部启用成功。")
        log("=" * 78)
        return 0

    # ---------------- 生成模式 ----------------
    if not args.base or not args.out:
        log("!! 生成模式需要 --base 与 --out 参数")
        return 2
    dev = args.device.lower()
    if dev not in DEVICES:
        log("!! 未知设备：%s（可选 %s）" % (args.device, "/".join(DEVICES)))
        return 2
    prof = DEVICES[dev]
    optimization = args.opt if args.opt is not None else prof["opt"]

    base = read_lines(args.base)

    # ---- 平台锁定：不管基线 config 原来是哪个目标平台，一律改写成本项目固定值 ----
    foreign_boards = []
    if not args.no_lock_target:
        base, foreign_boards = lock_target(base)

    # 索引：key -> 行号（同一 key 可能出现多次，全部记录）
    index = {}
    for i, line in enumerate(base):
        s = line.strip()
        m = RE_ON.match(s) or RE_OFF.match(s) or RE_ANY.match(s)
        if m:
            index.setdefault(m.group(1), []).append(i)

    # ---- 汇总：后出现的条目覆盖先出现的（自定义追加区因此可以覆盖上面的分组开关）----
    out = list(base)
    appended = []
    changed = []
    stats = {"on": 0, "off": 0, "skip": 0, "new": 0}
    final = {}
    order = []
    overridden = []
    for state, key, raw, no in entries:
        stats[state] += 1
        if state == "skip":
            if key in final:
                overridden.append((key, "skip", no))
            if key not in final:
                order.append(key)
            final[key] = "skip"
            continue
        if key in final and final[key] != state:
            overridden.append((key, state, no))
        if key not in final:
            order.append(key)
        final[key] = state

    for key in order:
        state = final[key]
        if state == "skip":
            continue
        want = "%s=y" % key if state == "on" else "# %s is not set" % key
        if key in index:
            for i in index[key]:
                out[i] = want
            changed.append(key)
        else:
            appended.append(want)
            stats["new"] += 1

    # 设备编译参数
    def set_key(container_list, key, value):
        pat = re.compile(r"^#?\s*%s[= ]" % re.escape(key))
        for i, line in enumerate(container_list):
            if pat.match(line.strip()):
                container_list[i] = value
                return True
        return False

    for key, value in ((OPT_ENABLE_KEY, "%s=y" % OPT_ENABLE_KEY),
                       (OPT_KEY, '%s="%s"' % (OPT_KEY, optimization))):
        if not set_key(out, key, value):
            appended.append(value)

    if appended:
        out.append("")
        out.append("# " + "=" * 74)
        out.append("# 由 plugins.cfg / gen_config.py 自动补充（基线 config 中原本没有这些条目）")
        out.append("# " + "=" * 74)
        out.extend(appended)

    text = "\n".join(out)
    if not text.endswith("\n"):
        text += "\n"

    if args.dump:
        log("[dump] 设备=%s  优化参数=%s" % (dev, optimization))
        log("变更 %d 项，追加 %d 项" % (len(changed), len(appended)))
    else:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    if foreign_boards:
        log("")
        log("!" * 78)
        log("!! 注意：基线 config 的目标平台检测到 %s，不是本项目固定的 %s/%s。"
            % (", ".join(foreign_boards), TARGET_BOARD, TARGET_SUBTARGET))
        log("!! 已自动改写为 %s/%s（%s），你不需要再手工改 config。"
            % (TARGET_BOARD, TARGET_SUBTARGET, TARGET_ARCH_PACKAGES))
        log("!! 但这份 config 里的包选择 / 内核选项原本可能是为那个平台准备的，")
        log("!! 建议抽查 plugins.cfg，把不需要的用 off 关掉。")
        log("!" * 78)

    report = []
    report.append("=" * 78)
    report.append("gen_config 生成报告")
    report.append("=" * 78)
    report.append("  设备          : %s  (%s)" % (prof["label"], dev))
    report.append("  编译参数      : CONFIG_TARGET_OPTIMIZATION=\"%s\"" % optimization)
    plat = "%s/%s (%s)" % (TARGET_BOARD, TARGET_SUBTARGET, TARGET_ARCH_PACKAGES)
    if args.no_lock_target:
        plat += "   [未锁定，按基线原样]"
    elif foreign_boards:
        plat += "   [已强制改写；基线原平台: %s]" % ", ".join(foreign_boards)
    else:
        plat += "   [已确认一致]"
    report.append("  目标平台      : %s" % plat)
    report.append("  基线 config   : %s" % args.base)
    report.append("  插件清单      : %s" % args.plugins)
    report.append("  输出 config   : %s" % args.out)
    report.append("  清单条目      : 共 %d 项  (on %d / off %d / skip %d)"
                  % (stats["on"] + stats["off"] + stats["skip"], stats["on"], stats["off"], stats["skip"]))
    report.append("  覆盖基线行    : %d" % len(changed))
    report.append("  自动补上的行  : %d" % len(appended))
    report.append("=" * 78)
    if overridden:
        report.append("")
        report.append("· 下列条目在清单里出现了多次，已按「后面的覆盖前面的」处理（%d 项）：" % len(overridden))
        for key, state, no in overridden:
            report.append("    %s  →  %s（第 %d 行）" % (key, state, no))
        report.append("=" * 78)
    report_txt = "\n".join(report)
    log("")
    log(report_txt)
    if args.report and not args.dump:
        os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)
        with open(args.report, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(report_txt + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
