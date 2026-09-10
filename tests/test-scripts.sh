#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PYTHON=${PYTHON:-python3}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  grep -F -- "$2" "$1" >/dev/null || fail "$1 缺少预期内容: $2"
}

assert_word() {
  tr ' ' '\n' < "$1" | grep -Fx -- "$2" >/dev/null || fail "$1 缺少包: $2"
}

assert_no_word() {
  if tr ' ' '\n' < "$1" | grep -Fx -- "$2" >/dev/null; then
    fail "$1 不应包含包: $2"
  fi
}

echo "[1/8] shell 语法"
bash -n "$REPO_ROOT/scripts/compose-packages.sh"
bash -n "$REPO_ROOT/scripts/gen-overlay.sh"
bash -n "$REPO_ROOT/scripts/make-runpacks.sh"
if GITHUB_WORKSPACE= bash "$REPO_ROOT/scripts/gen-overlay.sh" >/dev/null 2>&1; then
  fail "缺少 GITHUB_WORKSPACE 时 overlay 脚本未失败"
fi
if GITHUB_WORKSPACE="$TMP_ROOT/no-fw" bash "$REPO_ROOT/scripts/compose-packages.sh" >/dev/null 2>&1; then
  fail "缺少 FW 时包清单脚本未失败"
fi

echo "[2/8] 预编译包哈希与完整文件列表"
(
  cd "$REPO_ROOT"
  "$PYTHON" scripts/verify-package-checksums.py packages/SHA256SUMS >/dev/null
)

echo "[3/8] overlay 输入校验、转义与时区"
overlay_ws="$TMP_ROOT/overlay"
mkdir -p "$overlay_ws"
GITHUB_WORKSPACE="$overlay_ws" \
  PPPOE_USER="o'brien" \
  PPPOE_PASS='literal $(command) `command` $HOME' \
  WAN_AUTO=false \
  TZ_NAME=Asia/Tokyo \
  bash "$REPO_ROOT/scripts/gen-overlay.sh" >/dev/null
bash -n "$overlay_ws/build-files/etc/uci-defaults/89-prewan"
bash -n "$overlay_ws/build-files/etc/uci-defaults/90-netauto"
bash -n "$overlay_ws/build-files/etc/uci-defaults/91-custom"
assert_file_contains "$overlay_ws/build-files/etc/uci-defaults/89-prewan" "uci set network.wan.username='o'\"'\"'brien'"
assert_file_contains "$overlay_ws/build-files/etc/uci-defaults/89-prewan" "uci set network.wan.password='literal \$(command) \`command\` \$HOME'"
assert_file_contains "$overlay_ws/build-files/etc/uci-defaults/90-netauto" "udhcpc -i \"\$1\" -n -q -t 2 -T 2 -f -s /bin/true"
assert_file_contains "$overlay_ws/build-files/etc/uci-defaults/90-netauto" 'return $rc'
assert_file_contains "$overlay_ws/build-files/etc/uci-defaults/91-custom" "system.@system[0].timezone='JST-9'"
if GITHUB_WORKSPACE="$TMP_ROOT/invalid-host" HOSTNAME='bad host' bash "$REPO_ROOT/scripts/gen-overlay.sh" >/dev/null 2>&1; then
  fail "非法主机名未被拒绝"
fi
if GITHUB_WORKSPACE="$TMP_ROOT/invalid-ip" LAN_IP='192.168.999.1' bash "$REPO_ROOT/scripts/gen-overlay.sh" >/dev/null 2>&1; then
  fail "非法 IPv4 地址未被拒绝"
fi

echo "[4/8] 版本化包清单"
pkg_ws="$TMP_ROOT/packages"
mkdir -p "$pkg_ws"
GITHUB_WORKSPACE="$pkg_ws" FW=24.10.6 B_PASSWALL2=true LUCI_LANG=en \
  bash "$REPO_ROOT/scripts/compose-packages.sh" >/dev/null
assert_word "$pkg_ws/pkg.list" luci-app-passwall2
assert_word "$pkg_ws/pkg.list" sing-box
assert_no_word "$pkg_ws/pkg.list" xray-core
GITHUB_WORKSPACE="$pkg_ws" FW=25.12.1 B_PASSWALL2=true LUCI_LANG=zh_cn \
  bash "$REPO_ROOT/scripts/compose-packages.sh" >/dev/null
assert_word "$pkg_ws/pkg.list" xray-core
assert_word "$pkg_ws/pkg.list" luci-i18n-passwall2-zh-cn

echo "[5/8] manifest 完整性"
printf 'alpha beta\n' > "$TMP_ROOT/requested.txt"
printf 'alpha - 1.0\nbeta - 2.0\n' > "$TMP_ROOT/manifest.txt"
"$PYTHON" "$REPO_ROOT/scripts/verify-manifest.py" "$TMP_ROOT/requested.txt" "$TMP_ROOT/manifest.txt" >/dev/null
printf 'alpha beta missing\n' > "$TMP_ROOT/requested.txt"
if "$PYTHON" "$REPO_ROOT/scripts/verify-manifest.py" "$TMP_ROOT/requested.txt" "$TMP_ROOT/manifest.txt" >/dev/null 2>&1; then
  fail "manifest 缺包时未失败"
fi

echo "[6/8] ImageBuilder 补丁必须精确且不可重复应用"
printf 'target:\n\t$(OPKG) install $(BUILD_PACKAGES)\n' > "$TMP_ROOT/Makefile"
"$PYTHON" "$REPO_ROOT/scripts/patch-imagebuilder.py" "$TMP_ROOT/Makefile" >/dev/null
assert_file_contains "$TMP_ROOT/Makefile" '$(OPKG) configure && $(OPKG) install $(BUILD_PACKAGES)'
if "$PYTHON" "$REPO_ROOT/scripts/patch-imagebuilder.py" "$TMP_ROOT/Makefile" >/dev/null 2>&1; then
  fail "ImageBuilder 补丁重复应用时未失败"
fi

echo "[7/8] opkg 索引可复现且与仓库一致"
mkdir -p "$TMP_ROOT/feed-a" "$TMP_ROOT/feed-b"
"$PYTHON" "$REPO_ROOT/scripts/gen-feed-index.py" "$REPO_ROOT/packages/local" "$TMP_ROOT/feed-a" >/dev/null
"$PYTHON" "$REPO_ROOT/scripts/gen-feed-index.py" "$REPO_ROOT/packages/local" "$TMP_ROOT/feed-b" >/dev/null
cmp "$TMP_ROOT/feed-a/Packages" "$TMP_ROOT/feed-b/Packages"
cmp "$TMP_ROOT/feed-a/Packages.gz" "$TMP_ROOT/feed-b/Packages.gz"
# Windows 上旧 checkout 可能仍保留 CRLF；内容比较时只归一化回车，gzip 仍做逐字节比较。
tr -d '\r' < "$REPO_ROOT/packages/local/Packages" | cmp "$TMP_ROOT/feed-a/Packages" -
cmp "$TMP_ROOT/feed-a/Packages.gz" "$REPO_ROOT/packages/local/Packages.gz"
[ "$(grep -c '^Package:' "$TMP_ROOT/feed-a/Packages")" -eq 12 ] || fail "opkg 索引包数量异常"

echo "[8/8] IPK 控制字段补丁与 run 包筛选"
cp "$REPO_ROOT/packages/local/luci-app-diskman_0.2.13-r1_all.ipk" "$TMP_ROOT/diskman.ipk"
"$PYTHON" "$REPO_ROOT/scripts/patch-ipk-control.py" "$TMP_ROOT/diskman.ipk" \
  'exfat-mkfs,exfat-fsck:exfatprogs' >/dev/null
if "$PYTHON" "$REPO_ROOT/scripts/patch-ipk-control.py" "$TMP_ROOT/diskman.ipk" \
  'exfat-mkfs:exfatprogs' >/dev/null 2>&1; then
  fail "IPK 依赖补丁在目标不存在时未失败"
fi
mkdir -p "$TMP_ROOT/patched-feed"
"$PYTHON" "$REPO_ROOT/scripts/gen-feed-index.py" "$TMP_ROOT" "$TMP_ROOT/patched-feed" >/dev/null
assert_file_contains "$TMP_ROOT/patched-feed/Packages" 'Depends: libc, luci-compat, blkid, e2fsprogs, parted, smartmontools, dosfstools, kmod-fs-msdos, kmod-fs-ntfs3, kmod-fs-exfat, exfatprogs, exfatprogs,'

fake_makeself="$TMP_ROOT/makeself.sh"
cat > "$fake_makeself" <<'EOF'
#!/bin/sh
while [ "${1#--}" != "$1" ]; do shift; done
src=$1
dst=$2
test -f "$src/SHA256SUMS"
cp "$src/install.sh" "$dst"
EOF
chmod +x "$fake_makeself"
bash "$REPO_ROOT/scripts/make-runpacks.sh" "$REPO_ROOT/packages/local" \
  "$TMP_ROOT/runpacks" "$fake_makeself" homebox >/dev/null
[ -f "$TMP_ROOT/runpacks/homebox.run" ] || fail "未生成筛选后的 homebox.run"
[ "$(find "$TMP_ROOT/runpacks" -maxdepth 1 -name '*.run' | wc -l)" -eq 1 ] || fail "run 包筛选失效"
assert_file_contains "$TMP_ROOT/runpacks/homebox.run" 'sha256sum -c SHA256SUMS'
assert_file_contains "$TMP_ROOT/runpacks/homebox.run" 'ImmortalWrt 24.10.x'
if bash "$REPO_ROOT/scripts/make-runpacks.sh" "$REPO_ROOT/packages/local" \
  "$TMP_ROOT/invalid-runpacks" "$fake_makeself" unknown >/dev/null 2>&1; then
  fail "未知 run 包应用未被拒绝"
fi

echo "全部脚本测试通过。"
