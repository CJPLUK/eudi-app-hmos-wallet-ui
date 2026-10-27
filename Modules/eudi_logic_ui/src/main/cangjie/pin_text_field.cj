/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/Input/PinTextFieldView.swift) to Cangjie ArkUI.
 *
 * S-018 paradigm: the PIN digits are drawn as boxes and a fully transparent,
 * uncontrolled TextInput is stacked on top of them. Taps focus the invisible
 * input, the system keyboard types into it, and `onChange` repaints the boxes.
 * Keeping the native input uncontrolled prevents a state repaint from writing
 * a five-digit value back while the IME is committing the sixth digit.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.arkui.component.focus_control.*
import ohos.base.*
import std.time.*
import kit.PerformanceAnalysisKit.Hilog
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Mirrors Swift `PinTextFieldView`: fixed number of digit boxes, secure or
 * plain echo, error highlighting and disabled state. Partial values flow out
 * through `onPinChange`; a full-length value is delivered only through
 * `onPinComplete`. Keeping those paths exclusive is important: a completion
 * can navigate or remount this field, and doing that while the native
 * TextInput is still dispatching its `onChange` event drops trailing fast-IME
 * input on some HarmonyOS devices. The completion is therefore posted to the
 * next UI turn. Instantiate with real callbacks (S-017: the defaults are
 * inert).
 */
@Component
public class PinTextFieldView {
    public var pinTitle: ?LocalizableStringKey = None
    public var maxDigits: Int64 = 6
    public var isSecureEntry: Bool = true
    public var hasError: Bool = false
    public var isDisabled: Bool = false
    public var boxWidth: Float64 = 45.0
    public var boxHeight: Float64 = 55.0
    public var boxSpacing: Float64 = 10.0
    public var onPinChange: (String) -> Unit = { _ => }
    public var onPinComplete: (String) -> Unit = { _ => }
    /**
     * Focus the hidden TextInput when it appears so the soft keyboard opens
     * without a manual tap (cold start PIN screen + remount after a rejected
     * attempt). Callers may set false only when the field must stay unfocused.
     */
    public var refocusOnAppear: Bool = true
    @State
    var pinValue: String = ""
    @State
    var isEditingAfterError: Bool = false
    private var inputGeneration: Int64 = 0
    /** Bumped when scheduling a new autofocus wave; stale retries bail out. */
    private var focusGeneration: Int64 = 0
    private var didAutoFocus: Bool = false

    private func hasTitle(): Bool {
        match (this.pinTitle) {
            case Some(_) => true
            case None => false
        }
    }

    private func titleText(): String {
        ListItemData.optText(this.pinTitle)
    }

    private func digitIndices(): Array<Int64> {
        Array<Int64>(this.maxDigits, { idx => idx })
    }

    private func digitDisplay(idx: Int64): String {
        if (idx >= this.pinValue.size) {
            return ""
        }
        if (this.isSecureEntry) {
            return "●"
        }
        return this.pinValue[idx..idx + 1].toString()
    }

    private func boxBorderColor(idx: Int64): Color {
        if (this.hasVisibleError()) {
            return uiColor(ThemeManager.shared.color.red)
        }
        if (idx == this.pinValue.size && !this.isDisabled) {
            return uiColor(ThemeManager.shared.color.accent)
        }
        return uiColor(ThemeManager.shared.color.separator)
    }

    private func digitColor(): Color {
        if (this.hasVisibleError()) {
            return uiColor(ThemeManager.shared.color.red)
        }
        return uiColor(ThemeManager.shared.color.primaryLabel)
    }

    private func fieldWidth(): Float64 {
        Float64(this.maxDigits) * this.boxWidth +
            Float64(this.maxDigits - 1) * this.boxSpacing
    }

    /** A new attempt must look normal immediately, before parent state syncs. */
    private func hasVisibleError(): Bool {
        this.hasError && !this.isEditingAfterError
    }

    /**
     * Defense in depth for IME composition and pasted text. ArkUI's
     * inputFilter handles the native field; this keeps all callbacks and PIN
     * state numeric even if an input method emits a mixed composition value.
     */
    private func digitsOnly(value: String): String {
        let result = StringBuilder()
        for (r in value.runes()) {
            if (r >= r'0' && r <= r'9') {
                result.append(r)
            }
        }
        return result.toString()
    }

    private func handleChange(value: String): Unit {
        this.inputGeneration += 1
        let generation = this.inputGeneration
        var next = this.digitsOnly(value)
        if (next.size > this.maxDigits) {
            next = next[0..this.maxDigits].toString()
        }
        if (!next.isEmpty()) {
            this.isEditingAfterError = true
        }
        this.pinValue = next
        if (next.size == this.maxDigits) {
            // Authentication can navigate away immediately. Give ArkUI enough
            // time to paint the completed field first; merely posting straight
            // back to UIThread still runs before the next display frame.
            let completedValue = next
            spawn {
                sleep(80 * Duration.millisecond)
                spawn(UIThread) { =>
                    // Ignore a stale completion if the user edited the value
                    // again during the one-frame paint window.
                    if (generation == this.inputGeneration && this.pinValue == completedValue) {
                        this.onPinComplete(completedValue)
                    }
                }
            }
        } else {
            this.onPinChange(next)
        }
    }

    /**
     * Ask ArkUI to focus the hidden TextInput and raise the soft keyboard.
     * Callers pass a short reason for hilog so cold-start races are diagnosable.
     */
    private func requestPinFocus(reason: String): Unit {
        if (!this.refocusOnAppear || this.isDisabled) {
            return
        }
        let ok = FocusControl.requestFocus("pin-input")
        Hilog.info(0, "PinFocus", "requestFocus reason=${reason} ok=${ok}")
        if (ok) {
            this.didAutoFocus = true
        }
    }

    /**
     * Cold-start PIN screens race navigation settle. Prefer synchronous +
     * chained UI-thread retries (spawn(UIThread) after sleep is unreliable —
     * see DocumentTab deferred-poll notes). onVisibleAreaChange is the
     * backstop once the field is on screen.
     */
    private func scheduleAutoFocus(): Unit {
        if (!this.refocusOnAppear || this.isDisabled) {
            return
        }
        this.focusGeneration += 1
        let gen = this.focusGeneration
        this.didAutoFocus = false
        this.requestPinFocus("appear")
        // Next UI turns without sleeping off-thread — covers post-push settle.
        spawn(UIThread) { =>
            if (gen == this.focusGeneration && !this.didAutoFocus) {
                this.requestPinFocus("ui-1")
                spawn(UIThread) { =>
                    if (gen == this.focusGeneration && !this.didAutoFocus) {
                        this.requestPinFocus("ui-2")
                        spawn(UIThread) { =>
                            if (gen == this.focusGeneration && !this.didAutoFocus) {
                                this.requestPinFocus("ui-3")
                            }
                        }
                    }
                }
            }
        }
    }

    public func build() {
        Column(space: SPACING_SMALL) {
            if (this.hasTitle()) {
                Text(this.titleText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
            }
            Stack {
                Row(space: this.boxSpacing) {
                    ForEach(
                        this.digitIndices(),
                        itemGenerator: { idx: Int64, _: Int64 =>
                            Column {
                                Text(this.digitDisplay(idx))
                                    .fontSize(20.0)
                                    .fontColor(this.digitColor())
                            }
                            .width(this.boxWidth)
                            .height(this.boxHeight)
                            .borderWidth(1.0)
                            .borderColor(this.boxBorderColor(idx))
                            .borderRadius(5.0)
                            .justifyContent(FlexAlign.Center)
                        }
                    )
                }
                // Do not bind `text` to pinValue. The latter is display state;
                // feeding it back into the native input can overwrite an IME
                // commit during sub-second six-digit entry.
                TextInput()
                    // inputFilter is a per-character allow pattern. `*` must
                    // not be used here because it also matches an empty string.
                    .inputFilter("[0-9]")
                    .maxLength(UInt32(this.maxDigits))
                    .fontColor(Color.Transparent)
                    .caretColor(Color.Transparent)
                    .placeholderColor(Color.Transparent)
                    .backgroundColor(Color.Transparent)
                    .selectionMenuHidden(true)
                    .enableKeyboardOnFocus(true)
                    .focusable(true)
                    .key("pin-input")
                    .id("pin-input")
                    .defaultFocus(this.refocusOnAppear && !this.isDisabled)
                    .width(this.fieldWidth())
                    .height(this.boxHeight)
                    .enabled(!this.isDisabled)
                    .onAppear({ => this.scheduleAutoFocus() })
                    .onVisibleAreaChange([0.0, 1.0], { isExpanding: Bool, ratio: Float64 =>
                        // After Startup → Biometry navigation the field can
                        // appear before the window accepts IME focus. Re-try
                        // once the field is actually on screen.
                        if (isExpanding && ratio >= 0.9) {
                            this.requestPinFocus("visible")
                        }
                    })
                    .onChange({ value => this.handleChange(value) })
            }
        }
        .alignItems(HorizontalAlign.Start)
    }
}
