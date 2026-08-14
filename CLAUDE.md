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
  `bernini/` (machine `config.json`, git hooks, LFS transfer agent — see `bernini/docs/lfs.md`),
  and point every checkout's editor at the test project. Idempotent: existing clones and an
  existing `config.json` are skipped, so re-running it is also how older checkouts are backfilled.
  The editor's `apps/editor/config.json` is git-ignored and per-checkout, and its `startupProject`
  is filled in with `bernini-test-project/Test Project.berniniproject` so `just run editor` opens
  the test project rather than the empty state, and its `instanceName` with the checkout's own name
  (`master` for the main clone) so two editors run side by side say which checkout each was built
  in — an existing one is patched, never replaced, and a value that stands is left alone.
- `ws doctor` — health check: platform, tools, clones, init state, LFS smudge, worktree seeding.
  Exits non-zero on FAILs.
- `ws completions [<zsh|bash>] [--install]` — print the shell completion script; `--install` writes
  it to a directory on the shell's real `$fpath` (asked of an interactive zsh, not guessed) and
  `ws doctor` reports it — once per machine, then a new shell. Both shims ask `ws __complete` for
  candidates, and it derives them from `scripts/`, the worktrees and git — so a new command or flag
  completes without a completion file being touched. Scripts named `_*` are plumbing: routable,
  hidden from usage.
- `ws feature <name> ["<prompt>"] [--cycle|--one-shot] [--branch <b>] [--preset <p>] [--model <m>]` — worktree at `bernini.features/<name>` on
  `feat/<name>` (resumes if the branch exists), seeded with `config.json`, the editor's startup
  project (see `ws init`) and worktree-scoped
  `bernini.feature` config, then a tmux window running the agent on one of two workflows:
  `--cycle` (default) runs `bcp-feature <name> <prompt>` — plan PR, then one task PR at a time into
  `feat/<name>`; `--one-shot` runs `bcp-implement <prompt>` — the whole change as a single PR to
  master, which also means `bernini.feature` is left empty (bcp-implement hands over to bcp-feature
  when it is set, and origin/master is the base a one-shot wants). A fresh session at a terminal is
  asked which; the answer is recorded as `bernini.wsWorkflow` so resuming neither asks again nor
  re-seeds the wrong base. A new feature must come with a prompt — a terminal run asks for one, a
  non-interactive run refuses before creating anything; `--continue`, a borrowed checkout, and
  `--cycle` on an existing feature are the exceptions. An existing worktree is asked whether to
  resume its previous conversation *first*, and resuming means no prompt is wanted at all. Every
  question it asks is edited in zsh's line editor (`vared`, falling back to `read -e`): pastes are
  bracketed, so a pasted multi-line prompt lands whole instead of the first line answering this
  question and the rest answering the next ones — macOS bash 3.2 cannot do that.
  Before any of it, `scripts/_sync-master` fetches and fast-forwards the main clone's master:
  nothing else in the workspace moves `bernini/`, and a stale master means quick fixes cut from an
  old tree and a `ws done` that reads a merged feature as unmerged.
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
  worktree without launching an agent — a checkout to build and run the editor in. The agent runs
  under `scripts/_agent`, which forks a watchdog and then execs claude — so the pane is still claude
  itself and behaves exactly as before, while the watchdog samples its process tree and kills what
  is left of it when the session ends: claude starts backgrounded work (`just watch-pr`) detached,
  so a window closed by `ws done` or a killed agent would otherwise leave a watcher polling a PR for
  hours.
  `--branch <b>` borrows an existing branch (it must already exist) instead of `feat/<name>`: the
  cross-platform debug case, where a fix written on Windows has to be built on the mac. A borrowed
  checkout is not ws's: `ws done` removes the worktree but leaves the branch, `bernini.feature` is
  left empty so the diff base stays `origin/master`, and a fresh worktree is fast-forwarded to
  `origin/<b>` so you never debug a stale local ref.
- `ws attach [<name>]` — attach to the `ws` tmux session to watch the agents (optionally one
  feature's window); detach with `Ctrl-b d`. Each terminal gets its own view session
  (`ws-view-<pid>`), so switching windows in one terminal does not move the others: `ws attach` is
  grouped with `ws` and shows every window, `ws attach <name>` holds that one window alone, so
  exiting the agent returns the terminal to its shell instead of sliding it onto another agent.
- `ws cmd <name> [--] <command> [args...]` — run a command in a feature's checkout
  (`ws cmd vat -- just run editor`), or in the main clone with `bernini`. Foreground, in your
  terminal, exiting with the command's status; the cwd is that checkout, so relative paths resolve
  there and not where you invoked `ws`. One terminal instead of one per worktree.
- `ws done <name>` — remove the worktree, kill the tmux window, delete the branch ws created for it
  (a borrowed branch is left alone). Refuses a dirty worktree or an unmerged branch rather than
  forcing — pulling master first, since "unmerged" is judged against the local one. It lists what it
  is about to remove and asks, every run, a merged feature included: the branch is the part that
  survives, and what goes with the worktree is the build dir. `--yes` and a scripted run print the
  same listing and skip the question. The listing says whether the branch is merged, which is the
  one thing the teardown itself cannot tell you in time: `branch -d` runs last, so its refusal of an
  unmerged branch arrives once the worktree is already gone.
- `ws list` — worktrees alongside open PRs: every live feature, its checkout, its PR state.
