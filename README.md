# Skyward for Xiaomi 17 Pro (pandora)

小米 17 Pro 的 Skyward recovery 编译工程。Skyward 是一个用 Rust 写的第三方 recovery（不是 TWRP），支持 /data 解密、备份/恢复、adb sideload、WLAN 等。

- 上游：[kirklin/skyward](https://github.com/kirklin/skyward)（本工程基于 v0.5.0）
- 参考：[mariusarva/skyward-pandora](https://github.com/mariusarva/skyward-pandora)（4.0.4.0 版，解密用的 secure world 配置即取自该工程）
- 目标机型：Xiaomi 17 Pro（`pandora`）

## 已验证的版本

| 版本 | 系统版本 | 状态 |
| --- | --- | --- |
| v0.5.1-4.0.8.0 | OS4.0.8.0.XBLCNXM | 待真机测试 |

## 以后系统更新了怎么编译

只需要把新版系统固件（卡刷包或线刷包）的**完整下载链接**发给 Muse，跑：

```bash
./build.sh "<固件完整链接>" [版本号]
```

脚本会自动：下载固件 → 解出 stock recovery → 算 SHA-256 → 生成对应版本的 `pandora.toml` → 编译 Skyward → 打包出新的 recovery 镜像（`skyward-pandora-<版本号>.img`）+ SHA-256。

> 注意：固件链接一般是带时效签名的（`?t=...&s=...`），拿到后尽快用，过期要重新取。

## 手动编译

依赖：Rust 1.100.0、`cargo-ndk`、Android NDK、cpio、lz4、python3（payload_dumper）。

```bash
# 1. 装 Rust + Android 目标 + cargo-ndk
rustup toolchain install 1.100.0
rustup target add aarch64-linux-android
cargo install cargo-ndk

# 2. 解压 Android NDK，设 ANDROID_NDK_HOME
export ANDROID_NDK_HOME=/path/to/android-ndk-r27c

# 3. 编译并打包（build.sh 已包好这几步）
./build.sh "<固件完整链接>" OS4.0.8.0.XBLCNXM
```

编译分三步（`build.sh` 内部就是这么做的）：

```bash
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 build --release -p skyward-system-init --target-dir target/system-init
cargo build --release -p skyward-pack
target/release/skyward-pack recovery \
  --stock work-<版本>/stock-recovery.img \
  --binary target/aarch64-linux-android/release/skyward \
  --system-init target/system-init/aarch64-linux-android/release/system-init \
  --config work-<版本>/pandora.toml \
  --font skyward-src/resources/fonts/MiSansVF.ttf \
  --mono skyward-src/resources/fonts/KirkMono-Regular.ttf \
  --mono-license skyward-src/resources/fonts/KirkMono-OFL.txt \
  --out skyward-pandora-<版本>.img
```

## 刷入

只动 recovery 分区，刷前先备份原厂 recovery，且手机必须已解锁 Bootloader：

```bash
fastboot flash recovery_b skyward-pandora-<版本>.img
fastboot reboot recovery
```

进 recovery 后先输锁屏 PIN，看能不能解密 /data（能看到 /data/data 和内部存储即成功）。

## 重要提醒

- **不要在 recovery 里装官方完整包**。装完后大概率卡米（更新包会把 boot 与 vbmeta 刷成原厂，绕不过签名校验）。请始终在系统里更新。
- 每个系统版本都要用对应版本的固件重新编译，跨版本不保证解密正常。
- 刷机有风险，先备份数据。
