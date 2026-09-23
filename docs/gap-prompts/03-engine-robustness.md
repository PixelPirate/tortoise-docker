# Agent prompt: Engine robustness — retry/backoff, arbitration, orphan cleanup

You are working in the TortoiseBots module checkout at
`/Users/pho/Turtle/New/TortoiseBots` (branch `main`, pinned upstream commit
`76a0a13d`). The image repo consuming your work is
`/Users/pho/Turtle/New/tortoise-docker` — read `docs/SPEC.md` for conventions.

## Problem

The capability ledger row `F25-SCHED` ("Scheduling + soak plan", audit DONE,
spec DONE, implementation missing) records that the bot engine lacks the
robustness machinery the donors have:

- **No engine retry/backoff**: an action that fails is retried on a tick loop
  with no decay, so bots can thrash or stall. Note: config plumbing for
  `failedActionRetryBaseMs` / `failedActionRetryMaxMs` already exists
  (`PlayerbotAIConfig.h` ~line 366, "Issue #84: bounded failure backoff
  tuning") — but there is **no consumer implementing the backoff**.
- **No central arbitrator**: competing background services (random bot
  population, LFT fill, BG queue, AH market) resolve conflicts only through
  emergent fail-closed guards.
- **Solo-idle triple-eligibility**: an idle solo bot can be simultaneously
  eligible for three services; selection order is undefined (ledger: "restart
  orphans" and "restart orphans (BG/LFT queues)" — a realm restart leaves
  bots registered in BG/LFT queues with no session to drain them).
- Donor reference for the *behavior* (not code): Shyalya's engine has
  retry/TTL/path-retry/crowd/slice budgets; AC's mod-playerbots has the
  operations queue with failure-retry guards.

Player-visible effect: bots that freeze in place, spam-fail an action, or
ghost-occupy queue slots after a server restart.

## Task

1. **Engine backoff (do this first, it is bounded)**: implement the failure
   backoff the #84 config anticipates. Find the engine tick
   (`ai/playerbot/strategy/Engine.cpp`) and action failure paths; on repeated
   failure of the same action/target, skip it for
   `failedActionRetryBaseMs` growing to `failedActionRetryMaxMs`. Honor the
   existing test harness: `tools/test_engine_failure_backoff.cpp` exists —
   read it, it encodes the expected semantics; make it pass.
2. **Restart orphan cleanup**: on module/session init, clear stale queue
   memberships for bots that no longer have a live session (BG queue via
   `runtime/BattlegroundQueueService.cpp`, LFT via `LftBotFillService.cpp`).
   Deterministic drain at startup, no background polling.
3. **Solo-idle arbitration**: define and implement a fixed priority order for
   the triple-eligibility case (document the order you chose in the code),
   or a simple lock so one service wins per tick.
4. Do NOT attempt a full central arbitrator redesign — that is a F25 follow-up;
   deliver the three bounded fixes above.

## Constraints

- No DB/world scan/network on the bot tick (project perf posture, `docs/PLAN.md`
  §9). Backoff state is in-memory per bot.
- All new tunables must read from `PlayerbotAIConfig` and be documented in
  `ai/playerbot/aiplayerbot.conf.dist.in`, then wired through the image's
  `docker/penqle/render-config.sh` + `.env.example.penqle` +
  `docker-compose.penqle.yml` + README table if user-facing.
- Keep fail-closed: an error in new code must disable the optimization, not
  the bot.

## Deliverable

1. Working changes in the TortoiseBots checkout; the failure-backoff test
   harness passes (compile and run it standalone if a full build is not
   possible — it is designed for that).
2. Patch `docker/penqle/patches/00N-engine-robustness.patch` (image repo),
   `git apply --check` clean against pin `76a0a13d...`.
3. Ledger row `F25-SCHED` updated: which of the three gaps closed, which
   remain.

## Verify

- `git apply --check` on the patch.
- Host contract script still passes (`tools/verify_penqle_host_contract.sh
  --core /Users/pho/Turtle/New/tortoise-wow`).
- Backoff harness: `tools/test_engine_failure_backoff.cpp` compiles and passes.
- Reasoning check: a bot whose movement action keeps failing stops re-attempting
  it every tick and resumes after the backoff window.
