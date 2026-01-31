# System Administration Ways

Guidance for managing local and remote systems.

## Domain Scope

This covers hands-on system work: package management, service control, filesystem operations, user management, and hardware interfaces. It spans local workstations (primarily Arch Linux), remote hosts over SSH, serial interfaces, and cross-platform considerations for Windows users who fork this repo.

Cloud provider platforms (AWS, GCP, Azure, Cloudflare) have their own domain. This domain is for the machines themselves.

## Principles

### Know the platform before acting

System commands are not portable. `pacman -S` is not `apt install` is not `winget install`. Detect the platform and use its native tools rather than assuming.

### Prefer declarative over imperative

When possible, describe the desired state rather than the steps to reach it. `systemctl enable --now nginx` (declarative: this service should be running) over a sequence of start/check/configure commands. This makes operations idempotent and self-documenting.

### Respect the user's authority model

Sometimes we have passwordless sudo. Sometimes we don't. Sometimes we're root directly. Don't assume - check, adapt, and ask if unclear. Never bypass or weaken security for convenience unless explicitly instructed.

### Serial and hardware interfaces are different

Serial consoles (`minicom`, `screen /dev/ttyUSB0`, etc.) are not SSH. They're synchronous, character-at-a-time, and have no reliable prompt detection. Timeouts and expect-style patterns matter more than exit codes.

---

## Ways

### packages

**Principle**: Package management should be aware of the distribution. Arch (pacman/yay), Debian/Ubuntu (apt), RHEL (dnf), macOS (brew), Windows (winget/choco/scoop).

**Triggers on**: Running package managers or mentioning package installation.

**Guidance direction**: Detect the distro from `/etc/os-release` or equivalent. Use the native package manager. For Arch specifically: check the AUR when the official repos don't have it, prefer `yay` for AUR packages, and be aware that Arch is rolling release (partial upgrades break things - `pacman -Syu` before installing).

### services

**Principle**: Service management is systemd on modern Linux, launchd on macOS, services on Windows. Know which you're on.

**Triggers on**: Running `systemctl`, `service`, `launchctl`, or mentioning daemons.

**Guidance direction**: Use `systemctl` patterns (enable/disable, start/stop, status, journal). Check if a service exists before trying to manage it. For user services vs system services, know the difference. Show journal output when debugging.

### filesystem

**Principle**: Filesystem operations at the system level (mounts, permissions, disk usage) are different from application-level file operations.

**Triggers on**: Running `mount`, `chmod`, `chown`, `df`, `du`, `fdisk`, `lsblk`, or mentioning disk/permissions.

**Guidance direction**: Check before modifying. `lsblk` before partitioning, `df -h` before assuming space, `stat` before changing permissions. For destructive operations (formatting, overwriting partitions), confirm explicitly.

### networking

**Principle**: Network configuration and troubleshooting at the system level.

**Triggers on**: Running `ip`, `ss`, `netstat`, `iptables`/`nft`, `nmcli`, `ping`, `traceroute`, `dig`, or mentioning network configuration.

**Guidance direction**: Modern tools over legacy (`ip` over `ifconfig`, `ss` over `netstat`). For firewall rules, check existing rules before adding. For DNS, check both local resolution and upstream.

### serial

**Principle**: Serial interfaces require different patterns than network connections. No reliable prompt detection, character-at-a-time, hardware flow control matters.

**Triggers on**: Running `minicom`, `screen` with `/dev/tty*`, `picocom`, or mentioning serial/UART/console.

**Guidance direction**: Check device permissions (`ls -la /dev/ttyUSB0`, user in `dialout` group). Set baud rate correctly (usually 115200 for modern devices, 9600 for legacy). Use expect-style patterns for automation rather than exit codes. Always have a clean disconnect plan.

### sudo

**Principle**: Privilege escalation patterns depend on the host's configuration. Don't assume.

**Triggers on**: Running `sudo` or discussing privilege escalation.

**Guidance direction**: Check if passwordless sudo is available (`sudo -n true 2>/dev/null`). If not, inform the user rather than hanging on a password prompt. For operations requiring root, batch them into a single sudo invocation where possible. Never suggest weakening sudoers for convenience unless asked.

### windows

**Principle**: Windows administration for users who fork this repo. PowerShell is the primary interface, not cmd.

**Triggers on**: Running PowerShell commands, mentioning Windows administration, or detecting a Windows environment.

**Guidance direction**: Use PowerShell idioms (Get-Command, Get-Service, Get-Process). For package management, prefer winget (built-in) over chocolatey/scoop unless the user has a preference. Be aware of UAC (User Account Control) as the Windows equivalent of sudo. WSL is a bridge, not a replacement - know when to use native Windows tools vs WSL.
