#!/bin/bash
# 按工作流输入生成 rootfs overlay (运行于 Actions runner)
# 输出目录: $GITHUB_WORKSPACE/build-files
set -e
OUT="$GITHUB_WORKSPACE/build-files"
rm -rf "$OUT"; mkdir -p "$OUT/etc/uci-defaults"

LAN_IP=${LAN_IP:-192.168.52.1}
NETMASK=${NETMASK:-255.255.255.0}
HOSTNAME=${HOSTNAME:-ImmortalWrt}
TZ_NAME=${TZ_NAME:-Asia/Shanghai}
LUCI_LANG=${LUCI_LANG:-zh_cn}
PPPOE_USER=${PPPOE_USER:-}
PPPOE_PASS=${PPPOE_PASS:-}
WAN_PORT=${WAN_PORT:-eth0}
WAN_AUTO=${WAN_AUTO:-true}
USB_AUTOMOUNT=${USB_AUTOMOUNT:-true}

# ---- 89-prewan: WAN 策略(先于 90-netauto 执行) ----
{
  echo '#!/bin/sh'
  echo '# 由 builder 生成: WAN 模式'
  if [ "$WAN_AUTO" = "true" ] && [ -z "$PPPOE_USER" ]; then
    echo '# 使用首启 DHCP 自动识别(默认)'
    echo 'exit 0'
  else
    echo 'uci set netauto.main.enabled=0'
    if [ -n "$PPPOE_USER" ]; then
      echo 'uci -q delete network.wan 2>/dev/null || true'
      echo 'uci set network.wan=interface'
      echo 'uci set network.wan.proto=pppoe'
      echo "uci set network.wan.device='$WAN_PORT'"
      echo "uci set network.wan.username='$PPPOE_USER'"
      echo "uci set network.wan.password='$PPPOE_PASS'"
      echo "uci set network.wan6.device='$WAN_PORT'"
    fi
    echo 'uci commit netauto'
    echo 'uci commit network'
    echo 'exit 0'
  fi
} > "$OUT/etc/uci-defaults/89-prewan"

# ---- 90-netauto: WAN 自动识别(静态基线) ----
mkdir -p "$OUT/etc/config"
cat > "$OUT/etc/config/netauto" <<'EOF'
config netauto 'main'
	option enabled '1'
EOF
cat > "$OUT/etc/uci-defaults/90-netauto" <<'EOF'
#!/bin/sh
# WAN 口首启自动识别: PCI 有线口优先 DHCP 探测
. /lib/functions.sh
enabled=$(uci -q get netauto.main.enabled)
[ "${enabled:-1}" = "1" ] || exit 0
[ -z "$(uci -q get netauto.main.done)" ] || exit 0
pci_ports=""; usb_ports=""
for p in $(ls /sys/class/net 2>/dev/null | grep -E '^eth[0-9]+$' | sort -V); do
    dev=$(readlink -f /sys/class/net/$p/device 2>/dev/null)
    case "$dev" in *usb*|*platform*) usb_ports="$usb_ports $p" ;; *) pci_ports="$pci_ports $p" ;; esac
done
probe() { ip link set dev "$1" up 2>/dev/null || return 1
  c=0; while [ $c -lt 20 ]; do [ "$(cat /sys/class/net/$1/carrier 2>/dev/null)" = "1" ] && break; c=$((c+1)); sleep 0.5; done
  udhcpc -i "$1" -n -q -t 2 -T 2 -f >/dev/null 2>&1
  ip addr flush dev "$1" 2>/dev/null; ip link set dev "$1" down 2>/dev/null; }
wan_port=""
for p in $pci_ports $usb_ports; do probe "$p" && { wan_port="$p"; break; }; done
if [ -n "$wan_port" ]; then
    dev=$(uci -q get network.lan.device)
    if [ -n "$dev" ] && [ "$dev" = "br-lan" ]; then
        for sec in $(uci -q show network | grep -oE "network\.@device\[[0-9]+\]" | sort -u); do
            [ "$(uci -q get ${sec}.name)" = "br-lan" ] && uci -q del_list ${sec}.ports="$wan_port" 2>/dev/null || true
        done
    fi
    uci -q delete network.wan 2>/dev/null || true
    uci set network.wan=interface; uci set network.wan.proto=dhcp
    uci set network.wan.device="$wan_port"; uci set network.wan.auto=1
    if [ -n "$(uci -q get network.wan6.device)" ]; then uci set network.wan6.device="$wan_port"; fi
fi
uci set netauto.main.done=1; uci commit netauto; uci commit network
exit 0
EOF
chmod +x "$OUT/etc/uci-defaults/"*.sh "$OUT/etc/uci-defaults/89-prewan" "$OUT/etc/uci-defaults/90-netauto" 2>/dev/null || true
chmod +x "$OUT/etc/uci-defaults/89-prewan" "$OUT/etc/uci-defaults/90-netauto"

# ---- 91-custom: IP/主机名/时区/语言 ----
{
  echo '#!/bin/sh'
  echo '# 由 builder 生成: 基础定制'
  echo "uci set network.lan.ipaddr='$LAN_IP'"
  echo "uci set network.lan.netmask='$NETMASK'"
  echo "uci set network.lan.proto='static'"
  echo 'uci commit network'
  echo "uci set system.@system[0].hostname='$HOSTNAME'"
  echo "uci set system.@system[0].timezone='CST-8'"
  echo "uci set system.@system[0].zonename='$TZ_NAME'"
  echo 'uci commit system'
  echo "uci set luci.main.lang='$LUCI_LANG'"
  echo 'uci commit luci'
  echo 'exit 0'
} > "$OUT/etc/uci-defaults/91-custom"
chmod +x "$OUT/etc/uci-defaults/91-custom"

# ---- USB 存储自动挂载热插拔脚本 ----
if [ "$USB_AUTOMOUNT" = "true" ]; then
  mkdir -p "$OUT/etc/hotplug.d/block"
  cat > "$OUT/etc/hotplug.d/block/10-automount" <<'EOF'
#!/bin/sh
[ "$ACTION" = "add" ] || [ "$ACTION" = "remove" ] || exit 0
[ -n "$DEVICENAME" ] || exit 0
case "$DEVICENAME" in
    sd[a-z][0-9]*|nvme[0-9]n[0-9]p[0-9]*|vd[a-z][0-9]*|hd[a-z][0-9]*) ;;
    *) exit 0 ;;
esac
DEV="/dev/$DEVICENAME"; MNT="/mnt/$DEVICENAME"
if [ "$ACTION" = "remove" ]; then
    mountpoint -q "$MNT" 2>/dev/null && umount "$MNT"; exit 0
fi
i=0; while [ $i -lt 6 ]; do [ -b "$DEV" ] && break; i=$((i+1)); sleep 0.5; done
[ -b "$DEV" ] || exit 0
TYPE=$(blkid -s TYPE -o value "$DEV" 2>/dev/null | head -1)
[ -n "$TYPE" ] || exit 0
mountpoint -q "$MNT" 2>/dev/null && exit 0
mkdir -p "$MNT"
case "$TYPE" in
    ntfs|ntfs3) mount -t ntfs3 "$DEV" "$MNT" 2>/dev/null || mount -t ntfs-3g "$DEV" "$MNT" 2>/dev/null ;;
    exfat)      mount -t exfat  "$DEV" "$MNT" 2>/dev/null ;;
    *)          mount -t "$TYPE" "$DEV" "$MNT" 2>/dev/null ;;
esac
[ $? -eq 0 ] || rmdir "$MNT" 2>/dev/null
exit 0
EOF
  chmod +x "$OUT/etc/hotplug.d/block/10-automount"
fi

echo "overlay 生成完毕:"
find "$OUT" -type f | head -20
