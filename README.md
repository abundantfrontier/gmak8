# gmak8

**gmak8** is a native SwiftUI macOS appliance for one local Kubernetes cluster. Individuals, students, and companies use the same MIT binary.

0.9 is the engine, menu extra, first-run, recovery, and Sparkle path. Workload GUI is 1.0.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon
- Xcode with Swift 6
- Go (to build `gvproxy` into `Contents/Helpers`)
- The app **must** live in `/Applications/gmak8.app` or the LaunchAgent will refuse to register
- Run `bash scripts/ci.sh` locally (or on a Mac/Linux builder you control) **before** pushing to GitHub. There is no GitHub Actions CI.

## Run locally (functionality testing)

Double-click `scripts/dev-install.command` in Finder (rebuilds Debug, installs `/Applications/gmak8.app`, opens it). From a terminal:

```bash
bash scripts/dev-install.sh
```

If the running copy is outside `/Applications`, first-run **Permissions** has **Install to /Applications**. Walk first-run (Welcome → Create and start). Current-context stays **off** unless you check it. Guest download is the Cosign-verified GitHub Release pin (`gmak8-guest-0.0.1-arm64.raw.zst`).

What you can test **without** `os.img`:

- First-run pages, `/Applications` gate, nested-virt badge, profile radios, CLI copy to `~/.local/bin`
- Menu extra, close last window vs Quit, Settings, Recovery / Diagnostics zip
- Start failing with a missing OS disk (honest, not a hang)

What you **cannot** test until a guest disk exists (download the Release pin, or build with mkosi on Linux arm64 — not vendored here):

- VM boot, k3s Ready, kubeconfig splice, NodePort curl

Override a local disk for bring-up (not a substitute for Cosign-verified cache):

```bash
defaults write dev.gmak8.core osImage /path/to/guest.raw
```

See [guest/README.md](guest/README.md).

## Build / test only

Run this before every push:

```bash
bash scripts/ci.sh
```

Open `Apps/gmak8/gmak8.xcodeproj` and run the **gmak8** scheme if you are iterating in Xcode — still copy the result to `/Applications` before expecting `gmak8-core` to register.

The CLI (`status`, `version`, `start`, `stop`, `image list|load|prune`) is `gmak8.app/Contents/Helpers/gmak8`, never PATH.

## License

MIT License. See [LICENSE](LICENSE). Third-party notices (gvproxy) are in [NOTICE](NOTICE).

## Design

See [docs/design.md](docs/design.md).
