#!/bin/bash
# 依据工作流勾选输入组装 PACKAGES 清单 (运行于 Actions runner)
set -e
P=""

add() { for p in "$@"; do P="$P $p"; done; }

# ---- 用户勾选的应用(官方源 + 本仓库 packages/local 自定义源) ----
[ "${B_OPENCLASH:-false}" = "true" ] && add luci-app-openclash
if [ "${B_ADGUARD:-false}" = "true" ]; then
  add adguardhome luci-app-adguardhome
fi
[ "${B_SAMBA:-false}" = "true" ]   && add luci-app-samba4
if [ "${B_TAILSCALE:-false}" = "true" ]; then
  add tailscale luci-app-tailscale-community
  [ "${LUCI_LANG:-zh_cn}" = "zh_cn" ] && add luci-i18n-tailscale-community-zh-cn
fi
if [ "${B_NETDATA:-false}" = "true" ]; then
  add netdata luci-app-netdata
fi
if [ "${B_HOMEBOX:-false}" = "true" ]; then
  add homebox luci-app-homebox
fi
[ "${B_DISKMAN:-false}" = "true" ]    && add luci-app-diskman
if [ "${B_SMARTINFO:-false}" = "true" ]; then
  add smartmontools luci-app-smartinfo
fi
[ "${B_TTYD:-false}" = "true" ]       && add luci-app-ttyd
[ "${B_UPNP:-false}" = "true" ]       && add luci-app-upnp

# ---- 磁盘/USB 工具 ----
if [ "${B_USB_AUTOMOUNT:-false}" = "true" ]; then
  add block-mount fdisk e2fsprogs dosfstools exfatprogs kmod-fs-exfat kmod-fs-ntfs3
fi

# ---- 主题与语言 ----
[ "${B_ARGON:-false}" = "true" ] && add luci-theme-argon
if [ "${LUCI_LANG:-zh_cn}" = "zh_cn" ]; then
  add luci-i18n-base-zh-cn
  [ "${B_SAMBA:-false}" = "true" ] && add luci-i18n-samba4-zh-cn
  [ "${B_TTYD:-false}" = "true" ]  && add luci-i18n-ttyd-zh-cn
fi

echo "$P" > /tmp/pkgs.raw
# 去空白并写入仓库根
tr -s ' ' < /tmp/pkgs.raw | sed 's/^ //;s/ $//' > "$GITHUB_WORKSPACE/pkg.list"
echo "pkg.list: $(cat "$GITHUB_WORKSPACE/pkg.list")"
