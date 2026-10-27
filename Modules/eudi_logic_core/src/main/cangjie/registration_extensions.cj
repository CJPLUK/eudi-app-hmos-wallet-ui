/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 *
 * Port of iOS logic-core/Sources/Extension/PolicyPurpose+Localized.swift,
 * PresentationPolicyViolation+Overasking.swift and the presenter-name half of
 * TransactionLog+Extensions.swift (registration certificate trust layer).
 *
 * Cangjie has no type extensions, so the iOS extension members become top-level
 * functions over the kit types. iOS `ClaimPath` is represented app-side as
 * `Array<String>` (each element rendered like `ClaimPathElement.description()`:
 * a claim name, a decimal array index, or "null" for the all-array-elements
 * wildcard — the same rendering the wallet-kit uses when it flattens paths).
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.PolicyPurpose
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.PresentationPolicyViolation
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.PresentationFailureReason
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.DisclosedDocumentSet
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.DocElements as WKDocElements
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.SdJwtElement as WKSdJwtElement
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DocClaim as WKDocClaim
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vp.entity.dcql.ClaimPath
import ohos_app_cangjie_eudi_cjx509.x509.core.Cert

// ─────────────────────────────────────────────────────────────────────────────
// Extension/PolicyPurpose+Localized.swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `[PolicyPurpose].localizedValue`: the purpose text whose language
 * subtag matches the current system language, else the first entry, else None.
 */
public func localizedPolicyPurposeValue(purposes: ?Array<PolicyPurpose>): ?String {
    match (purposes) {
        case None => return None
        case Some(list) =>
            if (list.size == 0) { return None }
            let language = languageSubtag(systemLanguageCode())
            for (p in list) {
                if (languageSubtag(p.lang) == language) { return Some(p.value) }
            }
            return Some(list[0].value)
    }
}

/** Mirrors the private `String.languageSubtag` — text before the first "-", lowercased. */
func languageSubtag(lang: String): String {
    match (indexOf(lang, "-")) {
        case Some(idx) => lang[0..idx].toAsciiLower()
        case None => lang.toAsciiLower()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension/PresentationPolicyViolation+Overasking.swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `[PresentationPolicyViolation].toOveraskedClaims()`: keep only
 * `.overAskedClaims` reasons; non-empty claim paths yield one OveraskedClaim
 * per ClaimPath, a nil/empty path list yields one whole-attestation claim
 * (`path: None`). De-duplicated preserving order.
 */
public func toOveraskedClaims(violations: Array<PresentationPolicyViolation>): Array<OveraskedClaim> {
    let result = ArrayList<OveraskedClaim>()
    for (violation in violations) {
        match (violation.reason) {
            case PresentationFailureReason.OverAskedClaims(docType, claims) =>
                match (claims) {
                    case Some(paths) where paths.size > 0 =>
                        for (path in paths) {
                            appendUniqueOveraskedClaim(
                                result,
                                OveraskedClaim(attestationType: docType, path: Some(claimPathToStrings(path)))
                            )
                        }
                    case _ =>
                        appendUniqueOveraskedClaim(
                            result,
                            OveraskedClaim(attestationType: docType, path: None)
                        )
                }
            case _ => ()
        }
    }
    return result.toArray()
}

/**
 * Kit `ClaimPath` → the app-side `Array<String>` path representation: each
 * element rendered as `ClaimPathElement.description()` (claim name, decimal
 * array index, or "null" for the all-array-elements wildcard).
 */
func claimPathToStrings(path: ClaimPath): Array<String> {
    let out = ArrayList<String>()
    for (element in path.value) {
        out.add(element.description())
    }
    return out.toArray()
}

/**
 * Array<String> equivalent of kit `ClaimPath.contains2(_:)` — wildcard-aware
 * element-wise containment over the common (zip-truncated) prefix, so an
 * ancestor policy path contains all its descendants. A "null" policy element
 * (the all-array-elements wildcard) contains any array index and "null"
 * itself, never a claim name — mirroring `ClaimPathElement.contains`.
 */
func claimPathStringsContains2(policy: Array<String>, leaf: Array<String>): Bool {
    let n = if (policy.size < leaf.size) { policy.size } else { leaf.size }
    var i = 0
    while (i < n) {
        if (!claimPathElementStringContains(policy[i], leaf[i])) { return false }
        i++
    }
    return true
}

func claimPathElementStringContains(policy: String, leaf: String): Bool {
    if (policy == leaf) { return true }
    if (policy == "null") {
        return leaf == "null" || isAllDigits(leaf)
    }
    return false
}

func isAllDigits(s: String): Bool {
    if (s.isEmpty()) { return false }
    for (b in s.toArray()) {
        if (b < b'0' || b > b'9') { return false }
    }
    return true
}

/**
 * Mirrors iOS `[DocElements].overaskedPaths(from:)` over the session's
 * `disclosedDocumentSets`: builds docId → over-asked leaf claim paths, in the
 * exact path shape eudi_feature_common's request bridge matches against
 * (mdoc: [namespace, elementIdentifier]; sd-jwt: the element path).
 *
 * Per element: any applicable whole-attestation claim (path None) marks ALL
 * leaves; otherwise a leaf is marked when some applicable claim path
 * contains2-matches it (an ancestor path marks all its leaves). Elements with
 * no marked leaves are omitted; leaf sets are de-duplicated preserving order
 * (iOS uses a Set).
 */
public func overaskedPathsByDocId(
    sets: Array<DisclosedDocumentSet>,
    claims: Array<OveraskedClaim>
): HashMap<String, Array<Array<String>>> {
    let result = HashMap<String, Array<Array<String>>>()
    if (claims.size == 0) { return result }

    for (set in sets) {
        for (element in set.docElements) {
            let attestationType = element.docTypeOrVct()

            let applicable = ArrayList<OveraskedClaim>()
            for (claim in claims) {
                if (claim.appliesTo(attestationType)) { applicable.add(claim) }
            }
            if (applicable.size == 0) { continue }

            let leafPaths = elementLeafPaths(element)

            var wholeAttestation = false
            for (claim in applicable) {
                if (claim.path.isNone()) { wholeAttestation = true }
            }

            let overasked = ArrayList<Array<String>>()
            for (leaf in leafPaths) {
                var marked = wholeAttestation
                if (!marked) {
                    for (claim in applicable) {
                        match (claim.path) {
                            case Some(policy) =>
                                if (claimPathStringsContains2(policy, leaf)) { marked = true }
                            case None => ()
                        }
                    }
                }
                if (marked) { appendUniquePath(overasked, leaf) }
            }

            if (overasked.size > 0) {
                result[element.docId()] = overasked.toArray()
            }
        }
    }
    return result
}

/**
 * Leaf claim paths of one kit DocElements entry. Where the element carries a
 * decoded DocClaim, its path/children tree is walked (iOS
 * `DocClaim.leafPaths()`); the transport in this port pre-selects elements
 * with `docClaim` None, so the structural fallback derives the same shape:
 * mdoc → [namespace, elementIdentifier]; sd-jwt → the element path, recursing
 * into nested elements.
 */
func elementLeafPaths(element: WKDocElements): Array<Array<String>> {
    let out = ArrayList<Array<String>>()
    match (element) {
        case MsoMdoc(doc) =>
            for (nse in doc.nameSpacedElements) {
                for (el in nse.elements) {
                    match (el.docClaim) {
                        case Some(claim) => appendDocClaimLeafPaths(claim, out)
                        case None => out.add([nse.nameSpace, el.elementIdentifier])
                    }
                }
            }
        case SdJwt(doc) =>
            for (el in doc.sdJwtElements) {
                appendSdJwtLeafPaths(el, out)
            }
    }
    return out.toArray()
}

/** Mirrors the private iOS `DocClaim.leafPaths()` recursion. */
func appendDocClaimLeafPaths(claim: WKDocClaim, out: ArrayList<Array<String>>): Unit {
    match (claim.children) {
        case Some(children) where children.size > 0 =>
            for (child in children) { appendDocClaimLeafPaths(child, out) }
        case _ => out.add(claim.path.toArray())
    }
}

func appendSdJwtLeafPaths(element: WKSdJwtElement, out: ArrayList<Array<String>>): Unit {
    match (element.docClaim) {
        case Some(claim) =>
            appendDocClaimLeafPaths(claim, out)
            return
        case None => ()
    }
    match (element.nestedElements) {
        case Some(nested) where nested.size > 0 =>
            for (child in nested) { appendSdJwtLeafPaths(child, out) }
        case _ => out.add(element.elementPath)
    }
}

func appendUniquePath(list: ArrayList<Array<String>>, path: Array<String>): Unit {
    for (existing in list) {
        if (pathEq(existing, path)) { return }
    }
    list.add(path)
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension/TransactionLog+Extensions.swift — withPresenterName()
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors the presenter-name half of iOS `TransactionLog.withPresenterName()`:
 * parse the head (leaf) of the reader/relying-party DER certificate chain and
 * read its subject CN (iOS `SecCertificateCopySubjectSummary`). Returns None
 * when the chain is absent/empty, the DER fails to parse, or the CN is empty —
 * callers then keep the existing relying-party display name.
 */
public func presenterNameFromCertificateChain(chain: ?Array<Array<UInt8>>): ?String {
    let leafDer = match (chain) {
        case Some(certs) where certs.size > 0 => certs[0]
        case _ => return None
    }
    try {
        return subjectCommonName(Cert.fromDer(leafDer).subject)
    } catch (_: Exception) {
        return None
    }
}

/**
 * First CN value of an X.509 DN string. The stdx DN rendering emits
 * "key=value" components separated by ',' (or '/'); the key is matched
 * case-insensitively ("CN" / the dotted OID spellings).
 */
func subjectCommonName(dn: String): ?String {
    for (component in splitDnString(dn)) {
        match (indexOf(component, "=")) {
            case Some(idx) =>
                let key = trimSpaces(component[0..idx]).toAsciiLower()
                let value = trimSpaces(component[(idx + 1)..component.size])
                if ((key == "cn" || key == "commonname" || key == "2.5.4.3" || key == "oid.2.5.4.3") && !value.isEmpty()) {
                    return Some(value)
                }
            case None => ()
        }
    }
    return None
}

func splitDnString(dn: String): Array<String> {
    let out = ArrayList<String>()
    let bytes = dn.toArray()
    var start: Int64 = 0
    var i: Int64 = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == b',' || b == b'/') {
            if (i > start) { out.add(String.fromUtf8(bytes[start..i])) }
            start = i + 1
        }
        i++
    }
    if (i > start) { out.add(String.fromUtf8(bytes[start..i])) }
    return out.toArray()
}

func trimSpaces(s: String): String {
    let bytes = s.toArray()
    var start: Int64 = 0
    var end: Int64 = bytes.size
    while (start < end && bytes[start] == b' ') { start++ }
    while (end > start && bytes[end - 1] == b' ') { end-- }
    if (start == 0 && end == bytes.size) { return s }
    return String.fromUtf8(bytes[start..end])
}
