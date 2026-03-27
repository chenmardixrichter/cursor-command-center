# Command Center — product definition & constraints

This document states what Command Center is meant to be, how that differs from earlier “webhook on every answer” ideas, what the app and extension already lean on, and why **idle / thinking / done** is hard to make perfectly accurate without deeper Cursor integration. It also specifies a **confidence-ranked signal hierarchy** so status stays useful when windows are **hidden or minimized**.

---

## 1. Product vision (authoritative)

### What we’re building

A **Command Center** macOS app that:

1. **Automatically discovers** all open Cursor **windows / agents** (no explicit signup or registration step).
2. Shows each one **live** with a simple status: **idle**, **thinking**, or **done**.
3. Lets the user **click** a row or tile to **open / focus** that Cursor window.
4. Lets the user **change the display name** for an entry (local override; does not rename anything inside Cursor).
5. Lets the user **remove an entry from Command Center** — meaning **hide / dismiss** from this dashboard (not necessarily terminating a remote agent). Hidden items may reappear when the same workspace opens again, unless we add stronger “ignore” semantics later.

That is the core product. **No** requirement in this vision for webhooks, n8n, or “ping an external service on every assistant reply.” Those were exploratory directions and are **out of scope** unless explicitly revived.

### Non-goals (for this definition)

- Replacing Cursor’s own UI for chat or agent management.
- Guaranteeing pixel-perfect parity with Cursor’s internal “thinking” state without Cursor exposing a stable API.
- Cloud-only or IDE-only exclusivity — discovery may combine **local windows** with other signals where useful, but the **UX** is one list.

---

## 2. Status model: idle, thinking, done

| State      | User-facing meaning |
|-----------|----------------------|
| **Idle**  | No strong signal that the agent is actively working in that window. |
| **Thinking** | Something indicates active work (see **aggregated signals** in §3). |
| **Done**  | A turn or burst of work has **settled**; show a clear “completed” beat (e.g. green glow) before decaying to idle (see §4). |

**Engineering note:** Local Composer/chat status is limited by **what we can observe** from outside Cursor. The **confidence ladder** in §3 keeps the UI accurate when windows are not on screen.

---

## 3. Aggregated signal hierarchy (“confidence score”)

To keep Command Center accurate when windows are **hidden or minimized**, use a **fallback stack**. Higher tiers override lower ones when available; lower tiers apply when UI inspection is impossible.

### 3.1 Active signal — **high confidence**

| | |
|--|--|
| **Method** | **Accessibility API** (`AXUIElement`). |
| **When** | Window is **visible** or **covered** by another window — but **not minimized**. |
| **Logic** | If a **Stop / Cancel** control exists (Composer/agent cancel), treat as **Thinking**. |

### 3.2 Background signal — **medium confidence**

| | |
|--|--|
| **Method** | **FSEvents** (file system watching). |
| **When** | Window is **minimized** (AX “Stop” may be unreachable or invisible). |
| **Logic** | Cursor often writes to **User/Global Storage** or the workspace **`.cursor`** tree during generation. **Timestamped** write bursts → **Thinking**. |

### 3.3 Pulse signal — **low confidence**

| | |
|--|--|
| **Method** | Process sampling (e.g. `ps`, or structured sampling of **Cursor Helper (Plugin)** tied to the window’s PID context). |
| **When** | **All else fails** — no reliable AX, weak or ambiguous FS activity. |
| **Logic** | If **CPU stays above a baseline** (e.g. **5%**) for **more than ~2 seconds**, assume **activity** → lean **Thinking** (with low confidence / optional UI hint). |

**Implementation note:** The user spec referenced “NSPromise”; interpret as **async sampling / timers** — the idea is **sustained** CPU over a short window, not a single spike.

---

## 4. Thinking → Done vs Idle (timeout gate)

The hardest transition is **Thinking → Done**, especially when **minimized**: you cannot see the Stop button disappear.

### Timeout gate (when AX is unavailable)

| Step | Rule |
|------|------|
| **Event** | **File system activity stops** (no meaningful writes in the watched paths for a short grace period) **and** **CPU drops** below the pulse baseline. |
| **Action** | Move to **Done** (visual: **green glow** or equivalent). |
| **Decay** | After **~60 seconds** with **no new Thinking signals**, transition **Done → Idle**. |

Tune grace periods and the 60s decay in Settings if needed; document them as **heuristic defaults**.

---

## 5. Refined discovery data structure

To support **renaming** and **hiding** entries, the internal model should be stable and keyed by workspace, not only by volatile window id.

| Field | Source | Purpose |
|-------|--------|---------|
| `windowID` | `CGWindowListCopyWindowInfo` | Volatile id for **focus / raise** operations. |
| `workspacePath` | `mdfind`, AppleScript, or path resolution from window title | **Stable unique key** for nicknames, hidden flags, and per-workspace prefs. |
| `lastSignal` | System events / aggregation layer | Timestamp of the last **Thinking**-class indicator. |
| `status` | Combined heuristic | **Idle / Thinking / Done** (machine state + optional confidence metadata). |

---

## 6. “Stealth” strategy: AppleScript (minimized windows)

If you want to **avoid relying solely** on the fragile extension API, **AppleScript** against Cursor is often robust for **minimized** windows: you can read **window names without un-minimizing**.

Example:

```applescript
tell application "Cursor"
    set windowNames to name of every window
end tell
```

**Insight:** During Composer flows, Cursor may **append status text** to the window title or change the **proxy icon**. If you can detect a **consistent string pattern** in `name of window` over time, that becomes a **Thinking**-class signal that works **even when the window is only in the Dock** — complementing FSEvents and CPU.

---

## 7. Other layers (extension, cloud)

These are **additional** inputs, not replacements for §3–6:

| Approach | Role |
|----------|------|
| **Window discovery** | `CGWindowListCopyWindowInfo`; bundle id; focus via `NSRunningApplication` + AppleScript. |
| **Cursor extension** (`command-center-agent-signal`) | Local files / command hints — **high value when stable**, version-sensitive. |
| **Cursor Cloud Agents API** | Polling cloud jobs when API key is set — **cloud** lifecycle, not local Composer. |

Fold extension signals into **high confidence** when they match a window/workspace.

---

## 8. Why some signals are weak or misleading

| Issue | Consequence |
|-------|-------------|
| Side-channel heuristics ≠ “assistant finished” | CPU idle does not guarantee the reply is rendered; user typing can look like activity. |
| Extension hooks without a public contract | Commands and internals can change; some listeners **false-positive**. |
| **Minimized** windows | AX Stop button may be unusable — **§3.2–3.3 + §4 + §6** exist to fill the gap. |

**Bottom line:** The **ideal** fix remains **first-class Cursor events** for local turn completion (see §9). Until then, the **confidence ladder** + **timeout gate** is the intended product behavior.

---

## 9. What’s still missing for “perfect” local status

1. **Stable semantics from Cursor** — documented extension or host events for **turn/message lifecycle**, versioned and testable.
2. **Clear mapping** — one row per window vs. workspace vs. cloud job when they overlap.
3. **Product policy for “remove”** — persist hidden workspace IDs, “reset hidden list,” optional decay.

---

## 10. Optional future directions (not current requirements)

- Webhooks / n8n **after** a reliable completion event exists.
- User-defined ping URLs per workspace (with spam-safe rules).

---

## 11. Related files in this repo

- `README.md` — build, permissions, high-level architecture.
- `docs/COMMAND_CENTER_TEST_PLAN.md` — testing notes.
- `cursor-extension/command-center-agent-signal/` — VS Code/Cursor extension that augments local signals.

---

*Last updated: aggregated signal hierarchy, timeout gate, discovery model, AppleScript stealth; cross-reference with implementation.*
