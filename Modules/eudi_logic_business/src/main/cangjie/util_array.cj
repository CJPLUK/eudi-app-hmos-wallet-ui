/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Extension/Array+Extensions.swift) to Cangjie.
 *
 * Swift `Array` extensions become `ArrayUtil` static generics. The Swift
 * `init(count:createElement:)` convenience maps to `filled`, the safe subscript
 * maps to `getOrNone`, and `appendIfNotExists` keeps its name on `ArrayList`.
 */
package eudi_logic_business

import std.collection.ArrayList

/** Array helper set mirroring the cross-module consumed iOS Array extensions. */
public class ArrayUtil {

    /** Mirrors `Array(count:createElement:)`. */
    public static func filled<T>(count: Int64, createElement: () -> T): ArrayList<T> {
        let list = ArrayList<T>()
        var i: Int64 = 0
        while (i < count) {
            list.add(createElement())
            i++
        }
        return list
    }

    /** Mirrors `subscript(safe:)`: element at index when in bounds, otherwise None. */
    public static func getOrNone<T>(items: Array<T>, index: Int64): ?T {
        if (index < 0 || index >= items.size) {
            return None
        }
        return items[index]
    }

    /** Mirrors `subscript(safe:)` for ArrayList. */
    public static func getOrNone<T>(items: ArrayList<T>, index: Int64): ?T {
        if (index < 0 || index >= items.size) {
            return None
        }
        return items[index]
    }

    /** Mirrors `appendIfNotExists(_:)` with Equatable elements. */
    public static func appendIfNotExists<T>(items: ArrayList<T>, element: T): Unit where T <: Equatable<T> {
        for (existing in items) {
            if (existing == element) {
                return
            }
        }
        items.add(element)
    }

    /** Mirrors `appendIfNotExists(_:)` with an explicit equality predicate (non-Equatable payloads). */
    public static func appendIfNotExists<T>(items: ArrayList<T>, element: T, equals: (T, T) -> Bool): Unit {
        for (existing in items) {
            if (equals(existing, element)) {
                return
            }
        }
        items.add(element)
    }
}
