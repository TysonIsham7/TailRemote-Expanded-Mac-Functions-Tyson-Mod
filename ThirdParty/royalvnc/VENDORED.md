# Vendored RoyalVNCKit

- Upstream: https://github.com/royalapplications/royalvnc
- Base commit: 0a76294a7cdc8616b2eea5fba958415e544ed34b
- License: MIT, see LICENSE in this folder (unchanged from upstream).

This copy carries TailRemote modifications on top of the base commit,
including the macOS Screen Sharing server-scale message
(`appleServerScale`, `VNCConnection+AppleScale.swift`). It is committed
as plain files, not a submodule. Edit it here directly; do not re-run
scripts/prepare-picture-scale.sh over it or the changes will be lost.

Upstream's `Design/` artwork is left out of this copy.
