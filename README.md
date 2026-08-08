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
workspace root (skipping any that already exist), then runs `just init` in `bernini/` — which
generates the machine `config.json`, installs the git hooks, and configures the LFS transfer agent
(see `bernini/docs/lfs.md`).

Re-running `ws init` is safe: clones that exist are skipped, and `just init` is skipped once
`bernini/scripts/config.json` exists.

### `ws doctor`

Checks the workspace for problems and exits non-zero on any `FAIL`: platform (Git Bash is
rejected), required tools (`git`, `python3`, `tmux`, `claude`, `git-lfs`), the clones, whether
`just init` has been run, whether `bernini/` is parked off master, whether LFS assets smudged or
are still pointer text, stale worktree registrations, per-worktree seeding, and the `ws` PATH
symlink. `warn`s are things the workspace survives; `FAIL`s break `ws feature` or the builds
inside it.

### `ws feature <name> ["<prompt>"] [--preset <p>]`

Starts (or resumes) a feature:

1. Fetches origin, then adds a worktree at `bernini.features/<name>` on branch `feat/<name>` —
   branched from `origin/master`, or reused as-is if the branch already exists locally or on
   origin (resume).
2. Seeds the worktree: copies the machine `scripts/config.json` in, sets the worktree-scoped
   `bernini.feature` git config, and moves in any tracker parked at
   `bernini/.claude/features/<name>.md` (a feature migrating from another checkout).
3. Opens a tmux window running `claude "bcp-feature <name> <prompt>"` in the worktree. If no tmux
   server is running, starts a detached session named `ws` instead — attach with
   `tmux attach -t ws`.

The seeded `config.json` is a copy of the main clone's — the machine default. The build preset in
it is a *choice*, not a machine fact (on Windows, one feature may build dx12 while another builds
vulkan), so `--preset <p>` re-inits the worktree's own copy with that preset: `init.py` re-derives
the preset-dependent fields and carries the stored LFS credential across, and no other checkout is
touched. The same works by hand at any time: `just init --preset <p> --force` inside the worktree.

Set `WS_NO_AGENT=1` to stop after step 2 and get a prepared worktree with no agent.

### `ws done <name>`

Tears the feature down: removes the worktree (the git-ignored tracker and worktree config die with
it), kills the tmux window, deletes `feat/<name>`. Refuses a dirty worktree or an unmerged branch
rather than forcing — override by hand if that is really what you want.

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
