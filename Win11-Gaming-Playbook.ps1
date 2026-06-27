#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Win11 Gaming Debloat Playbook

.DESCRIPTION
    Aggressive Windows 11 debloat + gaming optimizations.
    Gaming-focused: Xbox/GameBar kept by default, optional full removal.

    HOW TO USE:
      1. Right-click this file -> "Run with PowerShell" (as Admin)
         OR open an elevated PowerShell and run:
         Set-ExecutionPolicy Bypass -Scope Process -Force; .\Win11-Gaming-Playbook.ps1

      2. At startup, choose your browser (Helium / Brave / Firefox / None),
         whether to remove Edge, and which gaming launchers to install.

      3. Comment out any #region you want to skip before running.

      4. REBOOT after the script finishes.

    SECTIONS:
      01 - Safety (restore point)
      02 - Bloatware removal
      03 - OneDrive removal
      04 - Telemetry & data collection
      05 - Copilot & AI features
      06 - UI cleanup & taskbar
      07 - Service optimization
      08 - Windows Update control (interactive: recommended / minimal / off)
      09 - Gaming optimizations (HAGS, HPET, Ultimate Performance, Nagle)
      09b - Xbox removal (optional: apps, services, Game Bar, Game Mode)
      10 - Visual performance tweaks
      11 - Privacy deep clean
      12 - Telemetry IP block (hosts file)
      13 - Browser (interactive: remove Edge, install Helium/Brave/Firefox)
      14 - Memory & I/O tweaks
      15 - Extended tweaks (mouse accel, FSO, Teredo, WPBT, hibernation,
           SvcHost, sticky keys, classic context menu, temp cleanup)
      16 - Power & performance (USB suspend, PCIe ASPM, processor min/max,
           sleep/hibernate, display, wireless, fast startup, timer resolution,
           power throttling, NIC power saving)
      17 - Gaming runtimes (VC++ 2005-2022 all, .NET 3.5+6/7/8/9,
           DirectX June 2010, DirectPlay, XNA 4.0, OpenAL, WebView2, PhysX)
           + interactive gaming launcher install (Steam, Playnite, Epic, etc.)
      18 - Windows Defender (interactive: disable completely / drive exclusions / skip)
      19 - Startup optimization (autorun cleanup, services Manual/Delayed, logon tasks,
           UWP background access, boot config, RunOnce sweep)
      20 - Final cleanup & restart Explorer

.NOTES
    Tested on: Windows 11 22H2 / 23H2 / 24H2
    Xbox services are deliberately preserved for gaming.
    Reboot required for: HAGS, HPET, bcdedit, power plan, and service changes.
#>

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$Host.UI.RawUI.WindowTitle = "Win11 Gaming Playbook — Yavuz Akbay"

# ── Header ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Windows 11 Gaming Optimization Playbook" -ForegroundColor Cyan
Write-Host "  by Yavuz Akbay" -ForegroundColor DarkGray
Write-Host "  ─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Section([string]$Name) {
    Write-Host ""
    Write-Host "━━━ $Name " -ForegroundColor Cyan -NoNewline
    Write-Host ("━" * [Math]::Max(0, 55 - $Name.Length)) -ForegroundColor DarkCyan
}

function Write-OK([string]$Msg)   { Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Write-Skip([string]$Msg) { Write-Host "  · $Msg" -ForegroundColor DarkGray }
function Write-Info([string]$Msg) { Write-Host "  → $Msg" -ForegroundColor Gray }

function Set-Reg {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Disable-Service([string]$Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Info "Disabled service: $Name"
    }
}

function Disable-Task([string]$TaskPath, [string]$TaskName) {
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Disable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue | Out-Null
        Write-Info "Disabled task: $TaskName"
    }
}

function Set-WindowsUpdate-RebootSafety {
    $au = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

    Set-Reg $au "NoAutoRebootWithLoggedOnUsers" 1
    Set-Reg $wu "SetAutoRestartNotificationConfig" 1
    Set-Reg $wu "ConfigureDeadlineNoAutoReboot" 1
    Set-Reg $wu "ConfigureDeadlineGracePeriod" 7

    # 8 AM – 11 PM — avoid surprise restarts during typical gaming hours
    Set-Reg "$wu\ActiveHours" "ActiveHoursStart" 8
    Set-Reg "$wu\ActiveHours" "ActiveHoursEnd"   23
}

function Set-WindowsUpdate-SharedTweaks {
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"         "ExcludeWUDriversInQualityUpdate" 1
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" "SearchOrderConfig"               0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"  "DODownloadMode" 0
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" "DODownloadMode" 0
}

function Register-AppxDeprovisioned([string]$PackageFamilyName) {
    if ([string]::IsNullOrWhiteSpace($PackageFamilyName)) { return }
    $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$PackageFamilyName"
    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
        Write-Info "Deprovisioned: $PackageFamilyName"
    }
}

function Read-YesNo([string]$Prompt, [bool]$Default = $true) {
    $hint = if ($Default) { "Y/n" } else { "y/N" }
    do {
        $answer = (Read-Host "  $Prompt ($hint)").Trim()
        if ($answer -eq "") { return $Default }
        if ($answer -match '^[Yy]') { return $true }
        if ($answer -match '^[Nn]') { return $false }
        Write-Host "  Please enter Y or N." -ForegroundColor Yellow
    } while ($true)
}

function Read-SingleChoice {
    param(
        [string]$Title,
        [array]$Options   # @{ Key = "1"; Label = "Helium"; Value = "Helium" }
    )
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    foreach ($opt in $Options) {
        Write-Host "    $($opt.Key)) $($opt.Label)" -ForegroundColor Gray
    }
    $validKeys = $Options | ForEach-Object { $_.Key }
    do {
        $userInput = (Read-Host "  Enter choice").Trim()
        $selected = $Options | Where-Object { $_.Key -eq $userInput } | Select-Object -First 1
        if ($selected) { return $selected.Value }
        Write-Host "  Invalid choice. Enter one of: $($validKeys -join ', ')" -ForegroundColor Yellow
    } while ($true)
}

function Read-MultiChoice {
    param(
        [string]$Title,
        [array]$Options,
        [switch]$AllowNone
    )
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  Enter numbers separated by commas (e.g. 1,3) or press Enter to skip." -ForegroundColor DarkGray
    foreach ($opt in $Options) {
        Write-Host "    $($opt.Key)) $($opt.Label)" -ForegroundColor Gray
    }
    if ($AllowNone) {
        Write-Host "    0) None / Skip" -ForegroundColor DarkGray
    }
    do {
        $userInput = (Read-Host "  Your choices").Trim()
        if ($userInput -eq "" -or $userInput -eq "0") { return @() }

        $keys = $userInput -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $invalid = $keys | Where-Object { $_ -notin ($Options | ForEach-Object { $_.Key }) }
        if ($invalid) {
            $validList = ($Options | ForEach-Object { $_.Key }) -join ', '
            Write-Host "  Invalid: $($invalid -join ', '). Use: $validList" -ForegroundColor Yellow
            continue
        }
        return $Options | Where-Object { $_.Key -in $keys } | ForEach-Object { $_.Value }
    } while ($true)
}

function Get-BrowserProgId([string]$Browser) {
    switch ($Browser) {
        "Helium" {
            foreach ($hive in @("HKLM:\SOFTWARE\Clients\StartMenuInternet", "HKCU:\SOFTWARE\Clients\StartMenuInternet")) {
                $key = Get-ChildItem $hive -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -imatch "helium" } | Select-Object -First 1
                if ($key) {
                    $_reg = Get-ItemProperty "$($key.PSPath)\Capabilities\URLAssociations" -Name "http" -ErrorAction SilentlyContinue
                    $progId = if ($_reg) { $_reg.http } else { $null }
                    if ($progId) { return $progId }
                }
            }
            foreach ($candidate in @("HeliumHTML", "HeliumHTM", "Helium", "heliumhtml")) {
                if (Test-Path "HKCR:\$candidate") { return $candidate }
            }
        }
        "Brave" {
            foreach ($hive in @("HKLM:\SOFTWARE\Clients\StartMenuInternet", "HKCU:\SOFTWARE\Clients\StartMenuInternet")) {
                $key = Get-ChildItem $hive -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -imatch "brave" } | Select-Object -First 1
                if ($key) {
                    $_reg = Get-ItemProperty "$($key.PSPath)\Capabilities\URLAssociations" -Name "http" -ErrorAction SilentlyContinue
                    $progId = if ($_reg) { $_reg.http } else { $null }
                    if ($progId) { return $progId }
                }
            }
            foreach ($candidate in @("BraveHTML", "BraveHTM", "Brave")) {
                if (Test-Path "HKCR:\$candidate") { return $candidate }
            }
        }
        "Firefox" {
            foreach ($hive in @("HKLM:\SOFTWARE\Clients\StartMenuInternet", "HKCU:\SOFTWARE\Clients\StartMenuInternet")) {
                $key = Get-ChildItem $hive -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -imatch "firefox" } | Select-Object -First 1
                if ($key) {
                    $_reg = Get-ItemProperty "$($key.PSPath)\Capabilities\URLAssociations" -Name "http" -ErrorAction SilentlyContinue
                    $progId = if ($_reg) { $_reg.http } else { $null }
                    if ($progId) { return $progId }
                }
            }
            foreach ($candidate in @("FirefoxURL", "FirefoxURL-308046B0AF4A39CB")) {
                if (Test-Path "HKCR:\$candidate") { return $candidate }
            }
        }
    }
    return $null
}

function Set-DefaultBrowser([string]$Browser, [string]$ProgId) {
    $xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier="http"   ProgId="$ProgId" ApplicationName="$Browser"/>
  <Association Identifier="https"  ProgId="$ProgId" ApplicationName="$Browser"/>
  <Association Identifier=".html"  ProgId="$ProgId" ApplicationName="$Browser"/>
  <Association Identifier=".htm"   ProgId="$ProgId" ApplicationName="$Browser"/>
  <Association Identifier=".xhtml" ProgId="$ProgId" ApplicationName="$Browser"/>
  <Association Identifier=".svg"   ProgId="$ProgId" ApplicationName="$Browser"/>
</DefaultAssociations>
"@
    $xmlPath = "$env:SystemRoot\System32\BrowserDefaults-$Browser.xml"
    Set-Content -Path $xmlPath -Value $xmlContent -Encoding UTF8
    dism.exe /Online /Import-DefaultAppAssociations:"$xmlPath" 2>&1 | Out-Null
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DefaultAssociationsConfiguration" $xmlPath "String"

    foreach ($assoc in @("http", "https")) {
        $ucPath = "HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\$assoc\UserChoice"
        if (!(Test-Path $ucPath)) { New-Item -Path $ucPath -Force | Out-Null }
        Set-ItemProperty -Path $ucPath -Name "ProgId" -Value $ProgId -Type String -Force
    }
    foreach ($ext in @(".html", ".htm")) {
        $ucPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
        if (!(Test-Path $ucPath)) { New-Item -Path $ucPath -Force | Out-Null }
        Set-ItemProperty -Path $ucPath -Name "ProgId" -Value $ProgId -Type String -Force
    }
}

function Invoke-SteamGuideButtonConfig {
    $steamReg  = Get-ItemProperty "HKCU:\SOFTWARE\Valve\Steam" -ErrorAction SilentlyContinue
    $steamPath = $steamReg.SteamPath
    if (-not $steamPath) {
        Write-Skip "Steam registry path not found; skipping Guide button config."
        return
    }

    $configDir = Join-Path $steamPath "config"
    $configVdf = Join-Path $configDir "config.vdf"
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

    if (Test-Path $configVdf) {
        $vdf = Get-Content $configVdf -Raw
        if ($vdf -match 'guide_button_focuses_steam') {
            $vdf = $vdf -replace '"guide_button_focuses_steam"\s+"[^"]*"',
                                  '"guide_button_focuses_steam"		"0"'
            $vdf | Set-Content $configVdf -Encoding UTF8 -NoNewline
            Write-OK "Steam config.vdf patched: Guide button capture off."
        } else {
            Write-Info "Steam config.vdf exists but key not found yet — Steam will use defaults on first launch."
            Write-Info "Manually: Steam > Settings > Controller > uncheck 'Guide Button Focuses Steam'."
        }
    } else {
        @"
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"controller_options"
				{
					"guide_button_focuses_steam"		"0"
				}
			}
		}
	}
}
"@ | Set-Content $configVdf -Encoding UTF8
        Write-OK "Steam config.vdf created: Guide button will not focus Steam on first launch."
    }
}

function Disable-SteamOverlay {
    $steamReg  = Get-ItemProperty "HKCU:\SOFTWARE\Valve\Steam" -ErrorAction SilentlyContinue
    $steamPath = $steamReg.SteamPath
    if (-not $steamPath) {
        Write-Skip "Steam not found — overlay config skipped."
        return
    }

    $patched = 0
    Get-ChildItem "$steamPath\userdata" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $lc = Join-Path $_.FullName "config\localconfig.vdf"
        if (Test-Path $lc) {
            $vdf = Get-Content $lc -Raw
            if ($vdf -match '"EnableGameOverlay"\s+"[^"]*"') {
                $vdf = $vdf -replace '"EnableGameOverlay"\s+"[^"]*"', '"EnableGameOverlay"		"0"'
            } else {
                $vdf = $vdf -replace '("UserLocalConfigStore"\s*\{)', "`$1`n`t`t`"EnableGameOverlay`"`t`"0`""
            }
            $vdf | Set-Content $lc -Encoding UTF8 -NoNewline
            $patched++
        }
    }

    if ($patched -gt 0) {
        Write-OK "Steam overlay disabled ($patched user profile(s) patched)."
    } else {
        Write-Skip "No Steam user profiles found — overlay config skipped (Steam never launched)."
    }
}

# Admin check
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  [ERROR] Must run as Administrator." -ForegroundColor Red
    Write-Host "  Open PowerShell as Admin, then run:" -ForegroundColor Yellow
    Write-Host "    irm https://raw.githubusercontent.com/YavuzAkbay/win11-gaming-playbook/main/Win11-Gaming-Playbook.ps1 | iex" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ── Interactive preferences ───────────────────────────────────────────────────
Write-Section "User Preferences"

Write-Host "  Customize what gets installed. Everything else runs automatically." -ForegroundColor DarkGray

$RemoveEdge = Read-YesNo "Remove Microsoft Edge?" $true

$BrowserCatalog = @{
    Helium  = @{ WingetId = "ImputNet.Helium";      Label = "Helium — privacy focused - our recommendation" }
    Brave   = @{ WingetId = "Brave.Brave";          Label = "Brave — privacy focused - our recommendation" }
    Firefox = @{ WingetId = "Mozilla.Firefox";     Label = "Mozilla Firefox" }
}

$BrowserChoice = Read-SingleChoice "Which browser should be installed and set as default?" @(
    @{ Key = "1"; Label = $BrowserCatalog.Helium.Label;  Value = "Helium" }
    @{ Key = "2"; Label = $BrowserCatalog.Brave.Label;   Value = "Brave" }
    @{ Key = "3"; Label = $BrowserCatalog.Firefox.Label;  Value = "Firefox" }
    @{ Key = "4"; Label = "None — do not install a browser"; Value = "None" }
)

$GamingCatalog = @{
    Steam    = @{ WingetId = "Valve.Steam";                    Label = "Steam" }
    Playnite = @{ WingetId = "Playnite.Playnite";              Label = "Playnite — unified game library" }
    Epic     = @{ WingetId = "EpicGames.EpicGamesLauncher";    Label = "Epic Games Launcher" }
    GOG      = @{ WingetId = "GOG.Galaxy";                   Label = "GOG Galaxy" }
    EA       = @{ WingetId = "ElectronicArts.EADesktop";     Label = "EA App" }
}

$GamingChoices = Read-MultiChoice "Which gaming launchers should be installed?" @(
    @{ Key = "1"; Label = $GamingCatalog.Steam.Label;    Value = "Steam" }
    @{ Key = "2"; Label = $GamingCatalog.Playnite.Label; Value = "Playnite" }
    @{ Key = "3"; Label = $GamingCatalog.Epic.Label;     Value = "Epic" }
    @{ Key = "4"; Label = $GamingCatalog.GOG.Label;      Value = "GOG" }
    @{ Key = "5"; Label = $GamingCatalog.EA.Label;       Value = "EA" }
) -AllowNone

Write-Host "  NOTE: If you plan to use XboxFullscreenExperienceTool after this script," -ForegroundColor Yellow
Write-Host "        answer NO — Xbox App, Game Bar and Xbox services must stay installed." -ForegroundColor Yellow
$RemoveXbox = Read-YesNo "Remove Xbox components (apps, services, Game Bar, Game Mode)?" $false

$ConfigureController = Read-YesNo "Configure a controller frontend app?" $false
if ($ConfigureController) {
    $ControllerApp = Read-SingleChoice "Which app should handle controller input?" @(
        @{ Key = "1"; Label = "Steam — install Steam, remove Game Bar [incompatible with XboxFullscreenExperienceTool]"; Value = "Steam" }
        @{ Key = "2"; Label = "Game Bar — keep Xbox Game Bar [required for XboxFullscreenExperienceTool]"; Value = "GameBar" }
        @{ Key = "3"; Label = "Playnite — install Playnite + AutoHotkey, remove Game Bar [incompatible with XboxFullscreenExperienceTool]"; Value = "Playnite" }
    )
} else {
    $ControllerApp = $null
}

$WindowsUpdateChoice = Read-SingleChoice "Windows Update policy?" @(
    @{ Key = "1"; Label = "Recommended — notify before install, monthly patches OK, no version upgrades or driver swaps"; Value = "Recommended" }
    @{ Key = "2"; Label = "Minimal — defer all updates; you check Settings manually when ready";                         Value = "Minimal" }
    @{ Key = "3"; Label = "Off — disable Windows Update entirely (advanced / Atlas-style)";                             Value = "Off" }
)

$WindowsUpdateDisabled = $false

Write-Host ""
Write-Host "  Your choices:" -ForegroundColor Cyan
Write-Host "    Edge removal:    $(if ($RemoveEdge) { 'Yes' } else { 'No' })" -ForegroundColor Gray
Write-Host "    Browser:         $BrowserChoice" -ForegroundColor Gray
Write-Host "    Gaming apps:     $(if ($GamingChoices.Count) { $GamingChoices -join ', ' } else { 'None' })" -ForegroundColor Gray
Write-Host "    Xbox removal:    $(if ($RemoveXbox) { 'Yes — apps, services, Game Bar, Game Mode removed' } else { 'No (preserved)' })" -ForegroundColor Gray
if ($ConfigureController) {
    Write-Host "    Controller app:  $ControllerApp" -ForegroundColor Gray
}
Write-Host "    Windows Update:  $WindowsUpdateChoice" -ForegroundColor Gray
Write-Host ""

if (-not (Read-YesNo "Continue with these settings?" $true)) {
    Write-Host "  Playbook cancelled." -ForegroundColor Yellow
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
#region 01 — SAFETY: CREATE RESTORE POINT
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "01 — Safety: Restore Point"

Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
try {
    Checkpoint-Computer -Description "Pre-Debloat $(Get-Date -Format 'yyyy-MM-dd')" `
        -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
    Write-OK "Restore point created."
} catch {
    Write-Skip "Restore point skipped (may have been created recently — that's fine)."
}
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 02 — BLOATWARE REMOVAL
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "02 — Bloatware Removal"

$bloatApps = @(
    # Microsoft noise
    "Microsoft.3DBuilder"
    "Microsoft.BingNews"
    "Microsoft.BingWeather"
    "Microsoft.BingFinance"
    "Microsoft.BingSports"
    "Microsoft.BingSearch"
    "Microsoft.GetHelp"
    "Microsoft.Getstarted"
    "Microsoft.Messaging"
    "Microsoft.Microsoft3DViewer"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MixedReality.Portal"
    "Microsoft.MSPaint"         # Paint 3D (not classic Paint — classic stays)
    "Microsoft.Paint"           # New Store Paint app
    "Microsoft.StartExperiencesApp"
    "Microsoft.Windows.DevHome"
    "MicrosoftCorporationII.QuickAssist"
    "Microsoft.MicrosoftStickyNotes"
    "Microsoft.Office.OneNote"
    "Microsoft.OneConnect"
    "Microsoft.People"
    "Microsoft.Print3D"
    "Microsoft.SkypeApp"
    "Microsoft.Wallet"
    "Microsoft.WindowsAlarms"
    "Microsoft.WindowsCamera"
    "Microsoft.windowscommunicationsapps"   # Mail & Calendar
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.WindowsSoundRecorder"
    "Microsoft.YourPhone"                   # Phone Link
    "Microsoft.ZuneMusic"                   # Media Player (new)
    "Microsoft.ZuneVideo"                   # Movies & TV
    "Microsoft.Todos"
    "Microsoft.PowerAutomateDesktop"
    "Microsoft.Teams"
    "MicrosoftTeams"
    "Microsoft.OutlookForWindows"
    "Clipchamp.Clipchamp"
    "Microsoft.MicrosoftJournal"
    "Microsoft.Family"
    "Microsoft.549981C3F5F10"               # Cortana app
    "Microsoft.WindowsFeedback"
    "Microsoft.WindowsReadingList"
    "Microsoft.WindowsStore"                # Comment out if you use Store!
    # ↑ WARNING: Removing Store breaks app updates from Store.
    # If you install anything from Store (e.g. Xbox app updates), comment this line.

    # Third-party garbage pre-installed by OEMs / Microsoft
    "king.com.CandyCrushSaga"
    "king.com.CandyCrushFriends"
    "king.com.BubbleWitch3Saga"
    "king.com.FarmHeroesSaga"
    "SpotifyAB.SpotifyMusic"
    "Disney.37853D22215E"
    "TikTok.TikTok"
    "BytedancePte.Ltd.TikTok"
    "Amazon.com.Amazon"
    "Facebook.317180B0BB486"
    "Duolingo-LearnLanguagesforFree"
    "EclipseManager"
    "ActiproSoftwareLLC.562882FEEB491"
    "PandoraMediaInc.29680B314EFC2"
    "Playtika.CaesarsSlotsFreeCasino"
    "WinZipComputing.WinZipUniversal"
    "ROBLOXCORPORATION.ROBLOX"
)

# PRESERVED (do NOT add these):
# Microsoft.XboxApp, Microsoft.XboxGameOverlay, Microsoft.XboxGamingOverlay,
# Microsoft.XboxIdentityProvider, Microsoft.XboxSpeechToTextOverlay,
# Microsoft.GamingApp, Microsoft.Gaming.Services, Microsoft.DirectX

foreach ($app in $bloatApps) {
    # Installed packages
    Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
        Register-AppxDeprovisioned $_.PackageFamilyName
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        Write-Info "Removed: $app"
    }
    # Provisioned packages (prevents reinstall for new user profiles)
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "*$app*" } |
        ForEach-Object {
            Register-AppxDeprovisioned $_.DisplayName
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
}

Write-OK "Bloatware removed."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 03 — ONEDRIVE COMPLETE REMOVAL
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "03 — OneDrive Removal"

# Kill process
Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
Start-Sleep 1

# Uninstall via setup exe
$odPaths = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    "$env:SystemRoot\System32\OneDriveSetup.exe"
    "$env:LocalAppData\Microsoft\OneDrive\OneDriveSetup.exe"
)
foreach ($p in $odPaths) {
    if (Test-Path $p) {
        Start-Process $p "/uninstall" -Wait -ErrorAction SilentlyContinue
        break
    }
}

# Remove leftover folders
@(
    "$env:UserProfile\OneDrive"
    "$env:LocalAppData\Microsoft\OneDrive"
    "$env:ProgramData\Microsoft OneDrive"
    "$env:SystemDrive\OneDriveTemp"
) | ForEach-Object {
    if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
}

# Remove shell namespace entries
Remove-Item "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"           -Recurse -ErrorAction SilentlyContinue
Remove-Item "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Recurse -ErrorAction SilentlyContinue

# Policy block — prevents reinstall
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1

Write-OK "OneDrive removed."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 04 — TELEMETRY & DATA COLLECTION
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "04 — Telemetry & Data Collection"

# Telemetry level → 0 (Security — minimum allowed)
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"                     "AllowTelemetry"    0
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"      "AllowTelemetry"    0
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"      "MaxTelemetryAllowed" 0
Set-Reg "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0

# Kill & disable telemetry services
@(
    "DiagTrack"                                     # Connected User Experiences and Telemetry
    "dmwappushservice"                              # WAP Push Message Routing
    "diagnosticshub.standardcollector.service"      # Diagnostics Hub
    "WerSvc"                                        # Windows Error Reporting
    "wercplsupport"                                 # WER Control Panel Support
    "PcaSvc"                                        # Program Compatibility Assistant
) | ForEach-Object { Disable-Service $_ }

# Disable telemetry scheduled tasks
@(
    @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"}
    @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater"}
    @{Path="\Microsoft\Windows\Application Experience\"; Name="StartupAppTask"}
    @{Path="\Microsoft\Windows\Application Experience\"; Name="MareBackup"}
    @{Path="\Microsoft\Windows\Application Experience\"; Name="PcaPatchDbTask"}
    @{Path="\Microsoft\Windows\Autochk\";               Name="Proxy"}
    @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator"}
    @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip"}
    @{Path="\Microsoft\Windows\DiskDiagnostic\";        Name="Microsoft-Windows-DiskDiagnosticDataCollector"}
    @{Path="\Microsoft\Windows\Feedback\Siuf\";         Name="DmClient"}
    @{Path="\Microsoft\Windows\Feedback\Siuf\";         Name="DmClientOnScenarioDownload"}
    @{Path="\Microsoft\Windows\Windows Error Reporting\"; Name="QueueReporting"}
    @{Path="\Microsoft\Windows\Maps\";                  Name="MapsToastTask"}
    @{Path="\Microsoft\Windows\Maps\";                  Name="MapsUpdateTask"}
    @{Path="\Microsoft\Windows\NetTrace\";              Name="GatherNetworkInfo"}
    @{Path="\Microsoft\Windows\Power Efficiency Diagnostics\"; Name="AnalyzeSystem"}
    @{Path="\Microsoft\Windows\Speech\";                Name="SpeechModelDownloadTask"}
) | ForEach-Object { Disable-Task $_.Path $_.Name }

# Windows Error Reporting
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" 1
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"          "Disabled" 1

# CEIP
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"         "CEIPEnable" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\SQM"     "DisableCustomerImprovementProgram" 1

# Feedback
Set-Reg "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"                          "NumberOfSIUFInPeriod"          0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"     "DoNotShowFeedbackNotifications" 1

# Activity History / Timeline
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed"    0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities"  0

# Location
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny" "String"
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" 1

# Advertising ID
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"        "Enabled"                0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"              "DisabledByGroupPolicy"  1

# Tailored experiences
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0

# Cortana
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana"         0
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"   "CortanaEnabled"       0
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"   "BingSearchEnabled"    0
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"   "HistoryViewEnabled"   0
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"   "DeviceHistoryEnabled" 0

# Web search in Start
Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"       "DisableSearchBoxSuggestions" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch"            1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "ConnectedSearchUseWeb"       0

# Speech / online recognition
Set-Reg "HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" "HasAccepted"         0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Speech"                              "AllowSpeechModelUpdate" 0

# Handwriting & ink telemetry
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" "RestrictImplicitInkCollection"   1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" "RestrictImplicitTextCollection"  1
Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization"          "RestrictImplicitInkCollection"   1
Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization"          "RestrictImplicitTextCollection"  1
Set-Reg "HKCU:\SOFTWARE\Microsoft\Personalization\Settings"      "AcceptedPrivacyPolicy"           0

Write-OK "Telemetry disabled."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 05 — COPILOT & AI FEATURES
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "05 — Copilot & AI Features"

# Windows Copilot (all versions)
Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1

# Windows Recall (24H2 Snapdragon / AI PC feature — disable on all)
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement" 0

# Copilot taskbar button
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" 0

# AI-powered search box
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" "IsDynamicSearchBoxEnabled" 0

# Disable AI-generated content in Settings
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableContentBasedSuggestions" 1

Write-OK "Copilot & AI features disabled."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 06 — UI CLEANUP & TASKBAR
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "06 — UI Cleanup & Taskbar"

# Widgets — hide button, disable feeds, remove packages (WinUtil/Atlas aggressive)
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"                             "AllowNewsAndInterests" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"           "EnableFeeds"           0

Get-Process *Widget* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
foreach ($widgetPkg in @("Microsoft.WidgetsPlatformRuntime", "MicrosoftWindows.Client.WebExperience")) {
    Get-AppxPackage -Name $widgetPkg -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
        Register-AppxDeprovisioned $_.PackageFamilyName
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        Write-Info "Removed widget package: $($_.Name)"
    }
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "*$widgetPkg*" } |
        ForEach-Object {
            Register-AppxDeprovisioned $_.DisplayName
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
}

# Chat / Teams button off
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" 0

# Task View off (Win+Tab still works)
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0

# Search: 0=Hidden, 1=Icon only, 2=Search label, 3=Full search box
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0

# Notification Center off (WinUtil Advanced)
Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableNotificationCenter" 1

# Start Menu: disable recommendations, recently added, most used (Atlas)
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_IrisRecommendations"  0
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_AccountNotifications" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"                "HideRecommendedSection"           1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"                "HideRecommendedPersonalizedSites" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"                "HideRecentlyAddedApps"            1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"                "ShowOrHideMostUsedApps"           2
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoStartMenuMFUprogramsList"       1

# Disable Start Menu ads / sponsored apps
$cdm = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-Reg $cdm "SystemPaneSuggestionsEnabled"     0
Set-Reg $cdm "SoftLandingEnabled"               0
Set-Reg $cdm "SubscribedContent-338388Enabled"  0   # Start suggestions
Set-Reg $cdm "SubscribedContent-338389Enabled"  0   # Lock screen spotlight
Set-Reg $cdm "SubscribedContent-338393Enabled"  0
Set-Reg $cdm "SubscribedContent-353698Enabled"  0   # Timeline suggestions
Set-Reg $cdm "SubscribedContent-310093Enabled"  0
Set-Reg $cdm "RotatingLockScreenEnabled"         0
Set-Reg $cdm "RotatingLockScreenOverlayEnabled"  0
Set-Reg $cdm "ContentDeliveryAllowed"            0
Set-Reg $cdm "OemPreInstalledAppsEnabled"        0
Set-Reg $cdm "PreInstalledAppsEnabled"           0
Set-Reg $cdm "PreInstalledAppsEverEnabled"       0
Set-Reg $cdm "SilentInstalledAppsEnabled"        0   # Stops Microsoft silently installing apps!
Set-Reg $cdm "SubscribedContentEnabled"          0
Set-Reg $cdm "FeatureManagementEnabled"          0
Set-Reg $cdm "RemediationRequired"             0
Set-Reg $cdm "SubscribedContent-338387Enabled"  0   # Lock screen facts/tips
Set-Reg $cdm "SubscribedContent-353694Enabled"  0   # Settings suggested content
Set-Reg $cdm "SubscribedContent-353696Enabled"  0   # Settings suggested content

# Settings app account notifications off (Atlas)
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications" "EnableAccountNotifications" 0

# Block Store recommended search in Start menu (WinUtil Advanced)
$storeDb = "$env:LocalAppData\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db"
if (Test-Path $storeDb) {
    icacls $storeDb /deny Everyone:F 2>&1 | Out-Null
    Write-Info "Store recommended search blocked (store.db locked)."
} else {
    Write-Skip "Store not installed — skipped store.db lock."
}

# Lock screen / Spotlight cloud content
$cc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
Set-Reg $cc "DisableWindowsSpotlightFeatures" 1
Set-Reg $cc "DisableSoftLanding"              1
Set-Reg $cc "DisableThirdPartySuggestions"    1
Set-Reg $cc "DisableWindowsConsumerFeatures"  1   # Prevents auto-install of consumer apps

# Taskbar alignment: 0 = left, 1 = center (Windows 11 default)
# Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" 0

# Explorer: show file extensions & hidden files
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden"      1

# Disable "Get even more out of Windows" setup nag
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0

# Menu show delay (0ms — instant)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type String -ErrorAction SilentlyContinue

# Disable startup sound
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" "DisableStartupSound" 1

Write-OK "UI cleaned up."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 07 — SERVICE OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "07 — Service Optimization"

# NOTE: Xbox services are intentionally NOT in this list.
# Preserved: XblAuthManager, XblGameSave, XboxGipSvc, XboxNetApiSvc, GamingServices

@(
    "SysMain"               # Superfetch — hurts NVMe/SSD, remove for gaming
    "MapsBroker"            # Downloaded Maps Manager
    "lfsvc"                 # Geolocation Service
    "TrkWks"                # Distributed Link Tracking Client
    "WMPNetworkSvc"         # Windows Media Player Network Sharing
    "RemoteRegistry"        # Remote Registry — security risk
    "Fax"                   # Fax
    "RetailDemo"            # Retail Demo
    "SCPolicySvc"           # Smart Card Removal Policy
    "SCardSvr"              # Smart Card
    # NOTE: TabletInputService left at Manual (demand-start) — XboxFullscreenExperienceTool
    #       auto-simulates touch input; disabling this service breaks the gamepad keyboard.
    "icssvc"                # Mobile Hotspot
    "PhoneSvc"              # Phone Service
    "SEMgrSvc"              # NFC/Payments
    "wisvc"                 # Windows Insider Service
    "WpcMonSvc"             # Parental Controls
    "spectrum"              # Windows Perception Service (Mixed Reality)
    "perceptionsimulation"  # Windows Perception Simulation
    "HvHost"                # HV Host Service
    # NOTE: wlidsvc (Microsoft Account Sign-in Assistant) is intentionally NOT here.
    # XblAuthManager and XblGameSave depend on it — disabling it silently breaks
    # Xbox Live authentication. It is set to Manual (demand-start) below instead.
) | ForEach-Object { Disable-Service $_ }

# wlidsvc: keep alive but demand-start only (Xbox Live needs it for auth)
Set-Service "wlidsvc" -StartupType Manual -ErrorAction SilentlyContinue
Write-Info "wlidsvc set to Manual (Xbox Live auth dependency preserved)."

Write-OK "Services optimized."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 08 — WINDOWS UPDATE CONTROL
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "08 — Windows Update Control"

$auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

switch ($WindowsUpdateChoice) {
    "Recommended" {
        # Notify before download — nothing installs until the user approves
        Set-Reg $auPath "NoAutoUpdate" 0
        Set-Reg $auPath "AUOptions"    2   # 2 = Notify before download

        Set-WindowsUpdate-RebootSafety
        Set-WindowsUpdate-SharedTweaks

        # Pin to current Windows 11 release — blocks 23H2→24H2-style feature upgrades
        Set-Reg $wuPath "DisableOSUpgrade" 1
        $displayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion
        if ($displayVersion) {
            Set-Reg $wuPath "TargetReleaseVersion"     1
            Set-Reg $wuPath "TargetReleaseVersionInfo" $displayVersion "String"
            Set-Reg $wuPath "ProductVersion"           "Windows 11" "String"
            Write-Info "Feature updates blocked — pinned to $displayVersion."
        } else {
            Write-Info "Feature updates blocked (DisableOSUpgrade)."
        }

        Write-OK "Windows Update: Recommended — notify-first, monthly patches when you choose, no version upgrades."
        Write-Info "Check Settings > Windows Update when you want security/monthly patches."
    }

    "Minimal" {
        # Same manual gate as Recommended, but defer everything until you open Settings
        Set-Reg $auPath "NoAutoUpdate" 0
        Set-Reg $auPath "AUOptions"    2

        Set-WindowsUpdate-RebootSafety
        Set-WindowsUpdate-SharedTweaks

        Set-Reg $wuPath "DeferQualityUpdates"              1
        Set-Reg $wuPath "DeferQualityUpdatesPeriodInDays"  30
        Set-Reg $wuPath "DeferFeatureUpdates"              1
        Set-Reg $wuPath "DeferFeatureUpdatesPeriodInDays"  365
        Set-Reg $wuPath "ManagePreviewBuilds"              0

        Write-OK "Windows Update: Minimal — deferred, no auto-downloads, check manually when ready."
        Write-Info "Open Settings > Windows Update on your schedule; nothing will pull in the background."
    }

    "Off" {
        Set-Reg $auPath "NoAutoUpdate" 1
        foreach ($svc in @("wuauserv", "UsoSvc")) {
            Disable-Service $svc
        }
        $WindowsUpdateDisabled = $true

        Write-OK "Windows Update: Disabled (wuauserv + UsoSvc stopped)."
        Write-Info "Re-enable later: set both services to Manual/Automatic and remove NoAutoUpdate policy."
    }
}
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 09 — GAMING OPTIMIZATIONS
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "09 — Gaming Optimizations"

# ── Hardware Accelerated GPU Scheduling (HAGS) ────────────────────────────────
# Requires: GPU driver support (NVIDIA 451.48+ / AMD 20.5.1+), needs reboot
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
Write-Info "HAGS enabled (reboot required)."

# ── Game Mode ─────────────────────────────────────────────────────────────────
Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" 1
Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "AllowAutoGameMode"   1
Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "ShowStartupPanel"    0
Write-Info "Game Mode enabled."

# ── Variable Refresh Rate (Freesync / G-Sync via DWM) ────────────────────────
# We do NOT force Windows' "Variable refresh rate" / "Optimizations for windowed
# games" on. When enabled, these route presentation through the DWM compositor
# and can make borderless/windowed games feel like VSync is permanently ON —
# your in-game "VSync off" toggle then appears to do nothing. VRR is best left to
# the GPU driver (NVIDIA G-SYNC / AMD FreeSync) and your monitor's OSD instead.
# Both flags are explicitly set OFF so the playbook never surprises users.
Set-Reg "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences" "DirectXUserGlobalSettings" "VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;" "String"
Write-Info "Windows VRR/windowed optimizations left OFF (use your GPU driver/monitor for G-Sync/FreeSync)."

# ── CPU priority: foreground programs over background ─────────────────────────
# 0x26 = Foreground boost, Variable interval, Short quantum (gaming sweet spot)
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38
Write-Info "CPU priority set for foreground/gaming."

# ── Multimedia System Profile — Games ─────────────────────────────────────────
$tasks = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
Set-Reg $tasks "GPU Priority"          8
Set-Reg $tasks "Priority"             6
Set-Reg $tasks "Scheduling Category" "High" "String"
Set-Reg $tasks "SFIO Priority"       "High" "String"

# System-wide network & multimedia
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 4294967295
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness"   0

Write-Info "Gaming system profile tuned."

# ── HPET (High Precision Event Timer) disable ─────────────────────────────────
# Reducing timer resolution can lower input latency. Reboot required.
bcdedit /set useplatformclock false          2>&1 | Out-Null
bcdedit /set tscsyncpolicy enhanced         2>&1 | Out-Null
bcdedit /set disabledynamictick yes         2>&1 | Out-Null
bcdedit /set useplatformtick false          2>&1 | Out-Null
Write-Info "HPET/dynamic tick disabled (reboot required)."

# ── Ultimate Performance Power Plan ───────────────────────────────────────────
# Unhide and activate the hidden Ultimate Performance plan
$planCheck = powercfg -list 2>&1 | Select-String "Ultimate Performance"
if (-not $planCheck) {
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
}
$planLine = powercfg -list 2>&1 | Select-String "Ultimate Performance"
if ($planLine) {
    $guid = ($planLine.ToString() -split '\s+') | Where-Object { $_ -match '^[0-9a-f]{8}-' } | Select-Object -First 1
    if ($guid) {
        powercfg -setactive $guid 2>&1 | Out-Null
        Write-Info "Activated: Ultimate Performance ($guid)"
    }
} else {
    Write-Skip "Ultimate Performance plan not found — activate manually in Power Options."
}

# ── CPU Core Parking disabled ─────────────────────────────────────────────────
$corepark = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583"
Set-Reg $corepark "ValueMax" 0
Write-Info "CPU core parking disabled."

# ── Network — Disable Nagle Algorithm ────────────────────────────────────────
# Nagle batches small TCP packets — bad for real-time gaming, adds latency
$nicParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem $nicParams -ErrorAction SilentlyContinue | ForEach-Object {
    Set-Reg $_.PSPath "TcpAckFrequency" 1
    Set-Reg $_.PSPath "TCPNoDelay"      1
    Set-Reg $_.PSPath "TcpDelAckTicks"  0
}
Write-Info "Nagle algorithm disabled on all interfaces."

# NOTE: Xbox overlay policy block removed — XboxFullscreenExperienceTool requires the
# Guide button (Nexus) to trigger Game Bar / FSE. AllowGameDVR=0 and
# UseNexusForGameBarEnabled=0 would silently break FSE activation.

Write-OK "Gaming optimizations applied."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 09b — XBOX REMOVAL (OPTIONAL)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "09b — Xbox Removal"

if ($RemoveXbox) {
    # ── Xbox UWP apps ─────────────────────────────────────────────────────────
    Write-Info "Removing Xbox apps..."
    $xboxApps = @(
        "Microsoft.XboxApp"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.GamingApp"
        "Microsoft.Gaming.Services"
    )
    foreach ($app in $xboxApps) {
        Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
            Register-AppxDeprovisioned $_.PackageFamilyName
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            Write-Info "Removed: $app"
        }
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like "*$app*" } |
            ForEach-Object {
                Register-AppxDeprovisioned $_.DisplayName
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
    }

    # ── Xbox services ─────────────────────────────────────────────────────────
    Write-Info "Disabling Xbox services..."
    @("XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc", "GamingServices") | ForEach-Object {
        Disable-Service $_
    }
    # wlidsvc (Microsoft Account Sign-in) can now be fully disabled —
    # Xbox auth no longer needs it.
    Disable-Service "wlidsvc"

    # ── Game Bar / Game DVR ───────────────────────────────────────────────────
    Write-Info "Disabling Game Bar and Game DVR..."
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled"         0
    Set-Reg "HKCU:\System\GameConfigStore"                             "GameDVR_Enabled"           0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar"                         "UseNexusForGameBarEnabled" 0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar"                         "ShowStartupPanel"          0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"        "AllowGameDVR"              0
    Disable-Task "\Microsoft\XblGameSave\" "XblGameSaveTask"

    # ── Game Mode ─────────────────────────────────────────────────────────────
    Write-Info "Disabling Game Mode..."
    Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" 0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "AllowAutoGameMode"   0

    Write-OK "Xbox components removed."
} else {
    Write-Skip "Xbox removal skipped — Xbox components preserved."
}
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 10 — VISUAL PERFORMANCE
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "10 — Visual Performance"

# Best performance mode (disables most animations)
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2

# Disable transparency
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0

# Disable taskbar animations
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 0

# Disable window minimize/maximize animations
Set-Reg "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" 0

# Faster alt-tab (no thumbnail delay)
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ExtendedUIHoverTime" 1

Write-OK "Visual performance set to lean."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 11 — PRIVACY DEEP CLEAN
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "11 — Privacy Deep Clean"

$priv = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
# 0 = user-controlled, 2 = deny all apps

Set-Reg $priv "LetAppsAccessCamera"             2
Set-Reg $priv "LetAppsAccessMicrophone"         0   # user-controlled per-app (needed for gaming headsets)
Set-Reg $priv "LetAppsAccessContacts"           2
Set-Reg $priv "LetAppsAccessCalendar"           2
Set-Reg $priv "LetAppsAccessCallHistory"        2
Set-Reg $priv "LetAppsAccessMessaging"          2
Set-Reg $priv "LetAppsAccessAccountInfo"        2
Set-Reg $priv "LetAppsAccessLocation"           2
Set-Reg $priv "LetAppsAccessEmail"              2
Set-Reg $priv "LetAppsAccessPhone"              2
Set-Reg $priv "LetAppsRunInBackground"          2
Set-Reg $priv "LetAppsSyncWithDevices"          2
Set-Reg $priv "LetAppsAccessTasks"              2
Set-Reg $priv "LetAppsAccessNotifications"      2

Write-Info "All app permissions denied by policy (mic left user-controlled for gaming)."

# Maps auto-download
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps" "AutoDownloadAndUpdateMapData"           0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps" "AllowUntriggeredNetworkTrafficOnSettingsPage" 0

# Block sync of settings to cloud
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync" "DisableSettingSync"          2
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync" "DisableSettingSyncUserOverride" 1

# Disable connected experiences (Office-style phoning home)
Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\Privacy" "DisableConnectedExperiences" 1

Write-OK "Privacy locked down."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 12 — TELEMETRY IP BLOCK (hosts file)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "12 — Hosts File Telemetry Block"

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$marker    = "# WIN11-GAMING-PLAYBOOK-TELEMETRY-BLOCK"

$telemetryEntries = @"

$marker
0.0.0.0 vortex.data.microsoft.com
0.0.0.0 vortex-win.data.microsoft.com
0.0.0.0 telecommand.telemetry.microsoft.com
0.0.0.0 telecommand.telemetry.microsoft.com.nsatc.net
0.0.0.0 oca.telemetry.microsoft.com
0.0.0.0 sqm.telemetry.microsoft.com
0.0.0.0 watson.telemetry.microsoft.com
0.0.0.0 watson.microsoft.com
0.0.0.0 redir.metaservices.microsoft.com
0.0.0.0 choice.microsoft.com
0.0.0.0 choice.microsoft.com.nsatc.net
0.0.0.0 df.telemetry.microsoft.com
0.0.0.0 reports.wes.df.telemetry.microsoft.com
0.0.0.0 wes.df.telemetry.microsoft.com
0.0.0.0 sqm.df.telemetry.microsoft.com
0.0.0.0 telemetry.microsoft.com
0.0.0.0 watson.live.com
0.0.0.0 statsfe2.ws.microsoft.com
0.0.0.0 compatexchange.cloudapp.net
0.0.0.0 statsfe2.update.microsoft.com.akadns.net
0.0.0.0 sls.update.microsoft.com.akadns.net
0.0.0.0 diagnostics.support.microsoft.com
0.0.0.0 urs.microsoft.com
0.0.0.0 telemetry.appex.bing.net
0.0.0.0 telemetry.urs.microsoft.com
0.0.0.0 settings-sandbox.data.microsoft.com
0.0.0.0 vortex-sandbox.data.microsoft.com
0.0.0.0 survey.watson.microsoft.com
0.0.0.0 cy2.vortex.data.microsoft.com.akadns.net
0.0.0.0 v10.vortex-win.data.microsoft.com
0.0.0.0 feedback.microsoft-hohm.com
0.0.0.0 feedback.search.microsoft.com
0.0.0.0 feedback.windows.com
0.0.0.0 ssw.live.com
# END $marker
"@

$current = Get-Content $hostsPath -Raw -ErrorAction SilentlyContinue
if ($current -notmatch [regex]::Escape($marker)) {
    Add-Content -Path $hostsPath -Value $telemetryEntries -Encoding UTF8
    Write-OK "Telemetry hosts blocked."
} else {
    Write-Skip "Telemetry hosts already blocked — skipping."
}
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 13 — BROWSER (INTERACTIVE)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "13 — Browser Setup"

if ($RemoveEdge) {
    Get-Process -Name "msedge", "MicrosoftEdge*", "msedgewebview2" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Write-Info "Edge processes killed."

    $edgeSearchPaths = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application"
        "C:\Program Files\Microsoft\Edge\Application"
    )
    foreach ($searchDir in $edgeSearchPaths) {
        if (Test-Path $searchDir) {
            $setup = Get-ChildItem $searchDir -Recurse -Filter "setup.exe" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($setup) {
                Write-Info "Running Edge uninstaller: $($setup.FullName)"
                Start-Process $setup.FullName "--uninstall --system-level --verbose-logging --force-uninstall" -Wait -ErrorAction SilentlyContinue
            }
        }
    }

    winget uninstall --id Microsoft.Edge        --exact --silent --accept-source-agreements --force 2>&1 | Out-Null
    winget uninstall --id Microsoft.Edge.Beta   --exact --silent --accept-source-agreements --force 2>&1 | Out-Null
    winget uninstall --id Microsoft.Edge.Dev    --exact --silent --accept-source-agreements --force 2>&1 | Out-Null
    winget uninstall --id Microsoft.Edge.Canary --exact --silent --accept-source-agreements --force 2>&1 | Out-Null
    Write-Info "winget uninstall attempted."

    Get-AppxPackage -Name "*MicrosoftEdge*" -AllUsers -ErrorAction SilentlyContinue |
        ForEach-Object {
            Register-AppxDeprovisioned $_.PackageFamilyName
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    @(
        "Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe"
        "Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
    ) | ForEach-Object { Register-AppxDeprovisioned $_ }

    @(
        "$env:LocalAppData\Microsoft\Edge"
        "$env:ProgramFiles\Microsoft\Edge"
        "${env:ProgramFiles(x86)}\Microsoft\Edge"
        "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate"
        "${env:ProgramFiles(x86)}\Microsoft\EdgeCore"
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView"
        "${env:ProgramFiles(x86)}\Microsoft\Temp"
    ) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
            Write-Info "Removed: $_"
        }
    }

    @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
        "HKCU:\SOFTWARE\Microsoft\Edge"
    ) | ForEach-Object { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }

    Set-Reg "HKLM:\SOFTWARE\Microsoft\EdgeUpdate"        "DoNotUpdateToEdgeWithChromium" 1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "InstallDefault"              0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "UpdateDefault"               0

    Disable-Task "\Microsoft\MicrosoftEdge\"    "MicrosoftEdgeUpdateTaskMachineCore"
    Disable-Task "\Microsoft\MicrosoftEdge\"    "MicrosoftEdgeUpdateTaskMachineUA"
    Disable-Task "\Microsoft\MicrosoftEdgeUpdate\" "MicrosoftEdgeUpdateTaskMachineCore"
    Disable-Task "\Microsoft\MicrosoftEdgeUpdate\" "MicrosoftEdgeUpdateTaskMachineUA"

    Write-OK "Edge removed."
} else {
    Write-Skip "Edge removal skipped (your choice)."
}

if ($BrowserChoice -ne "None") {
    $browserInfo = $BrowserCatalog[$BrowserChoice]
    Write-Info "Installing $($browserInfo.Label)..."

    $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetAvailable) {
        winget install --id $browserInfo.WingetId --exact --silent `
            --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        Write-OK "$BrowserChoice installed."
    } else {
        Write-Host "  [!] winget not found. Install $BrowserChoice manually." -ForegroundColor Yellow
    }

    $maxWait = 30
    $waited  = 0
    $browserProgId = $null
    while (-not $browserProgId -and $waited -lt $maxWait) {
        Start-Sleep 2
        $waited += 2
        $browserProgId = Get-BrowserProgId $BrowserChoice
    }

    if ($browserProgId) {
        Write-Info "Detected $BrowserChoice ProgID: $browserProgId"
        Set-DefaultBrowser $BrowserChoice $browserProgId
        Write-OK "$BrowserChoice set as default browser (DISM + policy + UserChoice)."
        Write-Info "On first reboot: open $BrowserChoice and confirm 'Set as default' if prompted."
    } else {
        Write-Host "  [!] $BrowserChoice ProgID not detected yet — it registers on first launch." -ForegroundColor Yellow
        Write-Info "After reboot: open $BrowserChoice and set it as default in Windows Settings."
    }
} else {
    Write-Skip "Browser install skipped (your choice)."
}
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 14 — MEMORY & I/O TWEAKS
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "14 — Memory & I/O Tweaks"

$mem = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"

# Keep kernel/drivers in RAM, don't page them out.
# Only safe on 16GB+ — on lower RAM it competes with game memory and can destabilise.
$totalRamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
if ($totalRamGB -ge 16) {
    Set-Reg $mem "DisablePagingExecutive" 1
    Write-Info "Kernel paging disabled (${totalRamGB}GB RAM detected — safe)."
} else {
    Write-Skip "DisablePagingExecutive skipped — only ${totalRamGB}GB RAM, would compete with game memory."
}

# Large system cache: 0 = optimize for programs (not file cache) — better for gaming
Set-Reg $mem "LargeSystemCache" 0

# Disable Prefetch/Superfetch — redundant on NVMe, causes random disk activity
Set-Reg "$mem\PrefetchParameters" "EnablePrefetcher"  0
Set-Reg "$mem\PrefetchParameters" "EnableSuperfetch"  0

# NVMe link power management — disable for lower latency
# (safe on desktop, may affect laptop battery life)
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" `
    "IdlePowerManagement" 0

# ClearPageFileAtShutdown — disable (speeds up shutdown)
Set-Reg $mem "ClearPageFileAtShutdown" 0

# Heap decommit threshold (slight RAM usage optimization)
Set-Reg $mem "HeapDeCommitFreeBlockThreshold" 262144

# Storage Sense off (WinUtil Advanced)
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "01" 0
Write-Info "Storage Sense disabled."

# Reserved storage off — frees ~7GB for updates (Atlas)
dism.exe /Online /Set-ReservedStorageState /State:Disabled 2>&1 | Out-Null
Write-Info "Reserved storage disabled."

Write-OK "Memory & I/O tweaked."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 15 — EXTENDED TWEAKS (WinUtil-validated)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "15 — Extended Tweaks"

# ── Mouse Acceleration — DISABLE ─────────────────────────────────────────────
# The single most important input tweak for gaming. Ensures 1:1 raw cursor
# movement with no OS-level acceleration curve on top of your mouse's hardware.
Set-Reg "HKCU:\Control Panel\Mouse" "MouseSpeed"      0
Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold1" 0
Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold2" 0
Write-Info "Mouse acceleration disabled."

# ── Fullscreen Optimizations (FSO) — DISABLE ─────────────────────────────────
# By default Win11 overrides exclusive fullscreen with a DWM hybrid mode.
# Disabling forces true exclusive fullscreen → lower input latency, more FPS.
# Trade-off: disables OS-level color management in exclusive fullscreen.
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" 1
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode"               2
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior"                   2
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode"      1
Write-Info "Fullscreen Optimizations disabled (true exclusive fullscreen enabled)."

# ── Multiplane Overlay (MPO) — LEFT ENABLED BY DEFAULT ───────────────────────
# Older guides disabled MPO (OverlayTestMode=5) to fix flickering / black
# screens / micro-stutter on some (mostly NVIDIA) GPUs. BUT disabling MPO forces
# ALL rendering through the DWM compositor, which makes borderless/windowed games
# behave as if VSync is permanently ON — the in-game "VSync off" setting appears
# to do nothing. Recent GPU drivers have fixed the original MPO bugs, so MPO is
# LEFT ENABLED here to avoid that forced-VSync feel.
#
# Actively remove a leftover OverlayTestMode value so re-running this playbook
# self-heals machines that disabled MPO with an earlier version. (Takes effect
# after a reboot.) Only uncomment the Set-Reg line below if you STILL get
# MPO-related flicker/stutter AND accept the forced-VSync side effect in
# windowed/borderless games:
# Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" 5
Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -ErrorAction SilentlyContinue
Write-Info "Multiplane Overlay (MPO) left enabled (prevents forced-VSync feel in windowed/borderless games; reboot to apply)."

# ── Teredo & IPv4 Preferred ───────────────────────────────────────────────────
# Teredo = IPv6 tunneling over IPv4, adds overhead and latency.
# DisabledComponents: 0x01 = disable Teredo | 0x20 = prefer IPv4 → 0x21 = 33
netsh interface teredo set state disabled 2>&1 | Out-Null
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" 33
Write-Info "Teredo disabled, IPv4 preferred over IPv6."

# ── SMB Client — NAS compatibility ───────────────────────────────────────────
# Allows connecting to NAS devices that don't enforce SMB signing or require
# guest logons (common on Synology, QNAP, TrueNAS without strict security).
Set-SmbClientConfiguration -RequireSecuritySignature $false -Force
Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force
Write-Info "SMB client configured for NAS compatibility (guest + no mandatory signing)."

# ── Windows Platform Binary Table (WPBT) — DISABLE ───────────────────────────
# WPBT lets OEM/motherboard vendors silently execute code at every boot —
# used by anti-theft software and OEM bloatware injectors. No place here.
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "DisableWpbtExecution" 1
Write-Info "WPBT (OEM boot-time execution) disabled."

# ── Hibernation — DISABLE ─────────────────────────────────────────────────────
# hiberfil.sys = your RAM size in GB wasted on disk. Pointless on a desktop.
powercfg /hibernate off 2>&1 | Out-Null
Set-Reg "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" "HibernateEnabled" 0
Write-Info "Hibernation disabled (hiberfil.sys deleted, disk space reclaimed)."

# ── SvcHostSplitThreshold — match to installed RAM ────────────────────────────
# Windows spawns one svchost.exe per service by default (dozens of processes).
# Setting this threshold to your RAM amount consolidates them, reducing
# idle CPU/RAM overhead significantly.
$ramKB = [int]((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Value $ramKB -Type DWord -Force
Write-Info "SvcHostSplitThreshold set to ${ramKB}KB (RAM-matched, fewer svchost processes)."

# ── Offline Files (CscService) — DISABLE ─────────────────────────────────────
Disable-Service "CscService"   # Offline Files — not needed on a gaming machine

# ── File Explorer — open to This PC, remove Home & Gallery ───────────────────
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" -Force -ErrorAction SilentlyContinue  # Home
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" -Force -ErrorAction SilentlyContinue  # Gallery
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1
Write-Info "Explorer opens to This PC (Home/Gallery removed from sidebar)."

# ── Explorer auto folder discovery — DISABLE (WinUtil Standard) ───────────────
# Stops Explorer guessing folder types (slows browsing). Sign-out/reboot for full effect.
$bags    = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"
$bagMRU  = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
$allFolders = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"
Remove-Item -Path $bags -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction SilentlyContinue
if (!(Test-Path $allFolders)) { New-Item -Path $allFolders -Force | Out-Null }
Set-ItemProperty -Path $allFolders -Name "FolderType" -Value "NotSpecified" -Type String -Force
Write-Info "Explorer auto folder discovery disabled."

# ── End Task via Taskbar Right-Click ─────────────────────────────────────────
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" 1
Write-Info "End Task enabled in taskbar right-click menu."

# ── Sticky Keys / Filter Keys / Toggle Keys — DISABLE ────────────────────────
# Prevents Shift×5, CapsLock, and NumLock accessibility popups from
# interrupting gameplay at the worst possible moment.
Set-Reg "HKCU:\Control Panel\Accessibility\StickyKeys"        "Flags" "506" "String"
Set-Reg "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "122" "String"
Set-Reg "HKCU:\Control Panel\Accessibility\ToggleKeys"        "Flags" "58"  "String"
Write-Info "Sticky/Filter/Toggle Keys disabled."

# ── Num Lock on by default ────────────────────────────────────────────────────
Set-Reg "HKCU:\Control Panel\Keyboard" "InitialKeyboardIndicators" 2
Write-Info "Num Lock enabled on startup."

# ── Classic Right-Click Context Menu (Win10 style) ────────────────────────────
# Win11's new right-click hides most options behind "Show more options."
# This restores the full menu immediately.
if (!(Test-Path "HKCU:\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32")) {
    New-Item -Path "HKCU:\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type String -Force
Write-Info "Classic right-click context menu restored."

# ── Temp Files Cleanup ────────────────────────────────────────────────────────
Write-Info "Cleaning temp files..."
@($env:TEMP, $env:TMP, "C:\Windows\Temp", "C:\Windows\Prefetch") | ForEach-Object {
    if (Test-Path $_) {
        Get-ChildItem -Path $_ -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Info "Temp files cleaned."

# ── RunOnce cleanup ───────────────────────────────────────────────────────────
# Clear stale OEM/pre-install RunOnce entries BEFORE runtime installations below.
# Running this after §17 would risk erasing legitimate post-install entries
# written by the runtime installers (XNA 4.0, DirectX, VC++, etc.).
$runOnceKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"
)
foreach ($key in $runOnceKeys) {
    if (Test-Path $key) {
        $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($props) {
            $props.PSObject.Properties |
                Where-Object { $_.Name -notlike 'PS*' } |
                ForEach-Object {
                    Remove-ItemProperty $key -Name $_.Name -ErrorAction SilentlyContinue
                    Write-Info "Cleared RunOnce: $($_.Name)"
                }
        }
    }
}
Write-Info "RunOnce entries cleared (pre-runtime, safe)."

Write-OK "Extended tweaks applied."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 16 — POWER & PERFORMANCE
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "16 — Power & Performance"

# ── Verify Ultimate Performance plan is active ────────────────────────────────
$activePlanLine = powercfg -getactivescheme 2>&1 | Out-String
$activePlanGUID = if ($activePlanLine -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
    $Matches[1]
} else { $null }

if (-not $activePlanGUID) {
    # Fallback: re-create Ultimate Performance plan and activate it
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
    $activePlanGUID = (powercfg -list 2>&1 | Select-String "Ultimate Performance" |
        ForEach-Object { ($_ -split '\s+') | Where-Object { $_ -match '^[0-9a-f]{8}-' } } |
        Select-Object -First 1)
    if ($activePlanGUID) { powercfg -setactive $activePlanGUID 2>&1 | Out-Null }
}

Write-Info "Active power plan GUID: $activePlanGUID"

# Helper: set one AC value in the active plan
function Set-PwrAC([string]$Sub, [string]$Setting, [int]$Value) {
    powercfg /setacvalueindex $activePlanGUID $Sub $Setting $Value 2>&1 | Out-Null
}

# ── Hard Disk: never spin down ────────────────────────────────────────────────
Set-PwrAC "0012ee47-9041-4b5d-9b77-535fba8b1442" `
           "6738e2c4-e8a5-4a42-b16a-e040e769756e" 0
Write-Info "Hard disk: never turn off."

# ── Sleep: fully disabled ─────────────────────────────────────────────────────
Set-PwrAC "238c9fa8-0aad-41ed-83f4-97be242c8f20" "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" 0   # Sleep after  = never
Set-PwrAC "238c9fa8-0aad-41ed-83f4-97be242c8f20" "9d7815a6-7ee4-497e-8888-515a05f02364" 0   # Hibernate after = never
Set-PwrAC "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94ac6d29-73ce-41a6-809f-6363ba21b47e" 0   # Hybrid sleep = off
Set-PwrAC "238c9fa8-0aad-41ed-83f4-97be242c8f20" "bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d" 0   # Wake timers = disable
powercfg -change -standby-timeout-ac  0 2>&1 | Out-Null
powercfg -change -hibernate-timeout-ac 0 2>&1 | Out-Null
Write-Info "Sleep/hibernate: fully disabled."

# ── Display: never time out ───────────────────────────────────────────────────
Set-PwrAC "7516b95f-f776-4464-8c53-06167f40cc99" "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" 0
powercfg -change -monitor-timeout-ac 0 2>&1 | Out-Null
Write-Info "Display timeout: never."

# ── Hard disk timeout (belt & suspenders) ────────────────────────────────────
powercfg -change -disk-timeout-ac 0 2>&1 | Out-Null

# ── USB Selective Suspend: OFF ────────────────────────────────────────────────
# Prevents USB peripherals (controllers, headsets, hubs) from being
# power-cycled mid-game, which causes brief input drops and audio pops.
Set-PwrAC "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 0
Write-Info "USB selective suspend: disabled."

# ── PCI Express Link State Power Management: OFF ──────────────────────────────
# Keeps PCIe lanes (GPU, NVMe, capture cards) always at full power.
# Eliminates the micro-stutter caused by ASPM link transitions.
Set-PwrAC "501a4d13-42af-4429-9fd1-a8218c268e20" "ee12f906-d277-404b-b6da-e5fa1a576df5" 0
Write-Info "PCI Express ASPM: off (GPU/NVMe always at full power)."

# ── Processor: maximum clock at all times ─────────────────────────────────────
# Min 100% = CPU never downclocks, guaranteed instant response to game load.
# Max 100% = no artificial ceiling.
# Boost mode 2 = Aggressive Turbo.
# Boost policy 100 = always favour performance when scheduling.
Set-PwrAC "54533251-82be-4824-96c1-47b60b740d00" "893dee8e-2bef-41e0-89c6-b55d0929964c" 100  # Min processor state
Set-PwrAC "54533251-82be-4824-96c1-47b60b740d00" "bc5038f7-23e0-4960-96da-33abaf5935ec" 100  # Max processor state
Set-PwrAC "54533251-82be-4824-96c1-47b60b740d00" "be337238-0d82-4146-a960-4f3749d470c7" 2    # Boost mode: Aggressive
Set-PwrAC "54533251-82be-4824-96c1-47b60b740d00" "45bcc044-d885-43e2-8605-ee0ec6e96b59" 100  # Boost policy: max
Write-Info "Processor: min/max 100%, Turbo set to Aggressive."

# ── Wireless Adapter: maximum performance ────────────────────────────────────
Set-PwrAC "19caa586-fa4c-4e73-7c76-7f08df96fc5d" "12bbebe6-58d6-4636-95bb-3217ef867c1a" 0
Write-Info "Wireless adapter: maximum performance."

# ── Apply all power plan changes ──────────────────────────────────────────────
if ($activePlanGUID) { powercfg /setactive $activePlanGUID 2>&1 | Out-Null }

# ── Fast Startup: DISABLE ─────────────────────────────────────────────────────
# Fast Startup = partial hibernate on shutdown. Causes stale driver states,
# prevents Windows Update from completing, and breaks dual-boot.
# A clean full shutdown is always better on a gaming desktop.
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0
Write-Info "Fast Startup disabled (full clean shutdown restored)."

# ── High-Resolution System Timer (0.5ms) ─────────────────────────────────────
# Windows 11 defaults to 15.6ms timer resolution. Lowering to 0.5ms improves
# frame pacing and scheduler precision. Enabled system-wide via registry
# (Win11 22H2+ also honours per-process requests from games automatically).
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" 1
# Persist via boot flag (bcdedit)
bcdedit /set tscsyncpolicy enhanced 2>&1 | Out-Null   # already set in Section 09, idempotent
Write-Info "Global 0.5ms timer resolution requests: enabled."

# ── Interrupt affinity & DPC latency ─────────────────────────────────────────
# Disable Power Throttling — Win11 throttles background process performance.
# Off = all processes get equal scheduler treatment, no silent throttling.
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
Write-Info "Power Throttling: disabled."

# ── NIC / Ethernet power saving off ──────────────────────────────────────────
# Disable Energy Efficient Ethernet (EEE) and wake-on-LAN power features
# on all physical network adapters via registry (driver-level setting).
$nicAdvPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
Get-ChildItem $nicAdvPath -ErrorAction SilentlyContinue |
    Where-Object { (Get-ItemProperty $_.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue)."DriverDesc" -notmatch "WAN|VPN|Hyper|Loop|Virtual" } |
    ForEach-Object {
        # Energy Efficient Ethernet: disable
        Set-ItemProperty $_.PSPath -Name "EEE"               -Value 0 -ErrorAction SilentlyContinue
        # Green Ethernet: disable
        Set-ItemProperty $_.PSPath -Name "GreenEthernet"     -Value 0 -ErrorAction SilentlyContinue
        # Power saving mode: off
        Set-ItemProperty $_.PSPath -Name "PowerSavingMode"   -Value 0 -ErrorAction SilentlyContinue
        # Enable PME (wake-on-LAN events that consume power): disable
        Set-ItemProperty $_.PSPath -Name "EnablePME"         -Value 0 -ErrorAction SilentlyContinue
        # Advanced EEE
        Set-ItemProperty $_.PSPath -Name "AdvancedEEE"       -Value 0 -ErrorAction SilentlyContinue
    }
Write-Info "NIC power saving features disabled."

Write-OK "Power fully set to maximum performance."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 17 — GAMING RUNTIMES & REDISTRIBUTABLES
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "17 — Gaming Runtimes & Redistributables"

# Requires internet. Every package below is needed by at least one popular game.
# winget errors are suppressed — already-installed packages just skip silently.

function Install-Pkg([string]$Id, [string]$Label) {
    $check = winget list --id $Id --exact --accept-source-agreements 2>&1 | Out-String
    if ($check -match [regex]::Escape($Id)) {
        Write-Skip "$Label already installed — skipped."
        return
    }
    Write-Info "Installing $Label..."
    winget install --id $Id --exact --silent `
        --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
}

function Get-Runtime([string]$Url, [string]$OutFile) {
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# ── Visual C++ Redistributables — ALL versions ────────────────────────────────
# Games require whichever version they were compiled against. Install all = zero
# "MSVCP140.dll not found" / "VCRUNTIME140.dll missing" errors on first launch.
Write-Host "  Installing Visual C++ Redistributables..." -ForegroundColor Gray

$vcRedists = @(
    @{ Id = "Microsoft.VCRedist.2005.x64";  Label = "VC++ 2005 x64" }
    @{ Id = "Microsoft.VCRedist.2005.x86";  Label = "VC++ 2005 x86" }
    @{ Id = "Microsoft.VCRedist.2008.x64";  Label = "VC++ 2008 x64" }
    @{ Id = "Microsoft.VCRedist.2008.x86";  Label = "VC++ 2008 x86" }
    @{ Id = "Microsoft.VCRedist.2010.x64";  Label = "VC++ 2010 x64" }
    @{ Id = "Microsoft.VCRedist.2010.x86";  Label = "VC++ 2010 x86" }
    @{ Id = "Microsoft.VCRedist.2012.x64";  Label = "VC++ 2012 x64" }
    @{ Id = "Microsoft.VCRedist.2012.x86";  Label = "VC++ 2012 x86" }
    @{ Id = "Microsoft.VCRedist.2013.x64";  Label = "VC++ 2013 x64" }
    @{ Id = "Microsoft.VCRedist.2013.x86";  Label = "VC++ 2013 x86" }
    # 2015/2017/2019/2022 all share the same runtime — this one covers all four
    @{ Id = "Microsoft.VCRedist.2015+.x64"; Label = "VC++ 2015-2022 x64 (covers 2015/17/19/22)" }
    @{ Id = "Microsoft.VCRedist.2015+.x86"; Label = "VC++ 2015-2022 x86 (covers 2015/17/19/22)" }
)

foreach ($vc in $vcRedists) { Install-Pkg $vc.Id $vc.Label }
Write-OK "Visual C++ Redistributables done."

# ── .NET Framework 3.5 (includes 2.0 + 3.0) ──────────────────────────────────
# Required by Unity games, older Source Engine titles, and many indie games.
# It's a Windows Optional Feature — no external download needed.
Write-Info "Enabling .NET Framework 3.5 (includes 2.0, 3.0)..."
$netfx35 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3" -ErrorAction SilentlyContinue
if ($netfx35 -and $netfx35.State -ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
    Write-OK ".NET Framework 3.5 enabled."
} else {
    Write-Skip ".NET Framework 3.5 already enabled."
}

# ── .NET Desktop Runtimes (modern) ───────────────────────────────────────────
# Each major version is independent — games target a specific one.
# Install all to guarantee compatibility regardless of which engine was used.
# .NET 8 = current LTS | .NET 9 = current STS | 6 & 7 for legacy Unity titles
Write-Host "  Installing .NET Desktop Runtimes..." -ForegroundColor Gray

$dotnetRuntimes = @(
    @{ Id = "Microsoft.DotNet.DesktopRuntime.6";  Label = ".NET 6 Desktop Runtime (legacy Unity)" }
    @{ Id = "Microsoft.DotNet.DesktopRuntime.7";  Label = ".NET 7 Desktop Runtime" }
    @{ Id = "Microsoft.DotNet.DesktopRuntime.8";  Label = ".NET 8 Desktop Runtime (LTS)" }
    @{ Id = "Microsoft.DotNet.DesktopRuntime.9";  Label = ".NET 9 Desktop Runtime (current)" }
)

foreach ($rt in $dotnetRuntimes) { Install-Pkg $rt.Id $rt.Label }
Write-OK ".NET Desktop Runtimes done."

# ── DirectX End-User Runtime (June 2010) ─────────────────────────────────────
# DirectX 12 is built into Windows 11 already.
# This installs the LEGACY D3DX components that DX12 does NOT include:
#   D3DX9, D3DX10, D3DX11, XAudio 2.7, X3DAudio, XInput 1.1-1.3, XACT.
# Without this, thousands of games from 2004–2014 won't even launch.
if (Test-Path "$env:SystemRoot\System32\d3dx9_43.dll") {
    Write-Skip "DirectX End-User Runtime (June 2010) already installed — skipped."
} else {
    Write-Info "Downloading DirectX End-User Runtime (June 2010, ~100 MB)..."

    $dxDir  = "$env:TEMP\DX_June2010"
    $dxSfx  = "$dxDir\dx_redist.exe"
    $dxExe  = "$dxDir\DXSETUP.exe"
    New-Item -ItemType Directory -Path $dxDir -Force | Out-Null

    if (!(Test-Path $dxExe)) {
        $dxUrl = "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe"
        $ok = Get-Runtime $dxUrl $dxSfx
        if ($ok) {
            # Self-extracting cabinet — /T specifies output dir, /Q is quiet
            Start-Process $dxSfx -ArgumentList "/T:`"$dxDir`" /Q" -Wait -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $dxExe) {
        Write-Info "Running DXSETUP silently..."
        Start-Process $dxExe -ArgumentList "/silent" -Wait -ErrorAction SilentlyContinue
        Write-OK "DirectX End-User Runtime installed (D3DX9/10/11, XAudio 2.7, XInput)."
    } else {
        Write-Host "  [!] DirectX download failed — install manually:" -ForegroundColor Yellow
        Write-Host "      https://www.microsoft.com/en-us/download/details.aspx?id=8109" -ForegroundColor DarkGray
    }
}

# ── DirectPlay (Windows Feature) ─────────────────────────────────────────────
# Required by classic LAN/IPX multiplayer games:
# Age of Empires II (original), Diablo II, StarCraft, Red Alert 2, etc.
$directPlay = Get-WindowsOptionalFeature -Online -FeatureName "DirectPlay" -ErrorAction SilentlyContinue
if ($directPlay -and $directPlay.State -ne "Enabled") {
    Write-Info "Enabling DirectPlay..."
    Enable-WindowsOptionalFeature -Online -FeatureName "DirectPlay" -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
    Write-OK "DirectPlay enabled."
} else {
    Write-Skip "DirectPlay already enabled."
}

# ── XNA Framework 4.0 Redistributable ────────────────────────────────────────
# Required for games built on Microsoft XNA:
# Stardew Valley (pre-1.6), FEZ, Terraria (old builds), many XBLA ports, etc.
# Stardew Valley 1.6+ moved to MonoGame, but the XNA runtime is still needed
# for the thousands of other XNA titles on Steam.
$xnaInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
                    -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "*XNA Framework*4.0*" } |
                    Select-Object -First 1
if ($xnaInstalled) {
    Write-Skip "XNA Framework 4.0 already installed — skipped."
} else {
    Write-Info "Downloading XNA Framework 4.0..."
    $xnaPath = "$env:TEMP\xnafx40_redist.msi"
    $xnaUrl  = "https://download.microsoft.com/download/A/C/2/AC2C903B-E6E8-42C2-9FD7-BEBAC362A930/xnafx40_redist.msi"
    $ok = Get-Runtime $xnaUrl $xnaPath
    if ($ok -and (Test-Path $xnaPath)) {
        Start-Process msiexec.exe -ArgumentList "/i `"$xnaPath`" /quiet /norestart" -Wait -ErrorAction SilentlyContinue
        Write-OK "XNA Framework 4.0 installed."
    } else {
        Write-Host "  [!] XNA download failed — some indie games may not launch." -ForegroundColor Yellow
    }
}

# ── OpenAL Soft ───────────────────────────────────────────────────────────────
# OpenAL is a 3D audio API used by many games for positional sound.
# OpenAL Soft is the open-source, actively maintained implementation.
# (Note: most modern games ship their own OpenAL32.dll, but some rely on a
# system-level install — having this prevents audio failures in those titles.)
if (Test-Path "$env:SystemRoot\System32\OpenAL32.dll") {
    Write-Skip "OpenAL already installed — skipped."
} else {
    Write-Info "Installing OpenAL Soft..."
    $oalUrl  = "https://github.com/kcat/openal-soft/releases/download/1.23.1/openal-soft-1.23.1-bin.zip"
    $oalZip  = "$env:TEMP\openal-soft.zip"
    $oalDir  = "$env:TEMP\openal-soft"
    $ok = Get-Runtime $oalUrl $oalZip
    if ($ok) {
        Expand-Archive -Path $oalZip -DestinationPath $oalDir -Force -ErrorAction SilentlyContinue
        # Run the Win64 installer (router.exe copies OpenAL32.dll to system32)
        $oalInstaller = Get-ChildItem $oalDir -Recurse -Filter "oalinst.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($oalInstaller) {
            Start-Process $oalInstaller.FullName -ArgumentList "/S" -Wait -ErrorAction SilentlyContinue
            Write-OK "OpenAL Soft installed."
        } else {
            # Fallback: manually copy the DLL to System32
            $oalDll = Get-ChildItem $oalDir -Recurse -Filter "OpenAL32.dll" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "Win64" } | Select-Object -First 1
            if ($oalDll) {
                Copy-Item $oalDll.FullName "$env:SystemRoot\System32\OpenAL32.dll" -Force -ErrorAction SilentlyContinue
                Write-OK "OpenAL32.dll copied to System32."
            } else {
                Write-Skip "OpenAL install skipped — games that ship their own DLL are unaffected."
            }
        }
    } else {
        Write-Skip "OpenAL download failed — most games bundle their own OpenAL32.dll anyway."
    }
}

# ── WebView2 Runtime ──────────────────────────────────────────────────────────
# Used by: Epic Games Launcher, EA App, Xbox App, GOG Galaxy, and many
# modern launchers that embed a browser for their store/overlay UI.
Install-Pkg "Microsoft.EdgeWebView2Runtime" "WebView2 Runtime"
Write-OK "WebView2 Runtime installed."

# ── NVIDIA PhysX System Software ─────────────────────────────────────────────
# CPU-based PhysX for games that predate GPU PhysX:
# Batman: Arkham series, Borderlands 1/2, Mirror's Edge, Mafia II, etc.
# Even on AMD setups, the CPU PhysX driver makes these games stable.
Install-Pkg "Nvidia.PhysX" "NVIDIA PhysX System Software"
Write-OK "PhysX System Software installed."

# ── Gaming launchers (interactive — chosen at start) ──────────────────────────
if ($GamingChoices.Count -gt 0) {
    Write-Host "  Installing selected gaming launchers..." -ForegroundColor Gray
    foreach ($app in $GamingChoices) {
        $appInfo = $GamingCatalog[$app]
        Install-Pkg $appInfo.WingetId $appInfo.Label
        Write-OK "$app installed."
    }

    if ($GamingChoices -contains "Steam") {
        if ($ControllerApp -ne "Steam") {
            Write-Info "Configuring Steam Guide button (controller-friendly)..."
            Invoke-SteamGuideButtonConfig
        }
    }
} else {
    Write-Skip "No gaming launchers selected — skipped."
}

# ── Cleanup temp download files ───────────────────────────────────────────────
Remove-Item "$env:TEMP\DX_June2010" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\openal-soft*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\xnafx40_redist.msi" -Force -ErrorAction SilentlyContinue

Write-OK "All gaming runtimes & redistributables installed."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 17b — CONTROLLER APP
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "17b — Controller App"

if (-not $ConfigureController) {
    Write-Skip "Controller configuration skipped."
} else {
    switch ($ControllerApp) {

        "Steam" {
            Install-Pkg "Valve.Steam" "Steam"
            Write-OK "Steam installed."

            Write-Info "Removing Game Bar..."
            Get-AppxPackage -Name "Microsoft.XboxGamingOverlay" -AllUsers -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageName -like "*XboxGamingOverlay*" } |
                ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
            Write-OK "Game Bar removed. Steam is the controller frontend."
        }

        "GameBar" {
            Write-Info "Disabling Steam Big Picture guide button capture..."
            Invoke-SteamGuideButtonConfig
            Write-OK "Game Bar is the controller frontend."
        }

        "Playnite" {
            Write-Info "Disabling Steam overlay..."
            Disable-SteamOverlay

            Write-Info "Removing Game Bar..."
            Get-AppxPackage -Name "Microsoft.XboxGamingOverlay" -AllUsers -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageName -like "*XboxGamingOverlay*" } |
                ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
            Write-OK "Game Bar removed."

            Install-Pkg "Playnite.Playnite" "Playnite"
            Write-OK "Playnite installed."

            Install-Pkg "AutoHotkey.AutoHotkey" "AutoHotkey v2"

            $ahkDir    = "$env:LOCALAPPDATA\Playnite"
            $ahkScript = "$ahkDir\guide-button.ahk"
            New-Item -ItemType Directory -Path $ahkDir -Force | Out-Null

            Set-Content -Path $ahkScript -Encoding UTF8 -Value @'
#Requires AutoHotkey v2.0
#SingleInstance Force
A_IconTip := "Playnite Guide Button"

VK07::
{
    if !ProcessExist("Playnite.FullscreenApp.exe")
        Run EnvGet("LOCALAPPDATA") "\Playnite\Playnite.FullscreenApp.exe"
    else {
        WinShow "ahk_exe Playnite.FullscreenApp.exe"
        WinActivate "ahk_exe Playnite.FullscreenApp.exe"
    }
}
'@
            Write-OK "Guide button script written."

            # Resolve AHK v2 executable (winget installs to Program Files\AutoHotkey\v2)
            $ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
            if (-not (Test-Path $ahkExe)) { $ahkExe = "C:\Program Files\AutoHotkey\AutoHotkey64.exe" }

            $startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
            $lnkPath    = "$startupDir\Playnite Guide Button.lnk"
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut($lnkPath)
            $lnk.TargetPath       = $ahkExe
            $lnk.Arguments        = "`"$ahkScript`""
            $lnk.WorkingDirectory = $ahkDir
            $lnk.WindowStyle      = 7   # minimised / hidden
            $lnk.Description      = "Playnite Guide Button handler"
            $lnk.Save()
            Write-OK "Guide button handler added to startup."

            Write-Info "Disabling Steam guide button capture..."
            Invoke-SteamGuideButtonConfig

            Write-OK "Playnite is the controller frontend. Guide button launches Playnite fullscreen (via AutoHotkey XInput)."
        }
    }
}
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 18 — WINDOWS DEFENDER
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "18 — Windows Defender"

Write-Host ""
$defChoice = Read-Host "  Do you want to disable antivirus? (Y/N)"

if ($defChoice.Trim() -match '^[Yy]') {
    Write-Info "Adding exclusions for all drives..."
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
    foreach ($drive in $drives) {
        $root = $drive.RootDirectory.FullName
        Add-MpPreference -ExclusionPath $root -ErrorAction SilentlyContinue
        Write-OK "Excluded: $root"
    }
    Write-OK "Done."
} else {
    Write-Skip "Antivirus untouched."
}

#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 19 — STARTUP OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "19 — Startup Optimization"

# Helper: disable a startup entry via StartupApproved (same mechanism as
# Task Manager > Startup tab — entry stays, just doesn't run at boot)
function Disable-StartupEntry {
    param([string]$RunKey, [string]$Name)
    $approvedKey = $RunKey -replace '\\Run$', '\Explorer\StartupApproved\Run'
    if (-not (Test-Path $approvedKey)) { New-Item -Path $approvedKey -Force | Out-Null }
    # First byte 0x03 = disabled; Task Manager shows it as "Disabled"
    $bytes = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
    Set-ItemProperty -Path $approvedKey -Name $Name -Value $bytes -Type Binary -ErrorAction SilentlyContinue
    Write-Info "Startup disabled: $Name"
}

# ── Remove unnecessary startup entries entirely ───────────────────────────────
$removeEntries = @{
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" = @(
        "OneDrive",             # already removed but safety net
        "Teams",                # Microsoft Teams
        "Spotify",              # Spotify
        "Discord",              # no background chat on a console-feel PC
        "EpicGamesLauncher",    # Epic Games
        "GalaxyClient",         # GOG Galaxy
        "Uplay",                # Ubisoft Connect (old name)
        "UbisoftGameLauncher",  # Ubisoft Connect (new name)
        "AdobeGCInvoker-1.0",   # Adobe GC
        "CCLibrary",            # Adobe Creative Cloud
        "com.squirrel.Teams.Teams"
    )
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" = @(
        "TeamsMachineInstaller",
        "TeamsMachineUninstallerLocalAppData",
        "SecurityHealth"        # Windows Defender tray icon
    )
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" = @(
        "Adobe ARM",            # Adobe Acrobat updater
        "AdobeAAMUpdater-1.0"
    )
}

foreach ($path in $removeEntries.Keys) {
    foreach ($name in $removeEntries[$path]) {
        if (Get-ItemProperty $path -Name $name -ErrorAction SilentlyContinue) {
            Remove-ItemProperty $path -Name $name -ErrorAction SilentlyContinue
            Write-Info "Removed startup: $name"
        }
    }
}

# ── Edge auto-launch (wildcard — key name changes per install) ────────────────
$runHkcu = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$edgeEntries = (Get-ItemProperty $runHkcu -ErrorAction SilentlyContinue).PSObject.Properties |
               Where-Object { $_.Name -like "MicrosoftEdgeAutoLaunch*" }
foreach ($e in $edgeEntries) {
    Remove-ItemProperty $runHkcu -Name $e.Name -ErrorAction SilentlyContinue
    Write-Info "Removed Edge auto-launch: $($e.Name)"
}

# ── Edge startup boost & background mode — policy block ──────────────────────
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled"  0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled"  0
Set-Reg "HKCU:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
Write-Info "Edge startup boost and background mode disabled via policy."

# ── Steam: don't auto-start (Playnite launches it on demand) ─────────────────
Disable-StartupEntry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "Steam"

# ── Eliminate startup delay (boot faster, run all items in parallel) ──────────
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"         "ParseAutoexec"      1

# ── Disable background app access globally (Store apps won't run in bg) ───────
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1

# ── Per-app background access overrides — nuke them all ──────────────────────
# Individual UWP apps can re-enable background refresh even with the global flag.
# Enumerate every app entry and force it off.
$bgAppsBase = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
if (Test-Path $bgAppsBase) {
    Get-ChildItem $bgAppsBase -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty $_.PSPath -Name "Disabled"            -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty $_.PSPath -Name "DisabledByUser"      -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-Info "Per-app background access overrides cleared."
}

# ── Restore background access for Xbox Game Bar (required for FSE overlay) ────
# The global disable + per-app nuke above would also kill Game Bar's background
# hooks, preventing the Xbox Full Screen Experience overlay from appearing in-game.
$xboxBgPatterns = @(
    "Microsoft.XboxGamingOverlay_*",
    "Microsoft.GamingApp_*",
    "Microsoft.XboxApp_*",
    "Microsoft.XboxIdentityProvider_*"
)
if (Test-Path $bgAppsBase) {
    Get-ChildItem $bgAppsBase -ErrorAction SilentlyContinue | ForEach-Object {
        $leaf = Split-Path $_.PSPath -Leaf
        foreach ($pat in $xboxBgPatterns) {
            if ($leaf -like $pat) {
                Set-ItemProperty $_.PSPath -Name "Disabled"       -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty $_.PSPath -Name "DisabledByUser" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Write-Info "Background access restored: $leaf"
            }
        }
    }
}
Write-Info "Xbox Game Bar background access preserved (required for XboxFullscreenExperienceTool)."

# ── Services: Automatic → Manual (demand-start) ───────────────────────────────
# These services are harmless at zero — Windows starts them the moment something
# actually needs them. Keeping them Automatic wastes RAM/CPU every boot.
$toManual = @(
    "Spooler",          # Print Spooler — loads even without a printer
    "MapsBroker",       # Downloads offline maps nobody asked for
    "lfsvc",            # Geolocation — no reason to poll at boot
    "WerSvc",           # Windows Error Reporting — fires only on crash
    "TrkWks",           # Distributed Link Tracking Client — LAN relic
    "RetailDemo",       # Retail demo mode service
    "wisvc",            # Windows Insider Service
    "WbioSrvc",         # Windows Biometric (fingerprint/face) — on-demand fine
    "SharedAccess",     # Internet Connection Sharing
    "NetTcpPortSharing",# .NET port sharing — not needed
    "wcncsvc",          # Windows Connect Now (WPS pairing)
    "PhoneSvc",         # Phone Link / Your Phone
    "PrintNotify",      # Printer notifications
    "Fax",              # Fax service
    "NaturalAuthentication", # Windows Hello sensor polling
    "TabletInputService"    # Touch Keyboard — kept demand-startable for FSE touch simulation
)
foreach ($svc in $toManual) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.StartType -eq 'Automatic') {
        Set-Service $svc -StartupType Manual -ErrorAction SilentlyContinue
        Write-Info "Service → Manual: $svc"
    }
}

# ── Services: Automatic → Delayed Start ──────────────────────────────────────
# Must stay on but don't need to block the critical boot window.
# Delayed Start = fires ~2 min after logon, well after desktop is responsive.
# (Services already Disabled earlier are automatically skipped by the check below.)
$toDelayed = @(
    "DoSvc",                    # Delivery Optimization — we disabled P2P but service runs
    "CDPSvc",                   # Connected Devices Platform — Bluetooth/phone projection
    "PimIndexMaintenanceSvc",   # Contacts/calendar indexing — irrelevant on gaming PC
    "sppsvc"                    # Software Protection / activation check — boot-delay safe
)
if (-not $WindowsUpdateDisabled) {
    $toDelayed = @("wuauserv") + $toDelayed   # Windows Update — no reason to scan at boot
}
foreach ($svc in $toDelayed) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.StartType -eq 'Automatic') {
        # sc.exe is the only way to set Delayed-Auto in PowerShell
        sc.exe config $svc start= delayed-auto 2>&1 | Out-Null
        Write-Info "Service → Delayed Start: $svc"
    }
}

# ── Scheduled tasks that fire at logon ───────────────────────────────────────
# These run silently in the background right after login and waste CPU/disk.
$logonTasks = @(
    @{ Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater" },
    @{ Path="\Microsoft\Windows\Application Experience\"; Name="StartupAppTask" },
    @{ Path="\Microsoft\Windows\Application Experience\"; Name="MareBackup" },
    @{ Path="\Microsoft\Windows\Autochk\";                Name="Proxy" },
    @{ Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator" },
    @{ Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip" },
    @{ Path="\Microsoft\Windows\DiskDiagnostic\";         Name="Microsoft-Windows-DiskDiagnosticDataCollector" },
    @{ Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClient" },
    @{ Path="\Microsoft\Windows\Feedback\Siuf\";          Name="DmClientOnScenarioDownload" },
    @{ Path="\Microsoft\Windows\Maintenance\";            Name="WinSAT" },
    @{ Path="\Microsoft\Windows\Maps\";                   Name="MapsToastTask" },
    @{ Path="\Microsoft\Windows\Maps\";                   Name="MapsUpdateTask" },
    @{ Path="\Microsoft\Windows\NetTrace\";               Name="GatherNetworkInfo" },
    @{ Path="\Microsoft\Windows\PI\";                     Name="Sqm-Tasks" },
    @{ Path="\Microsoft\Windows\Power Efficiency Diagnostics\"; Name="AnalyzeSystem" },
    @{ Path="\Microsoft\Windows\Shell\";                  Name="FamilySafetyMonitor" },
    @{ Path="\Microsoft\Windows\Shell\";                  Name="FamilySafetyRefreshTask" },
    @{ Path="\Microsoft\Windows\SpacePort\";              Name="SpaceAgentTask" },
    @{ Path="\Microsoft\Windows\UpdateOrchestrator\";     Name="StartupAppTask" },
    @{ Path="\Microsoft\Windows\WS\";                     Name="License Validation" },
    @{ Path="\Microsoft\Windows\WS\";                     Name="WsAppx" }
)
foreach ($t in $logonTasks) {
    Disable-Task $t.Path $t.Name
}

# ── Boot configuration ────────────────────────────────────────────────────────
# Reduce boot menu timeout (already fast, this makes it instant on single-OS)
bcdedit /timeout 3 2>&1 | Out-Null
Write-Info "Boot: startup repair scan skipped, boot menu timeout = 3s."

Write-OK "Startup fully optimized."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
#region 20 — FINAL CLEANUP
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "20 — Final Cleanup"

# Flush DNS cache (clears any old telemetry IPs that were cached)
ipconfig /flushdns 2>&1 | Out-Null
Write-Info "DNS cache flushed."

# Disk cleanup — component store + silent drive clean (WinUtil Standard)
Write-Info "Running DISM component cleanup (may take a few minutes)..."
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null
cleanmgr.exe /autoclean /d C: 2>&1 | Out-Null
Write-Info "Disk cleanup complete."

# Reset Windows Update components (optional but clean)
# net stop wuauserv 2>&1 | Out-Null

# Restart Explorer to apply taskbar/shell changes
Write-Info "Restarting Explorer..."
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Start-Process explorer
Start-Sleep 1

Write-OK "Explorer restarted."
#endregion

# ─────────────────────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "  PLAYBOOK COMPLETE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "  REBOOT REQUIRED for:" -ForegroundColor Yellow
Write-Host "    • HAGS (GPU Scheduling)"
Write-Host "    • HPET / dynamic tick disable"
Write-Host "    • Ultimate Performance power plan"
Write-Host "    • Service changes"
Write-Host ""
Write-Host "  MANUAL STEPS after reboot:" -ForegroundColor Yellow
if ($BrowserChoice -ne "None") {
    Write-Host "    1. Open $BrowserChoice — confirm 'Set as default browser' if prompted"
    Write-Host "       If not prompted: Settings > Apps > Default Apps > $BrowserChoice > Set as default"
} else {
    Write-Host "    1. Set your preferred default browser in Windows Settings"
}
Write-Host "    2. GPU Control Panel: set Power Mode to Max Performance"
Write-Host "       Disable all Share/telemetry in GeForce Experience or AMD Software"
Write-Host "    3. BIOS: enable Resizable BAR (ReBAR), enable XMP/EXPO for RAM"
Write-Host "    4. NVIDIA users: install just the driver, skip GeForce Experience"
Write-Host "       (use NVCleanstall for a clean minimal driver install)"
Write-Host "    5. Consider NTLite to strip Windows components further (offline editing)"
switch ($WindowsUpdateChoice) {
    "Recommended" {
        Write-Host "    6. Windows Update: open Settings > Windows Update when you want monthly/security patches"
        Write-Host "       (nothing installs automatically — version upgrades are blocked)"
    }
    "Minimal" {
        Write-Host "    6. Windows Update: check Settings > Windows Update on your own schedule"
        Write-Host "       (updates are deferred — nothing pulls in the background)"
    }
    "Off" {
        Write-Host "    6. Windows Update is disabled — patch manually only if you change your mind later"
    }
}

$reboot = Read-Host "Reboot now? (Y/N)"
if ($reboot -match "^[Yy]") {
    Restart-Computer -Force
}
