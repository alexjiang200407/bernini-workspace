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

Then install tab completion once (see [`ws completions`](#ws-completions-zshbash---install) below),
and open a new shell:

```sh
ws completions --install
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

It also points every checkout's editor at the test project — see below. Re-running `ws init` is
safe: clones that exist are skipped, `just init` is skipped once `bernini/scripts/config.json`
exists, and the editor configs are only filled in where they are missing. That is the way to
backfill checkouts made before a workspace change.

#### The editor's startup project, and which checkout its window came from

`apps/editor/config.json` is the editor's own settings file — git-ignored, one per checkout,
deployed next to the binary by cmake. Two of its keys are the workspace's business, and `ws init`
and `ws feature` fill both in:

- `startupProject` names the project the editor opens on launch. It ships empty
  (`config.example.json`) because the repo has no idea where a project lives; the workspace does,
  so it is set to `bernini-test-project/Test Project.berniniproject`. `just run editor` in any
  checkout then comes up on the test project instead of the empty state, with no browsing to the
  same project once per worktree.
- `instanceName` leads the editor's window title. Running two checkouts side by side is what a
  worktree per feature is *for*, and their windows are otherwise identical — same title, same
  project. It is set to the checkout's own name (`master` for the main clone), so the windows read
  `vat — Bernini Editor — Test Project` and `master — Bernini Editor — Test Project`.

The file is the editor's, not ws's. An existing one is patched in place, never replaced, and each
key only when it holds nothing usable — a `startupProject` that is empty or names a path that is
gone (a config carried in from another machine), an empty `instanceName`. A value that stands is
somebody's choice and is left alone. One caveat on a checkout that was already built: cmake chooses
`config.json`-or-`config.example.json` at *configure* time and copies it next to the binary after
linking the editor, neither of which a file that changed underneath them triggers — so the build
keeps deploying what it was built with until `just build --configure` says otherwise. ws says so
when it matters.

### `ws doctor`

Checks the workspace for problems and exits non-zero on any `FAIL`: platform (Git Bash is
rejected), required tools (`git`, `python3`, `tmux`, `claude`, `git-lfs`), the clones, whether
`just init` has been run, whether `bernini/` is parked off master, whether LFS assets smudged or
are still pointer text, stale worktree registrations, per-worktree seeding, whether each checkout's
editor has a startup project that still exists, and the `ws` PATH symlink. `warn`s are things the
workspace survives; `FAIL`s break `ws feature` or the builds inside it.

### `ws completions [<zsh|bash>] [--install]`

Prints the completion script for a shell (yours, unless you name one). `--install` puts it where
that shell will find it, which is the whole reason the flag exists: zsh only autoloads `_ws` from a
directory on its `$fpath`, and `$fpath` is whatever your config makes it — a Homebrew
`site-functions` directory is on it only if something added it, while oh-my-zsh contributes its own
`custom/completions`. So `--install` asks an interactive zsh what its `$fpath` actually is and
writes into a directory from that list, preferring one no package manager or framework update will
overwrite. Then open a new shell. `ws doctor` reports where the file is — and warns if one exists
somewhere `$fpath` never looks, which completes nothing and looks exactly like no completion at all
(zsh quietly falls back to completing filenames).

Only the shim is installed. Everything that knows about ws lives in `ws __complete`, in the repo,
so new commands, flags and features complete without reinstalling anything.

What completes: the commands, described by their one-line headers; live features for `attach`,
`done` and `cmd`, each shown with the branch its checkout is on; for `ws feature`, those plus the
`feat/*` branches that have *no* worktree — the resumable ones, minus any branch already checked
out somewhere, which git would refuse anyway; branch names for `--branch`; for `--preset`, the
presets this host can actually select (bernini's own answer, so a mac is never offered the
`windows-*` half of `CMakePresets.json`); and the fixed sets for `--mode` and `--model`.

Past `ws cmd <name> --`, completion hands the line back to the shell's ordinary command completion,
run **inside that checkout** — `ws cmd vat -- cat apps/edi⇥` completes against the worktree, not
against your current directory. zsh does this properly; bash needs `bash-completion` for the
handoff, and macOS's stock bash 3.2 falls back to command names and plain filenames.

The shims are thin on purpose: both ask `ws __complete` what to offer. One implementation, so the
shells cannot drift apart, and a new script in `scripts/` completes the moment it lands — there is
no list of commands or flags to keep in sync. Scripts named `_*` are plumbing: routable
(`ws __complete`), hidden from `ws` usage.

### `ws feature <name> ["<prompt>"] [--cycle|--one-shot] [--branch <b>] [--preset <p>] [--mode <m>] [--model <m>] [--continue] [--no-agent]`

Starts (or resumes) a feature:

1. Fetches origin and pulls master (below), then adds a worktree at `bernini.features/<name>` on
   branch `feat/<name>` —
   branched from `origin/master`, or reused as-is if the branch already exists locally or on
   origin (resume). `--branch <b>` borrows an existing branch instead (see below).
2. Seeds the worktree: copies the machine `scripts/config.json` in, points the editor's
   `apps/editor/config.json` at the test project and names its window after the feature
   (above), sets the worktree-scoped
   `bernini.feature` git config, and moves in any tracker parked at
   `bernini/.claude/features/<name>.md` (a feature migrating from another checkout).
3. Opens a tmux window (always in the `ws` session, one window per feature) running
   `claude --permission-mode <m> "<workflow> <prompt>"` in the worktree — under `ws _agent`, so
   the agent's background watchers end when it does (below). The mode defaults
   to `bypassPermissions` — feature agents run unattended, so nothing stops at a prompt; bernini's
   own guard hooks (`gh pr` blocking, PR-watch) still apply. Pass `--mode` to gate a specific
   feature instead (e.g. `--mode acceptEdits` lets edits flow but stops Bash at a permission
   prompt until someone attaches). A *fresh* session at a terminal is asked which model to run
   on first — `opus`, `sonnet`, `haiku`, any other name typed through to `claude --model`, or
   Enter for the configured default; `--model <m>` answers it up front, and non-interactive runs
   take the default silently. A resumed conversation keeps the model it was started on, so the
   question is skipped for `--continue`. When run at a
   terminal, it then attaches you straight to the agent's window — `Ctrl-b d` to step back out;
   non-interactive runs just print the window name and return. If the feature's agent is already
   running, `ws feature <name>` simply attaches to it — one agent per feature, and the command is
   idempotent: it converges on "worktree exists, agent running, you're looking at it".

**The workflow: `--cycle` or `--one-shot`.** Not every change wants the same ceremony, so the agent
is started on one of two skills:

| | runs | the work lands as | `bernini.feature` |
|---|---|---|---|
| `--cycle` (default) | `bcp-feature <name> <prompt>` | the plan as its own PR, then one task PR at a time into `feat/<name>`; only the finished feature is proposed to master | `feat/<name>` |
| `--one-shot` | `bcp-implement <prompt>` | research → implement → test → docs → **one** PR to master | empty |

That last column is not bookkeeping. `bernini.feature` is the precheck's diff base, and
`bcp-implement` reads it being set as "this is a feature branch after all" and hands over to
`bcp-feature` — so a one-shot leaves it empty, exactly as a borrowed branch does, and its diff is
measured against `origin/master`. A fresh session at a terminal is asked which workflow to run;
`--cycle`/`--one-shot` answers up front, and non-interactive runs default to `cycle`. The answer is
recorded in the worktree (`bernini.wsWorkflow`), so resuming the feature later neither asks again
nor re-seeds the wrong base.

**A new feature needs a prompt.** There is nothing for an agent to do without one — `bcp-feature`
would open a feature named `<name>` with no idea what it is for. So a fresh session is asked for a
prompt if it was not given one, and a non-interactive run refuses outright, *before* creating the
worktree, rather than leaving one behind. Two exceptions, both of which carry the intent already:
`--continue` (the conversation has it) and pointing `--cycle` at a feature that already exists —
`bcp-feature` picks that up and reports where it stands.

An existing worktree is asked about *before* any of that: resume the previous conversation? Say yes
and the question of a prompt never comes up, because the conversation is the intent. Only a fresh
session on a `--one-shot` worktree still has to say what the change is — `bcp-implement` is one
change described once, so unlike `--cycle` there is no feature state for it to pick up.

The seeded `config.json` is a copy of the main clone's — the machine default. The build preset in
it is a *choice*, not a machine fact (on Windows, one feature may build dx12 while another builds
vulkan), so `--preset <p>` re-inits the worktree's own copy with that preset: `init.py` re-derives
the preset-dependent fields and carries the stored LFS credential across, and no other checkout is
touched. The same works by hand at any time: `just init --preset <p> --force` inside the worktree.

`--no-agent` (or `WS_NO_AGENT=1`) stops after step 2 and leaves a prepared worktree with no agent —
a checkout to build and run the editor in, nothing more.

#### Pulling master

Step 1 fetches *and* fast-forwards the main clone's master (`scripts/_sync-master`), because
nothing else in the workspace ever moves it. A new feature is cut from `origin/master` and is
current either way — `bernini/` is the one that quietly falls weeks behind, and it is the checkout
everything else leans on: the quick fix you make in it starts from an old master, `ws cmd bernini`
builds yesterday's tree, and `ws done` reads a feature merged on GitHub as unmerged and refuses to
delete its branch. So `ws done` pulls master too, right before that judgement.

Fast-forward only, and never over anything. A clone mid-rebase or with a change in the way is left
exactly as it is with a note; if master is not the checked-out branch, only the ref moves and your
working tree is untouched. Since this is a real pull, it also smudges the LFS assets of whatever
changed — a long-idle clone can take a moment to catch up.

#### What the agent leaves running

`bcp-feature` backgrounds a `just watch-pr <n>` that polls for hours, and claude starts such a
shell *detached*: its own process group, no controlling terminal. Nothing that ends the session
reaches it. An agent that exits by itself does clean up after itself, but every other way out —
`ws done`, a killed window, a terminal that went away — left the watcher polling a PR nobody was
reading and waking that dead session's notification hook every hour until someone hunted the pid
down.

So the agent runs under `scripts/_agent`, which forks a watchdog and then **`exec`s claude**: the
pane's process is still claude itself, same pid, same process group, same terminal. Ctrl-C, the
TUI, the exit status and the moment the window closes are all exactly what they were — the wrapper
is not in the middle of any of it. Beside it, the watchdog samples claude's process tree every 5s
(`WS_AGENT_SAMPLE_SECONDS`) and, once claude is gone, takes down what is left — `TERM`, then
`KILL`. Each remembered process is stored with its command line and killed only if it still
matches, so a pid the kernel has reused since is left alone. It has to be a poll rather than a look
around at teardown: a detached shell is identifiable only as a child of claude, and the moment
claude exits its children reparent to launchd and look like every other process on the machine.

What that sweeps up is *everything* the agent backgrounded, not only `watch-pr` — a build or a
server it left running goes too. Anything started outside the agent (`ws cmd`, your own shell, a
tmux window the agent opened) is not its child and is untouched. `WS_AGENT_LOG=<file>` records what
was killed; by default the watchdog writes nowhere and holds no terminal, since a process holding
the pane's would keep the window alive after the agent had exited.

#### Borrowing a branch: `--branch <b>`

bernini is multi-platform, so a fix written on Windows often has to be built and debugged on the
mac. `ws feature macdebug --branch feat/culling --no-agent` gives that branch its own checkout here
without ws pretending it owns it:

- **The branch must already exist** locally or on origin. `--branch` never creates one — a new
  branch off master would build clean and debug nothing, so it is an error instead.
- **`ws done` leaves it alone.** The worktree records `bernini.wsBorrowed=true`, and teardown
  removes the worktree and tmux window but never the branch. Delete it by hand if you want it gone.
- **`bernini.feature` is left empty**, so the diff base stays `origin/master`. That config is the
  precheck's base (`origin/$FEATURE`), not a label: point it at the branch you are debugging and a
  precheck diffs the branch against itself and reports a clean slice.
- **Staleness is handled.** `git worktree add` reuses the *local* ref, so a branch the other machine
  has pushed to since is silently old — the fix you came to test simply isn't there. A fresh
  worktree is fast-forwarded to `origin/<b>` (nothing local to lose) and says so; an existing one is
  warned about instead.
- **An agent, if you start one, gets no `bcp-feature` prompt** — that would open a feature workflow
  on top of someone else's in-flight branch. It gets your prompt, or a bare session.
- `<name>` stays the key (directory, tmux window, `ws done` argument) and is independent of the
  branch — branch names carry slashes that neither the layout nor `tmux -t ws:<name>` can take.

Two things `--branch` cannot do. It cannot check out `master` (the main clone holds it, and git
refuses a branch that is checked out elsewhere) — build master in `bernini/` itself. And it does
nothing about the branch now moving on two machines: commit and push from whichever one you fixed
it on, and pull before continuing on the other.

### `ws attach [<name>]`

Watch the agents: attaches to the `ws` tmux session, optionally jumping straight to one feature's
window. The window is the agent's live interactive session — you can type instructions, approve
permission prompts, or interrupt it directly. `Ctrl-b n`/`Ctrl-b p` cycle between feature windows
and `Ctrl-b w` lists them. For a non-interactive peek at what an agent is doing,
`tmux capture-pane -p -t ws:<name>` prints its screen.

Each terminal watches independently. Two clients of one tmux session share that session's current
window, so terminal 2 switching to `taa-improvements` would yank terminal 1 off `vat` too; instead
every attach gets its own throwaway session (they show up in `tmux ls` as `ws-view-<pid>` while
attached). The view dies with the terminal that asked for it; the agents belong to `ws` and outlive
it.

What the view holds depends on how you asked for it, and that decides where your terminal goes when
an agent's window closes:

| | the view | when a window closes |
|---|---|---|
| `ws attach` | a session *grouped* with `ws`: the same window list — `ws feature`'s new windows appear, `ws done`'s vanish — with its own selection | you asked for all of them, so tmux moves you to another window |
| `ws attach <name>` | that one window, linked in from `ws` | nothing is left in the session, so tmux drops you back to your shell |

The one-window view is the point of naming a feature. Grouped, an agent you exited would close its
window and slide your terminal onto whichever window came next — you would be typing into a
different feature's live agent with no sign that anything changed.

**Leaving: detach, don't exit.** `Ctrl-b d` detaches — your terminal comes back and the agent
keeps running; reattach any time. Closing your terminal window amounts to the same thing. But
`Ctrl-d` / typing `exit` go to the Claude session *inside* the window and end the agent; your
terminal comes back to its shell, and that agent is gone (recover with `ws feature <name>
--continue` — see below). Ending an agent is `ws done`'s job, not the keyboard's.

### `ws cmd <name> [--] <command> [args...]`

Run something in a feature's checkout without cd-ing there: `ws cmd vat -- just run editor`. One
terminal then serves the whole workspace — build in one worktree, run the editor from another,
`ws cmd bernini -- git log` in the main clone — instead of a window parked in each. `<name>` is a
feature (the same key `ws feature` and `ws done` take) or `bernini` for the main clone; `--` is
optional and only matters when the command itself starts with a dash.

The command runs in the foreground with your terminal attached — interactive tools, `Ctrl-C`, and
the exit status all pass straight through, so it chains and pipes like anything else. **The cwd is
the checkout**, not wherever you invoked `ws` from: relative paths resolve inside the worktree,
reads and writes both. If what you actually wanted was a shell there, that is a command too:
`ws cmd vat -- $SHELL`.

The feature's agent may be working in the same checkout (`ws attach <name>` shows what it is up
to) — two concurrent builds share one build directory and will trip over each other.

### `ws done <name>`

Tears the feature down: removes the worktree (the git-ignored tracker and worktree config die with
it), kills the tmux window — which takes the agent's backgrounded watchers with it, see [what the
agent leaves running](#what-the-agent-leaves-running) — and deletes the branch ws created for it.
Refuses a dirty worktree or an
unmerged branch rather than forcing — override by hand if that is really what you want. "Unmerged"
is git's judgement against the *local* master, so master is [pulled first](#pulling-master);
otherwise a feature merged on GitHub is refused for being merged somewhere this clone cannot see.
A borrowed
branch (`ws feature --branch`) is not ws's to delete: the worktree and window go, the branch stays.

Removing the worktree deletes everything in it, git-ignored content included — that includes the
`build*/` tree, so a debug checkout costs a full rebuild if you bring it back. (Untracked files that
are *not* ignored make `git worktree remove` refuse outright; clean them up or force by hand.)

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
