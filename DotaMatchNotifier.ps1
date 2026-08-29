<#
.SYNOPSIS
Notifies a phone through ntfy when Dota 2 or League of Legends becomes foreground.

.DESCRIPTION
After the user explicitly arms the notifier, this script watches the Windows
foreground window. A transition from another process to the selected game's
foreground process that remains stable briefly sends one urgent ntfy message.
The script does not read game memory, inspect traffic, modify game files, or
send input to either game.

.PARAMETER Game
Selects Dota2 or League. When omitted during normal use, the script prompts.

.PARAMETER Topic
Overrides the configured ntfy topic for this run. The override is not saved.

.PARAMETER TestNotification
Sends a test notification and exits without requiring either game.

.PARAMETER DryRun
Performs detection and logging but does not contact the ntfy server.

.PARAMETER Continuous
Allows another cycle only after an explicit Enter key press and a fresh arm.

.PARAMETER ConfigPath
Uses an alternate JSON configuration path.

.PARAMETER PollIntervalMs
Overrides the configured foreground polling interval in milliseconds.

.PARAMETER ConfirmationDelayMs
Overrides the configured foreground confirmation delay in milliseconds.

.EXAMPLE
.\DotaMatchNotifier.ps1 -TestNotification

.EXAMPLE
.\DotaMatchNotifier.ps1 -Game League -DryRun
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Dota2', 'League')]
    [string]$Game,

    [Parameter()]
    [string]$Topic,

    [Parameter()]
    [switch]$TestNotification,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Continuous,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [int]$PollIntervalMs,

    [Parameter()]
    [int]$ConfirmationDelayMs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:NotifierVersion = '1.1.0'
$script:LogPath = $null
$script:IsDotSourced = $MyInvocation.InvocationName -eq '.'
$script:TopicParameterSpecified = $PSBoundParameters.ContainsKey('Topic')
$script:PollIntervalParameterSpecified = $PSBoundParameters.ContainsKey('PollIntervalMs')
$script:ConfirmationDelayParameterSpecified = $PSBoundParameters.ContainsKey('ConfirmationDelayMs')

function Initialize-Logging {
    $applicationRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'DotaMatchNotifier'
    $logDirectory = Join-Path -Path $applicationRoot -ChildPath 'Logs'
    [void][System.IO.Directory]::CreateDirectory($logDirectory)

    $cutoff = (Get-Date).AddDays(-30)
    $existingLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'DotaMatchNotifier-*.log' -File -ErrorAction SilentlyContinue)

    foreach ($oldLog in @($existingLogs | Where-Object { $_.LastWriteTime -lt $cutoff })) {
        Remove-Item -LiteralPath $oldLog.FullName -Force -ErrorAction SilentlyContinue
    }

    $remainingLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'DotaMatchNotifier-*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending)
    foreach ($extraLog in @($remainingLogs | Select-Object -Skip 49)) {
        Remove-Item -LiteralPath $extraLog.FullName -Force -ErrorAction SilentlyContinue
    }

    $logName = 'DotaMatchNotifier-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $PID
    $script:LogPath = Join-Path -Path $logDirectory -ChildPath $logName
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($script:LogPath)) {
        return
    }

    $line = '{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message, [Environment]::NewLine
    try {
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($script:LogPath, $line, $utf8WithoutBom)
    }
    catch {
        # Logging must never hide or interrupt the foreground notification path.
    }
}

function Initialize-NativeTypes {
    if ('DotaMatchNotifier.NativeMethods' -as [type]) {
        return
    }

    $nativeSource = @'
using System;
using System.Runtime.InteropServices;

namespace DotaMatchNotifier
{
    public static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    }

    public static class CancellationMonitor
    {
        private static readonly object SyncRoot = new object();
        private static readonly ConsoleCancelEventHandler Handler = HandleCancelKeyPress;
        private static volatile bool cancellationRequested;
        private static bool installed;

        public static bool CancellationRequested
        {
            get { return cancellationRequested; }
        }

        public static void Install()
        {
            lock (SyncRoot)
            {
                cancellationRequested = false;
                if (!installed)
                {
                    Console.CancelKeyPress += Handler;
                    installed = true;
                }
            }
        }

        public static void Uninstall()
        {
            lock (SyncRoot)
            {
                if (installed)
                {
                    Console.CancelKeyPress -= Handler;
                    installed = false;
                }
                cancellationRequested = false;
            }
        }

        private static void HandleCancelKeyPress(object sender, ConsoleCancelEventArgs eventArgs)
        {
            eventArgs.Cancel = true;
            cancellationRequested = true;
        }
    }
}
'@

    Add-Type -TypeDefinition $nativeSource -Language CSharp
}

function Get-ForegroundProcessInfo {
    $windowHandle = [DotaMatchNotifier.NativeMethods]::GetForegroundWindow()
    if ($windowHandle -eq [IntPtr]::Zero) {
        return $null
    }

    [uint32]$foregroundProcessId = 0
    [void][DotaMatchNotifier.NativeMethods]::GetWindowThreadProcessId($windowHandle, [ref]$foregroundProcessId)
    if ($foregroundProcessId -eq 0) {
        return $null
    }

    $foregroundProcess = $null
    try {
        $foregroundProcess = Get-Process -Id $foregroundProcessId -ErrorAction Stop
        $processName = $foregroundProcess.ProcessName
        return [pscustomobject]@{
            ProcessId   = $foregroundProcessId
            ProcessName = $processName
        }
    }
    catch [System.ArgumentException] {
        return $null
    }
    catch [System.InvalidOperationException] {
        return $null
    }
    catch [System.ComponentModel.Win32Exception] {
        return $null
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $foregroundProcess) {
            $foregroundProcess.Dispose()
        }
    }
}

function Get-GameProfile {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$RequestedGame,

        [Parameter()]
        [switch]$PromptIfMissing
    )

    $selectedGame = $RequestedGame
    if ([string]::IsNullOrWhiteSpace($selectedGame)) {
        if (-not $PromptIfMissing) {
            return $null
        }

        Write-Host ''
        Write-Host 'Choose the game for this arming session:' -ForegroundColor Cyan
        Write-Host '  1. Dota 2'
        Write-Host '  2. League of Legends (experimental foreground detection)'
        while ($true) {
            $selection = Read-Host 'Enter 1 or 2'
            if ($selection -eq '1') {
                $selectedGame = 'Dota2'
                break
            }
            if ($selection -eq '2') {
                $selectedGame = 'League'
                break
            }
            Write-Warning 'Enter 1 for Dota 2 or 2 for League of Legends.'
        }
    }

    switch ($selectedGame) {
        'Dota2' {
            return [pscustomobject]@{
                Name                = 'Dota2'
                DisplayName         = 'Dota 2'
                ProcessName         = 'dota2'
                NotificationTitle   = 'Dota 2'
                NotificationMessage = 'MATCH FOUND - return to the PC and accept now.'
                NotificationTag     = 'video_game'
            }
        }
        'League' {
            return [pscustomobject]@{
                Name                = 'League'
                DisplayName         = 'League of Legends'
                ProcessName         = 'LeagueClientUx'
                NotificationTitle   = 'League of Legends'
                NotificationMessage = 'QUEUE READY - return to the PC and accept now.'
                NotificationTag     = 'video_game'
            }
        }
        default {
            throw 'The selected game is not supported.'
        }
    }
}

function Test-IsGameForeground {
    param(
        [Parameter()]
        [AllowNull()]
        [object]$ForegroundInfo,

        [Parameter(Mandatory = $true)]
        [object]$GameProfile
    )

    return ($null -ne $ForegroundInfo -and $ForegroundInfo.ProcessName -ieq $GameProfile.ProcessName)
}

function Test-GameProcessRunning {
    param(
        [Parameter(Mandatory = $true)]
        [object]$GameProfile
    )

    $gameProcesses = @(Get-Process -Name $GameProfile.ProcessName -ErrorAction SilentlyContinue)
    try {
        return $gameProcesses.Count -gt 0
    }
    finally {
        foreach ($gameProcess in $gameProcesses) {
            $gameProcess.Dispose()
        }
    }
}

function Get-ConfigurationProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$DefaultValue
    )

    $property = $Configuration.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }

    return $property.Value
}

function Test-TopicValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Value.Length -lt 1 -or $Value.Length -gt 64) {
        return $false
    }

    return $Value -cmatch '\A[A-Za-z0-9_-]+\z'
}

function Resolve-NtfyServer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $candidate = $Value.Trim()
    $serverUri = $null
    if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$serverUri)) {
        throw 'NtfyServer must be a valid absolute HTTPS URI.'
    }

    if ($serverUri.Scheme -ine 'https' -or [string]::IsNullOrWhiteSpace($serverUri.Host)) {
        throw 'NtfyServer must use HTTPS and include a host name.'
    }

    if (-not [string]::IsNullOrEmpty($serverUri.UserInfo) -or
        -not [string]::IsNullOrEmpty($serverUri.Query) -or
        -not [string]::IsNullOrEmpty($serverUri.Fragment)) {
        throw 'NtfyServer must not contain credentials, a query string, or a fragment.'
    }

    return $candidate.TrimEnd('/')
}

function ConvertTo-ValidatedInteger {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$Minimum,

        [Parameter(Mandatory = $true)]
        [int]$Maximum
    )

    $integerText = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
    [int]$converted = 0
    $parsed = [int]::TryParse(
        $integerText,
        [Globalization.NumberStyles]::Integer,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$converted
    )
    if (-not $parsed) {
        throw ('{0} must be an integer.' -f $Name)
    }

    if ($converted -lt $Minimum -or $converted -gt $Maximum) {
        throw ('{0} must be between {1} and {2} milliseconds.' -f $Name, $Minimum, $Maximum)
    }

    return $converted
}

function New-FirstRunConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Write-Host ''
    Write-Host 'No ntfy configuration was found.' -ForegroundColor Yellow
    Write-Host 'An ntfy topic acts like a password: anyone who knows it can publish to or subscribe to it.'
    Write-Host 'Keep the topic private, do not reuse it elsewhere, and do not share screenshots containing it.'
    $answer = Read-Host 'Generate a secure random topic and save it now? [Y/n]'
    if (-not [string]::IsNullOrWhiteSpace($answer) -and $answer -notmatch '\A(?i:y|yes)\z') {
        return $null
    }

    $generatedTopic = 'dota-{0}' -f ([Guid]::NewGuid().ToString('N'))
    $configuration = [pscustomobject][ordered]@{
        NtfyServer         = 'https://ntfy.sh'
        Topic              = $generatedTopic
        PollIntervalMs     = 250
        ConfirmationDelayMs = 750
        Priority           = 'max'
    }

    $destinationDirectory = Split-Path -Parent $DestinationPath
    if ([string]::IsNullOrWhiteSpace($destinationDirectory)) {
        $destinationDirectory = (Get-Location).Path
    }
    [void][System.IO.Directory]::CreateDirectory($destinationDirectory)
    $json = $configuration | ConvertTo-Json
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($DestinationPath, $json + [Environment]::NewLine, $utf8WithoutBom)

    Write-Host ''
    Write-Host 'Configuration saved.' -ForegroundColor Green
    Write-Host 'Subscribe to this exact topic in the ntfy mobile app:' -ForegroundColor Cyan
    Write-Host $generatedTopic -ForegroundColor White
    Write-Host 'This is the only normal setup step that prints the complete topic.' -ForegroundColor Yellow
    Write-Log -Level INFO -Message 'First-run configuration created; topic intentionally omitted from logs.'

    return $configuration
}

function Get-EffectiveConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedConfigPath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$TopicOverride
    )

    $configuration = $null
    if (Test-Path -LiteralPath $RequestedConfigPath -PathType Leaf) {
        try {
            $rawJson = [System.IO.File]::ReadAllText($RequestedConfigPath)
            $configuration = $rawJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw 'The configuration file could not be parsed as valid JSON.'
        }

        if ($configuration -is [System.Array]) {
            throw 'The configuration file must contain one JSON object.'
        }
    }
    elseif (-not $script:TopicParameterSpecified) {
        $configuration = New-FirstRunConfiguration -DestinationPath $RequestedConfigPath
        if ($null -eq $configuration) {
            return $null
        }
    }
    else {
        $configuration = [pscustomobject]@{}
    }

    $server = [string](Get-ConfigurationProperty -Configuration $configuration -Name 'NtfyServer' -DefaultValue 'https://ntfy.sh')
    $configuredTopic = [string](Get-ConfigurationProperty -Configuration $configuration -Name 'Topic' -DefaultValue '')
    $configuredPollInterval = Get-ConfigurationProperty -Configuration $configuration -Name 'PollIntervalMs' -DefaultValue 250
    $configuredConfirmationDelay = Get-ConfigurationProperty -Configuration $configuration -Name 'ConfirmationDelayMs' -DefaultValue 750
    $priority = [string](Get-ConfigurationProperty -Configuration $configuration -Name 'Priority' -DefaultValue 'max')

    $effectiveTopic = $configuredTopic
    if ($script:TopicParameterSpecified) {
        $effectiveTopic = $TopicOverride
    }

    if (-not (Test-TopicValue -Value $effectiveTopic)) {
        throw 'The ntfy topic is invalid. Use only A-Z, a-z, 0-9, underscore, and hyphen (1-64 characters).'
    }

    if ($priority -cne 'max') {
        throw 'Priority must be "max" so match-found alerts remain urgent.'
    }

    $effectivePollInterval = $configuredPollInterval
    if ($script:PollIntervalParameterSpecified) {
        $effectivePollInterval = $PollIntervalMs
    }

    $effectiveConfirmationDelay = $configuredConfirmationDelay
    if ($script:ConfirmationDelayParameterSpecified) {
        $effectiveConfirmationDelay = $ConfirmationDelayMs
    }

    return [pscustomobject]@{
        NtfyServer          = Resolve-NtfyServer -Value $server
        Topic               = $effectiveTopic
        PollIntervalMs      = ConvertTo-ValidatedInteger -Value $effectivePollInterval -Name 'PollIntervalMs' -Minimum 50 -Maximum 5000
        ConfirmationDelayMs = ConvertTo-ValidatedInteger -Value $effectiveConfirmationDelay -Name 'ConfirmationDelayMs' -Minimum 0 -Maximum 10000
        Priority            = 'max'
        ConfigPath          = $RequestedConfigPath
    }
}

function Get-NetworkFailureSummary {
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    $response = $null
    if ($Exception.PSObject.Properties['Response']) {
        $response = $Exception.Response
    }

    if ($null -ne $response -and $response.PSObject.Properties['StatusCode']) {
        try {
            return 'HTTP status {0}' -f [int]$response.StatusCode
        }
        catch {
            return 'HTTP request rejected'
        }
    }

    return $Exception.GetType().Name
}

function Send-NtfyNotification {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$NotificationTitle,

        [Parameter(Mandatory = $true)]
        [string]$NotificationTag
    )

    if ($DryRun) {
        Write-Host ('DRY RUN: Would send {0}; no network request was made.' -f $Description) -ForegroundColor Cyan
        Write-Log -Level INFO -Message ('Dry run completed for {0}; no network request was made.' -f $Description)
        return $true
    }

    $publishUriText = '{0}/{1}' -f $Configuration.NtfyServer, $Configuration.Topic
    $publishUri = $null
    if (-not [Uri]::TryCreate($publishUriText, [UriKind]::Absolute, [ref]$publishUri)) {
        Write-Log -Level ERROR -Message 'Notification URI construction failed; sensitive URL omitted.'
        return $false
    }

    $headers = @{
        Title    = $NotificationTitle
        Priority = 'max'
        Tags     = $NotificationTag
    }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $retryDelaysMs = @(0, 400, 800)
    $originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

    try {
        if (($originalSecurityProtocol -band [Net.SecurityProtocolType]::Tls12) -eq 0) {
            [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }

        for ($attempt = 1; $attempt -le 3; $attempt++) {
            if ($retryDelaysMs[$attempt - 1] -gt 0) {
                Start-Sleep -Milliseconds $retryDelaysMs[$attempt - 1]
            }

            try {
                $response = Invoke-WebRequest -Uri $publishUri.AbsoluteUri -Method Post -Headers $headers -Body $bodyBytes `
                    -ContentType 'text/plain; charset=utf-8' -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
                if ($null -eq $response.StatusCode -or ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)) {
                    Write-Host ('{0} delivered successfully.' -f $Description) -ForegroundColor Green
                    Write-Log -Level INFO -Message ('Notification delivery succeeded for {0} on attempt {1}.' -f $Description, $attempt)
                    return $true
                }
            }
            catch {
                $failureSummary = Get-NetworkFailureSummary -Exception $_.Exception
                Write-Warning ('Notification attempt {0} of 3 failed ({1}). The sensitive URL was omitted.' -f $attempt, $failureSummary)
                Write-Log -Level WARN -Message ('Notification delivery attempt {0} of 3 failed ({1}); sensitive URL omitted.' -f $attempt, $failureSummary)
            }
        }
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    }

    Write-Error ('{0} delivery failed after three attempts.' -f $Description) -ErrorAction Continue
    Write-Log -Level ERROR -Message ('Notification delivery failed for {0} after three attempts.' -f $Description)
    return $false
}

function Show-GameInstructions {
    param(
        [Parameter(Mandatory = $true)]
        [object]$GameProfile
    )

    Write-Host ''
    if ($GameProfile.Name -eq 'Dota2') {
        Write-Host @'
In Dota 2, open:
Settings > Options > Advanced Options

Enable:
Bring Dota 2 to front when match found

For the cleanest result, temporarily disable other
"Bring Dota 2 to front" events, especially Ready Checks.
'@
        return
    }

    Write-Host @'
League of Legends mode is experimental.

It watches LeagueClientUx.exe becoming the foreground application.
Riot does not document queue pop as a guaranteed foreground transition.
If the League client only flashes on the taskbar, this mode will not trigger.

Keep the League client open and visible before joining the queue.
'@ -ForegroundColor Yellow
}

function Request-Arming {
    param(
        [Parameter(Mandatory = $true)]
        [object]$GameProfile
    )

    Write-Host ''
    [void](Read-Host 'Start matchmaking, then press Enter here')
    [void](Read-Host 'Alt+Tab back to this notifier and press Enter to check foreground state')

    while ($true) {
        $foregroundInfo = Get-ForegroundProcessInfo
        if (-not (Test-IsGameForeground -ForegroundInfo $foregroundInfo -GameProfile $GameProfile)) {
            Write-Host ''
            Write-Host ('ARMED: Waiting for {0} to become the foreground application.' -f $GameProfile.DisplayName) -ForegroundColor Green
            Write-Host ('Do not manually switch back to {0} while armed.' -f $GameProfile.DisplayName) -ForegroundColor Yellow
            Write-Log -Level INFO -Message ('Notifier armed for {0}.' -f $GameProfile.DisplayName)
            return $foregroundInfo
        }

        Write-Warning ('{0} is still foreground. The notifier is not armed yet.' -f $GameProfile.DisplayName)
        [void](Read-Host ('Alt+Tab away from {0}, return here, and press Enter to check again' -f $GameProfile.DisplayName))
    }
}

function Wait-ForGameForegroundTransition {
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InitialForeground,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [object]$GameProfile
    )

    $previousForeground = $InitialForeground
    [DotaMatchNotifier.CancellationMonitor]::Install()
    try {
        while (-not [DotaMatchNotifier.CancellationMonitor]::CancellationRequested) {
            Start-Sleep -Milliseconds $Configuration.PollIntervalMs
            if ([DotaMatchNotifier.CancellationMonitor]::CancellationRequested) {
                return $false
            }

            $currentForeground = Get-ForegroundProcessInfo
            $wasGame = Test-IsGameForeground -ForegroundInfo $previousForeground -GameProfile $GameProfile
            $isGame = Test-IsGameForeground -ForegroundInfo $currentForeground -GameProfile $GameProfile

            if (-not $wasGame -and $isGame) {
                Write-Log -Level INFO -Message ('Foreground transition to {0} detected; starting confirmation delay.' -f $GameProfile.DisplayName)
                Start-Sleep -Milliseconds $Configuration.ConfirmationDelayMs
                if ([DotaMatchNotifier.CancellationMonitor]::CancellationRequested) {
                    return $false
                }

                $confirmedForeground = Get-ForegroundProcessInfo
                if (Test-IsGameForeground -ForegroundInfo $confirmedForeground -GameProfile $GameProfile) {
                    Write-Host ('Confirmed: {0} remained foreground.' -f $GameProfile.DisplayName) -ForegroundColor Green
                    Write-Log -Level INFO -Message ('Foreground transition confirmed for {0}.' -f $GameProfile.DisplayName)
                    return $true
                }

                Write-Log -Level INFO -Message 'Foreground transition was not stable; monitoring resumed.'
                $previousForeground = $confirmedForeground
                continue
            }

            $previousForeground = $currentForeground
        }

        return $false
    }
    finally {
        [DotaMatchNotifier.CancellationMonitor]::Uninstall()
    }
}

function Invoke-NotifierMain {
    $defaultConfigPath = Join-Path -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'DotaMatchNotifier') -ChildPath 'config.json'
    $effectiveConfigPath = $ConfigPath
    if ([string]::IsNullOrWhiteSpace($effectiveConfigPath)) {
        $effectiveConfigPath = $defaultConfigPath
    }
    else {
        $effectiveConfigPath = [System.IO.Path]::GetFullPath($effectiveConfigPath)
    }

    $gameProfile = $null
    if ($TestNotification) {
        if (-not [string]::IsNullOrWhiteSpace($Game)) {
            $gameProfile = Get-GameProfile -RequestedGame $Game
        }
    }
    else {
        $gameProfile = Get-GameProfile -RequestedGame $Game -PromptIfMissing
        if (-not (Test-GameProcessRunning -GameProfile $gameProfile)) {
            Write-Error ('{0}.exe is not running. Start {1}, then run the notifier again.' -f $gameProfile.ProcessName, $gameProfile.DisplayName) -ErrorAction Continue
            Write-Log -Level ERROR -Message ('Selected game process was not detected for {0}; notifier cannot arm.' -f $gameProfile.DisplayName)
            return 10
        }

        Write-Log -Level INFO -Message ('Selected game process detected for {0}.' -f $gameProfile.DisplayName)
    }

    $configuration = Get-EffectiveConfiguration -RequestedConfigPath $effectiveConfigPath -TopicOverride $Topic
    if ($null -eq $configuration) {
        Write-Warning 'Setup was cancelled. No configuration was written.'
        Write-Log -Level WARN -Message 'First-run configuration was declined.'
        return 2
    }
    Write-Log -Level INFO -Message 'Configuration loaded and validated successfully; topic intentionally omitted.'

    if ($TestNotification) {
        $testTitle = 'Game Queue Notifier'
        $testMessage = 'TEST - phone notifications are connected.'
        if ($null -ne $gameProfile) {
            $testTitle = $gameProfile.NotificationTitle
            $testMessage = 'TEST - {0} phone notifier is connected.' -f $gameProfile.DisplayName
        }
        $testDelivered = Send-NtfyNotification -Configuration $configuration `
            -Message $testMessage -Description 'test notification' `
            -NotificationTitle $testTitle -NotificationTag 'video_game'
        if ($testDelivered) {
            return 0
        }
        return 20
    }

    Initialize-NativeTypes

    $sendTestAnswer = Read-Host 'Send a test phone notification before arming? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($sendTestAnswer) -or $sendTestAnswer -match '\A(?i:y|yes)\z') {
        $testDelivered = Send-NtfyNotification -Configuration $configuration `
            -Message ('TEST - {0} phone notifier is connected.' -f $gameProfile.DisplayName) -Description 'test notification' `
            -NotificationTitle $gameProfile.NotificationTitle -NotificationTag $gameProfile.NotificationTag
        if (-not $testDelivered) {
            return 20
        }
    }

    Show-GameInstructions -GameProfile $gameProfile

    while ($true) {
        $initialForeground = Request-Arming -GameProfile $gameProfile
        $transitionDetected = Wait-ForGameForegroundTransition -InitialForeground $initialForeground `
            -Configuration $configuration -GameProfile $gameProfile
        if (-not $transitionDetected) {
            Write-Host 'Cancellation requested. The notifier has stopped.' -ForegroundColor Yellow
            Write-Log -Level WARN -Message 'Notifier cancelled while armed.'
            return 130
        }

        $matchDelivered = Send-NtfyNotification -Configuration $configuration `
            -Message $gameProfile.NotificationMessage -Description 'match-found notification' `
            -NotificationTitle $gameProfile.NotificationTitle -NotificationTag $gameProfile.NotificationTag
        if (-not $matchDelivered) {
            return 20
        }

        if (-not $Continuous) {
            return 0
        }

        Write-Host ''
        Write-Host 'Continuous mode is disarmed. It will not monitor again until you explicitly re-arm it.' -ForegroundColor Cyan
        $continuousAnswer = Read-Host 'Press Enter to begin a new arming cycle, or type Q to quit'
        if ($continuousAnswer -match '\A(?i:q|quit)\z') {
            return 0
        }

        if (-not (Test-GameProcessRunning -GameProfile $gameProfile)) {
            Write-Error ('{0}.exe is no longer running.' -f $gameProfile.ProcessName) -ErrorAction Continue
            Write-Log -Level ERROR -Message ('{0} exited before a requested re-arm.' -f $gameProfile.DisplayName)
            return 10
        }

        Show-GameInstructions -GameProfile $gameProfile
    }
}

$exitCode = 1
try {
    Initialize-Logging
    Write-Log -Level INFO -Message ('Script start. Version {0}.' -f $script:NotifierVersion)
    $exitCode = Invoke-NotifierMain
}
catch [System.Management.Automation.PipelineStoppedException] {
    $exitCode = 130
    Write-Warning 'Cancellation requested. The notifier has stopped.'
    Write-Log -Level WARN -Message 'Notifier cancelled by the user.'
}
catch {
    $exitCode = 1
    Write-Error ('Notifier failed: {0}' -f $_.Exception.Message) -ErrorAction Continue
    Write-Log -Level ERROR -Message ('Unhandled failure: {0}' -f $_.Exception.GetType().Name)
}
finally {
    if ('DotaMatchNotifier.CancellationMonitor' -as [type]) {
        [DotaMatchNotifier.CancellationMonitor]::Uninstall()
    }
    Write-Log -Level INFO -Message ('Final exit status: {0}.' -f $exitCode)
}

if ($script:IsDotSourced) {
    return $exitCode
}

exit $exitCode
