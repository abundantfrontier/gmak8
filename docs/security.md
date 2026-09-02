# Security

Private signing material never belongs in this repository. Rotation is a GitHub Actions secret update plus a matching public artifact in the next release.

## Secrets (GitHub Actions)

| Secret | Use | Public counterpart |
| --- | --- | --- |
| Cosign private key | Sign guest and k3s airgap archives | `guest/airgap/cosign.pub` and the copy pinned in the app |
| Sparkle EdDSA private key | Sign Sparkle archives / appcast | `SUPublicEDKey` in `Apps/gmak8/App/Info.plist` (`SparklePin.publicEDKey`) |
| Notary API key (`.p8`) | `notarytool submit` | Apple Developer issuer / key id (not secret by themselves; the `.p8` is) |

Do not commit Cosign private keys, Sparkle EdDSA private keys, or Notary `.p8` files. Do not paste key bytes into workflow YAML.

## Rotation

1. Generate a new key offline.
2. Store the private key in the GitHub Actions secret. Delete local copies.
3. Replace the public counterpart in the tree (Cosign PEM or Sparkle `SUPublicEDKey`).
4. Ship a release that both **is signed with the old key** (so current apps can update) **and** contains the new public key, then sign subsequent releases with the new key.
5. Revoke or disable the previous secret.

## App updates

An app update **quits gmak8-core** and **restarts the cluster**. Do not replace `gmak8.app` while `gmak8-core` is alive.

Sparkle 2 uses EdDSA over an HTTPS appcast. Install path:

1. `willInstallUpdate` sends engine `prepareUpdate`.
2. `gmak8-core` ACPI-stops the guest, closes disk flocks, unlinks `engine.sock`, and exits 0.
3. The UI unregisters the `gmak8-core` LaunchAgent (`SMAppService` agent only — not the menu extra) so KeepAlive cannot respawn from the old bundle.
4. Wait until `engine.sock` is gone and `os.img` / `data.img` sidecar flocks are released (60 s). Fail the update if not.
5. Sparkle swaps `gmak8.app`.
6. Register the agent and launch `gmak8-core` from the new bundle (Helpers / `Contents/MacOS`, never `PATH`).
7. If Settings “keep cluster running” is on, `start`.

Updates require **`/Applications`**. Translocation (Downloads, quarantine) already refuses `SMAppService` register.

## Signing

Sign every Mach-O with the same Developer ID Team ID and Hardened Runtime: `gmak8` (app + CLI), `gmak8-core`, `gvproxy`, `buildctl`, `virtctl` when present, and Sparkle Autoupdate / XPC. UI entitlements omit `com.apple.security.virtualization`. `gmak8-core` sets it true. No App Sandbox.

Go helpers may need extra hardened-runtime exceptions; measure before adding them.

See `scripts/package-dmg.sh` and `scripts/notarize.sh`.
