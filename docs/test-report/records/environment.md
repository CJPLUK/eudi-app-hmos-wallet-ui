# 测试环境（2026-10-27 / 10-28）

| 项 | 值 |
|---|---|
| 被测版本 | `eudi-app-hmos-wallet-ui` `c8d48ce`（在全新 `git clone --recursive` 的仓库上快进到该提交） |
| submodule | 14 个 `third_party/eudi_lib_*`，版本按 `c8d48ce` 中的 gitlink 锁定 |
| 设备 | HUAWEI Mate 60 Pro，型号 ALN-AL80 |
| 设备系统 | `ALN-AL00 6.1.0.125(SP35C00E111R10P8log)`，API 24 |
| 宿主机 | macOS 26.6.2（25G83），arm64 |
| DevEco Studio | 6.1.1 |
| 仓颉编译器 | Cangjie Compiler 1.1.3 (cjnative)，`~/.cangjie-sdk/6.1` |
| hdc | 3.2.0d |
| 宿主测试 | `DEVECO_CANGJIE_HOME=~/.cangjie-sdk/6.1/cangjie DEVELOPER_DIR=/Library/Developer/CommandLineTools ./run_tests.sh all` |
| 设备测试 | `HDC_TARGET=<serial> ./run_device_tests.sh`（构建应用 HAP 与 ohosTest HAP，安装后 `aa test`） |
| 签名 | 本地 DevEco 自动签名（未提交到仓库） |
| iOS 参照 | `eudi-app-ios-wallet-ui` `95b71766`（2026-09-01），368 个 `func test*` |
