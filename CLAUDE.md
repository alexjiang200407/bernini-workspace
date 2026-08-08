# bernini-workspace — the map

One workspace, several checkouts of the same repo, one Claude session per checkout. PLAN.md holds
the full design; this file is the map every nested session inherits.

## Layout

- `bernini/` — main clone. Stays on `master`; used for quick fixes and landing. Never park it on a
  feature branch.
- `bernini.features/<name>/` — one git worktree per feature, on branch `feat/<name>`. Created and
  removed only by the `ws` scripts.
- `bernini-test-project/` — clone of the test project
  (`git@github.com:alexjiang200407/bernini-test-project.git`).
- `ws` — the dispatcher for the workspace scripts in `scripts/` (below): `./ws <command> [args]`.
  The scripts run at the workspace root; nobody *works* here. Symlink `ws` onto PATH for the
  `ws feature vat` spelling from anywhere.

## If you are a session inside a checkout

Your checkout (`bernini/` or `bernini.features/<name>/`) is your project, but it is one checkout
among several sharing a single git object store. A branch checked out in a sibling worktree cannot
be checked out in yours. Do your work in your own checkout; leave worktree creation/removal to the
`ws` scripts at the root — do not run `git worktree` yourself.

## Scripts (invoked as `./ws <command>` from the workspace root)

- `ws init` — once per machine: clone `bernini` and `bernini-test-project`, then run `just init` in
  `bernini/` (machine `config.json`, git hooks, LFS transfer agent — see `bernini/docs/lfs.md`).
  Idempotent: existing clones and an existing `config.json` are skipped.
- `ws doctor` — health check: platform, tools, clones, init state, LFS smudge, worktree seeding.
  Exits non-zero on FAILs.
- `ws feature <name> ["<prompt>"] [--preset <p>]` — worktree at `bernini.features/<name>` on
  `feat/<name>` (resumes if the branch exists), seeded with `config.json` and worktree-scoped
  `bernini.feature` config, then a tmux window running `claude "bcp-feature <name> <prompt>"`.
  `--preset` re-inits the worktree's own `config.json` with a different build preset (config.json
  is per-checkout; the preset in it is a choice, not machine state). `--mode` sets the agent's
  permission mode (default `acceptEdits`, never inherited). Set `WS_NO_AGENT=1` to create the
  worktree without launching the agent.
- `ws attach [<name>]` — attach to the `ws` tmux session to watch the agents (optionally one
  feature's window); detach with `Ctrl-b d`.
- `ws done <name>` — remove the worktree, kill the tmux window, delete `feat/<name>`. Refuses a
  dirty worktree or an unmerged branch rather than forcing.
- `ws list` — worktrees alongside open PRs: every live feature, its checkout, its PR state.
