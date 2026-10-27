# EUDI Wallet for HarmonyOS (Cangjie) · Test Report

[中文](README.md) | English

| Item | Content |
|---|---|
| Document type | Test Completion Report (structured after ISO/IEC/IEEE 29119-3) |
| Test item | `eudi-app-hmos-wallet-ui`: HarmonyOS port (Cangjie + ArkUI) of the EU Digital Identity Wallet reference app, bundle `eu.europa.ec.euidi` |
| Reference | iOS reference implementation [eudi-app-ios-wallet-ui](https://github.com/eu-digital-identity-wallet/eudi-app-ios-wallet-ui) (source pinned at `95b71766`, 2026-09-01), 368 XCTest cases |
| Scored build | `0e1f5c5` (the 14 `third_party/eudi_lib_*` submodules at the commits pinned there) |
| Report date | 2026-10-27 |
| Raw records | [records/](records/) (host and device test output, environment) |

## 1. Summary

| Metric | Value | Definition |
|---|---|---|
| Host unit tests | **131 / 131 passed** | `./run_tests.sh all`, counted in `@TestCase`s; the logic modules that run on macOS |
| Device unit tests | **630 passed / 0 failed / 0 errors** | `./run_device_tests.sh`, `aa test` on a phone, counted in executed assertions |
| iOS case parity | **90.7%** (330 / 364) | iOS cases migrated and passing ÷ (368 iOS cases − 4 not applicable); the 34 unmigrated cases stay in the denominator |
| End-to-end (scored build) | 1 run, 1 passed | Cold start and first PIN setup (E-01) |
| End-to-end (earlier builds) | 9 passed | Issuance, remote presentation, QR scanning, RQES signing, trust-chain probes; run on internal builds before the open-source release and **not re-run on the scored build** |
| End-to-end (not tested) | 5 | BLE proximity against a real reader, DCQL minimal disclosure, online SD-JWT without x5c, HUKS non-exportability, biometric unlock on a phone |

**Conclusion**:
- **Unit test level: pass.** Host and device unit tests all pass on the scored build. Against the iOS cases one by one, the only unmigrated tests are the 34 cases of the registration-trust UI model (section 7.3).
- **End-to-end level: partially verified.** The core flows (issuance, remote presentation, RQES signing) have run against real EUDI services on earlier builds, but only a cold-start smoke test ran on the scored build, and 5 items, including BLE proximity radio and DCQL minimal disclosure, have never been verified. **This report does not support a claim that the wallet has passed end-to-end acceptance.**

## 2. Method

### 2.1 Basis

- **ISO/IEC/IEEE 29119-3** (test documentation): organised by the elements of a test completion report, namely scope, method, environment, results, deviations and residual risks.
- **ISO/IEC 25010 functional suitability**: functional completeness and correctness, i.e. whether the HarmonyOS app can do what the iOS reference does, with the same results.
- **Presentation**: modelled on the Android CTS result summary and the OpenHarmony XTS summary_report: totals first, then per module, then failure and not-tested details.

### 2.2 Test levels and case sources

| Level | Runs on | Case source | Dependencies |
|---|---|---|---|
| L1 host unit tests | macOS, `cjpm test` | XCTest cases of the iOS `logic-*` modules, ported **method for method** as `@TestCase`s | Real validators / PBKDF2; hand-written fake keychain |
| L2 device unit tests | HarmonyOS phone, ohosTest HAP (`aa test`) | XCTest cases of the iOS `feature-*` and `logic-ui` modules, ported **suite by suite**: one iOS method maps to several assertions | Interactors, view models and coordinators are real code; the wallet engine and remote / proximity sessions are hand-written fakes |
| L3 end-to-end | HarmonyOS phone or emulator + real EUDI services | User-visible main flows: issuance, presentation, signing, scanning, trust chain | Real issuer / verifier / QTSP (DEV or DEMO environments) |

**iOS parity rule**: every iOS `func test*` has a row in the parity ledger and must either map to Cangjie assertions (migrated) or carry a reason (not applicable); "expected to fail" is never a reason to skip. Only two kinds of case may be marked not applicable: the empty template Xcode generates, and states that exist only in the iOS architecture (section 5.1).

### 2.3 Execution and verdicts

1. **Host**: `./run_tests.sh all` runs `eudi_logic_business`, `eudi_logic_api`, `eudi_logic_authentication` and `eudi_logic_storage`, and reads the `PASSED / FAILED / ERROR` summary of `cjpm test`.
2. **Device**: `./run_device_tests.sh` builds the app HAP and the ohosTest HAP, installs both on the phone and runs `aa test`. The entry point `runAllUnitSuites()` runs 8 suites and prints `CJ_TEST_SUMMARY: passed=… failed=… error=…`. Only `failed=0` and `error=0` counts as a pass.
3. **End-to-end**: the user path is driven on a phone; evidence is screenshots, app logs (hilog) and the peer service's feedback (e.g. the verifier front end showing the attributes it received).
4. **Test isolation**: `libeudi_unit_tests.so` is packaged only into the ohosTest HAP; the app HAP contains no test code.

### 2.4 Verdicts

| Verdict | Meaning | Counts as pass |
|---|---|---|
| Passed | Run on the scored build, all criteria met | Yes |
| Passed after fix | Failed on an earlier build in this round, passed on the scored build after a fix (section 7.1) | Yes |
| Earlier-build evidence | Run and passed on an internal build before the open-source release, with development records or logs; not re-run on the scored build | Reported separately, not in this build's pass rate |
| Not tested | Never run: peer device missing, server-side unsupported or not yet scheduled | No |
| Not migrated | The iOS case exists; no Cangjie assertion covers it yet | No (stays in the parity denominator) |
| Not applicable | The iOS case has no behaviour to port, or tests a state that cannot exist in the Cangjie design | Excluded from the parity denominator |

## 3. Environment

| Item | Under test | Reference |
|---|---|---|
| Device | HUAWEI Mate 60 Pro (ALN-AL80), physical | iPhone 17 Pro simulator (earlier rounds) |
| OS | HarmonyOS `6.1.0.125`, API 24 | iOS simulator (version in the earlier records) |
| App | `eu.europa.ec.euidi`, scored build `0e1f5c5`, debug signing | `eudi-app-ios-wallet-ui` `95b71766` |
| Toolchain | DevEco Studio 6.1.1, Cangjie 1.1.3 (cjnative), hvigor, hdc 3.2.0d | Xcode |
| Host | macOS 26.6.2 (arm64) | Same |
| Services | EUDI DEV / DEMO: `issuer.eudiw.dev`, `dev.verifier.eudiw.dev`, `verifier-backend.eudiw.dev`, `walletcentric.signer.eudiw.dev` | Same |

Host tests need `export DEVELOPER_DIR=/Library/Developer/CommandLineTools`: `libSystem.tbd` in the macOS 27 SDK that ships with Xcode lists the `arm64e.x1` architecture, which the Cangjie linker cannot parse (section 6.3).

## 4. Results overview

### 4.1 By test level

| Level | Build | Cases / assertions | Passed | Failed | Errors / not tested | Verdict |
|---|---|---|---|---|---|---|
| L1 host unit tests | `0e1f5c5` | 131 cases | 131 | 0 | 0 | Passed |
| L2 device unit tests | `0e1f5c5` | 630 assertions | 630 | 0 | 0 | Passed |
| L3 end-to-end (this build) | `0e1f5c5` | 1 | 1 | 0 | 0 | Passed |
| L3 end-to-end (earlier builds) | Internal builds, see section 8 | 9 | 9 | 0 | 0 | Earlier-build evidence |
| L3 end-to-end (not tested) | — | 5 | — | — | 5 | Not tested |

### 4.2 By feature area (iOS case parity)

| Area | iOS cases | Migrated | N/A | Not migrated | Cangjie side | Parity |
|---|---|---|---|---|---|---|
| [feature-startup](#startup) startup routing | 4 | 4 | 0 | 0 | device `startup`, 12 | 100% |
| [feature-common](#common) PIN / biometrics / scanning / issuer trust / registration trust | 80 | 46 | 0 | 34 | device `featureCommon` 64, `errorIssuerTrust` 14 | 57.5% |
| [feature-issuance](#issuance) add document / document offer | 45 | 45 | 0 | 0 | device `featureIssuance`, 103 | 100% |
| [feature-dashboard](#dashboard) home / documents / transactions / settings | 78 | 78 | 0 | 0 | device `featureDashboard`, 222 | 100% |
| [feature-presentation](#presentation) remote presentation | 21 | 20 | 1 | 0 | device `featurePresentation`, 72 | 100% |
| [feature-proximity](#proximity) proximity presentation | 22 | 20 | 2 | 0 | device `featureProximity`, 133 | 100% |
| [logic-ui](#logicui) deep-link routing | 21 | 21 | 0 | 0 | device `deepLink`, 56 | 100% |
| [logic-authentication](#auth) PIN storage / throttling / biometry controller | 53 | 53 | 0 | 0 | host, 57 cases | 100% |
| [logic-business](#business) filter / form validation | 43 | 43 | 0 | 0 | host, 68 cases | 100% |
| logic-api | 1 | 0 | 1 | 0 | — | — |
| **Total** | **368** | **330** | **4** | **34** | device 630 (runtime) / host 131 | **90.7%** |

Notes:
- Device-side numbers are assertion call sites in each suite's source (a static count, 676 in total). 630 run at runtime; the difference is failure branches of `if / else` guards that the normal path never takes.
- The host also runs 6 `eudi_logic_storage` cases with no iOS counterpart, which are not counted for parity. Besides the 43 iOS cases, the 68 `eudi_logic_business` cases cover Cangjie-side paths for configuration, preferences, date and string utilities and phone-number metadata.

## 5. Results and evidence by feature

### 5.1 Unit tests

<a id="startup"></a>
**feature-startup**: all 4 `TestStartupInteractor` cases migrated, covering routing on first launch, with a PIN set, and with or without documents.

<a id="common"></a>
**feature-common**:

| iOS test class | Cases | Verdict | Notes |
|---|---|---|---|
| TestBiometryInteractor | 22 | Migrated · passed | Includes the error channel after the real-biometrics port (`biometryError`, section 7.1) |
| TestQuickPinInteractor | 11 | Migrated · passed | |
| TestScannerInteractor | 3 | Migrated · passed | |
| TestErrorIssuerTrust | 10 | Migrated · passed | Error classification for untrusted issuers |
| TestRelyingPartyRegistrationUiModel | 17 | **Not migrated** | Registration-trust UI model, see section 7.3 |
| TestPresentationPolicyViolationOverasking | 10 | **Not migrated** | Same |
| TestPolicyPurposeLocalized | 4 | **Not migrated** | Same |
| TestRequestDataUiModelSelection | 3 | **Not migrated** | Same |

<a id="issuance"></a>
**feature-issuance**: all 25 `TestAddDocumentInteractor` and 20 `TestDocumentOfferInteractor` cases migrated, including the 5 issuer-registration blocking cases iOS added in 2026-09 (all issuers untrusted, partial failure, registration blocked, registration does not vouch, offer blocked).

<a id="dashboard"></a>
**feature-dashboard**: all 78 cases of the 7 test classes migrated; the most finely split suite (222 assertions), including how the batch-issuance counter switch affects the document card badge (section 7.1).

<a id="presentation"></a>
**feature-presentation**: 20 cases migrated, 1 not applicable:

| iOS case | Verdict | Reason |
|---|---|---|
| `testOnSendResponse_WhenSecondGetActiveRemoteCoordinatorThrows_ThenReturnsFailure` | Not applicable | iOS tests its own `SessionCoordinatorHolder` failing on a second coordinator lookup; the Cangjie port injects the coordinator directly, so the state cannot exist |

<a id="proximity"></a>
**feature-proximity**: 20 cases migrated, 2 not applicable for the same reason (`testOnResponsePrepare_…GetActiveProximityCoordinatorThrowsError…`, `testOnSendResponse_…GetActiveProximityCoordinatorThrowsError…`). The device suite also drives the real proximity coordinator through the full poweredOn → qrEngagementReady → connected → started → requestReceived → userSelected → responseSent → disconnected sequence, and covers BLE availability mapping, stop on cancel and radio-off errors.

<a id="logicui"></a>
**logic-ui**: all 21 `TestDeepLinkController` cases migrated, including the `openid4vp`, `openid-credential-offer` and `rqes` schemes.

<a id="auth"></a>
**logic-authentication** (host): 53 cases of 5 test classes ported **method for method**, plus 2 PIN PBKDF2 golden-vector cases (same salt, same PIN, 210000 rounds, compared byte for byte with the iOS CommonCrypto output) and 2 Cangjie-only paths: 57 cases in total.

<a id="business"></a>
**logic-business** (host): all 23 `TestFilterValidator` and 20 `TestFormValidator` cases migrated.

### 5.2 End-to-end

| ID | Scenario | Verdict | Build / date | Evidence | Notes |
|---|---|---|---|---|---|
| E-01 | Cold start → set and confirm a 6-digit PIN → home | Passed | `0e1f5c5` · 2026-10-27 | [evidence/E-01](evidence/E-01/) | Fresh install; the process never restarted, no crash records; [run log](evidence/E-01/run_log.md) |
| E-02 | OpenID4VCI authorization-code issuance of a PID (`issuer.eudiw.dev`), side by side with iOS | Earlier-build evidence | Internal build · 2026-07 | [Dual-platform demo video](../../dual-platform-issuance-demo.mp4) | Set PIN → add document → authorize → issued → check stored data |
| E-03 | OpenID4VCI issuance of Health ID (MSO mdoc) with the holder key in HUKS | Earlier-build evidence | Internal build · 2026-08-26 | Development record (hilog) | `HuksSecureArea.createKeyBatch` → `issue … via SecureArea` → stored; no software-key signing seen |
| E-04 | OpenID4VP remote presentation of EHIC to the DEV verifier, attributes checked in its front end | Earlier-build evidence | Internal build · 2026-07-06 · emulator | Development record | Trusted reader badge → Share → PIN → success screen; the verifier front end decoded `issuing_authority` and other attributes |
| E-05 | OpenID4VP remote presentation of Health ID, DeviceAuth signed by HUKS | Earlier-build evidence | Internal build · 2026-08-26 | Development record (hilog) | `DeviceAuth signing with SecureArea` → `direct_post` HTTP 200 → success screen |
| E-06 | Camera QR scanning (HMS Scan Kit) into issuance / presentation | Earlier-build evidence | Internal build · 2026-08 | User confirmation | |
| E-07 | RQES remote signing, full flow | Earlier-build evidence | Internal build · 2026-09-06 | Development record | Pick document → pick QTSP → OAuth in the system browser (back via `rqes://oauth/callback`) → pick certificate → PIN → signed |
| E-08 | Trust anchors: DEMO LoTE loaded | Earlier-build evidence | Internal build · 2026-08-28 | Development record (hilog) | `LOTE: pid=7 wrpac=7` |
| E-09 | Proximity reader certificate not trusted → fail closed | Earlier-build evidence | Internal build · 2026-08-28 | Development record (hilog) | Synthetic DeviceRequest: `reader x5c not trusted (fail-closed)` |
| E-10 | SD-JWT without x5c verified via JWKS (synthetic issuer) | Earlier-build evidence | Internal build · 2026-08-28 | Development record (hilog) | Synthetic probe `SDJWT-JWKS probe ok`; for the online case see E-12 |
| E-11 | BLE proximity presentation (ISO 18013-5) against a real reader | Not tested | — | — | No peer reader; the code path and device unit tests are in place |
| E-12 | Online SD-JWT without x5c verified via the issuer's JWKS | Not tested | — | — | The DEMO issuer's `/.well-known/jwt-vc-issuer` returns 400 |
| E-13 | OpenID4VP DCQL minimal disclosure (request only `age_over_18`) | Not tested | — | — | The iOS app has no such test either |
| E-14 | Holder keys in HUKS are non-exportable | Not tested | — | — | The code requests never-export with a fallback; not measured |
| E-15 | Biometric unlock on a phone | Not tested | — | — | UserAuthenticationKit is wired in; no device record to cite |

E-01 evidence (scored build, cold start after a fresh install):

<img src="evidence/E-01/01_cold_start.jpeg" width="180" alt="E-01 cold start"> <img src="evidence/E-01/02_confirm_pin.jpeg" width="180" alt="E-01 confirm PIN"> <img src="evidence/E-01/03_wallet_secured.jpeg" width="180" alt="E-01 wallet secured"> <img src="evidence/E-01/04_home.jpeg" width="180" alt="E-01 home">

## 6. Cangjie capability limits

### 6.1 Conclusion

This chapter answers which wallet features can only be built through an ArkTS bridge because the Cangjie SDK 6.1 lacks the interface. The basis is the bridge code and its comments (`entry/src/main/ets/pages/Index.ets`) and the development records.

- **Features Cangjie cannot do at all, with no alternative path: 0.**
- **No Cangjie interface, bridged through ArkTS: 4**, all in use (6.2).
- The shared cost of bridging: a retained JS function cannot be called from a Cangjie worker thread, so commands are queued as strings and run on the ArkTS event loop; the platform call blocks a worker, never the UI thread.

### 6.2 Features limited by Cangjie, bridged

| Item | User-visible feature | Cangjie gap | Status |
|---|---|---|---|
| B1 | Biometric unlock, the biometrics switch in Settings, opening the system biometrics settings | No `UserAuthenticationKit` (userIAM) binding | ArkTS bridge; the device capability is probed before start-up and published to the Cangjie controller; the settings page opens via ArkTS `settings.openBiometricsSettingsPage` |
| B2 | Camera QR scanning (issuance offers, presentation requests) | HMS Scan Kit has no Cangjie binding | ArkTS bridge; `startScanForResult` must be called in an ArkUI page context |
| B3 | Picking the PDF to sign in RQES | `DocumentViewPicker` has no Cangjie binding | ArkTS bridge; the file is copied into the app cache and its path handed to Cangjie, keeping the original file name |
| B4 | GATT peripheral and Bluetooth adapter state for BLE proximity | The Cangjie ConnectivityKit binding refuses `addService` on HarmonyOS 6.1.1; no `ohos.bluetooth.access` binding | ArkTS bridge; radio state comes from the adapter state; GATT notify / stop operations are drained on the ArkTS event loop |

### 6.3 Cangjie development notes (workarounds exist, not capability gaps)

| Symptom | Consequence | Handling |
|---|---|---|
| `match` is not allowed inside `@Builder` / `build` | Compile error | Use `if (opt.isSome()) { … opt.getOrThrow() … }` |
| hvigor compiles `@r` macros against each module's own resource table | A direct dependency between feature modules expands resource macros against an empty table and fails | Inject through a launcher seam (e.g. `RqesSigningLauncher`) at the `entry` composition root |
| An escaping closure in a constructor cannot capture `this` | Compile error | Copy into a local `let` first and capture the local |
| Code using device-only OHOS packages placed in a host-runnable module | The host unit tests stop compiling altogether | Keep the device implementation in `entry` and only the interface in the logic module (section 7.1) |
| Two concurrent hvigor builds of one project, or app HAP then test HAP | The incremental module cache is corrupted; a bogus `Out of memory` within seconds | Delete `Modules/<module>/build` and re-run |
| The macOS SDK in Xcode 27 (`libSystem.tbd` lists `arm64e.x1`) | The Cangjie linker cannot parse it; host tests fail to link | `export DEVELOPER_DIR=/Library/Developer/CommandLineTools` |

## 7. Defects, fixes and residual risks

### 7.1 Fixed in this round (failed on an earlier build → passed on the scored build)

| Issue | Failure | Fix | Scored build |
|---|---|---|---|
| Host unit tests do not compile | `eudi_logic_business` imported the device-only `ohos.ability_access_ctrl`; all 4 host modules failed to compile | Moved `ReachabilityControllerImpl` (Bluetooth permission prompt, system settings link) to `entry/src/main/cangjie/reachability_impl.cj`, logic unchanged | 131 / 131 |
| `biometry.authenticate_deniedAccess_pinError` | The assertion checked `pinError`; the error actually goes to `biometryError` (the iOS alert channel) | Assert on `biometryError` | Passed |
| `settings.openBiometrySettings_availabilityGate_available` | The fake biometry controller had no `biometryType` | Set `BiometryType.FaceID` | Passed |
| `proximity.connectionVm_initialize_receivesRequest` | `receiveRequest` runs on an async worker; the assertion ran before the call | Wait for the call before asserting | Passed |
| `docTab.usageBadge_shownWhenBatchCounterOn` | The fixture was a `FakeDocClaims`; production code builds the counter badge only for an `IssuedDocument` | Use an `IssuedDocument` fixture | Passed |
| Issuance log leaked sensitive values | `eudi_lib_wallet_kit` logged the authorization code, state and PKCE verifier in clear text on resume | Log only the code length and whether the state matches | Device unit tests passed; E-01 passed |

The 4 device-case fixes change only test code, not production code: `3773356` gave 626 passed / 4 failed, the fixed build 630 / 0 / 0.

### 7.2 RQES UI gaps closed in earlier rounds

A screen-by-screen iOS / HarmonyOS comparison of RQES on 2026-09-04 recorded 9 gaps (G1–G9). Checked against the code of the scored build:

| Gap | Content | Status |
|---|---|---|
| G1 | Signed screen lacked the "Data shared" structure and the close confirmation | Implemented (`signed_document_view.cj`) |
| G2 | Data-sharing request lacked single choice between credential combinations | Implemented (`e95848e`, combination request model and UI) |
| G4a | Closing document selection lacked the "Cancel signing process?" confirmation | Implemented (`document_selection_view.cj`) |
| G4b | A temporary file name was shown instead of the original | Implemented (the file-picker bridge keeps the original name) |
| G8 | After sharing, the flow stalled and Done did not resume signing | Partial: Done resumes the flow (`165ce75`); iOS resumes automatically, HarmonyOS still needs Done |
| G9 | Step texts differed from iOS | Implemented (`rqes_view_models.cj`) |
| G3 / G4c / G5 / G6 / G7 | Title alignment, step-done state, back button style, checkmark colour, verifier name | Not re-checked one by one |

These are code-level findings; **RQES was not re-run on a phone with the scored build.**

### 7.3 Residual risks

| Category | Description |
|---|---|
| End-to-end not re-run on the scored build | E-02 to E-10 ran on internal builds before the open-source release; the scored build only had the cold-start smoke test (E-01). An end-to-end phone round of issuance, presentation and RQES on `0e1f5c5` is recommended |
| Registration-trust unit tests not migrated | The 34 cases iOS added in 2026-09 (`TestRelyingPartyRegistrationUiModel` etc.) have no counterpart in this repository. The production code is ported (`registration_ui_model.cj`) but has no unit-test coverage |
| BLE proximity radio | The code path is complete and the device tests drive the real coordinator, but it has never paired with a real reader (e.g. `eudi-app-multiplatform-verifier-ui`); advertising discovery, CCCD subscription, notify back-pressure and ReaderAuth against a real certificate chain are unverified |
| Unit tests rely on fakes | In the device unit tests the wallet engine and the remote / proximity sessions are fakes; all-green shows that interactor and view-model logic is correct, not that the real protocols are |
| Security properties | Whether HUKS keys are really non-exportable or held in a TEE is untested; there is no key-attestation chain equivalent to the iOS Secure Enclave |
| iOS reference not re-run | iOS XCTest last ran locally on 2026-08-24 (329 / 0, when iOS had 329 cases); the iOS side of the 368 cases was not re-run this round |
| OpenSSL version | The OpenSSL 1.1.1u statically linked into the RQES signing engine `libpodofo_rqes.so` is end of life |
| Coverage and performance | No code coverage collected, no performance benchmarks |

## 8. Builds and rounds

| Round | Build | Scope | Result |
|---|---|---|---|
| R1 | `3773356` | Host + device unit tests | Host 131 / 131; device 626 passed / 4 failed / 0 errors |
| R2 | `a23e8dc` | Device unit tests (after the 4 test fixes) | 630 / 0 / 0 |
| **R3 (scored)** | **`0e1f5c5`** | Fresh `clone --recursive` from GitHub; host + device unit tests + E-01 | Host 131 / 131; device 630 / 0 / 0; E-01 passed |
| H1 | Internal build · 2026-07 | E-02 (dual-platform issuance demo), E-04 (remote presentation, emulator) | Passed |
| H2 | Internal build · 2026-08-24 / 25 | Device unit tests ×4, iOS XCTest | Device 506 / 0 / 0 (four identical runs); iOS 329 / 0 |
| H3 | Internal build · 2026-08-26 / 28 | E-03, E-05, E-08, E-09, E-10 | Passed |
| H4 | Internal build · 2026-09-06 | E-07 (full RQES flow) | Passed |

Between R1 and R3 the only code differences are the 4 test fixes of section 7.1; R3 has the same code as R2 (only documentation and commit history differ).

## 9. References

- ISO/IEC/IEEE 29119-3:2021, *Software and systems engineering — Software testing — Part 3: Test documentation*: <https://www.iso.org/standard/79429.html>
- ISO/IEC 25010:2023, *Systems and software Quality Requirements and Evaluation (SQuaRE) — Product quality model*: <https://www.iso.org/standard/78176.html>
- Android Compatibility Test Suite — Interpret CTS results: <https://source.android.com/docs/compatibility/cts/interpret>
- OpenHarmony XTS test subsystem: <https://gitee.com/openharmony/xts_acts>
- iOS reference implementation: <https://github.com/eu-digital-identity-wallet/eudi-app-ios-wallet-ui>
- Raw output and environment for this round: [records/](records/)
