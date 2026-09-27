# Demo.lib.ps1 - sample SCCM / Intune log generation for the "Demo data" button
# Dot-sourced by EndpointLogMonitor.ps1
#
# Writes realistic CMTrace-format logs into <app>\DemoLogs so the whole pipeline
# (parse -> filter -> group -> fix match -> export) can be demonstrated on a
# machine that has no ConfigMgr client installed.

function New-CmTraceLine {
    param([string]$Message, [string]$Component, [int]$Type, [datetime]$Time)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $time = $Time.ToString('HH:mm:ss.fff', $inv)
    $date = $Time.ToString('M-d-yyyy', $inv)
    '<![LOG[{0}]LOG]!><time="{1}+000" date="{2}" component="{3}" context="" type="{4}" thread="5184" file="{3}.cpp:1421">' -f
        $Message, $time, $date, $Component, $Type
}

function New-DemoLogs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    # Type: 1 = info, 2 = warning, 3 = error. Count = how often it repeats.
    # [[GUID]] is swapped for a fresh GUID on every repeat, so the demo also
    # shows that grouping survives changing identifiers.
    $files = @(
        # ------------------------------------------------------- ConfigMgr --
        @{ Name = 'AppEnforce.log'; Component = 'AppEnforce'; Entries = @(
            @{ Type = 3; Count = 7; Msg = 'Application "Adobe Acrobat Reader DC 24.0" was installed, but the detection method did not find the product installed. ProductCode [[GUID]], msiexec returned 0x87D00324.' }
            @{ Type = 3; Count = 4; Msg = 'Installation of application "Microsoft Teams classic" failed. Windows Installer returned exit code 1603 (0x80070643) for package [[GUID]].' }
            @{ Type = 3; Count = 2; Msg = 'Another installation is already in progress (MSI exit code 1618). Sequence 4081, retry scheduled in 10 minutes.' }
            @{ Type = 3; Count = 3; Msg = 'CAppEnforcer::InstallApplication failed (0x87D0EE12) for deployment [[GUID]]; retry scheduled by the GRS window.' }
            @{ Type = 1; Count = 1; Msg = 'Prepared command line: "setup.exe" /quiet /norestart /log C:\Windows\ccmsetup\install.log' }
            @{ Type = 1; Count = 1; Msg = 'Entering Execution Manager (sequence: 4082).' }
        )}
        @{ Name = 'AppDiscovery.log'; Component = 'AppDiscovery'; Entries = @(
            @{ Type = 3; Count = 3; Msg = 'Detection rule evaluation failed for clause "Registry: HKLM\Software\Adobe\Acrobat Reader\Version". Error 0x87D00400 returned by the rule evaluator.' }
            @{ Type = 1; Count = 1; Msg = 'Starting detection evaluation for application [[GUID]].' }
        )}
        @{ Name = 'PolicyAgent.log'; Component = 'PolicyAgent'; Entries = @(
            @{ Type = 3; Count = 5; Msg = 'Failed to download policy [[GUID]] from the management point. Error 0x87D00440 - the expected policy document is incomplete.' }
            @{ Type = 1; Count = 2; Msg = 'Get policies = []' }
        )}
        @{ Name = 'LocationServices.log'; Component = 'LocationServices'; Entries = @(
            @{ Type = 2; Count = 3; Msg = 'Failed to resolve management point location using DNS for site PS1. No records were returned.' }
            @{ Type = 1; Count = 1; Msg = 'EspPhase: NotInEsp' }
        )}
        @{ Name = 'WUAHandler.log'; Component = 'WUAHandler'; Entries = @(
            @{ Type = 3; Count = 4; Msg = 'Scan failed with error 0x80244022 when contacting WSUS server wsus.corp.local on port 8530.' }
            @{ Type = 2; Count = 2; Msg = 'Failed to end search job - no results were returned by the update search.' }
            @{ Type = 1; Count = 1; Msg = 'Its a WSUS Update Source type' }
            @{ Type = 1; Count = 1; Msg = 'Enabling WUA Managed server policy' }
            @{ Type = 1; Count = 1; Msg = 'Async searching of updates using WUAgent started' }
        )}
        @{ Name = 'CAS.log'; Component = 'CAS'; Entries = @(
            @{ Type = 3; Count = 3; Msg = 'Content location request failed. Content not found (0x87D00607) for package [PS100012] version 1.0, revision [[GUID]].' }
            @{ Type = 3; Count = 1; Msg = 'Not enough disk space to download content (0x87D01201). Required 4096 MB, free 118 MB on C:.' }
        )}
        @{ Name = 'ccmsetup.log'; Component = 'ccmsetup'; Entries = @(
            @{ Type = 3; Count = 2; Msg = 'CcmSetup failed with error code 0x800701AD. Refer to CMSetup.log for detailed resolution steps.' }
            @{ Type = 3; Count = 1; Msg = 'Client installation completed with fatal Windows Installer error 0x80070643 (MSI 1603).' }
        )}
        @{ Name = 'UpdatesDeployment.log'; Component = 'UpdatesDeployment'; Entries = @(
            @{ Type = 2; Count = 2; Msg = 'No service window exists to install software updates (0x87D00667) for assignment [[GUID]].' }
            @{ Type = 1; Count = 1; Msg = 'Update assignment [[GUID]] evaluated.' }
        )}
        @{ Name = 'ClientIDManagerStartup.log'; Component = 'ClientIDManagerStartup'; Entries = @(
            @{ Type = 3; Count = 2; Msg = 'RegTask: Failed to send the registration request to the site. Error 0x8007071A.' }
        )}
        @{ Name = 'DataTransferService.log'; Component = 'DataTransferService'; Entries = @(
            @{ Type = 3; Count = 2; Msg = 'Downloading from http://dp1.corp.local:8530/CCMTOKENAUTH/ failed. Network timeout contacting the update/content server (0x80072EE2).' }
            @{ Type = 1; Count = 1; Msg = 'hr = 0x0' }
        )}

        # ------------------------------------------------------------ Intune --
        @{ Name = 'IntuneManagementExtension.log'; Component = 'IntuneManagementExtension'; Entries = @(
            @{ Type = 3; Count = 5; Msg = 'Win32 app installation failed for "Company Portal". Error 0x87D13B64, unknown application install error.' }
            @{ Type = 3; Count = 2; Msg = 'Content download failed. Remote content was not found at the server (0x87D104B3) for https://fef.managedcontent.microsoft.com/tenants/12345.' }
            @{ Type = 3; Count = 1; Msg = 'MSIX deployment rejected: sideloading is not enabled on this system (0x80073CFF).' }
            @{ Type = 3; Count = 2; Msg = 'Connection to the remote server timed out (0x87D103EC) after 30000 ms while polling for install status.' }
            @{ Type = 3; Count = 2; Msg = 'The IME service returned an unexpected response (0x87D00000) during tenant onboarding.' }
            @{ Type = 1; Count = 1; Msg = 'Got 12 Win32App(s) from the service' }
            @{ Type = 1; Count = 1; Msg = 'Requesting available apps only' }
            @{ Type = 1; Count = 1; Msg = 'Beginning detection started for app [[GUID]].' }
            @{ Type = 1; Count = 1; Msg = 'IntuneManagementExtension service started (version 10.2402.4.0).' }
        )}
        @{ Name = 'AgentExecutor.log'; Component = 'AgentExecutor'; Entries = @(
            @{ Type = 3; Count = 3; Msg = 'Script execution timed out after 60 minutes. Script [[GUID]] returned error 0x87D00207.' }
            @{ Type = 1; Count = 1; Msg = 'Looking for exit code 1234 in exit codes table' }
            @{ Type = 1; Count = 1; Msg = 'Process 5124 terminated with exitcode: 0' }
        )}
        @{ Name = 'HealthScripts.log'; Component = 'HealthScripts'; Entries = @(
            @{ Type = 3; Count = 3; Msg = 'Remediation failed for script "Check free disk space". Error 0x87D1FDE8 returned by the remediation.' }
            @{ Type = 2; Count = 1; Msg = 'Remediation not applicable for this device: script "Verify BitLocker" (0x87D1FDE9).' }
        )}
        @{ Name = 'AppWorkload.log'; Component = 'AppWorkload'; Entries = @(
            @{ Type = 3; Count = 2; Msg = 'Intune Win32 app enforcement error (detection/state) for "Microsoft 365 Apps for Enterprise". Error 0x87D1041C.' }
            @{ Type = 2; Count = 1; Msg = 'Intune Win32 app detection rules not present for app [[GUID]] (0x87D1041B).' }
            @{ Type = 1; Count = 1; Msg = 'Applicability: Win32App-2048 Status: Installed, ErrorCode: null' }
        )}
        @{ Name = 'MDM-Diagnostics.log'; Component = 'DeviceManagement-Enterprise-Diagnostics-Provider'; Entries = @(
            @{ Type = 3; Count = 3; Msg = 'MDM policy sync was rejected during enrollment. Error 0x8018002B, session [[GUID]].' }
            @{ Type = 3; Count = 1; Msg = 'MDM sync failed with Invalid Request (HTTP 400) - code 0x80190190.' }
        )}
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $Root -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $start = (Get-Date).AddHours(-4)
    foreach ($f in $files) {
        $sb = New-Object System.Text.StringBuilder
        $t = $start
        foreach ($e in $f.Entries) {
            for ($i = 0; $i -lt [int]$e.Count; $i++) {
                $msg = "$($e.Msg)"
                if ($msg.Contains('[[GUID]]')) {
                    $msg = $msg.Replace('[[GUID]]', ([guid]::NewGuid()).ToString().ToUpper())
                }
                [void]$sb.AppendLine((New-CmTraceLine -Message $msg -Component $f.Component -Type ([int]$e.Type) -Time $t))
                $t = $t.AddMinutes(2)
            }
        }
        $path = Join-Path $Root $f.Name
        [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    }
    return $Root
}
