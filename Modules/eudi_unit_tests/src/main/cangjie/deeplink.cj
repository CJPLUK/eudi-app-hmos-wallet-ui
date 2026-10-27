// Device unit tests for eudi_logic_ui DeepLinkController, migrated 1:1 from iOS
// logic-ui/Tests/Controller/TestDeepLinkController.swift (21 cases). Runs via the
// device bridge (DeviceTestRun in dev_unit_driver.cj). Hand-written fakes replace
// iOS Cuckoo mocks: a fake UrlSchemaController (name → schemas map, or a name→list
// closure), a real in-memory PrefsController, and InMemoryRouterHost from
// eudi_logic_ui for push/popTo/foreground state.
//
// iOS asserts opaque side effects indirectly (verify router.push / prefs.remove).
// The Cangjie controller records the branch it took as a DeepLinkOutcome AND makes
// the real RouterHost push/popTo call, so each iOS assertion maps to either an
// outcome check, a router-stack check, or a prefs-state check (stronger than the
// iOS `push(any())`). Three cases have iOS-only effects (NotificationCenter post
// on the already-foreground branches; EudiRQESUi.resume on the rqes-with-code
// branch) that cannot run in a unit test; they map to the equivalent decision
// point (PresentationAlreadyForeground / IssuanceAlreadyForeground / RqesResume)
// and are annotated inline. Every one of the 21 iOS cases has a real assertion.
package eudi_unit_tests

import std.collection.HashMap
import eudi_logic_ui.{
    DeepLinkController, DeepLinkControllerImpl, DeepLinkAction, DeepLinkExecutable,
    DeepLinkOutcome, UrlSchemaController, InMemoryRouterHost, AppRoutes
}
import eudi_logic_business.{PrefsController, PrefsKey, ParsedUrl, UrlUtil}

// ── Fakes ─────────────────────────────────────────────────────────────────────

// iOS MockUrlSchemaController.retrieveSchemas(with:) faked via thenReturn/then.
// Two shapes: a fixed list for every name, or a per-name closure (test 21).
class FakeUrlSchemaController <: UrlSchemaController {
    private var fixed: Array<String> = Array<String>()
    private var byName: ?(String) -> Array<String> = None

    public func retrieveSchemas(name: String): Array<String> {
        match (this.byName) {
            case Some(fn) => return fn(name)
            case None => return this.fixed
        }
    }

    func returnAlways(schemas: Array<String>): Unit { this.fixed = schemas }
    func returnPerName(fn: (String) -> Array<String>): Unit { this.byName = fn }
}

// In-memory PrefsController (iOS MockPrefsController). Records set/remove counts so
// the iOS verify(times(0)/times(1)) assertions map to counters, and stores values
// so getString round-trips for the getPending* / cache / remove cases.
class FakeDeepLinkPrefs <: PrefsController {
    let values = HashMap<String, String>()
    var setCount: Int64 = 0
    var removeCount: Int64 = 0

    public func setValue(value: ToString, forKey: PrefsKey): Unit {
        this.setCount += 1
        this.values[forKey.rawValue] = value.toString()
    }
    public func getString(forKey: PrefsKey): ?String { this.values.get(forKey.rawValue) }
    public func getOptionalString(forKey: PrefsKey): String { this.getString(forKey) ?? "" }
    public func getBool(forKey: PrefsKey): Bool { false }
    public func getFloat(forKey: PrefsKey): Float64 { 0.0 }
    public func getInt(forKey: PrefsKey): Int64 { 0 }
    public func remove(forKey: PrefsKey): Unit {
        this.removeCount += 1
        this.values.remove(forKey.rawValue)
    }
    public func getValue(forKey: PrefsKey): ?String { this.getString(forKey) }
    public func getUserLocale(): String { "en_GB" }

    func hasCachedDeepLink(): Bool { this.values.contains(PrefsKey.cachedDeepLink.rawValue) }
}

// ── Fixtures (mirror iOS static mocked* values) ────────────────────────────────

let DL_OPENID4VP_URL =
    "eudi-openid4vp://verifier-backend.eudiw.dev?client_id=verifier-backend.eudiw.dev&request_uri=https://verifier-backend.eudiw.dev/wallet/request.jwt/x"
let DL_EXTERNAL_URL = "https://commission.europa.eu"
let DL_RQES_URL = "rqes://callback?code=auth-code"
let DL_MALFORMED_URL = "not_a_valid_url"
// iOS mocked openid4vp schema list.
let DL_OPENID4VP_SCHEMAS: Array<String> = ["eudi-openid4vp", "mdoc-openid4vp"]

// Builds a DeepLinkExecutable directly from a URL string + action (iOS builds
// DeepLink.Executable(link: URLComponents(url:...)!, plainUrl: url, action:)).
func makeExecutable(url: String, action: DeepLinkAction): DeepLinkExecutable {
    let parsed = UrlUtil.parse(url).getOrThrow()
    return DeepLinkExecutable(parsed, url, action)
}

func makeDeepLinkController(schema: FakeUrlSchemaController): (DeepLinkControllerImpl, FakeDeepLinkPrefs) {
    let prefs = FakeDeepLinkPrefs()
    return (DeepLinkControllerImpl(prefs, schema), prefs)
}

// ── Tests (iOS TestDeepLinkController, 21) ─────────────────────────────────────

func runDeepLinkTests(t: DeviceTestRun): Unit {
    // ── testHasDeepLink_WhenUrlIsAValidOpenId4VPDeepLink_ThenReturnDeepLinkActionWithOpenId4VPType ──
    // 1. hasDeepLink, valid OpenId4VP URL → executable with .openid4vp.
    //    iOS: XCTAssertEqual(action, mockedOpenId4VPDeepLinkAction)
    let s1 = FakeUrlSchemaController(); s1.returnAlways(DL_OPENID4VP_SCHEMAS)
    let (c1, _) = makeDeepLinkController(s1)
    match (c1.hasDeepLink(DL_OPENID4VP_URL)) {
        case Some(exec) => t.check(exec.action == DeepLinkAction.Openid4vp, "deeplink.hasDeepLink_openid4vp_type")
        case None => t.check(false, "deeplink.hasDeepLink_openid4vp_type (got None)")
    }

    // ── testHasDeepLink_WhenUrlIsNotKnownType_ThenReturnDeepLinkActionWithExternalType ──
    // 2. hasDeepLink, unknown scheme → executable with .external.
    //    iOS: XCTAssertEqual(action, mockedExternalDeepLinkAction)
    let s2 = FakeUrlSchemaController(); s2.returnAlways(Array<String>())
    let (c2, _) = makeDeepLinkController(s2)
    match (c2.hasDeepLink(DL_EXTERNAL_URL)) {
        case Some(exec) => t.check(exec.action == DeepLinkAction.External, "deeplink.hasDeepLink_unknown_external")
        case None => t.check(false, "deeplink.hasDeepLink_unknown_external (got None)")
    }

    // ── testHasDeepLink_WhenUrlIsMalformed_ThenReturnDeepLinkActionNil ──
    // 3. hasDeepLink, malformed URL → None. iOS: XCTAssertNil(action)
    let s3 = FakeUrlSchemaController()
    let (c3, _) = makeDeepLinkController(s3)
    t.check(c3.hasDeepLink(DL_MALFORMED_URL).isNone(), "deeplink.hasDeepLink_malformed_nil")

    // ── testHandleDeepLinkAction_WhenRouterReturnsPreAuthorizationFlow_ThenValidateCachingOfDeepLink ──
    // 4. Pre-authorization flow (not logged in) → caches URL, does NOT remove.
    //    iOS: verify setValue(cachedDeepLink); verify times(0) remove(cachedDeepLink)
    let s4 = FakeUrlSchemaController(); s4.returnAlways(DL_OPENID4VP_SCHEMAS)
    let (c4, p4) = makeDeepLinkController(s4)
    let r4 = InMemoryRouterHost()
    r4.setLoggedInWithDocuments(false)
    r4.setLoggedInWithNoDocuments(false)
    let exec4 = makeExecutable(DL_OPENID4VP_URL, DeepLinkAction.Openid4vp)
    let out4 = c4.handleDeepLinkAction(r4, exec4, false)
    t.check(out4 == DeepLinkOutcome.Cached, "deeplink.preAuth_cached_outcome")
    t.check(p4.setCount == 1, "deeplink.preAuth_setValueInvoked")
    t.check(p4.removeCount == 0, "deeplink.preAuth_removeNotInvoked")
    t.check(p4.hasCachedDeepLink(), "deeplink.preAuth_urlPersisted")

    // ── testHandleDeepLinkAction_WhenRouterReturnsAfterAuthorizationFlowAndActionIsOpenId4VPAndScreenNotForeground_ThenValidateCachingRemovalAndExecutionOfNavigation ──
    // 5. Post-auth, openid4vp, screen NOT foreground → remove cache + push presentation.
    //    iOS: verify times(0) setValue; verify remove; verify push(presentationRoute)
    let s5 = FakeUrlSchemaController(); s5.returnAlways(DL_OPENID4VP_SCHEMAS)
    let (c5, p5) = makeDeepLinkController(s5)
    let r5 = InMemoryRouterHost()
    r5.setLoggedInWithDocuments(true)
    let exec5 = makeExecutable(DL_OPENID4VP_URL, DeepLinkAction.Openid4vp)
    let out5 = c5.handleDeepLinkAction(r5, exec5, true /* hasCoordinator */)
    t.check(out5 == DeepLinkOutcome.PushedPresentation, "deeplink.postAuth_openid4vp_notFg_outcome")
    t.check(p5.setCount == 0, "deeplink.postAuth_openid4vp_setValueNotInvoked")
    t.check(p5.removeCount == 1, "deeplink.postAuth_openid4vp_removeInvoked")
    t.check(r5.isScreenOnBackStack(AppRoutes.presentationRequest), "deeplink.postAuth_openid4vp_pushedPresentation")

    // ── testHandleDeepLinkAction_WhenRouterReturnsAfterAuthorizationFlowAndActionIsOpenId4VPAndScreenIsForeground_ThenValidateCachingRemovalAndRouteNil ──
    // 6. Post-auth, openid4vp, screen IS foreground → remove cache, NO push.
    //    iOS: verify times(0) setValue; verify remove; verify times(0) push.
    //    (iOS then posts NotificationCenter.PresentationVC — a platform-only effect
    //     with no HAR counterpart; the decision point is PresentationAlreadyForeground.)
    let s6 = FakeUrlSchemaController(); s6.returnAlways(DL_OPENID4VP_SCHEMAS)
    let (c6, p6) = makeDeepLinkController(s6)
    let r6 = InMemoryRouterHost()
    r6.setLoggedInWithDocuments(true)
    r6.push(AppRoutes.presentationRequest) // make presentationRequest the foreground screen
    let depth6 = r6.stackSize()
    let exec6 = makeExecutable(DL_OPENID4VP_URL, DeepLinkAction.Openid4vp)
    let out6 = c6.handleDeepLinkAction(r6, exec6, true)
    t.check(out6 == DeepLinkOutcome.PresentationAlreadyForeground, "deeplink.postAuth_openid4vp_fg_outcome")
    t.check(p6.removeCount == 1, "deeplink.postAuth_openid4vp_fg_removeInvoked")
    t.check(p6.setCount == 0, "deeplink.postAuth_openid4vp_fg_setValueNotInvoked")
    t.check(r6.stackSize() == depth6, "deeplink.postAuth_openid4vp_fg_noPush")

    // ── testHandleDeepLinkAction_WhenRouterReturnsAfterAuthorizationFlowAndActionIsExternal_ThenValidateCachingRemovalAndNoInvocationOfRouter ──
    // 7. Post-auth, external → remove cache, NO router invocation.
    //    iOS: verify times(0) setValue; verify remove; verify times(0) push.
    //    (iOS then calls plainUrl.open() — system browser, no HAR counterpart.)
    let s7 = FakeUrlSchemaController(); s7.returnAlways(Array<String>())
    let (c7, p7) = makeDeepLinkController(s7)
    let r7 = InMemoryRouterHost()
    r7.setLoggedInWithDocuments(true)
    let exec7 = makeExecutable(DL_EXTERNAL_URL, DeepLinkAction.External)
    let out7 = c7.handleDeepLinkAction(r7, exec7, false)
    t.check(out7 == DeepLinkOutcome.ExternalOpen, "deeplink.postAuth_external_outcome")
    t.check(p7.removeCount == 1, "deeplink.postAuth_external_removeInvoked")
    t.check(p7.setCount == 0, "deeplink.postAuth_external_setValueNotInvoked")
    t.check(r7.stackSize() == 0, "deeplink.postAuth_external_noPush")

    // ── testGetPendingDeepLinkAction_WhenCachedDeepLinkIsValidAndActionRequiresCoordinator_ThenReturnDeepListActionAndVerifyCoordinatorFlag ──
    // 8. getPendingDeepLinkAction, cached + action requires coordinator (openid4vp)
    //    → returns executable, requiresCoordinator == true.
    let s8 = FakeUrlSchemaController(); s8.returnAlways(DL_OPENID4VP_SCHEMAS)
    let (c8, p8) = makeDeepLinkController(s8)
    p8.values[PrefsKey.cachedDeepLink.rawValue] = DL_OPENID4VP_URL
    match (c8.getPendingDeepLinkAction()) {
        case Some(exec) =>
            t.check(exec.action == DeepLinkAction.Openid4vp, "deeplink.getPending_requiresCoordinator_action")
            t.check(exec.requiresCoordinator, "deeplink.getPending_requiresCoordinator_true")
        case None => t.check(false, "deeplink.getPending_requiresCoordinator (got None)")
    }

    // ── testGetPendingDeepLinkAction_WhenCachedDeepLinkIsValidAndActionDoesNotRequireCoordinator_ThenReturnDeepListActionAndVerifyCoordinatorFlag ──
    // 9. getPendingDeepLinkAction, cached + action does NOT require coordinator (external)
    //    → returns executable, requiresCoordinator == false.
    let s9 = FakeUrlSchemaController(); s9.returnAlways(DL_OPENID4VP_SCHEMAS)
    let (c9, p9) = makeDeepLinkController(s9)
    p9.values[PrefsKey.cachedDeepLink.rawValue] = DL_EXTERNAL_URL
    match (c9.getPendingDeepLinkAction()) {
        case Some(exec) =>
            t.check(exec.action == DeepLinkAction.External, "deeplink.getPending_noCoordinator_action")
            t.check(!exec.requiresCoordinator, "deeplink.getPending_noCoordinator_false")
        case None => t.check(false, "deeplink.getPending_noCoordinator (got None)")
    }

    // ── testGetPendingDeepLinkAction_WhenCachedDeepLinkIsInvalid_ThenReturnDeepListActionNil ──
    // 10. getPendingDeepLinkAction, cached value is invalid URL → None.
    let s10 = FakeUrlSchemaController()
    let (c10, p10) = makeDeepLinkController(s10)
    p10.values[PrefsKey.cachedDeepLink.rawValue] = DL_MALFORMED_URL
    t.check(c10.getPendingDeepLinkAction().isNone(), "deeplink.getPending_invalidCached_nil")

    // ── testGetPendingDeepLinkAction_WhenPrefsControllerReturnsNil_ThenReturnDeepListActionNil ──
    // 11. getPendingDeepLinkAction, prefs returns nil (nothing cached) → None.
    let s11 = FakeUrlSchemaController()
    let (c11, _) = makeDeepLinkController(s11)
    t.check(c11.getPendingDeepLinkAction().isNone(), "deeplink.getPending_prefsNil_nil")

    // ── testCacheDeepLinkURL_WhenUrlIsProvided_ThenVerifyMethodInvocation ──
    // 12. cacheDeepLinkURL → setValue(cachedDeepLink) invoked.
    let s12 = FakeUrlSchemaController()
    let (c12, p12) = makeDeepLinkController(s12)
    c12.cacheDeepLinkURL(DL_OPENID4VP_URL)
    t.check(p12.setCount == 1, "deeplink.cacheDeepLinkURL_setInvoked")
    t.eqStr(p12.getString(PrefsKey.cachedDeepLink) ?? "", DL_OPENID4VP_URL, "deeplink.cacheDeepLinkURL_valueStored")

    // ── testHandleDeepLinkAction_WhenCredentialOfferActionAndScreenIsNotForeground_ThenPushCredentialOfferRequest ──
    // 13. Post-auth, credential_offer, screen IS foreground → remove, NO push.
    //     iOS: verify times(0) setValue; verify remove; verify times(0) push.
    //     The iOS name says "NotForeground" but its stub passes
    //     isScreenForeground: true and it asserts times(0) push, so the
    //     foreground branch is what that case actually covers. Case 14 is the
    //     genuinely-not-foreground one. Matched on behaviour, not on the name.
    let s13 = FakeUrlSchemaController(); s13.returnAlways(Array<String>())
    let (c13, p13) = makeDeepLinkController(s13)
    let r13 = InMemoryRouterHost()
    r13.setLoggedInWithDocuments(true)
    r13.push(AppRoutes.credentialOfferRequest) // foreground = credentialOfferRequest
    let depth13 = r13.stackSize()
    let exec13 = makeExecutable(DL_EXTERNAL_URL, DeepLinkAction.CredentialOffer)
    let out13 = c13.handleDeepLinkAction(r13, exec13, false)
    t.check(out13 == DeepLinkOutcome.IssuanceAlreadyForeground, "deeplink.postAuth_credentialOffer_fg_outcome")
    t.check(p13.removeCount == 1, "deeplink.postAuth_credentialOffer_fg_removeInvoked")
    t.check(r13.stackSize() == depth13, "deeplink.postAuth_credentialOffer_fg_noPush")

    // ── testHandleDeepLinkAction_WhenCredentialOfferActionAndScreenIsNotForeground_ThenPushesIssuanceRoute ──
    // 14. Post-auth, credential_offer, screen NOT foreground → push issuance route.
    //     iOS: verify remove; verify push(any()).
    let s14 = FakeUrlSchemaController(); s14.returnAlways(Array<String>())
    let (c14, p14) = makeDeepLinkController(s14)
    let r14 = InMemoryRouterHost()
    r14.setLoggedInWithDocuments(true)
    let exec14 = makeExecutable(DL_EXTERNAL_URL, DeepLinkAction.CredentialOffer)
    let out14 = c14.handleDeepLinkAction(r14, exec14, false)
    t.check(out14 == DeepLinkOutcome.PushedIssuance, "deeplink.postAuth_credentialOffer_notFg_outcome")
    t.check(p14.removeCount == 1, "deeplink.postAuth_credentialOffer_notFg_removeInvoked")
    t.check(r14.isScreenOnBackStack(AppRoutes.credentialOfferRequest), "deeplink.postAuth_credentialOffer_notFg_pushedIssuance")

    // ── testHandleDeepLinkAction_WhenActionIsHaipVpAndScreenNotForeground_ThenPushesPresentationRoute ──
    // 15. Post-auth, haip_vp (shares openid4vp arm), NOT foreground → push presentation.
    //     iOS: verify remove; verify push(any()).
    let s15 = FakeUrlSchemaController(); s15.returnAlways(Array<String>())
    let (c15, p15) = makeDeepLinkController(s15)
    let r15 = InMemoryRouterHost()
    r15.setLoggedInWithDocuments(true)
    let exec15 = makeExecutable(DL_OPENID4VP_URL, DeepLinkAction.HaipVp)
    let out15 = c15.handleDeepLinkAction(r15, exec15, true /* hasCoordinator */)
    t.check(out15 == DeepLinkOutcome.PushedPresentation, "deeplink.postAuth_haipVp_notFg_outcome")
    t.check(p15.removeCount == 1, "deeplink.postAuth_haipVp_notFg_removeInvoked")
    t.check(r15.isScreenOnBackStack(AppRoutes.presentationRequest), "deeplink.postAuth_haipVp_notFg_pushedPresentation")

    // ── testHandleDeepLinkAction_WhenActionIsHaipVciAndScreenNotForeground_ThenPushesIssuanceRoute ──
    // 16. Post-auth, haip_vci (shares credential_offer arm), NOT foreground → push issuance.
    //     iOS: verify remove; verify push(any()).
    let s16 = FakeUrlSchemaController(); s16.returnAlways(Array<String>())
    let (c16, p16) = makeDeepLinkController(s16)
    let r16 = InMemoryRouterHost()
    r16.setLoggedInWithDocuments(true)
    let exec16 = makeExecutable(DL_EXTERNAL_URL, DeepLinkAction.HaipVci)
    let out16 = c16.handleDeepLinkAction(r16, exec16, false)
    t.check(out16 == DeepLinkOutcome.PushedIssuance, "deeplink.postAuth_haipVci_notFg_outcome")
    t.check(p16.removeCount == 1, "deeplink.postAuth_haipVci_notFg_removeInvoked")
    t.check(r16.isScreenOnBackStack(AppRoutes.credentialOfferRequest), "deeplink.postAuth_haipVci_notFg_pushedIssuance")

    // ── testHandleDeepLinkAction_WhenRqesPendingAndUserLoggedInWithDocuments_ThenPopsToDashboard ──
    // 17. rqes pending + logged in with documents + not on dashboard → cache + popTo(dashboard).
    //     iOS: verify setValue(cachedDeepLink); verify popTo(any(), inclusive: false).
    let s17 = FakeUrlSchemaController(); s17.returnAlways(Array<String>())
    let (c17, p17) = makeDeepLinkController(s17)
    let r17 = InMemoryRouterHost()
    r17.setLoggedInWithDocuments(true)
    r17.setLoggedInWithNoDocuments(false)
    // Put dashboard on the back stack under another screen so popTo has a target
    // AND the foreground screen is not dashboard (isRqesPendingAction true).
    r17.push(AppRoutes.dashboard)
    r17.push(AppRoutes.documentDetails)
    let exec17 = makeExecutable(DL_RQES_URL, DeepLinkAction.Rqes)
    let out17 = c17.handleDeepLinkAction(r17, exec17, false)
    t.check(out17 == DeepLinkOutcome.CachedAndPoppedToDashboard, "deeplink.rqes_pending_loggedIn_outcome")
    t.check(p17.setCount == 1, "deeplink.rqes_pending_loggedIn_setValueInvoked")
    t.check(r17.isScreenForeground(AppRoutes.dashboard), "deeplink.rqes_pending_loggedIn_poppedToDashboard")

    // ── testHandleDeepLinkAction_WhenRqesWithoutAuthorizationCode_ThenEarlyReturn ──
    // 18. rqes without a `code` query item + post-auth + on dashboard → remove, early return, NO push.
    //     iOS: verify remove; verify times(0) push.
    let s18 = FakeUrlSchemaController(); s18.returnAlways(Array<String>())
    let (c18, p18) = makeDeepLinkController(s18)
    let r18 = InMemoryRouterHost()
    r18.setLoggedInWithDocuments(true)
    r18.setLoggedInWithNoDocuments(false)
    r18.push(AppRoutes.dashboard) // on dashboard → isRqesPendingAction false → post-auth
    let depth18 = r18.stackSize()
    let exec18 = makeExecutable("rqes://callback?other=value", DeepLinkAction.Rqes)
    let out18 = c18.handleDeepLinkAction(r18, exec18, false)
    t.check(out18 == DeepLinkOutcome.RqesNoCode, "deeplink.rqes_noCode_outcome")
    t.check(p18.removeCount == 1, "deeplink.rqes_noCode_removeInvoked")
    t.check(r18.stackSize() == depth18, "deeplink.rqes_noCode_noPush")

    // ── testHandleDeepLinkAction_WhenRqesWithAuthorizationCode_ThenSchedulesResumeTask ──
    // 19. rqes WITH a `code` query item + post-auth + on dashboard → schedules resume.
    //     iOS: reaches the Task { EudiRQESUi.resume(...) } block (the poll loop never
    //     resolves in a unit test, so iOS only verifies remove). Equivalent decision
    //     point here: RqesResume(code) is recorded (real EudiRQESUi.resume has no HAR
    //     counterpart). Also verify the extracted code matches.
    let s19 = FakeUrlSchemaController(); s19.returnAlways(Array<String>())
    let (c19, p19) = makeDeepLinkController(s19)
    let r19 = InMemoryRouterHost()
    r19.setLoggedInWithDocuments(true)
    r19.setLoggedInWithNoDocuments(false)
    r19.push(AppRoutes.dashboard)
    let exec19 = makeExecutable("rqes://callback?code=abc123", DeepLinkAction.Rqes)
    let out19 = c19.handleDeepLinkAction(r19, exec19, false)
    t.check(out19 == DeepLinkOutcome.RqesResume("abc123"), "deeplink.rqes_withCode_resumeScheduled")
    t.check(p19.removeCount == 1, "deeplink.rqes_withCode_removeInvoked")
    t.eqStr(exec19.code ?? "", "abc123", "deeplink.rqes_withCode_codeExtracted")

    // ── testRemoveCachedDeepLinkURL_WhenCalled_ThenDelegatesToPrefsController ──
    // 20. removeCachedDeepLinkURL → delegates to prefs.remove(cachedDeepLink).
    let s20 = FakeUrlSchemaController()
    let (c20, p20) = makeDeepLinkController(s20)
    p20.values[PrefsKey.cachedDeepLink.rawValue] = DL_OPENID4VP_URL
    c20.removeCachedDeepLinkURL()
    t.check(p20.removeCount == 1, "deeplink.removeCachedDeepLinkURL_delegates")
    t.check(!p20.hasCachedDeepLink(), "deeplink.removeCachedDeepLinkURL_cleared")

    // ── testHasDeepLink_WhenSchemaControllerMatchesRqes_ThenActionIsRqes ──
    // 21. hasDeepLink, schema controller matches rqes for name=="rqes" → action .rqes.
    //     iOS: closure returns ["rqes-callback"] only when name == "rqes".
    let s21 = FakeUrlSchemaController()
    s21.returnPerName({ name => if (name == "rqes") { ["rqes-callback"] } else { Array<String>() } })
    let (c21, _) = makeDeepLinkController(s21)
    match (c21.hasDeepLink("rqes-callback://complete?code=abc")) {
        case Some(exec) => t.check(exec.action == DeepLinkAction.Rqes, "deeplink.hasDeepLink_rqesSchema_type")
        case None => t.check(false, "deeplink.hasDeepLink_rqesSchema_type (got None)")
    }
}
