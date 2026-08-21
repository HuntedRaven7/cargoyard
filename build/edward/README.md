# Build Scripts

Build scripts for the `edward` image (Arch Linux bootc base, Hyprland +
Quickshell). This is the per-variant directory for edward; sibling variants
live in `build/aira/`, `build/crmy/`, and `build/server/`. `.sh.example`
files are archived dnf5 templates from the old multi-variant setup.

## Layout

```
build/edward/
├── 00-image-info.sh            # image-info.json + os-release branding
├── 10-build.sh                 # brew overlay, custom files, pacman install, services
├── clean-stage.sh              # cleanup, always runs last
├── 20-onepassword.sh.example   # archived dnf5 templates (aira/crmy/server era)
├── 30-cosmic-desktop.sh.example
└── 40-nvidia.sh.example
```

## Containerfile Chain

`custom/edward/container/Containerfile.edward` runs them explicitly:

```dockerfile
RUN ... /ctx/build/00-image-info.sh
RUN ... /ctx/build/10-build.sh
RUN ... /ctx/build/clean-stage.sh
```

## Package Manager

The base is `ghcr.io/huntedraven7/arch-bootc`, so everything uses **pacman**:

```bash
pacman -Syu --noconfirm --needed package-name
```

Never call dnf5 here — the Arch base does not have it. `clean-stage.sh` has no
dnf5 blocks; it exempts `/var/cache/pacman` instead of libdnf5.

## Adding Scripts

Add numbered scripts to this directory and an explicit RUN block to the
Containerfile:

```bash
# 20-development.sh - dev tools
# 30-gaming.sh      - gaming software
```

### Best Practices

- **Use descriptive names**: `30-gaming.sh` is better than `30-stuff.sh`
- **One purpose per script**: Easier to debug and maintain
- **Clean up after yourself**: Remove temporary files
- **Test incrementally**: Add one script at a time and test builds

### Disabling Scripts

Remove the corresponding `RUN` block from the Containerfile and delete the script.

## Notes

- Scripts run as root during build
- Build context is available at `/ctx`
- Always use a non-interactive flag (`--noconfirm`)
