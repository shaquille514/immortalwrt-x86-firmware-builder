# ImmortalWrt x86_64 图形化固件构建器

网页勾选配置 → GitHub Actions 云端自动编译 → 下载固件。基于官方 **ImmortalWrt ImageBuilder**，约 15~25 分钟出包。

支持固件线：**24.10.6**（内核 6.6，opkg 包格式）与 **25.12.1**（内核 6.12，apk 包格式），Run workflow 时下拉选择。

## 使用方法

1. 打开本仓库 **Actions** 页面
2. 左侧选择 **"图形化构建固件"** 工作流 → 右侧 **Run workflow**
3. 选择 **ImmortalWrt 版本**（24.10.6 / 25.12.1）→ 按需勾选/填写 → 点绿色按钮启动
4. 构建完成后进入本次运行页面底部 **Artifacts** → 下载 `immortalwrt-<版本>-custom`

## 可选项一览

| 分组 | 选项 |
|---|---|
| 科学上网(勾选式) | **OpenClash**(预置 Meta 内核) / **PassWall2**(多协议分流, 预置 sing-box+xray 核心) / **Momo**(sing-box 独立透明代理图形面板) |
| 常用应用(勾选式) | AdGuard Home / Samba 共享 / Tailscale(含 community luci) / Netdata 监控 / HomeBox 测速 / 磁盘管理(含 exfat 工具) / S.M.A.R.T / 网页终端 / UPnP / Argon 主题 / USB 自动挂载 |
| 网络定制 | **WAN 自动识别开关** / PPPoE 宽带账号密码(留空=DHCP 自动识别) / WAN 物理口(PPPoE 时) / LAN IP / 子网掩码 / 主机名 |
| 系统定制 | 时区(上海/香港/台北/东京/新加坡/UTC) / LuCI 语言(中文/English)（产物同时含 squashfs 与 ext4 两套, 推荐刷 squashfs）|

## 内置软件源说明

- **官方源**：随所选版本自动匹配 ImmortalWrt packages/luci/kmods（Samba、Tailscale、Netdata、AdGuardHome、sing-box/xray-core 等守护进程）
- **自定义源**：
  - `packages/local/`（24.10.6，opkg/ipk）：预编译 ipk + Packages 索引（OpenClash 0.47.x、PassWall2 26.9.x、Momo 1.2.1、luci-app-adguardhome、HomeBox 0.1.3、Diskman、SmartInfo、Tailscale-community luci 等）
  - `packages/apk25/`（25.12.1，apk）：预编译 apk（同批包，版本随 25.12 构建链更新）
  - 如需更新自定义包：放入对应目录后 24.10 侧执行 `python3 scripts/gen-feed-index.py packages/local` 重新生成索引并提交（25.12 侧 apk 由构建时并入 IB 本地包目录）

## 默认行为(与源码版一致)

- 首启 **WAN 自动识别**：DHCP 探测每个有线口(PCI 优先)，第一个获得 DHCP 的口设为 WAN，其余桥接进 LAN
- 填了 PPPoE 账号时自动关闭自动识别并按指定口拨号
- USB 移动盘即插即用自动挂载 `/mnt/sdX1`（ntfs3/exfat/ext4）
- LAN 默认 `192.168.52.1`，LuCI 中文

## ⚠️ 隐私提示

- **PPPoE 账号密码会明文烧入固件**（/etc/config/network），拿到固件文件即可读取。仅在你接受此风险时填写；否则留空，首次开机后在 LuCI 手填（`接口 → WAN → 协议: PPPoE`）。
- 构建产物为公开仓库可见（Actions 日志不含你的密码输入，但固件文件本身含之）。

## 刷机

1. 解压 `.img.gz` → 用 Rufus/balenaEtcher 写入 SSD（或 dd）
2. 浏览器打开 `http://<你填的LAN_IP>`（默认 192.168.52.1）
3. 首次登录无密码 → 立即在 系统→管理权 设置密码

## 本地复现/贡献

- 修改 `scripts/gen-overlay.sh` 可加配置项；`scripts/compose-packages.sh` 是包映射表（注意 exfat 工具在 24.10/25.12 均为 `exfat-mkfs/exfat-fsck`，勿用 exfatprogs 包名）
- 自定义源 ipk/apk 打包需对应版本 SDK/源码构建（见 packages/ 下两个目录）
