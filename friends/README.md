# Friends

Sibling images that live alongside `edward` in this repo. Each folder holds a
Containerfile plus its variant-specific system files; shared assets are
centralized at the repo root per variant:

```
<variant>/
├── Containerfile      # context is the REPO ROOT (see COPY paths)
└── system_files/      # variant system files (where they exist)

build/<variant>/       # numbered build scripts for this variant
custom/<variant>/      # brew/ujust/flatpak assets for this variant
```

## Building

From the repo root (the COPY paths in each Containerfile are relative to it):

```bash
podman build -f friends/<variant>/Containerfile -t <image-name>:stable .
```

CI builds all variants via the matrix in
`.github/workflows/build-friends.yml`. Base images are digest-pinned in each
Containerfile's `FROM` lines; Renovate updates them.

## Variants

| Folder | Image            | Base                          | Package manager |
| ------ | ---------------- | ----------------------------- | --------------- |
| aira   | cargoyard-aira   | ghcr.io/ublue-os/bazzite      | dnf5            |
| crmy   | cargoyard-crmy   | quay.io/fedora/fedora-bootc   | dnf5            |
| server | cargoyard-server | ghcr.io/ublue-os/ucore        | dnf5            |
| ai     | ai               | docker.io/nvidia/cuda (ubuntu)| brew            |

The `ai` folder differs from the bootc variants above: it is a plain
application container (CUDA + Brew), so it has no `build/` or `custom/` —
just a `Containerfile` and its quadlet/desktop entry under `system_files/`.
