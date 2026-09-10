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

## Rules

- One feature per patch, numbered, named `NNN-description.patch`.
- Every patch must apply cleanly with `git apply` against the pinned
  `BOTS_COMMIT` — the Dockerfile fails the build otherwise.
- When bumping `BOTS_COMMIT`, re-verify all patches; rebase as needed.
- The same changes are applied to the local checkout
  `/Users/pho/Turtle/New/TortoiseBots` for reference; if you upstream a patch
  into TortoiseBots proper, delete it here after the pin includes it.
