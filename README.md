# Lede 25.12 云编译说明（先看这里）

本仓库在 GitHub 上云编译 **Lede（coolsnowwolf/lede，master 分支）openwrt-25.12** 固件，  
目标是 **Phicomm N1 (s905d)** 与 **X96 Max+ (s905x3)** 两个电视盒子。

全程只改仓库里的文本文件 + 在 Actions 页面点几下，**不需要本地编译环境，也不需要 SSH / make menuconfig**。

> **2026-10-17 变更**：
> · 修正 `F打包_*` 的 `Invalid workflow file` 报错（`jobs.<id>.name` 不支持 `env` 上下文，已改为字面量）；
> · 修正 Python 包 wheel 名补丁的误伤（`itsdangerous` 等包编译失败）；
> · `gen_config.py` 新增**平台自动锁定**，换别人的 config 不再需要手改平台行（见 4.1）；
> · 补齐网页上传漏掉的 7 个文件，并把碎片提交整理成 4 个有意义的提交。
>
> 2026-10-16 变更：旧版本号 `1806` 全部改名为 `2512`（目录、文件名、工作流名、标签名、脚本内容都已同步），  
> 并移除了老版 Docker 界面 `luci-app-docker`（继续使用 `luci-app-dockerman`）。  
> 改名前的老文件备份在仓库外的 `_旧版本备份/` 里。

---

## 一、六个工作流的分工

**主力四个**（编译 + 两个打包 + 重建清单）：

| 工作流（Actions 里的名字）  | 作用                                           | 产出标签                                 |
| ------------------ | -------------------------------------------- | ------------------------------------ |
| `编译Lede2512_FOL`   | 编译 rootfs（两个设备共用一套插件清单，只有编译参数不同）             | `Build2512-N1`、`Build2512-X96`（中间产物） |
| `F打包_Lede2512_N1`  | 用 openwrt_packit 把 N1 的 rootfs 打成 `.img.gz`  | `Lede2512-N1-日期时间`                   |
| `F打包_Lede2512_X96` | 用 openwrt_packit 把 X96 的 rootfs 打成 `.img.gz` | `Lede2512-X96-日期时间`                  |
| `重建插件清单`           | 按字典重新生成 `plugins.cfg`（改插件清单时才用）              | —                                    |

**辅助两个**（平时不用管）：

| 工作流 | 作用 |
| --- | --- |
| `删除旧工件和缓存` | 删掉旧的 workflow run 和编译缓存，省存储配额，可手动跑 |
| `提取Lede2512-config` | 备用：在线 SSH 进 Actions 提取 `.config`，**有封号风险，用不上别动**（见文末备忘） |

**运行顺序**：先跑 `编译Lede2512_FOL`（界面里选 `all` / `n1` / `x96`），成功后分别跑两个 `F打包_*`。

> `Build2512-N1` / `Build2512-X96` 是**编译中间产物**（只放 rootfs，供 Flippy 取用），  
> 名字固定、每次编译覆盖，不会在 Releases 页面累积；已标为预发布（Pre-release），  
> 会被折叠到页面的 Pre-releases 区，正式固件 `Lede2512-*-日期时间` 排在前面。

---

## 二、编译前自选插件 —— `aarch64/Lede2512/plugins.cfg`

在 GitHub 网页上直接编辑这个文件，改完提交，然后运行 `编译Lede2512_FOL` 即可。语法：

```
on    CONFIG_PACKAGE_luci-app-openclash      # 编译进固件
off   CONFIG_PACKAGE_luci-app-ramfree        # 不编译（自动写 "# CONFIG_xxx is not set"）
skip  CONFIG_PACKAGE_luci-app-cpe            # 脚本不干预，保持基线 config 原值
```

- 清单按 **91 个分组 / 539 项**排列（第一组「目前在用（必需）」→ Docker（dockerman）→  
  LuCI 应用插件 / 主题 / 协议 → Wifi 基础包 / 下载工具 …），每行末尾 `#` 后面是说明，随便改，不影响解析。
  当前状态是 **on 82 项 / off 457 项**。
- **加插件**：在文件最末尾「自定义追加区」加一行；包名直接写（会自动补 `CONFIG_PACKAGE_` 前缀），  
  基线 config 里没有的条目脚本会自动补上代码。
- **同一个条目写多次时，以最后一行那一行为准**，所以追加区可以覆盖上面的分组开关。
- **依赖保护**：某个 `off` 的项如果被某个 `on` 的插件依赖（OpenWrt 的 `select` 依赖），  
  `make defconfig` 会自动把它重新打开，编译日志里会打印「已自动保留」，不会把固件搞坏。
- 文件末尾有「已排除」区，列出了不再参与清单的条目（目前是老版 `luci-app-docker` 那一组）。

### 关于 `skip` 和 `=m`

基线 config 里 `CONFIG_xxx=m` 的项意思是「只编成 ipk 包、不装进固件」。  
清单里这类项默认写成 `skip`（保持 `=m` 原样），想把它装进固件就把 `skip` 改成 `on`。  
当前属于这种情况的有：`luci-app-cpe`、`luci-i18n-cpe-zh-cn`  
（`kmod-fast-classifier`、`kmod` 是 turboacc 用的，本来就不该进固件）。

### 关于 Docker

**用的是 `luci-app-dockerman`（新版 LuCI 界面），不是 `luci-app-docker`。**  
这两个是两个不同的插件，容易搞混：

| 插件                   | 状态    | 说明                                                                                 |
| -------------------- | ----- | ---------------------------------------------------------------------------------- |
| `luci-app-dockerman` | **开** | 新版界面，在清单第 2 组「Docker（dockerman）」。需要配套引擎 `dockerd` / `docker` 和依赖 `luci-lib-docker` |
| `luci-lib-docker`    | **开** | `luci-app-dockerman` 的必需依赖，关掉会导致 dockerman 不可用                                     |
| `luci-app-docker`    | **关** | 老版 Python 界面（配套 `python3-docker`、`python3-dockerpty`），已从清单里排除                      |

插件字典里删掉了「Docker容器」这一整段（16 条），所以清单里的这套是靠  
`build_plugins_cfg.py` 的 `FORCE_GROUP` 强制归到一组、状态以基线 `.config` 为准。

将来想改回老版 `luci-app-docker`：编辑 `build_plugins_cfg.py` 里的 `EXCLUDE_SYMBOLS`，  
再跑一次「重建插件清单」。整个 Docker 不要了：把「Docker（dockerman）」组里 12 项全改成 `off` 即可。

---

## 三、重建 / 一键生成 plugins.cfg

`aarch64/scripts/build_plugins_cfg.py` 把两样东西合并成一份可读可改的清单：

1. 插件字典 `aarch64/Lede2512/插件字典.tsv`（每行 = 一个 CONFIG 项的写法 + 中文分组标签）
2. 基线 `Lede2512_FOL.config` 的真实 on/off 状态（并读取 config 里自带的 `#注解` 当分组标签）

**三种跑法，选一种就行：**

| 方式              | 怎么做                                                        | 需要什么          |
| --------------- | ---------------------------------------------------------- | ------------- |
| ① 网页一键（推荐）      | Actions →「重建插件清单」→ Run workflow                            | 什么都不需要        |
| ② 本地一键（Windows） | 双击 `aarch64/scripts/一键重建插件清单.bat`                          | 电脑上有 Python 3 |
| ③ 本地命令行         | `python3 aarch64/scripts/build_plugins_cfg.py`（**不带参数即可**） | 有 Python 3    |

方式①跑完会把新的 `plugins.cfg` 自动提交回仓库（运行界面里可以选「不提交」，只下载产物）。  
方式②③在本机更新 `aarch64/Lede2512/plugins.cfg`，自己提交/上传即可。

> 平时只是增删插件的话，**直接编辑 `plugins.cfg` 就够了**，不用跑这个脚本。  
> 只有「字典改了」或「换了新基线 config」时才需要重建。

### 重建的两个坑（很重要）

**坑 1：重建是整份覆盖。** on/off 全部按基线 config 重新算，**不读现有的 `plugins.cfg`**。  
你在清单里手改过的开关会被清掉。所以正确顺序永远是：

```
先准备好基线 config / 字典  →  再重建  →  最后精调 plugins.cfg 的 on/off
```

反过来做（先精调、后重建）等于白改。

**坑 2：只收基线 config 里出现过的条目。** 生成器里有一条 `if key in state` 判断：  
字典里有、**基线 config 里完全没有**的 CONFIG，跑多少次重建都不会出现在清单里。  
要加这种插件，只能在清单末尾的「自定义追加区」手写一行：

```
on   CONFIG_PACKAGE_luci-app-xxx
```

`gen_config.py` 会把它追加到最终 `.config` 末尾，`make defconfig` 能认。

---

## 四、增加第三方插件 —— `aarch64/Lede2512/thirdparty.cfg`

```
# 关掉不用的内置克隆块（省编译时间、少踩坑）
off block openclash
off block ddns-go

# 新增第三方插件：一行一个仓库
on  repo https://github.com/xxx/luci-app-yyy.git master package/yyy luci-app-yyy:luci-app-yyy
```

- `block` 控制 `2512diy-part2.sh` 里已有的第三方克隆块（smartdns / kenzok8-small / helloworld /  
  passwall-packages / passwall / passwall2 / lua-maxminddb / amlogic / mosdns / ddns-go / openclash / vim）。
- `repo` 行会自动 `git clone`；`复制映射`（`源子目录:目标目录`）用于「包在仓库子目录里」的情况，  
  有映射时克隆目录会在复制完成后自动删除。
- 需要编译工具 / 打补丁 / 改文件的特殊插件，写进同目录的 `thirdparty.sh`。

### 4.1 换一份别人的 config —— 平台会自动锁定

拿别人的 `.config` 来改自己的插件，**不需要手工改平台相关的行**：

1. 备份现有 `aarch64/Lede2512/Lede2512_FOL.config`（改名成 `.bak-日期` 或移到 `_旧版本备份/`）；
2. 把别人的 config 复制进来，**文件名必须是 `Lede2512_FOL.config`**；
3. 双击 `aarch64/scripts/一键重建插件清单.bat` 重新生成 `plugins.cfg`；
4. 在 `plugins.cfg` 里把不想要的功能改成 `off`。

第 3 步是关键：`plugins.cfg` 的 on/off 是**按基线 config 的真实状态**生成的，  
所以换 config 后必须重建，否则清单还是旧的。**重建会覆盖你在 `plugins.cfg` 里的手动修改**，  
所以顺序一定是「先换 config → 再重建 → 最后精调」。

**平台不需要你管。** `gen_config.py` 在合成 `.config` 时会强制把平台身份写成固定值：

```
CONFIG_TARGET_armsr=y
CONFIG_TARGET_armsr_armv8=y
CONFIG_TARGET_BOARD="armsr"
CONFIG_TARGET_SUBTARGET="armv8"
CONFIG_TARGET_ARCH_PACKAGES="aarch64_generic"
```

即使别人的 config 原本是 `x86`、树莓派或别的板子，也会被自动改写，编译日志里会打印一条醒目提示：

```
!! 注意：基线 config 的目标平台检测到 x86，不是本项目固定的 armsr/armv8。
!! 已自动改写为 armsr/armv8（aarch64_generic），你不需要再手工改 config。
```

只锁「平台身份」；`CONFIG_TARGET_ROOTFS_PARTSIZE`（根分区大小）、内核选项等用户偏好  
仍然保持基线 config 的原值。

⚠️ 平台能自动纠正，但**包选择不能**。别人 config 里如果开了你没有源码的第三方插件，  
`make defconfig` 会把它们丢掉并打 warning（不影响编译）；想彻底干净就在 `plugins.cfg` 里 `off`。

### 4.2 编译报错的补丁代码放哪个脚本

先记住工作流的真实执行顺序，所有判断都基于它：

```
part1 → feeds update -a → feeds install -a → part2 → make defconfig → make download → make
```

（`part2` 内部还会再跑一次 `feeds update/install`，然后依次调用 `clone_thirdparty.sh`、`thirdparty.sh`。）

| 要改的东西 | 放哪个脚本 | 为什么 |
| --- | --- | --- |
| `package/lean/*`、`include/*`、`target/*`、`package/base-files`（lede 自带） | **`2512diy-part1.sh`** | 克隆完 lede 就存在；跑在 feeds update 之前，最不会被覆盖 |
| `feeds/packages/*`、`feeds/luci/*`（feeds 里的包） | **`2512diy-part2.sh`**，且必须写在 `./scripts/feeds install -a` **之后** | feeds 目录那时才存在；part2 自己还会再 update 一次，写前面会被冲掉 |
| 第三方克隆进来的包 | **`aarch64/Lede2512/thirdparty.sh`** | 克隆完成后自动执行 |
| 装编译依赖、改全局环境 | `2512diy-part2.sh` 开头 | 早执行 |

**三个坑：**

- **sed 少一个空格就静默失效。** 真实 Makefile 是 `include $(INCLUDE_DIR)/package.mk`，
  `include` 后面**有空格**；写成 `include$(INCLUDE_DIR)` 匹配不到，你以为补丁打上了其实没有。
- **不要硬编码交叉编译器前缀。** 用 `$(TARGET_CROSS)gcc` / `$(TARGET_CROSS)g++`，换平台自动正确。
- **`make package/xxx/clean` 不要写进 diy 脚本。** 那时 `.config` 还没生成（`make defconfig` 在后面），
  而且 `part2` 开头已经 `rm -rf staging_dir build_dir`，清理本就是多余的。

**通用骨架**（判存在 + 判幂等 + 打日志，三样缺一不可）：

```bash
MK=package/lean/xxx/Makefile          # 或 feeds/packages/.../Makefile
if [ ! -f "$MK" ]; then
    echo "[part1] 跳过：$MK 不存在"
elif grep -q '你的标记字符串' "$MK"; then
    echo "[part1] 已修补过，跳过"
else
    sed -i '你的替换' "$MK"
    echo "[part1] 已修补 $MK"
fi
```

---

## 五、N1 / X96 分开编译

`编译Lede2512_FOL` 运行时可以在界面上选 `all` / `n1` / `x96`。  
两个设备唯一的差别是编译参数（唯一来源是 `aarch64/scripts/gen_config.py` 里的设备表）：

| 设备                 | CPU           | CONFIG_TARGET_OPTIMIZATION                           |
| ------------------ | ------------- | ---------------------------------------------------- |
| Phicomm N1 (s905d) | 4× Cortex-A53 | `-Os -pipe -mcpu=generic`                            |
| X96 Max+ (s905x3)  | 4× Cortex-A55 | `-Os -pipe -march=armv8-a+crypto -mtune=cortex-a55 ` |

两个矩阵任务使用**独立编译缓存**（`Build2512-N1` / `Build2512-X96`），互不污染。

关于这两个参数的差别（**决定能不能刷到别的盒子上的是 `-march`，不是 `-mtune`**）：

- `-mcpu=generic`（N1）＝ 基础 ARMv8-A，不启用任何 CPU 专属扩展，**兼容性最好**，  
  所有 armv8-a 盒子都能跑，但用不上硬件加密加速。
- `-march=armv8-a+crypto`（X96）会让编译器真的生成 AES / SHA 硬件指令，  
  加解密性能明显更好（OpenSSL、WireGuard、代理类插件受益），  
  **代价是只能跑在支持 crypto 扩展的 CPU 上**——N1 的 A53 带 crypto 所以能跑，  
  但放到不带 crypto 的老盒子会 illegal instruction 崩。
- `-mtune=cortex-a55` **不影响兼容性**，只告诉编译器按 A55 的流水线做指令调度。  
  它和 `-march` 是独立的：这里 `-march` 仍是 `armv8-a`，所以生成的二进制一样能在  
  A53 上跑，只是调度按 A55 优化。（GCC 8.1 起支持 `-mtune=cortex-a55`，本项目工具链是  
  GCC 13/14，没问题。）

## 六、Flippy 打包区分设备

- 每个 Flippy 工作流只跑自己设备的打包脚本：  
  N1 → `mk_s905d_n1_basic.sh` + `mk_s905d_n1_plus.sh`；  
  X96 → `mk_s905x3_multi_basic.sh` + `mk_s905x3_multi_plus.sh`。
- 内核文件从 `Files` 标签自动下载（`aarch64/getImgs.sh` + `aarch64/scripts/dl_release.sh`），  
  **不再需要手动去 API 页查 release 数字 ID**；换标签只改 `FILES_TAG`。
- 发布标签：`Lede2512-N1-<日期时间>` / `Lede2512-X96-<日期时间>`。
- 晶晨宝盒的 Releases 关键字会按设备自动写成 `Lede2512-N1` / `Lede2512-X96`，避免刷错固件。

---

## 七、相关文件一览

```
.gitattributes            换行符策略（仓库内强制 LF，防止在 Windows 上改出 CRLF）
.gitignore                忽略规则（Python 缓存、备份文件、临时产物）
.github/workflows/
  Lede2512_FOL.yml        编译（双设备矩阵，界面选 all/n1/x96）
  Flippy_Lede2512_N1.yml  N1 打包
  Flippy_Lede2512_X96.yml X96 打包
  Rebuild_Plugins.yml     重建插件清单（一键）
  remove-old-artifacts.yml 定期清理旧工件和缓存
  sshLede2512.yml         在线 SSH 提取 .config（备用，小心封号）
aarch64/Lede2512/
  Lede2512_FOL.config     基线 config（目标平台/系统/内核/基础包），一般不用改
  plugins.cfg             插件清单 ← 平时主要改这个
  插件字典.tsv            插件字典（重建清单的依据，来自「批处理字典」）
  thirdparty.cfg          第三方插件清单与开关 ← 需要时改这个
  thirdparty.sh           第三方插件特殊处理钩子
  feeds.conf.default      feeds 源（luci 用的是 openwrt-25.12 分支）
  2512diy-part1.sh        feeds 之前的自定义（git 克隆）
  2512diy-part2.sh        移除包 / 克隆第三方 / 编译修复
aarch64/scripts/          【GitHub 编译必须传】
  gen_config.py           .config 生成器（插件清单 + 设备参数 + 校验）
  build_plugins_cfg.py    plugins.cfg 生成器（不带参数 = 一键重建）
  clone_thirdparty.sh     按 thirdparty.cfg 克隆第三方插件
  tp_lib.sh               第三方开关读取函数
  dl_release.sh           按标签名下载 Release 全部资源
                          ---- 以下是「只在你本机用」的，可以不传 ----
  rebuild_plugins.sh      上面生成器的 Linux/macOS 版
  一键重建插件清单.bat      上面生成器的 Windows 双击版
aarch64/
  getImgs.sh              下载 Files 标签里的内核文件
  autoVersion.sh          把源码版本号写进打包用的 whoami
depends-ubuntu-2204       编译依赖清单（apt 包列表）
scripts/
  respawn_mks.sh          重新生成 openwrt_packit 打包脚本
  whoami                  打包用的版本标识模板
```

`aarch64/scripts/` 里那 2 个本地脚本**不传也不影响云端编译**——GitHub 是 Linux 环境，  
`rebuild_plugins.sh` / `.bat` 只在你自己电脑上双击用；真要重建清单，网页上点  
「重建插件清单」工作流即可。它们加起来才 2.7 KB，传上去也无害。

仓库里目前只剩一个「用不到」的目录：`general/`（P3TERX 模板遗留的第三方包源码 + 补丁，  
59 个文件 474 KB）。**2512 这条线全仓库 0 处引用它**，想精简仓库可以不传，不影响编译。  
（`aarch64/Lede2305/`、`aarch64/immortalwrt/` 两条老线和原作者的 `redo.sh` 已经移除。）

---

## 八、在新 GitHub 账号上部署这套项目

## 8.1 哪些文件要上传？

分三类，按需取舍。

### ① 必须传 —— 少一个云端就编译不起来

| 路径                                            | 说明                                       |
| --------------------------------------------- | ---------------------------------------- |
| `.github/workflows/Lede2512_FOL.yml`          | 编译主工作流                                   |
| `.github/workflows/Flippy_Lede2512_N1.yml`    | N1 打包                                    |
| `.github/workflows/Flippy_Lede2512_X96.yml`   | X96 打包                                   |
| `.github/workflows/Rebuild_Plugins.yml`       | 重建插件清单（网页一键）                             |
| `aarch64/Lede2512/` **整个目录**                  | 基线 config、插件清单、插件字典、第三方清单、diy 脚本、feeds 源 |
| `aarch64/scripts/gen_config.py`               | 编译时合成 `.config` —— **没它编译直接失败**          |
| `aarch64/scripts/build_plugins_cfg.py`        | 「重建插件清单」工作流要调用                           |
| `aarch64/scripts/clone_thirdparty.sh`         | 按 `thirdparty.cfg` 克隆第三方插件               |
| `aarch64/scripts/tp_lib.sh`                   | 第三方开关读取函数（被 `2512diy-part2.sh` 引用）       |
| `aarch64/scripts/dl_release.sh`               | 打包时按标签名下载 Release 资源                     |
| `aarch64/getImgs.sh`、`aarch64/autoVersion.sh` | Flippy 工作流会调用                            |
| `scripts/respawn_mks.sh`、`scripts/whoami`     | Flippy 打包用                               |
| `depends-ubuntu-2204`                         | 编译环境 apt 依赖清单                            |


### ② 建议留着 —— 不传不影响编译

| 路径                                           | 说明                           |
| -------------------------------------------- | ---------------------------- |
| `.gitignore`                                 | 挡掉 Python 缓存、备份文件、临时产物       |
| `.gitattributes`                             | 强制仓库内 LF，防止 Windows 改出 CRLF |
| `README.md`、`插件说明.md`                        | 说明书                          |
| `.github/workflows/sshLede2512.yml`          | 备用：在线 SSH 提取 `.config`（小心封号） |
| `.github/workflows/remove-old-artifacts.yml` | 定期清理旧工件和缓存，可单独跑              |
| `LICENSE`                                    | 原项目协议                        |

### ③ 可以不传 —— 本地用 / 已无引用

| 路径                                   | 原因                                            |
| ------------------------------------ | --------------------------------------------- |
| `aarch64/scripts/rebuild_plugins.sh` | 只在**你本机** Linux/macOS 上跑；云端用工作流重建即可           |
| `aarch64/scripts/一键重建插件清单.bat`       | 只在你本机 Windows 上双击用，云端执行不了 `.bat`              |
| `general/`（59 个文件 / 474 KB）          | P3TERX 模板遗留的第三方包源码与补丁，**全仓库 0 处引用**，2512 线用不到 |

> 一句话版：**只有 `general/` 和 `aarch64/scripts/` 里那两个本地脚本可以不传。**  
> 其余（`aarch64/Lede2512/`、`aarch64/scripts/` 的 5 个核心脚本、`aarch64/getImgs.sh`、  
> `aarch64/autoVersion.sh`、`scripts/`、`depends-ubuntu-2204`）缺一不可。
>
> 那两个本地脚本加起来才 2.7 KB，传上去也完全无害——只是云端永远用不到。  
> `general/` 占了仓库体积的大头，是最值得省掉的一项。

## 8.2 建仓库 + 传文件

1. 新账号 → 右上角 `+` → **New repository**。
2. 名称建议 `Actions-OpenWrt`，可见性选 **Public**  
   （Public 仓库的 Actions 分钟数免费且不限量；Private 每月只有 2000 分钟，编译很快就不够用）。
3. 传文件 —— **只用命令行，不要用网页上传**：

   ```bash
   cd <项目目录>
   git init
   git add -A
   git commit -m "init: Lede 25.12 云编译"
   git branch -M main
   git remote add origin https://github.com/<你的账号>/Actions-OpenWrt.git
   git push -u origin main
   ```

   > ⚠️ **为什么坚决不用网页 `Add file → Upload files`**：本项目实测踩过三个坑 ——  
   > ① **会漏文件**：一次上传漏了 7 个（`.gitattributes`、`.gitignore`、`README.md`、
   > `插件说明.md`、`2512SSHCONFIG.config`、`rebuild_plugins.sh`、`一键重建插件清单.bat`）；  
   > ② **绕过 `.gitattributes`**：把 Windows 的 CRLF 原样传上去，`插件字典.tsv` 就中过招；  
   > ③ **历史全是噪音**：每批文件一个 `Add files via upload` 提交，几十条压不下来。  
   > 另外**空仓库首页没有 `Add file` 按钮**（显示的是 Quick setup 引导页），
   > 入口是引导文字里的 `uploading an existing file` 链接，或直接访问 `/upload/main`。

   > **Windows 上 git 连不上 GitHub**（报 `CRYPT_E_REVOCATION_OFFLINE`）：
   > 执行 `git config --local http.sslBackend openssl` 换成 OpenSSL 后端即可，
   > Windows 自带的 schannel 后端拉不到证书吊销列表会直接失败。
4. 推送后到 **Settings → Actions → General**，这一页有两三个分组，按下表设即可：
   | 选项                                                         | 怎么设                                          | 说明                    |
   | ---------------------------------------------------------- | -------------------------------------------- | --------------------- |
   | **Actions permissions**                                    | 选 `Allow all actions and reusable workflows` | 公开仓库默认就是这个，一般不用动      |
   | **Workflow permissions**                                   | 选 `Read and write permissions`               | 建议开，但**不勾也能跑**。见下面的说明 |
   | `Require actions to be pinned to a full-length commit SHA` | **不要勾**                                      | 见下面的说明                |
   | `Allow GitHub Actions to create and approve pull requests` | **不要勾**                                      | 本项目不需要                |
   **为什么 `Workflow permissions` 不是必须的**：「重建插件清单」这个工作流自己就写了  
   `permissions: contents: write`，而工作流里显式声明的权限会**覆盖**这里的仓库默认值；  
   而且它的 checkout 用的是 `secrets.RELEASES_TOKEN || secrets.GITHUB_TOKEN`，  
   配了 PAT 就走 PAT，跟这个开关无关。开着只是为了以后新增工作流时省事。

   **为什么不要勾「Require actions to be pinned to a full-length commit SHA」**：  
   勾上之后，所有按版本号/分支引用的 action **会直接无法运行**，必须全部改成 40 位 commit SHA。  
   本项目 8 个 action、21 处引用全是 `@v4` / `@v1` / `@main` / `@master` 形式，勾了等于把整条流水线停掉。

   **为什么不要勾「Allow GitHub Actions to create and approve pull requests」**：  
   本项目所有工作流都是直接 `git push` 到 main（或发 Release），不创建 PR，勾上只会白白扩大权限面。

## 8.3 需要令牌吗？需要哪些？

需要 **1 个必加 + 2 个可选**，全部在  
**仓库 Settings → Secrets and variables → Actions → New repository secret** 里添加。

| Secret 名称            | 必需     | 用途                           |
| -------------------- | ------ | ---------------------------- |
| `RELEASES_TOKEN`     | **必需** | 发布 Releases、删除旧版本/旧工件、上传下载资源 |
| `TELEGRAM_BOT_TOKEN` | 可选     | 编译完成电报通知                     |
| `TELEGRAM_CHAT_ID`   | 可选     | 同上，两个一起才生效                   |

不配电报那一对也能跑：通知步骤加了 `continue-on-error`，失败了也不会把整个任务标红。

### 生成 `RELEASES_TOKEN`

1. 新账号右上角头像 → **Settings** → 左侧最下面 **Developer settings**  
   → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**。
2. Note 随便写（例如 `Actions-OpenWrt`），Expiration 建议选 90 天，或按自己需要选 No expiration。
3. 勾选权限（**只勾这两项，别的都不要勾**）：
   - `repo`（完整仓库权限，父项一勾，下面 5 个子项会自动跟着勾）— **必勾**；
   - `workflow`（独立一项，**不包含在 `repo` 里**，要单独勾）— 建议也勾上。

> **为什么不是只勾 `public_repo`？**  
> `public_repo` 只管公开仓库，功能上对本项目大多数操作够用，但有一处不稳：  
> 工作流里的「删除旧的工作流程运行」（`Mattraks/delete-workflow-runs`）和「删除旧版本」  
> 属于仓库管理类接口，官方只承诺 `repo` 作用域；一旦哪天仓库改成 Private（或你建个私有测试库），  
> `public_repo` 会立刻全部失效，得重做令牌、重配 Secret。  
> 这是你自己账号的专用令牌，不是授权给第三方应用，勾完整 `repo` 的风险面可控，省事得多。  
> **不需要勾**：`admin:org`、`delete_repo`、`gist`、`user`、`write:packages` 等。

1. Generate → **立刻复制** 生成的 `ghp_...` 字符串（页面刷新后就看不到了）。
2. 回到仓库 → Settings → Secrets and variables → Actions → **New repository secret**：
   - Name 填 `RELEASES_TOKEN`（大小写要和工作流里写的完全一致）；
   - Secret 粘贴刚才那串值 → Add secret。

> 令牌必须是**这个仓库所属账号**（或对该仓库有写权限的账号）生成的，用别的账号的令牌发布会 403。

## 8.4 第一次跑的顺序

**动手前先确认两件事**：① 8.2 第 4 步的 Actions 设置已点保存；② 8.3 的 `RELEASES_TOKEN` 已加。
缺令牌的话，发布 Release 那一步会 403。

1. **建 `Files` 标签的 Release**：Releases → Draft a new release → Tag 填 `Files` →  
   把 F 大（unifreq）的内核文件包（`boot-*.tar.gz`、`*_kernel.tar.gz` 等）上传 → Publish。  
   （打包固件时内核就是从这里取的。）
2. **Actions →「编译Lede2512_FOL」→ Run workflow**：先选 `n1` 试一次，成功后再选 `all`。  
   跑完在 Releases 里会看到 `Build2512-N1` / `Build2512-X96`。
3. **Actions →「F打包_Lede2512_N1」→ Run workflow**；再跑 **「F打包_Lede2512_X96」**。
4. 成品在 Releases 里，名字是 `Lede2512-N1-2026xxxx-xxxx` / `Lede2512-X96-2026xxxx-xxxx`。
5. 以后只改插件：编辑 `aarch64/Lede2512/plugins.cfg` → Commit → 重跑第 2 步。

> 首次编译建议只选一个设备，跑通再选 `all`。  
> `make defconfig` 阶段日志里会打印「已被依赖强制保留」的清单，可以据此确认没有被误禁。  
> 整轮编译约 4~5 小时（8 核 runner、`-j8`），中途没有提示是正常的。

---

小白搬运

1: <https://github.com/HoldOnBro/Actions-OpenWrt>

2: <https://github.com/281677160/build-actions>

3：<https://github.com/ophub>

云编译说明 <https://github.com/danshui-git/shuoming>

F大  <https://github.com/unifreq/openwrt_packit>

---
