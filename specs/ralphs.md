# ralphs: Multi-Agent Orchestration Harness

**Version:** 0.1.0-draft
**Status:** Specification
**Lineage:** Evolved from [Classic Ralph](./ralph_classic.md)

---

## Overview

`ralphs` is a minimalist outer harness for orchestrating multiple coding agents. It combines:

- **tmux** for process lifecycle and observability
- **ticket** for git-backed task state and dependencies
- **Shell scripts** for glue (no daemons, no databases)

The philosophy: a single ralph is unreliable, but a *school* of ralphs—properly orchestrated—ships production code.

## Design Principles

### Inherited from Classic Ralph

1. **File-based state** — Specs, plans, and tickets are markdown files. Human-readable, git-tracked, agent-accessible.

2. **Deterministic stack loading** — Each agent loop loads the same context: its ticket, relevant specs, and role prompt.

3. **One task per agent** — Each agent focuses on exactly one ticket at its abstraction level.

4. **Backpressure through validation** — Code generation is cheap; validation (tests, review, QA) gates progression.

5. **Eventual consistency** — Accept that agents fail. Design for retry, rollback, and recovery.

### New in ralphs

6. **Externalized orchestration** — Subagent spawning moves from inside the agent to the harness. Observable, controllable, survivable.

7. **Scope-relative tasks** — "One task" is fractal. A supervisor's task is an epic; a worker's task is a component; inner subagents handle functions.

8. **Summarization over raw data** — Supervisors invoke tools that return insights, not 10k tokens of trajectory logs.

9. **Pipeline as hooks** — Backpressure stages (implement → review → QA) are encoded as git-style hooks triggered by ticket state transitions.

10. **Agent-agnostic** — The harness works with any inner agent that can read files, write files, and run shell commands.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        tmux session                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ window: main                                              │  │
│  │  ┌─────────────┬─────────────┬─────────────┬───────────┐  │  │
│  │  │ pane 0      │ pane 1      │ pane 2      │ pane 3    │  │  │
│  │  │ supervisor  │ impl-0      │ impl-1      │ review-0  │  │  │
│  │  │             │ tk-5c46     │ tk-8a2b     │ tk-5c46   │  │  │
│  │  └─────────────┴─────────────┴─────────────┴───────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      .tickets/                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ tk-5c46  │  │ tk-8a2b  │  │ tk-9f3c  │  │ tk-epic  │        │
│  │ stage:   │  │ stage:   │  │ stage:   │  │ children:│        │
│  │ review   │  │ impl     │  │ ready    │  │ 5c46,8a2b│        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      .ralphs/hooks/                             │
│  post-claim │ post-complete │ post-review │ post-close          │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| **tmux** | Process isolation, pane lifecycle, attach/detach, log capture |
| **ticket** | Task state, dependencies, stage tracking, queries (`tk ready`, `tk blocked`) |
| **hooks** | Trigger pipeline stages on ticket transitions |
| **tools** | Summarization, feedback injection, context building |
| **prompts** | Role-specific agent instructions |

---

## Supervisor Model

The supervisor is a **high-level scheduler**, not a processor. It:

- Queries ticket state (`tk ready`, `tk blocked`)
- Spawns workers into panes
- Invokes summarization tools to understand progress
- Makes decisions: retry, escalate, continue, intervene

The supervisor **does not**:

- Read raw agent trajectories
- Parse build logs directly
- Make low-level engineering decisions

### Supervisor Loop (Conceptual)

```bash
while :; do
  # Check worker status via summarization tools
  for pane in $(ralphs list-workers); do
    summary=$(ralphs fetch $pane)
    # Decide based on summary, not raw output
  done

  # Spawn new workers for ready tickets
  for ticket in $(tk ready --limit 3); do
    if ralphs has-capacity; then
      ralphs spawn impl $ticket
    fi
  done

  sleep $POLL_INTERVAL
done
```

---

## Worker Lifecycle

```
┌─────────┐     ┌───────────┐     ┌────────┐     ┌────────┐
│  spawn  │────▶│  working  │────▶│  done  │────▶│  hook  │
└─────────┘     └───────────┘     └────────┘     └────────┘
                     │                                │
                     ▼                                ▼
                ┌─────────┐                    ┌───────────┐
                │  stuck  │                    │next stage │
                └─────────┘                    └───────────┘
                     │
                     ▼
              supervisor intervenes
```

### Worker Contract

A worker agent:

1. **Reads** its assigned ticket on startup
2. **Works** on the task described
3. **Updates** the ticket with progress/notes
4. **Signals completion** via `tk close <id>` or stage transition
5. **Addresses feedback** if ticket is reopened with comments

Workers don't know about other workers. They focus on their ticket.

---

## Feedback Loop

When a worker completes, the pipeline advances:

```
implement ──▶ review ──▶ qa ──▶ done
    ▲            │        │
    │            ▼        ▼
    └────── feedback ─────┘
```

### Feedback Injection

**Step 1: Annotate ticket** (durable, git-tracked)
```yaml
# .tickets/tk-5c46.md
---
status: open
stage: implement
---
## Task
Implement auth middleware

## Feedback from Review
- Missing rate limiting
- Edge case not covered in tests
```

**Step 2: Ping agent** (wake it up)
```bash
tmux send-keys -t impl-0 "# Review feedback added to your ticket. Please address." Enter
```

The agent's next loop reads the ticket, sees feedback, continues work.

---

## Ticket Schema Extensions

Standard `ticket` fields plus ralphs-specific:

```yaml
---
id: tk-5c46
type: feature
status: in_progress
priority: 1

# ralphs extensions
stage: implement          # implement | review | qa | done
assigned_pane: impl-0     # which pane is working this
depends_on:               # ticket dependencies
  - tk-3a1b
blocks:
  - tk-9f3c
---
```

### Stages

| Stage | Description |
|-------|-------------|
| `ready` | Dependencies met, can be claimed |
| `implement` | Worker actively implementing |
| `review` | Review agent examining changes |
| `qa` | QA agent validating |
| `done` | Closed, all validation passed |

---

## Hooks

Git-style hooks triggered by ticket state transitions. Located in `.ralphs/hooks/`.

| Hook | Trigger | Typical Use |
|------|---------|-------------|
| `post-claim` | Ticket claimed by worker | Log, notify |
| `post-complete` | Worker marks stage done | Spawn reviewer |
| `post-review-approved` | Review passes | Advance to QA |
| `post-review-rejected` | Review fails | Reopen for implementer |
| `post-qa-passed` | QA passes | Close ticket |
| `post-qa-failed` | QA fails | Reopen with feedback |
| `post-close` | Ticket closed | Cleanup, metrics |

### Hook Interface

Hooks receive context via environment variables:

```bash
#!/bin/bash
# .ralphs/hooks/post-complete

TICKET_ID="$1"
PANE_ID="$RALPHS_PANE"
STAGE="$RALPHS_STAGE"

case $STAGE in
  implement)
    # Spawn review agent
    ralphs spawn reviewer "$TICKET_ID"
    ;;
  review)
    # Spawn QA agent
    ralphs spawn qa "$TICKET_ID"
    ;;
  qa)
    # All done
    tk close "$TICKET_ID"
    ;;
esac
```

---

## Directory Structure

```
project/
├── .tickets/              # ticket storage (git-tracked)
│   ├── tk-5c46.md
│   └── tk-8a2b.md
├── .ralphs/
│   ├── config.sh          # harness configuration
│   ├── hooks/
│   │   ├── post-claim
│   │   ├── post-complete
│   │   └── ...
│   └── prompts/
│       ├── supervisor.md
│       ├── implementer.md
│       ├── reviewer.md
│       └── qa.md
├── specs/                 # project specifications
│   └── *.md
└── AGENT.md               # inner harness instructions
```

---

## CLI Reference

### Session Management

```bash
ralphs init [--session NAME]
    Initialize tmux session and .ralphs/ directory

ralphs attach
    Attach to existing ralphs session

ralphs teardown
    Kill session, cleanup state
```

### Worker Management

```bash
ralphs spawn <role> <ticket-id>
    Spawn agent in new pane
    Roles: supervisor, impl, reviewer, qa

ralphs list
    List active panes and their tickets

ralphs kill <pane-id>
    Kill specific worker pane

ralphs ping <pane-id> <message>
    Send message to worker (wake/notify)
```

### Status & Observability

```bash
ralphs status
    Overview: panes, tickets, pipeline state

ralphs fetch <pane-id>
    Get summarized progress for worker
    (Invokes summarization, returns insight not raw logs)

ralphs logs <pane-id> [--tail N]
    Raw pane output (for debugging)
```

### Ticket Integration

```bash
ralphs ready
    Alias for: tk ready (show claimable tickets)

ralphs blocked
    Alias for: tk blocked (show blocked tickets)
```

---

## Tools

Tools are invoked by the supervisor (or hooks) to avoid context pollution.

### fetch-worker-progress

Summarizes a worker's trajectory into actionable insight.

**Input:** pane-id
**Output:** ~100 token summary

```
Worker impl-0 (tk-5c46):
- Implemented auth middleware in src/middleware/auth.ts
- Added 3 test cases, all passing
- Ready for review
- No blockers noted
```

**Implementation:** Captures pane output, reads recent git diff, synthesizes via LLM call.

### fetch-ticket-context

Builds a briefing for an agent about to start work.

**Input:** ticket-id
**Output:** Ticket + dependencies + recent activity

### inject-feedback

Appends feedback to ticket and pings the assigned worker.

**Input:** ticket-id, feedback-text, source (reviewer/qa)
**Output:** Updated ticket, ping sent

---

## Configuration

`.ralphs/config.sh`:

```bash
# Session name
RALPHS_SESSION="ralphs-myproject"

# Max concurrent workers
RALPHS_MAX_WORKERS=4

# Poll interval for supervisor (seconds)
RALPHS_POLL_INTERVAL=10

# Inner harness command
RALPHS_AGENT_CMD="claude"  # or "amp", "aider", etc.

# Pane layout
RALPHS_LAYOUT="tiled"  # or "even-horizontal", "even-vertical"
```

---

## Example Session

```bash
# Initialize
$ ralphs init
Created tmux session: ralphs-myproject
Initialized .ralphs/

# Create some tickets
$ tk create "Implement auth middleware" --type feature
Created: tk-5c46

$ tk create "Implement rate limiting" --type feature --dep tk-5c46
Created: tk-8a2b

# Start supervisor
$ ralphs spawn supervisor
Spawned supervisor in pane 0

# Supervisor sees tk-5c46 is ready, spawns worker
# (automatic via supervisor loop)

# Check status
$ ralphs status
SESSION: ralphs-myproject
PANES:
  0: supervisor    (running)
  1: impl-0        tk-5c46 [implement]

TICKETS:
  tk-5c46  implement  impl-0    auth middleware
  tk-8a2b  blocked    -         rate limiting (needs tk-5c46)

# Worker completes, hook spawns reviewer
# ...

# Get progress summary
$ ralphs fetch impl-0
Worker impl-0 (tk-5c46):
- Implemented auth middleware
- Tests passing
- Marked ready for review

# Later: all done
$ ralphs status
TICKETS:
  tk-5c46  done       -         auth middleware
  tk-8a2b  implement  impl-1    rate limiting
```

---

## Future Considerations

- **Metrics/telemetry** — Track cycle times, failure rates, token usage
- **Web dashboard** — Real-time view of hive state
- **Distributed execution** — Workers on remote machines (tmux over SSH)
- **Priority scheduling** — Smarter work assignment based on priority/deadlines

---

## Appendix: Comparison with Classic Ralph

| Aspect | Classic Ralph | ralphs |
|--------|---------------|--------|
| Loop | Single bash while loop | Supervisor + worker panes |
| Subagents | Internal (black box) | External (tmux panes) |
| State | fix_plan.md | ticket system |
| Backpressure | Single agent runs tests | Pipeline stages via hooks |
| Observability | Watch the stream | `ralphs status`, `ralphs fetch` |
| Recovery | git reset --hard | Per-ticket retry, rollback |
