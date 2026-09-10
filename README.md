# ImmortalWrt x86_64 图形化固件构建器

网页勾选配置 → GitHub Actions 云端自动编译 → 下载固件。基于官方 **ImmortalWrt ImageBuilder**，约 15~25 分钟出包。构建会校验 ImageBuilder、自带预编译包、最终包清单和产物哈希；公开仓库还会生成 GitHub 构建来源证明。

支持固件线：**24.10.6**（内核 6.6，opkg 包格式）与 **25.12.1**（内核 6.12，apk 包格式），Run workflow 时下拉选择。

另提供 **功能包 .run 一键安装包**（见下方），给不想刷机、已在跑 ImmortalWrt 的用户补装 PassWall2/Momo 等功能。

## 使用方法

### 1) 编译固件

1. 打开本仓库 **Actions** 页面
2. 左侧选择 **"图形化构建固件"** 工作流 → 右侧 **Run workflow**
3. 选择 **ImmortalWrt 版本**（24.10.6 / 25.12.1）→ 按需勾选/填写 → 点绿色按钮启动
   - 勾选 **"发布为 GitHub Release"** 可把固件发布到长期 Release（不勾则只存 Artifacts 14 天）
   - PPPoE 建议首次开机后配置。确需预置时，只能在**私有仓库**的 `Settings → Secrets and variables → Actions` 中配置 `PPPOE_USERNAME` 和 `PPPOE_PASSWORD`，再勾选 PPPoE；含凭据的构建禁止发布 Release
4. 构建完成后：本次运行底部 **Artifacts** 下载 `immortalwrt-<版本>-custom`；或到 **Releases** 页下载同名 Release（tag `v<版本>-<日期>-<构建号>`，含 sha256sums.txt）

### 2) 生成 run 一键安装包（免刷机补装功能）

1. **Actions** 页 → **"生成 run 一键安装包"** → Run workflow
2. 可选：填 `apps`（如 `passwall2,momo`）只打指定包；勾"发布为 GitHub Release"生成长期 Release
3. 到 **Releases** 页下载 `runpacks-x86_64-<日期>-<构建号>` 里的 `.run` 文件

## 可选项一览

| 分组 | 选项 |
|---|---|
| 科学上网(勾选式) | **OpenClash**(LuCI 面板，Mihomo 内核需在面板中另行下载) / **PassWall2**(24.10 含 sing-box；25.12 再含 xray-core) / **Momo**(sing-box 独立透明代理图形面板) |
| 常用应用(勾选式) | AdGuard Home / Samba 共享 / Tailscale(含 community luci) / Netdata 监控 / HomeBox 测速 / 磁盘管理(含 exfat 工具) / S.M.A.R.T / 网页终端 / UPnP / Argon 主题 / USB 自动挂载 |
| 网络定制 | **WAN 自动识别开关** / PPPoE 开关与 WAN 物理口 / LAN IP / 子网掩码 / 主机名 |
| 系统定制 | 时区(上海/香港/台北/东京/新加坡/UTC) / LuCI 语言(中文/English)（产物同时含 squashfs 与 ext4 两套, 推荐刷 squashfs）|

## 功能包 .run 一键安装包

> 适用：**已在运行 ImmortalWrt 24.10(opkg) x86_64**、不想刷机重装、想补装 PassWall2/Momo 等功能的用户
> 原理：makeself 自解压包（内含仓库中的预编译 ipk + 安装脚本）。打包过程不临时抓取其他第三方二进制，但这些 ipk 本身仍是需要信任和审计的第三方预编译快照。

| 包 | 内容 |
|---|---|
| `passwall2.run` | PassWall2 26.9.x 多协议分流（含中文语言包） |
| `momo.run` | Momo(sing-box 透明代理) + luci 面板 |
| `openclash.run` | OpenClash 科学上网 |
| `homebox.run` | HomeBox 内网测速 |
| `diskman.run` | 磁盘管理(分区/格式化/挂载) |
| `smartinfo.run` | S.M.A.R.T 硬盘健康监控 |
| `adguardhome.run` | AdGuard Home(DNS 过滤) luci 面板 |
| `tailscale.run` | Tailscale 组网(community luci) |

**安装方法**（从某个明确的 `runpacks-x86_64-*` Release 下载 `.run` 与 `sha256sums.txt`，不要使用混合固件 Release 的 `latest/download`）：
```bash
# 两个文件放在同一目录后，先只校验目标文件
grep ' passwall2.run$' sha256sums.txt | sha256sum -c -
sh passwall2.run --check          # 再校验自解压载荷
sh passwall2.run                  # 安装（自动 opkg update + 官方源补齐依赖）
# 或只解压不安装:
sh passwall2.run --target /tmp/pw --noexec
```

> 注意：安装器默认只接受 **ImmortalWrt 24.10.x + opkg + x86_64**（不支持 25.12/apk 与其他架构）；安装需联网（依赖从官方源拉取）。确认兼容后可用 `ALLOW_UNSUPPORTED=1` 绕过系统版本检查，只有确需覆盖已装包时才使用 `FORCE_REINSTALL=1`。

## 内置软件源说明

- **官方源**：随所选版本自动匹配 ImmortalWrt packages/luci/kmods（Samba、Tailscale、Netdata、AdGuardHome、sing-box 等；xray-core 仅加入 25.12 构建）
- **自定义源**：
  - `packages/local/`（24.10.6，opkg/ipk）：预编译 ipk + Packages 索引（OpenClash 0.47.x、PassWall2 26.9.x、Momo 1.2.1、luci-app-adguardhome、HomeBox 0.1.3、Diskman、SmartInfo、Tailscale-community luci 等）
  - `packages/apk25/`（25.12.1，apk）：预编译 apk（同批包，版本随 25.12 构建链更新）
  - 如需更新自定义包：放入对应目录，执行 `python3 scripts/gen-feed-index.py packages/local` 重新生成 24.10 索引，再从仓库根目录重建 `packages/SHA256SUMS`；CI 会拒绝索引或哈希未同步的提交
  - **run 包数据源即 `packages/local/`**——更新 ipk 后重跑"生成 run 一键安装包"即可出新版 .run

预编译包的哈希只能证明文件与仓库记录一致，不能替代上游来源证明或源码审计。维护要求见 [`packages/README.md`](packages/README.md)。

## 默认行为(与源码版一致)

- 首启 **WAN 自动识别**：DHCP 探测每个有线口(PCI 优先)，第一个真正获得租约的口设为 WAN；未探测到时保留脚本，下次启动重试
- 填了 PPPoE 账号时自动关闭自动识别并按指定口拨号
- USB 移动盘即插即用自动挂载 `/mnt/sdX1`（ntfs3/exfat/ext4）
- LAN 默认 `192.168.52.1`，LuCI 中文

## ⚠️ 隐私与安全提示

- **PPPoE 账号密码会明文烧入固件**（`/etc/config/network`），拿到固件即可读取。项目只允许私有仓库通过 Actions Secrets 预置，并禁止这类构建发布 Release；仓库协作者仍可能下载 Artifact，因此首启后手工配置最安全。
- 下载后应使用随产物提供的 `sha256sums.txt` 校验。GitHub 构建来源证明能关联产物与工作流，但不代表仓库内第三方预编译包已经源码审计。
- 刷机后首次登录没有密码，请立即设置强密码；涉及外网暴露前还应检查防火墙和已启用服务。

## 固件文件怎么选（小白版）

下载固件时会看到一堆文件名，其实都是由几个关键词组合的，拆开看就懂了：

```
immortalwrt-24.10.6-x86-64-generic-<文件系统>-<结构>[-efi].<格式>.gz
```

### 四个关键区别

**① 文件系统：squashfs vs ext4**（影响你能不能"恢复出厂"）
| | squashfs | ext4 |
|---|---|---|
| 特点 | 底层只读压缩 + 上层可读写，稳 | 整盘可读写，扩容方便 |
| 恢复出厂 | ✅ 支持一键恢复（firstboot） | ❌ 崩了不能一键还原 |
| 适合谁 | **大多数人选这个**，随便折腾不怕坏 | 要装很多大插件/经常扩分区的人 |

**② 启动方式：带 efi vs 不带 efi**
- `-efi`：UEFI 引导（新电脑/虚拟机默认）
- 不带：传统 BIOS（Legacy）引导
- **近几年的电脑/虚拟机直接选带 efi 的**；很老的主机才需要不带 efi 的

**③ 结构：combined vs rootfs**
- `combined`：**完整磁盘镜像**（含引导区），能直接刷盘启动 ← **普通用户只认这个**
- `rootfs`：只有系统文件没有引导区，给 Docker/LXC 容器用的，**不用管**

**④ 格式后缀**（对应不同刷写/虚拟化环境）
| 后缀 | 用途 |
|---|---|
| `.img.gz` | **物理机刷盘**（解压后用 Rufus/balenaEtcher 写 SSD/U 盘）|
| `.qcow2.gz` | PVE / KVM 虚拟机直接用 |
| `.vmdk.gz` | VMware（ESXi / Workstation）|
| `.vhdx.gz` | Hyper-V |
| `.vdi.gz` | VirtualBox |
| `.tar.gz` / `-rootfs` | 容器用，不用管 |

### 🎯 直接抄作业（选型速查）
| 你的情况 | 下载这个 |
|---|---|
| 物理小主机/软路由（UEFI 启动）| `squashfs-combined-efi.img.gz` ⭐ |
| 物理机（老 Legacy BIOS）| `squashfs-combined.img.gz` |
| PVE 虚拟机 | `.qcow2.gz`（或解压 `.img.gz` 导入）|
| VMware / Hyper-V / VirtualBox | 对应 `.vmdk.gz` / `.vhdx.gz` / `.vdi.gz` |
| 什么都看不懂 | **`squashfs-combined-efi.img.gz`** 准没错 |

## 刷机

1. 解压 `.img.gz` → 用 Rufus/balenaEtcher 写入 SSD（或 dd）
2. 浏览器打开 `http://<你填的LAN_IP>`（默认 192.168.52.1）
3. 首次登录无密码 → 立即在 系统→管理权 设置密码

## 本地复现/贡献

- 修改 `scripts/gen-overlay.sh` 可加配置项；`scripts/compose-packages.sh` 是包映射表（注意 exfat 工具在 24.10/25.12 均为 `exfat-mkfs/exfat-fsck`，勿用 exfatprogs 包名）
- `scripts/make-runpacks.sh` 是 .run 打包脚本，`APPS` 数组是应用清单
- 自定义源 ipk/apk 打包需对应版本 SDK/源码构建（见 packages/ 下两个目录）
- 提交前运行 `sha256sum -c packages/SHA256SUMS` 和 `bash tests/test-scripts.sh`；推送与 PR 也会自动执行相同自检

## Fork 使用(给想自己出固件的人)

1. **Fork** 本仓库到你的账号
2. **启用 Actions**: fork 后进入 Settings → Actions → General → Actions permissions → 选 Allow
   (GitHub 对 fork 默认禁用 Actions, 必须手动开)
3. **运行**: Actions 页 → 选工作流 → Run workflow
   - "图形化构建固件": 选版本/勾功能; 勾"发布为 GitHub Release"生成长期 Release(tag v<版本>-<日期>-<构建号>)
   - "生成 run 一键安装包": 打 .run 免刷机安装包(Release tag runpacks-x86_64-<日期>-<构建号>)
4. 产物在本次运行 Artifacts(14 天) 或 Releases(长期)

注意事项:
- 仓库自包含: 自定义功能包(ipk/apk)已随仓库提交, 构建时从官方源拉 ImageBuilder + 基础包, 不依赖上游仓库
- 自定义包为预编译快照(OpenClash/PassWall2/Momo 等固定版本), 需更新时替换 packages/local(24.10) 与 packages/apk25(25.12) 下的包并重新生成索引(见"内置软件源说明"), 然后重跑两个 workflow 即出新版
- 公共仓库构建有 Actions 免费额度限制；PPPoE 预置只允许私有仓库通过 `PPPOE_USERNAME` / `PPPOE_PASSWORD` Secrets 使用
