// 设备单元测试：feature-proximity（近场 BLE 出示）interactor 行为迁移。
//
// 源用例：iOS Modules/feature-proximity/Tests/Interactor/TestProximityInteractor.swift
//         （共 18 个 case，逐条映射见下方对照表与每个 case 上方注释）。
//
// 通过设备桥（dev_unit_driver.cj 的 DeviceTestRun）运行。仅手写 fake，
// 不依赖 Cuckoo / 真实引擎 / keychain / BLE 收发。
//
// ─── 被测对象 ────────────────────────────────────────────────────────────────
//   ProximityInteractorImpl(coordinator!: ProximitySessionCoordinator,
//                           walletController!: WalletKitController)
//
// 关键架构差异（影响映射，务必先读）：
//   iOS 的 interactor 经 SessionCoordinatorHolder.getActiveProximityCoordinator()
//   间接拿 coordinator，且每个方法都可能在“取 coordinator”时抛错。
//   Cangjie 把这层 holder 折叠掉了——coordinator 在构造时直接注入并以 `let`
//   字段持有（刻意保留此更简洁的直注设计，不加回 holder 间接层）。
//   为让 iOS 测试的决策点可断言，本轮给 interactor 补了薄的公开访问器
//   getSessionStatePublisher(): ProximityPublisherResult 与
//   getCoordinator(): ProximityCoordinatorResult（分别镜像 iOS
//   ProximityPublisherPartialState / ProximityCoordinatorPartialState）。
//   iOS 里“令 sessionHolder.getActiveProximityCoordinator() 抛错→failure”的 case，
//   等价触发方式=**注入一个在 getStream()（liveness 探针）上抛错的 fake coordinator**，
//   使访问器走 catch → failure（见 [iOS 4]/[iOS 6] 及 onResponsePrepare/onSendResponse
//   的 setState/sendResponse 抛错用例）。
//
//   另外 BLE 双设备近场出示在仓颉/鸿蒙侧平台受限：真实 BLE 引擎未接入，
//   QR 引擎/请求收发由 coordinator 抽象，单测用 fake coordinator 注入既定返回，
//   覆盖的是 interactor 的业务编排逻辑，而非真实 BLE 传输（真实传输无法在
//   headless 设备单测里复现，属平台降级）。
//
// ─── 本文件内的本地 fake（必须 top-level；仓颉不允许局部类定义）─────────────
//   FakeProximityCoordinator       —— 可配返回/抛错/计数的 ProximitySessionCoordinator
//   FakeProximityWalletController   —— 继承 dev_test_fakes.cj 的 FakeWalletKitController
//                                      （复用 stopPresentationCalls / revokedDocumentIds 等）
//   makeProximityDoc                —— 造一个带非空 docClaims 的 DocClaimsDecodable
//                                      （供 fetchDocument → buildRequestReceivedModel 用）
package eudi_unit_tests

import std.collection.{ArrayList, HashMap}
import std.time.DateTime
import eudi_logic_core.{
    WalletCoreError,
    ProximitySessionCoordinator, ProximitySessionCoordinatorImpl,
    PresentationSession, PresentationSessionStatus,
    PresentationState, PresentationRequest,
    SendableCurrentValueSubject, RequestItemConvertible, RequestItemsWrapper, RequestConvertibleItems,
    DocElements, DocClaim, DocDataValue,
    DocClaimsDecodable, DocDataFormat, CredentialPolicy,
    StatusIdentifier, DisplayMetadata, CredentialsUsageCounts
}
import eudi_feature_proximity.{
    ProximityInteractorImpl, NoopProximityInteractor, ProximityConnectionViewModel,
    DeviceEngagementResult, QrGenerationResult, ProximitySentResult,
    ProximityPublisherResult, ProximityCoordinatorResult
}
import eudi_feature_common.RequestDataCell
import eudi_logic_ui.InMemoryRouterHost
import eudi_logic_business.{
    BleAvailibity, BleRadioState, mapBleAvailability,
    bleRadioStateFromErrorCode, allPermissionsGranted
}
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WrpRegistrationPolicy as ProxWrpRegistrationPolicy
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.{DisclosedDocumentSet, PresentationPolicyViolation}

// ─────────────────────────────────────────────────────────────────────────────
// FakeProximityCoordinator —— ProximitySessionCoordinator 的可配置 fake
// ─────────────────────────────────────────────────────────────────────────────
//
// 设计（对齐 dev_test_fakes.cj 的约定）：
//   - 返回值方法 → 可配 public var；
//   - Unit 方法 → 调用计数 public var；
//   - “应抛错”开关 → shouldThrowXxx；抛错消息可配（默认非空，验证错误文本透传）。
//
// 子类可 override，因此基类标 open（仓颉铁律 5）。
open class FakeProximityCoordinator <: ProximitySessionCoordinator {
    // 内部 subject：sendableCurrentValueSubject / getStream 都返回它。
    private let subject = SendableCurrentValueSubject<PresentationState>(PresentationState.loading)

    // ── 可配返回 ──────────────────────────────────────────────────────────────
    /** startQrEngagement() 返回的 device-engagement 载荷（"mdoc:" + base64url(CBOR)）。 */
    public var qrPayload: String = ""
    /** currentRelyingParty() 返回的验证方名（交易日志用）。 */
    public var relyingPartyName: String = "Verifier"
    /** requestReceived() 返回的请求。 */
    public var request: PresentationRequest = PresentationRequest(
        items: Array<DocElements>(), relyingParty: "", dataRequestInfo: "", isTrusted: false
    )
    /** getState() 返回的当前状态（onSendResponse 读取它判定）。 */
    public var state: PresentationState = PresentationState.loading

    // ── 抛错开关（默认 false；消息默认非空以验证错误文本透传）──────────────────
    public var shouldThrowInitialize: Bool = false
    public var initializeError: String = "device engagement failed"
    public var shouldThrowQr: Bool = false
    public var qrError: String = "qr generation failed"
    public var shouldThrowRequestReceived: Bool = false
    /** requestReceived() 抛信任失败（对应 iOS WalletError(.trustError)）。 */
    public var shouldThrowTrustError: Bool = false
    public var requestReceivedError: String = "request conversion failed"
    public var shouldThrowSendResponse: Bool = false
    public var sendResponseError: String = "send response failed"
    public var shouldThrowGetState: Bool = false
    public var shouldThrowSetState: Bool = false
    /** 为 true 时 getStream() 抛错——等价触发 iOS “取 coordinator 抛错→failure” 路径。 */
    public var shouldThrowGetStream: Bool = false

    // ── 调用计数 ──────────────────────────────────────────────────────────────
    public var initializeCalls: Int64 = 0
    public var startQrEngagementCalls: Int64 = 0
    public var requestReceivedCalls: Int64 = 0
    public var sendResponseCalls: Int64 = 0
    public var getStateCalls: Int64 = 0
    public var setStateCalls: Int64 = 0
    public var stopPresentationCalls: Int64 = 0
    /** 最近一次 sendResponse 收到的 items（供断言响应已构建并下发）。 */
    public var lastSentItems: ?RequestItemConvertible = Option<RequestItemConvertible>.None
    /** 最近一次 setState 收到的状态。 */
    public var lastSetState: ?PresentationState = Option<PresentationState>.None

    public init() {}

    public prop sendableCurrentValueSubject: SendableCurrentValueSubject<PresentationState> {
        get() { this.subject }
    }

    // ── Registration-certificate layer (wallet-kit 0.40.x seam) ──────────────
    /** Verifier WRPRC policy fed to getVerifierRegistration (default None). */
    public var relyingPartyRegistrationValue: ?ProxWrpRegistrationPolicy = Option<ProxWrpRegistrationPolicy>.None
    /** ""-keyed (request-level) WRPRC violation messages (default none). */
    public var relyingPartyWarningViolationsValue: Array<String> = Array<String>()
    /** docId → over-asked leaf paths handed to the request bridge (default empty). */
    public var overaskedLeafPaths: HashMap<String, Array<Array<String>>> = HashMap<String, Array<Array<String>>>()

    public prop relyingPartyRegistration: ?ProxWrpRegistrationPolicy {
        get() { this.relyingPartyRegistrationValue }
    }

    public prop relyingPartyWarningViolations: Array<String> {
        get() { this.relyingPartyWarningViolationsValue }
    }

    public prop readerCertificateChain: ?Array<Array<UInt8>> {
        get() { Option<Array<Array<UInt8>>>.None }
    }

    public func overaskedLeafPathsByDocId(): HashMap<String, Array<Array<String>>> {
        return this.overaskedLeafPaths
    }

    public open func initialize(): Unit {
        this.initializeCalls += 1
        if (this.shouldThrowInitialize) { throw Exception(this.initializeError) }
    }

    public open func startQrEngagement(): String {
        this.startQrEngagementCalls += 1
        if (this.shouldThrowQr) { throw Exception(this.qrError) }
        return this.qrPayload
    }

    public open func currentRelyingParty(): String {
        return this.relyingPartyName
    }

    public open func requestReceived(): PresentationRequest {
        this.requestReceivedCalls += 1
        // iOS stubs WalletError(code: .trustError) here for the not-secured case.
        if (this.shouldThrowTrustError) { throw WalletCoreError.issuerNotTrusted() }
        if (this.shouldThrowRequestReceived) { throw Exception(this.requestReceivedError) }
        return this.request
    }

    public open func sendResponse(response: RequestItemConvertible): Unit {
        this.sendResponseCalls += 1
        this.lastSentItems = Some(response)
        if (this.shouldThrowSendResponse) { throw Exception(this.sendResponseError) }
    }

    public open func getState(): PresentationState {
        this.getStateCalls += 1
        if (this.shouldThrowGetState) { throw Exception("getState failed") }
        return this.state
    }

    public open func setState(presentationState: PresentationState): Unit {
        this.setStateCalls += 1
        this.lastSetState = Some(presentationState)
        if (this.shouldThrowSetState) { throw Exception("setState failed") }
    }

    public open func getStream(): SendableCurrentValueSubject<PresentationState> {
        if (this.shouldThrowGetStream) { throw Exception("getStream failed") }
        return this.subject
    }

    public open func stopPresentation(): Unit {
        this.stopPresentationCalls += 1
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FakeProximityWalletController —— 复用 FakeWalletKitController
// ─────────────────────────────────────────────────────────────────────────────
//
// FakeWalletKitController（dev_test_fakes.cj）已带：
//   - stopPresentationCalls          → stopPresentation() 计数（验证 interactor 调用引擎停止）
//   - revokedDocumentIds             → fetchRevokedDocuments() 返回
//   - documentById                   → fetchDocument(id:) 返回（buildRequestReceivedModel 用）
// 这里加一个开关：让 fetchRevokedDocuments 抛错，复现 iOS
//   “fetchRevokedDocuments throws 但 items 非空 → 仍成功” 的鲁棒性用例。
open class FakeProximityWalletController <: FakeWalletKitController {
    /** 为 true 时 fetchRevokedDocuments() 抛错（buildRequestReceivedModel 内部 try/catch 吞掉）。 */
    public var revokedThrows: Bool = false

    public override func fetchRevokedDocuments(): Array<String> {
        if (this.revokedThrows) { throw Exception("fetch revoked failed") }
        return this.revokedDocumentIds
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FakeProximityPresentationSession —— logic-core PresentationSession 的可配置 fake
// ─────────────────────────────────────────────────────────────────────────────
//
// 驱动**真实** ProximitySessionCoordinatorImpl（WP6 状态机）：
//   - emit(status)   模拟引擎 onStatusChange（EnginePresentationSession.notify），
//                    可按 ISO 18013-5 全序列逐个推送；
//   - sendResponse   只记录 onSent，不触发——由测试用 fireOnSent 模拟引擎 onSuccess，
//                    以断言 responseSent 仅在传输 ResponseSent 之后发布且只发布一次；
//   - stop()         计数，断言取消/返回会真正停引擎会话。
class FakeProximityPresentationSession <: PresentationSession {
    private var currentStatus: PresentationSessionStatus = PresentationSessionStatus.initializing
    private let observers = ArrayList<(PresentationSessionStatus) -> Unit>()

    /** deviceEngagement 返回值（None → coordinator.startQrEngagement 抛 unableToPresentAndShare）。 */
    public var engagement: ?String = Option<String>.None
    /** disclosedDocuments 返回值。 */
    public var documents: Array<DocElements> = Array<DocElements>()
    /** readerCertIssuer 返回值。 */
    public var issuer: ?String = Option<String>.None
    /** uiErrorDescription 返回值（sessionError 时进 PresentationState.error）。 */
    public var errorDescription: ?String = Option<String>.None

    public var startQrEngagementCalls: Int64 = 0
    public var receiveRequestCalls: Int64 = 0
    public var sendResponseCalls: Int64 = 0
    public var waitForDisconnectCalls: Int64 = 0
    public var stopCalls: Int64 = 0
    /** 最近一次 sendResponse 收到的 onSent（测试决定何时触发 = 引擎 onSuccess）。 */
    public var pendingOnSent: Option<(?String) -> Unit> = None

    public prop status: PresentationSessionStatus { get() { this.currentStatus } }
    public prop disclosedDocuments: Array<DocElements> { get() { this.documents } }
    public prop readerCertIssuer: ?String { get() { this.issuer } }
    public prop readerCertValidationMessage: ?String { get() { Option<String>.None } }
    public prop readerCertIssuerValid: ?Bool { get() { Some(true) } }
    public prop deviceEngagement: ?String { get() { this.engagement } }
    public prop uiErrorDescription: ?String { get() { this.errorDescription } }
    public prop disclosedDocumentSets: Array<DisclosedDocumentSet> { get() { Array<DisclosedDocumentSet>() } }
    public prop wrpVerifierPolicy: ?ProxWrpRegistrationPolicy { get() { Option<ProxWrpRegistrationPolicy>.None } }
    public prop wrpVerifierWarnings: ?HashMap<String, Array<PresentationPolicyViolation>> {
        get() { Option<HashMap<String, Array<PresentationPolicyViolation>>>.None }
    }
    public prop readerCertificateChain: ?Array<Array<UInt8>> { get() { Option<Array<Array<UInt8>>>.None } }

    public func observeStatus(observer: (PresentationSessionStatus) -> Unit): Unit {
        this.observers.add(observer)
        observer(this.currentStatus)
    }

    public func startQrEngagement(): Unit {
        this.startQrEngagementCalls += 1
    }

    public func receiveRequest(): Unit {
        this.receiveRequestCalls += 1
    }

    public func sendResponse(userAccepted: Bool, itemsToSend: RequestConvertibleItems, onSent: (?String) -> Unit): Unit {
        this.sendResponseCalls += 1
        this.pendingOnSent = Some(onSent)
    }

    public func waitForDisconnect(): Unit {
        this.waitForDisconnectCalls += 1
    }

    public func stop(): Unit {
        this.stopCalls += 1
    }

    /** 模拟引擎状态变化。 */
    func emit(status: PresentationSessionStatus): Unit {
        this.currentStatus = status
        for (o in this.observers) {
            o(status)
        }
    }

    /** 模拟引擎 onSuccess：触发（并清除）pending onSent。 */
    func fireOnSent(url: ?String): Unit {
        let cb = this.pendingOnSent
        this.pendingOnSent = Option<(?String) -> Unit>.None
        match (cb) {
            case Some(f) => f(url)
            case None => ()
        }
    }
}

/** PresentationState → 短名（供序列断言）。 */
func proximityStateName(s: PresentationState): String {
    match (s) {
        case loading => "loading"
        case prepareQr => "prepareQr"
        case qrReady(payload) => "qrReady:" + payload
        case requestReceived(_) => "requestReceived"
        case responseToSend(_) => "responseToSend"
        case responseSent(_) => "responseSent"
        case error(e) => "error:" + e.message
    }
}

/** 拼接序列（"a>b>c"）。 */
func joinNames(names: ArrayList<String>): String {
    var out = ""
    var i = 0
    while (i < names.size) {
        if (i > 0) { out += ">" }
        out += names[i]
        i++
    }
    return out
}

// ─────────────────────────────────────────────────────────────────────────────
// 测试数据构造
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 造一个带非空 docClaims 的 DocClaimsDecodable。
 * buildRequestReceivedModel 会对 request.items 里每个 docId 调 fetchDocument，
 * 再用其 docClaims 展开成可勾选 cell——需要非空 claims 才会产出 section（否则降级失败）。
 * 复用 FakeWalletKitController 的 documentById（单一字段，所有 id 都映射到它）。
 */
class ProximityDocClaims <: DocClaimsDecodable {
    private let id_: String
    private let claims_: Array<DocClaim>
    init(id_: String, claims_: Array<DocClaim>) {
        this.id_ = id_
        this.claims_ = claims_
    }
    public prop id: String { get() { this.id_ } }
    public prop statusIdentifier: ?StatusIdentifier { get() { None } }
    public prop createdAt: DateTime { get() { DateTime.now() } }
    public prop modifiedAt: ?DateTime { get() { None } }
    public prop displayName: ?String { get() { Some("ISO mDL") } }
    public prop docType: String { get() { "org.iso.18013.5.1.mDL" } }
    public prop docClaims: Array<DocClaim> { get() { this.claims_ } }
    public prop docDataFormat: DocDataFormat { get() { DocDataFormat.cbor } }
    public prop ageOverXX: HashMap<Int64, Bool> { get() { HashMap<Int64, Bool>() } }
    public prop display: ?Array<DisplayMetadata> { get() { None } }
    public prop issuerDisplay: ?Array<DisplayMetadata> { get() { None } }
    public prop credentialIssuerIdentifier: ?String { get() { None } }
    public prop configurationIdentifier: ?String { get() { None } }
    public prop validFrom: ?DateTime { get() { None } }
    public prop validUntil: ?DateTime { get() { None } }
    public prop secureAreaName: ?String { get() { None } }
    public prop credentialsUsageCounts: ?CredentialsUsageCounts { get() { None } }
    public prop credentialPolicy: CredentialPolicy { get() { CredentialPolicy.rotateUse } }
}

/** 造一个含单条 mDL mandatory-schema claim 的可披露文档。 */
func makeProximityDoc(docId!: String = "iso-mdl-id"): DocClaimsDecodable {
    let claim = DocClaim(
        name: "family_name",
        dataValue: DocDataValue.text("Doe"),
        stringValue: "Doe",
        namespace: Some("org.iso.18013.5.1")
    )
    return ProximityDocClaims(docId, [claim])
}

/** 造一个仅含一个被请求文档的 PresentationRequest。 */
func makeProximityRequest(
    docId!: String = "iso-mdl-id",
    relyingParty!: String = "Verifier",
    dataRequestInfo!: String = "info",
    isTrusted!: Bool = true
): PresentationRequest {
    PresentationRequest(
        items: [DocElements(docId)],
        relyingParty: relyingParty,
        dataRequestInfo: dataRequestInfo,
        isTrusted: isTrusted
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// 测试入口
// ─────────────────────────────────────────────────────────────────────────────
//
// 注：run 函数非 public（仓颉铁律 6：public func 不能带 internal 参 DeviceTestRun）。
func runFeatureProximityTests(t: DeviceTestRun): Unit {

    // ═══ onDeviceEngagement ════════════════════════════════════════════════════

    // ── [iOS 1] testOnDeviceEngagement_WhenCoordinatorInitializeSuccess_ThenVerifyCoordinatorInitializedAndState  ✅ ──
    // iOS: coordinator.initialize() 成功 → state==.success；verify initialize 被调。
    // CJ:  onDeviceEngagement() → EngagementSuccess；coordinator.initialize 计数==1。
    let coord1 = FakeProximityCoordinator()
    let inter1 = ProximityInteractorImpl(coordinator: coord1, walletController: FakeWalletKitController())
    let r1 = inter1.onDeviceEngagement()
    let ok1 = match (r1) { case EngagementSuccess => true; case _ => false }
    t.check(ok1, "proximity.onDeviceEngagement_success")
    t.eqInt(coord1.initializeCalls, 1, "proximity.onDeviceEngagement_initializeCalled")

    // ── [iOS 2] testOnDeviceEngagement_WhenCoordinatorInitializeThrowsError_ThenVerifyStateError  ✅ ──
    // iOS: initialize() 抛错 → state==.failure，错误文本透传。
    // CJ:  onDeviceEngagement() → EngagementFailure(msg)，msg 透传 initialize 抛出的消息。
    let coord2 = FakeProximityCoordinator()
    coord2.shouldThrowInitialize = true
    coord2.initializeError = "engagement boom"
    let inter2 = ProximityInteractorImpl(coordinator: coord2, walletController: FakeWalletKitController())
    let r2 = inter2.onDeviceEngagement()
    match (r2) {
        case EngagementFailure(m) =>
            t.check(true, "proximity.onDeviceEngagement_throws_failure")
            t.eqStr(m, "engagement boom", "proximity.onDeviceEngagement_throws_errorText")
        case _ => t.check(false, "proximity.onDeviceEngagement_throws_failure")
    }

    // ═══ getStream / getSessionStatePublisher ══════════════════════════════════

    // ── [iOS 3] testGetSessionStatePublisher_WhenCoordinatorIsValid_ThenVerifyStateSuccess  ✅ ──
    // iOS: 取 publisher 成功 → state==.success。
    // CJ:  补齐架构 seam：现暴露 getSessionStatePublisher(): ProximityPublisherResult
    //      （镜像 iOS ProximityPublisherPartialState）。coordinator 有效 → ProximityPublisherSuccess。
    //      （同时保留下层 getStream() 的 Some 断言作为薄封装一致性校验。）
    let coord3 = FakeProximityCoordinator()
    let inter3 = ProximityInteractorImpl(coordinator: coord3, walletController: FakeWalletKitController())
    let pub3 = match (inter3.getSessionStatePublisher()) {
        case ProximityPublisherSuccess(_) => true; case _ => false
    }
    t.check(pub3, "proximity.getSessionStatePublisher_valid_success")
    let ok3 = match (inter3.getStream()) { case Some(_) => true; case None => false }
    t.check(ok3, "proximity.getStream_valid_someSubject")

    // ── [iOS 4] testGetSessionStatePublisher_WhenCoordinatorIsNotValid_ThenVerifyStateFailure  ✅ (等价触发) ──
    // iOS: 令 sessionHolder.getActiveProximityCoordinator() 抛错 → state==.failure。
    // CJ:  无 holder；等价触发方式=注入一个 getStream()（liveness 探针）抛错的 fake
    //      coordinator → getSessionStatePublisher 走 catch → ProximityPublisherFailure，
    //      错误文本透传（iOS 校验 error 相等）。
    let coord4 = FakeProximityCoordinator()
    coord4.shouldThrowGetStream = true
    let inter4 = ProximityInteractorImpl(coordinator: coord4, walletController: FakeWalletKitController())
    match (inter4.getSessionStatePublisher()) {
        case ProximityPublisherFailure(m) =>
            t.check(true, "proximity.getSessionStatePublisher_invalid_failure (erroring fake coordinator)")
            t.eqStr(m, "getStream failed", "proximity.getSessionStatePublisher_invalid_errorText")
        case _ => t.check(false, "proximity.getSessionStatePublisher_invalid_failure")
    }

    // ── [iOS 5] testGetCoordinator_WhenCoordinatorIsValid_ThenVerifyStateSuccess  ✅ ──
    // iOS: interactor.getCoordinator() 成功（验证从 holder 取到 coordinator）。
    // CJ:  补齐架构 seam：现暴露 getCoordinator(): ProximityCoordinatorResult（镜像 iOS
    //      ProximityCoordinatorPartialState）。直注设计里 coordinator 恒在，liveness 探针
    //      不抛 → ProximityCoordinatorSuccess。
    let coord5 = FakeProximityCoordinator()
    let inter5 = ProximityInteractorImpl(coordinator: coord5, walletController: FakeWalletKitController())
    let co5 = match (inter5.getCoordinator()) {
        case ProximityCoordinatorSuccess(_) => true; case _ => false
    }
    t.check(co5, "proximity.getCoordinator_valid_success")

    // ── [iOS 6] testGetCoordinator_WhenCoordinatorIsNotValid_ThenVerifyStateSuccess  ✅ (等价触发) ──
    // iOS: getActiveProximityCoordinator().thenThrow → getCoordinator() 失败。
    // CJ:  等价触发：注入 getStream() 抛错的 fake coordinator（liveness 探针失败）→
    //      ProximityCoordinatorFailure，错误文本透传。直注设计里“coordinator 不可用”的等价失败路径。
    let coord6 = FakeProximityCoordinator()
    coord6.shouldThrowGetStream = true
    let inter6 = ProximityInteractorImpl(coordinator: coord6, walletController: FakeWalletKitController())
    match (inter6.getCoordinator()) {
        case ProximityCoordinatorFailure(m) =>
            t.check(true, "proximity.getCoordinator_invalid_failure (erroring fake coordinator)")
            t.eqStr(m, "getStream failed", "proximity.getCoordinator_invalid_errorText")
        case _ => t.check(false, "proximity.getCoordinator_invalid_failure")
    }

    // ═══ onQRGeneration ════════════════════════════════════════════════════════

    // ── [iOS 7] testOnQRGeneration_WhenCoordinatorStartQrEngagementReturnsValidData_ThenVerifySuccessAndImage  ✅(行为等价) ──
    // iOS: startQrEngagement() 返回 UIImage("qrcode") → state==.success(image)，比对 pngData 大小。
    // CJ:  ⚠️ 平台差异：CJ coordinator.startQrEngagement() 返回 device-engagement 字符串
    //      （"mdoc:" + base64url(CBOR)），由 ArkUI QRCode 组件渲染，非 UIImage（鸿蒙无 UIKit）。
    //      行为等价为“成功返回非空载荷且与注入一致”。
    let coord7 = FakeProximityCoordinator()
    coord7.qrPayload = "mdoc:owBjMS4wAYIB2BhYS6QBAiABIVggAQID"
    let inter7 = ProximityInteractorImpl(coordinator: coord7, walletController: FakeWalletKitController())
    let r7 = inter7.onQRGeneration()
    match (r7) {
        case QrSuccess(payload) =>
            t.check(true, "proximity.onQRGeneration_validData_success")
            t.eqStr(payload, "mdoc:owBjMS4wAYIB2BhYS6QBAiABIVggAQID", "proximity.onQRGeneration_validData_payload")
        case _ =>
            t.check(false, "proximity.onQRGeneration_validData_success")
    }
    t.check(coord7.startQrEngagementCalls == 1, "proximity.onQRGeneration_startQrCalled")

    // ── [iOS 8] testOnQRGeneration_WhenCoordinatorStartQrEngagementThrowsError_ThenVerifyFailure  ✅ ──
    // iOS: startQrEngagement() 抛 PresentationSessionError.qrGeneration → state==.failure。
    // CJ:  onQRGeneration() → QrFailure(msg)，msg 透传抛出的错误文本。
    let coord8 = FakeProximityCoordinator()
    coord8.shouldThrowQr = true
    coord8.qrError = "qr boom"
    let inter8 = ProximityInteractorImpl(coordinator: coord8, walletController: FakeWalletKitController())
    let r8 = inter8.onQRGeneration()
    match (r8) {
        case QrFailure(m) =>
            t.check(true, "proximity.onQRGeneration_throws_failure")
            t.eqStr(m, "qr boom", "proximity.onQRGeneration_throws_errorText")
        case _ => t.check(false, "proximity.onQRGeneration_throws_failure")
    }

    // ── [iOS 9] testOnQRGeneration_WhenCoordinatorStartQrEngagementReturnsInValidData_ThenVerifyFailure  ✅(等价于 8) ──
    // iOS: 此 case 与 8 实现完全相同（都令 startQrEngagement() 抛 qrGeneration 错误）。
    //      “InvalidData”在 CJ 由 ProximitySessionCoordinatorImpl.startQrEngagement 内部
    //      抛 WalletCoreError 表达（deviceEngagement/qrCodeImage 为 None 时）；interactor
    //      层无从区分“无效数据”与“抛错”，二者都归为 QrFailure。故用一条抛错断言覆盖。
    let coord9 = FakeProximityCoordinator()
    coord9.shouldThrowQr = true
    coord9.qrError = "invalid engagement data"
    let inter9 = ProximityInteractorImpl(coordinator: coord9, walletController: FakeWalletKitController())
    let r9 = inter9.onQRGeneration()
    let ok9 = match (r9) { case QrFailure(_) => true; case _ => false }
    t.check(ok9, "proximity.onQRGeneration_invalidData_failure")

    // ═══ stopPresentation ══════════════════════════════════════════════════════

    // ── [iOS 10] testStopPresentation_WhenWalletKitControllerStopPresenation_ThenVerifyWalletKitControllerStopPresentation  ✅ ──
    // iOS: interactor.stopPresentation() → verify walletKitController.stopPresentation()。
    // CJ:  stopPresentation() 同时调 walletController.stopPresentation() 与
    //      coordinator.stopPresentation()。断言 wallet 侧计数==1（与 iOS 等价）+ coordinator 侧==1。
    let coord10 = FakeProximityCoordinator()
    let wallet10 = FakeWalletKitController()
    let inter10 = ProximityInteractorImpl(coordinator: coord10, walletController: wallet10)
    inter10.stopPresentation()
    t.eqInt(wallet10.stopPresentationCalls, 1, "proximity.stopPresentation_walletStopped")
    t.eqInt(coord10.stopPresentationCalls, 1, "proximity.stopPresentation_coordinatorStopped")

    // ═══ onRequestReceived ═════════════════════════════════════════════════════

    // ── [iOS 11] testOnRequestReceived_WhenCoordinatorRequestReceivedReturnsSuccess_ThenVerifySuccessState  ✅(行为等价) ──
    // iOS: requestReceived() 返回 request + parseDocClaim 产 uiModels + 无吊销
    //      → state==.success(uimodels, relyingParty, dataRequestInfo, isTrusted)。
    // CJ:  ⚠️ 数据建模差异：iOS 用 parseDocClaim 把 docClaim 解析成 RequestDataUiModel；
    //      CJ 的 buildRequestReceivedModel 改为从 fetchDocument(docId).docClaims 读取并
    //      展开成 RequestDataSection/Cell（见 feature-common/request_bridge.cj 文档注释）。
    //      行为等价为：成功 + relyingParty/isTrusted 透传 + 产出非空 section。
    let coord11 = FakeProximityCoordinator()
    coord11.request = makeProximityRequest(docId: "iso-mdl-id", relyingParty: "ACME Verifier", isTrusted: true)
    let wallet11 = FakeProximityWalletController()
    wallet11.documentById = Some(makeProximityDoc(docId: "iso-mdl-id"))  // fetchDocument → 带 claims 的文档
    wallet11.revokedDocumentIds = Array<String>()                         // 无吊销
    let inter11 = ProximityInteractorImpl(coordinator: coord11, walletController: wallet11)
    let model11 = inter11.onRequestReceived()
    t.check(model11.isSuccess, "proximity.onRequestReceived_success")
    t.eqStr(model11.relyingParty, "ACME Verifier", "proximity.onRequestReceived_relyingParty")
    t.check(model11.isTrusted, "proximity.onRequestReceived_isTrusted")
    // iOS 95b71766: 成功负载携带 RelyingPartyRegistration（fake wallet 基线：
    // notSupported + access-cert 名字/徽章 → isFullyVerified 跟随 isTrusted）。
    match (model11.relyingPartyRegistration) {
        case Some(reg11) =>
            t.check(true, "proximity.onRequestReceived_carriesRegistration")
            t.eqStr(reg11.name ?? "", "ACME Verifier", "proximity.onRequestReceived_registrationName")
            t.check(reg11.isFullyVerified, "proximity.onRequestReceived_registrationFullyVerified")
        case None => t.check(false, "proximity.onRequestReceived_carriesRegistration")
    }
    t.check(model11.sections.size > 0, "proximity.onRequestReceived_hasSections")
    if (model11.sections.size > 0) {
        // iOS proximity 固定把已提供字段映射为 isRequired=false。即使
        // family_name 在 mDL schema 中是 mandatory，持有人仍可取消披露。
        t.check(model11.sections[0].cells.size > 0, "proximity.onRequestReceived_sectionHasCells")
        if (model11.sections[0].cells.size > 0) {
            t.check(model11.sections[0].cells[0].selectable,
                "proximity.onRequestReceived_mandatorySchemaClaimIsSelectable")
        }
    }

    // ── [iOS 12] testOnRequestReceived_WhenCoordinatorRequestReceivedThrowsError_ThenVerifyFailureState  ✅ ──
    // iOS: requestReceived() 抛 PresentationSessionError.conversionToRequestItemModel → state==.failure。
    // CJ:  onRequestReceived() → RequestReceivedModel.failure(msg)，msg 透传。
    let coord12 = FakeProximityCoordinator()
    coord12.shouldThrowRequestReceived = true
    coord12.requestReceivedError = "conversion failed"
    let inter12 = ProximityInteractorImpl(coordinator: coord12, walletController: FakeProximityWalletController())
    let model12 = inter12.onRequestReceived()
    t.check(!model12.isSuccess, "proximity.onRequestReceived_throws_failure")
    t.eqStr(model12.errorMessage, "conversion failed", "proximity.onRequestReceived_throws_errorText")

    // ── testOnRequestReceived_WhenCoordinatorRequestReceivedThrowsTrustError_ThenVerifyNotSecuredRequest ──
    // iOS: requestReceived() 抛 WalletError(.trustError) → state==.notSecuredRequest（非 .failure）。
    // CJ:  onRequestReceived() 经 isTrustBlocked 分流到 RequestReceivedModel.notSecuredRequest()。
    let coordTrust = FakeProximityCoordinator()
    coordTrust.shouldThrowTrustError = true
    let interTrust = ProximityInteractorImpl(
        coordinator: coordTrust, walletController: FakeProximityWalletController()
    )
    let modelTrust = interTrust.onRequestReceived()
    t.check(modelTrust.isNotSecuredRequest, "proximity.onRequestReceived_trustError_notSecuredRequest")
    t.check(!modelTrust.isSuccess, "proximity.onRequestReceived_trustError_notSuccess")
    t.eqStr(modelTrust.errorMessage, "", "proximity.onRequestReceived_trustError_noGenericErrorMessage")

    // ── [iOS 17→95b71766] testOnRequestReceived_WhenAllDocumentsAreRevoked_ThenStillSucceeds ──
    // iOS 95b71766 移除了空 combinations 早退：全部被吊销 → sections 为空但仍
    // .success（不可满足的请求也要显示是谁在要）。
    // CJ:  buildRequestReceivedModel 同步移除空 sections 早退：成功 + 0 section +
    //      relyingParty 透传 + 成功负载携带 RelyingPartyRegistration。
    let coord17 = FakeProximityCoordinator()
    coord17.request = makeProximityRequest(docId: "iso-mdl-id")
    let wallet17 = FakeProximityWalletController()
    wallet17.documentById = Some(makeProximityDoc(docId: "iso-mdl-id"))
    wallet17.revokedDocumentIds = ["iso-mdl-id"]   // 唯一被请求文档被吊销
    let inter17 = ProximityInteractorImpl(coordinator: coord17, walletController: wallet17)
    let model17 = inter17.onRequestReceived()
    t.check(model17.isSuccess, "proximity.onRequestReceived_allRevoked_stillSuccess (iOS 95b71766)")
    t.eqInt(model17.sections.size, 0, "proximity.onRequestReceived_allRevoked_noSections")
    t.eqStr(model17.relyingParty, "Verifier", "proximity.onRequestReceived_allRevoked_showsWhoAsked")
    let hasReg17 = match (model17.relyingPartyRegistration) { case Some(_) => true; case None => false }
    t.check(hasReg17, "proximity.onRequestReceived_allRevoked_carriesRegistration")

    // ── [iOS 18] testOnRequestReceived_WhenFetchRevokedDocumentsThrowsAndItemsNotEmpty_ThenVerifySuccessState  ✅(行为等价) ──
    // iOS: fetchRevokedDocuments() 抛错但 items 非空 → 仍 state==.success（鲁棒性）。
    // CJ:  ⚠️ buildRequestReceivedModel 用 try/catch 吞掉 fetchRevokedDocuments 异常
    //      （revoked 当作空），文档仍可展开 → 成功。断言成功 + 有 section。
    let coord18 = FakeProximityCoordinator()
    coord18.request = makeProximityRequest(docId: "iso-mdl-id")
    let wallet18 = FakeProximityWalletController()
    wallet18.documentById = Some(makeProximityDoc(docId: "iso-mdl-id"))
    wallet18.revokedThrows = true   // fetchRevokedDocuments 抛错 → 被吞，按无吊销处理
    let inter18 = ProximityInteractorImpl(coordinator: coord18, walletController: wallet18)
    let model18 = inter18.onRequestReceived()
    t.check(model18.isSuccess, "proximity.onRequestReceived_revokedThrowsItemsNotEmpty_success")
    t.check(model18.sections.size > 0, "proximity.onRequestReceived_revokedThrows_hasSections")

    // ── [iOS decodeRequest + itemSets.first] 同 docType 多份文档 → 同一组合、每份一张卡 ──
    // iOS: PresentationSession.decodeRequest 遍历全部已存文档，docType 匹配的每一份
    //      各生成一个 DocElements 并追加到同一个 disclosedElements，整个请求只产出
    //      一个 DisclosedDocumentSet；ProximityInteractor 取 itemSets.first 后
    //      toUiModels 是 compactMap —— 4 份 PID 就是 4 张各带字段复选框的卡。
    // CJ:  logic_core 曾把这一个集合按 matchedDocIds 做笛卡尔积拆成 4 个单文档组合，
    //      proximity 取 combinations[0] 后只剩 1 份。这里钉住：1 个组合、4 个 section。
    let coordMulti = FakeProximityCoordinator()
    let pidIds = ["pid-a", "pid-b", "pid-c", "pid-d"]
    let pidElements = ArrayList<DocElements>()
    for (id in pidIds) { pidElements.add(DocElements(id)) }
    coordMulti.request = PresentationRequest(
        items: pidElements.toArray(),
        relyingParty: "Verifier",
        dataRequestInfo: "info",
        isTrusted: true,
        itemSets: [pidElements.toArray()]
    )
    let walletMulti = FakeProximityWalletController()
    walletMulti.documentById = Some(makeProximityDoc(docId: "pid-a"))
    let interMulti = ProximityInteractorImpl(coordinator: coordMulti, walletController: walletMulti)
    let modelMulti = interMulti.onRequestReceived()
    t.check(modelMulti.isSuccess, "proximity.onRequestReceived_fourSameTypeDocs_success")
    t.eqInt(modelMulti.combinations.size, 1, "proximity.onRequestReceived_fourSameTypeDocs_oneCombination")
    t.eqInt(modelMulti.sections.size, 4, "proximity.onRequestReceived_fourSameTypeDocs_fourSections")

    // ═══ onResponsePrepare ═════════════════════════════════════════════════════

    // ── [iOS 13] testOnResponsePrepare_WhenRequestItemsContainDataOrVerificationRows_ThenVerifySuccessStateAndRequestItems  ✅(行为等价) ──
    // iOS: requestItems 含可分享行 → state==.success(request)，request.items==mockRequestItems；
    //      verify coordinator.setState(presentationState:)。
    // CJ:  ⚠️ 形态差异：CJ onResponsePrepare(selected: ArrayList<RequestDataCell>): Bool。
    //      它经 buildRequestConvertible(selected, claimIndex) 反查 → 非空才 setState 并返回 true。
    //      关键：claimIndex 是 interactor 私有、在 onRequestReceived 时填充的。
    //      因此必须先跑 onRequestReceived 建索引，再用其产出的 cell 调 onResponsePrepare，
    //      才能命中 claimIndex（否则 convertible 为空 → false）。
    let coord13 = FakeProximityCoordinator()
    coord13.request = makeProximityRequest(docId: "iso-mdl-id")
    let wallet13 = FakeProximityWalletController()
    wallet13.documentById = Some(makeProximityDoc(docId: "iso-mdl-id"))
    let inter13 = ProximityInteractorImpl(coordinator: coord13, walletController: wallet13)
    let model13 = inter13.onRequestReceived()   // 先建 claimIndex
    let selected13 = ArrayList<RequestDataCell>()
    if (model13.sections.size > 0) {
        for (cell in model13.sections[0].cells) { selected13.add(cell) }  // 选中该 section 的全部 cell
    }
    let prepared13 = inter13.onResponsePrepare(selected13)
    t.check(prepared13, "proximity.onResponsePrepare_withRows_true")
    // setState 被调用（iOS verify setState）；且写入的是 responseToSend。
    t.check(coord13.setStateCalls == 1, "proximity.onResponsePrepare_setStateCalled")
    let isResponseToSend13 = match (coord13.lastSetState) {
        case Some(s) => match (s) { case responseToSend(_) => true; case _ => false }
        case None => false
    }
    t.check(isResponseToSend13, "proximity.onResponsePrepare_setState_responseToSend")

    // ── [iOS 14] testOnResponsePrepare_WhenRequestItemsDoNotContainDataOrVerificationRows_ThenVerifyFailureState  ✅(行为等价) ──
    // iOS: requestItems 不含可分享行（dropLast 去掉唯一行）→ state==.failure(conversionToRequestItemModel)。
    // CJ:  ⚠️ 形态差异：空选择 → buildRequestConvertible 产空 convertible → onResponsePrepare 返回 false，
    //      且不调 setState。断言 false + setState 未被调（错误文案由 view 层补，interactor 只回 Bool）。
    let coord14 = FakeProximityCoordinator()
    let wallet14 = FakeProximityWalletController()
    let inter14 = ProximityInteractorImpl(coordinator: coord14, walletController: wallet14)
    let empty14 = ArrayList<RequestDataCell>()   // 无任何选中行
    let prepared14 = inter14.onResponsePrepare(empty14)
    t.check(!prepared14, "proximity.onResponsePrepare_noRows_false")
    t.eqInt(coord14.setStateCalls, 0, "proximity.onResponsePrepare_noRows_setStateNotCalled")

    // ── [iOS 15(后半)] testOnResponsePrepare_WhenGetActiveProximityCoordinatorThrowsError_ThenVerifyFailureState  ⚠️/❌ ──
    // iOS: getActiveProximityCoordinator() 抛错 → state==.failure(generic)。
    // CJ:  ❌ 无 holder 间接层，coordinator 取用不抛错。最接近的等价：coordinator.setState 抛错
    //      时 onResponsePrepare 应回 false（catch 兜底）。这是 CJ 自有的失败路径（非 iOS 原义，
    //      但验证 interactor 对 coordinator 异常的容错），标 ⚠️。
    let coord15 = FakeProximityCoordinator()
    coord15.request = makeProximityRequest(docId: "iso-mdl-id")
    coord15.shouldThrowSetState = true   // setState 抛错 → interactor catch → false
    let wallet15 = FakeProximityWalletController()
    wallet15.documentById = Some(makeProximityDoc(docId: "iso-mdl-id"))
    let inter15 = ProximityInteractorImpl(coordinator: coord15, walletController: wallet15)
    let model15 = inter15.onRequestReceived()   // 建 claimIndex
    let selected15 = ArrayList<RequestDataCell>()
    if (model15.sections.size > 0) {
        for (cell in model15.sections[0].cells) { selected15.add(cell) }
    }
    let prepared15 = inter15.onResponsePrepare(selected15)
    t.check(!prepared15, "proximity.onResponsePrepare_setStateThrows_false")

    // ═══ onSendResponse ════════════════════════════════════════════════════════

    // ── [iOS 16a] testOnSendResponse_WhenCoordinatorPresentationStateIsResponseToSend_ThenverifySuccessState  ✅ ──
    // iOS: getState()==.responseToSend → sendResponse 被调 → state==.sent；verify getState + sendResponse。
    // CJ:  getState()==responseToSend(item) → coordinator.sendResponse(item) → ProximitySent。
    let coord16a = FakeProximityCoordinator()
    coord16a.state = PresentationState.responseToSend(RequestItemsWrapper())  // 处于待发送状态
    let inter16a = ProximityInteractorImpl(coordinator: coord16a, walletController: FakeWalletKitController())
    let r16a = inter16a.onSendResponse()
    let ok16a = match (r16a) { case ProximitySent => true; case _ => false }
    t.check(ok16a, "proximity.onSendResponse_responseToSend_sent")
    t.check(coord16a.getStateCalls == 1, "proximity.onSendResponse_getStateCalled")
    t.check(coord16a.sendResponseCalls == 1, "proximity.onSendResponse_sendResponseCalled")

    // ── [iOS 16b] testOnSendResponse_WhenCoordinatorPresentationStateIsNotResponseToSend_ThenVerifyFailureState  ✅ ──
    // iOS: getState()==.prepareQr（非 responseToSend）→ state==.failure(invalidState)；verify getState。
    // CJ:  getState() 非 responseToSend → ProximitySendFailure("Invalid presentation state")，不调 sendResponse。
    let coord16b = FakeProximityCoordinator()
    coord16b.state = PresentationState.prepareQr
    let inter16b = ProximityInteractorImpl(coordinator: coord16b, walletController: FakeWalletKitController())
    let r16b = inter16b.onSendResponse()
    match (r16b) {
        case ProximitySendFailure(m) =>
            t.check(true, "proximity.onSendResponse_notResponseToSend_failure")
            t.eqStr(m, "Invalid presentation state", "proximity.onSendResponse_notResponseToSend_invalidStateText")
        case _ => t.check(false, "proximity.onSendResponse_notResponseToSend_failure")
    }
    t.check(coord16b.getStateCalls == 1, "proximity.onSendResponse_notResponseToSend_getStateCalled")
    t.eqInt(coord16b.sendResponseCalls, 0, "proximity.onSendResponse_notResponseToSend_sendResponseNotCalled")

    // ── [iOS 16c] testOnSendResponse_WhenCoordinatorPresentationStateIsResponseToSendAndSendResponseThrowsError_ThenVerifyFailureState  ✅(行为等价) ──
    // ── testOnSendResponse_WhenGetActiveProximityCoordinatorThrowsError_ThenVerifyFailureState  ⚠️(与上一条共用同一段断言) ──
    //     后者在 iOS 里是“取 coordinator 时就抛错”，CJ 无 holder 故无此触发点，
    //     只能落在同一处 sendResponse 抛错的断言上。两条 iOS 用例共用一份证据，
    //     不是各自独立验证，故台账记 ⚠️ 而非 ✅（同 #236/#282 的判定口径）。
    // iOS: state==.responseToSend 但发送链路抛错 → state==.failure(invalidState)；times(0) getState/sendResponse
    //      （因 iOS 在 getActiveProximityCoordinator 处先抛，根本没进 getState）。
    // CJ:  ⚠️ 路径不同：CJ 无 holder，getState 正常返回 responseToSend，进入 sendResponse 时抛错 →
    //      interactor catch → ProximitySendFailure(透传 sendResponse 的错误文本)。
    //      故 getState/sendResponse 各被调 1 次（iOS 是 0 次，因更早抛错；这是架构差异）。断言失败结果 + 错误文本透传。
    let coord16c = FakeProximityCoordinator()
    coord16c.state = PresentationState.responseToSend(RequestItemsWrapper())
    coord16c.shouldThrowSendResponse = true
    coord16c.sendResponseError = "send link broke"
    let inter16c = ProximityInteractorImpl(coordinator: coord16c, walletController: FakeWalletKitController())
    let r16c = inter16c.onSendResponse()
    match (r16c) {
        case ProximitySendFailure(m) =>
            t.check(true, "proximity.onSendResponse_sendThrows_failure")
            t.eqStr(m, "send link broke", "proximity.onSendResponse_sendThrows_errorText")
        case _ => t.check(false, "proximity.onSendResponse_sendThrows_failure")
    }

    // ═══ NoopProximityInteractor（平台降级 fallback，无 iOS 对应）═══════════════
    // CJ 自有：无引擎接入时的 no-op interactor（镜像 iOS “capability unavailable” 降级）。
    // 不对应任何 iOS case，但作为 proximity 平台受限的显式降级路径，验证其行为一致：
    // 所有操作都安全失败/no-op，不伪造成功。
    let noop = NoopProximityInteractor()
    let nOk1 = match (noop.onDeviceEngagement()) { case EngagementFailure(_) => true; case _ => false }
    t.check(nOk1, "proximity.noop_onDeviceEngagement_failure")
    let nOk2 = match (noop.onQRGeneration()) { case QrFailure(_) => true; case _ => false }
    t.check(nOk2, "proximity.noop_onQRGeneration_failure")
    t.check(!noop.onRequestReceived().isSuccess, "proximity.noop_onRequestReceived_failure")
    t.check(!noop.onResponsePrepare(ArrayList<RequestDataCell>()), "proximity.noop_onResponsePrepare_false")
    let nOk3 = match (noop.onSendResponse()) { case ProximitySendFailure(_) => true; case _ => false }
    t.check(nOk3, "proximity.noop_onSendResponse_failure")
    let nOk4 = match (noop.getStream()) { case None => true; case Some(_) => false }
    t.check(nOk4, "proximity.noop_getStream_none")
    // 新增架构 seam 访问器在 Noop 上也应诚实失败（不伪造 coordinator/stream）。
    let nOk5 = match (noop.getSessionStatePublisher()) { case ProximityPublisherFailure(_) => true; case _ => false }
    t.check(nOk5, "proximity.noop_getSessionStatePublisher_failure")
    let nOk6 = match (noop.getCoordinator()) { case ProximityCoordinatorFailure(_) => true; case _ => false }
    t.check(nOk6, "proximity.noop_getCoordinator_failure")

    // ── seam 契约：一个 disclosedDocumentSet 的全部文档留在同一个 itemSet ──
    // iOS: itemSets = disclosedDocumentSets.map(\.docElements)，集合内文档不拆分。
    let sessMulti = FakeProximityPresentationSession()
    sessMulti.documents = [DocElements("pid-a"), DocElements("pid-b"), DocElements("pid-c"), DocElements("pid-d")]
    sessMulti.issuer = Some("ACME Reader")
    let coordSets = ProximitySessionCoordinatorImpl(sessMulti)
    let reqMulti = coordSets.requestReceived()
    t.eqInt(reqMulti.itemSets.size, 1, "proximity.coordinator_fourDocsOneSet_oneItemSet")
    if (reqMulti.itemSets.size == 1) {
        t.eqInt(reqMulti.itemSets[0].size, 4, "proximity.coordinator_fourDocsOneSet_allFourKept")
    }

    // ═══ WP6：真实 ProximitySessionCoordinatorImpl × fake 引擎会话（状态机）═══════
    // 无 iOS 对应（iOS 协调器无单测）；覆盖 iOS `$status` 管线的仓颉等价实现。

    // ── 完整 ISO 18013-5 状态序列 → 4 态 UI 流映射 ──
    // initializing→initialized→poweredOn→qrEngagementReady→connected→started→
    // requestReceived→userSelected→responseSent→disconnected 只应产出
    // prepareQr / requestReceived / responseSent 三个 UI 状态（sink 先回放 loading）；
    // 传输级步骤不产 UI 状态，sessionError → error(uiErrorDescription)。
    let sessA = FakeProximityPresentationSession()
    sessA.documents = [DocElements("iso-mdl-id")]
    sessA.issuer = Some("ACME Reader")
    let coordA = ProximitySessionCoordinatorImpl(sessA)
    let seenA = ArrayList<String>()
    coordA.getStream().sink({ s => seenA.add(proximityStateName(s)) })
    sessA.emit(PresentationSessionStatus.initialized)
    sessA.emit(PresentationSessionStatus.poweredOn)
    sessA.emit(PresentationSessionStatus.qrEngagementReady)
    sessA.emit(PresentationSessionStatus.connected)
    sessA.emit(PresentationSessionStatus.started)
    sessA.emit(PresentationSessionStatus.requestReceived)
    sessA.emit(PresentationSessionStatus.userSelected)
    sessA.emit(PresentationSessionStatus.responseSent)
    sessA.emit(PresentationSessionStatus.disconnected)
    t.eqStr(joinNames(seenA), "loading>prepareQr>requestReceived>responseSent",
        "proximity.coordinator_fullStatusSequence_mapsTo4CaseUiStream")
    sessA.errorDescription = Some("radio lost")
    sessA.emit(PresentationSessionStatus.sessionError)
    t.eqInt(seenA.size, 5, "proximity.coordinator_sessionError_emitsError")
    if (seenA.size == 5) {
        t.eqStr(seenA[4], "error:radio lost", "proximity.coordinator_sessionError_carriesUiErrorDescription")
    }
    t.eqStr(coordA.currentRelyingParty(), "ACME Reader", "proximity.coordinator_currentRelyingParty_readerCertIssuer")
    // requestReceived 载荷携带 disclosedDocuments + readerCertIssuer。
    let reqA = coordA.requestReceived()
    t.eqStr(reqA.relyingParty, "ACME Reader", "proximity.coordinator_requestReceived_relyingParty")
    t.eqInt(reqA.items.size, 1, "proximity.coordinator_requestReceived_items")

    // ── 取消 / 返回：stopPresentation 真正停引擎会话（HarmonyOS 无 ARC 释放）──
    // interactor.stopPresentation → wallet.stopPresentation（引擎 stopPresentation）
    // + coordinator.stopPresentation → session.stop()；订阅取消后状态不再进流。
    let sessB = FakeProximityPresentationSession()
    let coordB = ProximitySessionCoordinatorImpl(sessB)
    let walletB = FakeWalletKitController()
    let interB = ProximityInteractorImpl(coordinator: coordB, walletController: walletB)
    let seenB = ArrayList<String>()
    coordB.getStream().sink({ s => seenB.add(proximityStateName(s)) })
    interB.stopPresentation()
    t.eqInt(sessB.stopCalls, 1, "proximity.stopPresentation_cancel_stopsEngineSession")
    t.eqInt(walletB.stopPresentationCalls, 1, "proximity.stopPresentation_cancel_stopsWalletPresentation")
    sessB.emit(PresentationSessionStatus.qrEngagementReady)
    t.eqInt(seenB.size, 1, "proximity.stopPresentation_cancel_statusAfterStopIgnored")

    // ── responseSent 仅在引擎 onSuccess（传输 ResponseSent）之后，且只发布一次 ──
    let sessC = FakeProximityPresentationSession()
    let coordC = ProximitySessionCoordinatorImpl(sessC)
    var sentCountC: Int64 = 0
    let sentCellC = Array<Int64>(1, repeat: 0)
    coordC.getStream().sink({ s =>
        match (s) {
            case responseSent(_) => sentCellC[0] = sentCellC[0] + 1
            case _ => ()
        }
    })
    coordC.setState(PresentationState.responseToSend(RequestItemsWrapper()))
    coordC.sendResponse(RequestItemsWrapper())
    sentCountC = sentCellC[0]
    t.eqInt(sessC.sendResponseCalls, 1, "proximity.sendResponse_forwardsToSession")
    t.eqInt(sessC.waitForDisconnectCalls, 1, "proximity.sendResponse_waitsForDisconnect")
    t.eqInt(sentCountC, 0, "proximity.sendResponse_noResponseSentBeforeOnSuccess")
    let stillToSendC = match (coordC.getState()) { case responseToSend(_) => true; case _ => false }
    t.check(stillToSendC, "proximity.sendResponse_stateStaysResponseToSendUntilOnSuccess")
    sessC.fireOnSent(Option<String>.None)          // 引擎 onSuccess
    t.eqInt(sentCellC[0], 1, "proximity.sendResponse_responseSentAfterOnSuccess")
    sessC.emit(PresentationSessionStatus.responseSent)   // 传输状态回声
    t.eqInt(sentCellC[0], 1, "proximity.sendResponse_responseSentPublishedOnce")

    // 反向时序：状态先到（引擎 setStatus(ResponseSent) 在 onSuccess 内），onSent 后到 → 同样只发布一次。
    let sessC2 = FakeProximityPresentationSession()
    let coordC2 = ProximitySessionCoordinatorImpl(sessC2)
    let sentCellC2 = Array<Int64>(1, repeat: 0)
    coordC2.getStream().sink({ s =>
        match (s) {
            case responseSent(_) => sentCellC2[0] = sentCellC2[0] + 1
            case _ => ()
        }
    })
    coordC2.sendResponse(RequestItemsWrapper())
    sessC2.emit(PresentationSessionStatus.responseSent)
    sessC2.fireOnSent(Option<String>.None)
    t.eqInt(sentCellC2[0], 1, "proximity.sendResponse_statusThenOnSent_publishedOnce")

    // ── QR 载荷：coordinator.startQrEngagement 发布 qrReady(payload) 并返回它 ──
    let sessD = FakeProximityPresentationSession()
    sessD.engagement = Some("mdoc:owBjMS4wAYIB2BhYS6QBAiABIVggAQID")
    let coordD = ProximitySessionCoordinatorImpl(sessD)
    let payloadD = coordD.startQrEngagement()
    t.eqStr(payloadD, "mdoc:owBjMS4wAYIB2BhYS6QBAiABIVggAQID", "proximity.coordinator_startQrEngagement_returnsPayload")
    t.eqStr(proximityStateName(coordD.getState()), "qrReady:mdoc:owBjMS4wAYIB2BhYS6QBAiABIVggAQID",
        "proximity.coordinator_startQrEngagement_publishesQrReady")
    // 无 deviceEngagement → unableToPresentAndShare（iOS guard let deviceEngagement）。
    let sessD2 = FakeProximityPresentationSession()
    let coordD2 = ProximitySessionCoordinatorImpl(sessD2)
    var threwD2 = false
    try {
        coordD2.startQrEngagement()
    } catch (_: WalletCoreError) {
        threwD2 = true
    }
    t.check(threwD2, "proximity.coordinator_startQrEngagement_noEngagement_throws")

    // ── QR 载荷经 coordinator → interactor → ProximityConnectionViewModel ──
    // initialize()：订阅流 + coordinator.initialize（session.startQrEngagement/receiveRequest）；
    // 引擎 qrEngagementReady → prepareQr → VM 生成 QR → 状态 hasQr + qrPayload。
    let sessE = FakeProximityPresentationSession()
    sessE.engagement = Some("mdoc:abc")
    let coordE = ProximitySessionCoordinatorImpl(sessE)
    let interE = ProximityInteractorImpl(coordinator: coordE, walletController: FakeWalletKitController())
    let vmE = ProximityConnectionViewModel(router: InMemoryRouterHost(), interactor: interE)
    vmE.initialize()
    t.eqInt(sessE.startQrEngagementCalls, 1, "proximity.connectionVm_initialize_startsQrEngagement")
    t.eqInt(sessE.receiveRequestCalls, 1, "proximity.connectionVm_initialize_receivesRequest")
    t.check(!vmE.viewState.hasQr, "proximity.connectionVm_noQrBeforeEngagementReady")
    sessE.emit(PresentationSessionStatus.qrEngagementReady)
    t.check(vmE.viewState.hasQr, "proximity.connectionVm_qrEngagementReady_hasQr")
    t.eqStr(vmE.viewState.qrPayload, "mdoc:abc", "proximity.connectionVm_qrPayloadCarriedToView")
    t.check(!vmE.viewState.hasError, "proximity.connectionVm_qrEngagementReady_noError")
    // 引擎就绪但无 engagement 载荷 → QrFailure → 错误态（不伪造 QR）。
    let sessE2 = FakeProximityPresentationSession()
    let coordE2 = ProximitySessionCoordinatorImpl(sessE2)
    let interE2 = ProximityInteractorImpl(coordinator: coordE2, walletController: FakeWalletKitController())
    let vmE2 = ProximityConnectionViewModel(router: InMemoryRouterHost(), interactor: interE2)
    vmE2.initialize()
    sessE2.emit(PresentationSessionStatus.qrEngagementReady)
    t.check(vmE2.viewState.hasError, "proximity.connectionVm_missingEngagement_error")
    t.check(!vmE2.viewState.hasQr, "proximity.connectionVm_missingEngagement_noQr")
    // 传输层：无线电关 → didFinishedWithError(BleNotSupported, "Bluetooth is off")，
    // 不产生 qrEngagementReady；引擎会话 sessionError → 连接 VM 进错误态（非卡转圈）。
    let sessE3 = FakeProximityPresentationSession()
    let coordE3 = ProximitySessionCoordinatorImpl(sessE3)
    let interE3 = ProximityInteractorImpl(coordinator: coordE3, walletController: FakeWalletKitController())
    let vmE3 = ProximityConnectionViewModel(router: InMemoryRouterHost(), interactor: interE3)
    vmE3.initialize()
    sessE3.errorDescription = Some("Bluetooth is off (BleNotSupported)")
    sessE3.emit(PresentationSessionStatus.sessionError)
    t.check(vmE3.viewState.hasError, "proximity.connectionVm_radioOff_errorState")
    t.check(!vmE3.viewState.hasQr, "proximity.connectionVm_radioOff_noQr")
    t.eqStr(vmE3.viewState.errorMessage, "Bluetooth is off (BleNotSupported)", "proximity.connectionVm_radioOff_errorText")
    // fake coordinator 路径：qrReady(payload) 直接落到 VM 状态。
    let coordF = FakeProximityCoordinator()
    let interF = ProximityInteractorImpl(coordinator: coordF, walletController: FakeWalletKitController())
    let vmF = ProximityConnectionViewModel(router: InMemoryRouterHost(), interactor: interF)
    vmF.initialize()
    coordF.getStream().setValue(PresentationState.qrReady("mdoc:direct"))
    t.check(vmF.viewState.hasQr, "proximity.connectionVm_qrReadyState_hasQr")
    t.eqStr(vmF.viewState.qrPayload, "mdoc:direct", "proximity.connectionVm_qrReadyState_payload")

    // ═══ WP7：交易日志 —— 发送成功后记录验证方名 + 文档标题 ═══════════════════
    // iOS 在 PresentationSession.sendResponse 内经 TransactionLogger 落盘；
    // CJ 在 interactor.onSendResponse 成功返回后调 walletController.logPresentation
    // （controller 再用读卡器链 CN 覆盖出示方名）。
    let coordG = FakeProximityCoordinator()
    coordG.request = makeProximityRequest(docId: "iso-mdl-id", relyingParty: "ACME Verifier", isTrusted: true)
    let walletG = FakeProximityWalletController()
    walletG.documentById = Some(makeProximityDoc(docId: "iso-mdl-id"))
    let interG = ProximityInteractorImpl(coordinator: coordG, walletController: walletG)
    let modelG = interG.onRequestReceived()
    coordG.state = PresentationState.responseToSend(RequestItemsWrapper())
    let rG = interG.onSendResponse()
    let okG = match (rG) { case ProximitySent => true; case _ => false }
    t.check(okG, "proximity.txLog_sent")
    t.eqInt(walletG.logPresentationCalls, 1, "proximity.txLog_loggedOnce")
    t.eqStr(walletG.lastLoggedRelyingParty, "ACME Verifier", "proximity.txLog_relyingPartyName")
    t.eqInt(walletG.lastLoggedDocLabels.size, modelG.sections.size, "proximity.txLog_docLabelsFromSections")
    // 未经请求屏（无缓存名）→ 回退 coordinator.currentRelyingParty()（读卡器证书名）。
    let coordH = FakeProximityCoordinator()
    coordH.relyingPartyName = "Reader CN"
    coordH.state = PresentationState.responseToSend(RequestItemsWrapper())
    let walletH = FakeWalletKitController()
    let interH = ProximityInteractorImpl(coordinator: coordH, walletController: walletH)
    interH.onSendResponse()
    t.eqInt(walletH.logPresentationCalls, 1, "proximity.txLog_fallbackLogged")
    t.eqStr(walletH.lastLoggedRelyingParty, "Reader CN", "proximity.txLog_fallbackCurrentRelyingParty")
    // 发送失败 → 不落日志。
    let coordI = FakeProximityCoordinator()
    coordI.state = PresentationState.responseToSend(RequestItemsWrapper())
    coordI.shouldThrowSendResponse = true
    let walletI = FakeWalletKitController()
    let interI = ProximityInteractorImpl(coordinator: coordI, walletController: walletI)
    interI.onSendResponse()
    t.eqInt(walletI.logPresentationCalls, 0, "proximity.txLog_notLoggedOnSendFailure")

    // ═══ WP0：BLE 可用性映射（iOS ReachabilityControllerImpl.mapAvailability）═══
    // iOS: available→.available；poweredOff→.disabled；unauthorized→.noPermission；
    //      resetting/unsupported/any→.unavailable。
    t.check(mapBleAvailability(BleRadioState.poweredOn) == BleAvailibity.available, "reachability.map_poweredOn_available")
    t.check(mapBleAvailability(BleRadioState.poweredOff) == BleAvailibity.disabled, "reachability.map_poweredOff_disabled")
    t.check(mapBleAvailability(BleRadioState.unauthorized) == BleAvailibity.noPermission, "reachability.map_unauthorized_noPermission")
    t.check(mapBleAvailability(BleRadioState.resetting) == BleAvailibity.unavailable, "reachability.map_resetting_unavailable")
    t.check(mapBleAvailability(BleRadioState.unsupported) == BleAvailibity.unavailable, "reachability.map_unsupported_unavailable")
    t.check(mapBleAvailability(BleRadioState.unknown) == BleAvailibity.unavailable, "reachability.map_unknown_unavailable")
    // 无线电探针（ConnectivityKit createGattServer + close）的 BusinessException 码 → 无线电状态。
    t.check(bleRadioStateFromErrorCode(2900003) == BleRadioState.poweredOff, "reachability.errorCode_2900003_poweredOff")
    t.check(bleRadioStateFromErrorCode(201) == BleRadioState.unauthorized, "reachability.errorCode_201_unauthorized")
    t.check(bleRadioStateFromErrorCode(801) == BleRadioState.unsupported, "reachability.errorCode_801_unsupported")
    t.check(bleRadioStateFromErrorCode(2900001) == BleRadioState.unknown, "reachability.errorCode_serviceStopped_unknown")
    t.check(bleRadioStateFromErrorCode(2900099) == BleRadioState.unknown, "reachability.errorCode_operationFailed_unknown")
    // 端到端（探针码 → iOS 可用性）：无线电关 → disabled；权限拒绝 → noPermission；
    // 无 BLE 能力 → unavailable；探针成功（poweredOn）→ available。
    t.check(mapBleAvailability(bleRadioStateFromErrorCode(2900003)) == BleAvailibity.disabled, "reachability.e2e_radioOff_disabled")
    t.check(mapBleAvailability(bleRadioStateFromErrorCode(201)) == BleAvailibity.noPermission, "reachability.e2e_permissionDenied_noPermission")
    t.check(mapBleAvailability(bleRadioStateFromErrorCode(801)) == BleAvailibity.unavailable, "reachability.e2e_unsupported_unavailable")
    t.check(mapBleAvailability(BleRadioState.poweredOn) == BleAvailibity.available, "reachability.e2e_probeOk_available")
    // requestPermissionsFromUser 结果：authResults 全 0 才算授予。
    t.check(allPermissionsGranted([0i32]), "reachability.permissionResult_granted")
    t.check(!allPermissionsGranted([-1i32]), "reachability.permissionResult_denied")
    t.check(!allPermissionsGranted([0i32, -1i32]), "reachability.permissionResult_partialDenied")
    t.check(!allPermissionsGranted(Array<Int32>()), "reachability.permissionResult_empty_denied")
}
