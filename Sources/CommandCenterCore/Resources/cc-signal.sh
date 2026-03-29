#!/usr/bin/env bash
# Command Center agent signal helper.
# Usage:
#   source cc-signal start   "Brief task description"  (sets CC_AGENT_ID in caller's env)
#   cc-signal done    "Brief task description"          (uses CC_AGENT_ID from env)
#   cc-signal waiting "Waiting for approval"            (agent paused, needs user action)
#
# Identity: one inbox JSON per agent session. The id file lives at
#   <workspaceRoot>/.cursor/command-center-agent-id
# where workspaceRoot is stable (Cursor env, or walk up to .cursor/.git), not raw pwd — so the same
# project does not spawn a new tile when the shell cwd moves between subfolders.

set -uo pipefail

INBOX="$HOME/.cursor/command-center-agents"
ENABLED="$INBOX/.enabled"

# If Command Center has been uninstalled, silently do nothing.
[[ -f "$ENABLED" ]] || { return 0 2>/dev/null || exit 0; }

ACTION="${1:-}"
DESC="${2:-Agent working}"
DESC="${DESC:0:60}"

_cc_now() { date -u +%Y-%m-%dT%H:%M:%S.000Z; }

# Canonical folder for this Cursor project (not necessarily the current shell cwd).
_cc_workspace_root() {
  if [[ -n "${CURSOR_WORKSPACE_ROOT:-}" && -d "${CURSOR_WORKSPACE_ROOT}" ]]; then
    (cd "${CURSOR_WORKSPACE_ROOT}" && pwd -P)
    return
  fi
  if [[ -n "${WORKSPACE_FOLDER:-}" && -d "${WORKSPACE_FOLDER}" ]]; then
    (cd "${WORKSPACE_FOLDER}" && pwd -P)
    return
  fi
  local dir start
  dir="$(pwd -P)"
  start="$dir"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.cursor" ]]; then
      printf '%s' "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  dir="$start"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]]; then
      printf '%s' "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  pwd -P
}

_cc_agent_id_file() {
  local root
  root="$(_cc_workspace_root)"
  printf '%s' "$root/.cursor/command-center-agent-id"
}

# Same id on every `start` without relying on a previous shell's CC_AGENT_ID.
_cc_resolve_agent_id() {
  local f
  f="$(_cc_agent_id_file)"
  mkdir -p "$(dirname "$f")"

  if [[ -f "$f" ]]; then
    local existing
    existing="$(tr -d '\n\r' <"$f" | tr -cd 'a-f0-9')"
    if [[ ${#existing} -ge 8 ]]; then
      if [[ ${#existing} -gt 32 ]]; then
        existing="${existing:0:32}"
      fi
      printf '%s' "$existing"
      return
    fi
  fi

  # Migrate id files created under a subdirectory cwd (older cc-signal behavior).
  local dir old existing
  dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    old="$dir/.cursor/command-center-agent-id"
    if [[ -f "$old" && "$old" != "$f" ]]; then
      existing="$(tr -d '\n\r' <"$old" | tr -cd 'a-f0-9')"
      if [[ ${#existing} -ge 8 ]]; then
        if [[ ${#existing} -gt 32 ]]; then
          existing="${existing:0:32}"
        fi
        printf '%s\n' "$existing" >"$f"
        printf '%s' "$existing"
        return
      fi
    fi
    dir="$(dirname "$dir")"
  done

  if [[ -n "${CURSOR_TRACE_ID:-}" ]]; then
    local hex
    hex="$(printf '%s' "$CURSOR_TRACE_ID" | tr -cd 'a-f0-9')"
    if [[ ${#hex} -ge 8 ]]; then
      if [[ ${#hex} -gt 32 ]]; then
        hex="${hex:0:32}"
      fi
      printf '%s\n' "$hex" >"$f"
      printf '%s' "$hex"
      return
    fi
  fi
  local new_id
  new_id="$(openssl rand -hex 8)"
  printf '%s\n' "$new_id" >"$f"
  printf '%s' "$new_id"
}

_cc_signal_workspace_path() {
  _cc_workspace_root
}

case "$ACTION" in
  start)
    export CC_AGENT_ID
    CC_AGENT_ID="$(_cc_resolve_agent_id)"
    if [[ -z "$CC_AGENT_ID" ]]; then
      CC_AGENT_ID="$(openssl rand -hex 4)"
    fi
    mkdir -p "$INBOX"
    cat > "$INBOX/${CC_AGENT_ID}.json" <<SIGNAL
{"schemaVersion":2,"agentTurnActive":true,"updatedAt":"$(_cc_now)","workspacePath":"$(_cc_signal_workspace_path)","taskDescription":"$DESC"}
SIGNAL
    ;;
  done)
    if [[ -z "${CC_AGENT_ID:-}" ]]; then
      echo "cc-signal: CC_AGENT_ID not set — did you 'source cc-signal start' first?" >&2
      return 1 2>/dev/null || exit 1
    fi
    local_now="$(_cc_now)"
    cat > "$INBOX/${CC_AGENT_ID}.json" <<SIGNAL
{"schemaVersion":2,"agentTurnActive":false,"updatedAt":"$local_now","lastResponseCompletedAt":"$local_now","workspacePath":"$(_cc_signal_workspace_path)","taskDescription":"$DESC"}
SIGNAL
    ;;
  waiting)
    if [[ -z "${CC_AGENT_ID:-}" ]]; then
      echo "cc-signal: CC_AGENT_ID not set — did you 'source cc-signal start' first?" >&2
      return 1 2>/dev/null || exit 1
    fi
    local_now="$(_cc_now)"
    cat > "$INBOX/${CC_AGENT_ID}.json" <<SIGNAL
{"schemaVersion":2,"agentTurnActive":false,"awaitingInput":true,"updatedAt":"$local_now","workspacePath":"$(_cc_signal_workspace_path)","taskDescription":"$DESC"}
SIGNAL
    ;;
  *)
    echo "Usage: source cc-signal start|done|waiting \"description\"" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac
