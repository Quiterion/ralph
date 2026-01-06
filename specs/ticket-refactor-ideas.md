
Might be worth cleaning up the model and making workflows configurable.

## Basic idea of current architecture
- wiggum control plane uses configuration and registry in <proj-root>/.wiggum
- wiggum data plane (i.e. tickets) uses distributed hierachy:
  - origin is bare repo in <proj-root>/.wiggum/tickets.git
  - each agent interacts with a clone in <proj-root>/worktrees/<agent-id>/.wiggum/tickets
- why the nested repo structure? to prevent conceptual drift between agents in parallel project worktrees. 
  - ticket files can have a note saying to never edit directly, always use 'wiggum ticket' cmds
  - each command attempts to pull and push before and after every modification
  - if the pull retrieves changes in existing ticket files then we can return early and surface the changes to the agent.
  - if the push is blocked then we can undo the local edit, return early, and inform the agent

## Current implementation details
- <proj-root> := outer repo with .wiggum/ dir
- <proj-root>/.wiggum/tickets.git := inner bare repo with ticket md files
    - on-ticket-state-transition hooks are currently invoked by git hooks in this repo
    - they indirectly invoke user-defined hooks in <proj-root>/.wiggum/hooks
- ticket fields, possible ticket states and transitions are hardcoded in wiggum lib
- each new ticket gets a feature/<ticket-id> in <proj-root>
- lifetime of agent instance == lifetime of agent worktree branch == lifetime of agent tmux pane
  - mapping tracked in <proj-root>/.wiggum/panels.json registry
- <proj-root>/worktrees/<agent-id> := worktree of <proj-root> with <agent-id> branch
  - if <ticket-id> is supplied with `wiggum spawn <role> <ticket-id>`, then:
      - <agent-id> branch is created from feature/<ticket-id> 
      - changes in <agent-id> should be merged back into feature/<ticket-id>

- <proj-root>/worktrees/<agent-id>/.wiggum/tickets := clone of <proj-root>/.wiggum/tickets.git 
  - used for agent data plane interaction by agent
  - kept in sync with upstream by `wiggum ticket` cmds
  - see above justification of nested repo structure

- <proj-root>/.wiggum/tickets/ := clone of <proj-root>/.wiggum/tickets.git
  - used for human interaction with data plane 
  - conceptually equivalent to <proj-root>/worktrees/<agent-id>/.wiggum/tickets

## Invariants
- All operations that read from and write to wiggum control-plane configuration and registry must use $MAIN_WIGGUM_DIR aka <proj-root>/.wiggum
- All operations that read from and write to tickets should use CRUD wrappers from the ticket data layer, which enforce data plane sync

## Improvements
Add ticket prototype definitions:
- Store in control plane configuration i.e. <proj-root>/.wiggum/ticket_types.json
- Allow configuration of properties like:
  - allowed ticket states
  - additional frontmatter fields e.g. reviewer-agent-id,
  - valid ticket state transitions incl. filenames of pre- and post-transition hooks
- `wiggum ticket create` can then generate valid tickets from prototype

Ticket-state-transition-hook invocation:
- Remove git hooks in <proj-root>/.wiggum/tickets.git, too troublesome, and the implementation violatess the ticket data layer invariants
- Instead, hook scripts should be invoked by `wiggum ticket transition` after it successfully pushes changes to ticket upstream
  - would allow pre-transition hooks to be run in worktree
  - e.g. in-progress -> review should fail if no merge occurred

Enforce adherence of invariants:
- Remove mixed use of $TICKET_DIR, $MAIN_TICKET_DIR, $MAIN_WIGGUM_DIR, $WIGGUM_DIR, $PROJECT_DIR, and $MAIN_PROJECT_DIR
  - All operations that read from and write to wiggum control-plane configuration and registry must use $MAIN_WIGGUM_DIR aka <proj-root>/.wiggum
  - All operations that read from or write to tickets must use CRUD wrappers from the ticket data layer that enforce data plane sync
  - Only the CRUD wrappers in the ticket data layer may reference $TICKET_DIR !! (currently the git hook implementation volates)
