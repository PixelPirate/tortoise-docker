# Patches applied to the core at image build time (after the pinned clone).

Local patches on top of the pinned `CORE_COMMIT` (see `Dockerfile.penqle`).
The core is a separate upstream from the bot module, so its series lives in its
own folder and is applied to `tortoise-wow` before the module patches (the
module build reads the core tree).

Rules (same contract as `../patches`):

- One feature per patch, numbered `NNN-description.patch`, applied in numeric
  order so each applies on top of the previous.
- Every patch must apply cleanly with `git apply --check` against the pinned
  `CORE_COMMIT`; the Docker build fails otherwise.
- Re-verify and rebase the whole series whenever `CORE_COMMIT` moves, exactly
  as `docs/bot-patch-refresh.md` does for the module series.
- Propose each patch upstream to `tortoise-wow/tortoise-wow`; delete it here
  once the pin includes it.

## 001-headless-bot-visibility-elision.patch

Skips create/out-of-range object blocks and movement-broadcast subscriptions
between two headless (bot) sessions (`Headless.BotVisibilityElision`, default
on). Bots have no client, so those packets are dropped at the send path anyway,
after the per-packet script-hook dispatch in `WorldSession::SendPacket`; in a
crowded zone the per-(bot, bot) pair cost grows with the square of the local
population. Real players keep full visibility in both directions, and the
visible-GUID bookkeeping is kept, so group updates, stealth detection
(`Unit::IsVisibleForInState`) and emote/text targeting are unaffected. Bot AI
never reads these lists (it targets through grid searchers). Motivated by
`docs/perf-analysis-2026-10-01.md` (crowd culling).
