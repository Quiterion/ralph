#!/bin/bash
#
# test_kill.sh - Agent killing and cleanup tests
#

# SC2034: Test arrays are used by main test runner via source
# SC2064: We intentionally expand variables at trap definition time
# shellcheck disable=SC2034,SC2064

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$SCRIPT_DIR/framework.sh"

test_kill_cleanup_worktree_and_branch() {
    if ! tmux_available; then
        echo "SKIP:tmux not available"
        return 0
    fi

    local session
    session=$(test_session_name)
    export WIGGUM_SESSION="$session"
    trap "cleanup_test_session '$session'" RETURN

    "$WIGGUM_BIN" init
    
    # Need at least one commit for worktree to work
    touch README.md
    git add README.md
    git commit -m "Initial commit" &>/dev/null

    # Spawn a worker (needs a ticket)
    "$WIGGUM_BIN" ticket create "Test ticket" &>/dev/null
    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket ready | head -n 1)
    
    if [[ -z "$ticket_id" ]]; then
        echo "Failed to create ticket"
        return 1
    fi
    
    local agent_id
    agent_id=$("$WIGGUM_BIN" --quiet spawn worker "$ticket_id" | tail -n 1)
    
    if [[ -z "$agent_id" ]]; then
        echo "Failed to spawn agent"
        return 1
    fi
    
    # Verify worktree exists
    local worktree_path="worktrees/$agent_id"
    assert_dir_exists "$worktree_path" "Worktree should exist after spawn"
    
    # Verify branch exists
    if ! git rev-parse --verify "$agent_id" &>/dev/null; then
        echo "Branch $agent_id should exist after spawn"
        return 1
    fi
    
    # Kill the agent
    "$WIGGUM_BIN" --verbose kill "$agent_id"
    
    # Verify worktree is gone
    assert_not_exists "$worktree_path" "Worktree should be removed after kill"
    
    # Verify branch is gone
    if git rev-parse --verify "$agent_id" &>/dev/null; then
        echo "Branch $agent_id should be removed after kill"
        return 1
    fi
}

test_kill_force_cleanup() {
    if ! tmux_available; then
        echo "SKIP:tmux not available"
        return 0
    fi

    local session
    session=$(test_session_name)
    export WIGGUM_SESSION="$session"
    trap "cleanup_test_session '$session'" RETURN

    "$WIGGUM_BIN" init
    
    # Need at least one commit for worktree to work
    touch README.md
    git add README.md
    git commit -m "Initial commit" &>/dev/null

    # Spawn supervisor to keep session alive
    "$WIGGUM_BIN" --quiet spawn supervisor >/dev/null

    # Spawn a worker
    "$WIGGUM_BIN" ticket create "Test ticket" &>/dev/null
    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket ready | head -n 1)
    
    local agent_id
    agent_id=$("$WIGGUM_BIN" --quiet spawn worker "$ticket_id" | tail -n 1)
    
    local worktree_path="worktrees/$agent_id"
    
    # Create unmerged changes in the branch to prevent normal deletion
    pushd "$worktree_path" >/dev/null
    echo "unmerged change" > unmerged.txt
    git add unmerged.txt
    git commit -m "Unmerged change" &>/dev/null
    popd >/dev/null
    
    # Normal kill should fail to delete branch
    "$WIGGUM_BIN" --verbose kill "$agent_id"
    
    # Branch should still exist because it's not merged
    if ! git rev-parse --verify "$agent_id" &>/dev/null; then
        echo "Branch $agent_id should still exist after normal kill (unmerged)"
        return 1
    fi
    
    # Now use --force
    "$WIGGUM_BIN" --verbose kill "$agent_id" --force
    
    # Branch should be gone now
    if git rev-parse --verify "$agent_id" &>/dev/null; then
        echo "Branch $agent_id should be removed after kill --force"
        return 1
    fi
}

KILL_TESTS=(
    "Kill cleans up worktree and branch:test_kill_cleanup_worktree_and_branch"
    "Kill force cleans up unmerged branch:test_kill_force_cleanup"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap teardown EXIT
    echo "Running kill tests..."
    run_tests "${1:-}" KILL_TESTS
    print_summary
fi
