# EUDI Wallet for HarmonyOS

[English](README.md) | [简体中文](README.zh-CN.md)

[欧盟数字身份钱包（EU Digital Identity Wallet）](https://github.com/eu-digital-identity-wallet)参考应用的
HarmonyOS 移植版。钱包业务逻辑与界面使用 **Cangjie（仓颉）+ ArkUI** 编写，由 ArkTS `entry` 宿主通过
`CJHybridComponent` 承载仓颉 `AppRoot`。

本项目以 iOS 参考实现 [eudi-app-ios-wallet-ui](https://github.com/eu-digital-identity-wallet/eudi-app-ios-wallet-ui)
为基准逐模块移植，行为、界面与测试用例均与之对齐。

> **本项目为非官方移植**，与欧盟委员会（European Commission）无隶属关系，未获其认可，也不由其维护。
> “HarmonyOS” 是华为技术有限公司的商标。

## 功能

- PIN 与生物识别解锁
- 证件列表与详情，含过期、吊销状态
- **OpenID4VCI** 签发（授权码、预授权码、延迟签发），入口可以是应用内发行方列表、`credential-offer` 深链或二维码
- **OpenID4VP** 远程出示，含依赖方（Relying Party）注册信任校验
- 基于 BLE 的 **ISO/IEC 18013-5** 近场出示
- 通过 CSC v2 合格信任服务商进行远程文档签名（**RQES**）
- 交易记录

- Bundle name：`eu.europa.ec.euidi`
- Target / compatible SDK：HarmonyOS `6.1.1(24)`
- 设备：手机，arm64（`aarch64-ohos`）

## 演示

签发流程双端对照，左侧 iOS、右侧 HarmonyOS，从纯净安装到证件签发入库：

[![双端签发流程对照演示](docs/demo-poster.jpg)](docs/dual-platform-issuance-demo.mp4)

点击图片播放（1080p · 60fps · 约 96 秒），或直接下载
[`docs/dual-platform-issuance-demo.mp4`](docs/dual-platform-issuance-demo.mp4)。

## 环境要求

- DevEco Studio 6.1.x（自带 HarmonyOS SDK、Hvigor、Node.js、ohpm 和 `hdc`）
- HarmonyOS SDK `6.1.1(24)` 及对应的 Cangjie SDK / DevEco Cangjie 插件
- Git，以及能访问 GitHub 的网络（用于拉取 submodule）
- HarmonyOS 模拟器，或已开启开发者模式和 USB 调试的 arm64 真机

`run_tests.sh` 和 `run_device_tests.sh` 使用 macOS 上 DevEco Studio 的默认路径；其他平台请用 DevEco Studio
构建，或按本机工具链位置调整脚本开头的路径。

## 构建

```bash
git clone --recursive https://github.com/CJPLUK/eudi-app-hmos-wallet-ui.git
```

用 DevEco Studio 打开目录，等待 Project Sync 完成后执行 **Build → Build Hap(s)/App(s) → Build Hap(s)**。

根目录 [`hvigorfile.ts`](hvigorfile.ts) 会在编译任何模块之前做好准备：

- `third_party/` 下的 submodule 未检出时（clone 时没加 `--recursive`），自动执行 `git submodule update --init`；
- `entry/oh_modules` 不存在时，自动执行 `ohpm install --all`。

设置 `SKIP_FETCH_THIRD_PARTY=1` 可跳过 submodule 检查，例如 `third_party/` 已就位的离线构建。

产物：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
entry/build/default/outputs/default/entry-default-signed.hap   # 已配置签名时
```

### 签名

仓库不包含任何证书，`build-profile.json5` 中的 `signingConfigs` 为空。真机只能安装已签名的 HAP：在 DevEco Studio
中打开 **File → Project Structure → Project → Signing Configs**，勾选 **Automatically generate signature**，
并登录 Profile 中包含目标设备的华为开发者账号。

DevEco 会把证书路径和加密口令写入本地 `build-profile.json5`，这些内容与开发机绑定，不要提交：

```bash
git update-index --skip-worktree build-profile.json5      # 隐藏本地签名改动
git update-index --no-skip-worktree build-profile.json5   # 恢复
```

安装、启动和卸载步骤见 [INSTALL.md](INSTALL.md)。

## 三方库

协议层与密码学层是 EUDI Wallet 各库的仓颉移植，以 git submodule 形式放在 `third_party/` 下，并锁定到确定的提交：

| Submodule | 作用 |
| --- | --- |
| `eudi_lib_wallet_kit` | 钱包门面：签发、出示、存储、状态校验 |
| `eudi_lib_openid4vp_vci` | OpenID4VCI 与 OpenID4VP / SIOPv2 |
| `eudi_lib_mdoc_data_model`、`eudi_lib_mdoc_security`、`eudi_lib_mdoc_transfer` | ISO/IEC 18013-5 mdoc 数据模型、安全与 BLE 传输 |
| `eudi_lib_sdjwt` | SD-JWT VC |
| `eudi_lib_jose`、`eudi_lib_core_crypto`、`eudi_lib_x509`、`eudi_lib_cbor` | JOSE、密码学原语、X.509、CBOR |
| `eudi_lib_statium` | Token Status List（吊销状态） |
| `eudi_lib_etsi_1196x2` | ETSI 可信列表 |
| `eudi_lib_wallet_storage` | 证件存储 |
| `eudi_lib_rqes` | RQES：CSC 客户端、签名套件与 PoDoFo 原生引擎 |

升级某个库：在 `third_party/<name>` 中检出新提交，然后在主仓库提交更新后的 submodule 指针。预编译原生库
（仓颉 stdx、OpenSSL、libc++、PoDoFo 签名引擎）位于 `entry/libs/`。所有组件的许可见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 工程结构

```text
AppScope/                 应用级配置与图标
entry/                    ArkTS 宿主，加载仓颉 AppRoot
  src/main/cangjie/         仓颉组合根与 JS 桥
  src/main/ets/             EntryAbility、ArkTS 页面与平台能力桥
  src/ohosTest/             测试 HAP：仓颉桥 + ArkTS runner
  libs/                     预编译的仓颉 stdx 与原生库
Modules/                  eudi_feature_*（界面）与 eudi_logic_*（业务逻辑）模块
  eudi_unit_tests/          与 iOS 对齐的单测，只链进 ohosTest HAP
third_party/              eudi_lib_* git submodule
  libphonenumber/           手机号元数据子集与生成器
githooks/                 版本化的 git 钩子（用 githooks/install.sh 安装）
docs/                     演示视频、海报与测试报告
```

`Modules/eudi_logic_business/src/main/cangjie/phone_metadata*.cj` 是生成文件，请勿手改；改动请运行
`third_party/libphonenumber/gen_phone_metadata.py` 重新生成，pre-commit 钩子会校验两者一致。

## 测试

宿主机可运行的纯逻辑模块：

```bash
./run_tests.sh eudi_logic_business          # 单个模块
./run_tests.sh all                          # 所有宿主可运行模块
./run_tests.sh eudi_logic_business --filter='*FilterValidator*' --show-all-output
```

与 iOS 对齐的 feature / core 单测编进 **ohosTest HAP**，不进应用 HAP。构建两个 HAP、安装到已连接设备并执行测试：

```bash
HDC_TARGET=<serial-or-host:port> ./run_device_tests.sh
```

每次提交前自动跑宿主单测，每个 clone 安装一次钩子：

```bash
./githooks/install.sh          # 临时跳过：EUDI_SKIP_TESTS=1 git commit ...
```

最新测试报告（含与 iOS 用例的对齐、端到端结果与残留风险）见
[docs/test-report/2026-10-27](docs/test-report/2026-10-27/README.md)。

## 免责声明

与上游 EUDI Wallet 参考实现一致，本软件为初始开发版本：

- 后续可能发生较大变化，可能新增功能，也可能修改或移除现有功能，导致不兼容。
- 功能范围有限，文档尚不完整。
- 可能存在错误或设计缺陷，导致系统故障或数据丢失。
- 安全、隐私、可用性和可靠性标准低于未来的正式版本。

使用前请进行充分的工程评估与测试。**强烈建议不要将此版本用于生产环境。** 仅支持最新版本。

## 许可

Copyright (c) 2026 CJPLUK contributors.
基于 [eudi-app-ios-wallet-ui](https://github.com/eu-digital-identity-wallet/eudi-app-ios-wallet-ui)，
Copyright (c) 2023-2026 European Commission.

本项目基于 **EUPL-1.2**（European Union Public Licence 1.2，或欧盟委员会批准的后续版本）授权，许可全文见
[LICENSE](LICENSE)。署名信息见 [NOTICE](NOTICE)，三方组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

SPDX-License-Identifier: `EUPL-1.2`
