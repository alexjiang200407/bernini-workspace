# bernini-workspace — checkouts and agents for AI-parallel Bernini development

The plan for turning three independent clones (`bernini`, `bernini-v2`, `bernini-v3`) into one
workspace: a single main clone, one git worktree per feature, one Claude session per checkout.

## The layering principle

**bernini stays checkout-agnostic; bernini-workspace owns checkouts and agents.**

A solo developer clones bernini and never touches this workspace — everything in the repo works in
a plain clone. The repo carries only *worktree-compatibility*: correctness that must hold wherever
a checkout sits.

| | bernini (self-sufficient) | bernini-workspace |
|---|---|---|
| bcp-feature mechanics (plan PR, task loop, precheck, watch) | ✅ | — |
| worktree-safe `watchlist.py`, worktree-scoped `bernini.feature` | ✅ | — |
| worktree creation/removal, `config.json` seeding | — | `ws feature` / `ws done` |
| agent spawning (tmux + `claude` launch) | — | `ws feature` |
| layout map (`CLAUDE.md`, inherited by nested sessions) | — | ✅ |
| cross-feature status (worktrees × PR states) | — | `ws list` |

Rejected alternative: baking worktree creation into bcp-feature (the shape PR #303 currently has).
It couples the repo to a layout choice, and the session that starts a feature begins in one
checkout and `cd`s into another mid-flight. #303 **lands as-is** (its fixes are needed
regardless); a follow-up PR slims SKILL.md § 1/§ 5 to "run in the current checkout" once the `ws`
scripts exist to take the choreography over.

Rejected alternative: bernini as a submodule of the workspace. A submodule pins a SHA, which
fights a constantly-moving master; the clones are working state, not content — they are
git-ignored instead.

## Layout

```
~/source/bernini-workspace/
  PLAN.md                # this file
  CLAUDE.md              # the map every nested session inherits (parent-CLAUDE.md loading)
  .gitignore             # bernini/, bernini.features/, bernini-test-project/
  ws                     # dispatcher: `ws <command>` routes to scripts/
  scripts/               # the scripts below
  bernini/               # main clone — stays on master, never parked on a feature
  bernini-test-project/  # clone of the test project, used against bernini builds
  bernini.features/      # one worktree per feature, created on demand
    vat/
```

Sessions open **in the checkout being worked on** — `bernini/` for quick fixes and landing,
`bernini.features/<name>/` for feature work. Nobody works "in" the workspace root; only the `ws`
scripts run there. The root `CLAUDE.md` is inherited downward by every nested session, which is
how each agent knows it is one checkout among several.

## The bootstrap

The thing that exists before any worktree is the workspace itself. `ws feature` runs at the root:

```
ws feature <name> "<prompt>"
  1. git -C bernini fetch origin
  2. git -C bernini worktree add ../bernini.features/<name> -b feat/<name> origin/master
     (no -b when feat/<name> already exists — resume)
  3. worktree init:
       [ -f bernini/scripts/config.json ] && cp it into the worktree   # machine config, git-ignored
       git config extensions.worktreeConfig true                       # idempotent
       git config --worktree bernini.feature feat/<name>
  4. tmux new-window -c bernini.features/<name> -n <name> \
       claude "bcp-feature <name> <prompt>"
```

The agent is born inside a fully prepared checkout: its project context (CLAUDE.md, skills, memory
path, `just`) is the worktree's from the first token. Interactive tmux sessions, not `claude -p` —
bcp-feature's backgrounded `watch-pr` needs a live session to wake.

Teardown mirrors it: `ws done <name>` → `git -C bernini worktree remove ../bernini.features/<name>`,
kill the tmux window, `git -C bernini branch -d feat/<name>`. The git-ignored tracker and the
worktree config die with the worktree.

`ws init` (once per machine): clone bernini into `bernini/` and the test project
(`git@github.com:alexjiang200407/bernini-test-project.git`) into `bernini-test-project/`, then run
`just init` inside `bernini/` — which also sets up the LFS transfer agent per `docs/lfs.md`.

`ws list`: `git -C bernini worktree list` joined against `gh pr list` — every live feature, its
checkout, its open PRs.

## Tasks

- [ ] W1 PR #303 merges (repo-side worktree compatibility). Gate: merged; `watchlist.py` roundtrip
      in a linked worktree.
- [x] W2 workspace root becomes a repo: `git init`, this file, `CLAUDE.md`, `.gitignore`.
      Gate: a session opened in `bernini/` sees the root `CLAUDE.md` in its context.
      Remote: `git@github.com:alexjiang200407/bernini-workspace.git`.
- [x] W3 `bernini/` finished initializing: on master, `just init`, LFS agent configured.
      Gate: `just build` and an LFS smudge succeed there. (Built 2026-08-08, `macos-metal-debug`,
      311/311; smudge verified by `ws doctor`.)
- [x] W4 `ws feature` / `ws done` / `ws list`. Gate: `ws feature scratch` creates worktree +
      tmux window with a live session; `ws done scratch` leaves `git worktree list` clean.
- [ ] W5 follow-up bernini PR: slim bcp-feature § 1/§ 5 to checkout-agnostic wording.
      Gate: skill text names no workspace paths; a plain-clone run still works.
- [ ] W6 drain the old clones: push `bernini-v3`'s TAA branch; rehome `bernini`'s webgpu stash;
      `bernini-v2` goes last — it owns PR #303 and the in-flight feat/vat work until those migrate.
      Gate: nothing unpushed or stashed in any old clone.
      Progress 2026-08-08: `bernini-v3` drained (pushed `feat/taa-depth-reject-wip`,
      `feat/taa-seed-freeze-wip`, `backup/chunk-container-full`); old `bernini` drained (stash
      rehomed as pushed `feat/webgpu-preset-wip`, stash list empty). Only `bernini-v2` remains,
      by design.

## In-flight state (2026-08-08)

- feat/vat is mid-flight in the old `bernini-v2` clone: plan PR #296 in review. Its tracker has
  moved to `bernini-workspace/bernini/.claude/features/vat.md`; the feature continues from this
  workspace once W3 is done (its worktree: `ws feature vat` — the branch exists, so no `-b`).
- PR #303 (worktree compatibility) is open with a watcher on it, owned by the old `bernini-v2`
  clone until merged.
