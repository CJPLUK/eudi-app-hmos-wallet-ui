# Installation Guide / 安装指南

How to build, install, verify and uninstall EUDI Wallet for HarmonyOS.
从源码构建、安装、验证与卸载。

## 1. Prerequisites / 前置条件

- DevEco Studio 6.1.x with the HarmonyOS SDK `6.1.1(24)` and the Cangjie plugin. It provides
  Hvigor, ohpm and `hdc`.
- A HarmonyOS emulator (DevEco → Device Manager), or an arm64 phone with developer mode and
  USB debugging enabled.

`hdc` lives in the SDK `toolchains/` directory, for example:

- macOS: `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`
- Windows: `%USERPROFILE%\AppData\Local\Huawei\Sdk\default\openharmony\toolchains\hdc.exe`

## 2. Build / 构建

```bash
git clone --recursive https://github.com/CJPLUK/eudi-app-hmos-wallet-ui.git
```

Open the folder in DevEco Studio, wait for Project Sync, then
**Build → Build Hap(s)/App(s) → Build Hap(s)**. If you cloned without `--recursive`, the build
runs `git submodule update --init` for you.

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
entry/build/default/outputs/default/entry-default-signed.hap   # when signing is configured
```

A physical phone only accepts a **signed** HAP. In DevEco Studio open
**File → Project Structure → Project → Signing Configs**, tick
**Automatically generate signature** and sign in with a Huawei developer account. The emulator
also accepts the unsigned HAP.

真机只能安装已签名的 HAP，在 DevEco Studio 中勾选 **Automatically generate signature** 即可；模拟器可直接安装未签名 HAP。

## 3. Install and launch / 安装并启动

```bash
# Find the target (for example 127.0.0.1:5555 for the emulator)
hdc list targets

# Install (-r replaces an existing installation)
hdc -t <target> install -r entry/build/default/outputs/default/entry-default-signed.hap

# Launch
hdc -t <target> shell aa start -a EntryAbility -b eu.europa.ec.euidi
```

`-t <target>` can be omitted when a single device is connected. On first launch the app asks
you to set a **6-digit PIN**, then opens the wallet dashboard.

## 4. Verify / 验证

```bash
hdc shell pidof eu.europa.ec.euidi                    # prints a PID while running
hdc shell snapshot_display -f /data/local/tmp/eudi.jpeg
hdc file recv /data/local/tmp/eudi.jpeg ./eudi.jpeg
```

## 5. Uninstall / 卸载

```bash
hdc uninstall eu.europa.ec.euidi
```

## License / 许可

EUPL-1.2, see [LICENSE](LICENSE).
