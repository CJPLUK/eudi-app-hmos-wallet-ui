# E-01 执行记录

- 构建：`0e1f5c5`（`entry-default-signed.hap`，从 GitHub 全新 `clone --recursive` 构建）
- 设备：HUAWEI Mate 60 Pro（ALN-AL80），HarmonyOS 6.1.0.125
- 日期：2026-10-27

| 步骤 | 操作 | 观察结果 | 截图 |
|---|---|---|---|
| 1 | 卸载应用，安装计分构建 HAP | `uninstall bundle successfully` / `install bundle successfully` | — |
| 2 | `aa start -a EntryAbility -b eu.europa.ec.euidi` | 进程启动（PID 61360），显示 “Enter a PIN” 引导页，输入框获得焦点 | [01_cold_start.jpeg](01_cold_start.jpeg) |
| 3 | 输入 6 位 PIN | 自动进入 “Confirm PIN”（Re-type your PIN） | [02_confirm_pin.jpeg](02_confirm_pin.jpeg) |
| 4 | 再次输入相同 PIN | 显示 “Your wallet is secured! / Your Wallet is ready for use.” 与 “Go to home” | [03_wallet_secured.jpeg](03_wallet_secured.jpeg) |
| 5 | 点击 “Go to home” | 进入首页：Authenticate 与 Sign document 两张卡片，底部 Home / Documents / History 标签 | [04_home.jpeg](04_home.jpeg) |
| 6 | 检查进程与故障日志 | PID 仍为 61360（全程未重启）；`/data/log/faultlog/faultlogger` 与 hilog 中无本应用崩溃或 `CJ_EXC` / `CJ_ERR` 记录 | — |

结论：通过。
