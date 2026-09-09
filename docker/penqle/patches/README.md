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

## Rules

- One feature per patch, numbered, named `NNN-description.patch`.
- Every patch must apply cleanly with `git apply` against the pinned
  `BOTS_COMMIT` — the Dockerfile fails the build otherwise.
- When bumping `BOTS_COMMIT`, re-verify all patches; rebase as needed.
- The same changes are applied to the local checkout
  `/Users/pho/Turtle/New/TortoiseBots` for reference; if you upstream a patch
  into TortoiseBots proper, delete it here after the pin includes it.
