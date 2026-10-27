# Third-Party Notices

EUDI Wallet for HarmonyOS is licensed under the [EUPL-1.2](LICENSE). It builds on,
links against or bundles the third-party components listed below. Each component keeps
its own licence; full licence texts are in [`third_party_licenses/`](third_party_licenses/).

## Upstream reference implementation

| Component | Licence | Notes |
| --- | --- | --- |
| [eudi-app-ios-wallet-ui](https://github.com/eu-digital-identity-wallet/eudi-app-ios-wallet-ui) © European Commission | EUPL-1.2 | The wallet application this port is derived from. Its NOTICE (including the google/identity-credential attribution, Apache-2.0) is reproduced in [`NOTICE`](NOTICE). |

## Cangjie libraries (git submodules under `third_party/`)

HarmonyOS / Cangjie ports of the EUDI Wallet libraries, maintained alongside this
application. Each repository carries its own `LICENSE` and `NOTICE`.

| Path | Repository | Licence | Ported from / modelled on |
| --- | --- | --- | --- |
| `third_party/eudi_lib_cbor` | [eudi-lib-hmos-cbor](https://github.com/CJPLUK/eudi-lib-hmos-cbor) | Apache-2.0 | CBOR wrapper over cbor4cj |
| `third_party/eudi_lib_core_crypto` | [eudi-lib-hmos-core-crypto](https://github.com/CJPLUK/eudi-lib-hmos-core-crypto) | Apache-2.0 | Crypto wrap layer over Cangjie stdx.crypto |
| `third_party/eudi_lib_etsi_1196x2` | [eudi-lib-hmos-etsi-1196x2](https://github.com/CJPLUK/eudi-lib-hmos-etsi-1196x2) | Apache-2.0 | eudi-lib-kmp-etsi-1196x2 (Apache-2.0) |
| `third_party/eudi_lib_jose` | [eudi-lib-hmos-jose](https://github.com/CJPLUK/eudi-lib-hmos-jose) | Apache-2.0 | [JOSESwift](https://github.com/airsidemobile/JOSESwift) (Apache-2.0) |
| `third_party/eudi_lib_mdoc_data_model` | [eudi-lib-hmos-mdoc-data-model](https://github.com/CJPLUK/eudi-lib-hmos-mdoc-data-model) | Apache-2.0 | eudi-lib-ios-iso18013-data-model (Apache-2.0) |
| `third_party/eudi_lib_mdoc_security` | [eudi-lib-hmos-mdoc-security](https://github.com/CJPLUK/eudi-lib-hmos-mdoc-security) | Apache-2.0 | eudi-lib-ios-iso18013-security (Apache-2.0) |
| `third_party/eudi_lib_mdoc_transfer` | [eudi-lib-hmos-mdoc-transfer](https://github.com/CJPLUK/eudi-lib-hmos-mdoc-transfer) | Apache-2.0 | eudi-lib-ios-iso18013-data-transfer (Apache-2.0) |
| `third_party/eudi_lib_openid4vp_vci` | [eudi-lib-hmos-openid4vp-vci](https://github.com/CJPLUK/eudi-lib-hmos-openid4vp-vci) | Apache-2.0 | eudi-lib-ios-openid4vci-swift, eudi-lib-ios-siop-openid4vp-swift (Apache-2.0) |
| `third_party/eudi_lib_rqes` | [eudi-lib-hmos-rqes](https://github.com/CJPLUK/eudi-lib-hmos-rqes) | Apache-2.0 (bundled native library: see below) | eudi-lib-ios-rqes-csc-swift, eudi-lib-ios-rqes-kit, eudi-lib-ios-rqes-ui, eudi-lib-podofo |
| `third_party/eudi_lib_sdjwt` | [eudi-lib-hmos-sdjwt](https://github.com/CJPLUK/eudi-lib-hmos-sdjwt) | Apache-2.0 | eudi-lib-sdjwt-swift (Apache-2.0) |
| `third_party/eudi_lib_statium` | [eudi-lib-hmos-statium](https://github.com/CJPLUK/eudi-lib-hmos-statium) | Apache-2.0 | eudi-lib-ios-statium-swift (Apache-2.0) |
| `third_party/eudi_lib_wallet_kit` | [eudi-lib-hmos-wallet-kit](https://github.com/CJPLUK/eudi-lib-hmos-wallet-kit) | Apache-2.0 | eudi-lib-ios-wallet-kit (Apache-2.0) |
| `third_party/eudi_lib_wallet_storage` | [eudi-lib-hmos-wallet-storage](https://github.com/CJPLUK/eudi-lib-hmos-wallet-storage) | Apache-2.0 | eudi-lib-ios-wallet-storage (Apache-2.0) |
| `third_party/eudi_lib_x509` | [eudi-lib-hmos-x509](https://github.com/CJPLUK/eudi-lib-hmos-x509) | Apache-2.0 | X.509 certificate handling for the wallet |

Fetched by cjpm (not vendored; commit pinned in each `cjpm.lock`):

| Component | Licence | Notes |
| --- | --- | --- |
| [cbor4cj](https://github.com/CJPLUK/cbor4cj) | Apache-2.0 | Fork of [Cangjie-TPC/cbor4cj](https://gitcode.com/Cangjie-TPC/cbor4cj) with build-only fixes |

## Prebuilt native libraries in `entry/libs/`

| File(s) | Component | Licence |
| --- | --- | --- |
| `entry/libs/stdx/*` | [cangjie-stdx](https://github.com/cangjielanguage/cangjie_stdx) 1.1.3.1 | Apache-2.0 |
| `entry/libs/arm64-v8a/libcrypto_openssl.z.so`, `libssl_openssl.z.so` | [OpenSSL](https://www.openssl.org/) 3.0.9 | Apache-2.0 |
| `entry/libs/arm64-v8a/libc++_shared.so` | LLVM libc++ (from the OpenHarmony NDK) | Apache-2.0 WITH LLVM-exception |
| `entry/libs/arm64-v8a/libsecurec.so`, `entry/libs/stdx/libsecurec.so`, `entry/libs/stdx/libboundscheck.so` | [bounds_checking_function](https://gitee.com/openeuler/libboundscheck) | MulanPSL-2.0 |
| `entry/libs/arm64-v8a/libpodofo_rqes.so` | RQES signing engine, see next table | Mixed, see below |

`libpodofo_rqes.so` statically links the following components. The build recipes and
rebuild instructions are in the `eudi_lib_rqes` submodule (`native/recipes/`,
`native/REBUILD.md`), which lets you rebuild and relink the library as permitted by the
LGPL.

| Component | Version | Licence |
| --- | --- | --- |
| [PoDoFo](https://github.com/eu-digital-identity-wallet/eudi-lib-podofo) (EUDI fork) | 0.3.8 | LGPL-2.0-or-later |
| [OpenSSL](https://www.openssl.org/) | 1.1.1u | OpenSSL License and Original SSLeay License |
| [FreeType](https://freetype.org/) | 2.13.0 | FreeType License (FTL), chosen over GPL-2.0 |
| [libxml2](https://github.com/GNOME/libxml2) | 2.11.3 | MIT |
| [libpng](http://www.libpng.org/pub/png/libpng.html) | 1.6.39 | PNG Reference Library License version 2 |
| zlib | 1.3.1 | zlib License |
| podofo_ffi bridge (`eudi_lib_rqes/native/bridge`) | — | Apache-2.0 |

## Data

| Component | Licence | Notes |
| --- | --- | --- |
| [libphonenumber](https://github.com/google/libphonenumber) metadata | Apache-2.0 | Subset under `third_party/libphonenumber/`, distributed via [PhoneNumberKit](https://github.com/marmelroy/PhoneNumberKit) 5.0.4 (MIT); see its README |

## ohpm packages

| Package | Licence |
| --- | --- |
| `@cangjie/cjhybridcomponent` 1.0.0 | Apache-2.0 |
| `@ohos/hypium` 1.0.25 (dev) | Apache-2.0 |
| `@ohos/hamock` 1.0.0 (dev) | Apache-2.0 |

## Licence texts

| File | Used by |
| --- | --- |
| [`Apache-2.0.txt`](third_party_licenses/Apache-2.0.txt) | Cangjie libraries, cbor4cj, cangjie-stdx, OpenSSL 3.x, libc++, libphonenumber, ohpm packages, google/identity-credential |
| [`LLVM-exception.txt`](third_party_licenses/LLVM-exception.txt) | libc++ |
| [`MulanPSL-2.0.txt`](third_party_licenses/MulanPSL-2.0.txt) | bounds_checking_function |
| [`LGPL-2.0-or-later.txt`](third_party_licenses/LGPL-2.0-or-later.txt) | PoDoFo |
| [`OpenSSL.txt`](third_party_licenses/OpenSSL.txt) | OpenSSL 1.1.1u (in libpodofo_rqes.so) |
| [`FTL.txt`](third_party_licenses/FTL.txt) | FreeType |
| [`MIT.txt`](third_party_licenses/MIT.txt) | libxml2, PhoneNumberKit |
| [`libpng-2.0.txt`](third_party_licenses/libpng-2.0.txt) | libpng |
| [`Zlib.txt`](third_party_licenses/Zlib.txt) | zlib |
