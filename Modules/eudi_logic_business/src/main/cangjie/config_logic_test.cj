/*
 * Host unit tests for the build-variant seam. iOS resolves the variant from
 * the app bundle ("Build Variant" in Info.plist) and falls back to DEV when it
 * is missing or unrecognised; these cases pin the same behaviour so a build
 * that forgets to declare it points at the development issuers rather than
 * silently at DEMO.
 */
package eudi_logic_business

import std.unittest.*
import std.unittest.testmacro.*

@Test
class AppBuildVariantResolutionTest {

    @TestCase
    func declaredVariantIsUsed(): Unit {
        AppBuildVariantSource.setReader({ => "DEMO" })
        @Expect(resolveAppBuildVariant() == AppBuildVariant.DEMO, true)
        @Expect(ConfigLogicImpl().appBuildVariant == AppBuildVariant.DEMO, true)
    }

    @TestCase
    func unrecognisedVariantFallsBackToDev(): Unit {
        AppBuildVariantSource.setReader({ => "STAGING" })
        @Expect(resolveAppBuildVariant() == AppBuildVariant.DEV, true)
    }

    @TestCase
    func emptyDeclarationFallsBackToDev(): Unit {
        AppBuildVariantSource.setReader({ => "" })
        @Expect(resolveAppBuildVariant() == AppBuildVariant.DEV, true)
    }

    @TestCase
    func failingReaderFallsBackToDev(): Unit {
        AppBuildVariantSource.setReader({ => throw Exception("no bundle off-device") })
        @Expect(resolveAppBuildVariant() == AppBuildVariant.DEV, true)
    }

    @TestCase
    func explicitArgumentStillWins(): Unit {
        AppBuildVariantSource.setReader({ => "DEV" })
        let demo = ConfigLogicImpl(buildVariant: AppBuildVariant.DEMO)
        @Expect(demo.appBuildVariant == AppBuildVariant.DEMO, true)
    }
}
