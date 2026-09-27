# Actions.lib.ps1 - ConfigMgr / Intune client actions
# Dot-sourced by EndpointLogMonitor.ps1

$script:ScheduleActions = @(
    @{ Name = 'Machine Policy Retrieval & Evaluation Cycle'; Ids = @('{00000000-0000-0000-0000-000000000021}', '{00000000-0000-0000-0000-000000000022}') }
    @{ Name = 'User Policy Retrieval & Evaluation Cycle';   Ids = @('{00000000-0000-0000-0000-000000000025}', '{00000000-0000-0000-0000-000000000026}') }
    @{ Name = 'Application Deployment Evaluation Cycle';    Ids = @('{00000000-0000-0000-0000-000000000121}') }
    @{ Name = 'Software Updates Scan Cycle';                Ids = @('{00000000-0000-0000-0000-000000000113}') }
    @{ Name = 'Software Updates Agent Assignment Evaluation'; Ids = @('{00000000-0000-0000-0000-000000000108}') }
    @{ Name = 'Hardware Inventory Cycle';                   Ids = @('{00000000-0000-0000-0000-000000000001}') }
    @{ Name = 'Software Inventory Cycle';                   Ids = @('{00000000-0000-0000-0000-000000000002}') }
    @{ Name = 'Discovery Data Collection (Heartbeat)';      Ids = @('{00000000-0000-0000-0000-000000000003}') }
    @{ Name = 'Refresh Location Services';                  Ids = @('{00000000-0000-0000-0000-000000000024}') }
    @{ Name = 'Agent Cleanup Request';                      Ids = @('{00000000-0000-0000-0000-000000000040}') }
)

function Get-TargetName {
    param([string]$Computer)
    if ([string]::IsNullOrWhiteSpace($Computer)) { return $env:COMPUTERNAME }
    return $Computer.Trim()
}

function Invoke-ClientSchedule {
    param([string]$Computer, [string[]]$Ids, [string]$Name)
    $target = Get-TargetName -Computer $Computer
    foreach ($id in $Ids) {
        try {
            $p = @{
                Namespace   = 'root\ccm'
                ClassName   = 'SMS_Client'
                MethodName  = 'TriggerSchedule'
                Arguments   = @{ sScheduleID = $id }
                ErrorAction = 'Stop'
            }
            if ($Computer) { $p['ComputerName'] = $Computer.Trim() }
            $null = Invoke-CimMethod @p
            "OK   $Name -> $id on $target"
        } catch {
            "FAIL $Name -> $id on $target : $($_.Exception.Message)"
        }
    }
}

function Invoke-ServiceRestart {
    param([string]$Computer, [string]$Service)
    $target = Get-TargetName -Computer $Computer
    try {
        if ([string]::IsNullOrWhiteSpace($Computer)) {
            Restart-Service -Name $Service -Force -ErrorAction Stop
        } else {
            Restart-Service -Name $Service -ComputerName $Computer.Trim() -Force -ErrorAction Stop
        }
        "OK   Restarted service '$Service' on $target"
    } catch {
        "FAIL Restart '$Service' on $target : $($_.Exception.Message)"
    }
}

function Invoke-CcmCacheClear {
    param([string]$Computer)
    $target = Get-TargetName -Computer $Computer
    try {
        $cache = if ([string]::IsNullOrWhiteSpace($Computer)) { Join-Path $env:windir 'CCM\CcmCache' }
                 else { "\\$target\admin$\Windows\CCM\CcmCache" }
        if (-not (Test-Path -LiteralPath $cache)) { return "FAIL ccmcache not found at $cache" }
        $before = @(Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue).Count
        Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { } }
        $after = @(Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue).Count
        "OK   Cleared ccmcache on $target ($before -> $after folders left)"
    } catch {
        "FAIL Clearing ccmcache on $target : $($_.Exception.Message)"
    }
}

function Invoke-IntuneSync {
    param([string]$Computer)
    $target = Get-TargetName -Computer $Computer
    $session = $null
    try {
        $p = @{ TaskPath = '\Microsoft\Windows\EnterpriseMgmt\*'; ErrorAction = 'Stop' }
        if ($Computer) { $session = New-CimSession -ComputerName $Computer.Trim(); $p['CimSession'] = $session }
        $tasks = @(Get-ScheduledTask @p |
            Where-Object { $_.TaskName -like 'Schedule*' -or $_.TaskName -like '*enrollment*' })
        if ($tasks.Count -eq 0) {
            return "FAIL No EnterpriseMgmt enrolment tasks on $target (is the device MDM-enrolled?)"
        }
        $started = 0
        foreach ($t in $tasks) {
            $sp = @{ TaskPath = $t.TaskPath; TaskName = $t.TaskName; ErrorAction = 'Stop' }
            if ($session) { $sp['CimSession'] = $session }
            try { Start-ScheduledTask @sp; $started++ } catch { }
        }
        "OK   Triggered $started MDM sync task(s) on $target"
    } catch {
        "FAIL Intune sync on $target : $($_.Exception.Message)"
    } finally {
        if ($session) { try { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue } catch { } }
    }
}
