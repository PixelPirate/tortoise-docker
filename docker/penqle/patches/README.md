# Patches applied to TortoiseBots at image build time (after the pinned clone).

## 001-summon-when-group.patch

Ports AzerothCore mod-playerbots' `AiPlayerbot.SummonWhenGroup` behavior:
a bot that accepts a group invitation teleports to the inviter when it is
beyond sight range or on another map (falls back to normal travel if no safe
teleport spot is found).

Touches: `PlayerbotAIConfig.{h,cpp}` (new `summonWhenGroup` option),
`UseMeetingStoneAction.h` (expose `SummonAction::Teleport`),
`AcceptInvitationAction.h` (the summon-on-join logic),
`aiplayerbot.conf.dist.in` (documented config key).

## 002-dungeon-cc-suppression.patch

Ports AzerothCore mod-playerbots PR #2648 ("stop the generic cc strategy
from firing in 5-man dungeons"): a new `Strategy::IsSuppressed()` virtual
that `Engine::Init()` honors by skipping the strategy entirely, and the
generic per-class "cc" strategies return suppressed while the bot is in a
non-raid dungeon. Open world, raids, battlegrounds, and per-dungeon instance
strategies (Onyxia/MC/BWL/Naxx, their own named CC) are unaffected. Covers
Polymorph, Shackle Undead, Turn Undead, Scare Beast, Hibernate, Freezing
Trap, Sap, Entangling Roots, Banish, Fear (all verified present in Vanilla
spell data). Dragon's Breath / Blast Wave relocation in the donor PR was
skipped (not Vanilla spells). No new config key; behavior documented as a
comment in `aiplayerbot.conf.dist.in`. Implementation-verified,
gameplay-untested.

Touches: `Strategy.h` (the virtual), `Engine.cpp` (skip in `Init()`),
`PlayerbotAI.{h,cpp}` (`IsInNonRaidDungeon()` helper),
`ClassStrategy.{h,cpp}` (suppression helper + legacy `CcStrategy` family),
the seven forward-ported `Generic*Strategy.h` cc classes,
`aiplayerbot.conf.dist.in` (comment only).

## 003-avoid-creature.patch

Ports the Shyalya donor's avoid-creature system: a chat-managed list of
creature entries a bot must not target or approach. `avoid creature <id|name>`
adds, `-` removes, `?` lists, `reset` clears (`AvoidCreatureListAction` +
`AvoidCreatureListValue`, persisted via the generic `save ai` store;
`CreatureIdValue` resolves ids/names against core creature templates). When a
listed creature comes within 10y, the `avoid specific creatures` strategy
(installed on both combat and reaction engines) fires
`CloseToSpecificCreaturesTrigger` → `MoveAwayFromSpecificCreatures`, reusing
the existing dungeon move-away pathing. The navmesh area filter ("avoid
mobs"/"set avoid area") remains fail-closed — the core has no path area
API — with ledger-pointing comments instead of silent no-ops. No new config
key; the list starts empty and is player-managed. Implementation-verified
(wiring checker live-missing=0), gameplay-untested.

Touches: `strategy/actions/AvoidCreatureListAction.{h,cpp}`,
`strategy/values/{AvoidCreatureListValue.{h,cpp},CreatureIdValue.{h,cpp}}`,
`generic/CombatStrategy.{h,cpp}` (the strategy),
`generic/ChatCommandHandlerStrategy.cpp` (supported command),
`actions/ChatActionContext.h`, `actions/ActionContext.h`,
`actions/DungeonActions.{h,cpp}`, `actions/SetAvoidAreaAction.cpp`,
`triggers/ChatTriggerContext.h`, `triggers/TriggerContext.h`,
`triggers/DungeonTriggers.{h,cpp}`, `values/ValueContext.h`,
`StrategyContext.h`, `AiFactory.cpp` (strategy installs + posture comments).

## 004-force-rebuff-ready-check.patch

Ports AzerothCore mod-playerbots PR #2571 ("force rebuff on ready check"):
when a ready check is issued out of combat, bots whisper their readiness
report and top up missing/short buffs before confirming ready — a bot with
outstanding buff work (including casts that fail for missing reagents) stays
not-ready until the ready check ends. A `rebuff` chat command runs the same
buff pass manually (works regardless of the config key), and heals yield to
buffing while the pass runs. Kept from the donor: the 2-minute rebuff-window
ceiling, buff triggers re-evaluated every tick during the pass, and the
buffs-topped-toward-full-duration refresh margin
(`AiPlayerbot.ForceRebuffMarginSecs`, default 60).
`AiPlayerbot.ForceRebuffOnReadyCheck` ships default **off** (donor default)
and is exposed as `AI_FORCE_REBUFF_ON_READY_CHECK` in the image (rendered
config, `.env.example.penqle`, compose, README table).

Touches: `strategy/generic/ForceRebuff.{h,cpp}` (new: rebuff window state,
strategy, buff-first multiplier), `Trigger.{h,cpp}` (buff-trigger virtuals +
per-tick eval), `GenericTriggers.{h,cpp}` (duration-aware `BuffTrigger`,
`ForceRebuffPendingTrigger`), `TriggerContext.h`, `Engine.cpp` (cycle roll +
buff-proposed note), `GenericSpellActions.{h,cpp}` (`CastBuffSpellAction`
buff-work note), `ReadyCheckAction.{h,cpp}` (defer/report split, `force
rebuff` + `ready reply` actions), `WorldPacketActionContext.h`,
`ChatTriggerContext.h`, `ChatCommandHandlerStrategy.cpp`,
`StrategyContext.h`, `AiFactory.cpp`, `PlayerbotAI.{h,cpp}` (window state,
cast note), `PlayerbotAIConfig.{h,cpp}`, `aiplayerbot.conf.dist.in`.

## 005-trade-cancel-hygiene.patch

Ports the portable half of AzerothCore mod-playerbots PR #2651 ("fix selfbot
trading and trade cancellations"): a session null guard before touching trade
packets, and the refusal path factored into a `TradeStatusAction::CancelTrade()`
helper that sends the cancel packet so the bot never sits in a phantom
open-trade state (Tortoise's refusal branch already sent it; the helper keeps
that guarantee in one place). The donor's selfbot-refusal half is not ported:
selfbots are blocked upstream in TortoiseBots (ledger F18) and bot traders are
handled by the module's `PlayerbotAIStorage` gate. No config key.

Touches: `strategy/actions/TradeStatusAction.{h,cpp}`.

## 006-interrupt-caststop.patch

Ports AzerothCore mod-playerbots PR #2680 ("rework spell interrupt calls"):
every force-interrupt call site that stopped "whatever the bot is doing"
now uses the core's `Unit::CastStop()`, which only ends casts a player could
stop — no cancelling of in-flight projectiles or queued melee swings, no
synthetic spell-failure packets. Site-by-site: the reaction interrupt,
`Reset(full)` and the fall handler in `PlayerbotAI.cpp` use `CastStop()`;
`ReInitCurrentEngine()` no longer interrupts at all (donor end-state);
`MovementAction::MoveTo2` no longer force-interrupts when starting to move
(the core's natural move-interrupt flags break the cast like they do for a
player); `MovementAction::Follow` uses a plain `CastStop()`;
`JumpAction::DoJump` and the drink/eat actions use `CastStop()`. The
`PlayerbotAI::InterruptSpell()` wrapper is kept for the "stop attacking"
target-drop (no donor counterpart; already flag-gated and packet-clean).
The donor's WotLK-only raid/dungeon call sites (ICC/Gruul/UK/Seth/Kara) have
no Tortoise files, and Tortoise has no always-false interrupt guards of the
donor's BattlegroundTactics shape. No config key.

Touches: `PlayerbotAI.cpp`, `strategy/actions/MovementActions.cpp`,
`strategy/actions/UseItemAction.h`, `strategy/generic/FleeStrategy.cpp`
(comment only).

## 007-grind-rpg-corrections.patch

Ports the Shyalya donor's four grind/RPG corrections (ledger `F04-RPG`,
donor branch `playerbots-integration-gh` post-`1f9497e`): (1) **crowd
tally** — `ChooseRpgTargetAction::HasSameTarget` becomes a precomputed
`GetTargetCounts` tally so the "too many bots on one rpg target" limit
applies at every population instead of being disabled at 200+ nearby
players; (2) **RNG source** — the per-call `time(0)`-seeded
`std::mt19937` in `ChooseRpgTargetAction::Execute` and
`RpgAction::SetNextRpgAction` is replaced with the shared thread-local
`*GetRandomGenerator()` (already in the compat shim); (3) **patrol
pause** — `MoveToRpgTargetAction` drops vanished/unpathable rpg targets
into the ignore list and stops the move leg (`isUseful` returns false)
instead of chaining legs against a stale target; (4) **taxi-cheat
exclusion** — flight masters are rejected as ambient rpg targets
(`PossibleRpgTargetsValue::AcceptUnit`) and as rpg destinations
(`RpgTravelDestination::IsActive`) for taxi-cheat bots, and
`MovementAction::UseTaxi` fails closed on flight paths the bot has not
learned (unless the taxi cheat is enabled), gains an optional
established flight-master argument, and `RpgTaxiAction` routes ambient
free flights through it funding the exact fare only. No new config key.
The level-5 RPG travel gate (`runtime/BotManager.cpp`) and the persisted
`ai_playerbot_zone_level` destination cache are untouched.
Implementation-verified (wiring checker live-missing=0), gameplay-untested.

Touches: `TravelMgr.cpp` (`RpgTravelDestination::IsActive`),
`strategy/actions/{ChooseRpgTargetAction.{h,cpp},RpgAction.cpp,`
`MoveToRpgTargetAction.cpp,MovementActions.{h,cpp},RpgSubActions.cpp}`,
`strategy/values/PossibleRpgTargetsValue.cpp`.

## 008-engine-robustness.patch

Closes the remaining bounded F25-SCHED gaps (gap prompt
`docs/gap-prompts/03-engine-robustness.md`). The engine failure backoff half
of F25 needed no patch: the pinned `BOTS_COMMIT` already contains the
`ActionFailureBackoff` policy and its `Engine` consumer (upstream issue #84),
with `AiPlayerbot.FailedActionRetryBase`/`FailedActionRetryMax` (plus the
cache TTL/size keys) documented in `aiplayerbot.conf.dist.in` and wired as
`AI_FAILED_ACTION_RETRY_BASE`/`AI_FAILED_ACTION_RETRY_MAX` in the image.

(1) **Restart orphan cleanup** — deterministic one-shot drains at module
init, no background polling. BG side: `character_battleground_data` rows
persist across a realm restart while core queue memberships do not, so
sessionless random-bot characters carried stale rows;
`BattlegroundQueueService::Initialize` deletes them scoped to the
`RandomBotAccountPrefix` account pool and offline characters only (human
rows keep the core's own relogin handling). LFT side:
`LftBotFillService::Initialize` drains core queue/offer entries whose
character has no live session through the native `LFTMgr::LeaveQueue`
cancellation path (a no-op at cold start, a deterministic drain on warm
re-init).

(2) **Solo-idle arbitration** — an idle solo bot can be simultaneously
eligible for the AH market errand, the BG auto-queue, and the LFT fill.
`BotManager::ClaimIdleBot` implements a per-tick claim (keyed by a tick
counter bumped at the top of `BotManager::OnWorldUpdate`, so one claimant
wins per bot per world tick regardless of WorldScript dispatch order). The
effective priority is the fixed host update order: AH market → BG auto-queue
→ LFT fill; losing services re-evaluate the bot on a later interval, and
cross-tick conflicts stay covered by the existing fail-closed eligibility
guards. No new config key; no central arbitrator (explicit F25 follow-up).

Touches: `runtime/BotManager.{h,cpp}` (claim registry),
`runtime/AhMarketService.cpp` (claims), `runtime/BattlegroundQueueService.{h,cpp}`
(BG data drain + claims), `runtime/LftBotFillService.{h,cpp}` (LFT drain +
claims). Implementation-verified (host contract + backoff harness pass),
gameplay-untested.

## Rules

- One feature per patch, numbered, named `NNN-description.patch`.
- Every patch must apply cleanly with `git apply` against the pinned
  `BOTS_COMMIT` — the Dockerfile fails the build otherwise.
- When bumping `BOTS_COMMIT`, re-verify all patches; rebase as needed.
- The same changes are applied to the local checkout
  `/Users/pho/Turtle/New/TortoiseBots` for reference; if you upstream a patch
  into TortoiseBots proper, delete it here after the pin includes it.
