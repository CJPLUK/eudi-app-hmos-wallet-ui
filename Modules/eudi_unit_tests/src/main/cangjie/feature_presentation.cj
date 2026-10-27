// 设备单测：feature-presentation，按行为迁移自：
//   iOS TestPresentationInteractor.swift  （19 个用例）
//
// 通过设备桥执行（dev_unit_driver.cj 里的 DeviceTestRun）。仅手写 fake，
// 不用 Cuckoo，不接真实引擎/keychain/IO。
//
// 架构差异（关键）：
//   iOS 的 PresentationInteractorImpl 依赖一个 MockSessionCoordinatorHolder
//   间接层（getActiveRemoteCoordinator() 取/抛 coordinator），并把
//   onDeviceEngagement 与 onRequestReceived 拆成两个方法，另外还在 interactor
//   上挂了 getSessionStatePublisher / getCoordinator / updatePresentationCoordinator
//   / storeDynamicIssuancePendingUrl。
//
//   仓颉的 PresentationInteractorImpl 是“精简移植”（直注 coordinator、无 holder）：
//     · 直接注入 RemoteSessionCoordinator（无 holder 间接层，刻意保留此更简洁设计）。
//     · onDeviceEngagement() 一步到位（initialize + requestReceived + 构建模型），
//       吸收了 iOS 的 onRequestReceived。
//   为让 iOS 测试的决策点可断言，本轮给 interactor 补了**薄的、测试友好的公开访问器**
//   （不加回 holder 间接层）：
//     · getSessionStatePublisher(): PublisherResult   —— 镜像 iOS RemotePublisherPartialState
//     · getCoordinator(): CoordinatorResult           —— 镜像 iOS PresentationCoordinatorPartialState
//     · storeDynamicIssuancePendingUrl(url)           —— 转发到 walletController（同 iOS）
//   iOS 里“holder 取 coordinator 抛错→failure”的路径在仓颉不存在，等价触发方式=
//   **注入一个在 getStream()（liveness 探针）上抛错的 fake coordinator**，走 catch → failure。
//   updatePresentationCoordinator 的“运行期替换/setActive 计次”语义无法 1:1 复现（直注为
//   一次性 `let` 注入），映射为“注入后 coordinator 即可用”的可达等价断言（见对应用例注释）。
//
//   仓颉 PresentationInteractor 方法（补齐后）：
//     getStream() / getSessionStatePublisher() / getCoordinator() /
//     onDeviceEngagement() / onResponsePrepare(selected) / onSendResponse() /
//     storeDynamicIssuancePendingUrl(url) / stopPresentation()
//
// 真实业务逻辑落点：
//   onDeviceEngagement -> coordinator.initialize() -> coordinator.requestReceived()
//     -> buildRequestReceivedModel(request, walletController, claimIndex)
//        （feature-common request_bridge）：对 request.items 里每个 docId，
//         过滤 walletController.fetchRevokedDocuments()，再 fetchDocument(docId)
//         取 docClaims 摊平成 RequestDataCell；空 sections 仍成功（iOS 95b71766：
//         不可满足的请求也要显示是谁在要）。
package eudi_unit_tests

import std.collection.{ArrayList, HashMap}
import eudi_feature_presentation.{
    PresentationInteractorImpl, NoopPresentationInteractor,
    SentResponseResult, PublisherResult, CoordinatorResult,
    PresentationRequestViewModel, PresentationLoaderViewModel
}
import eudi_feature_common.{
    RequestDataCell
}
import eudi_logic_ui.{InMemoryRouterHost, AppRoutes}
import eudi_logic_business.{ParsedUrl}
import eudi_logic_core.{
    WalletCoreError,
    RemoteSessionCoordinator, PresentationState, PresentationRequest, DocElements, RequestedClaim,
    SendableCurrentValueSubject,
    RequestItemConvertible, RequestItemsWrapper, RequestItem, RequestConvertibleItems,
    DocClaimsDecodable, DocClaim, DocDataValue, DocDataFormat, CredentialPolicy,
    StatusIdentifier, DisplayMetadata, CredentialsUsageCounts, ParsedUrlRef
}
import std.time.DateTime
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WrpRegistrationPolicy as PresWrpRegistrationPolicy

// ─────────────────────────────────────────────────────────────────────────────
// 局部 fake（仓颉禁止局部类定义，全部顶层）
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 可配置的 RemoteSessionCoordinator fake。
 * 镜像 iOS MockRemoteSessionCoordinator 的可桩点：
 *   · requestReceived()  -> 返回 requestToReturn，或当 requestReceivedThrows 时抛错
 *   · initialize()       -> 计数；当 initializeThrows 时抛错
 *   · getState()         -> 返回内部 subject 当前值
 *   · setState()         -> 写 subject + 计数（onResponsePrepare 用）
 *   · sendResponse()     -> 计数 + 记录最后一次入参（onSendResponse 用）
 *   · getStream()        -> 返回内部 subject（当 getStreamThrows 时抛错）
 *   · stopPresentation() -> 计数
 */
open class FakePresentationCoordinator <: RemoteSessionCoordinator {
    private let subject: SendableCurrentValueSubject<PresentationState>

    public var requestToReturn: PresentationRequest
    public var requestReceivedThrows: Bool = false
    public var requestReceivedError: String = "conversionToRequestItemModel"
    /** When true, requestReceived() throws a trust failure instead of a plain
     *  exception — iOS stubs WalletError(code: .trustError) here. */
    public var requestReceivedTrustError: Bool = false
    public var initializeThrows: Bool = false
    public var getStreamThrows: Bool = false

    public var initializeCalls: Int64 = 0
    public var setStateCalls: Int64 = 0
    public var sendResponseCalls: Int64 = 0
    public var stopPresentationCalls: Int64 = 0
    public var lastSentResponse: ?RequestItemConvertible = Option<RequestItemConvertible>.None

    public init(initialState: PresentationState, request: PresentationRequest) {
        this.subject = SendableCurrentValueSubject<PresentationState>(initialState)
        this.requestToReturn = request
    }

    public prop sendableCurrentValueSubject: SendableCurrentValueSubject<PresentationState> {
        get() { this.subject }
    }

    // ── Registration-certificate layer (wallet-kit 0.40.x seam) ──────────────
    /** Verifier WRPRC policy fed to getVerifierRegistration (default None). */
    public var relyingPartyRegistrationValue: ?PresWrpRegistrationPolicy = Option<PresWrpRegistrationPolicy>.None
    /** ""-keyed (request-level) WRPRC violation messages (default none). */
    public var relyingPartyWarningViolationsValue: Array<String> = Array<String>()
    /** docId → over-asked leaf paths handed to the request bridge (default empty). */
    public var overaskedLeafPaths: HashMap<String, Array<Array<String>>> = HashMap<String, Array<Array<String>>>()

    public prop relyingPartyRegistration: ?PresWrpRegistrationPolicy {
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

    public func initialize(): Unit {
        this.initializeCalls += 1
        if (this.initializeThrows) {
            throw Exception("initialize failed")
        }
    }

    public func requestReceived(): PresentationRequest {
        if (this.requestReceivedTrustError) {
            throw WalletCoreError.issuerNotTrusted()
        }
        if (this.requestReceivedThrows) {
            throw Exception(this.requestReceivedError)
        }
        return this.requestToReturn
    }

    public open func sendResponse(response: RequestItemConvertible): Unit {
        this.sendResponseCalls += 1
        this.lastSentResponse = Some(response)
        // 模拟引擎回吐：设为 responseSent（loader 订阅会观察到）
        this.subject.setValue(PresentationState.responseSent(Option<String>.None))
    }

    public open func getState(): PresentationState { this.subject.getValue() }

    public open func setState(presentationState: PresentationState): Unit {
        this.setStateCalls += 1
        this.subject.setValue(presentationState)
    }

    public func getStream(): SendableCurrentValueSubject<PresentationState> {
        if (this.getStreamThrows) {
            throw Exception("getStream failed")
        }
        return this.subject
    }

    public func stopPresentation(): Unit {
        this.stopPresentationCalls += 1
    }

    public open func currentRelyingParty(): String { "Verifier" }
}

/** getStream 直接抛错的 coordinator（覆盖 getStream() 失败路径）。 */
class FakeCoordinatorStreamThrows <: FakePresentationCoordinator {
    public init(request: PresentationRequest) {
        super(PresentationState.loading, request)
        this.getStreamThrows = true
    }
}

/**
 * 一个 docClaims 非空的 DocClaimsDecodable —— 共享 fake 里的 FakeDocClaims
 * 的 docClaims 恒为空数组（buildRequestReceivedModel 会因无 cell 跳过该 doc），
 * 故这里单独造一个带真实 claims 的最小实现，让 onDeviceEngagement 能产出 section。
 */
class FakePresDoc <: DocClaimsDecodable {
    let id_: String
    let claims_: Array<DocClaim>
    init(id_: String, claims_: Array<DocClaim>) {
        this.id_ = id_
        this.claims_ = claims_
    }
    public prop id: String { get() { this.id_ } }
    public prop statusIdentifier: ?StatusIdentifier { get() { Option<StatusIdentifier>.None } }
    public prop createdAt: DateTime { get() { DateTime.now() } }
    public prop modifiedAt: ?DateTime { get() { Option<DateTime>.None } }
    public prop displayName: ?String { get() { Some("ISO mDL") } }
    public prop docType: String { get() { "org.iso.18013.5.1.mDL" } }
    public prop docClaims: Array<DocClaim> { get() { this.claims_ } }
    public prop docDataFormat: DocDataFormat { get() { DocDataFormat.cbor } }
    public prop ageOverXX: HashMap<Int64, Bool> { get() { HashMap<Int64, Bool>() } }
    public prop display: ?Array<DisplayMetadata> { get() { Option<Array<DisplayMetadata>>.None } }
    public prop issuerDisplay: ?Array<DisplayMetadata> { get() { Option<Array<DisplayMetadata>>.None } }
    public prop credentialIssuerIdentifier: ?String { get() { Option<String>.None } }
    public prop configurationIdentifier: ?String { get() { Option<String>.None } }
    public prop validFrom: ?DateTime { get() { Option<DateTime>.None } }
    public prop validUntil: ?DateTime { get() { Option<DateTime>.None } }
    public prop secureAreaName: ?String { get() { Option<String>.None } }
    public prop credentialsUsageCounts: ?CredentialsUsageCounts { get() { Option<CredentialsUsageCounts>.None } }
    public prop credentialPolicy: CredentialPolicy { get() { CredentialPolicy.rotateUse } }
}

/**
 * 按 id 返回文档的 wallet fake（基类 FakeWalletKitController.fetchDocument 只能
 * 返回单一 documentById，无法按 docId 区分），并可配置 revoked 列表。
 * buildRequestReceivedModel 依赖 fetchDocument(docId).docClaims 与
 * fetchRevokedDocuments() 这两条。
 */
class FakePresWallet <: FakeWalletKitController {
    public var docsById: HashMap<String, DocClaimsDecodable> = HashMap<String, DocClaimsDecodable>()
    public var fetchRevokedThrows: Bool = false

    public override func fetchDocument(id: String): ?DocClaimsDecodable {
        if (this.docsById.contains(id)) {
            return Some(this.docsById[id])
        }
        return Option<DocClaimsDecodable>.None
    }

    public override func fetchRevokedDocuments(): Array<String> {
        if (this.fetchRevokedThrows) {
            throw Exception("fetchRevokedDocuments failed")
        }
        return this.revokedDocumentIds
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/** 造一个最小 mdoc claim（name=elementIdentifier，文本值）。 */
func makePresClaim(
    name!: String = "elementIdentifier",
    namespace!: String = "nameSpace",
    value!: String = "value"
): DocClaim {
    DocClaim(
        name: name,
        dataValue: DocDataValue.text(value),
        stringValue: value,
        namespace: Some(namespace)
    )
}

/** 造一个 request，items 为给定 docId 列表（DocElements 仅有 id 字段）。 */
func makePresRequest(
    docIds!: Array<String> = ["isoMdlModelId"],
    relyingParty!: String = "Relying Party",
    isTrusted!: Bool = true
): PresentationRequest {
    let elements = ArrayList<DocElements>()
    for (d in docIds) {
        elements.add(DocElements(d))
    }
    return PresentationRequest(
        items: elements.toArray(),
        relyingParty: relyingParty,
        dataRequestInfo: "dataRequestInfo",
        isTrusted: isTrusted
    )
}

/** 造一个挂好 1 个文档（含 1 claim）的 wallet，文档 id 与 request docId 一致。 */
func makeWalletWithDoc(docId!: String = "isoMdlModelId"): FakePresWallet {
    let w = FakePresWallet()
    w.docsById[docId] = FakePresDoc(docId, [makePresClaim()])
    return w
}

/** 造一个非空的 RequestItemConvertible（responseToSend 状态用）。 */
func makeConvertible(
    docId!: String = "isoMdlModelId",
    namespace!: String = "nameSpace",
    element!: String = "elementIdentifier"
): RequestItemConvertible {
    let dict: RequestConvertibleItems = HashMap<String, HashMap<String, Array<RequestItem>>>()
    let ns = HashMap<String, Array<RequestItem>>()
    ns[namespace] = [RequestItem(elementIdentifier: element, intentToRetain: Some(false))]
    dict[docId] = ns
    return RequestItemsWrapper(dict)
}

func makeInteractor(coordinator: FakePresentationCoordinator, wallet: FakeWalletKitController): PresentationInteractorImpl {
    PresentationInteractorImpl(coordinator: coordinator, walletController: wallet)
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactor 用例（映射自 iOS TestPresentationInteractor.swift）
// ─────────────────────────────────────────────────────────────────────────────

func runPresentationInteractorTests(t: DeviceTestRun): Unit {

    // ── testGetSessionStatePublisher_WhenActiveCoordinatorReturnsStream_ThenResultIsSuccessWithThatStream ──
    // iOS：getSessionStatePublisher() -> .success(stream)。
    // ✅ 补齐架构 seam：仓颉现暴露 getSessionStatePublisher(): PublisherResult（Result 式，
    //   镜像 iOS RemotePublisherPartialState）。coordinator 有效 -> PublisherSuccess(stream)。
    //   （同时保留旧 getStream() 断言作为薄封装的下层校验。）
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.getSessionStatePublisher()
        let ok = match (res) { case PublisherSuccess(_) => true; case _ => false }
        t.check(ok, "pres.getSessionStatePublisher_active_success ✅")
        // 下层 getStream() 也应返回 Some（薄封装一致性）。
        let stream = intr.getStream()
        let someOk = match (stream) { case Some(_) => true; case None => false }
        t.check(someOk, "pres.getStream_active_returnsSome ✅")
    }()

    // ── testGetSessionStatePublisher_WhenActiveCoordinatorThrowsError_ThenReturnsFailureWithThatError ──
    // iOS：holder.getActiveRemoteCoordinator() 抛错 -> getSessionStatePublisher 返回 .failure。
    // ✅ 仓颉无 holder；等价触发方式=注入一个 getStream() 抛错的 fake coordinator
    //   （FakeCoordinatorStreamThrows），使 getSessionStatePublisher 走 catch ->
    //   PublisherFailure，且错误文本透传（iOS 校验 error 相等）。
    { =>
        let coord = FakeCoordinatorStreamThrows(makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.getSessionStatePublisher()
        var failed = false
        var msg = ""
        match (res) { case PublisherFailure(m) => failed = true; msg = m; case _ => () }
        t.check(failed, "pres.getSessionStatePublisher_throws_failure ✅ (erroring fake coordinator)")
        t.eqStr(msg, "getStream failed", "pres.getSessionStatePublisher_throws_errorText ✅")
        // 下层 getStream() 也回退 None。
        let isNone = match (intr.getStream()) { case Some(_) => false; case None => true }
        t.check(isNone, "pres.getStream_throws_returnsNone ✅")
    }()

    // ── testGetCoordinator_WhenActiveCoordinatorExists_ThenReturnsSuccessWithCoordinator ──
    // iOS：getCoordinator() 取到活动 coordinator -> .success(coordinator)。
    // ✅ 补齐架构 seam：仓颉现暴露 getCoordinator(): CoordinatorResult（镜像 iOS
    //   PresentationCoordinatorPartialState）。直注设计里 coordinator 恒在，liveness 探针
    //   （getStream）不抛 -> CoordinatorSuccess(coordinator)。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.getCoordinator()
        let ok = match (res) { case CoordinatorSuccess(_) => true; case _ => false }
        t.check(ok, "pres.getCoordinator_exists_success ✅")
    }()

    // ── testGetCoordinator_WhenActiveCoordinatorThrowsError_ThenReturnsFailureWithThatError ──
    // iOS：holder.getActiveRemoteCoordinator() 抛错 -> getCoordinator() 返回 .failure。
    // ✅ 等价触发：注入 getStream() 抛错的 fake coordinator（liveness 探针失败）->
    //   CoordinatorFailure，错误文本透传。这是直注设计里“coordinator 不可用”的等价失败路径。
    { =>
        let coord = FakeCoordinatorStreamThrows(makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.getCoordinator()
        var failed = false
        var msg = ""
        match (res) { case CoordinatorFailure(m) => failed = true; msg = m; case _ => () }
        t.check(failed, "pres.getCoordinator_throws_failure ✅ (erroring fake coordinator)")
        t.eqStr(msg, "getStream failed", "pres.getCoordinator_throws_errorText ✅")
    }()

    // ── testUpdatePresentationCoordinator_WhenUpdatingWithCoordinator_ThenCallsSetActiveRemoteCoordinatorTwice ──
    // iOS：updatePresentationCoordinator(with:) -> holder.setActiveRemoteCoordinator 被调（累计 2 次，
    //   含 init 里那次）。
    // ⚠️ 等价映射（无法 1:1 复现）：仓颉是直注设计，coordinator 为 init 时一次性注入的 `let` 字段，
    //   刻意不提供运行期替换/holder 层（这是比 iOS 更简洁的取舍，不加回间接层）。因此“调用
    //   setActiveRemoteCoordinator 两次”的计数语义在仓颉不存在。可达等价断言：init 注入的
    //   coordinator 即为 getCoordinator() 取到的那一个（注入后立即可用、无需二次 set）。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.getCoordinator()
        let ok = match (res) { case CoordinatorSuccess(_) => true; case _ => false }
        t.check(ok, "pres.updateCoordinator_injectedCoordinatorLive ⚠️iOS=setActiveTwice(直注无holder,映射为注入后即可用)")
    }()

    // ── testStoreDynamicIssuancePendingUrl_WhenCalledWithUrl_ThenCallsWalletKitControllerStoreDynamicIssuancePendingUrl ──
    // iOS：interactor.storeDynamicIssuancePendingUrl(with:) -> walletKitController.storeDynamicIssuancePendingUrl 被调。
    // ✅ 补齐架构 seam：仓颉 interactor 现转发 storeDynamicIssuancePendingUrl(url) 到
    //   walletController（与 iOS 一致——interactor 层转发）。断言 wallet 侧计数 +1。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let wallet = FakePresWallet()
        let intr = makeInteractor(coord, wallet)
        let url: ParsedUrlRef = ParsedUrl(
            Option<String>.None, Option<String>.None, "https://example.com/pending",
            Option<String>.None, Option<String>.None)
        intr.storeDynamicIssuancePendingUrl(url)
        t.eqInt(wallet.storeDynamicIssuancePendingUrlCalls, 1,
            "pres.storeDynamicIssuancePendingUrl_forwardsToWallet ✅")
    }()

    // ── testStopPresentation_WhenInteractorMethodCalled_ThenCallsWalletKitControllerStopPresentation ──
    // iOS：interactor.stopPresentation() -> walletController.stopPresentation() 被调用。
    // ✅ 仓颉 stopPresentation() 先调 walletController.stopPresentation()（计数 +1），
    //   再尝试 coordinator.stopPresentation()。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let wallet = FakePresWallet()
        let intr = makeInteractor(coord, wallet)
        intr.stopPresentation()
        t.eqInt(wallet.stopPresentationCalls, 1, "pres.stop_callsWalletStop ✅")
    }()

    // ── testStopPresentation_WhenInteractorCalled_ThenCallsWalletKitControllerStopPresentation ──
    // iOS：与上一个用例语义完全相同（重复用例）。
    // ✅ 这里额外断言 coordinator.stopPresentation() 也被调用一次（仓颉在 wallet 之后还停 coordinator）。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let wallet = FakePresWallet()
        let intr = makeInteractor(coord, wallet)
        intr.stopPresentation()
        t.eqInt(wallet.stopPresentationCalls, 1, "pres.stop_dup_callsWalletStop ✅")
        t.eqInt(coord.stopPresentationCalls, 1, "pres.stop_alsoStopsCoordinator ✅")
    }()

    // ── testOnDeviceEngagement_WhenRequestReceivedAndClaimsParsed_ThenReturnsSuccessWithModel ──
    // iOS：initialize + requestReceived 成功，claim 解析 -> .success(model)。
    // ✅ 仓颉 onDeviceEngagement()：coordinator.initialize() -> requestReceived() ->
    //   buildRequestReceivedModel 产出 section -> RequestReceivedModel.isSuccess==true。
    //   （iOS 用 parseDocClaim mock；仓颉从 fetchDocument(docId).docClaims 取真实 claim。）
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let wallet = makeWalletWithDoc()
        let intr = makeInteractor(coord, wallet)
        let model = intr.onDeviceEngagement()
        t.check(model.isSuccess, "pres.onDeviceEngagement_claimsParsed_success ✅")
        t.eqInt(coord.initializeCalls, 1, "pres.onDeviceEngagement_initializeCalled ✅")
        t.check(model.sections.size >= 1, "pres.onDeviceEngagement_hasSections ✅")
    }()

    // The UI must render only verifier-requested claims and honour explicit
    // optionality even when a schema normally marks that field mandatory.
    { =>
        let docId = "selectable-mdl"
        let requested = RequestedClaim(
            namespace: "org.iso.18013.5.1",
            elementPath: ["family_name"],
            isOptional: true
        )
        let req = PresentationRequest(
            items: [DocElements(
                docId,
                docType: "org.iso.18013.5.1.mDL",
                requestedClaims: [requested]
            )],
            relyingParty: "Verifier",
            dataRequestInfo: "requests the following",
            isTrusted: true
        )
        let wallet = FakePresWallet()
        wallet.docsById[docId] = FakePresDoc(docId, [
            makePresClaim(name: "family_name", namespace: "org.iso.18013.5.1", value: "Doe"),
            makePresClaim(name: "resident_city", namespace: "org.iso.18013.5.1", value: "Brussels")
        ])
        let intr = makeInteractor(FakePresentationCoordinator(PresentationState.loading, req), wallet)
        let model = intr.onDeviceEngagement()
        t.eqInt(model.sections.size, 1, "pres.requestedClaims_oneDocument")
        t.eqInt(model.sections[0].cells.size, 1, "pres.requestedClaims_filtersUnrequested")
        t.eqStr(model.sections[0].cells[0].title, "family_name", "pres.requestedClaims_keepsRequested")
        t.check(model.sections[0].cells[0].selectable,
            "pres.requestedClaims_explicitOptionalIsSelectable")
    }()

    // ── testOnRequestReceived_WhenCoordinatorReturnsRequest_ThenEmitsSuccessStateWithParsedUiModels ──
    // iOS：onRequestReceived() -> .success，并校验 requestDataCells / relyingParty /
    //   dataRequestInfo / isTrusted 与 request 一致。
    // ⚠️ 仓颉无独立 onRequestReceived()（已并入 onDeviceEngagement）。在 onDeviceEngagement
    //   返回的 RequestReceivedModel 上断言对应字段：relyingParty / isTrusted 透传，
    //   且生成了 cell（section 非空）。iOS 的 requestDataCells 逐项相等无法 1:1
    //   （cell 由真实 claims 派生，结构不同）→ 退化为“section 内有 cell”。
    { =>
        let req = makePresRequest(docIds: ["isoMdlModelId"], relyingParty: "ACME RP", isTrusted: true)
        let coord = FakePresentationCoordinator(PresentationState.loading, req)
        let wallet = makeWalletWithDoc()
        let intr = makeInteractor(coord, wallet)
        let model = intr.onDeviceEngagement()
        t.check(model.isSuccess, "pres.onRequestReceived_success ⚠️mergedIntoOnDeviceEngagement")
        t.eqStr(model.relyingParty, "ACME RP", "pres.onRequestReceived_relyingPartyMatches ✅")
        t.check(model.isTrusted, "pres.onRequestReceived_isTrustedMatches ✅")
        // iOS 95b71766: 成功负载携带 RelyingPartyRegistration（fake wallet 的
        // getVerifierRegistration 基线：notSupported + access-cert 名字/徽章）。
        match (model.relyingPartyRegistration) {
            case Some(reg) =>
                t.check(true, "pres.onRequestReceived_carriesRegistration ✅")
                t.eqStr(reg.name ?? "", "ACME RP", "pres.onRequestReceived_registrationName ✅")
                t.check(reg.isFullyVerified, "pres.onRequestReceived_registrationFullyVerified ✅")
            case None => t.check(false, "pres.onRequestReceived_carriesRegistration ✅")
        }
        t.eqStr(model.dataRequestInfo, "dataRequestInfo", "pres.onRequestReceived_dataRequestInfoMatches ✅")
        var hasCell = false
        for (s in model.sections) {
            if (s.cells.size > 0) { hasCell = true }
        }
        t.check(hasCell, "pres.onRequestReceived_hasParsedCells ⚠️notCellEquality")
    }()

    // ── testOnRequestReceived_WhenCoordinatorRequestReceivedThrowsError_ThenReturnsFailureWithThatError ──
    // iOS：coordinator.requestReceived() 抛 conversionToRequestItemModel -> .failure(该错误)。
    // ✅ 仓颉 onDeviceEngagement 捕获异常 -> RequestReceivedModel.failure(错误信息)，isSuccess==false，
    //   errorMessage 透传异常 message。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        coord.requestReceivedThrows = true
        coord.requestReceivedError = "conversionToRequestItemModel"
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let model = intr.onDeviceEngagement()
        t.check(!model.isSuccess, "pres.onRequestReceived_throws_failure ✅")
        t.eqStr(model.errorMessage, "conversionToRequestItemModel", "pres.onRequestReceived_throws_errorMessage ✅")
    }()

    // ── testOnRequestReceived_WhenCoordinatorRequestReceivedThrowsTrustError_ThenReturnsNotSecuredRequest ──
    // iOS：requestReceived 抛 WalletError(.trustError) -> .notSecuredRequest（而非
    // .failure）。✅ 仓颉 onDeviceEngagement() 用 isTrustBlocked 分流到
    // RequestReceivedModel.notSecuredRequest()：非成功、非普通失败、无报错文案。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        coord.requestReceivedTrustError = true
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let model = intr.onDeviceEngagement()
        t.check(model.isNotSecuredRequest, "pres.onRequestReceived_trustError_notSecuredRequest ✅")
        t.check(!model.isSuccess, "pres.onRequestReceived_trustError_notSuccess ✅")
        t.eqStr(model.errorMessage, "", "pres.onRequestReceived_trustError_noGenericErrorMessage ✅")
    }()

    // PresentationRequestViewModel：notSecuredRequest 不得渲染成可重试的错误页
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        coord.requestReceivedTrustError = true
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let vm = PresentationRequestViewModel(router: InMemoryRouterHost(), interactor: intr)
        vm.doWork()
        t.check(vm.viewState.isNotSecuredRequest, "presVM.request_doWork_trustError_notSecured (cangjie-only)")
        t.check(!vm.viewState.hasError, "presVM.request_doWork_trustError_noError (cangjie-only)")
    }()

    // ── testOnResponsePrepare_WhenCoordinatorSetState_ThenReturnsSuccessWithMappedRequestItemsAndCallsSetState ──
    // iOS：onResponsePrepare(requestItems) -> .success(mappedRequestItems)，且 coordinator.setState 被调用。
    // ⚠️ 仓颉 onResponsePrepare(selected: ArrayList<RequestDataCell>): Bool（返回 Bool 而非
    //   Result<convertible>）。需先 onDeviceEngagement 填充 claimIndex（reverse-map 依赖它），
    //   再用对应 groupId 的 cell 调 onResponsePrepare；成功返回 true 且 coordinator.setState 计数 +1。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let wallet = makeWalletWithDoc()
        let intr = makeInteractor(coord, wallet)
        // 先跑 onDeviceEngagement 取出真实 cell（其 groupId 已登记进 claimIndex）
        let model = intr.onDeviceEngagement()
        let selected = ArrayList<RequestDataCell>()
        for (s in model.sections) {
            for (c in s.cells) { selected.add(c) }
        }
        let ok = intr.onResponsePrepare(selected)
        t.check(ok, "pres.onResponsePrepare_success ⚠️iosReturnsResult_cangjieBool")
        t.eqInt(coord.setStateCalls, 1, "pres.onResponsePrepare_callsSetState ✅")
        // 进一步断言：coordinator 状态已被设成 responseToSend
        let st = coord.getState()
        let isResp = match (st) { case responseToSend(_) => true; case _ => false }
        t.check(isResp, "pres.onResponsePrepare_stateIsResponseToSend ✅")
    }()

    // ── testOnResponsePrepare_WhenSessionCoordinatorThrowsInvalidStateError_ThenReturnsFailureWithThatError ──
    // iOS：holder.getActiveRemoteCoordinator() 抛 invalidState -> .failure。
    // ⚠️ 仓颉无 holder；onResponsePrepare 的失败路径是 coordinator.setState 抛错 -> 返回 false。
    //   用 setState 抛错的 coordinator 触发该路径（行为对应：失败 -> false）。
    { =>
        let coord = FakeCoordinatorSetStateThrows(makePresRequest())
        let wallet = makeWalletWithDoc()
        let intr = makeInteractor(coord, wallet)
        let model = intr.onDeviceEngagement()
        let selected = ArrayList<RequestDataCell>()
        for (s in model.sections) {
            for (c in s.cells) { selected.add(c) }
        }
        let ok = intr.onResponsePrepare(selected)
        t.check(!ok, "pres.onResponsePrepare_setStateThrows_false ⚠️iOS=holderThrows->failure")
    }()

    // ── testOnResponsePrepare_WhenRequestItemsMissingDataOrVerificationRows_ThenReturnsFailureWithConversionError ──
    // iOS：requestItems 缺数据/校验行（dropLast）-> .failure(conversionToRequestItemModel)。
    // ⚠️ 仓颉的对应失败条件不同：buildRequestConvertible 产出为空（无任何 cell 能 reverse-map）
    //   时 onResponsePrepare 返回 false。这里传空选择 -> convertible.items 为空 -> false。
    //   （iOS 的“缺行”语义≈仓颉的“无可映射项”，但触发方式不同，注差异。）
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let empty = ArrayList<RequestDataCell>()
        let ok = intr.onResponsePrepare(empty)
        t.check(!ok, "pres.onResponsePrepare_emptySelection_false ⚠️iOS=missingRows->conversionError")
        t.eqInt(coord.setStateCalls, 0, "pres.onResponsePrepare_emptySelection_noSetState ✅")
    }()

    // ── testOnSendResponse_WhenCoordinatorStateIsResponseToSend_ThenReturnsSentAndInvokesSendResponse ──
    // iOS：coordinator.getState()==responseToSend -> onSendResponse() 返回 .sent，sendResponse 被调用。
    // ✅ 仓颉 onSendResponse()：getState()==responseToSend(item) -> coordinator.sendResponse(item) ->
    //   返回 SentResponseResult.ResponseSent。
    { =>
        let coord = FakePresentationCoordinator(
            PresentationState.responseToSend(makeConvertible()), makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.onSendResponse()
        let sent = match (res) { case ResponseSent => true; case _ => false }
        t.check(sent, "pres.onSendResponse_responseToSend_sent ✅")
        t.eqInt(coord.sendResponseCalls, 1, "pres.onSendResponse_invokesSendResponse ✅")
    }()

    // ── testOnSendResponse_WhenCoordinatorStateIsNotResponseToSend_ThenReturnsFailureWithInvalidStateError ──
    // iOS：state==.prepareQr（非 responseToSend）-> .failure(invalidState)。
    // ✅ 仓颉 onSendResponse()：状态非 responseToSend -> ResponseFailure("Invalid presentation state")。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.prepareQr, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.onSendResponse()
        // 单次 match 取出 failed 标志与错误信息（避免对同一 let 二次 match 的移动语义风险）
        var failed = false
        var msg = ""
        match (res) {
            case ResponseFailure(m) => failed = true; msg = m
            case _ => ()
        }
        t.check(failed, "pres.onSendResponse_notResponseToSend_failure ✅")
        t.eqStr(msg, "Invalid presentation state", "pres.onSendResponse_notResponseToSend_invalidStateMsg ✅")
        t.eqInt(coord.sendResponseCalls, 0, "pres.onSendResponse_notResponseToSend_noSend ✅")
    }()

    // ── testOnSendResponse_WhenCoordinatorStateIsResponseToSendAndActiveCoordinatorThrowsError_ThenReturnsFailureWithThatError ──
    // iOS：state==responseToSend，但第二次取 coordinator（holder）抛 invalidState -> .failure。
    // ⚠️ 仓颉无 holder 二次取 coordinator；对应失败路径是 coordinator.sendResponse 抛错 ->
    //   onSendResponse 捕获 -> ResponseFailure。用 sendResponse 抛错的 coordinator 触发。
    { =>
        let coord = FakeCoordinatorSendThrows(makeConvertible(), makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let res = intr.onSendResponse()
        let failed = match (res) { case ResponseFailure(_) => true; case _ => false }
        t.check(failed, "pres.onSendResponse_sendThrows_failure ⚠️iOS=secondHolderThrows")
    }()

    // ── testOnSendResponse_WhenSecondGetActiveRemoteCoordinatorThrows_ThenReturnsFailure ──
    // ❌ GAP：该用例专门验证 holder.getActiveRemoteCoordinator() 第一次返回、第二次抛错。
    //   仓颉无 SessionCoordinatorHolder，也不做“二次取 coordinator”，无此双取语义。
    //   上一个 sendThrows 用例已覆盖“发送阶段失败 -> failure”的等价行为，这里仅记 GAP。

    // ── testOnRequestReceived_WhenAllDocumentsRevoked_ThenStillSucceedsShowingRP ──
    // iOS 95b71766 移除了 `guard !combinations.isEmpty`：全部请求文档被吊销 ->
    //   sections 为空，但请求仍 .success（"不可满足的请求也要显示是谁在要"）。
    // ✅ 仓颉 buildRequestReceivedModel 同步移除空 sections 早退：成功 + 0 section +
    //   relyingParty 透传 + 成功负载携带 RelyingPartyRegistration。
    { =>
        let coord = FakePresentationCoordinator(
            PresentationState.loading, makePresRequest(docIds: ["isoMdlModelId"]))
        let wallet = makeWalletWithDoc()
        wallet.revokedDocumentIds = ["isoMdlModelId"]  // 唯一文档被吊销
        let intr = makeInteractor(coord, wallet)
        let model = intr.onDeviceEngagement()
        t.check(model.isSuccess, "pres.onRequestReceived_allRevoked_stillSuccess ✅ (iOS 95b71766)")
        t.eqInt(model.sections.size, 0, "pres.onRequestReceived_allRevoked_noSections ✅")
        t.eqStr(model.relyingParty, "Relying Party", "pres.onRequestReceived_allRevoked_showsWhoAsked ✅")
        let hasReg = match (model.relyingPartyRegistration) { case Some(_) => true; case None => false }
        t.check(hasReg, "pres.onRequestReceived_allRevoked_carriesRegistration ✅")
    }()

    // ── testOnRequestReceived_WhenFetchRevokedDocumentsThrows_ThenReturnsSuccess ──
    // iOS：fetchRevokedDocuments() 抛错，但 parse 仍产出 cell -> 整体 .success（吊销查询失败不致命）。
    // ✅ 仓颉 buildRequestReceivedModel 用 try/catch 吞掉 fetchRevokedDocuments 异常（revoked 视为空），
    //   照常 fetchDocument 产出 section -> isSuccess==true。
    { =>
        let coord = FakePresentationCoordinator(
            PresentationState.loading, makePresRequest(docIds: ["isoMdlModelId"]))
        let wallet = makeWalletWithDoc()
        wallet.fetchRevokedThrows = true  // 吊销查询抛错，应被容忍
        let intr = makeInteractor(coord, wallet)
        let model = intr.onDeviceEngagement()
        t.check(model.isSuccess, "pres.onRequestReceived_fetchRevokedThrows_stillSuccess ✅")
    }()

    // ── 额外覆盖（无直接 iOS 对应）：NoopPresentationInteractor 的降级行为 ──
    // 说明：iOS 无此类；仓颉为“无引擎预览/降级渲染”提供 Noop 实现，统一返回失败/false，
    //   保证 UI 诚实显示空/错状态。此处验证其契约（非 iOS 用例迁移，标注来源）。
    { =>
        let noop = NoopPresentationInteractor()
        let eng = noop.onDeviceEngagement()
        t.check(!eng.isSuccess, "pres.noop_onDeviceEngagement_failure (cangjie-only)")
        let prep = noop.onResponsePrepare(ArrayList<RequestDataCell>())
        t.check(!prep, "pres.noop_onResponsePrepare_false (cangjie-only)")
        let send = noop.onSendResponse()
        let f = match (send) { case ResponseFailure(_) => true; case _ => false }
        t.check(f, "pres.noop_onSendResponse_failure (cangjie-only)")
        let s = noop.getStream()
        let n = match (s) { case Some(_) => false; case None => true }
        t.check(n, "pres.noop_getStream_none (cangjie-only)")
        // 新增架构 seam 访问器在 Noop 上也应诚实失败（不伪造 coordinator/stream）。
        let pub = noop.getSessionStatePublisher()
        let pf = match (pub) { case PublisherFailure(_) => true; case _ => false }
        t.check(pf, "pres.noop_getSessionStatePublisher_failure (cangjie-only)")
        let co = noop.getCoordinator()
        let cf = match (co) { case CoordinatorFailure(_) => true; case _ => false }
        t.check(cf, "pres.noop_getCoordinator_failure (cangjie-only)")
        // storeDynamicIssuancePendingUrl 在 Noop 上为 no-op（不崩、无副作用）。
        let noopUrl: ParsedUrlRef = ParsedUrl(
            Option<String>.None, Option<String>.None, "https://example.com/noop",
            Option<String>.None, Option<String>.None)
        noop.storeDynamicIssuancePendingUrl(noopUrl)
        t.check(true, "pres.noop_storeDynamicIssuancePendingUrl_noop (cangjie-only)")
    }()
}

// ─────────────────────────────────────────────────────────────────────────────
// 触发特定失败路径的 coordinator 变体（顶层定义）
// ─────────────────────────────────────────────────────────────────────────────

/** setState 抛错的 coordinator（onResponsePrepare 失败路径）。 */
class FakeCoordinatorSetStateThrows <: FakePresentationCoordinator {
    public init(request: PresentationRequest) {
        super(PresentationState.loading, request)
    }
    public override func setState(presentationState: PresentationState): Unit {
        this.setStateCalls += 1
        throw Exception("setState failed (invalid state)")
    }
}

/** getState 返回 responseToSend，但 sendResponse 抛错的 coordinator（onSendResponse 失败路径）。 */
class FakeCoordinatorSendThrows <: FakePresentationCoordinator {
    public init(item: RequestItemConvertible, request: PresentationRequest) {
        super(PresentationState.responseToSend(item), request)
    }
    public override func sendResponse(response: RequestItemConvertible): Unit {
        this.sendResponseCalls += 1
        throw Exception("sendResponse failed (invalid state)")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ViewModel 层补充用例（iOS 无独立 ViewModel 测试，但仓颉把部分 interactor 行为
// 折进了 ViewModel.doWork/onShare/onCancel；这里用 InMemoryRouterHost 断言路由 +
// viewState，作为行为对照补充，标注为 cangjie-only / 行为对照）
// ─────────────────────────────────────────────────────────────────────────────

func runPresentationViewModelTests(t: DeviceTestRun): Unit {

    // PresentationRequestViewModel.doWork 成功 -> isLoading 落 false、无 error
    // （对应 interactor.onDeviceEngagement 成功 -> 渲染请求屏）
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let router = InMemoryRouterHost()
        let vm = PresentationRequestViewModel(router: router, interactor: intr)
        vm.doWork()
        t.check(!vm.viewState.isLoading, "presVM.request_doWork_success_notLoading (cangjie-only)")
        t.check(!vm.viewState.hasError, "presVM.request_doWork_success_noError (cangjie-only)")
    }()

    // PresentationRequestViewModel.doWork 失败（requestReceived 抛错）-> hasError==true
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        coord.requestReceivedThrows = true
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let router = InMemoryRouterHost()
        let vm = PresentationRequestViewModel(router: router, interactor: intr)
        vm.doWork()
        t.check(vm.viewState.hasError, "presVM.request_doWork_failure_hasError (cangjie-only)")
    }()

    // PresentationRequestViewModel.onShare 成功 -> 先进入 PIN/生物识别门禁；
    // 认证成功后再由 BiometricUiConfig 推到 presentationLoader。
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let router = InMemoryRouterHost()
        let vm = PresentationRequestViewModel(router: router, interactor: intr)
        let model = intr.onDeviceEngagement()  // 填充 claimIndex
        let selected = ArrayList<RequestDataCell>()
        for (s in model.sections) {
            for (c in s.cells) { selected.add(c) }
        }
        vm.onShare(selected)
        t.check(router.isScreenOnBackStack(AppRoutes.biometry),
            "presVM.request_onShare_success_pushesBiometry")
        t.check(!router.isScreenOnBackStack(AppRoutes.presentationLoader),
            "presVM.request_onShare_doesNotBypassAuthentication")
    }()

    // PresentationRequestViewModel.onShare 失败（空选择 -> prepare 返回 false）-> hasError，不推路由
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let router = InMemoryRouterHost()
        let vm = PresentationRequestViewModel(router: router, interactor: intr)
        vm.onShare(ArrayList<RequestDataCell>())
        t.check(vm.viewState.hasError, "presVM.request_onShare_emptyFail_hasError (cangjie-only)")
        t.check(!router.isScreenOnBackStack(AppRoutes.presentationLoader),
            "presVM.request_onShare_emptyFail_noPush (cangjie-only)")
    }()

    // PresentationRequestViewModel.onCancel -> 调 interactor.stopPresentation（wallet 计数 +1）
    { =>
        let coord = FakePresentationCoordinator(PresentationState.loading, makePresRequest())
        let wallet = makeWalletWithDoc()
        let intr = makeInteractor(coord, wallet)
        let router = InMemoryRouterHost()
        let vm = PresentationRequestViewModel(router: router, interactor: intr)
        vm.onCancel()
        t.eqInt(wallet.stopPresentationCalls, 1, "presVM.request_onCancel_stopsPresentation (cangjie-only)")
    }()

    // PresentationLoaderViewModel.doWork：状态为 responseToSend -> onSendResponse 成功 ->
    //   订阅观察到 responseSent -> 停止 + 路由到 presentationSuccess
    { =>
        let coord = FakePresentationCoordinator(
            PresentationState.responseToSend(makeConvertible()), makePresRequest())
        let wallet = makeWalletWithDoc()
        let intr = makeInteractor(coord, wallet)
        let router = InMemoryRouterHost()
        let vm = PresentationLoaderViewModel(router: router, interactor: intr)
        vm.doWork()
        // sendResponse 内部把状态推到 responseSent，sink 回调触发 routeToSuccess
        t.check(router.isScreenOnBackStack(AppRoutes.presentationSuccess),
            "presVM.loader_doWork_responseSent_routesToSuccess (cangjie-only)")
        t.eqInt(coord.sendResponseCalls, 1, "presVM.loader_doWork_invokesSendResponse (cangjie-only)")
    }()

    // PresentationLoaderViewModel.doWork：onSendResponse 失败（状态非 responseToSend）->
    //   hasError==true，不路由 success
    { =>
        let coord = FakePresentationCoordinator(PresentationState.prepareQr, makePresRequest())
        let intr = makeInteractor(coord, makeWalletWithDoc())
        let router = InMemoryRouterHost()
        let vm = PresentationLoaderViewModel(router: router, interactor: intr)
        vm.doWork()
        t.check(vm.viewState.hasError, "presVM.loader_doWork_sendFail_hasError (cangjie-only)")
        t.check(!router.isScreenOnBackStack(AppRoutes.presentationSuccess),
            "presVM.loader_doWork_sendFail_noSuccessRoute (cangjie-only)")
    }()
}

// ─────────────────────────────────────────────────────────────────────────────
// 入口（由 dev_unit_driver.cj:runAllUnitSuites 调用；本文件为 stash，未接驱动）
// ─────────────────────────────────────────────────────────────────────────────

func runFeaturePresentationTests(t: DeviceTestRun): Unit {
    runPresentationInteractorTests(t)
    runPresentationViewModelTests(t)
}
