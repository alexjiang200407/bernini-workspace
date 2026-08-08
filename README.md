# bernini-workspace

Checkouts and agents for AI-parallel [bernini](https://github.com/alexjiang200407/bernini)
development: one main clone, one git worktree per feature, one Claude session per checkout.
`PLAN.md` holds the design; `CLAUDE.md` is the map inherited by every session opened inside a
checkout. The clones themselves are git-ignored — this repo tracks only the plan, the map, and the
scripts.

## Platform support

macOS and Linux. On Windows the workspace only works inside
[WSL](https://learn.microsoft.com/windows/wsl/) — Git Bash is **not** supported: it has no tmux
(which `ws feature` needs for the agent sessions), and its `ln -s` silently copies instead of
linking, which breaks the `ws` dispatcher. Note this applies to the *workspace tooling* only —
bernini itself still builds natively on Windows from a plain clone.

## Setup

```sh
git clone git@github.com:alexjiang200407/bernini-workspace.git
cd bernini-workspace
./ws init
```

`ws init` also symlinks `ws` into `~/.local/bin` (when that directory exists and nothing named
`ws` is on PATH already), so the commands work bare — `ws feature vat` from anywhere. To do it by
hand, link `ws` from any directory on your PATH:

```sh
ln -s "$PWD/ws" ~/.local/bin/ws
```

## Commands

`./ws` with no arguments lists these. `ws` is a thin dispatcher; the implementations live in
`scripts/`.

### `ws init`

Once per machine. Clones `bernini` and
[`bernini-test-project`](https://github.com/alexjiang200407/bernini-test-project) into the
workspace root (skipping any that already exist), installs tmux if missing (Homebrew on macOS,
apt on Linux — tmux hosts the feature agent sessions), then runs `just init` in `bernini/` — which
generates the machine `config.json`, installs the git hooks, and configures the LFS transfer agent
(see `bernini/docs/lfs.md`). Like bernini's own scripts, `python3` is assumed to be on PATH.

Re-running `ws init` is safe: clones that exist are skipped, and `just init` is skipped once
`bernini/scripts/config.json` exists.

### `ws doctor`

Checks the workspace for problems and exits non-zero on any `FAIL`: platform (Git Bash is
rejected), required tools (`git`, `python3`, `tmux`, `claude`, `git-lfs`), the clones, whether
`just init` has been run, whether `bernini/` is parked off master, whether LFS assets smudged or
are still pointer text, stale worktree registrations, per-worktree seeding, and the `ws` PATH
symlink. `warn`s are things the workspace survives; `FAIL`s break `ws feature` or the builds
inside it.

### `ws feature <name> ["<prompt>"] [--preset <p>] [--mode <m>] [--continue]`

Starts (or resumes) a feature:

1. Fetches origin, then adds a worktree at `bernini.features/<name>` on branch `feat/<name>` —
   branched from `origin/master`, or reused as-is if the branch already exists locally or on
   origin (resume).
2. Seeds the worktree: copies the machine `scripts/config.json` in, sets the worktree-scoped
   `bernini.feature` git config, and moves in any tracker parked at
   `bernini/.claude/features/<name>.md` (a feature migrating from another checkout).
3. Opens a tmux window (always in the `ws` session, one window per feature) running
   `claude --permission-mode <m> "bcp-feature <name> <prompt>"` in the worktree. The mode defaults
   to `acceptEdits` — file edits flow, but Bash/gh stop at a permission prompt until someone
   attaches — and is never inherited from your user config, so a `bypassPermissions` default on
   your machine does not leak into unattended agents. Pass `--mode` to override (e.g.
   `--mode bypassPermissions` for a feature you deliberately want fully autonomous).

The seeded `config.json` is a copy of the main clone's — the machine default. The build preset in
it is a *choice*, not a machine fact (on Windows, one feature may build dx12 while another builds
vulkan), so `--preset <p>` re-inits the worktree's own copy with that preset: `init.py` re-derives
the preset-dependent fields and carries the stored LFS credential across, and no other checkout is
touched. The same works by hand at any time: `just init --preset <p> --force` inside the worktree.

Set `WS_NO_AGENT=1` to stop after step 2 and get a prepared worktree with no agent.

### `ws attach [<name>]`

Watch the agents: attaches to the `ws` tmux session, optionally jumping straight to one feature's
window. The window is the agent's live interactive session — you can type instructions, approve
permission prompts, or interrupt it directly. `Ctrl-b n`/`Ctrl-b p` cycle between feature windows
and `Ctrl-b w` lists them. For a non-interactive peek at what an agent is doing,
`tmux capture-pane -p -t ws:<name>` prints its screen.

**Leaving: detach, don't exit.** `Ctrl-b d` detaches — your terminal comes back and the agent
keeps running; reattach any time. Closing your terminal window amounts to the same thing. But
`Ctrl-d` / typing `exit` go to the Claude session *inside* the window and end the agent (recover
with `ws feature <name> --continue` — see below). Ending an agent is `ws done`'s job, not the
keyboard's.

### `ws done <name>`

Tears the feature down: removes the worktree (the git-ignored tracker and worktree config die with
it), kills the tmux window, deletes `feat/<name>`. Refuses a dirty worktree or an unmerged branch
rather than forcing — override by hand if that is really what you want.

## Stopping and resuming a feature

A feature's state lives in layers, and each survives different things:

| State | Where | Survives |
|---|---|---|
| commits on `feat/<name>` | git (shared object store; origin once pushed) | everything (once pushed) |
| uncommitted edits | the worktree | agent exit, reboot — anything but `ws done` / disk loss |
| the bcp-feature tracker | `<worktree>/.claude/features/<name>.md` (git-ignored) | same as the worktree |
| the agent's conversation | claude's per-project history for that worktree | agent exit, reboot |

So an agent that exited, crashed, or was lost to a reboot has destroyed nothing. To recover:

- **`ws feature <name> --continue`** — reuses the worktree and resumes the worktree's previous
  claude conversation, full context restored (each worktree is its own claude project, so
  `--continue` finds the right history). Add a prompt to say what to do next:
  `ws feature vat --continue "picking up after reboot — check watch-pr state"`.
- **`ws feature <name>`** (plain) on an existing worktree **asks at the terminal**: resume the
  previous conversation? (default yes) — and if resuming, compact it first? (default no —
  compacting frees context but replaces the transcript with a summary; when compacting, any
  prompt argument is deferred to `ws attach`, since `/compact` takes the first input). Answering
  no to resume starts a *fresh* conversation on the bcp-feature prompt — the skill re-derives
  where it was from the tracker and the PR state; right when the old conversation isn't worth
  carrying. Non-interactive runs skip the questions and start fresh.

The one thing with no second copy is the worktree itself: the tracker and uncommitted edits die
with it. That is `ws done`'s refusal semantics — it will not remove a dirty worktree or delete an
unmerged branch, so finished work must be pushed (or force-discarded by hand) before teardown
succeeds. A feature that must survive the *machine* needs its branch pushed; the tracker is
machine-local by design.

### `ws list`

Every live feature: `git worktree list` for the checkouts, `gh pr list` for the open PRs.

## Layout

```
ws                     # dispatcher: ./ws <command> [args]
scripts/               # the command implementations
CLAUDE.md              # the map every nested Claude session inherits
PLAN.md                # the design and its task list
bernini/               # main clone — stays on master (quick fixes, landing)
bernini-test-project/  # test project, used against bernini builds
bernini.features/      # one worktree per feature
  <name>/              # feat/<name>, home of that feature's session and tracker
```

Sessions open **in the checkout being worked on** — `bernini/` for quick fixes and landing,
`bernini.features/<name>/` for feature work. Nobody works in the workspace root; only the `ws`
commands run here.
