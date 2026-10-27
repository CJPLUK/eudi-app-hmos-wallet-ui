/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 */

package ohos_app_cangjie_entry

// 主仓 entry 直接消费 B 交付的 CBOR 库(third_party/eudi_lib_cbor @ v0.1.0)。
// 用例覆盖蓝图 owns_interfaces 声明的核心面:decodeCbor/encode 往返、at 索引、
// field 取键、cborInt、tag-24 embedded(ISO 18013-5 mdoc 高频用法)。
import ohos_app_cangjie_eudi_cjcbor.cbor.*

func cborBytesEq(a: Array<UInt8>, b: Array<UInt8>): Bool {
    if (a.size != b.size) {
        return false
    }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) {
            return false
        }
        i++
    }
    return true
}

// 5 个用例逐个跑,每个独立 try,返回 "N/5 | 明细"。
public func entry_cbor_selftest(): String {
    var report = ""
    var passed = 0

    // T1 — decode→encode 往返: [0x83,01,02,03] = 数组 [1,2,3]
    try {
        let bytes: Array<UInt8> = [0x83, 0x01, 0x02, 0x03]
        if (cborBytesEq(decodeCbor(bytes).encode(), bytes)) { passed++; report += "roundtrip:ok " } else { report += "roundtrip:BAD " }
    } catch (e: Exception) { report += "roundtrip:ERR(${e.message}) " }

    // T2 — at(1) 取数组元素 == cborInt(2)
    try {
        let v = decodeCbor([0x83, 0x01, 0x02, 0x03])
        match (v.at(1)) {
            case Some(x) => if (x == cborInt(2)) { passed++; report += "at:ok " } else { report += "at:BAD " }
            case None => report += "at:NONE "
        }
    } catch (e: Exception) { report += "at:ERR(${e.message}) " }

    // T3 — field 取 map 键: {1: "a"} = [0xA1,0x01,0x61,0x61]
    try {
        let m = decodeCbor([0xA1, 0x01, 0x61, 0x61])
        match (m.field(cborInt(1))) {
            case Some(x) => if (x == CborValue.TextStringVal("a")) { passed++; report += "field:ok " } else { report += "field:BAD " }
            case None => report += "field:NONE "
        }
    } catch (e: Exception) { report += "field:ERR(${e.message}) " }

    // T4 — tag-24 embedded 往返(mdoc DeviceEngagement 核心用法)
    try {
        if (decodeEmbedded(encodeEmbedded(cborInt(5))) == cborInt(5)) { passed++; report += "tag24:ok " } else { report += "tag24:BAD " }
    } catch (e: Exception) { report += "tag24:ERR(${e.message}) " }

    // T5 — 文本串编码: "abc" → [0x63,0x61,0x62,0x63]
    try {
        let expect: Array<UInt8> = [0x63, 0x61, 0x62, 0x63]
        if (cborBytesEq(CborValue.TextStringVal("abc").encode(), expect)) { passed++; report += "text:ok" } else { report += "text:BAD" }
    } catch (e: Exception) { report += "text:ERR(${e.message})" }

    return "${passed}/5 | ${report}"
}
