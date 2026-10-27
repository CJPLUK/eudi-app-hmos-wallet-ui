/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-resources module
 * (Localizable/LocalizableStringKey.swift + Manager/LocalizableManager.swift) to
 * Cangjie for the EUDI HarmonyOS wallet.
 *
 * The English default literals come from Resources/Localizable.xcstrings (the iOS
 * source of truth). Parameterized keys substitute their `%@` format markers with the
 * supplied arguments, left to right. An unmapped/dynamic key returns its raw value.
 */
package eudi_logic_resources

/**
 * Every localization key of the wallet, ported 1:1 from Swift `LocalizableStringKey`.
 * Parameterized cases carry their substitution arguments as `Array<String>`,
 * matching the Swift `case foo([String])` form.
 */
public enum LocalizableStringKey {
    | custom(String)
    | space
    | search
    | genericErrorTitle
    | genericErrorDesc
    | biometryOpenSettings
    | biometryConfirmRequest
    | invalidQuickPin
    | tryAgain
    | shareButton
    | cancelButton
    | requestDataInfoNotice
    | requestDataTitle(Array<String>)
    | requestCombinationTitle(Array<String>)
    | documentAdded
    | okButton
    | success
    | successfullySharedFollowingInformation
    | incompleteRequestDataSelection
    | addDoc
    | filters
    | sortByIssuedDateSectionTitle
    | showResults
    | welcomeBack(Array<String>)
    | pleaseWait
    | requestDataShareQuickPinCaption
    | requestDataShareBiometryCaption
    | addDocumentTitle
    | addDocumentSubtitle
    | addDocumentRequest
    | proximityConnectivityCaption
    | unavailableField
    | changeQuickPinOption
    | quickPinSetTitle
    | quickPinEnterPin
    | quickPinNavigationEnterPin
    | quickPinConfirmPin
    | quickPinSetCaptionOne
    | quickPinSetCaptionTwo
    | quickPinNextButton
    | quickPinConfirmButton
    | quickPinSetSuccess
    | quickPinSetNoActivationSuccess
    | loginTitle
    | loginWithBiometrics
    | loginCaptionQuickPinOnly
    | loginCaption
    | quickPinSetSuccessButton
    | quickPinSetNoActivationSuccessButton
    | quickPinDoNotMatch
    | quickPinLockedOut(Array<String>)
    | quickPinUpdateTitle
    | quickPinUpdateCaptionOne
    | quickPinUpdateCaptionTwo
    | quickPinUpdateCaptionThree
    | quickPinUpdateSuccess
    | quickPinUpdateSuccessButton
    | quickPinUpdateCancellationTitle
    | quickPinUpdateCancellationCaption
    | quickPinUpdateCancellationContinue
    | successTitlePunctuated
    | issuerWantWalletAddition
    | unknownVerifier
    | unknownIssuer
    | genericIssuer
    | filterByIssuer
    | yes
    | no
    | scanQrCode
    | signDocument
    | signDocumentSubtitle
    | selectDocument
    | validUntil(Array<String>)
    | bleDisabledModalTitle
    | bleDisabledModalCaption
    | bleDisabledModalButton
    | requestDataNoDocument
    | issuanceDetailsDeletionTitle(Array<String>)
    | deleteDocument
    | removeFromWallet
    | issuanceDetailsDeletionCaption(Array<String>)
    | errorUnableFetchDocuments
    | errorUnableFetchDocument
    | scannerQrTitleIssuing
    | scannerQrTitlePresentation
    | scannerQrCaptionIssuing
    | scannerQrCaptionPresentation
    | scannerQrTitle
    | scannerQrCaption
    | cameraError
    | missingPid
    | requestCredentialOfferTitle(Array<String>)
    | requestCredentialOfferNoDocument
    | unableToIssueAndStore
    | missingMetadata
    | issueButton
    | issuanceCodeTitle(Array<String>)
    | issuanceCodeCaption(Array<String>)
    | transactionCodeFormatError(Array<String>)
    | inProgress
    | scopedIssuanceSuccessDeferredCaption
    | scopedIssuanceSuccessDeferredCaptionDocName(Array<String>)
    | scopedIssuanceSuccessDeferredCaptionDocNameAndIssuer(Array<String>)
    | issuanceSuccessDeferredCaption(Array<String>)
    | pending
    | issuanceFailed
    | issuanceBlockedTitle
    | issuanceBlockedMessage
    | presentationBlockedTitle
    | presentationBlockedMessage
    | relyingPartyId(Array<String>)
    | privacyPolicy
    | intendedUse
    | understandRisksAgree
    | relyingPartyNotVerifiedWarning
    | relyingPartyOveraskedWarning
    | notRegisteredData
    | issuanceRegistrationBlockedTitle
    | issuanceRegistrationBlockedMessage
    | issuanceRequestTitle
    | validateIssuerRegistration
    | restartRequiredTitle
    | restartRequiredMessage
    | continueButton
    | deferredDocumentsIssuedModalTitle
    | defferedDocumentsIssuedModalCaption
    | retrieveLogs
    | qrScanInformativeText
    | unableToPresentAndShare
    | itemNotFoundInStorage
    | itemsNotFoundInStorage
    | home
    | documents
    | historyTitle
    | authenticateAuthoriseTransactions
    | homeScreenAuthenticateDescription
    | electronicallySignDigitalDocuments
    | learnMore
    | chooseFromList
    | chooseFromListTitle
    | addDocumentsToWallet
    | details
    | dataSharingRequest
    | dataShared
    | doneButton
    | dataSharingTitle
    | close
    | reset
    | all
    | descending
    | ascending
    | trustedRelyingParty
    | trustedRelyingPartyDescription
    | alertAccessOnlineServices
    | alertAccessOnlineServicesMessage
    | alertSignDocumentsSafely
    | alertSignDocumentsSafelyMessage
    | authenticate
    | inPerson
    | online
    | savedToFavorites
    | succesfullyAddedFollowingToWallet
    | removedFromFavorites
    | savedToFavoritesMessage
    | removedFromFavoritesMessages
    | viewDetails
    | requestsTheFollowing
    | walletIsSecured
    | noResults
    | noResultsDocumentsDescription
    | noResultsTransactionsDescription
    | proximityConnectionBleDescription
    | selectExpiryPeriod
    | filterByState
    | sortBy
    | deleteDocumentConfirmDialog
    | defaultLabel
    | valid
    | revoke
    | expired
    | dateIssued
    | expiryDate
    | nextSevenDays
    | nextThirtyDays
    | beyondThiryDays
    | beforeToday
    | issuanceRequest
    | myEuWallet
    | categoryGovernment
    | categoryHealth
    | categoryEducation
    | categoryFinance
    | categoryRetail
    | categoryOther
    | categorySocialSecurity
    | categoryTravel
    | changelog
    | orderBy
    | filterByCategory
    | searchDocuments
    | searchTransactions
    | filterByStatus
    | completed
    | failed
    | filterByDate
    | startDate
    | endDate
    | resetDates
    | relyingParty
    | signedDocuments
    | transactionInformation
    | transactionDetailsDataShare
    | transactionDetailsDataSigned
    | transactionDetailsScreenCardDateLabel
    | transactionDetailsCompleted
    | or
    | today
    | thisWeek
    | unknownDate
    | minutesAgo(Array<String>)
    | minuteAgo(Array<String>)
    | transactionDate
    | filterByType
    | presentation
    | signing
    | issuance
    | deletion
    | withoutRelyingName
    | errorFetchTransactionLog
    | incomplete
    | justNow
    | revoked
    | revokedModalTitle
    | revokedModalDescription
    | transactionDetailsRequestDeletionMessage
    | transactionDetailsRequestDeletionButton
    | transactionDetailsReportTransactionMessage
    | transactionDetailsReportTransactionButton
    | settings
    | documentDetailsDocumentCredentialsText(Array<String>)
    | documentDetailsDocumentCredentialsExpandedTextSubtitle
    | documentsListCredentialsUsageText(Array<String>)
    | expandableDocumentCredentialsIssueButton
    | issuanceAddDocumentNoOptions
    | unknown
    | pidCombined
    | documentData
    | documentDetailsShow
    | documentDetailsHide
    | issuanceSuccessHeaderDescription
    | documentDetailsReIssueButton
    | documentDetailsRemoveButton
    | documentDetailsExpiresOn(Array<String>)
    | documentDetailsExpiredOn(Array<String>)
    | documentDetailsIssuedOn(Array<String>)
    | documentDetailsRevokedDocument
    | documentDetailsIssuerCardIssuedMessageText
    | documentDetailsIssuerCardRevokedMessageText
    | documentDetailsIssuerCardExpiredMessageText
    | documentDetailsIssuerCardIssuedActionButtonText
    | batchIssuanceCounter
    | documentProviderExtensionAcceptButton
    | documentProviderExtensionRejectButton
    | enterYourPin
}

/**
 * Resolves a `LocalizableStringKey` to its English string. Mirrors Swift
 * `LocalizableManager.get(with:)`. Missing keys never crash; a `dynamic`/`custom`
 * key returns its raw value. `substitute` replaces `%@` format markers in order.
 */
public class LocalizableManager {
    private static func resolve(key: LocalizableStringKey): String {
        match (key) {
            case custom(literal) => literal
            case space => " "
            case search => "Search"
            case genericErrorTitle => "Houston we have a problem!"
            case genericErrorDesc => "If the issue persists, please contact customer support"
            case biometryOpenSettings => "Go to settings"
            case biometryConfirmRequest => "Confirm request"
            case invalidQuickPin => "Invalid pin"
            case tryAgain => "Try again"
            case shareButton => "Share"
            case cancelButton => "Cancel"
            case requestDataInfoNotice => "Why we need your data?"
            case requestDataTitle(args) => LocalizableManager.substitute("%@ requests the following", args)
            case requestCombinationTitle(args) => LocalizableManager.substitute("Option %@ of %@", args)
            case documentAdded => "Add Document"
            case okButton => "OK"
            case success => "Success"
            case successfullySharedFollowingInformation => "You successfully shared the following information with"
            case incompleteRequestDataSelection => "Your selection of data to be shared may impact the service"
            case addDoc => "Add doc"
            case filters => "Filter by"
            case sortByIssuedDateSectionTitle => "SORT BY ISSUED DATE"
            case showResults => "Show Results"
            case welcomeBack(args) => LocalizableManager.substitute("Welcome%@", args)
            case pleaseWait => "Please wait..."
            case requestDataShareQuickPinCaption => "Enter your PIN"
            case requestDataShareBiometryCaption => "Use your biometrics to share information"
            case addDocumentTitle => "Add document"
            case addDocumentSubtitle => "Select a document to add in your EUDI Wallet"
            case addDocumentRequest => "Add document request"
            case proximityConnectivityCaption => "Show this QR code to an interacting party within close proximity to authenticate your identity."
            case unavailableField => "Not available"
            case changeQuickPinOption => "Change pin"
            case quickPinSetTitle => "Welcome to your wallet"
            case quickPinEnterPin => "Enter a 6-digit PIN"
            case quickPinNavigationEnterPin => "Enter a PIN"
            case quickPinConfirmPin => "Confirm PIN"
            case quickPinSetCaptionOne => "Secure your wallet with a PIN code and connect to your National System."
            case quickPinSetCaptionTwo => "Re-type your PIN"
            case quickPinNextButton => "Proceed"
            case quickPinConfirmButton => "Confirm"
            case quickPinSetSuccess => "To activate your wallet, connect to your National System to add your Digital ID."
            case quickPinSetNoActivationSuccess => "Your Wallet is ready for use."
            case loginTitle => "Welcome back!"
            case loginWithBiometrics => "Authenticate with biometrics"
            case loginCaptionQuickPinOnly => "To access the EUDI Wallet you need to provide your PIN."
            case loginCaption => "To access the EUDI Wallet you need to provide your biometrics."
            case quickPinSetSuccessButton => "Add my Digital ID"
            case quickPinSetNoActivationSuccessButton => "Go to home"
            case quickPinDoNotMatch => "Pins do not match"
            case quickPinLockedOut(args) => LocalizableManager.substitute("You have entered the wrong PIN %@ times in a row.\nPlease wait %@ before trying again.", args)
            case quickPinUpdateTitle => "Change pin"
            case quickPinUpdateCaptionOne => "Type your current pin"
            case quickPinUpdateCaptionTwo => "Set a pin for future login"
            case quickPinUpdateCaptionThree => "Re-enter the pin"
            case quickPinUpdateSuccess => "You successfully set the pin"
            case quickPinUpdateSuccessButton => "Back to home"
            case quickPinUpdateCancellationTitle => "Cancel pin changing?"
            case quickPinUpdateCancellationCaption => "Cancel will redirect you back to the home without changing the pin"
            case quickPinUpdateCancellationContinue => "Continue"
            case successTitlePunctuated => "Success!"
            case issuerWantWalletAddition => "wants to add the following to your wallet:"
            case unknownVerifier => "Verifier"
            case unknownIssuer => "Issuer"
            case genericIssuer => "ISSUER DETAILS"
            case filterByIssuer => "Issuer"
            case yes => "yes"
            case no => "no"
            case scanQrCode => "Scan QR"
            case signDocument => "Sign document"
            case signDocumentSubtitle => "Select a document from your device to sign electronically."
            case selectDocument => "Select document"
            case validUntil(args) => LocalizableManager.substitute("Valid until %@", args)
            case bleDisabledModalTitle => "Enable bluetooth?"
            case bleDisabledModalCaption => "Enable bluetooth to share your information using the QR/TAP option"
            case bleDisabledModalButton => "Enable"
            case requestDataNoDocument => "The requested document is not available in your EUDI Wallet. Please contact the authorised issuer for further information."
            case issuanceDetailsDeletionTitle(args) => LocalizableManager.substitute("Delete %@?", args)
            case deleteDocument => "Delete document"
            case removeFromWallet => "Remove from wallet"
            case issuanceDetailsDeletionCaption(args) => LocalizableManager.substitute("You will not be able to use your %@ for future verifications", args)
            case errorUnableFetchDocuments => "Unable to fetch documents"
            case errorUnableFetchDocument => "Unable to fetch document"
            case scannerQrTitleIssuing => "Scan QR"
            case scannerQrTitlePresentation => "Authenticate my identity "
            case scannerQrCaptionIssuing => "Scan a QR code provided from an issuer to add a digital document to your wallet."
            case scannerQrCaptionPresentation => "Scan a QR code provided from an interacting party to authenticate your identity."
            case scannerQrTitle => "Scan QR Code"
            case scannerQrCaption => "Position the QR code within the frame to scan"
            case cameraError => "Camera permission not provided\nOpen App Settings"
            case missingPid => "Wallet needs to be activated first with a National ID"
            case requestCredentialOfferTitle(args) => LocalizableManager.substitute("%@ wants to issue the following in your wallet", args)
            case requestCredentialOfferNoDocument => "Unable to fetch and process the credential offer"
            case unableToIssueAndStore => "Something went wrong issuing your document(s)"
            case missingMetadata => "Unable to retreive document metadata"
            case issueButton => "Issue"
            case issuanceCodeTitle(args) => LocalizableManager.substitute("%@ requires verification", args)
            case issuanceCodeCaption(args) => LocalizableManager.substitute("Type the %@-digit transaction code you received", args)
            case transactionCodeFormatError(args) => LocalizableManager.substitute("Invalid transaction code format. Length should be between %@ to %@ digits and only numeric characters are allowed.", args)
            case inProgress => "In progress"
            case scopedIssuanceSuccessDeferredCaption => "Your document has been requested. You will be notified when it has been issued to your wallet."
            case scopedIssuanceSuccessDeferredCaptionDocName(args) => LocalizableManager.substitute("Your document %@ has been requested. You will be notified when it has been issued to your wallet.", args)
            case scopedIssuanceSuccessDeferredCaptionDocNameAndIssuer(args) => LocalizableManager.substitute("Your document %@ from %@ has been requested. You will be notified when it has been issued to your wallet.", args)
            case issuanceSuccessDeferredCaption(args) => LocalizableManager.substitute("Your documents from %@ have been requested. You will be notified when they have been issued to your wallet.", args)
            case pending => "Pending"
            case issuanceFailed => "Issuance failed"
            case issuanceBlockedTitle => "Issuance blocked"
            case issuanceBlockedMessage => "This issuance request has been blocked because the provider could not be verified by your Wallet.\n\nYour personal information or other data has not been shared with this provider."
            case presentationBlockedTitle => "Presentation blocked"
            case presentationBlockedMessage => "This presentation request has been blocked because the relying party could not be verified by your Wallet.\n\nYour personal information or other data has not been shared with this relying party."
            case relyingPartyId(args) => LocalizableManager.substitute("(ID: %@)", args)
            case privacyPolicy => "Privacy policy"
            case intendedUse => "Intended use"
            case understandRisksAgree => "I understand the risks and agree to share my data"
            case relyingPartyNotVerifiedWarning => "Warning: The information registered about the entity could not be obtained. Review carefully before sharing your data."
            case relyingPartyOveraskedWarning => "Warning: Some of the requested data are not registered with this interacting party. Review carefully before sharing your data."
            case notRegisteredData => "Not registered data"
            case issuanceRegistrationBlockedTitle => "Issuance blocked"
            case issuanceRegistrationBlockedMessage => "This issuance request has been blocked because the provider is not registered for it.\n\nNo document has been added to your Wallet."
            case issuanceRequestTitle => "Issuance request"
            case validateIssuerRegistration => "Check Registration Certificates"
            case restartRequiredTitle => "Restart required"
            case restartRequiredMessage => "Restart the app to apply this change"
            case continueButton => "Continue"
            case deferredDocumentsIssuedModalTitle => "Documents issued"
            case defferedDocumentsIssuedModalCaption => "New documents have been added to your wallet."
            case retrieveLogs => "Retrieve logs"
            case qrScanInformativeText => "Having trouble scanning the QR Code?\nPlease try an alternative way"
            case unableToPresentAndShare => "Unable to present and share your documents."
            case itemNotFoundInStorage => "Item not found in storage"
            case itemsNotFoundInStorage => "Items not found in storage"
            case home => "Home"
            case documents => "Documents"
            case historyTitle => "History"
            case authenticateAuthoriseTransactions => "Authenticate, authorise transactions and share your digital documents in person or online."
            case homeScreenAuthenticateDescription => "Authenticate by sharing your data in person (in close proximity) or online (website/service)."
            case electronicallySignDigitalDocuments => "Electronically sign digital documents with your wallet by choosing a file from your device or by scanning a QR code."
            case learnMore => "Learn more"
            case chooseFromList => "Choose from list"
            case chooseFromListTitle => "Choose a digital document from the list below to add to your wallet. You may add more documents by scanning the QR code provided to you by an authorised issuing service."
            case addDocumentsToWallet => "Add documents to your wallet by choosing from the list below."
            case details => "Details"
            case dataSharingRequest => "Data sharing request"
            case dataShared => "Data shared"
            case doneButton => "Done"
            case dataSharingTitle => "The following transaction requires your permission and authentication."
            case close => "Close"
            case reset => "Reset"
            case all => "All"
            case descending => "Descending"
            case ascending => "Ascending"
            case trustedRelyingParty => "Trusted Relying Party"
            case trustedRelyingPartyDescription => "A Relying Party is considered trusted when it meets predefined criteria for security, data protection, compliance, and responsible data handling. Trust is reinforced through assessments, audits, and certifications."
            case alertAccessOnlineServices => "Access online services"
            case alertAccessOnlineServicesMessage => "Identify yourself to a wide range of public and private online services while protecting your privacy. Prove who you are with just a few taps — no need to manage countless passwords."
            case alertSignDocumentsSafely => "Sign documents safely"
            case alertSignDocumentsSafelyMessage => "Sign documents with just your wallet. Providing a legally binding e-signature will be faster and easier than ever, enabling you to conduct business wherever you are."
            case authenticate => "Authenticate"
            case inPerson => "In person"
            case online => "Online"
            case savedToFavorites => "Saved to favorites"
            case succesfullyAddedFollowingToWallet => "You have successfully added the following to your wallet"
            case removedFromFavorites => "Removed from favorites"
            case savedToFavoritesMessage => "The document was successfully added from your favorite list"
            case removedFromFavoritesMessages => "The document was successfully removed from your favorite list"
            case viewDetails => "View details"
            case requestsTheFollowing => "requests the following"
            case walletIsSecured => "Your wallet is secured!"
            case noResults => "No results"
            case noResultsDocumentsDescription => "No documents found. Try changing your search or filters."
            case noResultsTransactionsDescription => "No transactions found. Try changing your search or filters."
            case proximityConnectionBleDescription => "Hold your phone near object to scan."
            case selectExpiryPeriod => "Expiry Period"
            case filterByState => "State"
            case sortBy => "Sort by"
            case deleteDocumentConfirmDialog => "This document will be removed from your wallet and may affect access to services."
            case defaultLabel => "Default"
            case valid => "Valid"
            case revoke => "Revoke"
            case expired => "Expired"
            case dateIssued => "Date Issued"
            case expiryDate => "Expiry Date"
            case nextSevenDays => "Next 7 days"
            case nextThirtyDays => "Next 30 days"
            case beyondThiryDays => "Beyond 30 days"
            case beforeToday => "Before today"
            case issuanceRequest => "ISSUANCE REQUEST"
            case myEuWallet => "My EU Wallet"
            case categoryGovernment => "GOVERNMENT"
            case categoryHealth => "HEALTH"
            case categoryEducation => "EDUCATION"
            case categoryFinance => "FINANCE"
            case categoryRetail => "RETAIL"
            case categoryOther => "OTHER"
            case categorySocialSecurity => "SOCIAL SECURITY"
            case categoryTravel => "TRAVEL"
            case changelog => "Changelog"
            case orderBy => "Order by"
            case filterByCategory => "Category"
            case searchDocuments => "Search"
            case searchTransactions => "Search"
            case filterByStatus => "Status"
            case completed => "Completed"
            case failed => "Failed"
            case filterByDate => "Transaction Date Period"
            case startDate => "Start date"
            case endDate => "End date"
            case resetDates => "Reset dates"
            case relyingParty => "Relying Party"
            case signedDocuments => "Signed Documents"
            case transactionInformation => "Transaction information"
            case transactionDetailsDataShare => "DATA SHARED"
            case transactionDetailsDataSigned => "DATA SIGNED"
            case transactionDetailsScreenCardDateLabel => "Date"
            case transactionDetailsCompleted => "Completed"
            case or => "OR"
            case today => "TODAY"
            case thisWeek => "THIS WEEK"
            case unknownDate => "Unknown Date"
            case minutesAgo(args) => LocalizableManager.substitute("%@ minutes ago", args)
            case minuteAgo(args) => LocalizableManager.substitute("%@ minute ago", args)
            case transactionDate => "Transaction Date"
            case filterByType => "Transaction Type"
            case presentation => "Presentation"
            case signing => "Signing"
            case issuance => "Issuance"
            case deletion => "Deletion"
            case withoutRelyingName => "No Relying Party"
            case errorFetchTransactionLog => "Unable to fetch transaction log"
            case incomplete => "Incomplete"
            case justNow => "Just now"
            case revoked => "Revoked"
            case revokedModalTitle => "Revoked documents"
            case revokedModalDescription => "The following documents have been revoked."
            case transactionDetailsRequestDeletionMessage => "You can request to stop processing personal data linked to this transaction. This may affect your access to services."
            case transactionDetailsRequestDeletionButton => "Request data deletion"
            case transactionDetailsReportTransactionMessage => "If you believe this relying party has unlawfully requested personal data, you can report this transaction to the authorities. "
            case transactionDetailsReportTransactionButton => "Report suspicious transaction"
            case settings => "Settings"
            case documentDetailsDocumentCredentialsText(args) => LocalizableManager.substitute("Instances remaining %@/%@", args)
            case documentDetailsDocumentCredentialsExpandedTextSubtitle => "For security reasons, this document can be shared a limited number of times before it needs to be re-issued by the issuing authority."
            case documentsListCredentialsUsageText(args) => LocalizableManager.substitute("%@/%@", args)
            case expandableDocumentCredentialsIssueButton => "Issue new"
            case issuanceAddDocumentNoOptions => "No available documents"
            case unknown => "Unknown"
            case pidCombined => "PID Combined"
            case documentData => "DOCUMENT DATA"
            case documentDetailsShow => "Show"
            case documentDetailsHide => "Hide"
            case issuanceSuccessHeaderDescription => "You have successfully added the following to your wallet"
            case documentDetailsReIssueButton => "Reissue document"
            case documentDetailsRemoveButton => "Remove"
            case documentDetailsExpiresOn(args) => LocalizableManager.substitute("Expires on: %@", args)
            case documentDetailsExpiredOn(args) => LocalizableManager.substitute("Expired on: %@", args)
            case documentDetailsIssuedOn(args) => LocalizableManager.substitute("Issued on: %@", args)
            case documentDetailsRevokedDocument => "Document revoked"
            case documentDetailsIssuerCardIssuedMessageText => "You may reissue this document at any time."
            case documentDetailsIssuerCardRevokedMessageText => "This document cannot be used for verification."
            case documentDetailsIssuerCardExpiredMessageText => "This document has expired. You may reissue it."
            case documentDetailsIssuerCardIssuedActionButtonText => "Reissue document"
            case batchIssuanceCounter => "Batch issuance counter"
            case documentProviderExtensionAcceptButton => "Accept"
            case documentProviderExtensionRejectButton => "Reject"
            case enterYourPin => "Enter your PIN"
        }
    }

    /**
     * Substitutes successive `%@` format markers in `template` with `args` in order.
     * Mirrors iOS `String(format:arguments:)` for the `%@` case used by this module.
     * Surplus markers are left intact; surplus args are ignored.
     */
    public static func substitute(template: String, args: Array<String>): String {
        var result = template
        for (arg in args) {
            let idx = result.indexOf("%@")
            match (idx) {
                case Some(pos) =>
                    let before = result[0..pos]
                    let after = result[pos + 2..result.size]
                    result = before + arg + after
                case None => break
            }
        }
        return result
    }

    /**
     * Convenience resolver for a non-parameterized key.
     */
    public static func get(key: LocalizableStringKey): String {
        return LocalizableManager.resolve(key)
    }

    /**
     * Resolves a raw dynamic key string to its English literal, returning the raw
     * key when unmapped (never crashes), mirroring iOS bundle fallback behavior.
     */
    public static func getDynamic(rawKey: String): String {
        return LocalizableManager.resolve(LocalizableStringKey.custom(rawKey))
    }
}
