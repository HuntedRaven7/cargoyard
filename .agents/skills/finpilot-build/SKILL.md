---
name: finpilot-build
description: >-
  Containerfile multi-stage build, image digest pinning in FROM lines,
  Justfile local build recipes, and build script conventions.
  Use when changing Containerfile, Justfile, or build/*.sh.
---

# finpilot Build System

## When to Use

- Editing `Containerfile` (ARGs, stages, base image, RUN directives)
- Editing `Justfile` (build recipe, tag strategy, version computation)
- Adding or modifying `build/*.sh` scripts
- Debugging why a local build fails differently from CI

## When NOT to Use

- CI workflow changes (`.github/workflows/`) — use `finpilot-ci`
- Runtime customizations (`custom/`) — use `finpilot-custom`

## Core Process

1. **Identify which `FROM` line or ARG drives your change**
2. **All image digests** are pinned directly in `Containerfile` `FROM` lines; Renovate updates them
3. **Run `just build`** locally before opening a PR; `just lint` to shellcheck
4. **Add `00-` prefix** for metadata scripts, `10-` for main packages, `20+` for extras

## Image Pinning Pattern

All OCI images are pinned directly in `Containerfile` `FROM` lines. Renovate's
built-in `dockerfile` manager updates every digest.

```dockerfile
# OCI context images
FROM ghcr.io/projectbluefin/common:latest@sha256:<current> AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:<current> AS brew

# Base image
ARG FEDORA_MAJOR_VERSION="44"
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:<current>
```

**Never update digests manually.** Let Renovate open PRs for digest bumps.

To change an image or tag, edit its `FROM` line. To bump the Fedora major
release, update both the `FEDORA_MAJOR_VERSION` ARG and the base image tag.

## Build Script Conventions

### Multi-variant layout

This repo builds five images: `edward` (main, Arch base) plus the friends
`aira`, `crmy`, `server` (bootc) and `ai` (app container). Build scripts and
custom assets are centralized per variant at the repo root:

```
build/
├── edward/                  # pacman (Arch base)
│   ├── 00-image-info.sh     # image-info.json + os-release branding
│   ├── 10-build.sh          # brew overlay, custom files, pacman install, services
│   ├── clean-stage.sh       # cleanup, always runs last
│   └── *.sh.example         # dnf5-based templates from the old multi-variant days
├── aira/                    # dnf5 (Bazzite base), incl. copr-helpers.sh
├── crmy/                    # dnf5 (fedora-bootc base)
└── server/                  # dnf5 (uCore base)

custom/
├── edward/                  # brew/, flatpaks/, ujust/, system_files/, container/
│   └── container/Containerfile.edward   # main image Containerfile
├── aira/  ├── crmy/  └── server/

friends/
├── aira/                    # Containerfile + system_files/
└── crmy/                    # Containerfile only (no system_files)
# Each friend Containerfile uses the REPO ROOT as context:
#   COPY build/<variant> /build
#   COPY custom/<variant> /custom
#   COPY friends/<variant>/system_files /system_files

server/                       # bootc sibling OUTSIDE friends/: own workflow
ai/                           # app container (CUDA+Brew): no build/ or custom/,
                              #   own workflow; quadlet under ai/system_files/
```

- **edward's package manager is pacman**: `pacman -Syu --noconfirm --needed ...`.
  Never call dnf5 there; the Arch base does not have it. Friends use dnf5.
- Each bootc Containerfile chain runs `/ctx/build/00-image-info.sh` →
  `/ctx/build/10-build.sh` → `/ctx/build/clean-stage.sh` from its variant dir.
- No `FEDORA_MAJOR_VERSION` ARG in edward; `00-image-info.sh` omits the JSON
  field and the Justfile build recipe falls back to date-only version strings.
- aira/crmy are built by the matrix in `.github/workflows/build-friends.yml`,
  server by `build-server.yml`; `ai` is built with plain podman by
  `build-ai.yml` (not `just build`).
- `copr-helpers.sh` exists only under `build/{aira,crmy,server}/` (COPR is
  dnf5-only). The `.example` scripts reference it only as archived templates.

### Numbering

| Prefix             | Purpose                                                        |
| ------------------ | -------------------------------------------------------------- |
| `00-image-info.sh` | Metadata only: writes `image-info.json`, customises `os-release` |
| `10-build.sh`      | Main script: copies custom files, installs packages            |
| `20-*.sh`          | Optional extras                                                |
| `30-*.sh`          | Optional desktop swaps                                         |
| `clean-stage.sh`   | Always runs last: clears caches and artefacts                  |

### Template build script rules

- **Default packages**: build scripts in the template must have **no packages installed by default** — only commented examples. Users add their own.
- **Exception**: `dnf5 install -y tmux` is intentionally present as a minimal smoke-test that the DNF cache is warm. Do not remove it.
- Always use `dnf5` — never `dnf`, `yum`, or `rpm-ostree`
- Always use `dnf5 install -y` (non-interactive)
- COPR: enable → install → `copr_install_isolated` (auto-disables); never leave a repo enabled

### NVIDIA GPU support

NVIDIA support is a build-time option activated by renaming the example script and adding its explicit Containerfile `RUN` block:

```bash
mv build/40-nvidia.sh.example build/<variant>/40-nvidia.sh
# Add the standard RUN block for /ctx/build/<variant>/40-nvidia.sh after
# 10-build.sh. See build/README.md.
just build
```

All NVIDIA logic is self-contained in `40-nvidia.sh`. When both the script and its explicit Containerfile `RUN` block are activated, it provisions the NVIDIA driver, CDI container toolkit, Mutter kms-modifiers, and bootc kernel args directly into the base image — no separate image variant, no `IMAGE_NAME` gating.

Deactivate by removing its Containerfile `RUN` block and renaming the script back to `.example`. See `build/40-nvidia.sh.example` for the full implementation.

### 00-image-info.sh branding

The comment in the `os-release` append block must use `${IMAGE_NAME}`:

```bash
cat >> "${OS_RELEASE}" << EOF

# ${IMAGE_NAME} image identity   ← use variable, not literal "finpilot"
VARIANT_ID="${IMAGE_FLAVOR}"
...
EOF
```

## Base Image

Per-variant bases, pinned in each Containerfile's `FROM` line:

| Variant  | Base                                            | Package manager |
| -------- | ----------------------------------------------- | --------------- |
| edward   | `ghcr.io/huntedraven7/arch-bootc:testing`       | pacman          |
| aira     | `ghcr.io/ublue-os/bazzite:stable`               | dnf5            |
| crmy     | `quay.io/fedora/fedora-bootc:44`                | dnf5            |
| server   | `ghcr.io/ublue-os/ucore:stable`                 | dnf5            |

Fedora variants control the major version via the `FEDORA_MAJOR_VERSION` ARG
and the `FROM` line. To bump a Fedora release:

1. Update `FEDORA_MAJOR_VERSION` and the `FROM` line in that variant's Containerfile
2. Update the Renovate rule that blocks major updates for the base image
3. Test with `just build` — expect `bootc container lint --fatal-warnings` to catch regressions

## Common Rationalizations

| Rationalization                                                      | Reality                                                                                                |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| "I'll skip the digest pin and use a floating tag."                   | Non-reproducible builds and breaks supply-chain traceability. The `FROM` line should always be pinned. |
| "Renovate won't notice a manually pinned digest in `Containerfile`." | Renovate's dockerfile manager tracks `FROM image:tag@sha256:...` in `Containerfile` automatically.     |
| "I'll add `dnf` as a fallback since dnf5 might not be installed."    | Never. `dnf5` is the canonical tool. Using `dnf` or `rpm-ostree` diverges from Bluefin.                |

## Red Flags

- Floating tags (`FROM image:latest` without `@sha256:...`)
- `FROM ${FOO}@${BAR}` where `BAR` could be empty
- `dnf`, `yum`, or `rpm-ostree` in any build script
- Wrong package manager for the variant: dnf5 in `build/edward/`, pacman elsewhere
- COPR left enabled after package install (missing `dnf5 copr disable`)
- `# finpilot image identity` hardcoded instead of `# ${IMAGE_NAME} image identity`

## Verification

- [ ] Are all `FROM` lines pinned with `@sha256:...`?
- [ ] Does each variant's `00-image-info.sh` use `${IMAGE_NAME}` in the os-release comment?
- [ ] Does `just build` succeed locally?
- [ ] Does `just lint` pass clean (shellcheck)?
- [ ] Does `bootc container lint --fatal-warnings` pass in CI?
