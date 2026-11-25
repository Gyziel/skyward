#!/bin/bash
# build.sh — 为小米 17 Pro (pandora) 编译 Skyward recovery
#
# 用法:
#   ./build.sh <固件完整链接> [版本号]
#
# 例子:
#   ./build.sh "https://ultimateota.d.miui.com/OS4.0.8.0.XBLCNXM/pandora-ota_full-OS4.0.8.0.XBLCNXM-user-17.0-f86b9e9f4d.zip?t=...&s=..." OS4.0.8.0.XBLCNXM
#
# 只需要给一个新版固件（卡刷包或线刷包）的完整下载链接，脚本会:
#   1. 下载固件
#   2. 解出 stock recovery 镜像，算 SHA-256
#   3. 生成对应版本的 pandora.toml（解密用的 secure world 配置已内置）
#   4. 编译 Skyward + system-init + skyward-pack
#   5. 打包出最终的 recovery 镜像 + SHA-256
#
# 依赖: Rust 1.100.0 + cargo-ndk + Android NDK + cpio + lz4 + python3(payload_dumper)
set -e
export TZ=Asia/Shanghai

FIRMWARE_URL="$1"
VERSION="${2:-}"
if [ -z "$FIRMWARE_URL" ]; then
  echo "用法: $0 <固件完整链接> [版本号]" >&2
  exit 1
fi
# 从链接里猜版本号 (OSx.y.z.w.XBLCNXM)
if [ -z "$VERSION" ]; then
  VERSION=$(echo "$FIRMWARE_URL" | grep -o -E "OS[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.XBLCNXM" | head -1)
fi
if [ -z "$VERSION" ]; then
  echo "无法从链接里识别版本号，请把版本号作为第二个参数传入" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/work-$VERSION"
SKYWARD_SRC="$ROOT/skyward-src"
DEVICE_TOML_BASE="$ROOT/pandora-base.toml"
mkdir -p "$WORK"
cd "$WORK"

echo "=== 1/6 下载固件 $VERSION ==="
FIRMWARE_FILE="$WORK/firmware.zip"
if [ ! -s "$FIRMWARE_FILE" ]; then
  curl -sL -C - -o "$FIRMWARE_FILE" "$FIRMWARE_URL"
fi
ls -lh "$FIRMWARE_FILE"

echo "=== 2/6 解出 stock recovery ==="
unzip -o -q "$FIRMWARE_FILE" "payload.bin" -d "$WORK" || \
  unzip -o -q "$FIRMWARE_FILE" "payload.bin" -d "$WORK"
python3 "$ROOT/payload_dumper.py" -o "$WORK/out" "$WORK/payload.bin" >/dev/null 2>&1 || \
  python3 "$ROOT/payload_dumper.py" "$WORK/payload.bin" "$WORK/out" >/dev/null 2>&1
RECOVERY_IMG=$(find "$WORK/out" -iname "*recovery*.img" | head -1)
if [ -z "$RECOVERY_IMG" ]; then
  echo "没有解出 recovery 镜像" >&2; exit 1
fi
cp "$RECOVERY_IMG" "$WORK/stock-recovery.img"
RECOVERY_SHA=$(sha256sum "$WORK/stock-recovery.img" | awk '{print $1}')
echo "stock recovery: $WORK/stock-recovery.img"
echo "sha256: $RECOVERY_SHA"

echo "=== 3/6 生成 pandora.toml ($VERSION) ==="
# 以 mariusarva 的 device.toml 为底（带解密用的 secure world 配置），只换 [stock] 一节
python3 - "$DEVICE_TOML_BASE" "$WORK/pandora.toml" "$VERSION" "$FIRMWARE_URL" "$RECOVERY_SHA" <<'PY'
import sys, re
src, dst, version, url, sha = sys.argv[1:6]
text = open(src).read()
# 替换 [stock] 一节的 version / package / recovery
text = re.sub(r'(?m)^version = "OS[^"]*"$', f'version = "{version}"', text, count=1)
text = re.sub(r'(?m)^package = "https?://[^"]*"$', f'package = "{url}"', text, count=1)
text = re.sub(r'(?m)^recovery = "[0-9a-f]*"$', f'recovery = "{sha}"', text, count=1)
open(dst, 'w').write(text)
print("pandora.toml 已生成")
PY

echo "=== 4/6 编译 Skyward (aarch64-linux-android) ==="
export PATH="$HOME/.cargo/bin:$PATH"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ROOT/android-ndk}"
export CARGO_BUILD_JOBS=1
cd "$SKYWARD_SRC"
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" \
  cargo ndk -t arm64-v8a --platform 30 build --release -p skyward-system-init \
  --target-dir target/system-init
cargo build --release -p skyward-pack

echo "=== 5/6 打包 recovery 镜像 ==="
"$SKYWARD_SRC/target/release/skyward-pack" recovery \
  --stock "$WORK/stock-recovery.img" \
  --binary "$SKYWARD_SRC/target/aarch64-linux-android/release/skyward" \
  --system-init "$SKYWARD_SRC/target/system-init/aarch64-linux-android/release/system-init" \
  --config "$WORK/pandora.toml" \
  --font "$SKYWARD_SRC/resources/fonts/MiSansVF.ttf" \
  --mono "$SKYWARD_SRC/resources/fonts/KirkMono-Regular.ttf" \
  --mono-license "$SKYWARD_SRC/resources/fonts/KirkMono-OFL.txt" \
  --out "$ROOT/skyward-pandora-$VERSION.img"

echo "=== 6/6 校验成品 ==="
ls -lh "$ROOT/skyward-pandora-$VERSION.img"
sha256sum "$ROOT/skyward-pandora-$VERSION.img"
"$SKYWARD_SRC/target/release/skyward-pack" list "$ROOT/skyward-pandora-$VERSION.img" | head -20
echo "完成: $ROOT/skyward-pandora-$VERSION.img"
