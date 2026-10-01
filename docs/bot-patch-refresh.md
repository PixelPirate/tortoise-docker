# Refreshing the TortoiseBots patch series

Runbook for moving the image to a newer TortoiseBots upstream `main` while
keeping the local bot work alive. It rebases the `enhancements` branch, folds
it back into the numbered patches the image applies at build time, re-pins the
module, and rebuilds the stack.

This document is the single input: an agent with fresh context should be able
to perform the whole refresh from here, plus the two reference checkouts on
this machine. House rules for any module change (vanilla 1.12 IDs only,
fail-closed, no silent no-ops, ledger row updates) live in
`docs/gap-prompts/README.md` and still apply.

## The three words this runbook runs on

- **pin** — the commit SHA the Docker build checks out for a source
  (`BOTS_COMMIT` / `CORE_COMMIT` in `Dockerfile.penqle`).
- **boundary** — a commit on the cleaned feature branch that ends exactly one
  patch; a patch is the diff between two consecutive boundaries.
- **prefer main** — on a rebase conflict where upstream and `enhancements`
  solve the same problem, upstream's code wins; the local feature keeps only
  what upstream does not already do.

## When to run this

Run it whenever the module pin should move (routine: upstream `main` takes
commits several times a day) or when a patch needs to be dropped because
upstream absorbed it. Do **not** run it to add a feature: new features start
from `docs/gap-prompts/` and land as a new patch on the existing series.

## Inputs and invariants

| Path | Role |
|---|---|
| `/Users/pho/Turtle/New/TortoiseBots` | Module checkout. `main` tracks upstream; `enhancements` holds the local work; the image pins an upstream `main` SHA plus the patches. Read/write. |
| `/Users/pho/Turtle/New/tortoise-docker` | This repo. Owns `Dockerfile.penqle`, `docker/penqle/patches/`, the pin docs. Read/write. |
| `/Users/pho/Turtle/New/tortoise-wow` | Core checkout. Reference only; do not modify. |

### Pins

The build pins two SHAs in `Dockerfile.penqle` (`CORE_COMMIT`, `BOTS_COMMIT`),
declared immediately before the clone `RUN`. Read the current values from
there, and resolve each source's tip without touching the reference checkouts:

```bash
git ls-remote https://github.com/tortoise-wow/tortoise-wow.git main   # CORE_COMMIT
git ls-remote https://github.com/Sagiroth/TortoiseBots.git main          # BOTS_COMMIT
```

Both move on every run of this runbook. A core bump is accepted only if the
module's host-contract gate passes in the build; if the new core tip fails it,
revert the core pin (or fix the module) before proceeding.

Invariants that must hold at the end:

- `enhancements` is linear on top of the new upstream `main` tip (no merge
  commits), and applying every patch in numeric order to a checkout of the new
  `BOTS_COMMIT` reproduces `enhancements`' source tree (docs excluded).
- Every patch applies with `git apply --check` against the new `BOTS_COMMIT`.
- The patch numbering has no gaps; retired patches are recorded in
  `docker/penqle/patches/README.md`.

## Pipeline

1. **Rebase** `enhancements` onto `main` (`prefer main` on conflicts).
2. **Regenerate** the patches from the rebased branch.
3. **Re-pin, rebuild, start** the image.

Each stage below ends with its own completion criterion; do not start the next
stage until it holds.

---

## Stage 1 — Rebase `enhancements` onto `main`

### 1.1 Sync and back up

```bash
cd /Users/pho/Turtle/New/TortoiseBots
git fetch origin
git status                                   # must be clean
NEXT=$(git for-each-ref --format='%(refname:short)' 'refs/heads/backup/enhancements-pre-rebase*' \
  | grep -oE '[0-9]+$' | sort -n | tail -1)
git branch "backup/enhancements-pre-rebase-$(( ${NEXT:-0} + 1 ))" enhancements
git checkout main
git merge --ff-only origin/main              # local main == origin/main
git checkout enhancements
```

Backups are the only undo for a bad rebase; take one every run even if the
last few look unused.

### 1.2 Rebase

```bash
git rebase main
```

Conflicts stop the rebase. Resolve, `git add`, `git rebase --continue`.
A commit that becomes empty because upstream now contains it is dropped with
`git rebase --skip` (see 1.4).

### 1.3 Conflict policy: prefer main

When both sides solve the same problem, keep upstream's code and adapt the
local side to it. Two shapes recur:

- **Additive conflict** (both sides add a different include, member, or
  registration) — keep both. There is no shared problem to arbitrate.
- **Same-problem conflict** (both sides rework the same function or policy) —
  take upstream's version, then re-apply only the part of the local feature
  upstream still lacks. If upstream's version makes the local feature
  redundant, drop the feature (1.4).

Worked example from the 2026-09-30 re-pin: `bb8dbc2 Force rebuff on ready
check` conflicted in `PlayerbotAI.h` (upstream added `BotDiagnostics.h`, the
patch added `ForceRebuff.h` — additive, keep both) and in
`CastBuffSpellAction` (upstream had reworked the same upkeep-buff retry loop —
same problem, upstream wins; the patch keeps only its rebuff-window hooks that
upstream lacks). Re-derive each resolution from the two trees; do not copy
this example blindly.

Do not resolve a conflict by deleting upstream code to keep the local shape,
and do not `--skip` a commit merely because it is inconvenient.

### 1.4 Retire features upstream absorbed

For each commit the rebase reports as empty (or that a resolution reduced to
nothing), the matching patch is now dead:

1. Delete `docker/penqle/patches/NNN-*.patch`.
2. Add a short entry under `## Merged upstream since the last pin` in
   `docker/penqle/patches/README.md` saying what upstream now owns.
3. Leave the numbering gap documented (the README already does this: patch 011
   was dropped and numbering continued at 012).
4. If the feature had env-mapped settings, remove them from
   `docker/penqle/render-config.sh`, `.env.example.penqle`, the compose file,
   and the `README.md` settings table — unless upstream's `.dist` now defines
   the same key, in which case keep the mapping and point it at upstream.

**Completion criterion (Stage 1):** `git rebase main` finishes with no rebase
in progress, `git log --merges main..enhancements` is empty, and
`git status` is clean.

---

## Stage 2 — Regenerate the patch series

The patches are consecutive diffs of a **clean branch**: `enhancements` with
the doc-only commits removed and each feature's follow-up/fixup commits
squashed into the feature's boundary, so no patch carries a transient
add-then-remove. Build the clean branch in a scratch worktree; never generate
patches from `enhancements` directly.

### 2.1 Build the clean branch

```bash
cd /Users/pho/Turtle/New/TortoiseBots
NEWPIN=$(git rev-parse main)                 # == origin/main tip
git worktree add --detach /tmp/bots-clean "$NEWPIN"
cd /tmp/bots-clean
git checkout -B clean                        # -B: reset a stale branch from a prior run

pick()   { git cherry-pick    "$(git log -1 -F --format=%H --grep="$1" enhancements)"; }
squash() { git cherry-pick -n "$(git log -1 -F --format=%H --grep="$1" enhancements)" \
           && git commit --amend --no-edit; }
```

Then replay the boundaries in the order of the table below. The subjects are
taken from the rebased `enhancements`; confirm each lookup resolves
(`git log -1 -F --grep='...' enhancements`) before running it, and that the
resulting `git log --oneline "$NEWPIN"..clean` has exactly one commit per
patch.

| Patch | Commit subjects to replay (top to bottom, in this order) |
|---|---|
| 001 | `Summon bot to player when grouped.` |
| 002 | `Don't do generic crowd control inside non-raid dungeons.` |
| 003 | `Add manual creature avoidance.` |
| 004 | `Force rebuff on ready check.` |
| 005 | `Harden trade packet handling on refusal.` |
| 006 | `Rework spell interrupt calls to CastStop.` |
| 007 | `Grind RPG corrections.` |
| 008 | `Engine robustness.` + squash `Drop solo-idle claim registry superseded by the lease manager` |
| 009 | `Port raid boss tactics for Onyxia, MC, BWL, and Naxx fights.` |
| 010 | `Dungeon Clear port.` + squash `Make the vendored tree compile against the Penqle core.` + squash `Fix wrong character in config.` + squash `Provision dungeon-clear test bots with MakeComplete after factory refactor.` |
| 012 | `Improve bot performance.` + squash `Fix tick-divisor stagger skipping via return not continue.` + squash `Batch the real-player scan used by the bot AI stagger gate.` |

Doc-only commits are deliberately not replayed: `Record QoL batch ledger
rows.` and `Record raid boss tactics ledger row.` (the patches ship source
only; docs stay on `enhancements` and in the module repo).

If Stage 1 retired a feature, delete its row and renumber nothing — leave the
gap and continue.

### 2.2 Emit the patches

Each patch is the diff between its boundary and the previous one, excluding
docs. Emit in order so a patch always applies on top of the previous:

```bash
cd /tmp/bots-clean
P=/Users/pho/Turtle/New/tortoise-docker/docker/penqle/patches
BOUNDS=( "$NEWPIN" $(git rev-list --reverse "$NEWPIN"..clean) )   # boundaries, oldest first
NAMES=( 001-summon-when-group 002-dungeon-cc-suppression 003-avoid-creature \
        004-force-rebuff-ready-check 005-trade-cancel-hygiene 006-interrupt-caststop \
        007-grind-rpg-corrections 008-engine-robustness 009-raid-boss-tactics \
        010-dungeon-clear 012-bot-ai-tick-divisor )              # drop names of retired patches
for i in "${!NAMES[@]}"; do
  git -c core.abbrev=7 diff --no-color "${BOUNDS[$i]}" "${BOUNDS[$((i+1))]}" \
    -- . ':(exclude)docs/' ':(exclude)*.md' > "$P/${NAMES[$i]}.patch"
done
```

`core.abbrev=7` keeps the `index` lines byte-stable with the existing series;
`git apply` ignores them either way. Patch 010 is ~6 MB and expected.

### 2.3 Verify the series

Apply the whole series to a scratch checkout of the new pin and confirm the
result equals `enhancements` (docs excluded). This is the acceptance check:

```bash
cd /Users/pho/Turtle/New/TortoiseBots
git worktree add --detach /tmp/bots-verify "$NEWPIN"
cd /tmp/bots-verify
for p in /Users/pho/Turtle/New/tortoise-docker/docker/penqle/patches/*.patch; do
  git apply --check "$p" || exit 1
  git apply "$p" || exit 1
done
git add -A
git diff --cached enhancements -- . ':(exclude)docs/' ':(exclude)*.md'   # must be empty
```

Then clean up: `git worktree remove --force /tmp/bots-verify` (and
`/tmp/bots-clean` once its patches are emitted).

**Completion criterion (Stage 2):** the `git diff --cached` above prints
nothing, and every patch passed `git apply --check`.

---

## Stage 3 — Re-pin, rebuild, start

### 3.1 Bump the pins and their docs

```bash
CORE_NEW=$(git ls-remote https://github.com/tortoise-wow/tortoise-wow.git main | cut -f1)
BOTS_NEW=$(git -C /Users/pho/Turtle/New/TortoiseBots rev-parse main)
# Dockerfile.penqle: ARG CORE_COMMIT=<CORE_NEW>, ARG BOTS_COMMIT=<BOTS_NEW>
# (both declared immediately before the clone RUN; do not reorder)
```

Also update both pins in `docker/penqle/patches/README.md` (the "Pins these
patches are written against" block) and `docs/SPEC.md` (§0 path table, the
re-pin note, and any pin reference). The core bump is only accepted if the
build's host-contract gate passes (see Gotchas).

### 3.2 Build and start

```bash
cd /Users/pho/Turtle/New/tortoise-docker
docker build -f Dockerfile.penqle --build-arg CPU_TARGET=armv8-a \
  -t tortoise-docker:penqle-bots .
docker compose -f docker-compose.penqle.yml up -d
docker compose -f docker-compose.penqle.yml logs -f mangosd
```

`CPU_TARGET` defaults to `x86-64-v2` for x86_64 CI; on ARM/Apple Silicon pass
`armv8-a` or the compile fails with `unknown value 'x86-64-v2' for '-march'`.
The build compiles the core (1–6 hours) and fails fast on a bad patch, the
host-contract check, or the `-march=native` guard. A `.env` must exist
(copy from `.env.example.penqle`); client data must be under `DATA_PATH`.

### 3.3 Acceptance

- Image builds; host-contract verify passes inside the build.
- `mangosd` logs the world-server-ready line; `realmd` is up.
- Module migrations apply on first `mangosd` start (AutoUpdater lines in
  `docker compose logs mangosd`).
- Any newly added/removed env setting is reflected in `README.md`'s settings
  table and takes effect after restart.

This is the `docs/SPEC.md` §5 checklist; run it as the definition of done.

**Completion criterion (Stage 3):** the stack is up and the §5 checklist
passes.

---

## Rollback

- Rebase went wrong: `git checkout enhancements && git reset --hard
  backup/enhancements-pre-rebase-N`.
- Patches wrong but rebase good: delete the regenerated patches, rebuild the
  clean branch from `enhancements`, and re-emit (Stage 2 is repeatable).
- Image wrong but patches verified: `git revert` the pin commit; the previous
  image tag still exists locally.

## Gotchas

- `git worktree add <path> <branch>` fails while that branch is checked out in
  the main worktree; always use `--detach` (or a new branch, as in 2.1).
- Do not generate patches from `enhancements`: the fixup commits would leak
  transient add-then-remove changes into the series.
- Do not `git apply` a patch without `--check` first in the build; a patch
  that only applies after the previous one must be verified in order.
- The clean branch is scratch. `enhancements` keeps its history (fixups
  included); only the patches are squashed.
- When a patch is retired, its env-mapped keys are the easiest thing to
  forget; grep `render-config.sh` and `.env.example.penqle` for the feature.
- A core bump is a separate risk: the module's host-contract gate
  (`tools/verify_penqle_host_contract.sh --core .`) runs in the build and must
  pass against the new core tip. If it fails, revert the core pin rather than
  weakening the gate.
