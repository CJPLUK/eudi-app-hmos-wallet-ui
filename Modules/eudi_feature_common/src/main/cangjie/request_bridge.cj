/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. The shared request/response bridge for
 * the presentation (OpenID4VP) and proximity (BLE) data-sharing flows.
 *
 * iOS decodes a presentation request into RequestDataUiModel trees via logic-
 * core's `toUiModels`, and reverse-maps the selected rows into a
 * RequestItemConvertible via `prepareRequest()` / `filterSelectedRows()`. The
 * Cangjie logic-core seam exposes the request as a PresentationRequest and
 * preserves each verifier-requested claim (path, namespace, optionality and
 * availability). Stored claims are consulted only for their display metadata
 * and values (WalletKitController.fetchDocument → docClaims), then surfaced as the
 * RequestDataSection / RequestDataCell selection model rendered by
 * BaseRequestView. On confirm the selected cells are reverse-mapped into a
 * RequestItemsWrapper (docId → namespace → [RequestItem]) — exactly the
 * RequestItemConvertible the engine's sendResponse consumes.
 *
 * Lives in feature-common so both feature-presentation and feature-proximity
 * share one bridge (the request shape is identical for remote and proximity
 * coordinators). UI-free.
 */
package eudi_feature_common

import std.collection.{ArrayList, HashMap}
import eudi_logic_core.{
    PresentationRequest, WalletKitController, DocClaim, RelyingPartyRegistration,
    RequestItem, RequestedClaim, RequestItemConvertible, RequestItemsWrapper, RequestConvertibleItems
}

/** Mirrors iOS `OnlineAuthenticationRequestSuccessModel` — the request-received
 *  payload the request screens render (relying party + selectable sections). */
public class RequestReceivedModel {
    public let isSuccess: Bool
    public let relyingParty: String
    public let dataRequestInfo: String
    public let isTrusted: Bool
    // iOS `requestDataCombinations: [[RequestDataUiModel]]` — each inner list is one
    // combination's document sections. Single-combination requests have exactly one.
    public let combinations: ArrayList<ArrayList<RequestDataSection>>
    public let errorMessage: String
    /**
     * iOS `OnlineAuthenticationRequestSuccessModel.relyingPartyRegistration`:
     * the combined two-layer trust verdict for the verifier, resolved by the
     * feature interactor via `WalletKitController.getVerifierRegistration`.
     * `None` only on the failure/not-secured arms (the failed-request verdict
     * travels separately through `registrationForFailedRequest()`).
     */
    public let relyingPartyRegistration: ?RelyingPartyRegistration
    /**
     * The request was blocked because the other side could not be verified
     * (iOS `.notSecuredRequest`). A third outcome next to success and failure:
     * the screen shows a blocking sheet, not a retryable error, so it must stay
     * distinguishable from a plain `failure`.
     *
     * Note this is *not* the same as `isTrusted == false` on a successful
     * request: that one only downgrades the relying-party badge while the flow
     * continues, mirroring iOS.
     */
    public let isNotSecuredRequest: Bool

    private init(
        isSuccess: Bool,
        relyingParty: String,
        dataRequestInfo: String,
        isTrusted: Bool,
        combinations: ArrayList<ArrayList<RequestDataSection>>,
        errorMessage: String,
        isNotSecuredRequest!: Bool = false,
        relyingPartyRegistration!: ?RelyingPartyRegistration = None
    ) {
        this.isSuccess = isSuccess
        this.relyingParty = relyingParty
        this.dataRequestInfo = dataRequestInfo
        this.isTrusted = isTrusted
        this.combinations = combinations
        this.errorMessage = errorMessage
        this.isNotSecuredRequest = isNotSecuredRequest
        this.relyingPartyRegistration = relyingPartyRegistration
    }

    /** Convenience: the first combination's sections (backward-compat with callers
     *  that predate combinations; also what single-combination requests disclose). */
    public prop sections: ArrayList<RequestDataSection> {
        get() {
            if (this.combinations.size > 0) { return this.combinations[0] }
            return ArrayList<RequestDataSection>()
        }
    }

    public static func success(
        relyingParty!: String,
        dataRequestInfo!: String,
        isTrusted!: Bool,
        combinations!: ArrayList<ArrayList<RequestDataSection>>,
        relyingPartyRegistration!: ?RelyingPartyRegistration = None
    ): RequestReceivedModel {
        RequestReceivedModel(
            true, relyingParty, dataRequestInfo, isTrusted, combinations, "",
            relyingPartyRegistration: relyingPartyRegistration
        )
    }

    public static func failure(message: String): RequestReceivedModel {
        RequestReceivedModel(false, "", "", false, ArrayList<ArrayList<RequestDataSection>>(), message)
    }

    public static func notSecuredRequest(): RequestReceivedModel {
        RequestReceivedModel(
            false, "", "", false, ArrayList<ArrayList<RequestDataSection>>(), "",
            isNotSecuredRequest: true
        )
    }
}

/** A selected cell's coordinates back into the engine response map. */
public class ClaimRef {
    public let docId: String
    public let namespace: String
    public let elementIdentifier: String
    public let elementPath: Array<String>
    public let intentToRetain: Bool

    public init(
        docId!: String,
        namespace!: String,
        elementIdentifier!: String,
        elementPath!: Array<String> = Array<String>(),
        intentToRetain!: Bool = false
    ) {
        this.docId = docId
        this.namespace = namespace
        this.elementIdentifier = elementIdentifier
        this.elementPath = if (elementPath.isEmpty()) { [elementIdentifier] } else { elementPath }
        this.intentToRetain = intentToRetain
    }
}

/**
 * Builds the selectable request sections from a PresentationRequest. Each
 * requested doc id is a stored document; its claims become the disclosable
 * rows. The (groupId → ClaimRef) index is recorded so a later selection can be
 * reverse-mapped to a RequestItem (iOS `prepareRequest`). Revoked documents are
 * filtered (iOS `fetchRevokedDocuments` exclusion).
 *
 * `overaskedPaths` (iOS `toUiModels(overaskedPaths:)`, docId → leaf claim
 * paths not covered by the relying party's registration certificate) marks
 * the matching rows `isOverasked`; absent/empty means no marking.
 */
public func buildRequestReceivedModel(
    request: PresentationRequest,
    walletController: WalletKitController,
    claimIndex: HashMap<String, ClaimRef>,
    overaskedPaths!: ?HashMap<String, Array<Array<String>>> = None,
    claimsAreSelectable!: Bool = false
): RequestReceivedModel {
    claimIndex.clear()
    let revoked = ArrayList<String>()
    try {
        for (r in walletController.fetchRevokedDocuments()) { revoked.add(r) }
    } catch (_: Exception) {}

    // iOS maps each of `itemSets` (the combinations) through toUiModels
    // (PresentationInteractor.onRequestReceived: itemSets.map { toUiModels(…) }).
    // Fall back to treating the flat `items` as one combination when the request
    // carries no sets (locally constructed requests/tests).
    var sets = request.itemSets
    if (sets.size == 0) {
        sets = [request.items]
    }

    let combinations = ArrayList<ArrayList<RequestDataSection>>()
    for (set in sets) {
        let sections = ArrayList<RequestDataSection>()
        for (element in set) {
            let docId = element.id
            var skip = false
            for (rv in revoked) {
                if (rv == docId) { skip = true }
            }
            if (skip) { continue }

            match (walletController.fetchDocument(docId)) {
                case None => ()
                case Some(doc) =>
                    let cells = ArrayList<RequestDataCell>()
                    let overaskedForDoc: ?Array<Array<String>> = match (overaskedPaths) {
                        case Some(map) => map.get(doc.id)
                        case None => None
                    }
                    if (element.requestedClaims.isEmpty()) {
                        // Backward-compatible fallback for locally constructed
                        // requests/tests and the spec's request-all form.
                        appendRequestClaimCells(
                            doc.id, doc.docType, doc.docClaims, cells, claimIndex,
                            overaskedForDoc, claimsAreSelectable
                        )
                    } else {
                        appendRequestedClaimCells(
                            doc.id, element.requestedClaims, doc.docClaims,
                            cells, claimIndex, overaskedForDoc, claimsAreSelectable
                        )
                    }
                    if (cells.size > 0) {
                        let sectionTitle = doc.displayName ?? doc.docType
                        sections.add(RequestDataSection(id: doc.id, title: sectionTitle, cells: cells))
                    }
            }
        }
        // iOS keeps the .map cardinality — an empty set stays an (empty)
        // combination rather than being dropped.
        combinations.add(sections)
    }

    // iOS 95b71766 removed the `!combinations.isEmpty` guard: an unsatisfiable
    // request (no matching document, or everything revoked) still succeeds into
    // the request screen with empty sections, so the user sees WHO asked.
    return RequestReceivedModel.success(
        relyingParty: request.relyingParty,
        dataRequestInfo: request.dataRequestInfo,
        isTrusted: request.isTrusted,
        combinations: combinations
    )
}

/** Builds rows only for claims present in the verifier request. This mirrors
 * iOS `MsoMdocElements` / `SdJwtElements`; absent requested claims remain
 * visible but disabled, while optional available claims can be deselected. */
func appendRequestedClaimCells(
    docId: String,
    requestedClaims: Array<RequestedClaim>,
    storedClaims: Array<DocClaim>,
    out: ArrayList<RequestDataCell>,
    claimIndex: HashMap<String, ClaimRef>,
    overasked: ?Array<Array<String>>,
    claimsAreSelectable: Bool
): Unit {
    for (requested in requestedClaims) {
        let stored = findRequestedClaim(storedClaims, requested)
        let available = requested.isAvailable && stored.isSome()
        let title = match (stored) {
            case Some(claim) => claim.displayName ?? claim.name
            case None => requested.elementIdentifier
        }
        let value = match (stored) {
            case Some(claim) => requestClaimDisplayValue(claim)
            case None => ""
        }
        let pathKey = joinRequestPath(requested.elementPath)
        let groupId = "request_${docId}_${requested.namespace}_${pathKey}"
        if (available) {
            claimIndex[groupId] = ClaimRef(
                docId: docId,
                namespace: requested.namespace,
                elementIdentifier: requested.elementIdentifier,
                elementPath: requested.elementPath,
                intentToRetain: requested.intentToRetain
            )
        }
        out.add(RequestDataCell(
            groupId: groupId,
            title: title,
            value: value,
            // iOS proximity parity: WalletKitController.parseDocClaim maps
            // every available claim to `.available(isRequired: false)`.
            // wallet-kit's mdoc schema-mandatory bit describes the credential
            // shape; it must not lock the holder's disclosure checkbox.
            isRequired: if (claimsAreSelectable) { false } else { !requested.isOptional },
            isAvailable: available,
            isOverasked: isRequestedPathOverasked(requested, overasked)
        ))
    }
}

func findRequestedClaim(claims: Array<DocClaim>, requested: RequestedClaim): ?DocClaim {
    // mdoc claims are commonly flat and namespace-qualified.
    if (!requested.namespace.isEmpty()) {
        for (claim in claims) {
            if ((claim.namespace ?? "") == requested.namespace && claim.name == requested.elementIdentifier) {
                return Some(claim)
            }
        }
    }
    return findClaimByPath(claims, requested.elementPath, 0)
}

func findClaimByPath(claims: Array<DocClaim>, path: Array<String>, offset: Int64): ?DocClaim {
    if (offset >= path.size) { return None }
    for (claim in claims) {
        if (claim.name != path[offset]) { continue }
        if (offset == path.size - 1) { return Some(claim) }
        match (claim.children) {
            case Some(children) =>
                let nested = findClaimByPath(children, path, offset + 1)
                if (nested.isSome()) { return nested }
            case None => ()
        }
    }
    return None
}

func joinRequestPath(path: Array<String>): String {
    var result = ""
    for (part in path) {
        if (!result.isEmpty()) { result += "." }
        result += part
    }
    return result
}

func isRequestedPathOverasked(
    requested: RequestedClaim,
    overasked: ?Array<Array<String>>
): Bool {
    let leaf = if (requested.namespace.isEmpty()) {
        requested.elementPath
    } else {
        let result = ArrayList<String>()
        result.add(requested.namespace)
        for (part in requested.elementPath) { result.add(part) }
        result.toArray()
    }
    return containsRequestPath(overasked, leaf)
}

func containsRequestPath(overasked: ?Array<Array<String>>, leaf: Array<String>): Bool {
    let paths = match (overasked) {
        case Some(p) => p
        case None => return false
    }
    for (candidate in paths) {
        if (candidate.size != leaf.size) { continue }
        var equal = true
        var i = 0
        while (i < candidate.size) {
            if (candidate[i] != leaf[i]) { equal = false; break }
            i++
        }
        if (equal) { return true }
    }
    return false
}

/** Flattens a document's claims (recursing into structured children) into
 *  selectable rows, recording each row's response coordinates. `overasked`
 *  carries the doc's over-asked leaf paths (None = no marking).
 *  `claimsAreSelectable` = iOS toUiModels flag: proximity rows get checkboxes,
 *  presentation rows are read-only (whole combination disclosed). */
func appendRequestClaimCells(
    docId: String,
    docType: String,
    claims: Array<DocClaim>,
    out: ArrayList<RequestDataCell>,
    claimIndex: HashMap<String, ClaimRef>,
    overasked: ?Array<Array<String>>,
    claimsAreSelectable: Bool
): Unit {
    for (claim in claims) {
        match (claim.children) {
            case Some(children) where children.size > 0 =>
                appendRequestClaimCells(
                    docId, docType, children, out, claimIndex,
                    overasked, claimsAreSelectable
                )
            case _ =>
                let title = claim.displayName ?? claim.name
                let value = requestClaimDisplayValue(claim)
                let groupId = "request_${docId}_${claim.namespace ?? ""}_${claim.name}"
                claimIndex[groupId] = ClaimRef(
                    docId: docId,
                    namespace: claim.namespace ?? docId,
                    elementIdentifier: claim.name
                )
                out.add(
                    RequestDataCell(
                        groupId: groupId,
                        title: title,
                        value: value,
                        // ISO DeviceRequest has no `isOptional` bit. iOS only
                        // locks the mandatory fields of the two known mdoc
                        // types; other proximity claims stay selectable.
                        isRequired: if (claimsAreSelectable) {
                            false
                        } else {
                            isMandatoryPresentationClaim(docType, claim)
                        },
                        isAvailable: true,
                        hasCheckbox: claimsAreSelectable,
                        isOverasked: isClaimOverasked(claim, overasked)
                    )
                )
        }
    }
}

/** Mirrors iOS `MsoMdocElements.getMandatoryElementKeys(docType:ns:)`. */
public func isMandatoryPresentationClaim(docType: String, claim: DocClaim): Bool {
    let namespace = claim.namespace ?? ""
    if (docType == "eu.europa.ec.eudi.pid.1" && namespace == "eu.europa.ec.eudi.pid.1") {
        return stringInSet(claim.name, [
            "age_over_18", "family_name", "given_name", "birth_date",
            "birth_place", "nationality"
        ])
    }
    if (docType == "org.iso.18013.5.1.mDL" && namespace == "org.iso.18013.5.1") {
        return stringInSet(claim.name, [
            "family_name", "given_name", "birth_date", "issue_date",
            "expiry_date", "issuing_country", "issuing_authority",
            "document_number", "portrait", "driving_privileges",
            "un_distinguishing_sign"
        ])
    }
    return false
}

func stringInSet(value: String, values: Array<String>): Bool {
    for (candidate in values) {
        if (candidate == value) { return true }
    }
    return false
}

/** The leaf path used for over-asked matching: the claim's engine path where
 *  one was decoded, else namespace + element identifier (mdoc), else the bare
 *  element identifier (iOS `DocClaim` leaves always carry a ClaimPath; the
 *  stored-claim seam here may not). */
func requestClaimLeafPath(claim: DocClaim): Array<String> {
    if (claim.path.size > 0) {
        return claim.path
    }
    match (claim.namespace) {
        case Some(ns) => return [ns, claim.name]
        case None => return [claim.name]
    }
}

/** Whether one of the doc's over-asked leaf paths matches this claim
 *  (element-wise equality, iOS `overaskedPaths.contains(claimPath)`). */
func isClaimOverasked(claim: DocClaim, overasked: ?Array<Array<String>>): Bool {
    let paths = match (overasked) {
        case Some(p) => p
        case None => return false
    }
    let leaf = requestClaimLeafPath(claim)
    for (candidate in paths) {
        if (candidate.size != leaf.size) {
            continue
        }
        var allEqual = true
        var i = 0
        while (i < candidate.size) {
            if (candidate[i] != leaf[i]) {
                allEqual = false
                break
            }
            i++
        }
        if (allEqual) {
            return true
        }
    }
    return false
}

func requestClaimDisplayValue(claim: DocClaim): String {
    match (claim.dataValue.image) {
        case Some(_) => return requestImagePlaceholderText()
        case None => ()
    }
    return claim.stringValue
}

/** Reverse-maps the selected cells into a RequestItemConvertible
 *  (docId → namespace → [RequestItem]) — iOS `requestItems.prepareRequest()`. */
public func buildRequestConvertible(
    selected: ArrayList<RequestDataCell>,
    claimIndex: HashMap<String, ClaimRef>
): RequestItemConvertible {
    let dictionary: RequestConvertibleItems = HashMap<String, HashMap<String, Array<RequestItem>>>()
    let acc = HashMap<String, HashMap<String, ArrayList<RequestItem>>>()

    for (cell in selected) {
        match (claimIndex.get(cell.groupId)) {
            case None => ()
            case Some(ref) =>
                if (!acc.contains(ref.docId)) {
                    acc[ref.docId] = HashMap<String, ArrayList<RequestItem>>()
                }
                let nsMap = acc[ref.docId]
                if (!nsMap.contains(ref.namespace)) {
                    nsMap[ref.namespace] = ArrayList<RequestItem>()
                }
                nsMap[ref.namespace].add(RequestItem(
                    elementIdentifier: ref.elementIdentifier,
                    intentToRetain: Some(ref.intentToRetain),
                    elementPath: ref.elementPath
                ))
        }
    }

    for ((docId, nsMap) in acc) {
        let outNs = HashMap<String, Array<RequestItem>>()
        for ((namespace, items) in nsMap) {
            outNs[namespace] = items.toArray()
        }
        dictionary[docId] = outNs
    }
    return RequestItemsWrapper(dictionary)
}

func requestImagePlaceholderText(): String { "Image" }
