/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Validator/FormValidator.swift) to Cangjie.
 *
 * The full iOS `Rule` enum is migrated case by case with equivalent semantics:
 * - Peppermint LengthPredicate  -> rune-count comparisons
 * - Peppermint RegexPredicate   -> std.regex full-string match
 * - Peppermint EmailPredicate   -> the same email regex, full-string match
 * - PhoneNumberKit              -> deterministic E.164-style digit validation
 * - the backreference regex of ValidateDuplicateCharacterNotInConsecutiveOrder
 *   ((\d|\w)\1{n,}) -> equivalent linear scan over [0-9A-Za-z_] runs
 * The Swift `[[Rule]: String]` dictionary becomes an array of FormInput pairs
 * (Cangjie enums with payloads are not hashable map keys); iteration semantics
 * are identical. async validate methods become synchronous (pure CPU work).
 */
package eudi_logic_business

import std.collection.ArrayList
import std.convert.*

/** Mirrors the iOS `Rule` enum (full case set). */
public enum Rule {
    | ValidateNotEmpty(String)                          // errorMessage
    | ValidateEmail(String)                             // errorMessage
    | ValidatePhoneNumber(String, String)               // countryCode, errorMessage
    | ValidateStringMaxLength(Int64, String)            // length, errorMessage
    | ValidateStringMinLength(Int64, String)            // length, errorMessage
    | ValidateStringRange(Int64, Int64, String)         // minLength, maxLength, errorMessage
    | ValidateRegex(String, String)                     // regex, errorMessage
    | ValidateStringMatch(String, String, Bool)         // stringToMatch, errorMessage, isCaseSensitive
    | ValidateStringNotMatch(String, String, Bool)      // stringToMatch, errorMessage, isCaseSensitive
    | ValidateDuplicateCharacterNotInConsecutiveOrder(Int64, String) // maxTimesOfConsecutiveOrder, errorMessage
    | ValidateNumericNotInConsecutiveSequenceOrder(Int64, String)    // length, errorMessage
    | ValidateMinimumAmount(Int64, String)              // min, errorMessage
    | ValidateMaximumAmount(Int64, String)              // max, errorMessage
    | ValidateStringLengths(Array<Int64>, String)       // lengths, errorMessage
    | ValidateNoWhiteSpaces(String)                     // errorMessage
    | ValidateUrl(String, Bool, Bool, Bool, Bool)       // errorMessage, host, schema, query, path
}

/** One (rules, value) pair of a form; replaces one Swift dictionary entry. */
public class FormInput {
    public let rules: Array<Rule>
    public let value: String

    public init(rules: Array<Rule>, value: String) {
        this.rules = rules
        this.value = value
    }
}

/** Mirrors iOS `ValidatableForm`. */
public class ValidatableForm {
    public let inputs: Array<FormInput>

    public init(inputs: Array<FormInput>) {
        this.inputs = inputs
    }
}

/** Mirrors iOS `FormValidationResult`. */
public class FormValidationResult {
    public let isValid: Bool
    public let message: String

    public init(isValid: Bool, message!: String = "") {
        this.isValid = isValid
        this.message = message
    }
}

/** Mirrors iOS `FormsValidationResult`. */
public class FormsValidationResult {
    public let isValid: Bool
    public let messages: Array<String>

    public init(isValid: Bool, messages!: Array<String> = Array<String>()) {
        this.isValid = isValid
        this.messages = messages
    }
}

/** Mirrors the iOS `FormValidator` protocol (and `FormValidatorInteractor`). */
public interface FormValidator {
    func validateForm(form: ValidatableForm): FormValidationResult
    func validateForms(forms: Array<ValidatableForm>): FormsValidationResult
}

/** Stateless validation engine, mirrors iOS `FormValidatorImpl`. */
public class FormValidatorImpl <: FormValidator {

    /** Peppermint EmailPredicate expression, evaluated as a full-string match. */
    private static let EMAIL_PATTERN = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"

    public init() {}

    public func validateForm(form: ValidatableForm): FormValidationResult {
        for (input in form.inputs) {
            for (rule in input.rules) {
                match (validateRule(rule, input.value)) {
                    case Some(result) => return result
                    case None => ()
                }
            }
        }
        return FormValidationResult(true)
    }

    public func validateForms(forms: Array<ValidatableForm>): FormsValidationResult {
        let errors = ArrayList<String>()
        var isValid = true
        for (form in forms) {
            for (input in form.inputs) {
                for (rule in input.rules) {
                    match (validateRule(rule, input.value)) {
                        case Some(result) =>
                            isValid = false
                            errors.add(result.message)
                        case None => ()
                    }
                }
            }
        }
        return FormsValidationResult(isValid, messages: errors.toArray())
    }

    private func validateRule(rule: Rule, value: String): ?FormValidationResult {
        match (rule) {
            case ValidateNotEmpty(errorMessage) =>
                return checkValidationResult(!value.isEmpty(), errorMessage)
            case ValidateEmail(errorMessage) =>
                return checkValidationResult(isEmailValid(value), errorMessage)
            case ValidatePhoneNumber(countryCode, errorMessage) =>
                return checkValidationResult(isPhoneNumberValid(value, countryCode), errorMessage)
            case ValidateStringMaxLength(length, errorMessage) =>
                return checkValidationResult(runeCount(value) <= length, errorMessage)
            case ValidateStringMinLength(length, errorMessage) =>
                return checkValidationResult(runeCount(value) >= length, errorMessage)
            case ValidateStringRange(minLength, maxLength, errorMessage) =>
                let count = runeCount(value)
                return checkValidationResult(count >= minLength && count <= maxLength, errorMessage)
            case ValidateRegex(regex, errorMessage) =>
                return checkValidationResult(StringUtil.fullMatches(value, regex), errorMessage)
            case ValidateStringMatch(stringToMatch, errorMessage, isCaseSensitive) =>
                return checkValidationResult(
                    StringUtil.equalsString(value, stringToMatch, ignoreCase: !isCaseSensitive),
                    errorMessage
                )
            case ValidateStringNotMatch(stringToMatch, errorMessage, isCaseSensitive) =>
                return checkValidationResult(
                    !StringUtil.equalsString(value, stringToMatch, ignoreCase: !isCaseSensitive),
                    errorMessage
                )
            case ValidateDuplicateCharacterNotInConsecutiveOrder(maxTimes, errorMessage) =>
                return checkValidationResult(
                    duplicateCharacterNotInConsecutiveOrder(value, maxTimes),
                    errorMessage
                )
            case ValidateNumericNotInConsecutiveSequenceOrder(length, errorMessage) =>
                return checkValidationResult(
                    numericNotInConsecutiveSequenceOrder(value, length),
                    errorMessage
                )
            case ValidateMinimumAmount(min, errorMessage) =>
                return checkValidationResult(isAboveOrEqualMinimum(value, min), errorMessage)
            case ValidateMaximumAmount(max, errorMessage) =>
                return checkValidationResult(isBelowOrEqualMaximum(value, max), errorMessage)
            case ValidateStringLengths(lengths, errorMessage) =>
                return checkValidationResult(isLengthIncluded(value, lengths), errorMessage)
            case ValidateNoWhiteSpaces(errorMessage) =>
                return checkValidationResult(!value.contains(" "), errorMessage)
            case ValidateUrl(errorMessage, shouldValidateHost, shouldValidateSchema, shouldValidateQuery, shouldValidatePath) =>
                return checkValidationResult(
                    isUrlValid(value, shouldValidateHost, shouldValidateSchema, shouldValidateQuery, shouldValidatePath),
                    errorMessage
                )
        }
    }

    private func checkValidationResult(isValid: Bool, errorMessage: String): ?FormValidationResult {
        if (!isValid) {
            return FormValidationResult(false, message: errorMessage)
        }
        return None
    }

    private func runeCount(value: String): Int64 {
        return Int64(value.toRuneArray().size)
    }

    private func isEmailValid(email: String): Bool {
        return StringUtil.fullMatches(email, EMAIL_PATTERN)
    }

    /**
     * Region-aware validation against the libphonenumber metadata, matching iOS
     * `PhoneNumberUtility.parse(phone, withRegion: countryCode, ignoreType: false)`.
     * See `phone_number_validator.cj` for the ported algorithm.
     */
    private func isPhoneNumberValid(phone: String, countryCode: String): Bool {
        return PhoneNumberValidator.isValid(phone, countryCode)
    }

    private func isAboveOrEqualMinimum(value: String, min: Int64): Bool {
        match (StringUtil.toInteger(value)) {
            case Some(v) => return amountMagnitude(v) >= min
            case None => return false
        }
    }

    private func isBelowOrEqualMaximum(value: String, max: Int64): Bool {
        match (StringUtil.toInteger(value)) {
            case Some(v) => return amountMagnitude(v) <= max
            case None => return false
        }
    }

    private func amountMagnitude(v: Int64): Int64 {
        if (v >= 0) { return v }
        try {
            return -v
        } catch (_: OverflowException) {
            return Int64.Max
        }
    }

    private func isLengthIncluded(value: String, lengths: Array<Int64>): Bool {
        let count = runeCount(value)
        for (length in lengths) {
            if (length == count) {
                return true
            }
        }
        return false
    }

    /**
     * Mirrors the iOS backreference regex (\d|\w)\1{maxTimes-1,}: valid when no
     * word character ([0-9A-Za-z_]) repeats maxTimes or more consecutively.
     */
    private func duplicateCharacterNotInConsecutiveOrder(value: String, maxTimesOfConsecutiveOrder: Int64): Bool {
        if (maxTimesOfConsecutiveOrder < 2) {
            return true
        }
        let runes = value.toRuneArray()
        var i: Int64 = 0
        while (i < runes.size) {
            let current = runes[i]
            var runLength: Int64 = 1
            while (i + runLength < runes.size && runes[i + runLength] == current) {
                runLength++
            }
            if (isWordRune(current) && runLength >= maxTimesOfConsecutiveOrder) {
                return false
            }
            i += runLength
        }
        return true
    }

    private func isWordRune(r: Rune): Bool {
        return (r >= r'0' && r <= r'9') ||
            (r >= r'a' && r <= r'z') ||
            (r >= r'A' && r <= r'Z') ||
            r == r'_'
    }

    /**
     * Mirrors iOS `numericNotInConsecutiveSequenceOrder` exactly: builds the
     * ascending/descending sequence seeded by the first two digits (allowing
     * negative continuations like "3210-1-2", same as Swift string append) and
     * fails only when the value contains that sequence.
     */
    private func numericNotInConsecutiveSequenceOrder(value: String, length: Int64): Bool {
        if (value.isEmpty() || length < 2) {
            return true
        }
        if (StringUtil.toInteger(value).isNone()) {
            return true
        }
        let runes = value.toRuneArray()
        if (Int64(runes.size) != length) {
            return true
        }
        let firstNumber = digitValue(runes[0])
        let secondNumber = digitValue(runes[1])
        match ((firstNumber, secondNumber)) {
            case (Some(first), Some(second)) =>
                let isReversed = first > second
                let sb = StringBuilder()
                sb.append("${first}")
                var i: Int64 = 1
                while (i <= length - 1) {
                    if (isReversed) {
                        sb.append("${first - i}")
                    } else {
                        sb.append("${first + i}")
                    }
                    i++
                }
                return !value.contains(sb.toString())
            case _ => return true
        }
    }

    private func digitValue(r: Rune): ?Int64 {
        if (r >= r'0' && r <= r'9') {
            return Int64(UInt32(r)) - 48
        }
        return None
    }

    /** Mirrors iOS `isUrlValid` over `toCompatibleUrl` + URLComponents checks. */
    private func isUrlValid(
        value: String,
        shouldValidateHost: Bool,
        shouldValidateSchema: Bool,
        shouldValidateQuery: Bool,
        shouldValidatePath: Bool
    ): Bool {
        if (value.isEmpty()) {
            return false
        }
        let url: ParsedUrl
        match (UrlUtil.toCompatibleUrl(value)) {
            case Some(parsed) => url = parsed
            case None => return false
        }
        if (shouldValidateHost && StringUtil.isNilOrEmpty(url.host)) {
            return false
        }
        if (shouldValidateSchema && StringUtil.isNilOrEmpty(url.scheme)) {
            return false
        }
        if (shouldValidateQuery && StringUtil.isNilOrEmpty(url.query)) {
            return false
        }
        if (shouldValidatePath && url.path.isEmpty()) {
            return false
        }
        return true
    }
}

/** Factory replacing the iOS Swinject assembly registration for FormValidator. */
public func createFormValidator(): FormValidator {
    return FormValidatorImpl()
}
