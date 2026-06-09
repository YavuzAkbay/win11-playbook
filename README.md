# Win11 Gaming Playbook

Aggressive Windows 11 debloat + gaming optimizations in a single PowerShell script.  
Gaming-focused: keeps Xbox/GameBar, strips everything else.

---

## Quick Start

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/YavuzAkbay/win11-gaming-playbook/main/Win11-Gaming-Playbook.ps1 | iex
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
| 15 | Extended tweaks | Mouse accel, FSO, MPO, Teredo, sticky keys, classic context menu, temp cleanup |
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
