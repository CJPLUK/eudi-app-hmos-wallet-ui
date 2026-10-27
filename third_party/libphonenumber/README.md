# libphonenumber 手机号校验元数据

iOS 侧 `FormValidator` 通过 [PhoneNumberKit](https://github.com/PhoneNumberKit/PhoneNumberKit)
做区域感知的号码校验（`parse(phone, withRegion: countryCode, ignoreType: false)`）。
仓颉侧要与之行为一致，就必须用**同一张** libphonenumber 元数据表——号码有效性取决于
各地区实际已分配的号段，不是长度规则能近似的（例如 `6941111111` 是合法的希腊手机号，
但 `694` 不是已分配的 NANP 区号，因此在 US 无效）。

## 文件

| 文件 | 说明 |
|---|---|
| `phone_metadata.json` | 提取出的校验相关子集（254 个地区），**已纳入 git**，是生成器的输入 |
| `extract_metadata.py` | 从 PhoneNumberKit 的 `PhoneNumberMetadata.json` 提取上述子集 |
| `gen_phone_metadata.py` | 由子集生成仓颉源码；`--check` 校验生成物是否最新 |

生成物（**不要手改**）：

- `Modules/eudi_logic_business/src/main/cangjie/phone_metadata.cj` —— 表格，随 App 打包
- `Modules/eudi_logic_business/src/main/cangjie/phone_metadata_examples_test.cj` —— 1137 条示例号，
  `_test.cj` 后缀使其被 `cjpm build` 排除，只在测试中使用

算法实现在 `Modules/eudi_logic_business/src/main/cangjie/phone_number_validator.cj`。

## 为什么把子集纳入 git

上游 `PhoneNumberMetadata.json` 只存在于 Xcode 的 SPM checkout 里
（`~/Library/Developer/Xcode/DerivedData/.../checkouts/PhoneNumberKit/...`），
那是随时会被清掉的临时目录。把提取后的子集纳入 git，重新生成才不依赖本机是否装过 Xcode。

## 更新元数据

```bash
# 1. 重新提取（路径取自当前 SPM checkout）
python3 extract_metadata.py \
  ~/Library/Developer/Xcode/DerivedData/EudiReferenceWallet-*/SourcePackages/checkouts/\
PhoneNumberKit/Sources/PhoneNumberKit/Resources/PhoneNumberMetadata.json

# 2. 重新生成仓颉源码
python3 gen_phone_metadata.py

# 3. 跑宿主测试（示例号全量扫描会验证整张表）
cd ../.. && ./run_tests.sh eudi_logic_business
```

更新后请同步 `extract_metadata.py` 里 `_provenance` 的版本号。pre-commit 钩子会跑
`gen_phone_metadata.py --check`，防止生成物与输入漂移。

## 当前版本

PhoneNumberKit 5.0.4（`ab06a8333394f4a4fb6eecca447dae0aa06c1eca`），与 iOS 工程
`Package.resolved` 锁定的版本一致。

## 许可

libphonenumber 元数据来自 Google 的 libphonenumber 项目（Apache License 2.0），
经 PhoneNumberKit（MIT）转为 JSON 分发。此处仅重新打包校验所需的号码模式子集。
