import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

const FILE_NAME = "command-center-agent-signal.json";
const COMMAND_LOG_FILE = "command-center-command-log.txt";
const OUTPUT_NAME = "Command Center: command log";
/** After a detected chat submit, auto-clear if nothing else stops the turn (no reliable “stream ended” API without doc spam). */
const SUBMIT_AUTO_CLEAR_MS = 120_000;
/** Manual test command clears automatically so the file cannot stay true forever. */
const MANUAL_AUTO_CLEAR_MS = 10 * 60_000;

function workspaceRoot(): string | undefined {
  return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
}

function config(): vscode.WorkspaceConfiguration {
  return vscode.workspace.getConfiguration("commandCenterAgentSignal");
}

/** Plain Output channel + same lines appended to `.cursor/command-center-command-log.txt` (visible even if Output UI misbehaves). */
async function appendCommandLogLine(output: vscode.OutputChannel, line: string): Promise<void> {
  output.appendLine(line);
  const root = workspaceRoot();
  if (!root) {
    return;
  }
  const p = path.join(root, ".cursor", COMMAND_LOG_FILE);
  try {
    await fs.promises.mkdir(path.dirname(p), { recursive: true });
    await fs.promises.appendFile(p, line + "\n", "utf8");
  } catch {
    /* ignore disk errors */
  }
}

/** When “only likely chat” is on, skip unrelated commands (typing, file ops, …). */
function shouldLogCommandId(command: string, onlyLikely: boolean): boolean {
  if (!onlyLikely) {
    return true;
  }
  const c = command.toLowerCase();
  return (
    c.includes("chat") ||
    c.includes("composer") ||
    c.includes("cursor") ||
    c.includes("aichat") ||
    c.includes("agent") ||
    c.includes("copilot") ||
    c.includes("inline") ||
    c.includes("cline") ||
    c.includes("ask") ||
    c.includes("prompt") ||
    c.includes("submit") ||
    c.includes("cancel") ||
    c.includes("abort") ||
    c.includes("stop")
  );
}

async function writeSignalFile(root: string, payload: Record<string, unknown>): Promise<void> {
  const dir = path.join(root, ".cursor");
  await fs.promises.mkdir(dir, { recursive: true });
  const file = path.join(dir, FILE_NAME);
  await fs.promises.writeFile(file, JSON.stringify(payload, null, 2), "utf8");
}

/** Core agent-turn flag; omits `lastResponseCompletedAt` so a new turn or stop does not leave a stale completion ping. */
async function writeSignal(active: boolean): Promise<void> {
  const root = workspaceRoot();
  if (!root) {
    vscode.window.showWarningMessage("Command Center signal: open a folder workspace first.");
    return;
  }
  await writeSignalFile(root, {
    schemaVersion: 1,
    agentTurnActive: active,
    updatedAt: new Date().toISOString(),
  });
}

/**
 * Same moment Cursor uses for the optional completion chime (`cursor.composer.shouldChimeAfterChatFinishes`).
 * Command Center reads `lastResponseCompletedAt` — no audio involved. Map real command ids via **Toggle command logging**.
 */
async function recordResponseCompleted(): Promise<void> {
  const root = workspaceRoot();
  if (!root) {
    return;
  }
  await writeSignalFile(root, {
    schemaVersion: 1,
    agentTurnActive: false,
    updatedAt: new Date().toISOString(),
    lastResponseCompletedAt: new Date().toISOString(),
  });
}

export function activate(context: vscode.ExtensionContext): void {
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let submitOrManualTimer: ReturnType<typeof setTimeout> | undefined;

  // Plain channel — avoid LogOutputChannel (`{ log: true }`) which can hide or format `appendLine` oddly in some hosts.
  const output = vscode.window.createOutputChannel(OUTPUT_NAME);

  const commandsWithExecuteHook = vscode.commands as typeof vscode.commands & {
    onDidExecuteCommand?: (listener: (command: string) => void) => vscode.Disposable;
  };
  const hookOk = typeof commandsWithExecuteHook.onDidExecuteCommand === "function";

  void appendCommandLogLine(
    output,
    `[${new Date().toISOString()}] Command Center extension v0.2.4 activated. onDidExecuteCommand hook: ${hookOk ? "YES" : "NO — nothing will log"}`,
  );

  const clearDeadline = () => {
    if (submitOrManualTimer) {
      clearTimeout(submitOrManualTimer);
      submitOrManualTimer = undefined;
    }
  };

  const armDeadline = (ms: number) => {
    clearDeadline();
    submitOrManualTimer = setTimeout(() => {
      submitOrManualTimer = undefined;
      startHeartbeat(false);
      void writeSignal(false);
    }, ms);
  };

  const startHeartbeat = (active: boolean) => {
    if (heartbeat) {
      clearInterval(heartbeat);
      heartbeat = undefined;
    }
    if (!active) {
      return;
    }
    heartbeat = setInterval(() => {
      void writeSignal(true);
    }, 8000);
  };

  context.subscriptions.push(
    vscode.commands.registerCommand("commandCenterAgentSignal.setTurnActive", async () => {
      await writeSignal(true);
      startHeartbeat(true);
      armDeadline(MANUAL_AUTO_CLEAR_MS);
      void vscode.window.showInformationMessage("Command Center signal: turn active (clears automatically after 10 min or use Clear).");
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("commandCenterAgentSignal.clearTurn", async () => {
      clearDeadline();
      startHeartbeat(false);
      await writeSignal(false);
      void vscode.window.showInformationMessage("Command Center signal: cleared.");
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("commandCenterAgentSignal.showCommandLog", () => {
      output.show(true);
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("commandCenterAgentSignal.openCommandLogFile", async () => {
      const root = workspaceRoot();
      if (!root) {
        void vscode.window.showWarningMessage("Open a folder workspace first.");
        return;
      }
      const p = path.join(root, ".cursor", COMMAND_LOG_FILE);
      const uri = vscode.Uri.file(p);
      try {
        await fs.promises.mkdir(path.dirname(p), { recursive: true });
        if (!fs.existsSync(p)) {
          await fs.promises.writeFile(p, "", "utf8");
        }
      } catch {
        /* ignore */
      }
      await vscode.window.showTextDocument(uri);
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("commandCenterAgentSignal.toggleCommandLogging", async () => {
      const cfg = config();
      const cur = cfg.get<boolean>("logExecutedCommands", false);
      await cfg.update("logExecutedCommands", !cur, vscode.ConfigurationTarget.Global);
      output.show(true);
      await appendCommandLogLine(output, "");
      await appendCommandLogLine(
        output,
        `--- command logging ${!cur ? "ON" : "OFF"} (${new Date().toISOString()}) ---`,
      );
      await appendCommandLogLine(
        output,
        !cur
          ? "Also open: .cursor/command-center-command-log.txt (Command Center: Open command log file). Send chat / stop / cancel."
          : "Logging paused.",
      );
    }),
  );

  if (hookOk) {
    const disposable = commandsWithExecuteHook.onDidExecuteCommand!((command: string) => {
      const cfg = config();
      if (cfg.get<boolean>("logExecutedCommands")) {
        const onlyLikely = cfg.get<boolean>("logOnlyLikelyChat", true);
        if (shouldLogCommandId(command, onlyLikely)) {
          void appendCommandLogLine(output, `[${new Date().toISOString()}] ${command}`);
        }
      }

      const c = command.toLowerCase();
      if (
        c.includes("submit") &&
        (c.includes("chat") || c.includes("aichat") || c.includes("composer") || c.includes("cursor"))
      ) {
        void writeSignal(true);
        startHeartbeat(true);
        armDeadline(SUBMIT_AUTO_CLEAR_MS);
      }
      if (
        (c.includes("cancel") || c.includes("abort")) &&
        (c.includes("chat") || c.includes("composer") || c.includes("cursor") || c.includes("aichat"))
      ) {
        clearDeadline();
        startHeartbeat(false);
        void writeSignal(false);
      }
      // Stop / interrupt generation — clears turn without waiting for the 120s submit timeout.
      if (
        c.includes("stop") &&
        !c.includes("stopwatch") &&
        !c.includes("non-stop") &&
        (c.includes("chat") || c.includes("composer") || c.includes("cursor") || c.includes("aichat"))
      ) {
        clearDeadline();
        startHeartbeat(false);
        void writeSignal(false);
      }

      const completionIds = cfg.get<string[]>("completionCommandIds", []);
      if (completionIds.length > 0 && completionIds.includes(command)) {
        clearDeadline();
        startHeartbeat(false);
        void recordResponseCompleted();
      }
    });
    context.subscriptions.push(disposable);
  } else {
    void vscode.window.showWarningMessage(
      "Command Center: onDidExecuteCommand not available — command logging and submit hooks will not run in this host.",
    );
  }

  context.subscriptions.push(output);

  context.subscriptions.push({
    dispose: () => {
      clearDeadline();
      if (heartbeat) {
        clearInterval(heartbeat);
        heartbeat = undefined;
      }
    },
  });
}

export function deactivate(): void {}
