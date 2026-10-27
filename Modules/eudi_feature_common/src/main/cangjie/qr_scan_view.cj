/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Scanner/ScannerView.swift + ScannerViewModel.swift) to
 * Cangjie ArkUI.
 *
 * iOS scans with the camera (CodeScanner). The HarmonyOS emulator has no
 * camera and this SDK generation has no Cangjie scanKit binding (old-project
 * D-013 evidence: kit.CameraKit dlopen-crashes at startup), so this screen
 * ships the QA'd manual-input fallback: the user pastes/types the URL read
 * from the QR code, the value is validated through the delivered
 * eudi_logic_business FormValidator with the exact iOS rule
 * (`Rule.ValidateUrl(errorMessage:"", shouldValidateHost:false,
 * shouldValidatePath:false)` — schema and query stay validated), and a valid
 * value fires `onScanResult`. Failures count up; past
 * MAX_ALLOWED_FAILED_SCANS (5) the informative text appears (iOS
 * `showInformativeText`). A device track replaces the preview frame with
 * the real camera feed and funnels detections into the same `submitResult`
 * entry point.
 *
 * Plain @Component — composition root owns navigation chrome.
 */
package eudi_feature_common

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.device_info.DeviceInfo
import eudi_logic_ui.*
import eudi_logic_business.{Rule, FormInput, ValidatableForm, FormValidator, FormValidatorImpl}
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * QR scan screen (fc_common_shared_screens exposed symbol `QRScanView`).
 *
 * Injection points (S-017):
 *  - `config`: ScannerUiConfig — presentation or issuing flow (titles,
 *    captions and downstream navigation payload).
 *  - `onScanResult`: fires with the validated URL string; the hosting flow
 *    routes it (iOS onScanResultValidated → presentationRequest /
 *    credentialOfferRequest push).
 */
@Component
public class QRScanView {
    public var config: ScannerUiConfig = ScannerUiConfig(flow: ScannerFlow.FlowPresentation)
    public var onScanResult: (String) -> Unit = { _ => }
    /** Leading back action (iOS scanner toolbar chevron.left → router.pop). The
     *  hosting destination owns the router, so it injects the pop handler. */
    public var onClose: () -> Unit = { => }

    private let validator: FormValidator = FormValidatorImpl()
    /** Mirrors iOS ScannerState.MAX_ALLOWED_FAILED_SCANS. */
    private let maxAllowedFailedScans: Int64 = 5

    @State
    var manualInput: String = ""
    @State
    var errorText: String = ""
    @State
    var failedScanAttempts: Int64 = 0
    @State
    var showInformativeText: Bool = false
    @State
    var allowScanning: Bool = true
    /** Emulator only: reveal the paste-the-URL fallback after "Select a custom
     *  image" is tapped (this SDK has no photo-picker + QR-decode binding). */
    @State
    var showManualInput: Bool = false
    /** Device: set when Scan Kit could not be opened, so the manual URL entry is
     *  offered instead of leaving the user on a dead screen. */
    @State
    var cameraUnavailable: Bool = false

    /**
     * Opens the HMS Scan Kit camera scanner through the ArkTS bridge and funnels
     * the decoded text into the same `submitResult` the manual path uses, so the
     * iOS validation + failed-attempt rules apply identically to both.
     *
     * Returning false means no launcher was installed (Scan Kit unavailable, or
     * the ArkTS side never registered) — fall back to manual entry.
     */
    private func startCameraScan(): Unit {
        this.allowScanning = true
        let started = ScanBridge.requestScan({
            text => this.submitResult(text)
        })
        if (!started) {
            this.cameraUnavailable = true
            this.showManualInput = true
        }
    }

    protected override func aboutToAppear(): Unit {
        // Mirrors iOS ScannerView, which starts the camera as soon as the screen
        // appears rather than waiting for a tap.
        if (!this.isEmulator() && ScanBridge.isAvailable()) {
            this.startCameraScan()
        }
    }

    private func screenTitle(): String {
        LocalizableManager.get(this.config.flow.title())
    }

    private func screenCaption(): String {
        LocalizableManager.get(this.config.flow.caption())
    }

    private func informativeText(): String {
        LocalizableManager.get(this.config.flow.informativeText())
    }

    /**
     * True when running on the HarmonyOS emulator (no camera / no scanKit binding).
     * The emulator reports `productModel == "emulator"`. On the emulator we keep the
     * paste-the-URL + "Scan QR" manual fallback; on a real device we show the
     * camera-first layout (mirrors iOS, which drives the scan from the camera).
     */
    private func isEmulator(): Bool {
        DeviceInfo.productModel.contains("emulator") || DeviceInfo.productModel.contains("Emulator")
    }

    /**
     * Exact iOS validation rule: URL with scheme+query required, host/path
     * not enforced (deep links like `openid4vp://...?...` must pass).
     */
    private func isValidScanResult(value: String): Bool {
        let form = ValidatableForm(
            [
                FormInput(
                    [Rule.ValidateUrl("", false, true, true, false)],
                    value
                )
            ]
        )
        return this.validator.validateForm(form).isValid
    }

    /**
     * Single submission entry point (manual fallback now, camera detections
     * on device later). Mirrors iOS `onResult`: valid → hand off; invalid →
     * count the failure and show the informative text past the cap.
     */
    private func submitResult(scanResult: String): Unit {
        if (!this.allowScanning) {
            return
        }
        this.allowScanning = false
        if (this.isValidScanResult(scanResult)) {
            this.errorText = ""
            // Keep allowScanning=false: the TextInput's onSubmit and the
            // Scan-QR button can BOTH fire for one entry, which pushed two
            // DocumentOffer pages (the first flashed an error, the second
            // rendered over it). iOS stops the scanner on first result too;
            // the @State resets when the scanner page is rebuilt.
            this.onScanResult(scanResult)
        } else {
            this.failedScanAttempts += 1
            this.showInformativeText = this.failedScanAttempts > this.maxAllowedFailedScans
            this.errorText = LocalizableManager.get(LocalizableStringKey.cameraError)
            this.allowScanning = true
        }
    }

    private func handleInputChange(value: String): Unit {
        this.manualInput = value
        if (!this.errorText.isEmpty()) {
            this.errorText = ""
        }
    }

    private func hasError(): Bool {
        !this.errorText.isEmpty()
    }

    /**
     * Nav bar mirroring the iOS scanner toolbar: leading back chevron
     * (chevron.left → onClose/pop) + centered title, in the shared circular-chip
     * style. iOS has no trailing action here.
     */
    @Builder
    private func navBar() {
        Stack(alignContent: Alignment.Center) {
            // Flow-specific title (iOS ScannerView navigationTitle = flow.title):
            // presentation → "Authenticate my identity", issuing → "Scan QR".
            Text(this.screenTitle())
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            Row {
                Row {
                    AppIcon(
                        token: ThemeManager.shared.image.chevronLeft,
                        size: 25.0,
                        color: uiColor(ThemeManager.shared.color.primaryLabel)
                    )
                }
                .width(40.0)
                .height(40.0)
                .justifyContent(FlexAlign.Center)
                .borderRadius(20.0)
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
                .onClick({ _ => this.onClose() })
                Row {}.layoutWeight(1)
                Row {}.width(40.0).height(40.0)
            }
            .width(100.percent)
            .alignItems(VerticalAlign.Center)
        }
        .width(100.percent)
        .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
    }

    public func build() {
        Column(space: SPACING_MEDIUM) {
            this.navBar()
            Column(space: SPACING_MEDIUM_LARGE) {
            // Caption below the title (iOS ContentCaptionView: primaryLabel, bodyLarge).
            Text(this.screenCaption())
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .width(100.percent)
                .textAlign(TextAlign.Start)

            if (this.isEmulator()) {
                // Mirrors the iOS CodeScanner simulator screen: a notice that the
                // camera is unavailable + a "Select a custom image" button (blue).
                // This SDK generation has no photo-picker + no QR-decode binding, so
                // the button reveals a paste-the-URL fallback to complete the flow.
                Column(space: SPACING_MEDIUM) {
                    Text("You're running in the emulator, which means the camera isn't available. Select an image that contains a QR code.")
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .textAlign(TextAlign.Center)
                        .width(100.percent)
                    WrapButtonView(
                        title: LocalizableStringKey.custom("Select a custom image"),
                        style: ButtonViewStyle.secondary(),
                        onAction: { => this.showManualInput = true }
                    )
                }
                .width(100.percent)
                .padding(SPACING_LARGE)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .borderWidth(2.0)
                .borderColor(uiColor(ThemeManager.shared.color.separator))
                .borderRadius(ThemeManager.shared.shape.medium)
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryBackground))

                if (this.showManualInput) {
                    TextInput(text: this.manualInput, placeholder: "Paste the QR link")
                        .width(100.percent)
                        .height(48.0)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .backgroundColor(uiColor(ThemeManager.shared.color.secondaryBackground))
                        .borderRadius(ThemeManager.shared.shape.extraSmall)
                        .onChange({ value => this.handleInputChange(value) })
                        .onSubmit({ _ => this.submitResult(this.manualInput) })

                    if (this.hasError()) {
                        Text(this.errorText)
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                            .fontColor(uiColor(ThemeManager.shared.color.red))
                            .textAlign(TextAlign.Start)
                            .width(100.percent)
                    }

                    WrapButtonView(
                        title: LocalizableStringKey.scanQrCode,
                        style: ButtonViewStyle.primary(),
                        isEnabled: this.allowScanning,
                        onAction: { => this.submitResult(this.manualInput) }
                    )
                }
            } else {
                // Real device: the camera runs in the HMS Scan Kit page, which
                // aboutToAppear opens. This panel is what the user returns to
                // after dismissing it, so it offers a re-scan.
                Column(space: SPACING_SMALL) {
                    Text("\u{1F4F7}")
                        .fontSize(uiFontSize(ThemeManager.shared.font.displayLarge))
                    Text(LocalizableManager.get(LocalizableStringKey.scannerQrCaption))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .textAlign(TextAlign.Center)
                }
                .width(100.percent)
                .height(200.0)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .borderWidth(2.0)
                .borderColor(uiColor(ThemeManager.shared.color.separator))
                .borderRadius(ThemeManager.shared.shape.medium)
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryBackground))

                WrapButtonView(
                    title: LocalizableStringKey.scanQrCode,
                    style: ButtonViewStyle.primary(),
                    onAction: { => this.startCameraScan() }
                )

                if (this.cameraUnavailable) {
                    Text("Camera scanning is unavailable on this device. Paste the QR link instead.")
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .textAlign(TextAlign.Center)
                        .width(100.percent)
                }

                // Manual entry stays reachable on device too: Scan Kit can be
                // absent (non-HMS build) or camera permission denied, and the
                // user must still be able to complete the flow.
                if (this.showManualInput) {
                    TextInput(text: this.manualInput, placeholder: "Paste the QR link")
                        .width(100.percent)
                        .height(48.0)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .backgroundColor(uiColor(ThemeManager.shared.color.secondaryBackground))
                        .borderRadius(ThemeManager.shared.shape.extraSmall)
                        .onChange({ value => this.handleInputChange(value) })
                        .onSubmit({ _ => this.submitResult(this.manualInput) })

                    if (this.hasError()) {
                        Text(this.errorText)
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                            .fontColor(uiColor(ThemeManager.shared.color.red))
                            .textAlign(TextAlign.Start)
                            .width(100.percent)
                    }

                    WrapButtonView(
                        title: LocalizableStringKey.custom("Submit link"),
                        style: ButtonViewStyle.secondary(),
                        isEnabled: this.allowScanning,
                        onAction: { => this.submitResult(this.manualInput) }
                    )
                }
            }

            if (this.showInformativeText) {
                Row(space: SPACING_SMALL) {
                    Text("\u{24D8}")
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    Text(this.informativeText())
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .textAlign(TextAlign.Center)
                }
                .width(100.percent)
                .padding(SPACING_MEDIUM_SMALL)
                .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                .borderRadius(ThemeManager.shared.shape.medium)
                .justifyContent(FlexAlign.Center)
            }
            }
            .width(100.percent)
            .layoutWeight(1)
            .padding(top: 0.0, right: ThemeManager.shared.dimension.padding, bottom: ThemeManager.shared.dimension.padding, left: ThemeManager.shared.dimension.padding)
            .alignItems(HorizontalAlign.Start)
        }
        .width(100.percent)
        .height(100.percent)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }
}
