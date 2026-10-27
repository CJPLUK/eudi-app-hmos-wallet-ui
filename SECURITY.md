# Security Policy / 安全政策

EUDI Wallet for HarmonyOS handles digital identity credentials, PINs, biometric
authentication and cryptographic keys. We take security issues seriously and appreciate
responsible disclosure.

本项目处理数字身份凭证、PIN、生物识别与加密密钥等敏感数据，我们非常重视安全问题，感谢负责任的漏洞披露。

## Supported Versions / 受支持的版本

The project is in an initial development release. Security fixes are made on the
**default branch only**; there is no long-term support for older tags.

| Version | Supported |
| --- | --- |
| Default branch (latest) | ✅ |
| Older tags | ❌ |

## Reporting a Vulnerability / 报告漏洞

**Do not report security vulnerabilities through public issues or pull requests.**

Use GitHub's private vulnerability reporting instead: open the repository's
**Security** tab and choose **Report a vulnerability**.

请勿通过公开 Issue / PR 报告安全漏洞，请使用仓库 **Security → Report a vulnerability** 私密上报。

Please include, where possible:

- the affected module / file and commit;
- steps to reproduce, or a proof of concept;
- the impact (which data can be disclosed or tampered with, whether credentials or keys are affected);
- a suggested fix, if you have one.

## Our Commitment / 响应流程

- **Acknowledge** the report as soon as possible.
- **Assess and fix**: verify, rate severity and develop a fix; high-severity issues first.
- **Coordinated disclosure**: details are published after the fix lands, crediting the
  reporter unless they prefer to stay anonymous.

## Scope Notes / 范围说明

- Much of the cryptographic and protocol logic lives in the `third_party/eudi_lib_*`
  submodules (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). Reports against those
  libraries are welcome here; we will route them to the right repository.
- Issues in the upstream EU Digital Identity Wallet reference implementations should be
  reported to the respective
  [eu-digital-identity-wallet](https://github.com/eu-digital-identity-wallet) repositories.

## License / 许可

This project is licensed under the **EUPL-1.2**; see [LICENSE](LICENSE).
