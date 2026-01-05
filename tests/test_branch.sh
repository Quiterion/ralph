#!/bin/bash
#
# test_branch.sh - Branch management tests
#
# Tests for:
#   - wiggum branch list/cleanup/merge commands
#   - wiggum rebase command
#   - merge_to_feature() function
#   - Merge conflict blocking in ticket transitions
#

# SC2034: Test arrays are used by main test runner via source
# shellcheck disable=SC2034

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$SCRIPT_DIR/framework.sh"

#
# Helper: Create initial commit to allow branching
#
create_initial_commit() {
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit" --quiet
    # Ensure branch is named 'main' (default may differ by git version)
    git branch -M main 2>/dev/null || true
}

#
# Tests: wiggum branch list
#

test_branch_list_basic() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local output
    output=$("$WIGGUM_BIN" branch list)

    # Should show table headers
    assert_contains "$output" "BRANCH" "Should show BRANCH header"
    assert_contains "$output" "TICKET" "Should show TICKET header"
    assert_contains "$output" "TYPE" "Should show TYPE header"
}

test_branch_list_shows_feature_branch() {
    "$WIGGUM_BIN" init
    create_initial_commit

    # Create a feature branch manually
    git branch feature/tk-1234

    local output
    output=$("$WIGGUM_BIN" branch list)

    assert_contains "$output" "feature/tk-1234" "Should show feature branch"
    assert_contains "$output" "tk-1234" "Should show ticket ID"
    assert_contains "$output" "feature" "Should show branch type"
}

test_branch_list_filters_by_ticket() {
    "$WIGGUM_BIN" init
    create_initial_commit

    # Create multiple feature branches
    git branch feature/tk-1111
    git branch feature/tk-2222

    local output
    output=$("$WIGGUM_BIN" branch list tk-1111)

    assert_contains "$output" "feature/tk-1111" "Should show matching branch"

    # Should not contain the other ticket
    if [[ "$output" == *"tk-2222"* ]]; then
        echo "Should not show non-matching ticket"
        return 1
    fi
}

test_branch_list_shows_agent_branches() {
    "$WIGGUM_BIN" init
    create_initial_commit

    # Create agent branches
    git branch worker-0
    git branch reviewer-1
    git branch qa-2

    local output
    output=$("$WIGGUM_BIN" branch list)

    assert_contains "$output" "worker-0" "Should show worker branch"
    assert_contains "$output" "reviewer-1" "Should show reviewer branch"
    assert_contains "$output" "qa-2" "Should show qa branch"
    assert_contains "$output" "worker" "Should show worker type"
    assert_contains "$output" "reviewer" "Should show reviewer type"
    assert_contains "$output" "qa" "Should show qa type"
}

#
# Tests: wiggum branch cleanup
#

test_branch_cleanup_usage_error() {
    "$WIGGUM_BIN" init
    create_initial_commit

    if "$WIGGUM_BIN" branch cleanup 2>/dev/null; then
        echo "Should fail without ticket ID"
        return 1
    fi
}

test_branch_cleanup_deletes_feature_branch() {
    "$WIGGUM_BIN" init
    create_initial_commit

    # Create a ticket and its feature branch
    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Cleanup test")
    git branch "feature/$ticket_id"

    # Verify branch exists
    if ! git rev-parse --verify "feature/$ticket_id" &>/dev/null; then
        echo "Feature branch should exist before cleanup"
        return 1
    fi

    # Run cleanup
    "$WIGGUM_BIN" branch cleanup "$ticket_id"

    # Branch should be deleted
    if git rev-parse --verify "feature/$ticket_id" &>/dev/null; then
        echo "Feature branch should be deleted after cleanup"
        return 1
    fi
}

test_branch_cleanup_reports_count() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Count test")
    git branch "feature/$ticket_id"

    local output
    output=$("$WIGGUM_BIN" branch cleanup "$ticket_id" 2>&1)

    assert_contains "$output" "Cleaned up" "Should report cleanup"
    assert_contains "$output" "branches" "Should mention branches"
}

#
# Tests: wiggum branch merge
#

test_branch_merge_usage_error() {
    "$WIGGUM_BIN" init
    create_initial_commit

    if "$WIGGUM_BIN" branch merge 2>/dev/null; then
        echo "Should fail without ticket ID"
        return 1
    fi
}

test_branch_merge_requires_feature_branch() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "No feature branch")

    if "$WIGGUM_BIN" branch merge "$ticket_id" 2>/dev/null; then
        echo "Should fail when feature branch doesn't exist"
        return 1
    fi
}

test_branch_merge_merges_to_main() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Merge test")

    # Create and checkout feature branch
    git branch "feature/$ticket_id"
    git checkout "feature/$ticket_id" --quiet

    # Add a commit to the feature branch
    echo "feature work" > feature.txt
    git add feature.txt
    git commit -m "Feature work" --quiet

    # Go back to main
    git checkout main --quiet

    # Merge
    local output
    output=$("$WIGGUM_BIN" branch merge "$ticket_id" 2>&1)

    assert_contains "$output" "Successfully merged" "Should report success"

    # Check that main has the feature work
    if [[ ! -f "feature.txt" ]]; then
        echo "Feature file should exist on main after merge"
        return 1
    fi
}

test_branch_merge_detects_conflict() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Conflict test")

    # Create feature branch with a change
    git branch "feature/$ticket_id"
    git checkout "feature/$ticket_id" --quiet
    echo "feature version" > conflict.txt
    git add conflict.txt
    git commit -m "Feature change" --quiet

    # Go back to main and make conflicting change
    git checkout main --quiet
    echo "main version" > conflict.txt
    git add conflict.txt
    git commit -m "Main change" --quiet

    # Attempt merge - should fail with conflict
    local output
    local exit_code=0
    output=$("$WIGGUM_BIN" branch merge "$ticket_id" 2>&1) || exit_code=$?

    # Should exit with merge conflict code (7)
    assert_eq "7" "$exit_code" "Should exit with EXIT_MERGE_CONFLICT"
    assert_contains "$output" "conflict" "Should mention conflict"
}

#
# Tests: wiggum rebase
#

test_rebase_usage_error() {
    "$WIGGUM_BIN" init
    create_initial_commit

    # Not on an agent branch, no ticket specified
    if "$WIGGUM_BIN" rebase 2>/dev/null; then
        echo "Should fail without ticket ID when not on agent branch"
        return 1
    fi
}

test_rebase_requires_feature_branch() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "No feature for rebase")

    if "$WIGGUM_BIN" rebase "$ticket_id" 2>/dev/null; then
        echo "Should fail when feature branch doesn't exist"
        return 1
    fi
}

test_rebase_rebases_onto_feature() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Rebase test")

    # Create feature branch with some commits
    git branch "feature/$ticket_id"
    git checkout "feature/$ticket_id" --quiet
    echo "feature base" > base.txt
    git add base.txt
    git commit -m "Feature base" --quiet

    # Create a worker branch from main (simulating starting before feature existed)
    git checkout main --quiet
    git checkout -b "worker-test" --quiet
    echo "worker work" > work.txt
    git add work.txt
    git commit -m "Worker work" --quiet

    # Rebase onto feature branch
    local output
    output=$("$WIGGUM_BIN" rebase "$ticket_id" 2>&1)

    assert_contains "$output" "Successfully rebased" "Should report success"

    # Worker should now have feature base file
    if [[ ! -f "base.txt" ]]; then
        echo "Base file from feature should exist after rebase"
        return 1
    fi
}

test_rebase_detects_conflict() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Rebase conflict")

    # Create feature branch with a change
    git branch "feature/$ticket_id"
    git checkout "feature/$ticket_id" --quiet
    echo "feature version" > conflict.txt
    git add conflict.txt
    git commit -m "Feature change" --quiet

    # Create worker branch from main with conflicting change
    git checkout main --quiet
    git checkout -b "worker-conflict" --quiet
    echo "worker version" > conflict.txt
    git add conflict.txt
    git commit -m "Worker change" --quiet

    # Attempt rebase - should fail with conflict
    local output
    local exit_code=0
    output=$("$WIGGUM_BIN" rebase "$ticket_id" 2>&1) || exit_code=$?

    # Should exit with merge conflict code (7)
    assert_eq "7" "$exit_code" "Should exit with EXIT_MERGE_CONFLICT"
    assert_contains "$output" "conflict" "Should mention conflict"

    # Clean up the rebase
    git rebase --abort 2>/dev/null || true
}

#
# Tests: merge_to_feature() function
#
# Note: merge_to_feature is called internally by ticket_transition.
# We test it indirectly through ticket transition behavior.
#

test_merge_to_feature_on_review_transition() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Merge on review")

    # Create feature branch
    git branch "feature/$ticket_id"

    # Create worker branch with changes (simulating agent work)
    git checkout -b "worker-0" --quiet
    echo "worker implementation" > impl.txt
    git add impl.txt
    git commit -m "Worker implementation" --quiet

    # Set up ticket as if assigned to worker-0
    "$WIGGUM_BIN" ticket transition "$ticket_id" in-progress --no-hooks

    # Manually set the assigned_agent_id (normally done by spawn)
    local ticket_path=".wiggum/tickets/${ticket_id}.md"
    sed -i 's/assigned_agent_id:.*/assigned_agent_id: worker-0/' "$ticket_path"

    # Sync the change
    "$WIGGUM_BIN" ticket sync --push

    # Transition to review - this should trigger merge_to_feature
    "$WIGGUM_BIN" ticket transition "$ticket_id" review --no-hooks

    # Check that feature branch has the worker's changes
    git checkout "feature/$ticket_id" --quiet
    if [[ ! -f "impl.txt" ]]; then
        echo "Feature branch should have worker's implementation after review transition"
        return 1
    fi
}

test_merge_to_feature_creates_branch_if_missing() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Auto create feature")

    # Do NOT create feature branch - let merge_to_feature create it

    # Create worker branch with changes
    git checkout -b "worker-0" --quiet
    echo "worker work" > work.txt
    git add work.txt
    git commit -m "Worker work" --quiet

    # Set up ticket
    "$WIGGUM_BIN" ticket transition "$ticket_id" in-progress --no-hooks
    local ticket_path=".wiggum/tickets/${ticket_id}.md"
    sed -i 's/assigned_agent_id:.*/assigned_agent_id: worker-0/' "$ticket_path"
    "$WIGGUM_BIN" ticket sync --push

    # Transition to review
    "$WIGGUM_BIN" ticket transition "$ticket_id" review --no-hooks

    # Feature branch should now exist
    if ! git rev-parse --verify "feature/$ticket_id" &>/dev/null; then
        echo "Feature branch should be created by merge_to_feature"
        return 1
    fi
}

test_merge_to_feature_no_op_when_no_changes() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "No changes")

    # Create feature branch
    git branch "feature/$ticket_id"

    # Create worker branch from feature (same commit, no new work)
    git checkout "feature/$ticket_id" --quiet
    git checkout -b "worker-0" --quiet

    # Set up ticket
    git checkout main --quiet
    "$WIGGUM_BIN" ticket transition "$ticket_id" in-progress --no-hooks
    local ticket_path=".wiggum/tickets/${ticket_id}.md"
    sed -i 's/assigned_agent_id:.*/assigned_agent_id: worker-0/' "$ticket_path"
    "$WIGGUM_BIN" ticket sync --push

    # Transition to review - should succeed even with no changes to merge
    local output
    output=$("$WIGGUM_BIN" ticket transition "$ticket_id" review --no-hooks 2>&1)

    # Should not fail
    local state
    state=$(grep "^state:" ".wiggum/tickets/${ticket_id}.md" | cut -d' ' -f2)
    assert_eq "review" "$state" "Ticket should be in review state"
}

#
# Tests: Merge conflict blocking in ticket transitions
#

test_transition_blocked_by_merge_conflict() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Conflict blocks transition")

    # Create feature branch with a change
    git branch "feature/$ticket_id"
    git checkout "feature/$ticket_id" --quiet
    echo "feature content" > conflict.txt
    git add conflict.txt
    git commit -m "Feature change" --quiet

    # Create worker branch from main with conflicting change
    git checkout main --quiet
    git checkout -b "worker-0" --quiet
    echo "worker content" > conflict.txt
    git add conflict.txt
    git commit -m "Worker change" --quiet

    # Set up ticket as assigned to worker
    git checkout main --quiet
    "$WIGGUM_BIN" ticket transition "$ticket_id" in-progress --no-hooks
    local ticket_path=".wiggum/tickets/${ticket_id}.md"
    sed -i 's/assigned_agent_id:.*/assigned_agent_id: worker-0/' "$ticket_path"
    "$WIGGUM_BIN" ticket sync --push

    # Attempt transition to review - should be blocked by conflict
    local output
    local exit_code=0
    output=$("$WIGGUM_BIN" ticket transition "$ticket_id" review --no-hooks 2>&1) || exit_code=$?

    # Should exit with merge conflict code
    assert_eq "7" "$exit_code" "Should exit with EXIT_MERGE_CONFLICT"
    assert_contains "$output" "conflict" "Should mention conflict"
    assert_contains "$output" "Cannot transition" "Should say cannot transition"

    # Ticket should still be in-progress
    local state
    "$WIGGUM_BIN" ticket sync --pull
    state=$(grep "^state:" ".wiggum/tickets/${ticket_id}.md" | cut -d' ' -f2)
    assert_eq "in-progress" "$state" "Ticket should remain in-progress"
}

test_transition_succeeds_after_conflict_resolution() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Resolve then transition")

    # Create feature branch with a change
    git branch "feature/$ticket_id"
    git checkout "feature/$ticket_id" --quiet
    echo "feature content" > conflict.txt
    git add conflict.txt
    git commit -m "Feature change" --quiet

    # Create worker branch from main with conflicting change
    git checkout main --quiet
    git checkout -b "worker-0" --quiet
    echo "worker content" > conflict.txt
    git add conflict.txt
    git commit -m "Worker change" --quiet

    # Resolve conflict by merging worker into feature first
    git checkout "feature/$ticket_id" --quiet
    git merge worker-0 --no-edit -X theirs --quiet 2>/dev/null || {
        # Handle conflict manually
        echo "resolved" > conflict.txt
        git add conflict.txt
        git commit -m "Resolve conflict" --quiet
    }

    # Set up ticket
    git checkout main --quiet
    "$WIGGUM_BIN" ticket transition "$ticket_id" in-progress --no-hooks
    local ticket_path=".wiggum/tickets/${ticket_id}.md"
    sed -i 's/assigned_agent_id:.*/assigned_agent_id: worker-0/' "$ticket_path"
    "$WIGGUM_BIN" ticket sync --push

    # Now transition should succeed (no new commits on worker)
    "$WIGGUM_BIN" ticket transition "$ticket_id" review --no-hooks

    local state
    state=$(grep "^state:" ".wiggum/tickets/${ticket_id}.md" | cut -d' ' -f2)
    assert_eq "review" "$state" "Ticket should transition to review"
}

test_transition_non_worker_skips_merge() {
    "$WIGGUM_BIN" init
    create_initial_commit

    local ticket_id
    ticket_id=$("$WIGGUM_BIN" ticket create "Non-worker transition")

    # Start ticket
    "$WIGGUM_BIN" ticket transition "$ticket_id" in-progress --no-hooks

    # Manually set assigned to reviewer (not worker)
    local ticket_path=".wiggum/tickets/${ticket_id}.md"
    sed -i 's/assigned_agent_id:.*/assigned_agent_id: reviewer-0/' "$ticket_path"
    "$WIGGUM_BIN" ticket sync --push

    # Transition should succeed without trying to merge
    "$WIGGUM_BIN" ticket transition "$ticket_id" review --no-hooks

    local state
    state=$(grep "^state:" ".wiggum/tickets/${ticket_id}.md" | cut -d' ' -f2)
    assert_eq "review" "$state" "Ticket should transition to review"
}

#
# Test list
#

BRANCH_TESTS=(
    # Branch list
    "Branch list basic:test_branch_list_basic"
    "Branch list shows feature branch:test_branch_list_shows_feature_branch"
    "Branch list filters by ticket:test_branch_list_filters_by_ticket"
    "Branch list shows agent branches:test_branch_list_shows_agent_branches"

    # Branch cleanup
    "Branch cleanup usage error:test_branch_cleanup_usage_error"
    "Branch cleanup deletes feature branch:test_branch_cleanup_deletes_feature_branch"
    "Branch cleanup reports count:test_branch_cleanup_reports_count"

    # Branch merge
    "Branch merge usage error:test_branch_merge_usage_error"
    "Branch merge requires feature branch:test_branch_merge_requires_feature_branch"
    "Branch merge merges to main:test_branch_merge_merges_to_main"
    "Branch merge detects conflict:test_branch_merge_detects_conflict"

    # Rebase
    "Rebase usage error:test_rebase_usage_error"
    "Rebase requires feature branch:test_rebase_requires_feature_branch"
    "Rebase rebases onto feature:test_rebase_rebases_onto_feature"
    "Rebase detects conflict:test_rebase_detects_conflict"

    # merge_to_feature()
    "Merge to feature on review transition:test_merge_to_feature_on_review_transition"
    "Merge to feature creates branch if missing:test_merge_to_feature_creates_branch_if_missing"
    "Merge to feature no-op when no changes:test_merge_to_feature_no_op_when_no_changes"

    # Merge conflict blocking
    "Transition blocked by merge conflict:test_transition_blocked_by_merge_conflict"
    "Transition succeeds after conflict resolution:test_transition_succeeds_after_conflict_resolution"
    "Transition non-worker skips merge:test_transition_non_worker_skips_merge"
)

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap teardown EXIT
    echo "Running branch management tests..."
    run_tests "${1:-}" BRANCH_TESTS
    print_summary
fi
