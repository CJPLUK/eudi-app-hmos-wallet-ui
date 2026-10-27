#!/bin/bash
###############################################################################
# run_tests.sh — cjpm-test runner for EUDI Cangjie modules (iOS-test parity).
#
# Host (macOS darwin): modules with no ohos/ArkUI import. stdx is allowed when
# a darwin stdx tree is on STDX_DARWIN.
# Device (aarch64-linux-ohos): feature/core suites in Modules/eudi_unit_tests —
# a standalone cjpm package that is NOT in the app HAP.
#
# Usage:
#   ./run_tests.sh <module-name> [extra cjpm test args...]   # host
#   ./run_tests.sh <module-name> --device [args...]          # ohos target
#   ./run_tests.sh all                                       # host-runnable modules
#   ./run_tests.sh eudi_unit_tests --device                  # migrated iOS-parity suites
#
# Examples:
#   ./run_tests.sh eudi_logic_business
#   ./run_tests.sh eudi_logic_business --filter=*FilterValidator* --show-all-output
###############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# ── Toolchain env (mirrors .claude/scripts/build.sh) ────────────────────────
DEVECO_HOME="/Applications/DevEco-Studio.app/Contents"
if [ -z "${DEVECO_CANGJIE_HOME:-}" ]; then
  _CJ_SDK_VER="$(ls -1 "$HOME/.cangjie-sdk" 2>/dev/null | sort -V | tail -1)"
  DEVECO_CANGJIE_HOME="$HOME/.cangjie-sdk/${_CJ_SDK_VER}/cangjie"
fi
[ -d "$DEVECO_CANGJIE_HOME" ] || { echo "ERROR: Cangjie SDK not found at $DEVECO_CANGJIE_HOME" >&2; exit 1; }

export DEVECO_CANGJIE_HOME
export DEVECO_OH_NATIVE_HOME="$DEVECO_HOME/sdk/default/openharmony/native"
export DEVECO_SDK_HOME="$DEVECO_HOME/sdk"
export CANGJIE_HOME="$DEVECO_CANGJIE_HOME/build-tools"
CJ_RUNTIME="$DEVECO_CANGJIE_HOME/build-tools/runtime/lib/darwin_aarch64_cjnative"
export DYLD_LIBRARY_PATH="$CJ_RUNTIME:${DYLD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$CJ_RUNTIME:${LD_LIBRARY_PATH:-}"
export PATH="$CJ_RUNTIME:$DEVECO_CANGJIE_HOME/build-tools/bin:$DEVECO_CANGJIE_HOME/build-tools/tools/bin:/bin:/usr/bin:/opt/homebrew/bin:$PATH"
export DEVECO_CANGJIE_PATH="${DEVECO_CANGJIE_PATH:-$DEVECO_CANGJIE_HOME}"
# ohos lib paths consumed by cjpm.toml target blocks
export AARCH64_LIBS="$DEVECO_CANGJIE_HOME/api/lib/linux_ohos_aarch64_cjnative/ohos"
export AARCH64_MACRO_LIBS="$DEVECO_CANGJIE_HOME/api/macro/ohos"
export AARCH64_KIT_LIBS="$DEVECO_CANGJIE_HOME/api/lib/linux_ohos_aarch64_cjnative/kit"
export X86_64_OHOS_LIBS="$DEVECO_CANGJIE_HOME/api/lib/linux_ohos_x86_64_cjnative/ohos"
export X86_64_OHOS_MACRO_LIBS="$DEVECO_CANGJIE_HOME/api/macro/ohos"
export X86_64_OHOS_KIT_LIBS=""
# macOS SDK — required so the host (aarch64-apple-darwin) link finds libSystem
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"

# Host stdx (darwin dylibs + .cjo). GitCode release zips 401 from this network, so the
# first run on a machine builds stdx 1.1.3.1 from source into ~/.cangjie_stdx.
# Override with STDX_DARWIN if you already have a matching darwin stdx tree.
export STDX_DARWIN="${STDX_DARWIN:-$HOME/.cangjie_stdx/v1.1.3.1/darwin_aarch64_cjnative/dynamic/stdx}"
OPENSSL_LIB="$(brew --prefix openssl@3 2>/dev/null)/lib"
if [ -d "$STDX_DARWIN" ]; then
  xattr -dr com.apple.quarantine "$STDX_DARWIN" >/dev/null 2>&1 || true
  export DYLD_LIBRARY_PATH="$STDX_DARWIN:${OPENSSL_LIB}:$CJ_RUNTIME:${DYLD_LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="$STDX_DARWIN:${OPENSSL_LIB}:$CJ_RUNTIME:${LD_LIBRARY_PATH:-}"
fi

# hvigor injects these when assembling the HAP. Standalone `cjpm test` must too:
# logic_api's cjpm.toml has path = "${eudi_logic_analytics}", and wallet-kit's
# compile-option has --cfg="${COMPILE_CONDITION}". Empty values become
# `path=""` / `--cfg -B` and the test graph fails to load.
export eudi_logic_analytics="${eudi_logic_analytics:-../eudi_logic_analytics}"
SYSCAP_CONFIG="$REPO_ROOT/.idea/.deveco/cangjie/syscap_api_config.json"
if [ ! -f "$SYSCAP_CONFIG" ] || ! grep -q '"deviceSysCap"' "$SYSCAP_CONFIG" 2>/dev/null; then
    mkdir -p "$(dirname "$SYSCAP_CONFIG")"
    cat > "$SYSCAP_CONFIG" <<JSON
{ "Modules": { "entry": { "deviceSysCap": { "phone": [
  "$DEVECO_HOME/sdk/default/hms/ets/api/device-define/phone-hmos.json",
  "$DEVECO_HOME/sdk/default/hms/ets/api/device-define/phone.json" ] } } }, "apiLevel": 22 }
JSON
fi
export COMPILE_CONDITION_ENTRY="${COMPILE_CONDITION_ENTRY:-APILevel_level=22,product=default,APILevel_syscap=$SYSCAP_CONFIG,target=default}"
export COMPILE_CONDITION="${COMPILE_CONDITION:-$COMPILE_CONDITION_ENTRY}"

# Host-runnable (pure-logic) modules — no transitive ohos/ArkUI import.
# eudi_logic_api / eudi_logic_authentication import stdx; host linking uses STDX_DARWIN.
HOST_MODULES=(eudi_logic_business eudi_logic_api eudi_logic_authentication eudi_logic_storage)

run_host() {
  local mod="$1"; shift
  if [ ! -f "$STDX_DARWIN/stdx.encoding.json.cjo" ]; then
    echo "ERROR: darwin stdx not found at $STDX_DARWIN" >&2
    echo "Build it once (Harmony cjc 1.1.3 + OpenSSL 3, NO_ASPECTCJ=1):" >&2
    echo "  git clone --depth 1 --branch v1.1.3.1 https://github.com/cangjielanguage/cangjie_stdx.git \$HOME/.cangjie_stdx/src-v1.1.3.1" >&2
    echo "  python3 \$HOME/.cangjie_stdx/src-v1.1.3.1/build.py build -t release --target-lib=\$(brew --prefix openssl@3)/lib --include=\$(brew --prefix openssl@3)/include" >&2
    echo "  python3 \$HOME/.cangjie_stdx/src-v1.1.3.1/build.py install --prefix \$HOME/.cangjie_stdx/v1.1.3.1" >&2
    exit 1
  fi
  echo "═══ cjpm test (host) :: $mod ═══"
  ( cd "$REPO_ROOT/Modules/$mod" && cjpm test --target aarch64-apple-darwin "$@" )
}

run_device() {
  local mod="$1"; shift
  echo "═══ cjpm test (ohos) :: $mod ═══"
  # Cross-compile for aarch64-linux-ohos. Do not execute on the Mac: the binary
  # is linux-ohos. Pass extra args after --no-run if you want a filter.
  ( cd "$REPO_ROOT/Modules/$mod" && cjpm test --target aarch64-linux-ohos --no-run "$@" )
}

[ $# -ge 1 ] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

if [ "$1" = "all" ]; then
  for m in "${HOST_MODULES[@]}"; do run_host "$m"; done
  exit 0
fi

MOD="$1"; shift
if [ "${1:-}" = "--device" ]; then shift; run_device "$MOD" "$@"; else run_host "$MOD" "$@"; fi
