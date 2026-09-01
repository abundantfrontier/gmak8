# **gmak8 — Native macOS Local Kubernetes Appliance**

| Field | Value |
| --- | --- |
| **Title** | gmak8: a Kubernetes-first desktop appliance for macOS |
| **Author** | Design Doc Writer |
| **Date** | 2026-09-01 |
| **Status** | Draft (rev 5) — Builderdash SSH bridge |
| **Code name / repo** | `gmak8` |
| **User-facing name** | **gmak8** |
| **License** | Apache License 2.0 |
| **Platform** | **App:** macOS 14 (Sonoma)+ , Apple Silicon only. **KubeVirt / Eureka profile:** macOS 15+ **and** M3+ (nested virt). |
| **Audience** | Senior engineers implementing from a clean-slate repo |
| **Team assumption** | **1–2 engineers.** Public **0.9** = PRs **1–18** (engine + onboarding + recovery + Sparkle-with-VM-stop + cask `gmak8`). **1.0** = PRs **19–28 and 30** (GUI + KubeVirt/Eureka + Builderdash SSH bridge). Rosetta is PR **29**, out of 0.9. |

---
## **Overview**
Local Kubernetes on a Mac is still a kit, not a product. Developers assemble a hypervisor, a Linux VM, a distro, a kubeconfig, port forwards, and a GUI from disconnected tools. Docker Desktop solved “one install, a Linux VM, a GUI, a menu bar” — then wrapped it in a Docker-first engine and a paid SKU. Rancher Desktop is free but Electron + Lima. OrbStack is the best native Mac VM in the category, and it is neither open nor free for commercial use.
**gmak8** is a native SwiftUI/AppKit macOS app that owns a single local Kubernetes cluster end-to-end: Virtualization.framework VM, a signed Linux appliance, k3s + containerd, localhost API access for unmodified kubectl, a menu-bar extra, and a NavigationSplitView client. There is no Docker Engine, no Compose, no Hub, no Pro SKU. Individuals, students, and companies use the same binary under Apache-2.0.
A first-class proving workload is **project Eureka’s Kubernetes / KubeVirt path** (/Users/kb/Documents/GitHub/eureka): AFW adapters k8s-1.33.3 / kubevirt-1.6.1, python/eureka/{k8s,kubevirt,kube_config}.py, and the kops-on-GCE stack Eureka uses in production. gmak8 does **not** run kops, GCE, AWS, or Cilium. It gives an Eureka developer a local cluster that speaks the same Kubernetes + KubeVirt APIs, with virtctl on PATH (Eureka’s SSH ProxyCommand), a storage class Eureka can set on the **data disk**, and (on M3+ / macOS 15+) nested virt so one scaled-down aarch64 KubeVirt VM can actually start. NodePort publish to 127.0.0.1 exists for generic kubectl/curl; it is **not** how Eureka SSHes to VMs. Eureka is not copied into this repo; it is a profile and an addon pack on a general free appliance.
The git repo at /Users/kb/Documents/GitHub/gmak8 is empty. Everything below is greenfield.
---
## **Background & Motivation**
### **Current state**

| Path | What you actually operate |
| --- | --- |
| Docker Desktop Kubernetes | Docker Engine + a hidden VM + optional single-node cluster. Docker-licensed for many companies. |
| OrbStack | Native VM, Docker CLI, k3s add-on. Closed source; commercial use requires a paid license (see OrbStack’s current pricing page — do not hard-code a dollar figure). |
| Rancher Desktop | k3s + containerd/dockerd via Lima. Electron UI is mostly settings. |
| Colima / Lima | Fast CLI, k3s optional. No first-class GUI. |
| minikube / kind / k3d | Powerful, fragmented. kind/k3d need a container engine. |
| OpenLens / Lens | Cluster *client*. Assumes a cluster already exists. |
| Eureka production | kops on GCE, 6× `n2-standard-8` workers, Cilium `bpfLBSock` + `bpfLBSockHostNSOnly`, GCE CSI, amd64 `ubuntu-2404-lts-amd64-latest-vmx-enabled`. Too heavy for a laptop, and not what gmak8 is. |

Pain points this product exists to remove:
1. **“Is the cluster actually up?” — no single, honest status surface.**

2. **Kubeconfig collisions — tools overwrite ****current-context**** or clobber unrelated clusters.**

3. **Port 6443 / NodePorts / LoadBalancers — conflicts are tribal knowledge. Eureka SSH is ****virtctl port-forward --stdio****, not ****ssh -p <nodePort>**** and not HTTPS to ****status.loadBalancer.ingress[0].ip**** (Klipper fills ****192.168.127.2****, which is not a Mac route).**

4. **Images without Docker — ****kind load**** / ****minikube image load**** / ****k3d image import**** are all different.**

5. **Resource sliders that lie — VM RAM is reserved but not explained; DataVolumes are 35–55 Gi each.**

6. **Electron tax — the heavy part is the Linux VM, not Chromium.**

7. **Licensing anxiety — Docker Desktop and OrbStack both create a commercial relationship for company use.**

8. **Eureka inner loop — iterating on ****python/eureka/kubevirt.py****, AFW k8s tests, and VMPool/Service YAML currently means a 6-node GCE cluster.**

### **Why native, why now**
- **Apple’s Virtualization.framework on macOS 14+ is production-quality for Linux: EFI, virtio-net, virtio-fs, virtio-sock, NVMe, Rosetta-for-Linux. Nested virtualization exists on macOS 15+ / M3+ (****VZGenericPlatformConfiguration.isNestedVirtualizationSupported****).**

- **k3s is CNCF, one static binary, containerd, Traefik, local-path, SQLite — the right shape for a laptop. Production Eureka stays kops; local is an appliance that speaks the same APIs.**

- **SwiftUI NavigationSplitView, Settings scenes, MenuBarExtra, and SMAppService are enough to build a HIG-faithful appliance.**

---
## **Goals & Non-Goals**
### **Goals (v1 / 1.0)**
- **One-click install of a notarized ****.app**** in ****/Applications**** (Developer ID, not Mac App Store).**

- **Start / stop / reset / pause one local Kubernetes cluster from the menu bar or main window, with honest progress and logs.**

- **Unmodified ****kubectl****, Helm CLI, Tilt, Skaffold, k9s, Argo, AFW k8s tests, and Eureka’s Python k8s/KubeVirt clients work against a real kube-apiserver at ****https://127.0.0.1:<api-port>**** using a gmak8-owned kubeconfig context. Tilt/Skaffold deploy works; image build/load is ****gmak8 build**** / ****gmak8 image load****. There is no Docker socket shim.**

- **Native GUI (1.0): cluster health, workloads (pods/deployments/…), pod detail (logs, events, YAML, port-forward), KubeVirt objects (VM, VMI, VMPool, DataVolume), node images, Settings, Recovery. Not a Lens clone of Services/ConfigMaps/PVCs as first-class sidebar explorers.**

- **Settings that matter locally: CPU / RAM / disk, profile (Kubernetes / Eureka / Eureka API-only), Kubernetes 1.33.3 channel, cluster name, registry mirrors, host mounts, KubeVirt addon, telemetry (default off).**

- **Image story without Docker: BuildKit in the guest + load into containerd ****k8s.io****; list and prune.**

- **ServiceLB / NodePort auto-publish to ****127.0.0.1**** with a collision UI, for generic ****kubectl****/****curl****. Eureka SSH is ****virtctl**** on PATH (****ProxyCommand virtctl port-forward --stdio=true vm/{name}/{ns} %p**** as in ****image/env.py****), with ****KUBECONFIG**** pointing at gmak8. Ingress-on-8080 and NodePorts are not substitutes for that path. env.py HTTPS to ****EXTERNAL-IP:443**** is out of the local proving workload (API + virtctl only; no privileged host :80/:443 helper).**

- **Builderdash SSH (1.0, Eureka profile):** VMI pod IPs are not Mac routes. gmak8 must make nested-VM SSH reachable from the host as ****127.0.0.1****. Two supported paths: (1) ****virtctl --stdio**** / engine ****portForwardStart**** with ****kind: vm|vmi**** (env.py and any client that can target localhost); (2) L1 guest ****sshd**** published to ****127.0.0.1:<highport>**** so unmodified ****builderdash**** paramiko can use ****proxy_conf**** (Mac → L1 → VMI pod IP:22). Arch, qcow URL, instancetype, and storage class are Eureka ****build.config****, not gmak8 features.

- **KubeVirt addon pack pinned to Eureka: KubeVirt 1.6.1, CDI v1.62.0, common-instancetypes v1.4.0, virtctl v1.6.1 installed as ****~/.local/bin/virtctl****, feature gates VMExport + EnableVirtioFsConfigVolumes. Airgapped operator/operand images plus an aarch64 smoke containerDisk.**

- **Nested virt on when ****isNestedVirtualizationSupported****; honest Pending UI on M1/M2 or macOS 14.**

- **Optional CLI on PATH (****gmak8****) talking to a user-level daemon — no root for the default path.**

- **Free for everyone under Apache-2.0.**

### **Non-goals (v1)**
- **Docker Engine, Docker CLI, Compose, Buildx-as-Docker, Docker Hub accounts, ****/var/run/docker.sock****.**

- **Windows or Linux ports of the app.**

- **Multiple local clusters; browsing remote kubeconfigs (Lens). v2.**

- **Helm ****release UI****, Gateway API UI, service mesh, GPU/USB passthrough, virtctl SSH/expose GUI (CLI ****virtctl**** on PATH is in).**

- **HTTPS to Klipper EXTERNAL-IP / env.py hitting ****ingress[0].ip:443**** locally. That IP is ****192.168.127.2****. Publishing guest :80/:443 onto the Mac needs the privileged helper we deferred. Local proving workload is Kubernetes/KubeVirt API + virtctl, not a GCE-shaped login HTTPS URL.**

- **In-app Network / Config / Storage explorers; command palette (⌘K).**

- **Multi-node local clusters, HA etcd, kind-in-VM, TCG/qemu emulation of nested VMs.**

- **Full Eureka production shape on a laptop (control + login + OrangeFS home/projects + N batch VMs). That is hundreds of GiB of DataVolumes and many nested VMs. v1 Eureka target is scaled-down (below).**

- **Silent amd64 nested VMs. L2 guests are aarch64. Eureka’s GCE image ****ubuntu-2404-lts-amd64-latest-vmx-enabled**** will not run as-is.**

- **Cilium, kops, AWS, GCP as the local runtime.**

- **Mac App Store. Intel Macs. App Sandbox on ****gmak8-core****.**

- **A paid SKU. Beating OrbStack on speed without measurements.**

- **Memory balloon, ****saveMachineState****, disk resize, sample-nginx button.**

### **Later (do not sneak into v1)**
- **Multiple local clusters; remote cluster browse; Helm UI; Gateway API default; extensions; Windows/Linux; privileged helper for host :80/:443; in-cluster registry UI; in-window VT100 exec; full multi-VM Eureka profile if the Mac has RAM/disk; Cilium-on-Eureka-profile; CSI snapshots; balloon after soak.**

### **v1 cut vs 0.9 vs 1.0**

| Milestone | What ships | Who |
| --- | --- | --- |
| **0.9 public beta** | **PRs 1–18.** VM + Debian appliance + disk contract (format unit) + k3s 1.33.3 + airgap + kubectl via `gmak8` context + menu extra + onboarding + recovery + NodePort publish + Sparkle that **quits gmak8-core** + cask `gmak8`. No workload GUI. | 1–2 engineers, first public cut |
| **1.0** | **PRs 19–28 and 30.** 0.9 + Workloads/Pod/Images/Settings GUI + KubeVirt addon pack + KubeVirt sidebar + Eureka profiles + nested virt + `virtctl` on PATH + VMI localhost SSH bridge (Builderdash) + one aarch64 VMI Ready soak | same team, after 0.9 soaks |
| **After 1.0** | PR 29 Rosetta; stretch: AFW test 050 (3 Running VMs + in-guest DNS) | not 1.0 gate |

---
## **Product name, identity, license**
The user-facing name is **gmak8**: Grandma Kate + Kubernetes. It is a nod to the owner’s mother, whom the kids called Grandma Kate (she passed in 2004). The product is not named “Grandma Kate.”

| Item | Decision |
| --- | --- |
| Repo / display name / CLI | **`gmak8`** everywhere: menu bar, About box, docs, cask, kube context |
| Bundle ID | `dev.gmak8.app` |
| LaunchAgent label | `dev.gmak8.core` |
| VZ queue | `dev.gmak8.vm` |
| Kube context / cluster / user | `gmak8` |
| Homebrew | **cask `gmak8`** exposing `binary "gmak8"` |
| App bundle | `gmak8.app` |
| CLI | **`gmak8`** (primary). No `kite` symlink. |
| virtctl | Upstream name **`virtctl`** on PATH (`~/.local/bin/virtctl`) |
| Appcast / downloads | GitHub Releases of the `gmak8` repo (URL is a **build-time constant**). Guest/airgap assets are **separate Release files**, each **< 2 GiB** |
| License | Apache-2.0 on all first-party code |
| Contributor terms | **DCO**, not a CLA |
| Trademark | Name is `gmak8`. Do not ship logo assets we cannot relicense. |

---
## **Competitive landscape**
Positioning: **free, native, Kubernetes-only local appliance for macOS**, with a first-class KubeVirt/Eureka profile.

| Product | License / cost | Native Mac GUI | Owns local cluster | Kubernetes-first | Docker-free | Nested virt / KubeVirt |
| --- | --- | --- | --- | --- | --- | --- |
| **gmak8 (this)** | Apache-2.0, free for companies | SwiftUI | Yes (VZ + appliance + k3s) | Yes | Yes | Yes on M3+/macOS 15; honest no on M1/M2 |
| Docker Desktop | Proprietary; paid for many orgs | Hybrid | Yes | No | No | Not the product |
| OrbStack | Proprietary; commercial license for business | Yes | Yes | No | No | Not positioned as KubeVirt |
| Rancher Desktop | Apache-2.0 | Electron | Yes (Lima + k3s) | Mostly | Optional containerd | Possible via Lima nested virt, not a KubeVirt GUI |
| Colima / minikube / kind / k3d | Apache-2.0 / MIT | None | Yes | Varies | kind/k3d need an engine | minikube #22805 is the same nested-virt ask |
| OpenLens / Lens | Mixed | Electron | No | Client only | N/A | Can browse KubeVirt CRDs if a cluster exists |

**What this uniquely buys:** no Docker license, no Compose surface, a cluster *appliance* plus a small native client, Apache-2.0, and a local Eureka k8s path without GCE.
**What we will not claim:** faster than OrbStack until measured; identical to kops+Cilium+GCE CSI; amd64 nested VMs.
---
## **Information architecture & UX**
gmak8 is an **appliance with a client**, not a Lens clone. The menu bar answers “is my cluster up?”; the main window answers “what is on it?”; Settings answers “how big / which profile / which folders.”
### **Design principles**
1. **macOS, not a web dashboard. NavigationSplitView, toolbar, inspector, Settings scene, About, HIG empty states.**

2. **The VM is the product. Progress, logs, disk, RAM, nested-virt capability are first-class.**

3. **Do not pretend to be ****kubectl****. GUI covers local-dev 80%. Terminal covers the rest. No command palette in v1.**

4. **Never clobber kubeconfig. Own the ****gmak8**** context. Never change ****current-context**** unless the user checks a box (default off after onboarding).**

5. **Secrets redacted. Values ****••••****; diagnostics zip omits keys unless checked.**

6. **Dark/light, window restoration.**

7. **One window + menu bar extra. Close window ≠ quit the extra.**

8. **Honest hardware. Nested virt is a capability badge, not a silent failure.**

### **Profiles (onboarding + Settings → Kubernetes)**

| Profile | Default vCPU | Default RAM | Data disk (sparse) | KubeVirt pack | Nested virt | What it is for |
| --- | --- | --- | --- | --- | --- | --- |
| **Kubernetes** | `min(4, host-2)` | 6 GiB if host ≥ 16 GiB, else 4 GiB | 60 GiB | Off | Off | General local k8s |
| **Eureka** | `min(8, host-2)` | **16 GiB** if host ≥ 24 GiB; **12 GiB** if host ≥ 18 GiB; else refuse this profile | **256 GiB** | On, versions pinned | On if supported; else refuse with copy pointing at API-only | One nested aarch64 VM (`u1.nano`/`u1.medium`, airgapped containerDisk) + CRDs + virtctl SSH. **Not** stock `env.py` / `u1.xlarge` / amd64 cirros |
| **Eureka API-only (tiny)** | 4 | 4 GiB | 60 GiB | On (operator + CRDs) | Off | AFW object tests (ConfigMap, Service, create VM/VMPool YAML) that do **not** need a Running VMI |

Refuse Eureka profile if the Mac has < 18 GiB RAM or < 80 GiB free disk, with a button to switch to API-only.
**Scaled-down Eureka target (v1 / 1.0 gate):** **one** Running aarch64 VMI (airgapped cirros or fedora containerDisk, instancetype **u1.nano** or **u1.medium**, kind: VirtualMachineClusterInstancetype) + CRDs + virtctl stdio port-forward + SA virtiofs mount. Enough to iterate on python/eureka/kubevirt.py with **documented overrides**. **Not** stock env.py (default u1.xlarge = 4 vCPU / 16 Gi — will not schedule in a 12–16 Gi L1). **Not** control + login + OrangeFS + N batch VMs. **Not** AFW test 050 (3 replicas + in-guest DNS) as the 1.0 gate — that is a stretch goal. **Not** https://{loadBalancer.ingress[0].ip}/apps/afw/admin/.
### **Sitemap (v1)**
`flowchart TB`
`  subgraph Menubar["Menu bar extra"]`
`    MB[Popover: state, CPU/RAM/disk, nested-virt badge, Start/Stop, Open gmak8, Terminal, Settings]`
`  end`

`  subgraph Onboarding["First-run"]`
`    O1[Welcome] --> O2[What gmak8 is / is not]`
`    O2 --> O3[Download guest + airgap assets]`
`    O3 --> O4[Permissions + /Applications check]`
`    O4 --> O5[Profile and resources]`
`    O5 --> O6[CLI install]`
`    O6 --> O7[Create cluster]`
`  end`

`  subgraph Main["Main window — NavigationSplitView"]`
`    S1[Cluster overview]`
`    S2[Workloads]`
`    S3[KubeVirt]`
`    S4[Images]`
`    S5[Diagnostics]`
`    S2 --> P[Pod detail]`
`    S3 --> VM[VM / VMI / VMPool / DataVolume detail]`
`    S4 --> IMG[Image detail]`
`  end`

`  subgraph Settings["Settings scene"]`
`    G[General]`
`    R[Resources]`
`    K[Kubernetes / profile / addon]`
`    F[Files]`
`    N[Network / registries / published ports]`
`    A[Advanced]`
`    PR[Privacy]`
`  end`

`  subgraph Fail["Recovery sheets"]`
`    E1[VM panic]`
`    E2[Disk full]`
`    E3[Port conflict API / 8080 / 8443 / NodePort]`
`    E4[k8s not ready]`
`    E5[Guest image verify fail]`
`    E6[Nested virt unavailable]`
`    E7[Disk images locked]`
`    E8[Login item denied]`
`  end`

`  MB --> Main`
`  O7 --> S1`
`  Main --> Settings`
`  Main --> Fail`
Sidebar (1.0): **Cluster**, **Workloads**, **KubeVirt**, **Images**, **Diagnostics**. Not in v1 sidebar: Network, Config, Storage, Events-as-root, command palette. Events live on pod/VM detail.
### **Keyboard (v1)**

| Shortcut | Action |
| --- | --- |
| ⌘, | Settings |
| ⌘F | Filter current list |
| ⌘R | Refresh (watches are automatic) |
| ⌘L | Focus logs if a pod/VMI is selected |
| ⌘1…⌘5 | Sidebar sections |
| ⌘O | Open main window from extra |
| ⌘T | Open Terminal with `KUBECONFIG` pointed at gmak8’s private kubeconfig |
| ⌘I | Toggle inspector |
| ⌘Q | **First time:** sheet “Keep cluster running in the background?” Default matches Settings. Subsequent: honor that choice. Quit **always** leaves or stops the extra consistently — see Menu extra. |
| ⌥⌘Q | Stop cluster and quit app + extra |

---
## **Screens (v1)**
AppKit only where SwiftUI is weak: Terminal.app, NSAlert for reset, Authorization Services only if we ever add an optional /usr/local/bin symlink (v1 default does **not**).
1. **First-run / onboarding**
**Page 1 — Welcome.** “gmak8 runs Kubernetes on this Mac. Not Docker.”
**Page 2 — What you get.** Local cluster, kubectl context gmak8, menu bar extra. Footnote: no Docker. Second footnote: Eureka/KubeVirt is an optional profile.
**Page 3 — Assets.** Download, with SHA-256 + **keyful Cosign** verify (public key **pinned in the app**; not keyless):

| Asset | Role | Size budget (zstd / uncompressed) |
| --- | --- | --- |
| `gmak8-guest-<ver>-arm64.raw.zst` | OS disk seed | **≤ 500 MiB** / ~2 GiB |
| `gmak8-k3s-airgap-v1.33.3-arm64.tar.zst` | k3s system images (pause, CoreDNS, Traefik, local-path, metrics-server, klipper-*) | **≤ 500 MiB** / ~1.5 GiB |
| `gmak8-kubevirt-airgap-1.6.1-arm64.tar.zst` | Eureka profile only: KubeVirt 1.6.1 + CDI v1.62.0 operand images | **≤ 1.5 GiB** / ~4 GiB |

Each GitHub Release asset must stay **under 2 GiB**. Do not ship a single 1.5 GiB “everything” blob as the only path. Offline: “Choose a file…” per asset. **System images are not pulled from Docker Hub at first boot.** That would violate Privacy and the 45–90 s target on VPNs that block docker.io.
**Page 4 — Permissions.**

| Item | Why | Required? |
| --- | --- | --- |
| `VZVirtualMachine.isSupported` | Hardware/entitlement/OS can virtualize. **Not** an exclusive lock against UTM/VirtualBuddy. | Hard fail if false |
| Nested virt probe | `isNestedVirtualizationSupported` | Informational; gates Eureka profile |
| Notifications | Ready / failed | Optional |
| Network client+server | Entitlement, no prompt | Required |
| Folder access | Host mounts | Optional, later NSOpenPanel |
| Login Items (two rows) | (1) `gmak8-core` LaunchAgent owns the VM; (2) login item for the menu extra | Agent required for “cluster stays up”; extra required if “launch at login” |
| App location | **Refuse LaunchAgent registration if translocated or not in `/Applications`** | Required |

No Full Disk Access. No Accessibility.
**Page 5 — Profile + resources.** Radio: Kubernetes / Eureka / Eureka API-only. Sliders pre-filled from the table above. Host-available callouts. Sparse disk explained. Eureka copy (verbatim intent): “This will not run the full GCE stack or stock env.py. u1.xlarge will Pending on this Mac. Use u1.nano/u1.medium and the airgapped aarch64 disk in docs/eureka-local.md. One nested VM + APIs + virtctl. HTTPS to the LoadBalancer IP is not available locally.”
**Page 6 — CLI.** Default: ~/.local/bin/gmak8 **and** ~/.local/bin/virtctl (copy of the bundled virtctl 1.6.1). Also detect /opt/homebrew/bin (Apple Silicon Homebrew). **Never require admin in v1.** If ~/.local/bin is not on PATH, show export PATH="$HOME/.local/bin:$PATH". Do **not** use zsh -ilc from the GUI/LaunchAgent as a source of truth for PATH — it does not match Terminal.app. Eureka SSH needs **virtctl**** on PATH**.
**Page 7 — Create cluster.** Name default gmak8. Kubernetes version **fixed to 1.33.3** for v1 (Eureka AFW pin), not a buffet. Checkbox: “Set gmak8 as kubectl current-context” **unchecked** by default. Primary: **Create and start**.
2. **Cluster stopped home**
Status **Stopped**, last run, primary **Start**, secondary **Reset…** / **Diagnostics**. Footnote about context gmak8 failing until start.
3. **Cluster starting**
Stepped list, not a fake determinate bar. start RPC returns immediately; this UI is driven by the **EngineStatus stream**.

| Step | Signal | Timeout |
| --- | --- | --- |
| 1. Engine running | XPC/socket connected | 5 s |
| 2. Disks locked | `flock` on `os.img` + `data.img` | 2 s |
| 3. Network stack | gvproxy HTTP `/` + vfkit socket | 10 s |
| 4. VM powered on | `VZVirtualMachine.State.running` | 15 s |
| 5. Guest agent | vsock `:1024` `GET /health` (agent starts **after** data disk is formatted and mounted; it is not the formatter) | 90 s first boot (includes mkfs) |
| 6. Data disk mounted | agent `GET /disks` `gmak8_data=mounted` **after** `gmak8-data-format.service` + `mnt-data.mount` succeeded (serial log: `gmak8-data-format: labeled GMAK8_DATA`) | 60 s first boot |
| 7. Airgap import | agent reports k3s images present | 120 s first boot |
| 8. Kubernetes starting | k3s systemd active | 60 s |
| 9. API reachable | `https://127.0.0.1:<api-port>/readyz` | 60 s |
| 10. Node Ready | `Node.Ready` | 60 s |
| 11. Addons | CoreDNS + local-path + (if not disabled) Traefik, metrics-server, ServiceLB | 90 s |
| 12. KubeVirt (Eureka profiles) | `KubeVirt kubevirt/kubevirt` phase `Deployed` | 180 s |

Logs disclosure: serial + engine (streamed). Cancel → Stopping → Stopped.
4. **Cluster running overview**
Header: **Running** · k3s v1.33.3+k3s1 · context gmak8 · API URL · **nested virt: yes/no**.
Cards: control plane (SQLite, /readyz), node (/dev/kvm present or not), addons (CoreDNS, Traefik, metrics-server, local-path, ServiceLB, and on Eureka: KubeVirt, CDI, common-instancetypes).
Meters: VM CPU, RAM, data disk used/sparse/cap. Published ports table (API, 8080/8443, NodePorts).
5. **Workloads browser (1.0)**
Namespace pop-up. Table: Pods as default, plus Deployments/StatefulSets/DaemonSets/Jobs/CronJobs. Empty state: “Apply a manifest, or gmak8 build an image and deploy.” **No sample nginx button.**
6. **Pod detail (1.0)**
Status, containers (secret refs not values), logs (k8s log API, 10k line cap), events, port-forward, YAML, **Open shell in Terminal** via gmak8 exec.
7. **KubeVirt (1.0, Eureka profiles; hidden if addon off)**
Sidebar section with segments: **VirtualMachines**, **VMIs**, **VMPools** (pool.kubevirt.io/v1alpha1), **DataVolumes**.
Columns: Name, Namespace, Status/Phase, Ready, Age. VM detail: running flag, instancetype, DataVolume names, conditions, events, YAML, **Start/Stop** (spec.running / virtctl start|stop). Do **not** embed Open OnDemand. Do **not** build virtctl SSH/expose GUI in v1 (CLI only).
Empty state if nested virt unsupported: “KubeVirt is installed. This Mac cannot run nested VMs (needs Apple Silicon M3 or later and macOS 15+). API objects can still be created; VMIs will stay Pending.”
Pending VMI with VirtLauncher.Unschedulable / missing /dev/kvm: same copy, plus Diagnostics.
8. **Images (1.0)**
Node containerd k8s.io images. System images hidden by default. Load / Build / Pull / Prune. Build uses **bundled ****buildctl**, not a Swift LLB client.
9. **Settings**
**General:** Launch at login (menu extra). Keep cluster running when window closes (default on). **Set current-context on start (default off).** Start cluster at login (default off). Check for updates (Sparkle; **update restarts the cluster** — copy in this tab).
**Resources:** CPU, memory, data disk cap (reset-required to shrink — but **shrink is not in v1**; grow is not in v1 either). Balloon toggle exists, **default off**, disabled with “experimental, not supported in v1”.
**Kubernetes:** Profile picker. Cluster name (reset-required). Version **1.33.3** (read-only in v1). KubeVirt addon toggle (Eureka profiles force on). “Disable bundled” checkboxes map to k3s --disable= values: traefik, servicelb, local-storage, metrics-server. **CoreDNS is not optional. Helm-controller is not a disable checkbox** (see k3s config). Storage class name display: local-path. Eureka profile **refuses to start** unless k3s config has default-local-storage-path: /mnt/data/local-path (PVCs must not land on the 8 GiB OS disk).
**Files:** Host mounts. Show **this Mac’s uid/gid** (typically **501:20**). Warning copy (see virtio-fs). No default $HOME share.
**Network:** API bind 127.0.0.1 only. API port 6443 with autodrop (rewrite kubeconfig server:). Ingress 8080/8443. **Published ports list** (auto NodePorts on/off; default **on** for generic kubectl/curl). Help text: “Eureka SSH uses virtctl, not these NodePorts.” registries.yaml editor; passwords in Keychain. Guest HTTP(S)_PROXY from macOS system proxy (SCDynamicStore), injected into k3s/containerd — **not** “gvproxy honors the proxy for image pulls.”
**Advanced:** Rosetta (see Rosetta). Guest SSH debug (default off). Reset factory.
**Privacy:** Telemetry off. Vendor network: Sparkle, GitHub Releases asset downloads. **Not** Docker Hub for system images.
10. **Menu bar popover**
`[icon]  gmak8                    Running`
`        gmak8 · k3s 1.33.3 · KubeVirt 1.6.1`
`        Nested virt: Yes`
`        CPU 8%   RAM 4.1 / 16 GiB   Disk 40 / 256 GiB`

`        [ Stop ]   [ Pause ]`
`        Open gmak8                 ⌘O`
`        Open Terminal             ⌘T`
`        Published ports (N) ▸`
---
`        Settings…`
`        Check for Updates…        (restarts cluster)`
`        Quit gmak8…`
**Quit vs close:**
- **Close last window → ****ActivationPolicy.accessory****; extra stays; cluster stays (if Settings says so).**

- **Quit gmak8… first time: sheet “Keep cluster running in the background? The menu bar extra will stay.” Default = Settings “keep running”. If the user chooses not to keep running: ACPI-stop VM, unregister extra, quit. If they keep running: quit the main windows but do not destroy the extra; extra is the status surface. Launch at login starts the extra, not only ****gmak8-core****.**

- **A headless 16 GiB VM with no extra is a product bug. Do not allow it.**
Icon: gray stopped, blue starting, filled running, yellow degraded, red failed, pause badge.

11. **Failure / recovery**

| Kind | Recovery |
| --- | --- |
| VM panic / VZ error | Diagnostics zip, Restart VM, Reset |
| Disk full | Reveal images, Prune images. **No resize in v1.** No “restore snapshot.” |
| API port conflict | Switch to 16443 (rewrites both kubeconfig copies’ `server:`), or pick a port; show `lsof` |
| **8080 / 8443 conflict** | Pick alternate host ports; Traefik in guest stays 80/443 |
| **NodePort collision on host** | Skip that port, show row “30663 in use by pid …”, offer remap |
| k8s not ready | k3s journal, Restart Kubernetes, Reset |
| Guest/airgap verify fail | Delete cache, re-download, import file |
| Agent timeout | Restart VM, serial |
| **SQLite corrupt** | **Reset only.** There is no snapshot. Time Machine excludes `vm/`. Copy says so. |
| Hypervisor / RAM pressure | “Another VM may be using CPU/RAM.” **Not** “isSupported is false because VirtualBuddy took a lock.” |
| **Disk images locked** | “Another gmak8 (`engine.sock` live) holds `data.img`. Quit that instance.” |
| Login item denied | Open System Settings → Login Items. Explain **two** rows. |
| Nested virt unavailable | Switch to API-only or Kubernetes profile |
| Translocated app | “Move gmak8 to /Applications and re-open.” |

Diagnostics zip: settings (redacted), engine log, serial, kubectl get nodes,pods -A, KubeVirt/CDI if installed, versions. Credentials opt-in.
Notifications: ready/fail/disk on; CrashLoopBackOff off by default.
---
## **Proposed design — runtime architecture**
### **Stack (v1)**

| Layer | Choice |
| --- | --- |
| Hypervisor | **Virtualization.framework**. Nested virt: `VZGenericPlatformConfiguration.isNestedVirtualizationEnabled = true` iff `isNestedVirtualizationSupported`. |
| Guest OS | **Debian 13 (trixie) arm64 appliance**, EFI, systemd, kernel with **`CONFIG_KVM=y` or `CONFIG_KVM=m`** and **`kvm.ko` in the image**. Image CI greps `/boot/config-*` for either, and asserts `kvm.ko` exists. First boot `modprobe kvm`. No TCG. |
| Kubernetes | **k3s `v1.33.3+k3s1`**, single-node, **SQLite**, `--data-dir /mnt/data/rancher` |
| CRI | k3s embedded **containerd** |
| CNI | k3s default **flannel + kube-proxy + Klipper ServiceLB**. **Not Cilium.** |
| Ingress | Traefik (k3s HelmChart addon). Host publish **8080/8443**, not :80/:443. |
| Disks | **NVMe** via `VZNVMExpressControllerDeviceConfiguration` + `VZDiskImageStorageDeviceAttachment` **`.cached` + `.full`**. Never virtio-blk. |
| Host shares | virtio-fs, user-selected folders only |
| Control plane host↔guest | virtio-sock **HTTP agent on vsock port 1024**. gvproxy is **vfkit unixgram**, not vsock. |
| Data plane | **gvproxy** (`gvisor-tap-vsock`) vfkit unixgram + `VZFileHandleNetworkDeviceAttachment` |
| kubectl | `127.0.0.1:<api-port>` → gvproxy expose → `192.168.127.2:6443` |
| Images in | Stream to data-disk temp → `k3s ctr -n k8s.io images import` |
| Builds | **`buildctl` in `gmak8.app/Contents/Helpers`** → guest `buildkitd` on **vsock 1025** → containerd `k8s.io` |
| x86_64 **containers** | Rosetta for Linux when installed; not a 0.9 blocker |
| x86_64 **nested VMs** | **Out of scope** |
| Time | chrony + agent `PUT /time` on **wake and on resume** |

**Rejected:** QEMU/VirtualBox/HyperKit; k0s/kubeadm/kind-in-VM; CRI-O; vzNAT-only; socket_vmnet/root; SSH-as-control-plane; wrapping Lima; Apple Containerization as the product; Cilium locally; TCG emulation.
### **Process architecture**
Root is **not** required. VZVirtualMachine dies with its process, so the VM lives in a LaunchAgent, not in the UI.
`flowchart LR`
`  subgraph UserSpace["User session — no root"]`
`    UI["gmak8.app — SwiftUI + MenuBarExtra"]`
`    CLI["gmak8 CLI"]`
`    CORE["gmak8-core LaunchAgent\nVZ on serial queue gmak8.vm"]`
`    GVP["gvproxy"]`
`    BCTL["buildctl"]`
`    UI -->|"NDJSON events + RPC"| CORE`
`    CLI -->|"same NDJSON on engine.sock"| CORE`
`    CORE --> GVP`
`    CORE --> BCTL`
`    CORE -->|Virtualization.framework| VZ["L1 Linux VM"]`
`  end`

`  subgraph Guest["L1 appliance"]`
`    GA["gmak8-agent vsock 1024"]`
`    BK["buildkitd vsock 1025"]`
`    K3S["k3s :6443"]`
`    CTD["containerd"]`
`    KV["virt-handler / virt-launcher"]`
`    L2["L2 KubeVirt VMs /dev/kvm"]`
`    GA --> K3S`
`    BK --> CTD`
`    K3S --> CTD`
`    KV --> CTD`
`    KV --> L2`
`  end`

`  CORE -->|vsock 1024/1025| GA`
`  GVP -->|unixgram vfkit fd| VZ`

| Process | Language | Role |
| --- | --- | --- |
| `gmak8.app` | Swift | UI, extra, Sparkle, SMAppService |
| `gmak8-core` | Swift | VM, gvproxy, agent client, kubeconfig, port publisher, XPC+socket |
| `gvproxy` | Go, pinned, **signed Hardened Runtime, same Team ID** | Userspace net |
| `buildctl` | Upstream, in Helpers, signed | Host BuildKit client |
| `virtctl` | Upstream v1.6.1 darwin-arm64, in Helpers, signed | Installed as **`~/.local/bin/virtctl`** (upstream name; not renamed) |
| `gmak8` | Swift ArgumentParser | CLI |
| `gmak8-agent` | Go | Guest HTTP |
| `buildkitd` | Upstream in guest | Builds |

**Codec:** **one** — **newline-delimited JSON (NDJSON)** — on both the unix socket and as Data messages over NSXPC. No parallel Codable-struct RPC that can drift.
**Socket path:** $HOME/Library/Application Support/dev.gmak8.app/engine.sock mode 0600.
**vfkit unixgram path:** $HOME/Library/Caches/dev.gmak8.app/n.sock (short; Darwin sun_path ~104 bytes). gvproxy API: $HOME/Library/Caches/dev.gmak8.app/g.sock.
**VZ queue:** create and call VZVirtualMachine **only** on a dedicated serial DispatchQueue(label: "dev.gmak8.vm"). Never the main queue, never the NSXPC queue. Hop results back via EngineStatus events.
**Privileged helper:** **none in v1.** Later bind-low-ports must not own the VM. Host :80/:443 stay out.
**Two Login Items:** (1) LaunchAgent gmak8-core — background VM. (2) Login item for gmak8.app extra — status surface at login. Settings copy names both. requiresApproval recovery opens Login Items.
### **Nested virtualization**
`flowchart TB`
`  L0["L0 macOS — Hypervisor.framework / VZ"]`
`  L1["L1 gmak8 appliance — k3s node, virt-handler, /dev/kvm"]`
`  L2["L2 KubeVirt VMI — aarch64 guest"]`
`  L0 --> L1 --> L2`

| Host | Nested virt | Eureka profile | What works |
| --- | --- | --- | --- |
| macOS 14 any M-series | No API | Refuse nested; offer Kubernetes or API-only | Plain k8s; AFW tests that do not need Running VMIs |
| macOS 15+ M1/M2 | `isNestedVirtualizationSupported == false` | Same | Same |
| macOS 15+ M3+ | Enable on the platform config | Eureka profile allowed | `/dev/kvm` in L1; virt-launcher can start L2 |

Guest image ships kvm.ko (Debian cloud kernels are typically **CONFIG_KVM=m**, which is acceptable). First-boot systemd: modprobe kvm (and kvm-arm if present). Agent GET /kvm checks **/dev/kvm**** exists and is a char device after nested virt is enabled on the platform config**, not merely that the kconfig bit is set. Image CI: grep CONFIG_KVM=y **or** CONFIG_KVM=m in /boot/config-*, and find kvm.ko in the rootfs/initramfs — fail the image if either is missing. On hosts without nested virt, /dev/kvm is absent; virt-handler reports it; UI tells the truth. **No TCG fallback in v1.**
vfkit/krunkit/UTM already expose --nested; minikube #22805 is the same use case.
---
## **Guest boot contract (two-disk persistence)**
This is a **contract**, not a slogan. Implement in the mkosi image (PR: disk contract) and assert in gmak8-core before start.
### **Disks**

| Role | Guest device | Host file | Size | Attachment |
| --- | --- | --- | --- | --- |
| OS | `/dev/nvme0n1` | `…/vm/os.img` | 8 GiB sparse | NVMe, `.cached` + `.full`, readOnly false |
| Data | `/dev/nvme1n1` | `…/vm/data.img` | profile default | NVMe, `.cached` + `.full`, readOnly false |
| EFI NVRAM | n/a (host) | `…/vm/efi-nvram.bin` | small | `VZEFIVariableStore` |

`let dataAttachment = try VZDiskImageStorageDeviceAttachment(`
`    url: dataURL,`
`    readOnly: false,`
`    cachingMode: .cached,`
`    synchronizationMode: .full`
`)`
`let dataNVMe = VZNVMExpressControllerDeviceConfiguration(attachment: dataAttachment)`
`// same pattern for osURL → osNVMe`
`config.storageDevices = [osNVMe, dataNVMe]`
There is no VZStorageDeviceConfiguration.nvme(url). Never attach virtio-blk.
**Host locks:** flock(LOCK_EX | LOCK_NB) on os.img and data.img (or sidecar *.lock) **before** VZVirtualMachine.start. If lock fails: Recovery “disk images locked”. Also fail start if engine.sock is already live (connect + status).
**Cache/sync:** .uncached + virtio-blk is the UTM #4840 corruption mode. We never use that pair. NVMe + .cached + .full is the v1 data-disk mode (SQLite durability over speed). Soak: dirty-kill the VM, fsck.ext4 -n the data image on the host (via a Linux CI job or guest agent fsck on next boot).
**Grow/shrink:** **not v1.** RecoveryView must not offer resize. Users who need a bigger disk **Reset** or create a new cluster after changing the setting (settings change to a *larger* cap can be implemented later as truncate + growfs; do not pretend it exists now).
### **Data disk format (first boot)**
**Do not** have gmak8-agent format the disk. On a blank data.img there is no /dev/disk/by-label/GMAK8_DATA, so mnt-data.mount fails, and an agent that Requires= that mount **never starts** — mkfs would deadlock.
Use a oneshot **before** the mount:
`# /etc/systemd/system/gmak8-data-format.service`
`[Unit]`
`Description=Format gmak8 data NVMe if unlabeled`
`DefaultDependencies=no`
`After=local-fs-pre.target`
`Before=mnt-data.mount`
`ConditionPathExists=/dev/nvme1n1`

`[Service]`
`Type=oneshot`
`RemainAfterExit=yes`
`ExecStart=/usr/local/lib/gmak8/format-data-disk.sh`
/usr/local/lib/gmak8/format-data-disk.sh (root, idempotent):
`#!/bin/sh`
`set -eu`
`DISK=/dev/nvme1n1`
`if ! blkid -o value -s LABEL "$DISK" 2>/dev/null | grep -qx GMAK8_DATA; then`
`  mkfs.ext4 -F -L GMAK8_DATA "$DISK"`
`fi`
Whole-disk ext4, no partition — findable after OS replace without GPT UUIDs from the previous os.img. Do **not** rely on x-systemd.makefs unless we have tested it on Debian 13; the oneshot is the contract.
`# /etc/systemd/system/mnt-data.mount`
`[Unit]`
`DefaultDependencies=no`
`Requires=gmak8-data-format.service`
`After=gmak8-data-format.service`
`Before=local-fs.target gmak8-agent.service k3s.service`

`[Mount]`
`What=/dev/disk/by-label/GMAK8_DATA`
`Where=/mnt/data`
`Type=ext4`
`Options=defaults,noatime`
Post-mount (drop-in or ExecStartPost on a mnt-data-prep.service After=mnt-data.mount Before=k3s.service):
`mkdir -p /mnt/data/rancher /mnt/data/buildkit /mnt/data/tmp /mnt/data/log /mnt/data/local-path`
Then:
- **Bind nothing over ****/var/lib/rancher****. k3s ****--data-dir /mnt/data/rancher****.**

- **default-local-storage-path: /mnt/data/local-path**** (required; local-path HelmChart hostPath otherwise stays ****/var/lib/rancher/k3s/storage**** on the 8 GiB OS disk). Also patch the local-path configmap to that path if the flag is not enough.**

- **buildkitd ****--root /mnt/data/buildkit****.**

- **Airgap tarballs into ****/mnt/data/rancher/agent/images/**** and/or ****ctr -n k8s.io images import****.**
k3s.service Requires=mnt-data.mount After=mnt-data.mount. gmak8-agent.service After=mnt-data.mount (no format responsibility). /health may only report data=mounted once the mount is up.
First-boot start **step 6** waits on gmak8_data=mounted (which implies format+mount succeeded). Serial must show gmak8-data-format before the agent is expected. **Eureka profile refuses to start** if default-local-storage-path is not /mnt/data/local-path. Soak: findmnt the PVC directory is under /mnt/data.

### **OS replace / EFI**
On **every** os.img replace (guest upgrade):
1. **Stop VM (ACPI, then force).**

2. **Delete and recreate ****efi-nvram.bin****. Do not reuse NVRAM across GPT/ESP PARTUUIDs minted by mkosi. Firmware boot entries from the old ESP are poison.**

3. **Keep ****data.img**** and ****machine-identifier.bin****.**

4. **Pre-start probe: mount data (or read ext4 via a small host-side probe later; v1: boot, agent reads ****/mnt/data/rancher/server/db**** + k3s version file if present). If the on-disk k3s minor is outside the shipped compatibility matrix, refuse and tell the user to Reset or install a matching gmak8/guest pair.**
Compatibility matrix (JSON shipped in the app, example):

`{`
`  "k3s": {`
`    "v1.33.3+k3s1": { "dataDirMinorsAccepted": ["1.33"] }`
`  }`
`}`
v1 does not in-place-upgrade 1.32 data to 1.33. New installs are 1.33.3. Future minors add rows.
k3s “upgrades the data dir in place when compatible” is **only** claimed inside that matrix, after a probe, never as folklore.
### **k3s configuration (host-generated, virtio-fs tag ****gmak8-config****)**
**Do not** set disable-helm-controller. Traefik and metrics-server are **HelmChart** addons (klipper-helm). Disabling the controller leaves CoreDNS + ServiceLB and **drops Traefik and metrics-server**. Settings “Disable bundled” uses k3s --disable= / disable: list only.
**Do not** pass a custom --enable-admission-plugins list (redundant with k3s defaults; additive flags are a footgun).
**Do not** set write-kubeconfig to a custom path. Admin kubeconfig is **/etc/rancher/k3s/k3s.yaml**. With --data-dir /mnt/data/rancher, k3s still writes that symlink/file; the agent **reads ****/etc/rancher/k3s/k3s.yaml**.
`# /mnt/config/k3s/config.yaml`
`data-dir: /mnt/data/rancher`
`default-local-storage-path: /mnt/data/local-path`
`cluster-cidr: 10.42.0.0/16`
`service-cidr: 10.43.0.0/16`
`cluster-dns: 10.43.0.10`
`tls-san:`
`  - 127.0.0.1`
`  - localhost`
`  - gmak8`
`  - gmak8.internal`
`  - 192.168.127.2`
`node-name: gmak8`
`https-listen-port: 6443`
`# disable: []   # filled from Settings: traefik | servicelb | local-storage | metrics-server`
`# kube-apiserver-arg feature-gates from Settings if any`
Privileged pods: k3s 1.33 does not deny them by default (no restricted PSS). Eureka’s kops allowPrivileged: true is the kops-era equivalent; locally we **document** that virt-launcher privileged + /dev/kvm is allowed, and we do **not** turn on PodSecurity restricted.
HelmChart CRs may exist in kube-system. The GUI does not list them. No Helm UI.
---
## **Networking (implementable)**
### **Address plan (pinned)**
gvproxy defaults, **do not change** without changing DHCP + MAC together:

| Item | Value |
| --- | --- |
| Subnet | `192.168.127.0/24` |
| Gateway | `192.168.127.1` |
| Guest IP (static DHCP) | **`192.168.127.2`** |
| Guest MAC | **`5a:94:ef:e4:0c:ee`** (gvproxy/vfkit required sample MAC) |
| Host-side loopback | **`127.0.0.1` only** — never `0.0.0.0` |

### **vfkit unixgram handshake**
gvproxy’s VZ path is **not** “pass a raw virtio-net fd into gvproxy.” Follow vfkit/Lima:
1. **socketpair**** is not sufficient by itself. Start:**

`   gvproxy \`
`     --listen unix://$HOME/Library/Caches/dev.gmak8.app/g.sock \`
`     --listen-vfkit unixgram://$HOME/Library/Caches/dev.gmak8.app/n.sock \`
`     --mtu 1500`
2. **gmak8-core**** connects the vfkit unixgram socket and wraps the connected datagram fd in ****VZFileHandleNetworkDeviceAttachment****.**

3. **VZVirtioNetworkDeviceConfiguration.attachment = that attachment****, ****macAddress = VZMACAddress(string: "5a:94:ef:e4:0c:ee")****.**

4. **Guest virtio-net DHCP → ****192.168.127.2****.**

5. **Expose via gvproxy HTTP on ****g.sock****:**

`   POST http://unix/services/forwarder/expose`
`   {"local":"127.0.0.1:6443","remote":"192.168.127.2:6443"}`
Same for 127.0.0.1:8080 → 192.168.127.2:80, 127.0.0.1:8443 → 192.168.127.2:443.
If n.sock path exceeds sun_path, start fails with Recovery “network socket path too long” (should not happen under Library/Caches/dev.gmak8.app/).
`sequenceDiagram`
`  participant kubectl`
`  participant Lo as 127.0.0.1:6443`
`  participant gvproxy`
`  participant Guest as 192.168.127.2:6443`
`  participant API as kube-apiserver`
`  kubectl->>Lo: TLS`
`  Lo->>gvproxy: expose mapping`
`  gvproxy->>Guest: NAT`
`  Guest->>API: k3s`
`  Note over gvproxy: vfkit unixgram, MAC 5a:94:ef:e4:0c:ee`
### **API port collision**
If 127.0.0.1:6443 bind/expose fails: try **16443**, then a Settings port. Rewrite server: in **both** …/kubeconfig and the merged ~/.kube/config gmak8 cluster (if merged). RecoveryView lists lsof. Same pattern for 8080/8443 (separate recovery kind).
### **ServiceLB / NodePort auto-publish (v1, generic kubectl)**
Klipper ServiceLB on a **single node** assigns EXTERNAL-IP=192.168.127.2 and creates svclb pods that **hostPort the Service ports** (22/80/443). A second Eureka LoadBalancer on 22/80/443 **cannot** get unique guest hostPorts — that is a known divergence from GCE cloud LBs (each got a public IP in resources_created_by_eureka.md). Scaled-down local target is **one** nested VM; if someone applies stock control-lb **and** login-lb both on 22/80/443, Klipper hostPorts collide — document that, do not paper over it with a privileged helper.
**v1 NodePort publisher (generic path, not Eureka SSH):**
1. **Watch all Services of type ****NodePort**** or ****LoadBalancer****.**

2. **For each ****spec.ports[].nodePort****, ****expose**** ****127.0.0.1:<nodePort> → 192.168.127.2:<nodePort>****.**

3. **Do not expose guest ****:22**** / ****:80**** / ****:443**** onto host ****:22**** / ****:80**** / ****:443**** (root).**

4. **UI Published ports table: Service name, port, nodePort, host URL, collision state.**

5. **Default on for generic ****kubectl****/****curl****. Settings can disable. Not how Eureka SSHes.**

6. **Cap: warn at 32 published ports; do not bind 0.0.0.0.**
Ingress-on-8080 remains for Traefik Ingress objects.

### **Eureka SSH = virtctl, not NodePort**
python/eureka/kubevirt.py get_load_balancer_ip() reads status.loadBalancer.ingress[0].ip. Klipper sets that to **192.168.127.2**, which is **not a host route**. image/env.py HTTPS to {public_ip}:443 (/apps/afw/admin/) is GCE-shaped and **out of v1 local proving**.
Eureka SSH (image/env.py) is:
`ProxyCommand virtctl port-forward --stdio=true vm/{name}/{namespace} %p`
**Product default:**
- **Ship ****virtctl**** v1.6.1 darwin-arm64 in ****Contents/Helpers**** and install it as ****~/.local/bin/virtctl****. Eureka’s ProxyCommand looks up ****virtctl**** on ****PATH****.**

- **Document in ****docs/eureka-local.md****:**

`  export KUBECONFIG="$HOME/Library/Application Support/dev.gmak8.app/kubeconfig"`
`  export PATH="$HOME/.local/bin:$PATH"`
`  # SSH config Host entries from env.py work unchanged if virtctl is on PATH`
- **Do not document ****ssh -p <nodePort> user@127.0.0.1**** as the Eureka path.**

- **1.0 soak: ****virtctl port-forward --stdio=true vm/<name>/<ns> 22**** to a Running VMI, not only NodePort curl.**

- **Builderdash (omnibond/builderdash, invoked by Eureka ****image/build.py -k****) does not call gmak8.** It uses the kube-apiserver (DataVolume + VM) then **paramiko to the VMI pod IP**, optionally via ****proxy_conf****. That pod IP is inside L1. Product work is the localhost SSH bridge below; Mac/ARM image and size differences are config in ****docs/eureka-local.md****.

### **Builderdash SSH bridge (1.0)**

Unmodified builderdash sets ****remoteIp**** from ****status.interfaces[0].ipAddress**** (cluster pod IP) and SSHes there on ****build_host_ssh_port**** (22). On GCE a jump host in the VPC reaches that IP. On a Mac it does not.

| Path | Who it serves | gmak8 work |
| --- | --- | --- |
| **A — virtctl stdio** | ****image/env.py**** ProxyCommand (already specified) | virtctl on PATH (PR 26) |
| **B — engine VM/VMI forward** | Any client that can SSH ****127.0.0.1:&lt;local&gt;**** (scripts, optional Eureka patch) | ****portForwardStart**** ****kind: vm\|vmi****; CLI ****gmak8 port-forward vm/&lt;name&gt; 2222:22****; bind ****127.0.0.1**** only; implement with bundled virtctl as a child of ****gmak8-core**** (PR 30) |
| **C — L1 as jump** | **Unmodified** builderdash paramiko + ****proxy_conf**** | Guest ****sshd**** in the appliance; Eureka profile publishes L1:22 → ****127.0.0.1:&lt;highport&gt;**** (never host :22). Document ****proxy_hostname: 127.0.0.1**** (PR 30 + PR 8 sshd) |

Do **not** wrap builderdash inside the app. Do **not** add a gmak8 REST “run a build” API. ****gmak8 build**** stays container BuildKit; builderdash stays VM-disk/CDI.

**Config (not gmak8 code)** — Eureka ****image/build.config**** / ****build.in**** for Apple Silicon:

- ****k8s_kubeconfig_path**** = gmak8 private kubeconfig; context ****gmak8****
- ****k8s_storage_class: local-path****
- Source qcow2 **aarch64** (not AlmaLinux-9 x86_64 GCS URL in ****build.in****)
- ****instancetype.kind: VirtualMachineClusterInstancetype**** (builderdash currently hardcodes namespaced ****VirtualMachineInstancetype**** — apply a namespaced copy of ****u1.medium**** *or* a one-line Eureka override; that is Eureka, not gmak8)
- ****u1.medium**** / small disk; one image at a time (35–100 Gi DV on the 256 Gi data disk). Stock ****u1.xlarge**** Pending
- ****proxy_conf**** → 127.0.0.1 and the published L1 SSH port (path C), **or** Eureka points SSH at 127.0.0.1 after path B

local-path **Retain** after builderdash ****saveimage**** is a documented local-PV caveat, not a CSI clone.

### **Proxy**
Image pulls happen in **guest containerd**, not in gvproxy. gmak8-core reads macOS system HTTP(S) proxy via SCDynamicStore and writes /mnt/config/proxy.env:
`HTTP_PROXY=...`
`HTTPS_PROXY=...`
`NO_PROXY=127.0.0.1,localhost,192.168.127.0/24,10.42.0.0/16,10.43.0.0/16,.svc,.cluster.local`
k3s.service and containerd drop-ins EnvironmentFile=/mnt/config/proxy.env. registries.yaml still used for mirrors/insecure/auth.
### **gvproxy crash / ENOBUFS**
Known vfkit/gvproxy issue: unixgram ENOBUFS / process exit under large pulls. **Risk (High for image load).** Mitigation: gmak8-core restarts gvproxy with backoff, re-exposes the port table; agent pause of large ctr import is on the vsock path (not unixgram) so **image load should use vsock, not the guest overlay network**. Document: prefer gmak8 image load / airgap over pulling multi-GB images through gvproxy.
---
## **Storage & host mounts (virtio-fs)**
- **Images: ****~/Library/Application Support/dev.gmak8.app/vm/****.**

- **tmutil addexclusion**** on ****vm/**** at first run. There is no snapshot product. Onboarding one-liner: “VM disks are excluded from Time Machine. Reset is destructive.”**

- **virtio-fs: user-selected folders only. Guest ****/mnt/host/<name>****.**

- **UID story (factual): Apple virtio-fs passes host UIDs through. The first macOS user is uid 501, gid 20 (staff), not 1000. There is no supported idmap. ****chown**** from Linux is not honored. hostPath from ****~/Projects**** appears as ****501:20**** in the guest and in pods. Non-root containers (****runAsUser: 1000****) cannot write. Root containers can. Settings → Files shows ****Host uid:gid = 501:20**** (actual values). Copy: “Prefer root containers for hostPath, or set ****runAsUser**** / ****fsGroup**** to this uid with eyes open.” Do not promise a map-to-1000 enhancement unless VZ grows idmap. Test: mount a folder, ****stat**** from a pod, assert uid 501.**
Kubernetes hostPath is the user’s problem with that warning. **KubeVirt ServiceAccount virtiofs** (Eureka VM spec filesystems[].virtiofs + EnableVirtioFsConfigVolumes) is **inside the L1 guest / virt-launcher**, not Apple virtio-fs, and is a separate soak (Issue-class: virtiofsd in virt-launcher). Host uid 501:20 does **not** apply to that SA mount.
local-path provisioner **must** use **/mnt/data/local-path** (default-local-storage-path). The 8 GiB OS disk cannot hold 35–55 Gi Eureka PVCs.

---
## **kubeconfig**
**Source of truth:** ~/Library/Application Support/dev.gmak8.app/kubeconfig mode 0600.
Agent reads **/etc/rancher/k3s/k3s.yaml**, rewrites server: to https://127.0.0.1:<api-port>, writes the private file.
### **Merge into ****~/.kube/config**
**Only if ****KUBECONFIG**** is unset or empty.** If KUBECONFIG is set (direnv, Tilt, kind): **do not merge**; print export KUBECONFIG="$HOME/Library/Application Support/dev.gmak8.app/kubeconfig:$KUBECONFIG" (or the equivalent prepend). kind’s model, not “smash the first file.”
If ~/.kube/config is missing: create a file that contains **only** the gmak8 cluster/user/context (and current-context only if the user opted in).
If it exists but is not YAML: **do not touch**; notify; same export snippet.
**current-context****:** default **off**. Onboarding checkbox. Settings “Set as current context on start” default **off**. Design principle 4 wins.
**Algorithm (own PR, golden tests):** **stanza splice**, not a naïve Yams round-trip.
1. **flock**** ****~/.kube/config.lock****.**

2. **Read bytes. Parse with Yams only to ****locate**** indices of list items named ****gmak8**** under ****clusters**** / ****users**** / ****contexts****.**

3. **Splice replacement YAML blocks for those three items in place (same list position if present, else append under the existing key). Preserve unknown keys inside other items by not rewriting them. Preserve comments and ****exec**** plugin blocks outside the ****gmak8**** stanzas because those bytes are copied through.**

4. **If ****current-context**** opt-in: replace or insert that single scalar; else leave the line alone.**

5. **Temp file in the same directory → ****fsync**** → ****rename****. Backup one generation ****~/.kube/config.gmak8.bak****.**
Goldens must include: comments, exec: users, multiple contexts, current-context pointing at something else, API port 16443 rewrite.
Port autodrop **must** update server: in the private file and, if merged, the gmak8 cluster stanza.

---
## **Image pipeline (protocol)**
**Decision:** host client is **buildctl** in Contents/Helpers. No Swift LLB. loadImage takes a **path string** (and a security-scoped bookmark only if we later sandbox; v1 core is unsandboxed — **do not** use bookmarks as the API).
### **Load**
`sequenceDiagram`
`  participant CLI as gmak8 image load`
`  participant Core as gmak8-core`
`  participant Agent as gmak8-agent :1024`
`  participant Disk as /mnt/data/tmp`
`  participant CTR as k3s ctr -n k8s.io`

`  CLI->>Core: RPC load {path, size}`
`  Core->>Core: preflight host size vs data disk free via agent`
`  Core->>Agent: PUT /images/import?name=...  (vsock HTTP, body = tar stream)`
`  Agent->>Disk: write temp, fsync, backpressure = TCP window`
`  Agent->>CTR: ctr images import /mnt/data/tmp/....tar`
`  CTR-->>Agent: digest`
`  Agent->>Disk: unlink temp`
`  Agent-->>Core: {digest, refs[]}`
`  Note over Core: progress on EngineStatus stream`
- **Preflight: refuse if ****size + 20%**** > data-disk free (agent ****GET /disks****).**

- **Progress: bytes received / imported (EngineStatus ****imageJob****).**

- **If k3s restarts containerd mid-import: fail the job, unlink temp, user retries. No resume-inside-ctr in v1.**

- **Airgap k3s tarball uses the same import path (or k3s’s ****agent/images/**** drop, which k3s already understands).**

- **vsock, not gvproxy, so ENOBUFS on unixgram does not kill a 4 GiB load.**

### **Build**
gmak8 build -t example:dev . execs bundled buildctl:
`buildctl --addr unix://$HOME/Library/Caches/dev.gmak8.app/buildkit.sock \`
`  build --frontend dockerfile.v0 --local context=. --local dockerfile=. \`
`  --output type=image,name=example:dev,push=false`
gmak8-core forwards that unix socket to **vsock 1025** (buildkitd --addr vsock://1025 or agent proxy). buildkitd containerd worker:
`--oci-worker=false --containerd-worker=true \`
`--containerd-worker-addr /run/k3s/containerd/containerd.sock \`
`--containerd-worker-namespace k8s.io`
Registry auth for FROM pulls: same Keychain → registries.yaml / containerd as k3s. BuildKit must see that containerd.
### **Tilt / Skaffold**
Overview claim restated: **deploy to the apiserver works**. Custom build: gmak8 build / gmak8 image load. No docker CLI, no kind-load equivalent beyond gmak8 image load. Document a Tilt custom_build snippet in README.
---
## **Eureka / KubeVirt addon pack**
Do **not** copy the Eureka tree into gmak8. Vendor **upstream YAML + images** at pinned versions, plus a small installer in the guest/agent.
### **Version pins (Eureka-aligned)**

| Component | Pin | Source in Eureka |
| --- | --- | --- |
| Kubernetes | **1.33.3** via k3s `v1.33.3+k3s1` | `REKA_KOPS_KUBERNETES_VERSION`, AFW `k8s-1.33.3` |
| KubeVirt | **1.6.1** (`v1.6.1`) | `REKA_KUBEVIRT_VERSION`, AFW `kubevirt-1.6.1` |
| CDI | **v1.62.0** | Eureka’s script uses GitHub `latest` — **we pin**. kubevirt 1.6 CI used CDI v1.62.0 |
| common-instancetypes | **v1.4.0** | `kubevirt-install-common-instance-types` kustomize ref |
| virtctl | **v1.6.1** darwin-arm64 as **`~/.local/bin/virtctl`** | `kubevirt-virtctl-install` |
| Feature gates | `VMExport`, `EnableVirtioFsConfigVolumes` | `kubevirt-install-feature-gates` |
| Smoke disk | **aarch64** containerDisk airgapped in `gmak8-kubevirt-airgap-*.tar.zst`. Pin at airgap-build time (prefer a known linux/arm64 cirros if published; otherwise `quay.io/containerdisks/fedora` **linux/arm64** digest). Write the digest/tag into `docs/eureka-local.md`. **Not** `quay.io/kubevirt/cirros-container-disk-demo` (x86_64). **Not** Eureka GCE amd64 images. | AFW/env defaults will Pending without overrides |
| Instancetype | Apply **exactly** `kubectl kustomize https://github.com/kubevirt/common-instancetypes.git/?ref=v1.4.0` (Cluster objects). Verify `kubectl get virtualmachineinstancetype,virtualmachineclusterinstancetype u1.nano`. Local smoke uses **`kind: VirtualMachineClusterInstancetype`**, name **`u1.nano`** (cirros) or **`u1.medium`** (fedora). | Eureka/AFW default `kind: VirtualMachineInstancetype` (namespaced) + `u1.xlarge` (4 vCPU / 16 Gi) **will Pending** |

Generated AFW models (k8s-1.33.3, kubevirt-1.6.1 including v1.VirtualMachine, v1alpha1.VirtualMachinePool) live in Eureka, not gmak8. gmak8 just has to be a cluster those models can talk to.
### **Install order (agent, Eureka profile)**
1. **Nested-virt / agent ****GET /kvm**** (****/dev/kvm**** present). If missing, still install CRDs/operator so API-only tests work; UI badge off.**

2. **ctr -n k8s.io images import**** kubevirt airgap tarball (includes virt-launcher with virtiofsd + aarch64 smoke containerDisk).**

3. **kubectl apply**** ****kubevirt-operator.yaml**** + ****kubevirt-cr.yaml**** from the v1.6.1 release (cached in the airgap payload, not ****curl**** GitHub at runtime).**

4. **Wait ****KubeVirt**** phase ****Deployed****.**

5. **Patch KubeVirt CR ****spec.configuration.developerConfiguration.featureGates**** = ****[VMExport, EnableVirtioFsConfigVolumes]**** (same as Eureka’s apply). Required for Eureka’s SA virtiofs mount in ****kubevirt_instance_template.yaml****.**

6. **Apply CDI operator+CR v1.62.0 from airgap.**

7. **Apply StorageProfile for ****local-path**** with ****cloneStrategy: copy**** (host-assisted). Do not apply Eureka’s ****cdi-storageprofiles-csi-clone.yaml****.**

8. **Apply common-instancetypes exactly as ****kubevirt-install-common-instance-types**** (****kustomize …/?ref=v1.4.0****). Then ****kubectl get virtualmachineinstancetype,virtualmachineclusterinstancetype u1.nano****. v1.4.0 ships VirtualMachineClusterInstancetype; AFW/env default ****kind: VirtualMachineInstancetype**** is namespaced and will not bind unless overridden to ****VirtualMachineClusterInstancetype****.**

9. **Host: copy Helpers ****virtctl**** to ****~/.local/bin/virtctl****.**

### **Storage class Eureka should set**
`k8s_storage_class: local-path`
(python/eureka / image/env.py require a StorageClass name and read_storage_class it). local-path is default on k3s. CDI clone of a 35–55 Gi DV is a **full copy**, not GCE csi-clone. Document in Help and in the Eureka profile empty state.
Scratch PVCs: CDI will allocate another PVC per import. Budget: one 40 Gi DV + scratch ≈ 80+ Gi on the 256 Gi data disk, plus k3s/kubevirt images (~10–20 Gi).
### **CNI divergence (honest)**
Production Eureka (kops customize script): **Cilium** enableNodePort: true, bpfLBSock: true, bpfLBSockHostNSOnly: true because of [kubevirt#10388](https://github.com/kubevirt/kubevirt/issues/10388) (Cilium socket-level LB vs KubeVirt masquerade service routing).
**Local v1: flannel + kube-proxy + Klipper.** We do not run Cilium, so we do not need bpfLBSockHostNSOnly. Masquerade + kube-proxy is the path kubevirt-on-kind typically uses.
**Known local divergences vs kops-on-GCE:**

| Topic | GCE Eureka | gmak8 |
| --- | --- | --- |
| CNI | Cilium + bpfLBSockHostNSOnly | flannel + kube-proxy |
| LoadBalancer | Cloud LB, unique public IPs | Klipper, `EXTERNAL-IP=192.168.127.2` (**not a Mac route**). Eureka SSH = **virtctl stdio**. NodePorts are for generic curl only. HTTPS to ingress IP is **out**. Two LBs on 22/80/443 collide on Klipper hostPort. |
| CSI | GCE PD `balanced-csi`, csi-clone | local-path, CDI **copy** |
| Arch | amd64 vmx-enabled Ubuntu | aarch64 L1 + aarch64 L2 |
| Nodes | 6 workers | 1 |
| Privileged | kops `allowPrivileged: true` | k3s default allow |

Soak test (self-hosted M3, **1.0 gate**):
1. **PVC from local-path lives under ****/mnt/data**** (****findmnt****).**

2. **kubectl get virtualmachineclusterinstancetype u1.nano****.**

3. **One aarch64 smoke VMI (****u1.nano**** or ****u1.medium****, Cluster kind, airgapped disk) reaches Ready.**

4. **That VMI has a ServiceAccount virtiofs mount (exercises virtiofsd in virt-launcher + ****EnableVirtioFsConfigVolumes****).**

5. **virtctl port-forward --stdio=true vm/<name>/<ns> 22**** succeeds.**

6. **GET /kvm**** is true only when nested virt was enabled.**

7. **Builderdash SSH soak (1.0, with PR 30):** ****gmak8 port-forward vm/&lt;name&gt; 2222:22**** (or L1 jump on a published high port) accepts an SSH handshake from the Mac to ****127.0.0.1****. Not a full ****build.py -k**** of control+cloudjump.
**Not 1.0 gate:** AFW 050 (3 Running VMs + in-guest nslookup), stock env.py, two LoadBalancers both on 22/80/443, HTTPS to 192.168.127.2:443. **Do not silently claim identical to kops.**

### **AFW / Python**
A writable kubeconfig at the private path is how afw/src/k8s/tests/ and python/eureka/kube_config.py run.
docs/eureka-local.md (required, exact overrides — airgap job fills the digest):
`export KUBECONFIG="$HOME/Library/Application Support/dev.gmak8.app/kubeconfig"`
`export PATH="$HOME/.local/bin:$PATH"   # virtctl`

`# Storage`
`k8s_storage_class: local-path`

`# Instancetype — Cluster, not namespaced; not u1.xlarge`
`instancetype.kind: VirtualMachineClusterInstancetype`
`instancetype.name: u1.nano          # cirros; use u1.medium for fedora cloud`

`# Disk — airgapped aarch64; NOT quay.io/kubevirt/cirros-container-disk-demo (x86_64)`
`containerDisk.image: <digest recorded at airgap build>`

`# SSH (unchanged Eureka ProxyCommand once virtctl is on PATH)`
`#   ProxyCommand virtctl port-forward --stdio=true vm/{name}/{ns} %p`

`# Builderdash (image/build.py -k): kubeconfig + local-path + aarch64 qcow + small Cluster`
`# instancetype as above. SSH: proxy_conf to 127.0.0.1:<L1 ssh port> (unmodified paramiko),`
`# or gmak8 port-forward vm/<name> 2222:22 if Eureka is pointed at localhost.`
`# Do not use the AlmaLinux x86_64 GCS URL on Apple Silicon.`

`# Out of local proving: HTTPS to status.loadBalancer.ingress[0].ip`
`# Stock image/env.py and u1.xlarge will Pending. Do not run them unmodified.`
Object-only AFW tests (ConfigMap, Service, create VM YAML without Ready) can run on the API-only profile. Tests that wait status.ready == true (012) and test 050 (3 replicas + in-guest DNS) need nested virt + the overrides above; **050 is stretch, not 1.0**.
OCLK8sProvider / K8sKeyMaterialObject (CA + token) are Eureka’s in-cluster creds. Locally, developers use the admin kubeconfig. gmak8 does not implement OCL.
### **What v1 Eureka will not run**
- **Full ****env.py**** controller + login + OrangeFS home/projects + batch VMPools.**

- **Stock ****env.py**** / ****u1.xlarge**** / x86_64 cirros without the overrides above (they Pending).**

- **Production amd64 GCE images.**

- **Open OnDemand in the gmak8 GUI; HTTPS to Klipper EXTERNAL-IP.**

- **OrangeFS.**

- **Six-node scheduling behavior.**

- **AFW test 050 as a release gate.**

- **Unmodified ****image/build.py -k**** against GCE-shaped ****build.in**** (x86_64 qcow, ****u1.xlarge****, VMI pod IP with no jump). Use the Eureka-local overrides + gmak8 SSH bridge.**

- **Wrapping builderdash inside gmak8 or a “run build” REST API.** Builderdash stays a kube-apiserver client launched from the Mac CLI.

---
## **Rosetta**
VZLinuxRosettaDirectoryShare.availability is notSupported | notInstalled | installed.
- **notSupported**** → toggle off, hidden.**

- **notInstalled**** → toggle visible, Install… calls ****VZLinuxRosettaDirectoryShare.installRosetta()****. Do not silently fail the first amd64 container pull.**

- **installed**** → default on.**

- **Branch on OS version for macOS 26/27 translation-without-Rosetta if the SDK distinguishes it; do not assume the macOS 14 API forever.**
**Not a 0.9 blocker.** Key Decision: feature-detect, default on when installed, install prompt when not. amd64 **containers** only. amd64 **VMs** still out of scope.

---
## **API / interface — engine protocol**
start / stop / reset **return immediately** with {ok} or {error: conflict|locked|translocated|...}. NSXPC will time out if a reply waits for Node Ready (15–90 s). Progress is an **event stream**.
**Unix socket:** NDJSON, one object per line, engine.sock. **XPC:** same NDJSON as Data; plus an **anonymous NSXPCListener** exported by the client for the stream (or the client reads the unix socket even from the app — **prefer: the app also uses ****engine.sock**** for the stream** so there is one path. XPC is then only an optional bootstrap to ask for the socket path. Simplest v1: **both UI and CLI use ****engine.sock**** NDJSON**. Team-ID check: the daemon verifies the peer via getsockopt(LOCAL_PEERPID) + SecCode on that pid.
`{"op":"start"}`
`{"op":"stop"}`
`{"op":"prepareUpdate"}`
`{"op":"reset","force":true}`
`{"op":"status"}`
`{"op":"subscribe"}`
`{"op":"loadImage","path":"/Users/…/foo.tar"}`
`{"op":"portForwardStart","ns":"default","kind":"pod","name":"x","local":18080,"remote":8080}`
`{"op":"portForwardStart","ns":"default","kind":"vm","name":"build-vm","local":2222,"remote":22}`
`{"op":"portForwardStop","id":"…"}`
****kind**** is ****pod**** | ****vm**** | ****vmi****. ****pod**** uses guest ****kubectl port-forward**** (0.9/1.0 workloads). ****vm**** / ****vmi**** use bundled ****virtctl port-forward --address 127.0.0.1**** as a ****gmak8-core**** child (PR 30). Always ****local: 127.0.0.1****. Collision → same UI as NodePorts. CLI: ****gmak8 port-forward vm/&lt;name&gt; [&lt;local&gt;:]&lt;remote&gt;****.
reset without force: true → error confirmation_required. CLI: gmak8 reset --force.
Stream lines:
`{"type":"status","state":"starting","step":"guestAgent","apiEndpoint":null,"vm":{"cpu":0.1,"ramUsed":1.2,"ramCap":16,"diskUsed":8,"diskCap":256},"nestedVirt":true,"lastError":null,"publishedPorts":[],"imageJob":null}`
`{"type":"log","source":"serial","line":"…"}`
`{"type":"log","source":"engine","line":"…"}`
XPC timeouts: RPC 5 s; stream is long-lived. Peer Team ID tests in the engine-stub PR.
`enum ClusterState: String, Codable {`
`    case stopped, starting, running, degraded, paused, stopping, failed`
`}`
---
## **Data model & on-disk layout**
`~/Library/Application Support/dev.gmak8.app/`
`  settings.json                 # 0600, schemaVersion`
`  engine.sock`
`  kubeconfig                    # 0600`
`  vm/`
`    os.img                      # flock`
`    data.img                    # flock`
`    efi-nvram.bin               # recreated on OS replace`
`    machine-identifier.bin`
`    serial.log`
`  cache/guest/                  # verified zst + .sig`
`~/Library/Caches/dev.gmak8.app/`
`  n.sock                        # vfkit unixgram (short path)`
`  g.sock                        # gvproxy HTTP`
`  buildkit.sock                 # forwarded to vsock 1025`
`~/Library/Logs/gmak8/`
No host database. No snapshots.
---
## **Repo / implementation shape**
`gmak8/`
`  LICENSE, NOTICE, README.md, CONTRIBUTING.md, AGENTS.md, CODE_OF_CONDUCT.md`
`  Apps/gmak8/gmak8.xcodeproj`
`    App/                      # SwiftUI target → gmak8.app`
`    Gmak8Core/                # LaunchAgent → gmak8-core`
`    CLI/                      # ArgumentParser target → binary gmak8`
`    Tests/`
`    Helpers/                  # gvproxy, buildctl, virtctl (copied at build)`
`    Entitlements/`
`  Packages/`
`    Gmak8Kit/                 # paths, settings, kubeconfig splice, redaction, uid display`
`    Gmak8XPC/                 # NDJSON types`
`    Gmak8Virtualization/      # VZ on gmak8.vm queue, flock, vfkit handshake`
`    Gmak8Kubernetes/          # Swiftkube + generic KubeVirt CRDs`
`    Gmak8GuestClient/         # vsock HTTP`
`  ThirdParty/gvproxy/         # pin + build script`
`  guest/`
`    mkosi/                    # Debian appliance + KVM kernel assert`
`    agent/`
`    k3s/                      # config templates`
`    kubevirt/                 # pinned YAML copies + StorageProfile local-path`
`    buildkit/`
`    airgap/                   # scripts to pull+sign k3s and kubevirt image tarballs`
`  scripts/                    # ci, dmg, notarize, appcast`
`  docs/security.md            # key storage, rotation`
`  .github/workflows/          # app.yml, guest.yml, airgap.yml, release.yml`
**Do not** submodule Eureka.
### **Signing, notarization, Sparkle, Cosign**
- **Sign every Mach-O in the bundle: ****gmak8**** (app + CLI), ****gmak8-core****, ****gvproxy****, ****buildctl****, ****virtctl****, Sparkle Autoupdate/XPC. Same Team ID, Hardened Runtime. Go binaries: test whether they need ****com.apple.security.cs.allow-unsigned-executable-memory**** / ****disable-library-validation****; measure, don’t assume.**

- **UI entitlements: omit ****com.apple.security.virtualization**** (do not set it to ****false**** as cargo-cult). ****gmak8-core**** sets it true. Both: network client. ****gmak8-core****: network server. No App Sandbox.**

- **Translocation: if the app is in ****Downloads**** / has a quarantine translocation path, refuse ****SMAppService**** register and show “Move to /Applications.”**

- **Sparkle 2, EdDSA, HTTPS appcast. Update flow (PR 18, load-bearing — ACPI-stop of the guest is not enough):**

1. **Sparkle ****willInstallUpdate**** sends engine ****prepareUpdate****.**

2. **gmak8-core**** ACPI-stops the VM, closes disk flocks, then exits 0.**

3. **LaunchAgent must not immediately restart it. Contract: during the swap window, ****SMAppService.unregister()**** the ****gmak8-core**** agent (this is what stops KeepAlive). Alternative equivalent: ****KeepAlive**** = ****{ SuccessfulExit: false }**** plus ****prepareUpdate**** always exits 0 — still unregister so launchd does not hold a mapped Mach-O from the old bundle.**

4. **Wait until ****engine.sock**** is gone and flock on ****os.img****/****data.img**** is released (timeout 60 s). Fail the update if not.**

5. **Sparkle swaps ****gmak8.app****.**

6. **SMAppService.register()**** + launch ****gmak8-core**** from the new bundle.**

7. **If Settings “keep running”: ****start****.**
**Document: an app update quits gmak8-core and restarts the cluster.** Do not replace gmak8.app while gmak8-core is alive.

- **Cosign keyful only (drop minisign). Public key pinned in the app. Keyless/OIDC is wrong for “Choose a file…” air-gap. Cosign private key, Sparkle EdDSA private key, Notary API key: GitHub Actions secrets; rotation procedure in ****docs/security.md****. Never in the repo.**

- **Guest/airgap signatures: Cosign over each zst.**

### **Tests / CI**

| Layer | Where |
| --- | --- |
| Unit | GitHub `macos-15` arm64: kubeconfig splice goldens, settings, state machine with fake VM, port publisher, NDJSON codec, Team-ID check with a fixture |
| Agent | Linux: HTTP handlers, import preflight |
| Image | Linux arm64: mkosi, **`CONFIG_KVM=y` or `=m` plus `kvm.ko` present**, QEMU smoke (not VZ) |
| VZ / KubeVirt soak | **Self-hosted M3 Mac mini**, label `gmak8-vm`. Not GitHub-hosted macOS. 0.9 nightly: start/stop 50×, dirty-kill + fsck, load image, nginx pod, NodePort curl. **1.0** adds: PVC under `/mnt/data`, `u1.nano` ClusterInstancetype, one aarch64 VMI Ready, SA virtiofs, `virtctl port-forward --stdio` |

PR gate = unit + agent + xcodebuild test without VZ.
---
## **Security & privacy**

| Threat | Sev | Mitigation |
| --- | --- | --- |
| Malicious container / VMI escape to L1 | Medium (accepted for local k8s/KubeVirt) | Document privileged virt-launcher |
| L1 escape to macOS | High | VZ only; no bridged vmnet; no USB |
| Supply chain guest/airgap | High | HTTPS + SHA-256 + keyful Cosign, pinned key |
| Sparkle | High | EdDSA, Developer ID, **quit gmak8-core** (unregister KeepAlive) then swap |
| kubeconfig theft (same uid) | Medium | `0600`; same-uid malware already owns the user |
| LAN exposure of API | High if happened | **127.0.0.1 only** |
| Port storm of NodePorts | Medium | cap + collision UI |
| Registry passwords | Medium | Keychain |
| Telemetry | Low | none |
| Translocated helper | Medium | refuse register |
| Nested virt unavailable surprise | Medium | capability badge + profile refuse |

No accounts. No crash reporter. Sparkle + GitHub Releases are the vendor network calls. **System images do not hit Docker Hub.**
---
## **Observability**
os_log subsystems: dev.gmak8.{ui,core,vm,net,k8s,kubevirt}. Never log kubeconfig material. Signposts gmak8.start.*. Diagnostics view is the support primitive.
---
## **Rollout**
1. **0.1 — VM boots, serial, disk contract, flock.**

2. **0.2 — gvproxy + k3s Ready + kubeconfig splice + airgap.**

3. **0.3 — NodePort publish + menu extra + onboarding + recovery.**

4. **0.9 beta — PRs 1–18: engine + onboarding + recovery + Sparkle that quits ****gmak8-core**** + cask ****gmak8****. Feature freeze on Docker-shaped requests.**

5. **1.0 — PRs 19–28 and 30: Workloads/Images GUI, KubeVirt pack, Eureka profiles, nested-virt soak (one aarch64 VMI + virtctl), Builderdash SSH bridge. Rosetta is PR 29, after 1.0 if needed.**
**Rollback:** previous app via Sparkle; previous guest in cache/; data disk discarded only on Reset. **No snapshot restore.**

---
## **Risks**

| Risk | Sev | Mitigation |
| --- | --- | --- |
| virtio-blk corruption | High | NVMe + `.cached` + `.full`; never virtio-blk |
| Two gmak8 instances corrupt disks | High | flock + live `engine.sock` |
| GitHub Actions cannot run VZ | High | Self-hosted M3 soak PR |
| gvproxy ENOBUFS / crash | High | vsock for image load; restart gvproxy; Risk accepted for overlay pulls |
| Nested virt only M3+/15+ | High (Eureka) | Profiles; honest Pending; no TCG |
| Nested VM performance | Medium | Scaled-down target; don’t promise GCE |
| DataVolume disk pressure | High | 256 GiB Eureka disk; warn; refuse full stack |
| LoadBalancer hostPort collisions | High | NodePort publish; UI |
| arm64 vs amd64 Eureka images | High | Document; aarch64 cirros/fedora only |
| CNI ≠ Cilium | Medium | Soak masquerade+DNS; no silent “identical” |
| helm-controller disabled by mistake | High (fixed) | Do not disable it |
| Sparkle vs running helper | High | `prepareUpdate` → process exit → SMAppService unregister → flock wait → swap → register |
| Translocation | Medium | `/Applications` gate |
| Swiftkube lags CRDs | Low | generic client for KubeVirt |
| Time skew after pause | Medium | `PUT /time` on resume **and** wake |
| Balloon flapping node | Medium | **Default off** |
| “Restore snapshot” with none | High (fixed) | Reset only |

---
## **Alternatives considered**
1. **QEMU / VirtualBox / HyperKit vs VZ — VZ wins for a Mac-native product. Nested virt is a VZ/macOS 15 feature; QEMU TCG would be the emulation we refuse.**

2. **k0s / kubeadm / kind-in-VM vs k3s — k3s wins for a laptop. Eureka production stays kops; local is not kops.**

3. **vzNAT-only vs gvproxy vs socket_vmnet — gvproxy for unprivileged expose. Dual-NIC later if measured.**

4. **Cilium locally vs flannel — flannel in v1; Cilium is the GCE workaround for socket LB, which we do not run. Revisit only if soak fails.**

5. **Wrap Lima / Apple Containerization — steal ideas, own VZ in Swift.**

6. **Alpine / FCOS / Talos vs Debian — Debian + KVM kernel assert.**

7. **App Sandbox — research project; Hardened Runtime only.**

8. **Electron — rejected.**

9. **TCG nested VMs on M1/M2 — slow, unsupported, out of v1.**

---
## **Open questions**
None.
---
## **References**
- **Apple Virtualization: ****VZVirtualMachine****, ****VZEFIBootLoader****, ****VZNVMExpressControllerDeviceConfiguration****, ****VZDiskImageStorageDeviceAttachment****, ****VZFileHandleNetworkDeviceAttachment****, ****VZGenericPlatformConfiguration.isNestedVirtualizationSupported****, ****VZLinuxRosettaDirectoryShare****, ****com.apple.security.virtualization**

- **k3s: HelmChart addons, ****registries.yaml****, ****ctr -n k8s.io****, ****--data-dir****, airgap ****agent/images/****, ****--disable=**

- **containers/gvisor-tap-vsock**** vfkit unixgram; vfkit MAC ****5a:94:ef:e4:0c:ee**

- **UTM #4840 / #5919 NVMe vs virtio-blk**

- **kubevirt#10388, Eureka ****k8s-customize-kops-yaml-spec.py**** Cilium flags**

- **Eureka pins: ****devops/kops-kubevirt/gcp/kops/etc/gcp-k8s-EXAMPLE.conf****, ****devops/kops-kubevirt/kubevirt/*****, ****doc/Kubernetes/resources_created_by_eureka.md****, ****image/kubevirt_instance_template.yaml****, ****afw/src/k8s/tests/**

- **Swiftkube; Sparkle 2; SMAppService**

- **GitHub Releases 2 GiB/file cap**

---
## **Key Decisions**
1. **User-facing name is ****gmak8**** (Grandma Kate + Kubernetes). Repo, CLI, menu bar, About, kube context ****gmak8****, cask ****gmak8****, bundle ****dev.gmak8.app****, LaunchAgent ****dev.gmak8.core****. No Kite/Skiff. No ****kite**** CLI symlink. virtctl stays ****virtctl****.**

2. **Apache-2.0 + DCO; no paid SKU.**

3. **App macOS 14+ Apple Silicon. KubeVirt/Eureka nested virt requires macOS 15+ M3+. Do not bump the whole app to 15.**

4. **Not Electron, not MAS, not Intel hosts in v1.**

5. **VZ + Debian 13 appliance + k3s ****v1.33.3+k3s1**** + containerd. Own VZ in Swift. Kubernetes version is Eureka’s 1.33.3. Guest KVM: ****CONFIG_KVM=y**** or ****=m**** plus ****kvm.ko****; ****modprobe kvm****; ****GET /kvm**** checks ****/dev/kvm****. No TCG.**

6. **Leave helm-controller enabled. Traefik/metrics-server are HelmCharts. “Disable bundled” = k3s ****disable:**** list only.**

7. **SQLite, single node, flannel+kube-proxy+Klipper. Document Cilium-on-GCE as a known divergence. Do not claim kops parity.**

8. **gvproxy vfkit unixgram, MAC ****5a:94:ef:e4:0c:ee****, guest ****192.168.127.2****, exposes on ****127.0.0.1**** only. Short socket under ****Library/Caches****.**

9. **Auto-publish NodePorts to 127.0.0.1 for generic kubectl/curl. Eureka SSH is ****virtctl**** on PATH (****ProxyCommand … --stdio****). Do not document ****ssh -p <nodePort>**** as the Eureka path. env.py HTTPS to EXTERNAL-IP is out. No host :80/:443 helper. Two LBs on 22/80/443 collide — scaled-down target is one VM.**

10. **No privileged helper in v1. ****gmak8-core**** LaunchAgent owns the VM. CLI → ****~/.local/bin**** and/or ****/opt/homebrew/bin****, never required admin.**

11. **Two NVMe disks; ****gmak8-data-format.service**** mkfs before ****mnt-data.mount****; label ****GMAK8_DATA****; k3s ****--data-dir /mnt/data/rancher**** and ****default-local-storage-path: /mnt/data/local-path****; recreate EFI NVRAM on OS replace; refuse start outside the version matrix. Eureka refuses start without the local-path setting.**

12. **NVMe attachment is real types, ****.cached**** + ****.full****. No virtio-blk. No disk resize in v1.**

13. **Airgap k3s (always) and KubeVirt/CDI (Eureka profile) images. Split GitHub assets < 2 GiB. No Docker Hub on first boot.**

14. **Image load: vsock stream → data-disk temp → ****ctr -n k8s.io import****. Host build client = ****buildctl****. No Docker socket. Tilt/Skaffold deploy-only.**

15. **Kubeconfig: read ****/etc/rancher/k3s/k3s.yaml****; private 0600 file; stanza-splice merge only if ****KUBECONFIG**** unset; ****current-context**** default off; rewrite ****server:**** on port change. Own PR + goldens.**

16. **Engine: NDJSON on ****engine.sock****; start/stop/reset return immediately; ****reset**** requires ****force****; status+logs are a subscribe stream. VZ on queue ****dev.gmak8.vm****. flock disks.**

17. **Sparkle: ACPI-stop VM, then ****gmak8-core**** exits, SMAppService unregister (KeepAlive must not restart), wait flock, swap, register, optional start. Update restarts the cluster. ****/Applications**** required. Keyful Cosign. Sign all Helpers.**

18. **virtio-fs: host UIDs pass through (501:20). Warn in Settings. No fake idmap.**

19. **No snapshots. SQLite corruption → Reset. Balloon default off. SET_TIME on wake and resume.**

20. **Rosetta: feature-detect; ****installRosetta()**** if notInstalled; not a 0.9 blocker; amd64 containers only.**

21. **Close window keeps extra + cluster. Quit asks once. Never headless VM without extra.**

22. **v1 GUI: Cluster, Workloads/Pod, KubeVirt, Images, Diagnostics, Settings, Recovery, menu extra. Cut Network/Config/Storage explorers, ⌘K, sample nginx, balloon, saveMachineState.**

23. **Eureka is a profile + addon pack, not a fork. Pins: KubeVirt 1.6.1, CDI v1.62.0, common-instancetypes v1.4.0 as ClusterInstancetype, gates VMExport + EnableVirtioFsConfigVolumes, storage class ****local-path**** on ****/mnt/data/local-path****, CDI ****copy****. Smoke: aarch64 airgapped disk + ****u1.nano****/****u1.medium**** Cluster kind + virtctl stdio + SA virtiofs. Stock ****env.py****/****u1.xlarge****/x86_64 cirros Pending. Full GCE-shaped env later.**

24. **Team 1–2 engineers: 0.9 = PRs 1–18; 1.0 = PRs 19–28 and 30; Rosetta PR 29 out of 0.9.**

25. **Telemetry off. 127.0.0.1 API. No default $HOME mount.**

26. **Builderdash is not a gmak8 feature.** It already calls Kubernetes + SSH. gmak8 supplies the cluster and a **localhost SSH bridge** (virtctl/engine VM forward + optional L1 sshd jump). Mac/ARM qcow, Cluster instancetype, ****local-path****, kubeconfig path, and small RAM/disk are Eureka ****build.config****. No Docker-shaped build API.

---
## **PR Plan**
Independently reviewable. Critical path for a reachable cluster:
**1 → 3 → 4 → 5 → 7 → 8 → 9 → 10 → 11 → 12 → 13**
(kubeconfig splice is PR 4, before k3s uses it. Guest image + disk contract before agent. gvproxy before k3s.)
0. **9 = PRs 1–18** (engine + onboarding + recovery + Sparkle-with-prepareUpdate/gmak8-core-quit + cask gmak8; PRs 2 and 6 parallel). **1.0 = PRs 19–28 and 30** (GUI + KubeVirt/Eureka + Builderdash SSH bridge). Rosetta is **PR 29**, out of 0.9.
### **PR 1 — Repo skeleton**
- **Title: ****chore: Apache-2.0 skeleton, Xcode workspace, package layout**

- **Files: ****LICENSE****, ****NOTICE****, ****README.md****, ****CONTRIBUTING.md****, ****AGENTS.md****, ****.gitignore****, ****.swift-format****, ****Apps/gmak8/gmak8.xcodeproj****, empty ****Gmak8App.swift****, ****Packages/Gmak8Kit**** hello**

- **Depends on: none**

- **Description: App builds and shows a window.**

### **PR 2 — CI (Mac unit)**
- **Title: ****ci: xcodebuild test and swift-format on macos-15 arm64**

- **Files: ****.github/workflows/app.yml****, ****scripts/ci.sh**

- **Depends on: PR 1**

- **Description: No VZ. Fail PRs that do not compile.**

### **PR 3 — Gmak8Kit paths, logging, settings**
- **Title: ****feat: host paths, os_log, versioned settings.json, profile enum**

- **Files: ****Packages/Gmak8Kit/******, tests**

- **Depends on: PR 1**

- **Description: Application Support vs Caches (short sockets), TM-exclusion helper, ****Profile { kubernetes, eureka, eurekaAPIOnly }**** resource defaults, ****schemaVersion****.**

### **PR 4 — Kubeconfig stanza splice**
- **Title: ****feat: gmak8 kubeconfig private file and stanza-splice merge**

- **Files: ****Packages/Gmak8Kit/Kubeconfig/******, goldens (comments, exec plugins, multi-context, port 16443, ****KUBECONFIG**** set ****⇒**** no merge)**

- **Depends on: PR 3**

- **Description: The most important host-side code, not buried in k3s bring-up. ****current-context**** default off.**

### **PR 5 — gmak8-core stub + NDJSON engine + status stream**
- **Title: ****feat: gmak8-core LaunchAgent, engine.sock NDJSON, subscribe stream**

- **Files: ****Apps/gmak8/Gmak8Core/******, ****Packages/Gmak8XPC/******, SMAppService plist, Team-ID/pid tests, ****start**** returns accepted, ****reset**** requires ****force**

- **Depends on: PR 3**

- **Description: No VM. Translocation check refuses register. Two Login Items documented in a comment/UI string.**

### **PR 6 — CLI ****gmak8 status|version**
- **Title: ****feat: gmak8 CLI on engine.sock**

- **Files: ****Apps/gmak8/CLI/****

- **Depends on: PR 5**

- **Description: Same codec as the app.**

### **PR 7 — Virtualization bring-up (EFI, serial, flock, VZ queue)**
- **Title: ****feat: boot Linux EFI VM on gmak8.vm queue with disk flock**

- **Files: ****Packages/Gmak8Virtualization/******, ****Gmak8Core.entitlements**** (****com.apple.security.virtualization**** true), serial Diagnostics**

- **Depends on: PR 5**

- **Description: Hidden defaults path to a raw disk. ****isSupported**** is hardware-only. flock exclusive. Manual test on a real Mac.**

### **PR 8 — Guest image + two-disk/EFI/data-dir contract**
- **Title: ****feat: Debian mkosi appliance, gmak8-data-format.service, GMAK8_DATA, k3s --data-dir and default-local-storage-path, KVM=y-or-m + kvm.ko**

- **Files: ****guest/mkosi/******, ****gmak8-data-format.service****, ****format-data-disk.sh****, ****mnt-data.mount****, ****.github/workflows/guest.yml**

- **Depends on: none (parallel with 7)**

- **Description: Format oneshot Before=mnt-data.mount. Agent/k3s do not format. CI greps ****CONFIG_KVM=y**** or ****=m**** and asserts ****kvm.ko****. ****modprobe kvm**** on boot. Recreate NVRAM on OS replace. Document the contract in ****guest/README.md****. Include ****sshd**** in the appliance (disabled until Eureka profile publishes L1:22 for the Builderdash jump — PR 30).**

### **PR 9 — gvproxy vfkit handshake**
- **Title: ****feat: gvproxy --listen-vfkit unixgram, pinned MAC/IP, 127.0.0.1 expose**

- **Files: ****ThirdParty/gvproxy**** pin + sign script, ****Gmak8Virtualization**** file-handle NIC, Cache socket paths**

- **Depends on: PR 7**

- **Description: Guest DHCP ****192.168.127.2****. Expose payload uses ****local: 127.0.0.1:…****. Restart-on-crash hook (ENOBUFS later).**

### **PR 10 — vsock guest agent**
- **Title: ****feat: vsock HTTP agent on 1024 (health, disks, time, shutdown)**

- **Files: ****guest/agent/******, ****Packages/Gmak8GuestClient/****

- **Depends on: PR 7, PR 8**

- **Description: Port 1024 is agent; gvproxy is not vsock. ****PUT /time**** for wake/resume.**

### **PR 11 — k3s 1.33.3 + kubeconfig**
- **Title: ****feat: k3s v1.33.3+k3s1, forward 6443, write gmak8 kubeconfig**

- **Files: ****guest/k3s/******, config share, uses PR 4 merge, start steps through Node Ready**

- **Depends on: PR 4, PR 9, PR 10**

- **Description: ****kubectl --context gmak8 get nodes**** with unmodified kubectl. helm-controller left on. Admin file ****/etc/rancher/k3s/k3s.yaml****. ****default-local-storage-path: /mnt/data/local-path****. Compatibility matrix probe.**

### **PR 12 — k3s airgap images**
- **Title: ****feat: import k3s-airgap-images-arm64 into data-dir agent/images**

- **Files: ****guest/airgap/******, ****.github/workflows/airgap.yml****, Cosign sign, downloader in onboarding**

- **Depends on: PR 8, PR 11**

- **Description: First boot does not pull ****docker.io/rancher/*****. Size budget in CI assertion.**

### **PR 13 — NodePort / LoadBalancer publish**
- **Title: ****feat: auto-publish Service nodePorts to 127.0.0.1 via gvproxy**

- **Files: ****gmak8-core**** watch (once Swiftkube exists this can be guest-side kubectl watch in v0.9: agent lists services), collision UI model, 8080/8443 collision recovery**

- **Depends on: PR 9, PR 11**

- **Description: v0.9 can poll ****kubectl get svc -A -o json**** via agent. Rewrite API ****server:**** on 16443. Generic kubectl/curl path. Not Eureka SSH.**

### **PR 14 — Menu extra, quit UX, cluster state**
- **Title: ****feat: MenuBarExtra, close-vs-quit, LaunchAgent keep-alive**

- **Files: ****Apps/gmak8/****** extra, first-quit sheet, icon states**

- **Depends on: PR 5, PR 11**

- **Description: No headless VM without extra. Launch at login starts extra.**

### **PR 15 — Onboarding**
- **Title: ****feat: first-run (assets, /Applications, profiles, CLI path, current-context checkbox off)**

- **Files: onboarding SwiftUI, Cosign verify, ****~/.local/bin**** + ****/opt/homebrew/bin**** detect**

- **Depends on: PR 12, PR 14**

- **Description: Two Login Items copy. Nested-virt probe informational.**

### **PR 16 — Recovery + diagnostics zip**
- **Title: ****feat: recovery kinds including disk lock, port classes, Reset-only SQLite**

- **Files: ****RecoveryView****, ****lsof**** helper, redacting zip**

- **Depends on: PR 14, PR 11**

- **Description: Fake-engine tests. No snapshot action.**

### **PR 17 — Self-hosted soak harness**
- **Title: ****ci: gmak8-vm self-hosted start/stop, dirty-kill fsck, NodePort curl**

- **Files: ****.github/workflows/soak.yml****, ****scripts/soak.sh**

- **Depends on: PR 11, PR 13**

- **Description: Manual runner label until hardware exists. 0.9 gate: start/stop, dirty-kill fsck, NodePort curl. KubeVirt/virtctl soaks wait for PRs 25–28.**

### **PR 18 — Sparkle with VM-stop + signing/notary/DMG/cask ****gmak8**
- **Title: ****feat: Sparkle EdDSA, prepareUpdate quits gmak8-core, Developer ID, cask gmak8**

- **Files: Sparkle, ****prepareUpdate**** in engine, SMAppService unregister/register around swap, ****scripts/package-dmg.sh****, ****scripts/notarize.sh****, ****docs/security.md****, ****dist/cask/gmak8.rb**

- **Depends on: PR 15, PR 16**

- **Description: ****willInstallUpdate**** → ACPI-stop → gmak8-core exits → unregister agent (KeepAlive must not respawn) → wait flock → swap → register → optional start. Helpers signed. Closes 0.9.**

### **PR 19 — Swiftkube + Cluster overview (1.0)**
- **Title: ****feat: Swiftkube client and running overview**

- **Files: ****Packages/Gmak8Kubernetes/******, Cluster screen**

- **Depends on: PR 11**

- **Description: Fake client for UI tests.**

### **PR 20 — Workloads + pod detail/logs**
- **Title: ****feat: namespace-scoped workloads and pod logs/events/YAML**

- **Files: ****Apps/gmak8/Workloads/****

- **Depends on: PR 19**

- **Description: No Network/Config/Storage explorers. No sample nginx. No ⌘K.**

### **PR 21 — Images list/load/prune (protocol)**
- **Title: ****feat: vsock image import to ctr k8s.io with preflight and progress**

- **Files: agent ****PUT /images/import****, Images screen, ****gmak8 image ***

- **Depends on: PR 10, PR 12**

- **Description: Implements the load protocol. ****loadImage(path:)**** not bookmarks.**

### **PR 22 — BuildKit + bundled buildctl**
- **Title: ****feat: gmak8 build via Helpers/buildctl and guest buildkitd vsock 1025**

- **Files: ****guest/buildkit/******, ****Contents/Helpers/buildctl****, Images → Build**

- **Depends on: PR 21**

- **Description: containerd worker namespace ****k8s.io****. README Tilt snippet.**

### **PR 23 — Settings scene**
- **Title: ****feat: Settings (profiles, disable= flags, files uid, proxy injection, published ports)**

- **Files: Settings SwiftUI, Keychain registry creds, SCDynamicStore → ****proxy.env**

- **Depends on: PR 3, PR 11, PR 13**

- **Description: Balloon control visible, default off, labeled unsupported.**

### **PR 24 — virtio-fs host mounts**
- **Title: ****feat: user-selected virtio-fs shares with 501:20 warning and stat test**

- **Files: VZ directory shares, agent fstab, Settings Files**

- **Depends on: PR 7, PR 23**

- **Description: NSOpenPanel. Unit/integration asserts guest ****stat**** uid.**

### **PR 25 — Nested-virt platform flag**
- **Title: ****feat: enable VZ nested virt when supported; /dev/kvm in agent health**

- **Files: ****VZGenericPlatformConfiguration****, agent ****GET /kvm****, Cluster badge**

- **Depends on: PR 7, PR 10**

- **Description: macOS 15+ API gated. M1/M2 stay false.**

### **PR 26 — KubeVirt + CDI + instancetypes airgap pack**
- **Title: ****feat: KubeVirt 1.6.1 addon pack, CDI v1.62.0, common-instancetypes v1.4.0, aarch64 smoke disk, virtctl on PATH**

- **Files: ****guest/kubevirt/******, airgap tarball (virt-launcher+virtiofsd + aarch64 containerDisk), agent installer, ****Contents/Helpers/virtctl**** → ****~/.local/bin/virtctl**

- **Depends on: PR 12, PR 25**

- **Description: No GitHub ****curl | apply**** at runtime. StorageProfile ****local-path**** cloneStrategy ****copy****. Apply common-instancetypes exactly as Eureka’s kustomize v1.4.0; verify Cluster ****u1.nano****. Feature gates VMExport + EnableVirtioFsConfigVolumes.**

### **PR 27 — KubeVirt UI**
- **Title: ****feat: sidebar for VM, VMI, VMPool, DataVolume list/detail/YAML/start-stop**

- **Files: ****Apps/gmak8/KubeVirt/******, generic Swiftkube CRDs**

- **Depends on: PR 19, PR 26**

- **Description: Honest Pending copy. No OOD, no virtctl SSH GUI.**

### **PR 28 — Eureka profile defaults + docs**
- **Title: ****feat: Eureka/API-only profiles, resource gates, k3s-deltas and Eureka-local docs**

- **Files: onboarding profile, Settings, ****docs/eureka-local.md**** (image digest, ****u1.nano****/****u1.medium**** Cluster kind, virtctl PATH, HTTPS-to-LB out), ****docs/k3s-deltas.md****, ****CHANGELOG.md**

- **Depends on: PR 15, PR 26, PR 13**

- **Description: Refuse Eureka profile on low RAM, no nested virt, or missing ****default-local-storage-path****. 1.0 soak: one aarch64 VMI Ready + SA virtiofs + ****virtctl --stdio****. Test 050 stretch. Do not copy Eureka sources. ****docs/eureka-local.md**** must include the Builderdash Mac/ARM config matrix (kubeconfig, ****local-path****, aarch64 qcow, Cluster ****u1.medium****, proxy_conf / localhost forward, one-image-at-a-time). Do not vendor builderdash.**

### **PR 29 — Rosetta install prompt (not 0.9)**
- **Title: ****feat: Rosetta-for-Linux installRosetta and amd64 container warning**

- **Files: availability switch, Images banner**

- **Depends on: PR 21, PR 7**

- **Description: Feature-detect; OS-version branch if required.**

### **PR 30 — VMI localhost SSH bridge (Builderdash)**

- **Title:** ****feat: port-forward vm/vmi to 127.0.0.1 and optional L1 sshd jump****
- **Files:** engine ****portForwardStart**** ****kind: vm|vmi****, CLI ****gmak8 port-forward****, guest sshd unit + Eureka-profile publish of L1:22 to a high localhost port, Settings copy, soak in ****scripts/soak.sh****
- **Depends on:** PR 5, PR 8 (sshd in image), PR 13 (collision UI), PR 26 (virtctl)
- **Description:** Implement the Builderdash SSH bridge. Path B: ****gmak8-core**** execs bundled virtctl ****--address 127.0.0.1**** for ****kind: vm|vmi****; CLI ****gmak8 port-forward vm/&lt;name&gt; 2222:22****. Path C: Eureka profile can enable L1 sshd published to ****127.0.0.1:&lt;highport&gt;**** so unmodified builderdash ****proxy_conf**** jumps Mac → L1 → VMI pod IP. Never bind 0.0.0.0; never host :22. Soak: SSH handshake to 127.0.0.1, not a full ****build.py -k****. 1.0.

PRs 2, 6, 8 can parallel the critical path. Sparkle (18) must not enable until prepareUpdate quits gmak8-core. **0.9 ends at PR 18.** KubeVirt UI is 1.0 (19–28). **Builderdash SSH is PR 30 (1.0).** Rosetta is 29.