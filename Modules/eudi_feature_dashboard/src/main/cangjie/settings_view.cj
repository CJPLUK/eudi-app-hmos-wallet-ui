/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (UI/Settings/SettingsView.swift + SettingsViewModel.swift +
 * UI/Settings/Model/SettingMenuItemUIModel.swift + Interactor/SettingsInteractor.swift)
 * to Cangjie.
 *
 * The Settings screen lists app preferences: login-with-biometrics toggle (only
 * when biometry hardware is available), the batch-issuance-counter toggle, a
 * retrieve-logs row, a changelog row (only when a changelog URL is configured)
 * and finally the app-version footer. iOS also exposes change-PIN via the side
 * menu; here change-PIN is reachable from SideMenu (mirrors iOS exactly).
 *
 * Real data sources (no stubs):
 *   - app version          → ConfigLogic.appVersion
 *   - changelog URL        → ConfigLogic.changelogUrl
 *   - batch counter flag   → PrefsController.getBool/setValue(PrefsKey.batchCounter)
 *   - biometry availability→ BiometryController.canEvaluate()
 *   - biometry-enabled flag→ PrefsController.getBool/setValue(PrefsKey.biometryEnabled)
 *
 * Toggling login-with-biometrics first requires an honest biometric evaluation
 * (BiometryController.requestBiometricUnlock); on the emulator the controller
 * reports BiometryNotSupported, so the row only appears on real hardware and the
 * toggle reverts with the honest error surfaced in an AlertView — never a fake
 * success path. The retrieve-logs row honestly reports that on HarmonyOS logs go
 * through Hilog (no shareable file URL), mirroring the logic-core getLogFileURL
 * contract that returns None on this platform.
 */
package eudi_feature_dashboard

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.app.ability.want.{Want, WantValueType}
import ohos.app.ability.want_constant.Flags
import ohos.ability.ability_result.AbilityResult
import ohos.business_exception.BusinessException
import ohos.file.fileuri.getUriFromPath
import ohos.file.fs.{FileIo, OpenMode}
import kit.ArkUI.*
import std.collection.HashMap
import std.collection.ArrayList
import std.fs.File
import std.time.DateTime
import eudi_logic_core.{NotificationCenter, NotificationName}
import eudi_logic_ui.{
    BaseViewModel, ViewState, RouterHost, AppRoutes, ToolBarContent, ToolBarAction,
    AlertView, AlertAction, ConfirmationSheetView,
    uiColor, uiFontSize, appImageSrc,
    SPACING_SMALL, SPACING_MEDIUM, SPACING_MEDIUM_SMALL, SPACING_LARGE, SPACING_LARGE_MEDIUM,
    ListDividerView, AppIcon
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_logic_business.{ConfigLogic, PrefsController, PrefsKey}
import eudi_logic_core.AppContextHolder
import eudi_feature_common.{BiometryController, BiometryUnlockResult, BiometryError, BiometryType}

// ─── Setting menu item (mirrors iOS SettingMenuItemUIModel) ─────────────────

/** The kind of a settings row (mirrors iOS isShareLink / isToggle flags). */
public enum SettingItemKind {
    | plain
    | toggle
    | shareLogs

    public func isToggle(): Bool {
        match (this) {
            case toggle => true
            case _ => false
        }
    }
}

/**
 * Flat, render-ready settings row. Mirrors iOS SettingMenuItemUIModel; the
 * callback semantics are resolved by SettingsView from the kind + id, so the
 * model itself stays a pure data carrier (no closures inside @State arrays).
 */
public class SettingMenuItem {
    public let id: String
    public let title: LocalizableStringKey
    public let iconSrc: String
    public let showDivider: Bool
    public let kind: SettingItemKind
    public let isOn: Bool

    public init(
        id!: String,
        title!: LocalizableStringKey,
        iconSrc!: String,
        showDivider!: Bool = true,
        kind!: SettingItemKind = SettingItemKind.plain,
        isOn!: Bool = false
    ) {
        this.id = id
        this.title = title
        this.iconSrc = iconSrc
        this.showDivider = showDivider
        this.kind = kind
        this.isOn = isOn
    }
}

// Diagnostic log file name (also the save-picker default) and its display parts.
let SETTINGS_LOG_FILE_STEM: String = "eudi-harmonyos-wallet-logs"
let SETTINGS_LOG_FILE_NAME: String = "${SETTINGS_LOG_FILE_STEM}.txt"

// Stable row ids (mirror iOS title-driven rows; used by the view to route taps).
let SETTINGS_ID_BIOMETRY: String = "biometry"
let SETTINGS_ID_BATCH: String = "batchCounter"
let SETTINGS_ID_REGISTRATION: String = "issuerRegistrationValidation"
let SETTINGS_ID_LOGS: String = "retrieveLogs"
let SETTINGS_ID_CHANGELOG: String = "changelog"

// ─── Interactor (mirrors iOS SettingsInteractor) ────────────────────────────

/**
 * Settings business seam. Mirrors the iOS SettingsInteractorImpl actor,
 * collapsing the biometry sub-interactor into the BiometryController seam and
 * the prefs/config into the delivered logic-business controllers. UI-free; the
 * view calls these from spawn{} where they touch storage.
 */
public class SettingsInteractor {
    private let configLogic: ConfigLogic
    private let prefsController: PrefsController
    private let biometryController: BiometryController

    public init(
        configLogic!: ConfigLogic,
        prefsController!: PrefsController,
        biometryController!: BiometryController
    ) {
        this.configLogic = configLogic
        this.prefsController = prefsController
        this.biometryController = biometryController
    }

    /** Mirrors iOS getAppVersion(). */
    public func getAppVersion(): String {
        this.configLogic.appVersion
    }

    /** Mirrors iOS retrieveChangeLogUrl(). */
    public func retrieveChangeLogUrl(): ?String {
        this.configLogic.changelogUrl
    }

    /** Mirrors iOS isBiometryAvailable() (LABiometryType != .none). */
    public func isBiometryAvailable(): Bool {
        match (this.biometryController.getBiometryType()) {
            case BiometryType.BiometryNone => false
            case _ => true
        }
    }

    /** Mirrors iOS isBiometryEnabled() (persisted preference). */
    public func isBiometryEnabled(): Bool {
        this.prefsController.getBool(PrefsKey.biometryEnabled)
    }

    /**
     * Mirrors iOS authenticateBiometry(): performs the real biometric
     * evaluation and reports the honest result.
     */
    public func authenticateBiometry(): BiometryUnlockResult {
        this.biometryController.requestBiometricUnlock()
    }

    /** Mirrors iOS openBiometrySettings(_:). */
    public func openBiometrySettings(): Unit {
        this.biometryController.openSettings({ => })
    }

    /** Mirrors iOS setBiometrySelection(isEnabled:). */
    public func setBiometrySelection(isEnabled: Bool): Unit {
        this.prefsController.setValue(isEnabled, PrefsKey.biometryEnabled)
    }

    /** Mirrors iOS isBatchCounterEnabled(). */
    public func isBatchCounterEnabled(): Bool {
        this.prefsController.getBool(PrefsKey.batchCounter)
    }

    /** Mirrors iOS setBatchCounter(isEnabled:). */
    public func setBatchCounter(isEnabled: Bool): Unit {
        this.prefsController.setValue(isEnabled, PrefsKey.batchCounter)
    }

    /** Mirrors iOS isIssuerRegistrationValidationEnabled() (persisted preference, default false). */
    public func isIssuerRegistrationValidationEnabled(): Bool {
        this.prefsController.getBool(PrefsKey.validateIssuerRegistrationCertificate)
    }

    /** Mirrors iOS setIssuerRegistrationValidation(isEnabled:). */
    public func setIssuerRegistrationValidation(isEnabled: Bool): Unit {
        this.prefsController.setValue(isEnabled, PrefsKey.validateIssuerRegistrationCertificate)
    }

    /**
     * Mirrors iOS retrieveLogFileUrl() + ShareLink as far as the platform
     * allows: runtime logs go through Hilog (no shareable file handle), so a
     * diagnostic snapshot is written to the app files dir and its path
     * returned for the user to pull (e.g. `hdc file recv`).
     */
    public func exportLogs(): ?(String, Int64) {
        let dir = match (AppContextHolder.get()) {
            case Some(ctx) => ctx.filesDir
            case None => return None
        }
        let path = "${dir}/${SETTINGS_LOG_FILE_NAME}"
        let sb = StringBuilder()
        sb.append("EUDI Wallet diagnostic log\n")
        sb.append("generated: ${DateTime.now()}\n")
        sb.append("app version: ${this.configLogic.appVersion}\n")
        sb.append("batch issuance counter enabled: ${this.isBatchCounterEnabled()}\n")
        sb.append("issuer registration validation enabled: ${this.isIssuerRegistrationValidationEnabled()}\n")
        sb.append("login with biometrics enabled: ${this.isBiometryEnabled()}\n")
        sb.append("biometry hardware available: ${this.isBiometryAvailable()}\n")
        sb.append("runtime logs are emitted via Hilog; capture with 'hdc shell hilog'.\n")
        try {
            let payload = sb.toString().toArray()
            File.writeTo(path, payload)
            return Some((path, Int64(payload.size)))
        } catch (_: Exception) {
            return None
        }
    }
}

// ─── State (mirrors iOS SettingsViewState) ──────────────────────────────────

/** Mirrors Swift `SettingsViewState`. */
public class SettingsViewState <: ViewState {
    public let items: Array<SettingMenuItem>
    public let isBiometryEnabled: Bool
    public let isBatchCounterEnabled: Bool
    public let isIssuerRegistrationValidationEnabled: Bool
    public let isRestartRequiredAlertShowing: Bool
    public let appVersion: String
    public let biometryError: ?String
    public let infoMessage: ?String
    public let logsPath: ?String
    public let logsSize: Int64

    public init(
        items!: Array<SettingMenuItem> = Array<SettingMenuItem>(),
        isBiometryEnabled!: Bool = false,
        isBatchCounterEnabled!: Bool = false,
        isIssuerRegistrationValidationEnabled!: Bool = false,
        isRestartRequiredAlertShowing!: Bool = false,
        appVersion!: String = "",
        biometryError!: ?String = Option<String>.None,
        infoMessage!: ?String = Option<String>.None,
        logsPath!: ?String = Option<String>.None,
        logsSize!: Int64 = 0
    ) {
        this.items = items
        this.isBiometryEnabled = isBiometryEnabled
        this.isBatchCounterEnabled = isBatchCounterEnabled
        this.isIssuerRegistrationValidationEnabled = isIssuerRegistrationValidationEnabled
        this.isRestartRequiredAlertShowing = isRestartRequiredAlertShowing
        this.appVersion = appVersion
        this.biometryError = biometryError
        this.infoMessage = infoMessage
        this.logsPath = logsPath
        this.logsSize = logsSize
    }
}

// ─── View model (mirrors iOS SettingsViewModel) ─────────────────────────────

/** Mirrors Swift `SettingsViewModel<Router>`. */
public class SettingsViewModel <: BaseViewModel<SettingsViewState> {
    private let interactor: SettingsInteractor

    public init(router!: RouterHost, interactor!: SettingsInteractor) {
        super(router, SettingsViewState())
        this.interactor = interactor
    }

    public func toolbarContent(): ToolBarContent {
        ToolBarContent(
            leadingActions: [
                ToolBarAction(
                    iconSrc: ThemeManager.shared.image.chevronLeft,
                    callback: { => this.router.pop() }
                )
            ]
        )
    }

    /** Mirrors iOS initialize() → buildUi(). Blocking; view wraps in spawn{}. */
    public func initialize(): Unit {
        this.buildUi()
    }

    /** Mirrors iOS updatePin(): push the QuickPin update flow (change PIN). */
    public func onChangePin(): Unit {
        this.router.push(AppRoutes.quickPin)
    }

    /**
     * Toggle the batch-issuance-counter preference (mirrors iOS
     * updateBatchCounter via the isBatchCounterEnabled didSet).
     */
    public func onToggleBatchCounter(): Unit {
        let next = !this.viewState.isBatchCounterEnabled
        this.interactor.setBatchCounter(next)
        this.buildUi()
        // iOS DocumentTabViewModel re-fetches on every appear, so the badge
        // follows the preference as soon as the user returns. The Cangjie tab
        // stays mounted behind Settings and only rebuilds on DocumentTabRefresh.
        NotificationCenter.post(NotificationName.DocumentTabRefresh)
    }

    /**
     * Toggle registration-certificate validation (mirrors iOS
     * updateIssuerRegistrationValidation). The wallet reads issuersConfig /
     * vpConfig at construction, so the change needs an app restart — persist,
     * then surface the restart-required alert.
     */
    public func onToggleIssuerRegistrationValidation(): Unit {
        let next = !this.viewState.isIssuerRegistrationValidationEnabled
        this.interactor.setIssuerRegistrationValidation(next)
        this.buildUi(showRestartAlert: true)
    }

    /** Dismisses the restart-required alert. */
    public func dismissRestartRequiredAlert(): Unit {
        this.setState({ s =>
            SettingsViewState(
                items: s.items,
                isBiometryEnabled: s.isBiometryEnabled,
                isBatchCounterEnabled: s.isBatchCounterEnabled,
                isIssuerRegistrationValidationEnabled: s.isIssuerRegistrationValidationEnabled,
                appVersion: s.appVersion,
                biometryError: s.biometryError,
                infoMessage: s.infoMessage,
                logsPath: s.logsPath,
                logsSize: s.logsSize
            )
        })
    }

    /**
     * Toggle login-with-biometrics. Mirrors iOS setBiometryEnabled: requires a
     * real biometric evaluation; on failure reverts and surfaces the honest
     * error (no fake success).
     */
    public func onToggleBiometry(): Unit {
        let desired = !this.viewState.isBiometryEnabled
        match (this.interactor.authenticateBiometry()) {
            case BiometryUnlockResult.UnlockSuccess =>
                this.interactor.setBiometrySelection(desired)
                this.buildUi()
            case BiometryUnlockResult.UnlockFailure(err) =>
                // Keep the persisted value and surface the reason — except the
                // plain BiometricError, which iOS swallows here too because the
                // platform sheet has already reported "not recognized".
                match (err) {
                    case BiometryError.BiometricError => ()
                    case _ =>
                        this.setState({ s =>
                            SettingsViewState(
                                items: s.items,
                                isBiometryEnabled: s.isBiometryEnabled,
                                isBatchCounterEnabled: s.isBatchCounterEnabled,
                                isIssuerRegistrationValidationEnabled: s.isIssuerRegistrationValidationEnabled,
                                appVersion: s.appVersion,
                                biometryError: Some(err.message()),
                                infoMessage: s.infoMessage,
                                logsPath: s.logsPath,
                                logsSize: s.logsSize
                            )
                        })
                }
        }
    }

    /** Mirrors iOS onBiometrySettings(). */
    public func onBiometrySettings(): Unit {
        this.interactor.openBiometrySettings()
    }

    /** Dismisses the biometry-error alert. */
    public func dismissBiometryError(): Unit {
        this.setState({ s =>
            SettingsViewState(
                items: s.items,
                isBiometryEnabled: s.isBiometryEnabled,
                isBatchCounterEnabled: s.isBatchCounterEnabled,
                isIssuerRegistrationValidationEnabled: s.isIssuerRegistrationValidationEnabled,
                appVersion: s.appVersion,
                biometryError: Option<String>.None,
                infoMessage: s.infoMessage,
                logsPath: s.logsPath,
                logsSize: s.logsSize
            )
        })
    }

    private func showInfo(message: String): Unit {
        this.setState({ s =>
            SettingsViewState(
                items: s.items,
                isBiometryEnabled: s.isBiometryEnabled,
                isBatchCounterEnabled: s.isBatchCounterEnabled,
                isIssuerRegistrationValidationEnabled: s.isIssuerRegistrationValidationEnabled,
                appVersion: s.appVersion,
                biometryError: s.biometryError,
                infoMessage: Some(message),
                logsPath: s.logsPath,
                logsSize: s.logsSize
            )
        })
    }

    /** Dismisses the info alert (retrieve-logs / changelog feedback). */
    public func dismissInfo(): Unit {
        this.setState({ s =>
            SettingsViewState(
                items: s.items,
                isBiometryEnabled: s.isBiometryEnabled,
                isBatchCounterEnabled: s.isBatchCounterEnabled,
                isIssuerRegistrationValidationEnabled: s.isIssuerRegistrationValidationEnabled,
                appVersion: s.appVersion,
                biometryError: s.biometryError,
                logsPath: s.logsPath,
                logsSize: s.logsSize
            )
        })
    }

    /** Mirrors iOS `changelogUrl.open()`: launch the system browser. */
    public func onChangelog(): Unit {
        let url = match (this.interactor.retrieveChangeLogUrl()) {
            case Some(u) where !u.isEmpty() => u
            case _ => return
        }
        match (AppContextHolder.get()) {
            case Some(ctx) =>
                try {
                    ctx.startAbility(Want(
                        action: "ohos.want.action.viewData",
                        uri: url,
                        entities: ["entity.system.browsable"]
                    ))
                } catch (e: Exception) {
                    this.showInfo("Unable to open ${url}: ${e.message}")
                }
            case None => this.showInfo("Unable to open ${url}: app context unavailable")
        }
    }

    /**
     * Mirrors the iOS ShareLink row: materialise the log file, then present
     * the share decision sheet (iOS opens the activity sheet with the file).
     */
    public func onRetrieveLogs(): Unit {
        match (this.interactor.exportLogs()) {
            case Some((path, size)) =>
                this.setState({ s =>
                    SettingsViewState(
                        items: s.items,
                        isBiometryEnabled: s.isBiometryEnabled,
                        isBatchCounterEnabled: s.isBatchCounterEnabled,
                        isIssuerRegistrationValidationEnabled: s.isIssuerRegistrationValidationEnabled,
                        appVersion: s.appVersion,
                        biometryError: s.biometryError,
                        infoMessage: s.infoMessage,
                        logsPath: Some(path),
                        logsSize: size
                    )
                })
            case None => this.showInfo("Unable to export logs")
        }
    }

    /** Closes the retrieve-logs sheet. */
    public func dismissLogsSheet(): Unit {
        this.setState({ s =>
            SettingsViewState(
                items: s.items,
                isBiometryEnabled: s.isBiometryEnabled,
                isBatchCounterEnabled: s.isBatchCounterEnabled,
                isIssuerRegistrationValidationEnabled: s.isIssuerRegistrationValidationEnabled,
                appVersion: s.appVersion,
                biometryError: s.biometryError,
                infoMessage: s.infoMessage
            )
        })
    }

    /**
     * Hands the log file to the system share panel (iOS activity sheet
     * equivalent). Emulators ship no share provider — fall back to surfacing
     * the file path so it can be pulled with `hdc file recv`.
     */
    public func onShareLogs(path: String): Unit {
        this.dismissLogsSheet()
        match (AppContextHolder.get()) {
            case Some(ctx) =>
                try {
                    ctx.startAbility(Want(
                        action: "ohos.want.action.sendData",
                        uri: getUriFromPath(path),
                        dataType: "text/plain",
                        flags: Flags.FLAG_AUTH_READ_URI_PERMISSION
                    ))
                } catch (_: Exception) {
                    this.showInfo("No share target available on this device.\nLog file:\n${path}")
                }
            case None => this.showInfo("Log file:\n${path}")
        }
    }

    /**
     * Save-as flow: the system file picker (the service behind ArkTS
     * DocumentViewPicker.save) lets the user pick the destination, then the
     * log content is written to the returned URI — mirroring the iOS
     * activity-sheet "Save to Files" option.
     */
    public func onSaveLogs(path: String): Unit {
        this.dismissLogsSheet()
        let ctx = match (AppContextHolder.get()) {
            case Some(c) => c
            case None =>
                this.showInfo("Log file:\n${path}")
                return
        }
        let params = HashMap<String, WantValueType>(
            [
                ("startMode", WantValueType.StringValue("save")),
                ("key_pick_num", WantValueType.Int64Value(1)),
                ("key_pick_file_name", WantValueType.ArrayValue([WantValueType.StringValue(SETTINGS_LOG_FILE_NAME)]))
            ]
        )
        // HarmonyOS file manager exposes the save picker (PathPickerAbility)
        // under CREATE_FILE; the OpenHarmony picker uses CREATE_FILE_SERVICE.
        try {
            ctx.startAbilityForResult(
                Want(action: "ohos.want.action.CREATE_FILE", parameters: params),
                { err, result => this.onSaveDestinationPicked(err, result, path) }
            )
        } catch (_: Exception) {
            try {
                ctx.startAbilityForResult(
                    Want(action: "ohos.want.action.CREATE_FILE_SERVICE", parameters: params),
                    { err, result => this.onSaveDestinationPicked(err, result, path) }
                )
            } catch (e: Exception) {
                this.showInfo("Unable to open the file picker: ${e.message}")
            }
        }
    }

    private func onSaveDestinationPicked(
        err: ?BusinessException,
        result: ?AbilityResult,
        sourcePath: String
    ): Unit {
        match (err) {
            case Some(e) =>
                this.showInfo("File picker failed: ${e.message}")
                return
            case None => ()
        }
        let res = match (result) {
            case Some(r) => r
            case None => return
        }
        if (res.resultCode != 0) {
            // User backed out of the picker — no destination, nothing to do.
            return
        }
        match (this.extractPickedUri(res.want.parameters)) {
            case Some(uri) =>
                try {
                    let content = String.fromUtf8(File.readFrom(sourcePath))
                    let out = FileIo.open(
                        uri,
                        mode: OpenMode.READ_WRITE | OpenMode.CREATE | OpenMode.TRUNC
                    )
                    FileIo.write(out.fd, content)
                    FileIo.close(out)
                    this.showInfo("Log saved to:\n${uri}")
                } catch (e: Exception) {
                    this.showInfo("Unable to write the log: ${e.message}")
                }
            case None => this.showInfo("The file picker returned no destination.")
        }
    }

    /** The picker returns the chosen URI under pick_path_return (string array). */
    private func extractPickedUri(params: HashMap<String, WantValueType>): ?String {
        func firstString(value: WantValueType): ?String {
            match (value) {
                case WantValueType.StringValue(s) => Some(s)
                case WantValueType.ArrayValue(items) =>
                    for (item in items) {
                        match (item) {
                            case WantValueType.StringValue(s) => return Some(s)
                            case _ => ()
                        }
                    }
                    None
                case _ => None
            }
        }
        match (params.get("pick_path_return")) {
            case Some(v) =>
                match (firstString(v)) {
                    case Some(s) => return Some(s)
                    case None => ()
                }
            case None => ()
        }
        // Fallback: any file:// value anywhere in the result bag.
        for ((_, v) in params) {
            match (firstString(v)) {
                case Some(s) where s.startsWith("file://") => return Some(s)
                case _ => ()
            }
        }
        return None
    }

    private func buildUi(showRestartAlert!: Bool = false): Unit {
        let appVersion = this.interactor.getAppVersion()
        let isBiometryEnabled = this.interactor.isBiometryEnabled()
        let isBatchEnabled = this.interactor.isBatchCounterEnabled()
        let isRegistrationValidationEnabled = this.interactor.isIssuerRegistrationValidationEnabled()

        let items = ArrayList<SettingMenuItem>()

        // Exactly like iOS, expose this row only when the platform reports a
        // biometric modality. Enrolled state is checked again on interaction.
        if (this.interactor.isBiometryAvailable()) {
            items.add(
                SettingMenuItem(
                    id: SETTINGS_ID_BIOMETRY,
                    title: LocalizableStringKey.loginWithBiometrics,
                    iconSrc: ThemeManager.shared.image.faceIdMenu,
                    showDivider: true,
                    kind: SettingItemKind.toggle,
                    isOn: isBiometryEnabled
                )
            )
        }

        items.add(
            SettingMenuItem(
                id: SETTINGS_ID_BATCH,
                title: LocalizableStringKey.batchIssuanceCounter,
                iconSrc: ThemeManager.shared.image.batchCounter,
                showDivider: true,
                kind: SettingItemKind.toggle,
                isOn: isBatchEnabled
            )
        )

        items.add(
            SettingMenuItem(
                id: SETTINGS_ID_REGISTRATION,
                title: LocalizableStringKey.validateIssuerRegistration,
                iconSrc: ThemeManager.shared.image.issuerRegistration,
                showDivider: true,
                kind: SettingItemKind.toggle,
                isOn: isRegistrationValidationEnabled
            )
        )

        items.add(
            SettingMenuItem(
                id: SETTINGS_ID_LOGS,
                title: LocalizableStringKey.retrieveLogs,
                iconSrc: ThemeManager.shared.image.retrieveLogs,
                showDivider: true,
                kind: SettingItemKind.shareLogs
            )
        )

        match (this.interactor.retrieveChangeLogUrl()) {
            case Some(url) where !url.isEmpty() =>
                items.add(
                    SettingMenuItem(
                        id: SETTINGS_ID_CHANGELOG,
                        title: LocalizableStringKey.changelog,
                        iconSrc: ThemeManager.shared.image.changelog,
                        showDivider: false,
                        kind: SettingItemKind.plain
                    )
                )
            case _ => ()
        }

        this.setState({ _ =>
            SettingsViewState(
                items: items.toArray(),
                isBiometryEnabled: isBiometryEnabled,
                isBatchCounterEnabled: isBatchEnabled,
                isIssuerRegistrationValidationEnabled: isRegistrationValidationEnabled,
                isRestartRequiredAlertShowing: showRestartAlert,
                appVersion: appVersion,
                biometryError: Option<String>.None
            )
        })
    }
}

// ─── View (mirrors iOS SettingsView) ────────────────────────────────────────

/**
 * Settings screen. NavDestination root (D-002), registered under the route key
 * AppRoutes.settingsMenu. The screen owns its own toolbar (back) + scrollable
 * settings list + version footer (mirrors iOS ContentScreenView body).
 */
@Component
public class SettingsView {
    public var viewModel: ?SettingsViewModel = Option<SettingsViewModel>.None

    @State
    var items: Array<SettingMenuItem> = Array<SettingMenuItem>()
    @State
    var appVersion: String = ""
    @State
    var biometryError: String = ""
    @State
    var showBiometryError: Bool = false
    @State
    var infoMessage: String = ""
    @State
    var showInfoMessage: Bool = false
    @State
    var showRestartRequiredAlert: Bool = false
    // Bumped after every toggle interaction so the ForEach keys change and the
    // (uncontrolled) Toggle remounts from item.isOn — otherwise a rejected
    // biometry toggle stays visually ON (known ForEach/Toggle refresh trap).
    @State
    var toggleTick: Int64 = 0
    @State
    var logsPath: String = ""
    @State
    var logsSize: Int64 = 0
    @State
    var showLogsSheet: Bool = false

    private var vm: ?SettingsViewModel = Option<SettingsViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.items = state.items
                        this.appVersion = state.appVersion
                        match (state.biometryError) {
                            case Some(e) =>
                                this.biometryError = e
                                this.showBiometryError = true
                            case None =>
                                this.showBiometryError = false
                        }
                        match (state.infoMessage) {
                            case Some(m) =>
                                this.infoMessage = m
                                this.showInfoMessage = true
                            case None =>
                                this.showInfoMessage = false
                        }
                        this.showRestartRequiredAlert = state.isRestartRequiredAlertShowing
                        match (state.logsPath) {
                            case Some(p) =>
                                this.logsPath = p
                                this.logsSize = state.logsSize
                                this.showLogsSheet = true
                            case None =>
                                this.showLogsSheet = false
                        }
                    }
                })
                spawn {
                    =>
                    model.initialize()
                }
            case None => ()
        }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onBack(): Unit {
        match (this.vm) {
            case Some(model) => model.router.pop()
            case None => ()
        }
    }

    /** iOS file-preview size string ("123 B" / "1 KB" / "1.2 MB"). */
    private func formatFileSize(bytes: Int64): String {
        if (bytes < 1024) {
            return "${bytes} B"
        }
        if (bytes < 1024 * 1024) {
            return "${bytes / 1024} KB"
        }
        let whole = bytes / (1024 * 1024)
        let tenth = (bytes % (1024 * 1024)) * 10 / (1024 * 1024)
        return "${whole}.${tenth} MB"
    }

    private func onRowTap(item: SettingMenuItem): Unit {
        match (this.vm) {
            case Some(model) =>
                match (item.kind) {
                    case SettingItemKind.toggle =>
                        if (item.id == SETTINGS_ID_BIOMETRY) {
                            spawn {
                                =>
                                model.onToggleBiometry()
                                spawn(UIThread) { => this.toggleTick += 1 }
                            }
                        } else if (item.id == SETTINGS_ID_BATCH) {
                            spawn {
                                =>
                                model.onToggleBatchCounter()
                                spawn(UIThread) { => this.toggleTick += 1 }
                            }
                        } else if (item.id == SETTINGS_ID_REGISTRATION) {
                            spawn {
                                =>
                                model.onToggleIssuerRegistrationValidation()
                                spawn(UIThread) { => this.toggleTick += 1 }
                            }
                        }
                    case SettingItemKind.plain =>
                        if (item.id == SETTINGS_ID_CHANGELOG) {
                            model.onChangelog()
                        }
                    case SettingItemKind.shareLogs =>
                        spawn {
                            =>
                            model.onRetrieveLogs()
                        }
                }
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Stack(alignContent: Alignment.Center) {
                Column {
                    this.toolbar()
                    Scroll {
                        // iOS Settings is a flat grouped list with hairline dividers
                        // between rows (not per-row rounded cards).
                        // Swift SettingsViewContainer uses VStack(spacing: 12).
                        Column(space: SPACING_MEDIUM_SMALL) {
                            ForEach(
                                this.items,
                                itemGenerator: { item: SettingMenuItem, idx: Int64 =>
                                    // TappableCellView itself is another VStack(spacing: 12):
                                    // the row is intrinsic-height and the divider follows
                                    // after 12pt. Do not force a 44pt cell; long localized
                                    // labels must grow exactly as they do on iOS.
                                    Column(space: SPACING_MEDIUM_SMALL) {
                                        Row(space: SPACING_MEDIUM) {
                                            Row {
                                                AppIcon(
                                                    token: item.iconSrc,
                                                    size: 24.0,
                                                    color: uiColor(ThemeManager.shared.color.accent)
                                                )
                                            }
                                            .width(24.0)
                                            .height(24.0)
                                            .justifyContent(FlexAlign.Center)
                                            Text(LocalizableManager.get(item.title))
                                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                                .textAlign(TextAlign.Start)
                                                .maxLines(2)
                                                .layoutWeight(1)
                                            if (item.kind.isToggle()) {
                                                Toggle(ToggleType.Switch, isOn: item.isOn)
                                                    .selectedColor(uiColor(ThemeManager.shared.color.green))
                                                    .width(51.0)
                                                    .height(31.0)
                                                    .onChange({ _ => this.onRowTap(item) })
                                            } else {
                                                Image(appImageSrc(ThemeManager.shared.image.chevronRightAccent))
                                                    .width(18.0)
                                                    .height(18.0)
                                                    .objectFit(ImageFit.Contain)
                                            }
                                        }
                                        .width(100.percent)
                                        .padding(top: 0.0, right: 0.0, bottom: 0.0, left: 0.0)
                                        // iOS passes useOverlay=false for toggle rows, so
                                        // tapping the label cannot also toggle the switch.
                                        .onClick({ _ =>
                                            if (!item.kind.isToggle()) {
                                                this.onRowTap(item)
                                            }
                                        })
                                        if (item.showDivider && idx < Int64(this.items.size) - 1) {
                                            // iOS Divider spans the full cell width.
                                            ListDividerView(spacing: 0.0)
                                        }
                                    }
                                    .width(100.percent)
                                },
                                keyGenerator: { item: SettingMenuItem, _: Int64 =>
                                    "${item.id}_${item.isOn}_${this.toggleTick}"
                                }
                            )
                        }
                        .width(100.percent)
                        .padding(
                            // ContentScreenView(canScroll: true) applies its
                            // standard 16pt padding to horizontal + top edges.
                            top: SPACING_MEDIUM,
                            right: SPACING_MEDIUM,
                            bottom: SPACING_LARGE_MEDIUM,
                            left: SPACING_MEDIUM
                        )
                    }
                    .align(Alignment.TopStart)
                    .layoutWeight(1)
                    // iOS anchors the app version at the bottom of the screen, not
                    // centered under the rows. The layoutWeight(1) Scroll pushes this
                    // footer down so it sits along the bottom edge.
                    if (!this.appVersion.isEmpty()) {
                        // iOS: bodyMedium, primaryLabel, centered, hugging the
                        // bottom edge above the home indicator.
                        Text(this.appVersion)
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .width(100.percent)
                            .textAlign(TextAlign.Center)
                            .padding(top: 0.0, right: SPACING_MEDIUM, bottom: SPACING_LARGE_MEDIUM, left: SPACING_MEDIUM)
                    }
                }
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(uiColor(ThemeManager.shared.color.background))

                // iOS ShareLink decision step: bottom sheet with the file +
                // share action (the activity sheet itself is the system's).
                if (this.showLogsSheet) {
                    ConfirmationSheetView(
                        // iOS ShareLink preview header: doc thumbnail +
                        // extension-less name line + "File · size" subtitle.
                        title: LocalizableStringKey.custom(SETTINGS_LOG_FILE_STEM),
                        titleColor: uiColor(ThemeManager.shared.color.primaryLabel),
                        titleFont: ThemeManager.shared.font.bodySmall,
                        titleIconSrc: "doc.text",
                        message: LocalizableStringKey.custom("File \u{00B7} ${this.formatFileSize(this.logsSize)}"),
                        messageFont: ThemeManager.shared.font.labelMedium,
                        bottomInset: SPACING_SMALL,
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.custom("Save to…"),
                                callback: { =>
                                    match (this.vm) {
                                        case Some(m) => m.onSaveLogs(this.logsPath)
                                        case None => ()
                                    }
                                }
                            ),
                            AlertAction(
                                title: LocalizableStringKey.custom("Share…"),
                                callback: { =>
                                    match (this.vm) {
                                        case Some(m) => m.onShareLogs(this.logsPath)
                                        case None => ()
                                    }
                                }
                            ),
                            AlertAction(
                                title: LocalizableStringKey.cancelButton,
                                isDestructive: true,
                                callback: { =>
                                    match (this.vm) {
                                        case Some(m) => m.dismissLogsSheet()
                                        case None => ()
                                    }
                                }
                            )
                        ],
                        onDismiss: {
                            =>
                            match (this.vm) {
                                case Some(m) => m.dismissLogsSheet()
                                case None => ()
                            }
                        }
                    )
                }

                if (this.showInfoMessage) {
                    AlertView(
                        title: LocalizableStringKey.retrieveLogs,
                        message: LocalizableStringKey.custom(this.infoMessage),
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.okButton,
                                callback: { =>
                                    match (this.vm) {
                                        case Some(m) => m.dismissInfo()
                                        case None => ()
                                    }
                                }
                            )
                        ],
                        onDismiss: {
                            =>
                            match (this.vm) {
                                case Some(m) => m.dismissInfo()
                                case None => ()
                            }
                        }
                    )
                }

                if (this.showRestartRequiredAlert) {
                    AlertView(
                        title: LocalizableStringKey.restartRequiredTitle,
                        message: LocalizableStringKey.restartRequiredMessage,
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.okButton,
                                callback: { =>
                                    match (this.vm) {
                                        case Some(m) => m.dismissRestartRequiredAlert()
                                        case None => ()
                                    }
                                }
                            )
                        ],
                        onDismiss: {
                            =>
                            match (this.vm) {
                                case Some(m) => m.dismissRestartRequiredAlert()
                                case None => ()
                            }
                        }
                    )
                }

                if (this.showBiometryError) {
                    AlertView(
                        title: LocalizableStringKey.genericErrorTitle,
                        message: LocalizableStringKey.custom(this.biometryError),
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.biometryOpenSettings,
                                callback: { =>
                                    match (this.vm) {
                                        case Some(m) =>
                                            m.dismissBiometryError()
                                            m.onBiometrySettings()
                                        case None => ()
                                    }
                                }
                            ),
                            AlertAction(
                                title: LocalizableStringKey.cancelButton,
                                callback: { =>
                                    match (this.vm) {
                                        case Some(m) => m.dismissBiometryError()
                                        case None => ()
                                    }
                                }
                            )
                        ],
                        onDismiss: {
                            =>
                            match (this.vm) {
                                case Some(m) => m.dismissBiometryError()
                                case None => ()
                            }
                        }
                    )
                }
            }
            .width(100.percent)
            .height(100.percent)
            // Let overlays (sheet scrim) paint under the bottom system bar —
            // expanding only the overlay is ineffective while the page root
            // stays inset by the safe area.
            .expandSafeArea(types: [SafeAreaType.System], edges: [SafeAreaEdge.Bottom])
        }
        .hideTitleBar(true)
    }

    @Builder
    private func toolbar() {
        Row(space: SPACING_SMALL) {
            // iOS back affordance: chevron in a circular white button (not a bare glyph).
            Row {
                Text("‹")
                    .fontSize(28.0)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            }
            .width(40.0)
            .height(40.0)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 8.0, color: uiColor(ThemeManager.shared.color.tertiaryLabel), offsetX: 0.0, offsetY: 2.0)
            .onClick({ _ => this.onBack() })
            Text(LocalizableManager.get(LocalizableStringKey.settings))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                // iOS centers the nav title; balance the leading back button.
                .textAlign(TextAlign.Center)
                .maxLines(1)
            Row {}
                .width(40.0)
                .height(40.0)
        }
        .width(100.percent)
        // iOS inline nav bar hugs the content — keep the vertical inset tight.
        .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
    }
}
