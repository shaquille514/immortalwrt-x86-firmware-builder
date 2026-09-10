#!/bin/bash
# 按工作流输入生成 rootfs overlay (运行于 Actions runner)
# 输出目录: $GITHUB_WORKSPACE/build-files
set -e
[ -n "${GITHUB_WORKSPACE:-}" ] && [ "$GITHUB_WORKSPACE" != "/" ] || {
  echo "错误: GITHUB_WORKSPACE 未设置或不安全" >&2
  exit 1
}
OUT="${GITHUB_WORKSPACE%/}/build-files"
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

die() {
  echo "错误: $*" >&2
  exit 1
}

validate_no_control_chars() {
  local name=$1 value=$2
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] || \
    die "$name 不能包含换行或制表符"
}

validate_ipv4() {
  local name=$1 value=$2 part
  local -a parts
  IFS=. read -r -a parts <<< "$value"
  [ "${#parts[@]}" -eq 4 ] || die "$name 不是合法 IPv4 地址: $value"
  for part in "${parts[@]}"; do
    [[ "$part" =~ ^[0-9]{1,3}$ ]] && (( 10#$part <= 255 )) || \
      die "$name 不是合法 IPv4 地址: $value"
  done
}

validate_netmask() {
  local value=$1 part seen_zero=0
  local -a parts
  validate_ipv4 "NETMASK" "$value"
  IFS=. read -r -a parts <<< "$value"
  for part in "${parts[@]}"; do
    case "$part" in
      255) [ "$seen_zero" -eq 0 ] || die "NETMASK 不是连续掩码: $value" ;;
      254|252|248|240|224|192|128) [ "$seen_zero" -eq 0 ] || die "NETMASK 不是连续掩码: $value"; seen_zero=1 ;;
      0) seen_zero=1 ;;
      *) die "NETMASK 不是连续掩码: $value" ;;
    esac
  done
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
}

emit_uci_set() {
  printf 'uci set %s=%s\n' "$1" "$(shell_quote "$2")"
}

for name in LAN_IP NETMASK HOSTNAME TZ_NAME LUCI_LANG PPPOE_USER PPPOE_PASS WAN_PORT; do
  validate_no_control_chars "$name" "${!name}"
done
validate_ipv4 "LAN_IP" "$LAN_IP"
validate_netmask "$NETMASK"
[[ "$HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || \
  die "HOSTNAME 只能包含字母、数字和中划线，且长度为 1-63"
[[ "$WAN_PORT" =~ ^[A-Za-z0-9_.:@-]+$ && ${#WAN_PORT} -le 15 ]] || \
  die "WAN_PORT 不是合法接口名: $WAN_PORT"
case "$WAN_AUTO" in true|false) ;; *) die "WAN_AUTO 只能是 true 或 false" ;; esac
case "$USB_AUTOMOUNT" in true|false) ;; *) die "USB_AUTOMOUNT 只能是 true 或 false" ;; esac
case "$LUCI_LANG" in zh_cn|en) ;; *) die "不支持的 LUCI_LANG: $LUCI_LANG" ;; esac
case "$TZ_NAME" in
  Asia/Shanghai)  TZ_POSIX='CST-8' ;;
  Asia/Hong_Kong) TZ_POSIX='HKT-8' ;;
  Asia/Taipei)    TZ_POSIX='CST-8' ;;
  Asia/Tokyo)     TZ_POSIX='JST-9' ;;
  Asia/Singapore) TZ_POSIX='<+08>-8' ;;
  UTC)            TZ_POSIX='UTC0' ;;
  *) die "不支持的 TZ_NAME: $TZ_NAME" ;;
esac

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
      emit_uci_set network.wan.device "$WAN_PORT"
      emit_uci_set network.wan.username "$PPPOE_USER"
      emit_uci_set network.wan.password "$PPPOE_PASS"
      emit_uci_set network.wan6.device "$WAN_PORT"
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
  # 使用空脚本只探测租约，避免把临时地址、路由和 DNS 写进运行系统。
  udhcpc -i "$1" -n -q -t 2 -T 2 -f -s /bin/true >/dev/null 2>&1
  rc=$?
  ip addr flush dev "$1" 2>/dev/null
  ip link set dev "$1" down 2>/dev/null
  return $rc
}
wan_port=""
for p in $pci_ports $usb_ports; do probe "$p" && { wan_port="$p"; break; }; done
[ -n "$wan_port" ] || {
    logger -t netauto "未发现可获取 DHCP 的有线口，将在下次启动时重试"
    exit 1
}
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
uci set netauto.main.done=1; uci commit netauto; uci commit network
exit 0
EOF
chmod +x "$OUT/etc/uci-defaults/"*.sh "$OUT/etc/uci-defaults/89-prewan" "$OUT/etc/uci-defaults/90-netauto" 2>/dev/null || true
chmod +x "$OUT/etc/uci-defaults/89-prewan" "$OUT/etc/uci-defaults/90-netauto"

# ---- 91-custom: IP/主机名/时区/语言 ----
{
  echo '#!/bin/sh'
  echo '# 由 builder 生成: 基础定制'
  emit_uci_set network.lan.ipaddr "$LAN_IP"
  emit_uci_set network.lan.netmask "$NETMASK"
  echo "uci set network.lan.proto='static'"
  echo 'uci commit network'
  emit_uci_set 'system.@system[0].hostname' "$HOSTNAME"
  emit_uci_set 'system.@system[0].timezone' "$TZ_POSIX"
  emit_uci_set 'system.@system[0].zonename' "$TZ_NAME"
  echo 'uci commit system'
  emit_uci_set luci.main.lang "$LUCI_LANG"
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
