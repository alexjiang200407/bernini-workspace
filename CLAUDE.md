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
- `ws feature <name> ["<prompt>"] [--branch <b>] [--preset <p>] [--model <m>]` — worktree at `bernini.features/<name>` on
  `feat/<name>` (resumes if the branch exists), seeded with `config.json` and worktree-scoped
  `bernini.feature` config, then a tmux window running `claude "bcp-feature <name> <prompt>"`.
  `--preset` re-inits the worktree's own `config.json` with a different build preset (config.json
  is per-checkout; the preset in it is a choice, not machine state). A fresh session at a
  terminal is asked which model to run on (`--model <m>` answers it up front; non-interactive
  runs take claude's configured default; resumed conversations keep their model). `--mode` sets the agent's
  permission mode (default `bypassPermissions` — agents run unattended; set, not inherited). `--continue` resumes the worktree's
  previous claude conversation instead of starting fresh — the recovery path after an agent
  exited or the machine rebooted; on an existing worktree without `--continue`, a terminal run
  asks whether to resume (and whether to compact first), while non-interactive runs start
  fresh. A terminal run auto-attaches to the new agent's window (`Ctrl-b d` to step out);
  non-interactive runs return immediately. If the feature's agent is already running, a terminal
  run attaches to it instead of starting a second one. `--no-agent` (or `WS_NO_AGENT=1`) creates the
  worktree without launching an agent — a checkout to build and run the editor in.
  `--branch <b>` borrows an existing branch (it must already exist) instead of `feat/<name>`: the
  cross-platform debug case, where a fix written on Windows has to be built on the mac. A borrowed
  checkout is not ws's: `ws done` removes the worktree but leaves the branch, `bernini.feature` is
  left empty so the diff base stays `origin/master`, and a fresh worktree is fast-forwarded to
  `origin/<b>` so you never debug a stale local ref.
- `ws attach [<name>]` — attach to the `ws` tmux session to watch the agents (optionally one
  feature's window); detach with `Ctrl-b d`. Each terminal gets its own view session grouped with
  `ws` (`ws-view-<pid>`), so switching windows in one terminal does not move the others.
- `ws cmd <name> [--] <command> [args...]` — run a command in a feature's checkout
  (`ws cmd vat -- just run editor`), or in the main clone with `bernini`. Foreground, in your
  terminal, exiting with the command's status; the cwd is that checkout, so relative paths resolve
  there and not where you invoked `ws`. One terminal instead of one per worktree.
- `ws done <name>` — remove the worktree, kill the tmux window, delete the branch ws created for it
  (a borrowed branch is left alone). Refuses a dirty worktree or an unmerged branch rather than
  forcing.
- `ws list` — worktrees alongside open PRs: every live feature, its checkout, its PR state.
