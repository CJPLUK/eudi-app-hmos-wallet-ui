/*
 * rqes_browser.cj — external system-browser open seam.
 *
 * iOS opens the QTSP authorization URL with UIApplication.openURLIfPossible; the flow returns
 * via the rqes:// deep link. On HarmonyOS the open is an implicit Want (viewData + uri) through
 * the ability context — but that lives in eudi_logic_core (AppContextHolder) + the ohos Want API,
 * which this feature must not depend on (keeps it core/native-free and standalone-buildable). So
 * this is a seam: `entry` installs the opener at startup (AppComposition), and the flow calls
 * open(). Mirrors the ScanBridge pattern.
 */
package eudi_feature_rqes

public class RqesBrowser {
    private static var opener: ?(String) -> Bool = None

    // Installed by `entry` at startup with a closure that does
    // AppContextHolder.get()?.startAbility(Want{viewData, uri}).
    public static func setOpener(open: (String) -> Bool): Unit {
        RqesBrowser.opener = Some(open)
    }

    // Opens `url` in the system browser. Returns false if no opener is installed or the launch
    // fails, so the caller can surface an "unable to open browser" error (iOS parity).
    public static func open(url: String): Bool {
        return match (RqesBrowser.opener) {
            case Some(f) => f(url)
            case None => false
        }
    }
}
