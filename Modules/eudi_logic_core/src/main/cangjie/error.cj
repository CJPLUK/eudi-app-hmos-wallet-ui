/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Error/WalletCoreError.swift +
 * Coordinator/Model/PresentationSessionError.swift.
 */
package eudi_logic_core

import eudi_logic_resources.LocalizableStringKey
import eudi_logic_resources.LocalizableManager

/**
 * Mirrors iOS `WalletCoreError: LocalizedError, Equatable`.
 *
 * Modelled as an Exception (so controller methods that `throw` it match the iOS
 * `throws` surface) while keeping the Equatable comparison the iOS source relied
 * on via `case` identity + payload comparison.
 */
public class WalletCoreError <: Exception {
    public let kind: WalletCoreErrorKind

    public init(kind: WalletCoreErrorKind) {
        super(kind.errorDescription())
        this.kind = kind
    }

    public prop errorDescription: String {
        get() { this.kind.errorDescription() }
    }

    // Factory helpers mirroring the iOS enum cases.
    public static func unableFetchDocuments(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.unableFetchDocuments) }
    public static func unableFetchDocument(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.unableFetchDocument) }
    public static func missingPid(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.missingPid) }
    public static func unableToIssueAndStore(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.unableToIssueAndStore) }
    public static func missingMetadata(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.missingMetadata) }
    public static func transactionCodeFormat(args: Array<String>): WalletCoreError { WalletCoreError(WalletCoreErrorKind.transactionCodeFormat(args)) }
    public static func unableToPresentAndShare(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.unableToPresentAndShare) }
    public static func unableToFetchTransactionLog(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.unableToFetchTransactionLog) }
    public static func issuerNotTrusted(): WalletCoreError { WalletCoreError(WalletCoreErrorKind.issuerNotTrusted) }
}

/** The discriminant of WalletCoreError, mirroring the iOS enum cases 1:1. */
public enum WalletCoreErrorKind <: Equatable<WalletCoreErrorKind> {
    | unableFetchDocuments
    | unableFetchDocument
    | missingPid
    | unableToIssueAndStore
    | missingMetadata
    | transactionCodeFormat(Array<String>)
    | unableToPresentAndShare
    | unableToFetchTransactionLog
    /**
     * App-level stand-in for a trust failure, used by issuance / presentation
     * fakes so UI wiring can be tested without driving the engine.
     *
     * The production classifier also matches the engine type iOS uses:
     * `WalletError.code == TrustError`. This kind stays so existing fakes
     * keep working; it is not a replacement for the engine signal.
     */
    | issuerNotTrusted

    /** Mirrors iOS `errorDescription` resolution through localization keys. */
    public func errorDescription(): String {
        match (this) {
            case unableFetchDocuments => LocalizableManager.get(LocalizableStringKey.errorUnableFetchDocuments)
            case unableFetchDocument => LocalizableManager.get(LocalizableStringKey.errorUnableFetchDocument)
            case missingPid => LocalizableManager.get(LocalizableStringKey.missingPid)
            case unableToIssueAndStore => LocalizableManager.get(LocalizableStringKey.unableToIssueAndStore)
            case missingMetadata => LocalizableManager.get(LocalizableStringKey.missingMetadata)
            case transactionCodeFormat(args) => LocalizableManager.get(LocalizableStringKey.transactionCodeFormatError(args))
            case unableToPresentAndShare => LocalizableManager.get(LocalizableStringKey.unableToPresentAndShare)
            case unableToFetchTransactionLog => LocalizableManager.get(LocalizableStringKey.errorFetchTransactionLog)
            case issuerNotTrusted => LocalizableManager.get(LocalizableStringKey.issuanceBlockedMessage)
        }
    }

    public operator func ==(o: WalletCoreErrorKind): Bool {
        match ((this, o)) {
            case (unableFetchDocuments, unableFetchDocuments) => true
            case (unableFetchDocument, unableFetchDocument) => true
            case (missingPid, missingPid) => true
            case (unableToIssueAndStore, unableToIssueAndStore) => true
            case (missingMetadata, missingMetadata) => true
            case (transactionCodeFormat(a), transactionCodeFormat(b)) => arraysEqual(a, b)
            case (unableToPresentAndShare, unableToPresentAndShare) => true
            case (unableToFetchTransactionLog, unableToFetchTransactionLog) => true
            case (issuerNotTrusted, issuerNotTrusted) => true
            case _ => false
        }
    }
    public operator func !=(o: WalletCoreErrorKind): Bool { !(this == o) }
}

/** Mirrors iOS `PresentationSessionError`. */
public enum PresentationSessionError <: Equatable<PresentationSessionError> {
    | qrGeneration
    | noDocumentFoundForRequest
    | conversionToRequestItemModel
    | invalidState
    | failedToParseRemoteURL

    public operator func ==(o: PresentationSessionError): Bool {
        match ((this, o)) {
            case (qrGeneration, qrGeneration) => true
            case (noDocumentFoundForRequest, noDocumentFoundForRequest) => true
            case (conversionToRequestItemModel, conversionToRequestItemModel) => true
            case (invalidState, invalidState) => true
            case (failedToParseRemoteURL, failedToParseRemoteURL) => true
            case _ => false
        }
    }
    public operator func !=(o: PresentationSessionError): Bool { !(this == o) }
}

/** Exception wrapper so PresentationSessionError can be thrown. */
public class PresentationSessionException <: Exception {
    public let error: PresentationSessionError
    public init(error: PresentationSessionError) {
        super("PresentationSessionError")
        this.error = error
    }
}
