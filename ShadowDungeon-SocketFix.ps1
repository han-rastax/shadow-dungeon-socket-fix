[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$AssemblyPath,

    [switch]$Restore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedOriginalSha256 = 'F1D130502E9F16477E779475B352F8BB127A1F7E6A0266FA9E761742899BF6B6'
$ExpectedPatchedSha256  = 'E97604ABA94E19AE0B3A5FB134508C2A7B31CA12C2644D1B164048A44A3CAB78'
$PatchOffset = 0x7A92B

[byte[]]$ExpectedBytes = @(
    0x02, 0x7B, 0xAB, 0x0A, 0x00, 0x04, 0x7B,
    0x14, 0x0A, 0x00, 0x04, 0x16, 0x31, 0x50
)

[byte[]]$ReplacementBytes = @(
    0x2B, 0x5C, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
)

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Find-ShadowDungeonAssembly {
    $steamRoots = New-Object 'System.Collections.Generic.List[string]'

    try {
        $steamRegistryPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath).SteamPath
        if ($steamRegistryPath) {
            $steamRoots.Add([IO.Path]::GetFullPath($steamRegistryPath))
        }
    }
    catch {
        # Steam may not have a per-user registry entry.
    }

    foreach ($fallback in @(
        (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
        (Join-Path $env:ProgramFiles 'Steam')
    )) {
        if ($fallback -and (Test-Path -LiteralPath $fallback)) {
            $steamRoots.Add([IO.Path]::GetFullPath($fallback))
        }
    }

    foreach ($root in @($steamRoots)) {
        $libraryFile = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile)) {
            continue
        }

        $libraryText = Get-Content -LiteralPath $libraryFile -Raw
        foreach ($match in [regex]::Matches($libraryText, '"path"\s+"([^"]+)"')) {
            $libraryPath = $match.Groups[1].Value -replace '\\\\', '\'
            if ($libraryPath -and (Test-Path -LiteralPath $libraryPath)) {
                $steamRoots.Add([IO.Path]::GetFullPath($libraryPath))
            }
        }
    }

    $candidates = @(
        $steamRoots |
            Select-Object -Unique |
            ForEach-Object {
                Join-Path $_ 'steamapps\common\Shadow Dungeon\Shadow Dungeon_Data\Managed\Assembly-CSharp.dll'
            } |
            Where-Object { Test-Path -LiteralPath $_ }
    )

    if ($candidates.Count -eq 0) {
        throw 'Shadow Dungeon was not found automatically. Pass the full DLL path with -AssemblyPath.'
    }

    if ($candidates.Count -gt 1) {
        $candidateList = $candidates -join [Environment]::NewLine
        throw "More than one installation was found. Run the script with -AssemblyPath and choose one:`n$candidateList"
    }

    return $candidates[0]
}

function Test-ByteSequence {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Data,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][byte[]]$Sequence
    )

    if ($Offset -lt 0 -or ($Offset + $Sequence.Length) -gt $Data.Length) {
        return $false
    }

    for ($index = 0; $index -lt $Sequence.Length; $index++) {
        if ($Data[$Offset + $index] -ne $Sequence[$index]) {
            return $false
        }
    }

    return $true
}

function Restore-OriginalAssembly {
    param([Parameter(Mandatory = $true)][string]$Path)

    $currentHash = Get-Sha256 -Path $Path
    if ($currentHash -eq $ExpectedOriginalSha256) {
        Write-Host 'The DLL is already original. Nothing to restore.' -ForegroundColor Green
        return
    }

    if ($currentHash -ne $ExpectedPatchedSha256) {
        throw "This DLL is neither the supported original nor this script's patched DLL. Refusing to restore an old backup over a different game build. Current SHA-256: $currentHash"
    }

    $directory = Split-Path -Parent $Path
    $fileName = Split-Path -Leaf $Path
    $backups = @(
        Get-ChildItem -LiteralPath $directory -File |
            Where-Object { $_.Name -like "$fileName.socketfix-backup-*" } |
            Sort-Object LastWriteTime -Descending
    )

    $validBackup = $null
    foreach ($backup in $backups) {
        if ((Get-Sha256 -Path $backup.FullName) -eq $ExpectedOriginalSha256) {
            $validBackup = $backup.FullName
            break
        }
    }

    if (-not $validBackup) {
        throw 'No matching original backup was found. Use Steam > Properties > Installed Files > Verify integrity instead.'
    }

    [IO.File]::Copy($validBackup, $Path, $true)
    if ((Get-Sha256 -Path $Path) -ne $ExpectedOriginalSha256) {
        throw 'Restore verification failed. The backup was not copied correctly.'
    }

    Write-Host "Restored the original DLL from:`n$validBackup" -ForegroundColor Green
}

try {
    $runningGame = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like '*Shadow*Dungeon*' } |
        Select-Object -First 1
    if ($runningGame) {
        throw 'Shadow Dungeon is running. Close the game before patching or restoring.'
    }

    if (-not $AssemblyPath) {
        $AssemblyPath = Find-ShadowDungeonAssembly
    }

    $resolvedPath = (Resolve-Path -LiteralPath $AssemblyPath).ProviderPath
    if ((Split-Path -Leaf $resolvedPath) -ne 'Assembly-CSharp.dll') {
        throw 'The selected file must be named Assembly-CSharp.dll.'
    }

    Write-Host "Target:`n$resolvedPath"

    if ($Restore) {
        Restore-OriginalAssembly -Path $resolvedPath
        exit 0
    }

    $currentHash = Get-Sha256 -Path $resolvedPath
    if ($currentHash -eq $ExpectedPatchedSha256) {
        Write-Host 'This supported DLL is already patched. Nothing to do.' -ForegroundColor Green
        exit 0
    }

    if ($currentHash -ne $ExpectedOriginalSha256) {
        throw "Unsupported DLL version. No changes were made. Current SHA-256: $currentHash"
    }

    $originalData = [IO.File]::ReadAllBytes($resolvedPath)
    if (-not (Test-ByteSequence -Data $originalData -Offset $PatchOffset -Sequence $ExpectedBytes)) {
        throw 'The expected instruction bytes were not found. No changes were made.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$resolvedPath.socketfix-backup-$timestamp"
    [IO.File]::Copy($resolvedPath, $backupPath, $false)

    $patchedData = New-Object byte[] $originalData.Length
    [Array]::Copy($originalData, $patchedData, $originalData.Length)
    [Array]::Copy($ReplacementBytes, 0, $patchedData, $PatchOffset, $ReplacementBytes.Length)

    $temporaryPath = "$resolvedPath.socketfix-$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $patchedData)
        $temporaryHash = Get-Sha256 -Path $temporaryPath
        if ($temporaryHash -ne $ExpectedPatchedSha256) {
            throw "Patched-file verification failed. Expected $ExpectedPatchedSha256 but got $temporaryHash."
        }

        [IO.File]::Copy($temporaryPath, $resolvedPath, $true)
        if ((Get-Sha256 -Path $resolvedPath) -ne $ExpectedPatchedSha256) {
            [IO.File]::Copy($backupPath, $resolvedPath, $true)
            throw 'Final verification failed. The original DLL was restored automatically.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }

    Write-Host "Temporary socket-loading fix applied successfully.`nBackup:`n$backupPath" -ForegroundColor Green
    Write-Host 'Steam updates or Verify integrity may replace the patched DLL. Re-run this script only if the new DLL hash is still supported.' -ForegroundColor Yellow
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
