# Command Center — Agent turn signal

Writes `.cursor/command-center-agent-signal.json` in the **workspace root** so the macOS **Command Center** app can show `thinking` while your message is queued or the agent is still on that turn.

## Install (Cursor / VS Code)

1. `npm install && npm run compile`
2. Command Palette → **Developer: Install Extension from Location…** (or **Install from Folder…**) and choose this directory (`command-center-agent-signal`).

## Behavior (v0.2)

- **No chat document listeners** — those fired on *your* typing and caused false “thinking.”
- **Heartbeat** (~8s) only while the signal is active (keeps Command Center’s 45s TTL fresh).
- **Submit / cancel:** if `onDidExecuteCommand` exists, best-effort match on command IDs; **submit** arms a **120s** auto-clear (there is no stable public “reply finished” event without false positives).
- **Commands:** *Mark agent turn active (test)* (auto-clears after 10 min) / *Clear agent turn signal*.

**Reality check:** Without an official Cursor API for “agent turn,” this cannot be perfect. Command Center defaults to **extension-only** thinking (CPU inference off).

## Map Cursor’s real command IDs (v0.2.2)

1. **Reload** after installing (**⌘⇧P** → **Developer: Reload Window**). Read the **first line** in the log: it must say `onDidExecuteCommand hook: YES`. If it says **NO**, Cursor is not exposing executed commands to extensions — we cannot capture Send/Stop ids this way.
2. If the **Output** panel looks empty, open **`.cursor/command-center-command-log.txt`** (same content) via **⌘⇧P** → **Command Center: Open command log file**.
3. **Toggle command logging** ON. Optionally set **`logOnlyLikelyChat`** to **false** to log every command (noisy).
4. Send a chat message, Stop, Cancel, etc. Lines look like `[time] some.command.id`.
5. Copy ids that match your actions into `src/extension.ts` (or paste here).

**Command Center: Show command log** opens the Output channel without toggling.

## Completion chime vs Command Center (v0.2.4)

Cursor can play a sound when a reply finishes (`cursor.composer.shouldChimeAfterChatFinishes`). The macOS app **cannot** detect audio. Instead, add **exact command ids** that run at that moment to **Settings → Command Center agent signal → Completion command ids** (`commandCenterAgentSignal.completionCommandIds`). Discover ids with **command logging**: run a full reply, find the line logged when the response completes, paste the id into the array. The extension then writes **`lastResponseCompletedAt`** (ISO time) so Command Center can show **Done** without hearing anything. You can leave the Cursor volume at 0 if you only want the signal path.

## File format

```json
{
  "schemaVersion": 1,
  "agentTurnActive": true,
  "updatedAt": "2025-03-25T12:00:00.000Z",
  "lastResponseCompletedAt": "2025-03-25T12:00:05.000Z"
}
```

`lastResponseCompletedAt` is optional — set when a configured “reply finished” command runs.

Add `.cursor/command-center-agent-signal.json` to `.gitignore` if you do not want it in git.
