# ADR 0001: Third-party extensions (F-52)

**Status:** Proposed — not started. Per `DROPPY_PARITY_PLAN.md` §9, F-52 is
"only if people actually ask"; this ADR exists so that ask has something
concrete to react to, not as a signal that implementation is scheduled.

## Context

`ExtensionSystem/ExtensionAPI.swift`'s header comment already states the
position: extensions are registered in-process rather than loaded from
external bundles, deliberately, because the app is sandboxed and notarized
and `dlopen`-ing third-party code would break both guarantees. That
constraint doesn't go away for F-52 — it's the reason a third-party
extension can't just be "more code in the same process" the way a built-in
one is.

Everything a built-in extension can currently do — contribute a live
activity, a notch tab, a header accessory, a menu bar item, a keyboard
shortcut, a board widget (F-11), read external data — a third-party one
would plausibly want too. Some of what built-ins reach for now (raw
`AXUIElement` window control for F-30, a system-wide `CGEventTap` for F-32,
a `pmset` shell-out for F-23) is exactly the kind of privileged capability
CLAUDE.md's XPC helper rules exist to gate, and none of that gating was
designed with an *untrusted* caller in mind — `HelperCapabilityGate`
assumes the only client is this app itself, code-signature-pinned in
`XPCClientValidator`.

## Decision drivers

1. **Sandbox integrity.** No change here can be "add an entitlement to let
   third-party code run in-process" — CLAUDE.md rules that out explicitly
   ("Don't de-sandbox the main app").
2. **The XPC helper's threat model changes completely.** Today it trusts
   exactly one signed caller. A third-party extension host means the helper
   either (a) still only trusts this app, and extensions have zero access
   to any `HelperCapability`, or (b) needs a real multi-tenant capability
   and audit model — per-extension grants, per-extension signing checks,
   per-extension audit logging — which is a rewrite of `HelperCapabilityGate`,
   not an extension of it.
3. **Review story.** A signed bundle format and a capability manifest (as
   the plan sketches) only mean something if something checks them before
   the extension runs — either at install time (this app validates a
   signature + manifest before loading) or via some distribution gate. This
   project has no notarization/review pipeline of its own to lean on.
4. **Blast radius of getting it wrong.** Every other privileged feature
   shipped so far in this plan (F-01, F-23, F-30, F-32) was scoped around
   the assumption that the calling code is this app's own, reviewed source.
   An extension host inverts that assumption for exactly the surface area
   CLAUDE.md is most conservative about.

## Options considered

**A. In-process Swift API, source-distributed.** Third-party code compiled
into a fork of the app, or added as a local SPM package the user builds
themselves. Zero sandbox risk, zero new XPC surface, but "third-party
extension" then means "recompile the app" — not what anyone asking for this
actually wants, and it doesn't compose with notarized distribution.

**B. Out-of-process extension host, capability-scoped.** Each third-party
extension ships as its own signed bundle + capability manifest (as the plan
sketches) and runs in its own XPC service, sandboxed independently, talking
to the main app over a narrow, typed protocol — board widgets, live
activities, and menu bar items as the initial surface, since none of those
need a `HelperCapability`. `BoringNotchXPCHelper` capabilities (`axWindows`,
`axNotifications`, `input`, `pty`, `power`) stay off-limits to extensions
in v1, full stop — reachable only by this app's own signed code, same as
today. This is real work: a manifest schema, per-extension XPC sandboxing,
a way to install/remove/update extension bundles, and UI for what an
extension is allowed to see. It's also the only option that doesn't either
break the sandbox or make "third-party extension" a lie.

**C. Do nothing further than this ADR.** Keep in-process built-ins as the
only extension mechanism, as today. Revisit if and when there's an actual
ask, per the plan's own gate.

## Recommendation

**C now, B if F-52 is ever actually greenlit.** Nothing about the current
architecture (`BoringExtension`, `ExtensionRegistry`) needs to change to
make B possible later — it's an additive, out-of-process peer to the
existing in-process registration, not a replacement. The capability-scoped
design in option B is the one worth building if this is ever prioritized:
start with board widgets and live activities (no privileged helper access
needed), and treat any future request for `HelperCapability` access from a
third-party extension as its own, separate security review — not something
this ADR pre-approves.

## Consequences

- No code changes from this ADR. `ExtensionRegistry.registerBuiltInExtensions()`
  remains the only registration path.
- If F-52 is picked up later, `HelperCapabilityGate` needs a real design
  pass (per-caller grants, not just per-capability) before any third-party
  code gets anywhere near `axWindows`/`axNotifications`/`input`/`pty`/`power`.
- The next concrete step, if this is greenlit, is a manifest schema draft
  and a spike of a single out-of-process board-widget extension — not a
  general-purpose plugin SDK on the first pass.
