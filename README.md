# agent-worktrees

Run several coding agents (Claude Code, Codex, Cursor, Aider…) on the same repo at the same time without them overwriting each other's files.

`wt` is one small bash script. It gives each agent its own git worktree (a separate folder on its own branch), copies your env files over, installs deps, hands out a free port, and lets each agent **claim the files it plans to touch** so clashes show up before any work starts, not at merge time.

```
$ wt new auth --port
› worktree  /code/app-auth
› branch    agent/auth
› copied 2 env file(s)
› port      3100 (written to .env.local)
› installing deps: pnpm install

$ wt new billing --port
$ wt claim auth src/auth src/lib/session.ts
$ wt claim billing src/billing src/lib/session.ts
! overlap: auth (src/lib/session.ts) vs billing (src/lib/session.ts)
! don't run these agents in parallel; sequence them or split the work
```

## Why

Running three agents in one folder means they edit the same files live and undo each other's work. Worktrees fix that: same repo, separate folders, separate branches.

But worktrees only **move** the conflict to merge time. Two agents can both "fix" the same util on different branches, and you only find out when you merge. So `wt` adds one cheap step: each agent declares what it will touch, and `wt check` flags overlaps while it's still free to change the plan.

The other papercuts it handles:

| Problem | What `wt` does |
|---|---|
| New worktree has no `.env`, agent starts without config | Copies untracked `.env*` files from the main checkout |
| `node_modules` missing in the new folder | Detects the lockfile and runs the right install (pnpm, npm, yarn, bun, uv, poetry, dotnet) |
| Two dev servers fight over port 3000 | `--port` writes a unique `PORT` to `.env.local` |
| Worktree folders and branches pile up | `wt ls` shows them all; `wt rm` cleans up folder, state and branch |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/kaimbuilds/agent-worktrees/main/bin/wt -o ~/.local/bin/wt
chmod +x ~/.local/bin/wt
```

Or clone and symlink `bin/wt` anywhere on your `PATH`. Needs bash 3.2+ (the macOS default works) and git 2.20+.

## Usage

```bash
wt new <name> [--base <ref>] [--no-install] [--port]   # create ../<repo>-<name> on agent/<name>
wt ls                                                  # list agent worktrees, status and claims
wt claim <name> <path>...                              # record what an agent will touch
wt claims                                              # show all claims
wt check                                               # exit 1 if any claims overlap
wt path <name>                                         # print the folder: cd "$(wt path auth)"
wt rm <name> [--delete-branch] [--force]               # remove when merged
```

Claims are path prefixes: claiming `src/auth` overlaps with anything under `src/auth/`. They live in `.git/wt/`, so nothing is committed and every worktree sees the same state.

## A typical session

```bash
wt new auth --port
wt new api --port
wt claim auth src/auth
wt claim api src/api
wt check                    # › no overlapping claims

cd "$(wt path auth)" && claude    # terminal 1
cd "$(wt path api)"  && claude    # terminal 2

# when each passes its tests
git merge agent/auth && wt rm auth --delete-branch
git rebase main agent/api         # keep the others close to main
```

Merge small and often. Rebasing the remaining branches after each merge keeps drift small.

## Let the agent claim its own files

Add this to your `CLAUDE.md` (or `AGENTS.md`) so the agent does the claiming for you:

```markdown
## Parallel work
You are one of several agents working in separate git worktrees.
Before editing, run `wt claim <your-worktree-name> <paths you will change>` and then `wt check`.
If `wt check` reports an overlap, stop and tell me instead of editing those files.
```

## Settings

| Variable | Default | Purpose |
|---|---|---|
| `WT_DIR` | next to the repo | Where worktree folders go |
| `WT_BRANCH_PREFIX` | `agent/` | Branch prefix |
| `WT_PORT_BASE` | `3100` | First port handed out by `--port` |

## Tests

```bash
./test/run.sh
```

Spins up a throwaway repo and checks creation, env copying, ports, overlap detection (exact file and directory vs file), cleanup and refusal to delete uncommitted work. CI runs it on Ubuntu and macOS.

## Licence

MIT
