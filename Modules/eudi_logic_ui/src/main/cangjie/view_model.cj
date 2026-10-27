/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (Architecture/ViewModel.swift) to Cangjie for the EUDI HarmonyOS wallet.
 *
 * Swift used `@Observable` + Combine; here state observation is a single-slot
 * listener: feature pages register one `onStateChange` callback and copy the
 * fresh state into their own `@State` fields (on the UI thread — see
 * syntax_error.md S-001 when notifying from async work).
 */
package eudi_logic_ui

/**
 * Marker protocol for every reducer state. Mirrors Swift `ViewState`.
 * Implementations must be `public` classes/structs (R-104) so consumer
 * components can hold them in `@State` fields.
 */
public interface ViewState {}

/**
 * Generic MVVM base. Mirrors Swift
 * `ViewModel<Router: RouterHost, UiState: ViewState>`:
 *  - `viewState` — current immutable state snapshot
 *  - `setState(reducer)` — produces the next state from the previous one
 *  - single-slot `onStateChange` listener, invoked after `viewState` updated
 *  - `router` — navigation host injected by the composition root
 */
public open class BaseViewModel<S> where S <: ViewState {
    public let router: RouterHost
    private var state: S
    private var listener: Option<(S) -> Unit> = None

    public init(router: RouterHost, initialState: S) {
        this.router = router
        this.state = initialState
    }

    public prop viewState: S {
        get() { this.state }
    }

    /**
     * Applies the reducer to the current state, stores the result, then
     * notifies the listener (if any) with the already-updated state.
     */
    public func setState(reducer: (S) -> S): Unit {
        this.state = reducer(this.state)
        match (this.listener) {
            case Some(notify) => notify(this.state)
            case None => ()
        }
    }

    /** Registers the single state listener, replacing any previous one. */
    public func onStateChange(handler: (S) -> Unit): Unit {
        this.listener = Some(handler)
    }

    /** Clears the listener slot (e.g. when the consuming page disappears). */
    public func clearStateListener(): Unit {
        this.listener = None
    }
}
