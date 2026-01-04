# Tickets

ralphs includes an integrated ticket system based on [wedow/ticket](https://github.com/wedow/ticket). Tickets are git-backed markdown files with YAML frontmatter.

Tickets are stored in a bare git repository (`.ralphs/tickets.git`) and cloned to each worktree for multi-agent synchronization. See [Sync & Distribution](#sync--distribution) below.

---

## Why Integrated?

Rather than bolting ticket management onto ralphs, we subsume it:

- **Single mental model** — `.ralphs/` is the whole system
- **Unified state machine** — One `state` field, not `status` vs `stage`
- **First-class hooks** — State transitions naturally trigger hooks
- **Cleaner implementation** — No impedance mismatch

The underlying `tk` CLI is vendored and available, but users interact via `ralphs ticket` commands.

---

## State Machine

```
┌─────────────┐    ┌─────────────┐    ┌──────────┐    ┌────────┐
│    ready    │───▶│ in-progress │───▶│  review  │───▶│   qa   │
└─────────────┘    └─────────────┘    └──────────┘    └────────┘
                          ▲               │              │
                          │               │              │
                          └───────────────┴──────────────┘
                                 (feedback)              │
                                                         ▼
                                                    ┌────────┐
                                                    │  done  │
                                                    └────────┘
```

### States

| State | Description | Typical Actor |
|-------|-------------|---------------|
| `ready` | Dependencies met, available for work | — |
| `in-progress` | Worker is actively working on ticket | Worker |
| `review` | Code review in progress | Reviewer agent |
| `qa` | Quality assurance/testing | QA agent |
| `done` | Completed, all validation passed | — |

### Transitions

| From | To | Trigger | Hook |
|------|----|---------|------|
| `ready` | `in-progress` | Worker assigned to ticket | `on-claim` |
| `in-progress` | `review` | Worker marks done | `on-in-progress-done` |
| `review` | `qa` | Reviewer approves | `on-review-done` |
| `review` | `in-progress` | Reviewer rejects | `on-review-rejected` |
| `qa` | `done` | QA passes | `on-qa-done` → `on-close` |
| `qa` | `in-progress` | QA fails | `on-qa-rejected` |

---

## Ticket Schema

```yaml
---
# Identity
id: tk-5c46
type: feature        # feature | bug | task | epic | chore
priority: 1          # 0 (highest) to 4 (lowest)

# State (unified)
state: in-progress

# Assignment
assigned_pane: worker-0
assigned_at: 2025-07-14T10:30:00Z

# Dependencies
depends_on:
  - tk-3a1b
blocks:
  - tk-9f3c

# Metadata
created_at: 2025-07-14T09:00:00Z
created_by: supervisor
---

# Implement auth middleware

## Description

Add JWT-based authentication middleware to the API routes.

## Acceptance Criteria

- [ ] Middleware validates JWT tokens
- [ ] Invalid tokens return 401
- [ ] Token payload available in request context

## Feedback

### From Review (2025-07-14 14:30)

- Missing rate limiting on auth endpoints
- Add test for expired token case

## Notes

Implementation started with src/middleware/auth.ts
```

---

## Dependencies

Tickets can declare dependencies:

```yaml
depends_on:
  - tk-3a1b    # This ticket needs tk-3a1b done first
blocks:
  - tk-9f3c    # tk-9f3c is waiting on this ticket
```

A ticket is `ready` only when all `depends_on` tickets are `done`.

Query blocked/ready tickets:

```bash
ralphs ticket ready      # Show tickets available to claim
ralphs ticket blocked    # Show tickets waiting on dependencies
ralphs ticket tree tk-5c46   # Show dependency tree
```

---

## Feedback Injection

When review or QA fails, feedback is appended to the ticket:

```yaml
## Feedback

### From Review (2025-07-14 14:30)

- Missing rate limiting on auth endpoints
- Add test for expired token case
```

The ticket state returns to `in-progress`, and the assigned worker is pinged:

```bash
# Happens automatically via hook
tmux send-keys -t worker-0 "# Review feedback added. Please address and re-submit." Enter
```

The worker's next loop reads the ticket, sees feedback, addresses it.

---

## Ticket CLI

All ticket operations go through `ralphs ticket`:

```bash
# Create
ralphs ticket create "Title" [--type TYPE] [--priority N] [--dep ID]

# Query
ralphs ticket list              # All tickets
ralphs ticket ready             # Ready to claim
ralphs ticket blocked           # Blocked by dependencies
ralphs ticket show <id>         # Full ticket details
ralphs ticket tree <id>         # Dependency tree

# State transitions
ralphs ticket claim <id>        # Mark in-progress (usually by worker)
ralphs ticket transition <id> <state>   # Explicit state change

# Edit
ralphs ticket edit <id>         # Open in $EDITOR
ralphs ticket feedback <id> <source> <message>   # Append feedback

# Sync (for distributed mode)
ralphs ticket sync              # Pull + push
ralphs ticket sync --pull       # Pull only
ralphs ticket sync --push       # Push only

# Partial ID matching
ralphs ticket show 5c4          # Matches tk-5c46
```

---

## File Format

Tickets are markdown with YAML frontmatter. This enables:

- **Human readability** — Edit in any text editor
- **Git tracking** — Full history, diffs, blame
- **Agent accessibility** — Easy to parse and update
- **IDE integration** — Click ticket IDs in commit messages to jump to files

---

## Sync & Distribution

Tickets are stored in a separate git repository for multi-agent synchronization.

### Architecture

```
.ralphs/
├── tickets.git/          ← bare repo (origin)
│   └── hooks/            ← pre-receive, post-receive
└── tickets/              ← clone (for CLI access)

worktrees/
├── worker-0/.ralphs/tickets/    ← clone
└── reviewer-0/.ralphs/tickets/  ← clone
```

All agents (including supervisor) have their own clone. They push/pull to the bare repo.

### Push Flow

```
agent edits ticket → commits → pushes
                                 ↓
                         pre-receive validates state transition
                                 ↓
                         post-receive triggers hooks (spawn reviewer, etc.)
```

### Auto-Sync

Ticket commands auto-sync by default:
- **Read ops** (`show`, `list`, `ready`) — pull first
- **Write ops** (`create`, `transition`, `feedback`) — pull, act, push

Disable with `RALPHS_AUTO_SYNC=false` or `--no-sync` flag.

### Manual Sync

```bash
ralphs ticket sync              # Pull + push
ralphs ticket sync --pull       # Pull only
ralphs ticket sync --push       # Push only
```

### Conflict Resolution

Most conflicts auto-resolve via rebase (agents edit different tickets). If rebase fails:
1. Worker sees warning: "Ticket sync conflict"
2. Resolve manually: `git -C .ralphs/tickets rebase --continue`

The bare repo uses `*.md merge=union` to append conflicting additions.

### Concurrent Transitions

If two agents try to transition the same ticket:
1. First push succeeds, hooks fire
2. Second push rejected by pre-receive (state already changed)
3. Second agent pulls, sees new state, adjusts
