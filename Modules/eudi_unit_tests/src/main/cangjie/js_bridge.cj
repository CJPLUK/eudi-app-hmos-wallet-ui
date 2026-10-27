package eudi_unit_tests

import ohos.ark_interop.JSModule
import ohos.ark_interop.JSContext
import ohos.ark_interop.JSCallInfo
import ohos.ark_interop.JSValue

func runUnitTests(runtime: JSContext, _: JSCallInfo): JSValue {
    runtime.string(runAllUnitSuites()).toJSValue()
}

let EXPORT_MODULE = JSModule.registerModule {
    runtime, exports =>
        exports["runUnitTests"] = runtime.function(runUnitTests).toJSValue()
}
