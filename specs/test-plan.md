# Test Plan: Recent Fixes

This document enumerates test cases for the fixes in commit e5afc88.

---

## 1. JSON Parsing in `cmd_list`

### Covered Functionality
- `cmd_list` parses `.ralphs/panes.json` to display active panes

### Test Cases

| ID | Description | Input | Expected |
|----|-------------|-------|----------|
| 1.1 | Empty registry | `[]` | Empty table, no errors |
| 1.2 | Single pane | `[{"pane": "worker-0", "role": "worker", "ticket": "tk-1234", "started_at": "..."}]` | One row displayed |
| 1.3 | Multiple panes | Array with 3+ entries | All rows displayed |
| 1.4 | Missing optional fields | Entry with empty `ticket` | Shows "—" for ticket |
| 1.5 | Malformed JSON | `[{broken` | Graceful error or warning |
| 1.6 | No jq installed | Disable jq | Falls back to grep-based parsing |
| 1.7 | Special characters in pane name | `pane: "impl-foo_bar"` | Displayed correctly |

---

## 2. `get_next_pane_index` Double-Echo Bug

### Covered Functionality
- Returns next available index for a role (0, 1, 2...)
- Used to generate unique pane names like `worker-0`, `worker-1`

### Test Cases

| ID | Description | Input | Expected |
|----|-------------|-------|----------|
| 2.1 | No registry file | File doesn't exist | Returns `0` |
| 2.2 | Empty registry | `[]` | Returns `0` |
| 2.3 | No matching role | Registry has `supervisor-0`, query `worker` | Returns `0` |
| 2.4 | One matching role | One `worker` entry | Returns `1` |
| 2.5 | Multiple matching | Three `worker` entries | Returns `3` |
| 2.6 | No newlines in output | Any input | Output is single line, no `\n` |

---

## 3. Prompt Loading and Composition

### Covered Functionality
- `build_agent_prompt()` loads role templates
- Substitutes `{TICKET_ID}`, `{TICKET_CONTENT}`, etc.
- Writes to `.ralphs/current_prompt.md`

### Test Cases

| ID | Description | Input | Expected |
|----|-------------|-------|----------|
| 3.1 | Supervisor role | `role=supervisor` | Loads `supervisor.md`, substitutes `{PROJECT_SPECS}` |
| 3.2 | Worker role | `role=worker` | Loads `worker.md` |
| 3.3 | Reviewer role | `role=reviewer` | Loads `reviewer.md` |
| 3.4 | With ticket | `ticket_id=tk-1234` | Reads ticket, substitutes `{TICKET_CONTENT}` |
| 3.5 | Without ticket | `ticket_id=""` | No ticket substitution |
| 3.6 | Missing template | No `foobar.md` exists | Returns minimal fallback prompt |
| 3.7 | Template in defaults | User hasn't customized | Uses `$RALPHS_DEFAULTS/prompts/` |
| 3.8 | Template in project | User has `.ralphs/prompts/foo.md` | Uses project version |
| 3.9 | Feedback in ticket | Ticket has `## Feedback` section | Extracted into `{FEEDBACK}` |
| 3.10 | Prompt file created | After spawn | `.ralphs/current_prompt.md` exists in worktree |

---

## 4. Vim Mode Detection and `send_pane_input`

### Covered Functionality
- Auto-detects `editorMode` from `~/.claude.json`
- Only checks Claude config when `RALPHS_AGENT_CMD` is `claude`
- Sends Escape + i + text + Enter for vim mode

### Test Cases

| ID | Description | Setup | Expected |
|----|-------------|-------|----------|
| 4.1 | Claude with vim mode | `~/.claude.json` has `"editorMode": "vim"` | `RALPHS_EDITOR_MODE=vim` |
| 4.2 | Claude with normal mode | `"editorMode": "normal"` | `RALPHS_EDITOR_MODE=normal` |
| 4.3 | Claude no editorMode | No field in config | `RALPHS_EDITOR_MODE=normal` |
| 4.4 | Claude no config file | `~/.claude.json` doesn't exist | `RALPHS_EDITOR_MODE=normal` |
| 4.5 | Non-claude agent | `RALPHS_AGENT_CMD=amp` | Skips Claude config check |
| 4.6 | Explicit override | `RALPHS_EDITOR_MODE=vim` set before load_config | Uses explicit value |
| 4.7 | Vim mode key sequence | vim mode + message "hello" | Sends: Esc, i, "hello", Enter |
| 4.8 | Normal mode key sequence | normal mode + message | Sends: "hello", Enter |
| 4.9 | Literal text | Message with special chars `$foo` | Sent literally via `-l` flag |

---

## 5. Worktree Support

### Covered Functionality
- `get_main_project_root()` returns main project, not worktree
- Config loaded from main project's `.ralphs/config.sh`
- Pane registry at main project's `.ralphs/panes.json`
- Session name derived from main project directory

### Test Cases

| ID | Description | CWD | Expected |
|----|-------------|-----|----------|
| 5.1 | Main project | `/proj` | `MAIN_PROJECT_ROOT=/proj` |
| 5.2 | Worktree | `/proj/worktrees/worker-0` | `MAIN_PROJECT_ROOT=/proj` |
| 5.3 | Nested worktree path | `/proj/worktrees/worker-0/src` | `MAIN_PROJECT_ROOT=/proj` |
| 5.4 | Session from worktree | In worktree | Session = `ralphs-<proj-basename>` |
| 5.5 | Config from worktree | In worktree | Loads `/proj/.ralphs/config.sh` |
| 5.6 | Panes.json from worktree | `ralphs list` in worktree | Reads `/proj/.ralphs/panes.json` |
| 5.7 | Spawn from worktree | `ralphs spawn worker tk-xxx` | Creates worktree under `/proj/worktrees/` |
| 5.8 | Tickets per-worktree | Worktree `.ralphs/tickets/` | Each worktree has own tickets clone |
| 5.9 | Hooks from main | Hook triggered in worktree | Uses `/proj/.ralphs/hooks/` |
| 5.10 | Prompts from main | Spawn in worktree | Uses `/proj/.ralphs/prompts/` |

---

## Integration Tests

| ID | Description | Steps | Expected |
|----|-------------|-------|----------|
| I.1 | Full spawn cycle | init → create ticket → spawn worker → verify | Agent running with prompt, pane registered |
| I.2 | Supervisor orchestration | Spawn supervisor → let it spawn worker | Worker spawned for ready ticket |
| I.3 | Cross-worktree visibility | Spawn from main, list from worktree | Same pane list |
| I.4 | Vim mode end-to-end | Enable vim, spawn, ping | All inputs work correctly |

---

## Edge Cases & Error Handling

| ID | Description | Expected |
|----|-------------|----------|
| E.1 | No tmux session | `ralphs list` → "Session not found" |
| E.2 | Corrupted panes.json | Graceful error, not crash |
| E.3 | Permission denied on files | Helpful error message |
| E.4 | Git worktree add fails | Handles gracefully, reports error |
| E.5 | Agent command not found | Error before pane creation |
