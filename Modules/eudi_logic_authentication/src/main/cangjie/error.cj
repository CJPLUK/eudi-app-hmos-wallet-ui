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
 * Port of iOS logic-authentication/Sources/Error/AuthenticationError.swift.
 *
 * iOS `enum AuthenticationError: LocalizedError` → Cangjie Exception subclass
 * (the delivered error pattern: `class X <: Exception` so `throw` matches the iOS
 * `throws` surface). The single `quickPinInvalid` case carries the same localized
 * description, resolved through the migrated LocalizableManager
 * (LocalizableStringKey.invalidQuickPin).
 */
package eudi_logic_authentication

import eudi_logic_resources.LocalizableStringKey
import eudi_logic_resources.LocalizableManager

/** The discriminant of AuthenticationError, mirroring the iOS enum cases 1:1. */
public enum AuthenticationErrorKind <: Equatable<AuthenticationErrorKind> {
    | quickPinInvalid

    /** Mirrors iOS `errorDescription`. */
    public func errorDescription(): String {
        match (this) {
            case quickPinInvalid => LocalizableManager.get(LocalizableStringKey.invalidQuickPin)
        }
    }

    public operator func ==(o: AuthenticationErrorKind): Bool {
        match ((this, o)) {
            case (quickPinInvalid, quickPinInvalid) => true
        }
    }
    public operator func !=(o: AuthenticationErrorKind): Bool { !(this == o) }
}

/** Mirrors iOS `enum AuthenticationError: LocalizedError`. */
public class AuthenticationError <: Exception {
    public let kind: AuthenticationErrorKind

    public init(kind: AuthenticationErrorKind) {
        super(kind.errorDescription())
        this.kind = kind
    }

    public prop errorDescription: String {
        get() { this.kind.errorDescription() }
    }

    /** Factory helper mirroring the iOS enum case. */
    public static func quickPinInvalid(): AuthenticationError {
        AuthenticationError(AuthenticationErrorKind.quickPinInvalid)
    }
}
