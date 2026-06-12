# Win11 Gaming Playbook

Aggressive Windows 11 debloat + gaming optimizations in a single PowerShell script.  
Gaming-focused: keeps Xbox/GameBar, strips everything else.

---

## Quick Start

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/YavuzAkbay/win11-playbook/main/Win11-Gaming-Playbook.ps1 | iex
```

> Must be an elevated (Admin) PowerShell window. The script will error with instructions if you forget.

**Reboot after it finishes.**

---

## What It Does

| # | Section | Notes |
|---|---------|-------|
| 01 | Safety — restore point | Creates a system restore point before any changes |
| 02 | Bloatware removal | Removes Microsoft + OEM noise apps |
| 03 | OneDrive removal | Full uninstall + folder cleanup |
| 04 | Telemetry & data collection | Disables diagnostic data, activity history, feedback |
| 05 | Copilot & AI features | Removes Copilot, AI-powered suggestions |
| 06 | UI cleanup & taskbar | Cleans taskbar, disables widgets, ads, tips |
| 07 | Service optimization | Disables unused services, keeps gaming-relevant ones |
| 08 | Windows Update control | **Interactive** — Recommended / Minimal / Off |
| 09 | Gaming optimizations | HAGS, HPET, Ultimate Performance plan, Nagle disable |
| 10 | Visual performance tweaks | Disables animations, transparency effects |
| 11 | Privacy deep clean | Location, camera, mic, contacts, advertising ID |
| 12 | Telemetry IP block | Blocks Microsoft telemetry endpoints via hosts file |
| 13 | Browser | **Interactive** — remove Edge, install Helium / Brave / Firefox |
| 14 | Memory & I/O tweaks | Page file, large system cache, NTFS tweaks |
| 15 | Extended tweaks | Mouse accel, FSO, Teredo, sticky keys, classic context menu, temp cleanup (MPO left **enabled** to avoid forced-VSync feel in windowed games) |
| 16 | Power & performance | USB suspend, PCIe ASPM, timer resolution, power throttling, NIC power saving |
| 17 | Gaming runtimes | VC++ 2005–2022, .NET 3.5/6/7/8/9, DirectX Jun2010, DirectPlay, XNA 4.0, OpenAL, WebView2, PhysX + **Interactive** launcher install |
| 18 | Windows Defender | **Interactive** — disable / drive exclusions / skip |
| 19 | Startup optimization | Autorun cleanup, delayed services, UWP background access, boot config |
| 20 | Final cleanup | Temp files, restart Explorer |

---

## Interactive Prompts

At startup, the script asks:

- **Remove Edge?** — yes / no
- **Browser** — Helium / Brave / Firefox / None
- **Gaming launchers** — Steam, Playnite, Epic Games, GOG Galaxy, EA App (multi-select)
- **Windows Update policy** — Recommended / Minimal / Off

During the run:

- **Windows Defender** — disable completely / add drive exclusions / skip
- **Reboot now?** — at the end

---

## Requirements

- Windows 11 22H2 / 23H2 / 24H2
- PowerShell 5.1+ (built-in on Win11)
- Internet connection (for runtime/launcher downloads in section 17)
- Admin privileges

---

## Skip Sections

To skip a section, open the script and comment out the `#region` block you want to omit before running:

```powershell
# #region 03 — ONEDRIVE REMOVAL
# ...
# #endregion
```

Or clone and run locally:

```powershell
git clone https://github.com/YavuzAkbay/win11-gaming-playbook
cd win11-gaming-playbook
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Win11-Gaming-Playbook.ps1
```

---

## Notes

- Xbox / GameBar services are **deliberately preserved**
- Reboot required for: HAGS, HPET, bcdedit changes, power plan, and service changes
- A system restore point is created before any changes (section 01)
- `$ErrorActionPreference = "SilentlyContinue"` — non-critical failures are swallowed silently

---

## VSync & Windowed Mode

This playbook does **not** force VSync on. Earlier versions disabled **Multiplane Overlay (MPO)** and enabled Windows' **Variable Refresh Rate** optimization — together these routed games through the desktop compositor and could make your in-game *"VSync off"* setting feel like it did nothing. Both are now left at gamer-friendly defaults (MPO enabled, VRR optimization off), and re-running the playbook will undo those tweaks if a previous version applied them. **Reboot for the MPO change to take effect.**

One thing no tweak can change: **Windows always syncs the final frame in borderless / windowed mode.** The desktop compositor (DWM) presents windowed games in step with your monitor's refresh, so *"VSync off"* may still look VSync-like there — this is standard Windows behavior on any PC, with or without this playbook.

If VSync still feels stuck on:

- **Run the game in true Exclusive Fullscreen** (not "Fullscreen Borderless" / "Windowed"). The playbook disables Fullscreen Optimizations so your in-game VSync toggle fully applies there.
- **Check your GPU driver:** NVIDIA Control Panel → *Vertical sync*, or AMD Software → *Wait for Vertical Refresh*. Set to "Off" or "Use the 3D application setting."
- **G-Sync / FreeSync** (driver or monitor OSD) can also impose refresh-synced behavior — toggle it there, not in the registry.

---

## Disclaimer

This project is a **configuration playbook only**. It applies registry tweaks, adjusts Windows settings, removes built-in apps, and installs gaming runtimes/launchers from their official sources.

- No modified or pre-activated Windows ISOs are distributed here
- No Windows activation tools, KMS scripts, or license bypasses are included or endorsed
- You must own a valid Windows 11 license
- Use at your own risk — a restore point is created before changes, but always back up important data first
