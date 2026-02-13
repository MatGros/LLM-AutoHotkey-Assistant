<#
.SYNOPSIS
  Launches the project using AutoHotkey v2 (AutoHotkey64.exe) if installed.
.DESCRIPTION
  Searches for a v2 AutoHotkey executable and starts the specified .ahk script.
  If no executable is found, prints an explanatory error and exits with code 1.
.PARAMETER ScriptPath
  Path to the .ahk file to run. Defaults to the repository's main script.
.EXAMPLE
  .\run-with-ahk2.ps1
  powershell -ExecutionPolicy Bypass -File .\run-with-ahk2.ps1 -ScriptPath ".\LLM AutoHotkey Assistant.ahk"
#>
param(
    [string]$ScriptPath = "$PSScriptRoot\LLM AutoHotkey Assistant.ahk",
    [switch]$Wait,
    [switch]$Verbose = $true,
    [switch]$HoldOnError = $true,
    [switch]$Tail
)

function Find-Ahk2Exe {
    # Search on all common drives (C:, D:, etc.)
    $allDrives = @('C:', 'D:', 'E:', $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    # Filter to only existing drives
    $drives = @()
    foreach ($d in $allDrives) {
        if ($d -match '^[A-Z]:$') {
            # It's a drive letter - check if it exists
            if (Test-Path $d) {
                $drives += $d
            }
        } else {
            # It's a path variable, use it directly
            $drives += $d
        }
    }
    $drives = $drives | Select-Object -Unique
    
    $candidates = @()
    foreach ($drive in $drives) {
        $candidates += Join-Path $drive 'Program Files\AutoHotkey\v2\AutoHotkey64.exe'
        $candidates += Join-Path $drive 'Program Files\AutoHotkey\AutoHotkey64.exe'
        $candidates += Join-Path $drive 'Program Files\AutoHotkey\AutoHotkey.exe'
    }

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            Write-Host "Found AutoHotkey at: $p" -ForegroundColor Green
            return $p
        }
    }

    # search all Program Files folders recursively (slower fallback)
    Write-Host "Searching for AutoHotkey64.exe in all Program Files folders..." -ForegroundColor Yellow
    foreach ($drive in $drives) {
        $programFilesPath = Join-Path $drive 'Program Files*'
        $found = Get-ChildItem $programFilesPath -Filter 'AutoHotkey64.exe' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\v2\\' } | Select-Object -First 1
        if ($found) {
            Write-Host "Found AutoHotkey at: $($found.FullName)" -ForegroundColor Green
            return $found.FullName
        }
    }

    # fallback to PATH
    $cmd = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

# Prepare logging (moved up so Log() is available immediately)
$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }
$logFile = Join-Path $logDir 'run-with-ahk2.log'
# ensure log file exists and write header
if (-not (Test-Path $logFile)) { "$(Get-Date -Format o) - LOG START" | Out-File -FilePath $logFile -Encoding UTF8 }
function Log($msg) {
    $line = "$(Get-Date -Format o) - $msg"
    Add-Content -Path $logFile -Value $line

    # always echo to console so the user sees immediate feedback
    Write-Host $line

    if ($Verbose) { Write-Host '---' -ForegroundColor DarkGray }
}

$ahkExe = Find-Ahk2Exe
if (-not $ahkExe) {
    $err = "AutoHotkey v2 executable not found. Please install AutoHotkey v2 (>= 2.0.18) or set the correct file association."
    Write-Host $err -ForegroundColor Red
    Write-Host "Download: https://autohotkey.com/download/" -ForegroundColor Yellow
    $line = "$(Get-Date -Format o) - ERROR: $err"
    Add-Content -Path $logFile -Value $line
    Write-Host $line -ForegroundColor Red
    if ($HoldOnError -and $Host.UI.RawUI.KeyAvailable -eq $false) {
        # interactive pause so user can see the message when double-clicked
        Read-Host "Press Enter to close"
    }
    exit 1
}

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Specified script not found: $ScriptPath"
    $line = "$(Get-Date -Format o) - ERROR: Specified script not found: $ScriptPath"
    Add-Content -Path $logFile -Value $line
    Write-Host $line -ForegroundColor Red
    exit 2
}
Write-Host "run-with-ahk2 starting..." -ForegroundColor Cyan
Log "run-with-ahk2 invoked. Script='$ScriptPath' Verbose=$Verbose Tail=$Tail"
Write-Host "Launching:`n  AHK: $ahkExe`n  Script: $ScriptPath" -ForegroundColor Cyan
Log "Attempting launch. AHK='$ahkExe' Script='$ScriptPath'"

# If an AutoHotkey process that runs this script already exists, inform the user
$scriptFullPath = (Resolve-Path $ScriptPath).Path
$existing = Get-Process -Name AutoHotkey64 -ErrorAction SilentlyContinue | Where-Object {
    ($_).Path -eq $ahkExe -and (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match [regex]::Escape($scriptFullPath)
}
if ($existing) {
    Write-Host "A matching AutoHotkey process is already running (PID: $($existing.Id))." -ForegroundColor Yellow
    Log "Already running PID=$($existing.Id)"
    if ($Verbose) { Get-Process -Id $existing.Id | Format-List * }
    exit 0
}

try {
    $proc = Start-Process -FilePath $ahkExe -ArgumentList ('"' + $scriptFullPath + '"') -PassThru
    Start-Sleep -Milliseconds 250
    if ($proc -and -not $proc.HasExited) {
        Write-Host "Started AHK (PID: $($proc.Id))." -ForegroundColor Green
        Log "Started PID=$($proc.Id)"
        if ($Wait) {
            Write-Host "Waiting for process to exit... (press Ctrl+C to cancel)" -ForegroundColor Cyan
            $proc.WaitForExit()
            Write-Host "Process exited with code $($proc.ExitCode)" -ForegroundColor Yellow
            Log "Process exited with code $($proc.ExitCode)"
        }

        if ($Tail) {
            Write-Host "Tailing log file (logs/run-with-ahk2.log). Press Ctrl+C to stop." -ForegroundColor Cyan
            try { Get-Content -Path $logFile -Tail 50 -Wait } catch { Write-Host "Failed to tail log: $($_.Message)" -ForegroundColor Red }
        }
    } else {
        Write-Host "Process started but exited immediately." -ForegroundColor Red
        Log "Process started but exited immediately. ExitCode=$($proc.ExitCode)"
        if ($HoldOnError) { Read-Host "Press Enter to continue" }
    }
} catch {
    Write-Host "Failed to start AutoHotkey: $($_.Exception.Message)" -ForegroundColor Red
    Log "Failed to start: $($_.Exception.Message)"
    if ($HoldOnError) { Read-Host "Press Enter to continue" }
    exit 3
}

