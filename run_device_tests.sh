#!/bin/bash
###############################################################################
# run_device_tests.sh — build app HAP + ohosTest HAP, install both, aa test.
#
# iOS-parity suites live in Modules/eudi_unit_tests and are linked only into
# the ohosTest HAP (libeudi_unit_tests.so). The app HAP does not
# contain them. `aa test` loads OpenHarmonyTestRunner from the test HAP, which
# calls runUnitTests() over the ArkTS interop bridge.
#
# Needs one connected arm64 Harmony device or emulator.
# Override the device with HDC_TARGET=<serial-or-host:port>.
#
# Usage: HDC_TARGET=... ./run_device_tests.sh
###############################################################################
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENTRY_MODULE="entry"
DEVECO_HOME="/Applications/DevEco-Studio.app/Contents"
HDC="${HDC:-$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc}"

if [ -z "${DEVECO_CANGJIE_HOME:-}" ]; then
  _CJ_SDK_VER="$(ls -1 "$HOME/.cangjie-sdk" 2>/dev/null | sort -V | tail -1)"
  DEVECO_CANGJIE_HOME="$HOME/.cangjie-sdk/${_CJ_SDK_VER}/cangjie"
fi
[ -d "$DEVECO_CANGJIE_HOME" ] || { echo "ERROR: Cangjie SDK not found at $DEVECO_CANGJIE_HOME" >&2; exit 1; }

export DEVECO_CANGJIE_HOME
export DEVECO_OH_NATIVE_HOME="$DEVECO_HOME/sdk/default/openharmony/native"
export DEVECO_SDK_HOME="$DEVECO_HOME/sdk"
export CANGJIE_HOME="$DEVECO_CANGJIE_HOME/build-tools"
export DEVECO_CANGJIE_PATH="${DEVECO_CANGJIE_PATH:-$DEVECO_CANGJIE_HOME}"
export CANGJIE_BUILD_SUPPORT_PATH="${CANGJIE_BUILD_SUPPORT_PATH:-$DEVECO_CANGJIE_HOME/build-tools/tools/hvigor/cangjie-build-support}"
export DEVECO_HVIGOR_CANGJIE_PLUGIN="${DEVECO_HVIGOR_CANGJIE_PLUGIN:-$CANGJIE_BUILD_SUPPORT_PATH}"
export JAVA_HOME="${JAVA_HOME:-$DEVECO_HOME/jbr/Contents/Home}"
export AARCH64_LIBS="$DEVECO_CANGJIE_HOME/api/lib/linux_ohos_aarch64_cjnative/ohos"
export AARCH64_MACRO_LIBS="$DEVECO_CANGJIE_HOME/api/macro/ohos"
export AARCH64_KIT_LIBS="$DEVECO_CANGJIE_HOME/api/lib/linux_ohos_aarch64_cjnative/kit"
export eudi_logic_analytics="${eudi_logic_analytics:-../eudi_logic_analytics}"

SYSCAP_CONFIG="$PROJECT_DIR/.idea/.deveco/cangjie/syscap_api_config.json"
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
export idDefined="$PROJECT_DIR/$ENTRY_MODULE/build/default/intermediates/res/default/ids_map/id_defined.json"
export moduleName="$ENTRY_MODULE" moduleType="hap"
BUNDLE="$(python3 -c "import re; t=open('$PROJECT_DIR/AppScope/app.json5').read(); m=re.search(r'bundleName\"\\s*:\\s*\"([^\"]+)\"', t); print(m.group(1) if m else 'eu.europa.ec.euidi')")"
export bundleName="$BUNDLE"

NODE="$DEVECO_HOME/tools/node/bin/node"
HVIGORW="$DEVECO_HOME/tools/hvigor/bin/hvigorw.js"

pick_hap() {
    local dir="$1"
    local hap=""
    for _h in "$dir"/*-signed.hap "$dir"/*-unsigned.hap; do
        [ -f "$_h" ] && { hap="$_h"; break; }
    done
    printf '%s' "$hap"
}

pick_target() {
    if [ -n "${HDC_TARGET:-}" ]; then
        printf '%s' "$HDC_TARGET"
        return
    fi
    local t
    t="$("$HDC" list targets 2>/dev/null | awk 'NF && $1 !~ /Empty/' | head -1 | tr -d '\r')"
    printf '%s' "$t"
}

cd "$PROJECT_DIR"

OHPM="/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm"
if [ -x "$OHPM" ]; then
    "$OHPM" install >/dev/null
    ( cd "$PROJECT_DIR/Modules/eudi_unit_tests" && "$OHPM" install >/dev/null )
fi

# Build-skip knobs (the app HAP rarely changes between test iterations, and the
# ohosTest HAP rebuild is incremental/fast when only a prebuilt .so moved):
#   SKIP_BUILD=1      -> skip BOTH assembleHap steps, reuse existing HAPs (pure install+test)
#   SKIP_APP_BUILD=1  -> skip only [1/4] app build, still rebuild [2/4] ohosTest HAP
if [ "${SKIP_BUILD:-}" = "1" ]; then
    echo "═══ [1-2/4] SKIP_BUILD=1 → reusing existing app + ohosTest HAPs ═══"
elif [ "${SKIP_APP_BUILD:-}" = "1" ]; then
    echo "═══ [1/4] SKIP_APP_BUILD=1 → reusing existing app HAP ═══"
    echo "═══ [2/4] assembleHap entry@ohosTest (test HAP with eudi_unit_tests) ═══"
    "$NODE" "$HVIGORW" assembleHap --mode module -p module=entry@ohosTest -p product=default --no-daemon
    TEST_RC=$?
    echo "ohosTest build rc=$TEST_RC"
    [ "$TEST_RC" = "0" ] || { echo "OHOSTEST BUILD FAILED"; exit 1; }
else
    echo "═══ [1/4] assembleHap entry@default (app, no unit tests) ═══"
    "$NODE" "$HVIGORW" assembleHap --mode module -p module=entry@default -p product=default --no-daemon
    BUILD_RC=$?
    echo "app build rc=$BUILD_RC"
    [ "$BUILD_RC" = "0" ] || { echo "APP BUILD FAILED"; exit 1; }

    echo "═══ [2/4] assembleHap entry@ohosTest (test HAP with eudi_unit_tests) ═══"
    "$NODE" "$HVIGORW" assembleHap --mode module -p module=entry@ohosTest -p product=default --no-daemon
    TEST_RC=$?
    echo "ohosTest build rc=$TEST_RC"
    [ "$TEST_RC" = "0" ] || { echo "OHOSTEST BUILD FAILED"; exit 1; }
fi

APP_HAP="$(pick_hap "$PROJECT_DIR/$ENTRY_MODULE/build/default/outputs/default")"
TEST_HAP=""
for d in \
    "$PROJECT_DIR/$ENTRY_MODULE/build/default/outputs/ohosTest" \
    "$PROJECT_DIR/$ENTRY_MODULE/build/ohosTest/outputs/default" \
    "$PROJECT_DIR/$ENTRY_MODULE/build/ohosTest/outputs/ohosTest"; do
    TEST_HAP="$(pick_hap "$d")"
    [ -n "$TEST_HAP" ] && break
done
if [ -z "$TEST_HAP" ]; then
    TEST_HAP="$(find "$PROJECT_DIR/$ENTRY_MODULE/build" -name '*ohosTest*.hap' 2>/dev/null | head -1)"
fi
[ -n "$APP_HAP" ] || { echo "ERROR: no app HAP" >&2; exit 1; }
[ -n "$TEST_HAP" ] || { echo "ERROR: no ohosTest HAP under $ENTRY_MODULE/build" >&2; exit 1; }
echo "app:  $APP_HAP"
echo "test: $TEST_HAP"

TARGET="$(pick_target)"
[ -n "$TARGET" ] || { echo "ERROR: no hdc target (set HDC_TARGET)" >&2; exit 1; }
echo "hdc target: $TARGET"

echo "═══ [3/4] install app HAP + ohosTest HAP ═══"
"$HDC" -t "$TARGET" install -r "$APP_HAP" 2>&1 | grep -aiE "success|fail" | tail -1
"$HDC" -t "$TARGET" install -r "$TEST_HAP" 2>&1 | grep -aiE "success|fail" | tail -1

echo "═══ [4/4] aa test ═══"
"$HDC" -t "$TARGET" shell hilog -r >/dev/null 2>&1
AA_LOG=/tmp/ohostest_aa.log
"$HDC" -t "$TARGET" shell aa test -b "$BUNDLE" -m entry_test -s unittest OpenHarmonyTestRunner -w 180 2>&1 | tee "$AA_LOG" | tail -20
echo "--- Cangjie-Test hilog ---"
"$HDC" -t "$TARGET" shell hilog -x 2>/dev/null | grep -aiE "Cangjie-Test|CJTest|CJ_TEST_SUMMARY|onPrepare|onRun" | tail -20

SUMMARY="$(tr -d '\r' < "$AA_LOG" | grep -a 'CJ_TEST_SUMMARY:' | tail -1)"
if [ -z "$SUMMARY" ]; then
    echo "TESTS INCONCLUSIVE: no CJ_TEST_SUMMARY in aa test output ($AA_LOG)" >&2
    exit 1
fi
echo "$SUMMARY"
case "$SUMMARY" in
    *"failed=0 error=0"*) echo "DEVICE TESTS PASSED" ;;
    *) echo "DEVICE TESTS FAILED" >&2; exit 1 ;;
esac
