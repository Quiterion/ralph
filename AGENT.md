# Agent Instructions

## Project Overview
This is a bash framework for running AI coding agents in autonomous loops (the "Ralph Wiggum" technique).

## Directory Structure
```
ralph/
├── PROMPT.md       # Main prompt fed each loop
├── fix_plan.md     # Living TODO list
├── AGENT.md        # This file - how to build/test
├── specs/          # Specifications
│   └── ralph.md    # The Ralph technique spec
└── src/            # Framework source
    ├── ralph.sh    # Main loop
    ├── init.sh     # Project scaffolding
    └── tune.sh     # Prompt tuning helper
```

## How to Test

### Test ralph.sh
```bash
# Dry run (echo instead of calling agent)
DRY_RUN=1 ./src/ralph.sh

# Single iteration
ONCE=1 ./src/ralph.sh
```

### Test init.sh
```bash
# Create a test project
mkdir /tmp/test-ralph && cd /tmp/test-ralph
/path/to/src/init.sh
ls -la  # Should show PROMPT.md, fix_plan.md, specs/, AGENT.md
```

### Test tune.sh
```bash
./src/tune.sh "Don't use placeholder implementations"
cat PROMPT.md  # Should show the new sign appended
```

## Commit Convention
After making changes that work, commit with:
```bash
git add -A && git commit -m "description of change"
```
