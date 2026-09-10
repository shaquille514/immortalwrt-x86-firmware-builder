#!/bin/bash
# make-runpacks.sh <ipk源目录> <输出目录> <makeself.sh路径> [apps逗号列表]
# 用仓库预编译 ipk 打 x86_64 .run 自解压安装包 (opkg / ImmortalWrt 24.10)
set -e

SRC=$1
OUT=$2
MAKESELF=$3
APPS_FILTER=$4
[ -n "$SRC" ] && [ -n "$OUT" ] && [ -n "$MAKESELF" ] || {
  echo "用法: $0 <ipk目录> <输出目录> <makeself.sh> [apps]"
  exit 1
}
[ -d "$SRC" ] || { echo "IPK 目录不存在: $SRC" >&2; exit 1; }
[ -f "$MAKESELF" ] || { echo "makeself 脚本不存在: $MAKESELF" >&2; exit 1; }
[ "$OUT" != "/" ] || { echo "拒绝使用根目录作为输出目录" >&2; exit 1; }
mkdir -p "$OUT"

# 每组: 名称|说明|包文件通配
APPS=(
  "passwall2|PassWall2 多协议分流(科学上网)|luci-app-passwall2_*.ipk luci-i18n-passwall2-zh-cn_*.ipk"
  "momo|Momo sing-box 透明代理图形面板|momo_*.ipk luci-app-momo_*.ipk"
  "openclash|OpenClash 科学上网|luci-app-openclash_*.ipk"
  "homebox|HomeBox 内网测速|homebox_*.ipk luci-app-homebox_*.ipk"
  "diskman|磁盘管理(分区/格式化)|luci-app-diskman_*.ipk"
  "smartinfo|S.M.A.R.T 硬盘健康监控|luci-app-smartinfo_*.ipk"
  "adguardhome|AdGuard Home DNS 过滤|luci-app-adguardhome_*.ipk"
  "tailscale|Tailscale 组网(community luci)|luci-app-tailscale-community_*.ipk luci-i18n-tailscale-community-zh-cn_*.ipk"
)

if [ -n "$APPS_FILTER" ]; then
  IFS=',' read -r -a requested_apps <<< "$APPS_FILTER"
  for requested in "${requested_apps[@]}"; do
    valid=0
    for entry in "${APPS[@]}"; do
      [ "${entry%%|*}" = "$requested" ] && valid=1
    done
    [ "$valid" -eq 1 ] || { echo "!! 未知应用: $requested" >&2; exit 1; }
  done
fi

for entry in "${APPS[@]}"; do
  IFS='|' read -r name desc pats <<< "$entry"
  if [ -n "$APPS_FILTER" ]; then
    ok=0
    for a in "${requested_apps[@]}"; do
      [ "$a" = "$name" ] && ok=1
    done
    [ "$ok" -eq 1 ] || continue
  fi

  work=$(mktemp -d "$OUT/work-$name.XXXXXX")
  mkdir -p "$work/main"
  found=0
  for p in $pats; do
    # shellcheck disable=SC2086
    for f in $SRC/$p; do
      [ -f "$f" ] || continue
      cp "$f" "$work/main/"
      found=1
    done
  done
  if [ "$found" -eq 0 ]; then
    echo "!! $name: 无匹配 ipk, 跳过"
    rm -rf "$work"
    continue
  fi

  cat > "$work/install.sh" <<'EOF'
#!/bin/sh
# ============================================================
#  ImmortalWrt x86_64 功能包一键安装 (opkg)
#  用法: sh xxx.run      # 安装
#        sh xxx.run --target <dir> --noexec   # 只解压不装
# ============================================================
arch=$(uname -m)
[ "$arch" = "x86_64" ] || { echo "!! 仅支持 x86_64 架构 (当前: $arch)"; exit 1; }
command -v opkg >/dev/null 2>&1 || { echo "!! 未找到 opkg - 本包适用于 ImmortalWrt 24.10/opkg 系系统"; exit 1; }
. /etc/openwrt_release 2>/dev/null || true
if [ "${DISTRIB_ID:-}" != "ImmortalWrt" ] || [ "${DISTRIB_RELEASE#24.10}" = "$DISTRIB_RELEASE" ]; then
  [ "${ALLOW_UNSUPPORTED:-0}" = "1" ] || {
    echo "!! 仅支持 ImmortalWrt 24.10.x；如已自行确认兼容，可设置 ALLOW_UNSUPPORTED=1"
    exit 1
  }
fi
cd "$(dirname "$0")" 2>/dev/null || cd /tmp
command -v sha256sum >/dev/null 2>&1 || { echo "!! 缺少 sha256sum，无法验证安装包"; exit 1; }
sha256sum -c SHA256SUMS || { echo "!! 安装包完整性校验失败"; exit 1; }
echo ">>> 更新软件源索引..."
opkg update >/dev/null 2>&1 || echo "(源更新失败, 继续尝试本地安装 - 依赖需从官方源解析时可能失败)"
echo ">>> 安装 $(ls main/*.ipk 2>/dev/null | wc -l) 个包 (依赖自动从官方源补齐)..."
opkg_args=""
[ "${FORCE_REINSTALL:-0}" = "1" ] && opkg_args="--force-reinstall"
# shellcheck disable=SC2086
opkg install $opkg_args main/*.ipk
rc=$?
if [ $rc = 0 ]; then
  echo ">>> ✅ 安装完成! 如 LuCI 未显示新菜单请刷新页面 (Ctrl+F5)"
else
  echo ">>> ⚠️ 安装返回 $rc；确认版本兼容后可设置 FORCE_REINSTALL=1 重试"
fi
exit $rc
EOF
  chmod +x "$work/install.sh"

  (
    cd "$work"
    sha256sum main/*.ipk > SHA256SUMS
  )

  # ipk 本身已压缩；使用 SHA256 校验自解压载荷，避免只依赖 CRC。
  "$MAKESELF" --nox11 --nomd5 --sha256 --nocomp "$work" "$OUT/$name.run" \
    "$name - $desc (x86_64, ImmortalWrt opkg)" ./install.sh >/dev/null
  echo "✔ $OUT/$name.run"
  rm -rf "$work"
done

echo "=== 完成: $(ls "$OUT"/*.run 2>/dev/null | wc -l) 个 run 包 ==="
