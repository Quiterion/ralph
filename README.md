# wiggum: Multi-Agent Orchestration Harness

**Version:** 0.1.0-draft
**Lineage:** Evolved from [Classic Ralph](../ralph_classic.md)

---

## What is wiggum?

`wiggum` is a minimalist outer harness for orchestrating multiple coding agents. A single Ralph is unreliable, but a *family of Ralphs* —properly orchestrated—ships production code.

The harness is **thin glue** between:
- **tmux** — process lifecycle and observability
- **tickets** — git-backed task state and dependencies
- **hooks** — pipeline stages triggered by state transitions
- **tools** — summarization so supervisors stay context-light

All offered via a simple, agent-friendly CLI tool.

---

## Design Principles

### Inherited from Classic Ralph

1. **File-based state** — Tickets and specs are markdown. Human-readable, git-tracked, agent-accessible.

2. **Deterministic context loading** — Each agent loop loads the same stack: its ticket, relevant specs, role prompt.

3. **One task per agent** — Each agent focuses on exactly one ticket at its abstraction level.

4. **Backpressure through validation** — Code generation is cheap; validation gates progression.

5. **Eventual consistency** — Agents fail. Design for retry, rollback, recovery.

### New in wiggum

6. **Externalized orchestration** — Subagent spawning moves from inside the agent to the harness. Observable, controllable, survivable.

7. **Scope-relative tasks** — "One task" is fractal. Supervisor's task = epic. Worker's task = component. Inner subagents = functions.

8. **Summarization over raw data** — Supervisors invoke tools that return *insights*, not 10k tokens of trajectory logs. (See: [tools.md](./specs/tools.md))

9. **Pipeline as hooks** — Backpressure stages (in-progress → review → QA) encoded as hooks triggered by ticket state transitions.

10. **Agent-agnostic** — Works with any inner harness that can read files, write files, run shell commands.

---

## Quick Start

```bash
# Initialize wiggum in your project
wiggum init

# Create a ticket
wiggum ticket create "Implement auth middleware" --type feature

# Start the supervisor
wiggum spawn supervisor

# Watch the school work
wiggum status

# Attach to observe
wiggum attach
```

---

## Specification Documents

| Document | Description |
|----------|-------------|
| [architecture.md](./specs/architecture.md) | System diagram, component responsibilities |
| [tickets.md](./specs/tickets.md) | Ticket schema, states, lifecycle |
| [hooks.md](./specs/hooks.md) | Hook system, interface, examples |
| [tools.md](./specs/tools.md) | Summarization tools |
| [cli.md](./specs/cli.md) | Command reference |
| [prompts.md](./specs/prompts.md) | Agent role templates |

---

## Comparison with Classic Ralph

| Aspect | Classic Ralph | wiggum |
|--------|---------------|--------|
| Loop | Single bash while loop | Supervisor + worker panes |
| Subagents | Internal (black box) | External (tmux panes) for long work |
| State | fix_plan.md | Integrated ticket system |
| Backpressure | Single agent runs tests | Pipeline stages via hooks |
| Observability | Watch the stream | `wiggum status`, `wiggum fetch` |
| Recovery | git reset --hard | Per-ticket retry, rollback |
