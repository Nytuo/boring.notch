# Deferred / descoped work

Tracks what `DROPPY_PARITY_PLAN.md` asked for that deliberately wasn't
built, or was built smaller than described, and why — so the reasoning
survives past the commit messages that made each call. Each item names the
plan section it corresponds to.

## F-33 — Console (terminal in the notch): not started

The plan calls this "highest risk in this plan" and requires it to build on
`SwiftTerm` (SPM, MIT) — a dependency not currently in this project. Adding
a new SPM package means editing `project.pbxproj`'s `XCRemoteSwiftPackageReference`/
`XCSwiftPackageProductDependency` entries and the resolved-package graph by
hand, with no way in this environment to run Xcode's actual package
resolution to verify the result. A malformed package reference risks
leaving the whole project unbuildable — for every feature in this plan, not
just this one — which is a disproportionate risk to take blind for a
single Phase-3 feature the plan itself gates behind "Default off, explicit
opt-in with a plain-language warning" and "Do not start before F-01 ships."

Combined with the actual feature — the unsandboxed XPC helper spawning a
PTY (`forkpty` + `login -fp $USER`) reachable from a hover target — this is
the single largest security-review surface in the entire plan. Shipping it
without being able to verify the SPM dependency resolves, and without a way
to interactively exercise a live PTY session in this environment, isn't a
responsible tradeoff.

**If this is picked up:** confirm `SwiftTerm` resolves cleanly in a real
Xcode session first, as its own isolated change, before writing any PTY
code. The XPC helper side (`forkpty`, streaming bytes over the connection,
gated on a `pty` `HelperCapability`) is a smaller, more contained addition
once that dependency is actually in the project.

## F-25 — AI agent progress: shipped, unverified end-to-end

The Unix-socket design in the plan (`~/Library/Application Support/BoringNotch/agent.sock`)
doesn't work as written — that path resolves inside this sandboxed app's
container, unreachable from an external unsandboxed CLI process. Shipped
instead as a fixed loopback TCP listener (port 47921) — see
`boringNotch/managers/AgentProgressServer.swift`'s header comment for the
full reasoning. Not exercised against a live Claude Code hook firing in
this environment; the HTTP parsing is deliberately defensive, but this is
the item most worth a real end-to-end check before relying on it.

## F-31 — Notification inline reply: shipped as a spike, not verified live

The plan explicitly asks for a spike against a real notification banner
before committing to the feature. There was no way to trigger a live
banner and inspect its actual AX role tree in this environment, so the
generic AX-based reply path shipped off-by-default and fails closed at
every step, but hasn't been checked against a real banner. See
`boringNotch/managers/NotificationWatcher.swift`'s "Reply (F-31)" section.

## F-43 — Motion art: shipped, scoped to looping video only

The plan describes three render modes (Metal shader, user Lottie file,
looping video). Only the video mode (`AVPlayerLooper`) shipped — `Lottie`
is a pinned dependency with no existing usage anywhere in this codebase to
build from, and both a from-scratch shader and a from-scratch Lottie
integration are pure visual work with no way to confirm they render
correctly in this environment. See
`boringNotch/managers/MotionArtController.swift`.

## F-14 — Universal launcher: shipped, apps + actions only, no files

Matches the plan's own scope guard ("apps + files + in-app actions. This is
not Raycast.") minus files. File search needs either `NSMetadataQuery`
(no prior art in this codebase to confirm it behaves as expected under this
app's sandbox) or broad filesystem access this app isn't entitled to.
Installed-app discovery uses a direct scan of the standard application
directories instead of Spotlight, for the same reason. See
`boringNotch/managers/UniversalLauncherManager.swift`.

## F-24 — Meeting controls: shipped, indicator only, no mute/leave

Real per-app mute/leave via synthetic keystrokes needs the XPC helper's
`input` capability to support posting keystrokes into other apps — a
meaningfully larger and riskier addition than the passive "your mic is
live" indicator, which the plan itself calls worth shipping alone. See
`boringNotch/managers/MeetingManager.swift`.

## F-52 — Third-party extensions: ADR only, no code

Per the plan's own instruction ("Write an ADR before any code, and only if
people actually ask"). See `docs/adr/0001-third-party-extensions.md`.
