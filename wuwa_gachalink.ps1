
#requires -Version 5.0

[CmdletBinding()]
param(
    # Optional full path to Client.log.
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $LogPath,

    # The extracted URL is copied to the clipboard unless -NoCopy is passed.
    [switch] $NoCopy,

    # Kept for backward compatibility; copying is now the default.
    [switch] $Copy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#  Log Matching e.g. - https://aki-gm-resources-oversea.aki-game.net/aki/gacha/index.html#/record?...
$script:ConveneUri = [regex]::new(
    ('https://aki-gm-resources' +
     '(?:-oversea){0,1}' +
     '[.]aki-game[.](?:net|com)' +
     '/aki/gacha/index[.]html#/record' +
     '[^\s"]*'),
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

function Read-BytesWithoutLocking {
    param([Parameter(Mandatory = $true)][string] $Path)

    $handle = $null
    $buffer = $null
    try {
        # Keep the handle read-only and share all ordinary file operations.
        $share = [IO.FileShare]::Read -bor [IO.FileShare]::Write -bor [IO.FileShare]::Delete
        $handle = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $buffer = [IO.MemoryStream]::new()
        $handle.CopyTo($buffer)
        return $buffer.ToArray()
    }
    finally {
        if ($buffer) { $buffer.Dispose() }
        if ($handle) { $handle.Dispose() }
    }
}

function ConvertFrom-GameObfuscation {
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)

    # XOR mask selection.
    $decoded = [byte[]]::new($Bytes.Length)
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        $value = [int]$Bytes[$i]
        $mask = if (($value -band 1) -eq 1) { 0xA5 } else { 0xEF }
        $decoded[$i] = [byte]($value -bxor $mask)
    }
    return $decoded
}

function ConvertTo-TextCandidates {
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)

    $utf8 = [Text.UTF8Encoding]::new($false, $false)
    $plain = $utf8.GetString($Bytes)
    $decoded = $utf8.GetString((ConvertFrom-GameObfuscation -Bytes $Bytes))

    if ($plain -eq $decoded) { return ,$plain }
    return @($plain, $decoded)
}

function Find-ConveneLink {
    param([Parameter(Mandatory = $true)][string[]] $Texts)

    foreach ($text in $Texts) {
        $hits = $script:ConveneUri.Matches($text)
        if ($hits.Count -gt 0) {
            # The last occurrence is normally the newest history URL in a log.
            return $hits[$hits.Count - 1].Value
        }
    }
    return $null
}

function Add-UniqueRoot {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $Set,
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $Set.Add($Path.Trim().TrimEnd('\', '/')) | Out-Null
}

function Add-PathRoot {
    # Extract the install root.
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $Set,
        [Parameter(Mandatory = $true)][string] $Text
    )

    $m = [regex]::Match($Text, '(?i)^(.+?)\\Client\\')
    if ($m.Success) { Add-UniqueRoot -Set $Set -Path $m.Groups[1].Value; return }

    $m = [regex]::Match($Text, '(?i)^(.+?)\\launcher[.]exe')
    if ($m.Success) { Add-UniqueRoot -Set $Set -Path $m.Groups[1].Value }
}

function Get-RegistryInstallRoots {
    # Probe the registry sources.
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $uninstallKeys = @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($keyPath in $uninstallKeys) {
        $entries = Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue
        foreach ($entry in @($entries)) {
            # Scan every property for a path that contains the game folder.
            foreach ($prop in $entry.PSObject.Properties) {
                $text = [string]$prop.Value
                if ($text -notmatch '(?i)wuthering') { continue }
                Add-PathRoot -Set $roots -Text $text
            }
        }
    }
    if ($roots.Count -gt 0) { return $roots }

    # MUI cache method.
    $muiKey = Get-Item -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache' -ErrorAction SilentlyContinue
    if ($null -ne $muiKey) {
        foreach ($name in $muiKey.GetValueNames()) {
            if ($name -notmatch '(?i)Client-Win64-Shipping[.]exe') { continue }
            $match = [regex]::Match($name, '(?i)^(.+?)\\Client\\')
            if ($match.Success) { Add-UniqueRoot -Set $roots -Path $match.Groups[1].Value }
        }
    }
    if ($roots.Count -gt 0) { return $roots }

    # Firewall rules method.
    $firewallKey = Get-Item -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules' -ErrorAction SilentlyContinue
    if ($null -ne $firewallKey) {
        $rules = Get-ItemProperty -LiteralPath $firewallKey.PSPath -ErrorAction SilentlyContinue
        if ($null -ne $rules) {
            foreach ($prop in $rules.PSObject.Properties) {
                $text = [string]$prop.Value
                if ($text -notmatch '(?i)wuthering') { continue }
                $appMatch = [regex]::Match($text, '(?i)App=([^|]+)')
                if (-not $appMatch.Success) { continue }
                $rootMatch = [regex]::Match($appMatch.Groups[1].Value, '(?i)^(.+?)\\Client\\')
                if ($rootMatch.Success) { Add-UniqueRoot -Set $roots -Path $rootMatch.Groups[1].Value }
            }
        }
    }

    return $roots
}

function Get-SteamInstallRoots {
    # Steam.
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $steamRoot = $null
    $steamKey = Get-Item -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
    if ($null -ne $steamKey) {
        $steamProps = Get-ItemProperty -LiteralPath $steamKey.PSPath -ErrorAction SilentlyContinue
        if ($null -ne $steamProps) {
            $installProp = $steamProps.PSObject.Properties['InstallPath']
            if ($null -ne $installProp) { $steamRoot = [string]$installProp.Value }
        }
    }
    if ([string]::IsNullOrWhiteSpace($steamRoot)) { return $roots }

    $libraries = [System.Collections.Generic.List[string]]::new()
    $libraries.Add($steamRoot)
    $vdfPath = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdfPath -PathType Leaf) {
        $vdfText = Get-Content -LiteralPath $vdfPath -Raw -ErrorAction SilentlyContinue
        if ($vdfText) {
            foreach ($m in [regex]::Matches($vdfText, '"path"\s+"([^"]+)"')) {
                $libraries.Add($m.Groups[1].Value.Replace('\\', '\'))
            }
        }
    }

    foreach ($library in $libraries) {
        $common = Join-Path $library 'steamapps\common\Wuthering Waves'
        Add-UniqueRoot -Set $roots -Path $common
        Add-UniqueRoot -Set $roots -Path (Join-Path $common 'Wuthering Waves Game')
    }
    return $roots
}

function Get-EpicInstallRoots {
    # Epic.
    $manifestDir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (-not (Test-Path -LiteralPath $manifestDir -PathType Container)) { return }

    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in Get-ChildItem -LiteralPath $manifestDir -Filter '*.item' -File -ErrorAction SilentlyContinue) {
        try {
            $manifest = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        }
        catch { continue }

        $display = $manifest.PSObject.Properties['DisplayName']
        $location = $manifest.PSObject.Properties['InstallLocation']
        if ($null -eq $display -or $null -eq $location) { continue }
        if ($display.Value -notmatch '(?i)wuthering') { continue }
        Add-UniqueRoot -Set $roots -Path ([string]$location.Value)
    }
    return $roots
}

function Get-CommonInstallRoots {
    # Sweep the usual base folders on every fixed drive.
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $baseFolders = @('', 'Games\', 'Program Files\', 'Program Files (x86)\')
    $gameFolders = @('Wuthering Waves Game', 'Wuthering Waves\Wuthering Waves Game')

    try {
        $drives = [System.IO.DriveInfo]::GetDrives()
    }
    catch { return $roots }

    foreach ($drive in $drives) {
        if (-not $drive.IsReady) { continue }
        if ($drive.DriveType -eq [System.IO.DriveType]::Network -or
            $drive.DriveType -eq [System.IO.DriveType]::CDRom) { continue }
        foreach ($baseFolder in $baseFolders) {
            foreach ($gameFolder in $gameFolders) {
                Add-UniqueRoot -Set $roots -Path (Join-Path $drive.RootDirectory.FullName ($baseFolder + $gameFolder))
            }
        }
    }
    return $roots
}

function Get-ClientLogsFromRoots {
    # Expand each root to the two known log paths and keep those that exist.
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $Roots
    )

    $logPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $Roots) {
        $logPaths.Add((Join-Path $root 'Client\Saved\Logs\Client.log')) | Out-Null
        $logPaths.Add((Join-Path $root 'Wuthering Waves Game\Client\Saved\Logs\Client.log')) | Out-Null
    }

    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($logPath in $logPaths) {
        $file = Get-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
        if ($null -eq $file -or $file.PSIsContainer) { continue }
        $found.Add([PSCustomObject]@{
                Path          = $logPath
                LastWriteTime = $file.LastWriteTime
                Source        = 'auto'
            })
    }
    return $found
}

function Find-GachaLogCandidates {
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in @(Get-SteamInstallRoots)) { Add-UniqueRoot -Set $roots -Path $root }
    foreach ($root in @(Get-EpicInstallRoots)) { Add-UniqueRoot -Set $roots -Path $root }
    foreach ($root in @(Get-CommonInstallRoots)) { Add-UniqueRoot -Set $roots -Path $root }

    $candidates = @(Get-ClientLogsFromRoots -Roots $roots)
    if ($candidates.Count -eq 0) {
        foreach ($root in @(Get-RegistryInstallRoots)) { Add-UniqueRoot -Set $roots -Path $root }
        $candidates = @(Get-ClientLogsFromRoots -Roots $roots)
    }

    $candidates | Sort-Object LastWriteTime -Descending
}

function Read-ConveneUrlFromLog {
    param([Parameter(Mandatory = $true)][string] $Path)

    $bytes = Read-BytesWithoutLocking -Path $Path
    return Find-ConveneLink -Texts (ConvertTo-TextCandidates -Bytes $bytes)
}

$candidateLogs = @()

if ($LogPath) {
    # Validate an explicit path up front so typos surface immediately.
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        throw "Log file not found: $LogPath"
    }
    $fullPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $LogPath).Path)
    $candidateLogs = @([PSCustomObject]@{
            Path          = $fullPath
            LastWriteTime = [datetime]::MinValue
            Source        = 'explicit'
        })
}
else {
    $candidateLogs = @(Find-GachaLogCandidates)
    if ($candidateLogs.Count -gt 0) {
        Write-Host ("Found {0} Client.log candidate(s), newest first:" -f $candidateLogs.Count)
        $rank = 0
        foreach ($log in $candidateLogs) {
            $rank++
            Write-Host ("  {0,2}. [{1:yyyy-MM-dd HH:mm}] {2}" -f $rank, $log.LastWriteTime, $log.Path) -ForegroundColor DarkGray
        }
    }
}

$url = $null
$matchedLog = $null

foreach ($log in $candidateLogs) {
    try {
        $url = Read-ConveneUrlFromLog -Path $log.Path
    }
    catch {
        if ($log.Source -eq 'auto') {
            Write-Warning "Could not read $($log.Path): $($_.Exception.Message)"
            continue
        }
        throw
    }
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        $matchedLog = $log
        break
    }
}

if ($null -eq $matchedLog) {
    if ($candidateLogs.Count -gt 0) {
        throw 'No record link was present in the newest logs. Launch the game, open the Convene History screen once, then run this again.'
    }

    # Ask for the path when no candidates were found.
    $manualPath = $null
    if (-not [Console]::IsInputRedirected) {
        Write-Host 'Could not locate Client.log automatically.' -ForegroundColor Yellow
        $manualPath = Read-Host 'Paste the full path to Client.log (or press Enter to quit)'
    }
    if ([string]::IsNullOrWhiteSpace($manualPath)) {
        throw 'Client.log could not be located. Re-run with -LogPath "<full path to Client.log>".'
    }
    if (-not (Test-Path -LiteralPath $manualPath -PathType Leaf)) {
        throw "Log file not found: $manualPath"
    }
    $manualFullPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $manualPath).Path)
    $url = Read-ConveneUrlFromLog -Path $manualFullPath
    $matchedLog = [PSCustomObject]@{ Path = $manualFullPath; LastWriteTime = [datetime]::MinValue; Source = 'manual' }
}

if ([string]::IsNullOrWhiteSpace($url)) {
    throw 'No record link was present in that log. Launch the game, open the Convene History screen once, then run this again.'
}

if ($matchedLog.Source -ne 'explicit') {
    Write-Host "Using $($matchedLog.Path)" -ForegroundColor Cyan
}

Write-Output $url

if (-not $NoCopy) {
    try {
        Set-Clipboard -Value $url
        Write-Host 'The link has been copied to the clipboard.' -ForegroundColor Green
    }
    catch {
        Write-Warning "The URL could not be copied to the clipboard: $($_.Exception.Message)"
    }
}
else {
    Write-Host 'Clipboard copy skipped (-NoCopy).' -ForegroundColor DarkGray
}

Read-Host 'Press Enter to Escape'
