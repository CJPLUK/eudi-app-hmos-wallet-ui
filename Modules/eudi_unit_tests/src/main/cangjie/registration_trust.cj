// Device unit tests for the registration-certificate (WRPRC) trust layer.
//
// Migrated 1:1 from four iOS test classes (wallet-kit 0.40.x upstream sync):
//   TestRelyingPartyRegistrationUiModel   (17 cases) — feature-common UI model
//   TestPresentationPolicyViolationOverasking (10 cases) — logic-core extension
//   TestPolicyPurposeLocalized            (4 cases)  — logic-core extension
//   TestRequestDataUiModelSelection       (3 cases)  — feature-common selection
//
// iOS asserts over RelyingPartyRegistration/IssuerRegistration mapping,
// [PresentationPolicyViolation].toOveraskedClaims() / [DocElements]
// .overaskedPaths(from:), [PolicyPurpose].localizedValue and
// filterSelectedRows(). The Cangjie counterparts are the top-level funcs in
// eudi_feature_common/registration_ui_model.cj and
// eudi_logic_core/registration_extensions.cj, plus
// RequestViewModel.selectedCells() + RequestDataCell.strippingOveraskedMark()
// (the HMOS carrier of the iOS filterSelectedRows semantics — flat groupId
// cells instead of iOS's nested ExpandableListItem tree).
package eudi_unit_tests

import std.collection.{ArrayList, HashMap}
import eudi_logic_core.{
    RelyingPartyRegistration, RegistrationStatus, RegistrationDetails,
    OveraskedClaim, IssuerRegistration, IssuerRegistrationBlockedReason,
    toOveraskedClaims, overaskedPathsByDocId, localizedPolicyPurposeValue,
    systemLanguageCode
}
import eudi_feature_common.{
    toRegistrationData, toWarning, issuerToRegistrationData, RegistrationWarning,
    RequestViewModel, RequestDataCell, RequestDataSection
}
import eudi_logic_ui.InMemoryRouterHost
import eudi_logic_resources.LocalizableStringKey
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.{
    PresentationPolicyViolation, PresentationFailureReason,
    DisclosedDocumentSet, DocElements, MsoMdocElements, NameSpacedElements,
    MsoMdocElement, SdJwtElements, SdJwtElement, PolicyPurpose
}
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vp.entity.dcql.{ClaimPath, ClaimPathElement}

// ─────────────────────────────────────────────────────────────────────────────
// Shared fixtures (iOS private extension helpers)
// ─────────────────────────────────────────────────────────────────────────────

/** iOS `details(logoUrl:)` — decoded WRPRC subject fields fixture. */
func rtDetails(logoUrl!: ?String = None): RegistrationDetails {
    RegistrationDetails(
        tradeName: "NordicBank A/S",
        uniqueId: "rp:nordicbank:prod",
        logoUrl: logoUrl,
        intendedUse: Some("Onboarding"),
        privacyPolicyUrl: Some("https://nordicbank.example/privacy"),
        serviceDescription: Some("Current account onboarding")
    )
}

/** iOS `relyingParty(status:)` — trusted access certificate + the given WRPRC verdict. */
func rtRelyingParty(status: RegistrationStatus): RelyingPartyRegistration {
    RelyingPartyRegistration(
        name: Some("NordicBank A/S"),
        uniqueId: Some("rp:nordicbank:prod"),
        isVerified: true,
        logoUrl: None,
        registration: status
    )
}

/** True when the optional key is `.custom(expected)`. */
func rtKeyIs(key: ?LocalizableStringKey, expected: String): Bool {
    match (key) {
        case Some(k) =>
            match (k) {
                case LocalizableStringKey.custom(v) => v == expected
                case _ => false
            }
        case None => false
    }
}

func rtWarnIs(w: ?RegistrationWarning, expected: RegistrationWarning): Bool {
    match (w) {
        case Some(v) => v == expected
        case None => false
    }
}

func rtOptStrIs(o: ?String, expected: String): Bool {
    match (o) {
        case Some(v) => v == expected
        case None => false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// iOS TestRelyingPartyRegistrationUiModel (17 cases)
// ─────────────────────────────────────────────────────────────────────────────

func runRelyingPartyRegistrationUiModelTests(t: DeviceTestRun): Unit {
    // testToRegistrationData_whenVerified_thenShowsRegistrationAndNoWarning
    let verified = rtRelyingParty(RegistrationStatus.verified(rtDetails(), Array<OveraskedClaim>()))
    let vData = toRegistrationData(verified, fallbackName: LocalizableStringKey.unknownVerifier)
    t.check(vData.primary.isVerified, "regTrust.verified_showsBadge")
    t.check(rtKeyIs(vData.intendedUse, "Onboarding"), "regTrust.verified_intendedUse")
    t.check(toWarning(verified).isNone(), "regTrust.verified_noWarning")

    // testToWarning_whenOverasked_thenReturnsOveraskedWarning
    let overasked = rtRelyingParty(RegistrationStatus.verified(
        rtDetails(),
        [OveraskedClaim(attestationType: "eu.europa.ec.eudi.pid.1", path: Some(["namespace", "age"]))]
    ))
    t.check(rtWarnIs(toWarning(overasked), RegistrationWarning.relyingPartyOverasked),
        "regTrust.overasked_warning")

    // testToWarning_whenNotVerified_thenReturnsNotVerifiedWarning
    let notVerified = rtRelyingParty(RegistrationStatus.notVerified(Some(rtDetails())))
    let nvData = toRegistrationData(notVerified, fallbackName: LocalizableStringKey.unknownVerifier)
    t.check(!nvData.primary.isVerified, "regTrust.notVerified_noBadge")
    t.check(rtWarnIs(toWarning(notVerified), RegistrationWarning.relyingPartyNotVerified),
        "regTrust.notVerified_warning")

    // testToRegistrationData_whenNotSupported_thenStillNamesTheRequester
    let notSupported = rtRelyingParty(RegistrationStatus.notSupported)
    let nsData = toRegistrationData(notSupported, fallbackName: LocalizableStringKey.unknownVerifier)
    t.check(rtKeyIs(Some(nsData.primary.name), "NordicBank A/S"), "regTrust.notSupported_namesRequester")
    t.check(nsData.primary.isVerified == notSupported.isFullyVerified,
        "regTrust.notSupported_badgeFollowsAccessCert")
    t.check(nsData.intendedUse.isNone(), "regTrust.notSupported_noIntendedUse")
    t.eqStr(nsData.privacyPolicyUrl, "", "regTrust.notSupported_noPrivacyPolicy")
    t.check(toWarning(notSupported).isNone(), "regTrust.notSupported_noWarning")

    // testToRegistrationData_whenRegistrationVerifiedButAccessCertificateIsNot_thenNoBadge
    let mismatched = RelyingPartyRegistration(
        name: Some("NordicBank A/S"),
        uniqueId: Some("rp:nordicbank:prod"),
        isVerified: false,
        logoUrl: None,
        registration: RegistrationStatus.verified(rtDetails(), Array<OveraskedClaim>())
    )
    let mData = toRegistrationData(mismatched, fallbackName: LocalizableStringKey.unknownVerifier)
    t.check(!mismatched.isFullyVerified, "regTrust.mismatch_notFullyVerified")
    t.check(!mData.primary.isVerified, "regTrust.mismatch_noBadge")
    t.check(rtKeyIs(mData.intendedUse, "Onboarding"), "regTrust.mismatch_sectionsStillRender")

    // testToRegistrationData_whenNotEvaluated_thenAccessCertificateDecidesAlone
    let trustedAlone = rtRelyingParty(RegistrationStatus.notSupported)
    let untrustedAlone = RelyingPartyRegistration(
        name: Some("NordicBank A/S"), uniqueId: None, isVerified: false,
        logoUrl: None, registration: RegistrationStatus.notSupported
    )
    t.check(trustedAlone.isFullyVerified, "regTrust.notEvaluated_trustedAccessCertShowsBadge")
    t.check(!untrustedAlone.isFullyVerified, "regTrust.notEvaluated_untrustedAccessCertNoBadge")

    // testToRegistrationData_whenNotVerified_thenStillNamesTheRequester
    t.check(rtKeyIs(Some(nvData.primary.name), "NordicBank A/S"), "regTrust.notVerified_namesRequester")
    t.check(!nvData.primary.isVerified, "regTrust.notVerified_namesRequester_noBadge")

    // testToRegistrationData_whenNotVerified_thenStillDescribesTheRequester
    t.check(rtKeyIs(nvData.intendedUse, "Onboarding"), "regTrust.notVerified_describes_intendedUse")
    t.eqStr(nvData.privacyPolicyUrl, "https://nordicbank.example/privacy",
        "regTrust.notVerified_describes_privacyPolicy")
    t.check(!notVerified.isFullyVerified, "regTrust.notVerified_describes_notFullyVerified")

    // testToRegistrationData_whenNotVerifiedAndUndecodable_thenOnlyTheNameSurvives
    let undecodable = rtRelyingParty(RegistrationStatus.notVerified(None))
    let uData = toRegistrationData(undecodable, fallbackName: LocalizableStringKey.unknownVerifier)
    t.check(rtKeyIs(Some(uData.primary.name), "NordicBank A/S"), "regTrust.undecodable_nameSurvives")
    t.check(uData.intendedUse.isNone(), "regTrust.undecodable_noIntendedUse")
    t.eqStr(uData.privacyPolicyUrl, "", "regTrust.undecodable_noPrivacyPolicy")

    // testResolveRequesterName_whenVerified_thenTheRegistrationNameWins
    let verifiedStatus = RegistrationStatus.verified(rtDetails(), Array<OveraskedClaim>())
    t.check(
        rtOptStrIs(verifiedStatus.resolveRequesterName(
            registrationName: Some("NordicBank A/S"), accessCertificateName: Some("nordicbank.example")
        ), "NordicBank A/S"),
        "regTrust.resolveName_verified_registrationWins")

    // testResolveRequesterName_whenNotVerified_thenTheAccessCertificateNameWins
    t.check(
        rtOptStrIs(RegistrationStatus.notVerified(None).resolveRequesterName(
            registrationName: Some("Definitely Your Bank"), accessCertificateName: Some("nordicbank.example")
        ), "nordicbank.example"),
        "regTrust.resolveName_notVerified_accessCertWins")

    // testResolveRequesterName_whenNamesAreMissing_thenFallsBackToTheOtherLayer
    t.check(
        rtOptStrIs(verifiedStatus.resolveRequesterName(
            registrationName: None, accessCertificateName: Some("nordicbank.example")
        ), "nordicbank.example"),
        "regTrust.resolveName_verifiedNoRegName_fallsBackToAccessCert")
    t.check(
        rtOptStrIs(RegistrationStatus.notVerified(None).resolveRequesterName(
            registrationName: Some("Definitely Your Bank"), accessCertificateName: None
        ), "Definitely Your Bank"),
        "regTrust.resolveName_notVerifiedNoAccessCert_fallsBackToRegName")
    t.check(
        RegistrationStatus.notSupported.resolveRequesterName(
            registrationName: Some("Definitely Your Bank"), accessCertificateName: None
        ).isNone(),
        "regTrust.resolveName_notSupportedNoAccessCert_none")

    // testResolveRequesterName_whenNotEvaluated_thenTheRegistrationIsIgnored
    t.check(
        rtOptStrIs(RegistrationStatus.notSupported.resolveRequesterName(
            registrationName: Some("Definitely Your Bank"), accessCertificateName: Some("nordicbank.example")
        ), "nordicbank.example"),
        "regTrust.resolveName_notEvaluated_registrationIgnored")

    // testIssuerToRegistrationData_whenCertificateHasNoLogo_thenFallsBackToIssuerMetadata
    let metaLogo = "https://issuer.example/logo.png"
    let noLogoData = issuerToRegistrationData(
        issuerRegistration: Some(IssuerRegistration.verified(rtDetails())),
        issuerName: "Aegean S.A.",
        issuerLogo: Some(metaLogo)
    )
    t.eqStr(noLogoData.primary.logoUrl, metaLogo, "regTrust.issuer_noCertLogo_metadataFallback")

    // testIssuerToRegistrationData_whenCertificateCarriesALogo_thenItWinsOverMetadata
    let certLogo = "https://registry.example/certified-logo.png"
    let certLogoData = issuerToRegistrationData(
        issuerRegistration: Some(IssuerRegistration.verified(rtDetails(logoUrl: Some(certLogo)))),
        issuerName: "Aegean S.A.",
        issuerLogo: Some(metaLogo)
    )
    t.eqStr(certLogoData.primary.logoUrl, certLogo, "regTrust.issuer_certLogo_winsOverMetadata")

    // testIssuerToRegistrationData_whenBlocked_thenStillNamesTheIssuer
    let blockedData = issuerToRegistrationData(
        issuerRegistration: Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.attestationNotRegistered)),
        issuerName: "Aegean S.A."
    )
    t.check(rtKeyIs(Some(blockedData.primary.name), "Aegean S.A."), "regTrust.issuerBlocked_namesIssuer")
    t.check(!blockedData.primary.isVerified, "regTrust.issuerBlocked_noSeal")
    t.check(blockedData.primary.identifier.isNone(), "regTrust.issuerBlocked_noIdentifier")
    t.check(blockedData.intendedUse.isNone(), "regTrust.issuerBlocked_noIntendedUse")

    // testIssuerToRegistrationData_whenNotEvaluated_thenStillNamesTheIssuer
    let nilRegData = issuerToRegistrationData(
        issuerRegistration: None,
        issuerName: "Aegean S.A.",
        issuerLogo: Some(metaLogo)
    )
    t.check(rtKeyIs(Some(nilRegData.primary.name), "Aegean S.A."), "regTrust.issuerNotEvaluated_namesIssuer")
    t.eqStr(nilRegData.primary.logoUrl, metaLogo, "regTrust.issuerNotEvaluated_metadataLogo")
    t.check(!nilRegData.primary.isVerified, "regTrust.issuerNotEvaluated_noSeal")
    t.eqStr(nilRegData.privacyPolicyUrl, "", "regTrust.issuerNotEvaluated_noPrivacyPolicy")
}

// ─────────────────────────────────────────────────────────────────────────────
// iOS TestPresentationPolicyViolationOverasking (10 cases)
// ─────────────────────────────────────────────────────────────────────────────

const RT_PID: String = "eu.europa.ec.eudi.pid.1"
const RT_NS: String = "eu.europa.ec.eudi.pid.1"
const RT_VCT: String = "urn:eu.europa.ec.eudi:pid:1"

/** iOS `claimPath(_:)` — every element a claim name. */
func rtClaimPath(parts: Array<String>): ClaimPath {
    let elements = ArrayList<ClaimPathElement>()
    for (p in parts) { elements.add(ClaimPathElement.claim(p)) }
    return ClaimPath(elements.toArray())
}

/** iOS `overaskingViolation(docType:paths:)`. */
func rtOveraskingViolation(docType: String, paths: ?Array<ClaimPath>): PresentationPolicyViolation {
    PresentationPolicyViolation(PresentationFailureReason.OverAskedClaims(docType, paths), "overasked")
}

/** iOS `overaskedClaim(_:_:)` — app-side claim with a concrete path. */
func rtOveraskedClaim(attestationType: String, path: Array<String>): OveraskedClaim {
    OveraskedClaim(attestationType: attestationType, path: Some(path))
}

/**
 * iOS `mdocElements(docId:claims:)`. docClaim stays None: the Cangjie
 * structural fallback derives the same [nameSpace, elementIdentifier] leaf
 * paths the iOS fixture writes into DocClaim.path.
 */
func rtMdocElements(docId: String, claims: Array<String>): DocElements {
    let elements = ArrayList<MsoMdocElement>()
    for (claim in claims) {
        elements.add(MsoMdocElement(claim, false, false, Some(claim), None, true, true))
    }
    let namespaces = ArrayList<NameSpacedElements>()
    namespaces.add(NameSpacedElements(RT_NS, elements))
    return DocElements.MsoMdoc(MsoMdocElements(docId, RT_PID, Some(RT_PID), true, namespaces))
}

/**
 * iOS `sdJwtElements(docId:claim:)` with the nested address→street tree. The
 * Cangjie fixture models the tree through nestedElements (docClaim None), the
 * transport shape this port pre-selects; leaf derivation is identical.
 */
func rtSdJwtNestedAddress(docId: String): DocElements {
    let street = SdJwtElement(["address", "street"], false, false, Some("street"), None, true, true, None)
    let nested = ArrayList<SdJwtElement>()
    nested.add(street)
    let address = SdJwtElement(["address"], false, false, Some(""), None, true, true, Some(nested))
    let elements = ArrayList<SdJwtElement>()
    elements.add(address)
    return DocElements.SdJwt(SdJwtElements(docId, RT_VCT, Some(RT_VCT), true, elements))
}

func rtSet(docs: Array<DocElements>): Array<DisclosedDocumentSet> {
    [DisclosedDocumentSet(docs, None)]
}

func rtPathsEq(a: Array<Array<String>>, b: Array<Array<String>>): Bool {
    if (a.size != b.size) { return false }
    var i = 0
    while (i < a.size) {
        if (a[i].size != b[i].size) { return false }
        var j = 0
        while (j < a[i].size) {
            if (a[i][j] != b[i][j]) { return false }
            j++
        }
        i++
    }
    return true
}

func rtMapEntryIs(map: HashMap<String, Array<Array<String>>>, docId: String, expected: Array<Array<String>>): Bool {
    match (map.get(docId)) {
        case Some(paths) => rtPathsEq(paths, expected)
        case None => false
    }
}

func runOveraskingExtensionTests(t: DeviceTestRun): Unit {
    // testToOveraskedClaims_whenViolationListsClaims_thenEachPathBecomesAClaim
    let listed = toOveraskedClaims([rtOveraskingViolation(
        RT_PID,
        Some([rtClaimPath([RT_NS, "family_name"]), rtClaimPath([RT_NS, "age_over_18"])])
    )])
    t.eqInt(listed.size, 2, "regTrust.toClaims_eachPathBecomesAClaim_count")
    var hasFamily = false
    var hasAge = false
    for (c in listed) {
        if (c == rtOveraskedClaim(RT_PID, [RT_NS, "family_name"])) { hasFamily = true }
        if (c == rtOveraskedClaim(RT_PID, [RT_NS, "age_over_18"])) { hasAge = true }
    }
    t.check(hasFamily, "regTrust.toClaims_containsFamilyName")
    t.check(hasAge, "regTrust.toClaims_containsAgeOver18")

    // testToOveraskedClaims_whenViolationListsNoClaims_thenTheWholeAttestationIsOverasked
    let whole = toOveraskedClaims([rtOveraskingViolation(RT_PID, None)])
    t.eqInt(whole.size, 1, "regTrust.toClaims_noPaths_singleClaim")
    t.check(whole.size == 1 && whole[0] == OveraskedClaim(attestationType: RT_PID, path: None),
        "regTrust.toClaims_noPaths_wholeAttestation")

    // testToOveraskedClaims_whenViolationIsNotAboutOverasking_thenItIsIgnored
    let unrelated = toOveraskedClaims([
        PresentationPolicyViolation(PresentationFailureReason.Expired, "expired"),
        PresentationPolicyViolation(PresentationFailureReason.TrustError, "untrusted")
    ])
    t.eqInt(unrelated.size, 0, "regTrust.toClaims_unrelatedReasonsIgnored")

    // testToOveraskedClaims_whenTheSameClaimIsReportedTwice_thenItIsKeptOnce
    let doubled = toOveraskedClaims([
        rtOveraskingViolation(RT_PID, Some([rtClaimPath([RT_NS, "family_name"])])),
        rtOveraskingViolation(RT_PID, Some([rtClaimPath([RT_NS, "family_name"])]))
    ])
    t.eqInt(doubled.size, 1, "regTrust.toClaims_duplicateKeptOnce")

    // testOveraskedPaths_whenNothingIsOverasked_thenNoDocumentIsMarked
    let noneMarked = overaskedPathsByDocId(
        rtSet([rtMdocElements("doc-1", ["family_name", "given_name"])]),
        Array<OveraskedClaim>()
    )
    t.eqInt(noneMarked.size, 0, "regTrust.paths_nothingOverasked_empty")

    // testOveraskedPaths_whenSomeClaimsAreOverasked_thenOnlyThoseAreMarked
    let someMarked = overaskedPathsByDocId(
        rtSet([rtMdocElements("doc-1", ["family_name", "age_over_18"])]),
        [rtOveraskedClaim(RT_PID, [RT_NS, "age_over_18"])]
    )
    t.eqInt(someMarked.size, 1, "regTrust.paths_someOverasked_oneDoc")
    t.check(rtMapEntryIs(someMarked, "doc-1", [[RT_NS, "age_over_18"]]),
        "regTrust.paths_someOverasked_onlyThatClaim")

    // testOveraskedPaths_whenTheAttestationItselfIsNotRegistered_thenEveryClaimIsMarked
    let allMarked = overaskedPathsByDocId(
        rtSet([rtMdocElements("doc-1", ["family_name", "age_over_18"])]),
        [OveraskedClaim(attestationType: RT_PID, path: None)]
    )
    t.check(rtMapEntryIs(allMarked, "doc-1", [[RT_NS, "family_name"], [RT_NS, "age_over_18"]]),
        "regTrust.paths_wholeAttestation_everyClaimMarked")

    // testOveraskedPaths_whenTheClaimBelongsToAnotherAttestation_thenNothingIsMarked
    let wrongType = overaskedPathsByDocId(
        rtSet([rtMdocElements("doc-1", ["family_name"])]),
        [rtOveraskedClaim("org.iso.18013.5.1.mDL", [RT_NS, "family_name"])]
    )
    t.eqInt(wrongType.size, 0, "regTrust.paths_otherAttestation_nothingMarked")

    // testOveraskedPaths_whenTheSameClaimIsRenderedByTwoDocuments_thenBothAreMarked
    let twoDocs = overaskedPathsByDocId(
        rtSet([rtMdocElements("doc-1", ["family_name"]), rtMdocElements("doc-2", ["family_name"])]),
        [rtOveraskedClaim(RT_PID, [RT_NS, "family_name"])]
    )
    t.eqInt(twoDocs.size, 2, "regTrust.paths_twoDocuments_bothPresent")
    t.check(rtMapEntryIs(twoDocs, "doc-1", [[RT_NS, "family_name"]]),
        "regTrust.paths_twoDocuments_firstMarked")
    t.check(rtMapEntryIs(twoDocs, "doc-2", [[RT_NS, "family_name"]]),
        "regTrust.paths_twoDocuments_secondMarked")

    // testOveraskedPaths_whenTheOveraskedPathIsAnAncestor_thenItsLeavesAreMarked
    let ancestor = overaskedPathsByDocId(
        rtSet([rtSdJwtNestedAddress("doc-1")]),
        [rtOveraskedClaim(RT_VCT, ["address"])]
    )
    t.check(rtMapEntryIs(ancestor, "doc-1", [["address", "street"]]),
        "regTrust.paths_ancestorPath_leavesMarked")
}

// ─────────────────────────────────────────────────────────────────────────────
// iOS TestPolicyPurposeLocalized (4 cases)
// ─────────────────────────────────────────────────────────────────────────────

/** Language subtag of a BCP-47 tag: text before the first '-'. */
func rtSubtag(tag: String): String {
    let bytes = tag.toArray()
    var i: Int64 = 0
    while (i < bytes.size) {
        if (bytes[i] == b'-') { return String.fromUtf8(bytes[0..i]) }
        i++
    }
    return tag
}

func runPolicyPurposeLocalizedTests(t: DeviceTestRun): Unit {
    // iOS `deviceLanguage` — dynamic, same source the production mapping reads.
    let deviceLanguage = systemLanguageCode()

    // testLocalizedValue_whenEmpty_thenReturnsNil
    t.check(localizedPolicyPurposeValue(Some(Array<PolicyPurpose>())).isNone(),
        "regTrust.purpose_empty_none")

    // testLocalizedValue_whenDeviceLanguageIsCarried_thenPrefersIt
    let carried = localizedPolicyPurposeValue(Some([
        PolicyPurpose("zz", "Wrong language"),
        PolicyPurpose(deviceLanguage, "Name verification")
    ]))
    t.check(rtOptStrIs(carried, "Name verification"), "regTrust.purpose_deviceLanguage_preferred")

    // testLocalizedValue_whenNoEntryMatches_thenFallsBackToTheFirst
    let fallback = localizedPolicyPurposeValue(Some([
        PolicyPurpose("zz", "First written"),
        PolicyPurpose("yy", "Second written")
    ]))
    t.check(rtOptStrIs(fallback, "First written"), "regTrust.purpose_noMatch_firstWins")

    // testLocalizedValue_whenTagCarriesRegionOrCasing_thenStillMatches
    let regional = localizedPolicyPurposeValue(Some([
        PolicyPurpose("zz", "Wrong language"),
        PolicyPurpose(rtSubtag(deviceLanguage).toAsciiUpper() + "-GB", "Name verification")
    ]))
    t.check(rtOptStrIs(regional, "Name verification"), "regTrust.purpose_regionAndCasing_stillMatches")
}

// ─────────────────────────────────────────────────────────────────────────────
// iOS TestRequestDataUiModelSelection (3 cases)
// HMOS carrier: RequestViewModel.selectedCells() rebuilds the confirmed rows
// via RequestDataCell.strippingOveraskedMark() (flat groupId cells replace the
// iOS nested ExpandableListItem tree).
// ─────────────────────────────────────────────────────────────────────────────

func rtSelectionVm(cells: ArrayList<RequestDataCell>): RequestViewModel {
    let vm = RequestViewModel(router: InMemoryRouterHost())
    let sections = ArrayList<RequestDataSection>()
    sections.add(RequestDataSection(id: "doc-id", title: "Document", cells: cells))
    vm.setItems(relyingParty: "Verifier", relyingPartyIsTrusted: true, sections: sections)
    return vm
}

func runRequestSelectionOveraskedTests(t: DeviceTestRun): Unit {
    // testFilterSelectedRows_whenARowIsOverasked_thenTheMarkDoesNotTravelOnwards
    let cells1 = ArrayList<RequestDataCell>()
    cells1.add(RequestDataCell(title: "Age", value: "value", isOverasked: true))
    let selected1 = rtSelectionVm(cells1).selectedCells()
    t.eqInt(selected1.size, 1, "regTrust.selection_overaskedRow_survives")
    t.check(selected1.size == 1 && !selected1[0].isOverasked,
        "regTrust.selection_overaskedRow_markStripped")

    // testFilterSelectedRows_whenARowIsNotSelected_thenItIsDropped
    let cells2 = ArrayList<RequestDataCell>()
    cells2.add(RequestDataCell(title: "Age", value: "value", selected: Some(false), isOverasked: true))
    cells2.add(RequestDataCell(title: "Family name", value: "value"))
    let selected2 = rtSelectionVm(cells2).selectedCells()
    t.eqInt(selected2.size, 1, "regTrust.selection_unselectedRow_dropped")
    t.check(selected2.size == 1 && selected2[0].title == "Family name",
        "regTrust.selection_survivorIsTheSelectedRow")

    // testFilterSelectedRows_whenRowsAreNested_thenTheMarkIsDroppedFromTheChildren
    // (HMOS request rows are flat groupId cells — a grouped child row is a cell
    // sharing the group's id; the mark must be stripped from it all the same.)
    let cells3 = ArrayList<RequestDataCell>()
    cells3.add(RequestDataCell(groupId: Some("group"), title: "Street", value: "street", isOverasked: true))
    let selected3 = rtSelectionVm(cells3).selectedCells()
    t.check(selected3.size == 1 && !selected3[0].isOverasked && selected3[0].groupId == "group",
        "regTrust.selection_groupedChild_markStripped")
}

// ─────────────────────────────────────────────────────────────────────────────
// Suite entry — called from unit_driver.runAllUnitSuites
// ─────────────────────────────────────────────────────────────────────────────

func runRegistrationTrustTests(t: DeviceTestRun): Unit {
    runRelyingPartyRegistrationUiModelTests(t)
    runOveraskingExtensionTests(t)
    runPolicyPurposeLocalizedTests(t)
    runRequestSelectionOveraskedTests(t)
}
