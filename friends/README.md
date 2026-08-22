# Friends

Bootc sibling images that live alongside `edward` in this repo. Each folder
holds a Containerfile plus its variant-specific system files; shared assets
are centralized at the repo root per variant:

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

CI builds both variants via the matrix in
`.github/workflows/build-friends.yml`. Base images are digest-pinned in each
Containerfile's `FROM` lines; Renovate updates them.

## Variants

| Folder | Image          | Base                       | Package manager |
| ------ | -------------- | -------------------------- | --------------- |
| aira   | aira           | ghcr.io/ublue-os/bazzite   | dnf5            |
| crmy   | crmy           | quay.io/fedora/fedora-bootc| dnf5            |

## Outside friends/

Two siblings live in their own top-level directories with their own workflows:

| Folder  | Image            | Workflow                          | Kind                |
| ------- | ---------------- | --------------------------------- | ------------------- |
| server/ | server           | `.github/workflows/build-server.yml` | bootc (uCore)    |
| ai/     | ai               | `.github/workflows/build-ai.yml`     | app container (CUDA + Brew) |
