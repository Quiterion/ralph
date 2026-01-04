# Distributed Tickets

This document specifies the distributed ticket system for multi-agent parallel development.

## Overview

When multiple agents work in parallel (each in their own git worktree), they need a synchronized view of ticket state. This spec describes how tickets are stored in a separate git repository and synchronized across worktrees using git's native mechanisms.

## Architecture

```
proj/
├── .ralphs/
│   ├── tickets.git/              ← bare repo (origin), hooks live here
│   ├── config.sh
│   ├── hooks/
│   └── prompts/
├── .gitmodules                   ← defines tickets submodule
│
├── (main worktree - supervisor)
│   └── .ralphs/tickets/          ← submodule checkout, main branch
│
└── worktrees/
    ├── impl-0/
    │   └── .ralphs/tickets/      ← submodule checkout, impl-0 branch
    └── reviewer-0/
        └── .ralphs/tickets/      ← submodule checkout, reviewer-0 branch
```

### Key Principles

1. **Tickets repo is separate from project repo** - ticket churn doesn't pollute project history
2. **Bare repo is the origin** - lives at `.ralphs/tickets.git`, hooks enforce rules here
3. **Supervisor owns main branch** - authoritative state, merges worker updates
4. **Workers own feature branches** - push changes to their branch, supervisor merges
5. **Submodule per worktree** - each worktree has its own tickets checkout

## Project Identity

Projects are identified by a hash of their git remote URL (stable across machines) or absolute path (fallback):

```bash
get_project_id() {
    local remote
    remote=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)
    if [[ -n "$remote" ]]; then
        echo "$remote" | sha256sum | cut -c1-12
    else
        echo "$PROJECT_ROOT" | sha256sum | cut -c1-12
    fi
}
```

This ID is used for:
- Cross-project ticket isolation
- Potential future: central ticket index at `~/.claude/ralphs/`

## Initialization

### First-time init (creates supervisor)

```bash
ralphs init [--session NAME]
```

1. Create bare tickets repo at `.ralphs/tickets.git`
2. Install pre-receive and post-receive hooks on bare repo
3. Initialize submodule: `git submodule add ./.ralphs/tickets.git .ralphs/tickets`
4. Create initial commit in tickets repo (empty or with README)
5. Mark this worktree as supervisor in config
6. Create tmux session, etc. (existing behavior)

### Spawning workers (creates worktree + submodule checkout)

```bash
ralphs spawn <role> [--ticket ID]
```

1. Create project worktree: `git worktree add worktrees/<pane-name> -b <pane-name>`
2. Initialize submodule in worktree: `git -C worktrees/<pane-name> submodule update --init`
3. Create ticket branch for worker: `git -C worktrees/<pane-name>/.ralphs/tickets checkout -b <pane-name>`
4. Register pane, start agent, etc. (existing behavior)

## Synchronization

### Worker → Origin (push)

Workers commit and push their ticket changes to their own branch:

```bash
# In worker's .ralphs/tickets/
git add -A
git commit -m "Update tk-1234: implement → review"
git push origin impl-0
```

### Origin hooks validate and trigger

**pre-receive hook** (on `.ralphs/tickets.git`):
- Parses incoming ticket changes
- Validates state transitions against state machine
- Rejects invalid pushes with helpful error message
- Allows free-form body edits (only validates frontmatter)

**post-receive hook** (on `.ralphs/tickets.git`):
- Detects state transitions
- Triggers appropriate ralphs hooks (on-implement-done, etc.)
- Optionally notifies supervisor to merge

### Supervisor merges to main

Supervisor periodically (or on notification) merges worker branches:

```bash
# In supervisor's .ralphs/tickets/
git fetch origin
git merge origin/impl-0 --no-edit
git push origin main
```

Or automated via post-receive hook that signals supervisor.

### Worker ← Origin (pull)

Workers pull latest main before operations:

```bash
# In worker's .ralphs/tickets/
git fetch origin main
git rebase origin/main
```

## Ticket Commands with Git Plumbing

### Read operations (pull first)

```bash
ticket_show() {
    ticket_sync_pull
    # ... existing show logic ...
}

ticket_list() {
    ticket_sync_pull
    # ... existing list logic ...
}
```

### Write operations (pull, modify, push)

```bash
ticket_transition() {
    ticket_sync_pull

    # Validate and update state
    # ... existing transition logic ...

    ticket_sync_push "Transition $id: $old_state → $new_state"
}

ticket_create() {
    ticket_sync_pull

    # Create ticket file
    # ... existing create logic ...

    ticket_sync_push "Create ticket: $id"
}
```

### Sync helpers

```bash
ticket_sync_pull() {
    git -C "$TICKETS_DIR" fetch origin --quiet
    git -C "$TICKETS_DIR" rebase origin/main --quiet 2>/dev/null || {
        warn "Ticket sync conflict - please resolve manually"
        return 1
    }
}

ticket_sync_push() {
    local message="$1"
    git -C "$TICKETS_DIR" add -A
    git -C "$TICKETS_DIR" commit -m "$message" --quiet 2>/dev/null || true
    git -C "$TICKETS_DIR" push origin HEAD --quiet
}

ticket_sync() {
    # Manual full sync
    ticket_sync_pull
    ticket_sync_push "Manual sync"
}
```

## Supervisor Detection

```bash
is_supervisor() {
    load_config
    [[ "${RALPHS_IS_SUPERVISOR:-false}" == "true" ]]
}
```

Set during init:
```bash
# In ralphs init
echo "RALPHS_IS_SUPERVISOR=true" >> "$RALPHS_DIR/config.sh"

# In ralphs spawn (worker worktree)
echo "RALPHS_IS_SUPERVISOR=false" >> "$worktree/.ralphs/config.sh"
```

## Origin Hooks

### pre-receive (validation)

Location: `.ralphs/tickets.git/hooks/pre-receive`

```bash
#!/bin/bash
set -e

# State transition rules
declare -A TRANSITIONS=(
    ["ready"]="claimed"
    ["claimed"]="implement"
    ["implement"]="review"
    ["review"]="qa implement"
    ["qa"]="done implement"
)

validate_transition() {
    local from="$1" to="$2"
    [[ " ${TRANSITIONS[$from]} " == *" $to "* ]]
}

while read oldrev newrev refname; do
    # Skip branch deletion
    [[ "$newrev" == "0000000000000000000000000000000000000000" ]] && continue

    # Check each changed ticket file
    for file in $(git diff --name-only "$oldrev" "$newrev" 2>/dev/null || git ls-tree -r --name-only "$newrev"); do
        [[ "$file" == *.md ]] || continue

        # Get old and new state
        old_state=""
        if [[ "$oldrev" != "0000000000000000000000000000000000000000" ]]; then
            old_state=$(git show "$oldrev:$file" 2>/dev/null | awk '/^state:/{print $2}')
        fi
        new_state=$(git show "$newrev:$file" | awk '/^state:/{print $2}')

        # Skip if state unchanged
        [[ "$old_state" == "$new_state" ]] && continue

        # New tickets start at ready
        if [[ -z "$old_state" ]]; then
            if [[ "$new_state" != "ready" ]]; then
                echo "error: new tickets must start in 'ready' state, got '$new_state'"
                echo "hint: file: $file"
                exit 1
            fi
            continue
        fi

        # Validate transition
        if ! validate_transition "$old_state" "$new_state"; then
            echo "error: invalid transition '$old_state' → '$new_state'"
            echo "hint: file: $file"
            echo "hint: allowed from '$old_state': ${TRANSITIONS[$old_state]}"
            exit 1
        fi
    done
done

exit 0
```

### post-receive (hooks trigger)

Location: `.ralphs/tickets.git/hooks/post-receive`

```bash
#!/bin/bash

# Find project root (bare repo is at .ralphs/tickets.git)
RALPHS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_ROOT="$(dirname "$RALPHS_DIR")"

# Source ralphs utilities
source "$PROJECT_ROOT/path/to/ralphs/lib/utils.sh"
source "$PROJECT_ROOT/path/to/ralphs/lib/hooks.sh"

while read oldrev newrev refname; do
    # Skip deletions
    [[ "$newrev" == "0000000000000000000000000000000000000000" ]] && continue

    # Only trigger hooks for main branch updates
    [[ "$refname" == "refs/heads/main" ]] || continue

    # Check each changed ticket
    for file in $(git diff --name-only "$oldrev" "$newrev" 2>/dev/null); do
        [[ "$file" == *.md ]] || continue

        ticket_id=$(basename "$file" .md)
        old_state=$(git show "$oldrev:$file" 2>/dev/null | awk '/^state:/{print $2}')
        new_state=$(git show "$newrev:$file" | awk '/^state:/{print $2}')

        [[ "$old_state" == "$new_state" ]] && continue

        # Determine which hook to run
        case "$new_state" in
            review)
                run_hook "on-implement-done" "$ticket_id"
                ;;
            qa)
                run_hook "on-review-done" "$ticket_id"
                ;;
            implement)
                if [[ "$old_state" == "review" ]]; then
                    run_hook "on-review-rejected" "$ticket_id"
                elif [[ "$old_state" == "qa" ]]; then
                    run_hook "on-qa-rejected" "$ticket_id"
                fi
                ;;
            done)
                run_hook "on-qa-done" "$ticket_id"
                run_hook "on-close" "$ticket_id"
                ;;
        esac
    done
done
```

## Conflict Resolution

### Automatic (rebase)

Most conflicts resolve automatically with rebase since:
- Each worker edits different tickets (claimed/assigned)
- Body edits are append-mostly (feedback, notes)

### Manual escalation

If rebase fails:
1. Worker's sync command warns: "Ticket sync conflict"
2. Worker can manually resolve or escalate to supervisor
3. Supervisor resolves on main branch

### Merge strategy for body content

Configure tickets repo to use union merge for markdown:
```bash
# .ralphs/tickets.git/info/attributes
*.md merge=union
```

This appends conflicting additions rather than marking conflicts.

## CLI Changes

### New commands

```bash
ralphs ticket sync              # Manual sync (pull + push)
ralphs ticket sync --pull       # Pull only
ralphs ticket sync --push       # Push only
```

### Modified commands

All ticket commands gain implicit sync:
- `ticket show`, `ticket list`, `ticket ready`, `ticket blocked` → pull first
- `ticket create`, `ticket transition`, `ticket claim`, `ticket feedback` → pull, act, push

### Flags

```bash
--no-sync                       # Skip git sync (for offline/testing)
```

## Configuration

New config options in `.ralphs/config.sh`:

```bash
RALPHS_IS_SUPERVISOR=true|false     # Is this the supervisor worktree?
RALPHS_TICKET_BRANCH=main|impl-0    # Which branch this worktree uses
RALPHS_AUTO_SYNC=true|false         # Auto-sync on ticket operations (default: true)
```

## Migration

For existing ralphs projects without distributed tickets:

```bash
ralphs migrate-tickets
```

1. Creates `.ralphs/tickets.git` bare repo
2. Moves existing `.ralphs/tickets/*.md` into repo
3. Sets up submodule
4. Installs hooks

## Edge Cases

### Offline operation

With `RALPHS_AUTO_SYNC=false` or `--no-sync`:
- Operations work locally
- User must manually sync when online

### Supervisor unavailable

Workers can still:
- Read their local ticket state
- Make local changes
- Push to their branch

They cannot:
- Get updates from other workers (need supervisor to merge)
- Trigger hooks (run on origin)

### Concurrent transitions

If two workers try to transition the same ticket:
1. First push succeeds
2. Second push fails pre-receive validation (state already changed)
3. Second worker pulls, sees new state, adjusts

## Future Considerations

### Central ticket index

Optional `~/.claude/ralphs/index.json` tracking all projects:
```json
{
  "a1b2c3d4e5f6": {
    "path": "/home/user/myproject",
    "name": "myproject",
    "last_accessed": "2024-01-15T10:30:00Z"
  }
}
```

### Cross-project dependencies

Tickets could reference tickets in other projects:
```yaml
depends_on:
  - tk-1234                    # Same project
  - proj:abc123:tk-5678        # Other project
```

### Remote ticket origins

Instead of local bare repo, use hosted git:
```bash
ralphs init --ticket-remote git@github.com:org/project-tickets.git
```
