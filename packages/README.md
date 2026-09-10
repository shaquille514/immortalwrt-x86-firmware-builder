# 预编译包维护规则

`local/` 与 `apk25/` 中的文件会以 root 权限进入固件，应按可执行代码对待。`SHA256SUMS` 是当前仓库接受的文件基线：它能发现文件损坏或未同步替换，但不能证明二进制由某份源码构建，也不能证明上游本身可信。

更新包时：

1. 优先从项目官方 Release 或对应版本 SDK/源码构建取得包，确认目标为 x86_64 且匹配 ImmortalWrt 版本。
2. 同时保存上游项目、Release/tag/commit、下载地址或构建命令。当前历史包缺少完整来源记录；后续更新不应继续扩大这个缺口。
3. 替换文件后，在仓库根目录重新生成 24.10 索引：

   ```bash
   python3 scripts/gen-feed-index.py packages/local
   ```

4. 从仓库根目录重建哈希清单，并审查文件列表变化：

   ```bash
   sha256sum packages/local/*.ipk packages/apk25/*.apk > packages/SHA256SUMS
   sha256sum -c packages/SHA256SUMS
   ```

5. 运行 `bash tests/test-scripts.sh`。不要为了让构建通过而全局关闭 opkg/apk 签名检查或忽略安装错误。

建议逐步将这些预编译包改为由固定上游 commit 的可复现构建生成，并为每次更新记录来源与构建环境。
