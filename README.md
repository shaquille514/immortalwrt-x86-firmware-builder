# ImmortalWrt x86_64 图形化固件构建器

网页勾选配置 → GitHub Actions 云端自动编译 → 下载固件。基于官方 **ImmortalWrt 24.10.6 ImageBuilder**，约 15~25 分钟出包。

## 使用方法

1. 打开本仓库 **Actions** 页面
2. 左侧选择 **"图形化构建固件"** 工作流 → 右侧 **Run workflow**
3. 按需勾选/填写（所有选项见下）→ 点绿色按钮启动
4. 构建完成后进入本次运行页面底部 **Artifacts** → 下载 `immortalwrt-24.10.6-custom`

## 可选项一览

| 分组 | 选项 |
|---|---|
| 常用应用(勾选式) | OpenClash(预置 Meta 内核) / AdGuard Home / Samba 共享 / Tailscale / Netdata 监控 / HomeBox 测速 / 磁盘管理 / S.M.A.R.T / 网页终端 / UPnP / Argon 主题 / USB 自动挂载 |
| 网络定制 | **WAN 自动识别开关** / PPPoE 宽带账号密码(留空=DHCP 自动识别) / WAN 物理口(PPPoE 时) / LAN IP / 子网掩码 / 主机名 |
| 系统定制 | 时区(上海/香港/台北/东京/新加坡/UTC) / LuCI 语言(中文/English)（产物同时含 squashfs 与 ext4 两套, 推荐刷 squashfs）|

## 内置软件源说明

- **官方源**：ImmortalWrt 24.10.6 packages/luci/kmods（Samba、Tailscale 守护进程、Netdata、AdGuardHome 守护进程等随版本自动更新）
- **自定义源** `packages/local/`：本仓库预编译 ipk（OpenClash 0.47.x、luci-app-adguardhome、HomeBox 0.1.3、Diskman 0.2.13、SmartInfo、Tailscale-community luci 等，源自本工程 x86_64 全量源码构建）
  - 如需更新自定义包：将新 ipk 放入 `packages/local/` 后执行 `python3 scripts/gen-feed-index.py packages/local` 重新生成索引并提交

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

- 修改 `scripts/gen-overlay.sh` 可加配置项；`scripts/compose-packages.sh` 是包映射表
- 本仓库固件线 = ImmortalWrt 24.10.6(内核 6.6)；更新版本需同步换 ImageBuilder URL 与自定义源
