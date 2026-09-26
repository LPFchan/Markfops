# Compatibility Watchlist

Use this watchlist during every upstream intake review.

These surfaces need explicit scrutiny because they can break downstream compatibility, upgrade flow, or public contracts even when the upstream change looks routine.

| Surface | Why it is sensitive | Questions to ask every time |
| --- | --- | --- |
| Public SDK, API, or type exports | Third-party or internal extensions may depend on these contracts | Does this change add, remove, rename, or reinterpret a public contract? |
| Plugin, extension, manifest, discovery, install, and package identity | Changes here can break loading, installation, or migration | Does this preserve existing identity and install behavior? |
| Config schema, aliases, and migrations | Small config changes can create upgrade drift quickly | Is this a pure cleanup, or will it change what existing configs mean? |
| Auth profiles, provider identity, and runtime state paths | These often affect onboarding, recovery, and upgrade continuity | Does this change login, stored auth, provider routing, or state lookup semantics? |
| Routing, dispatch, or delivery seams | Hidden changes here can break channels, extensions, or internal integrations | Does this preserve shared dispatch behavior and final-delivery semantics? |
| Security hardening with compatibility implications | Some hardening closes risky but real downstream assumptions | Are we fixing a bug, or changing an implicit contract someone may rely on? |
| Onboarding and setup flows | Upstream onboarding can encode product assumptions the fork does not want | Is this generic setup improvement or upstream-specific product direction? |
| Migration-sensitive runtime identity surfaces | Paths, names, namespaces, and state keys are hard to change later | Does this affect names, paths, or compatibility aliases that still matter? |

Update this watchlist when a new compatibility-sensitive seam appears more than once in intake work.