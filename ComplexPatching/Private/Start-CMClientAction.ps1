function Start-CMClientAction {
    <#
.SYNOPSIS
    Invokes CM Client actions on local or remote machines

.DESCRIPTION
    This script will allow you to invoke a set of CM Client actions on a machine (with optional credentials), providing a list of the actions and an optional delay betweens actions. 
    The function will attempt for 5 minutes to invoke the action, with a 10 second delay inbetween attempts. This is to account for invoke-wmimethod failures.

.PARAMETER Schedule
	Define the schedules to run on the machine - 'HardwareInv', 'SoftwareInv', 'UpdateScan', 'UpdateEval', 'MachinePol', 'AppEval'

.PARAMETER Delay
	Specify the delay in seconds between each schedule when more than one is ran - 0-30 seconds

.PARAMETER ComputerName
	Specifies the computers to run this against

.PARAMETER Credential
	Optional PSCredential

.EXAMPLE
	# Start a machine policy eval and a hardware inventory cycle
	Start-CMClientAction -Schedule MachinePol,HardwareInv

.NOTES
    FileName:    Start-CMClientAction.ps1
    Author:      Cody Mathis
    Contact:     @CodyMathis123
    Created:     11-29-2018
    Updated:     11-29-2018
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet('HardwareInv', 'SoftwareInv', 'UpdateScan', 'UpdateEval', 'MachinePol', 'AppEval')]
        [string[]]$Schedule,
        [parameter(Mandatory = $false)]
        [ValidateRange(0, 30)]
        [int]$Delay = 1,
        [parameter(Mandatory = $false)]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [parameter(Mandatory = $false)]
        [pscredential]$Credential,
        [parameter(Mandatory = $true)]
        [string]$SQLServer,
        [parameter(Mandatory = $true)]
        [string]$Database,
        [Parameter(Mandatory = $false)]
        [switch]$Component,
        [Parameter(Mandatory = $false)]
        [switch]$FileName,
        [Parameter(Mandatory = $false)]
        [switch]$Folder
    )
    begin {
        $PSDefaultParameterValues = $Global:PSDefaultParameterValues
        $TimeSpan = New-TimeSpan -Minutes 5
    }
    process {
        foreach ($Computer in $ComputerName) {
            foreach ($Option in $Schedule) {
                $Action = switch ($Option) {
                    HardwareInv {
                        "{00000000-0000-0000-0000-000000000001}"
                    }
                    SoftwareInv {
                        "{00000000-0000-0000-0000-000000000002}"
                    }
                    UpdateScan {
                        "{00000000-0000-0000-0000-000000000113}"
                    }
                    UpdateEval {
                        "{00000000-0000-0000-0000-000000000108}"
                    }
                    MachinePol {
                        "{00000000-0000-0000-0000-000000000021}"
                    }
                    AppEval {
                        "{00000000-0000-0000-0000-000000000121}"
                    }
                }

                $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
                do {
                    try {
                        $invokeWmiMethodSplat = @{
                            ComputerName = $Computer
                            Name         = 'TriggerSchedule'
                            Namespace    = 'root\ccm'
                            Class        = 'sms_client'
                            ArgumentList = $Action
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $invokeWmiMethodSplat.Add('Credential', $Credential)
                        }
                        $writeCMLogEntrySplat = @{
                            Folder    = $Folder
                            Component = $ComputerName
                            FileName  = $FileName
                            Value     = "Triggering a $Option Cycle on $Computer via the 'TriggerSchedule' WMI method"
                        }
                        Write-CMLogEntry @writeCMLogEntrySplat
                        $Invocation = Invoke-WmiMethod @invokeWmiMethodSplat
                    }
                    catch {
                        $writeCMLogEntrySplat = @{
                            Value     = "Failed to invoke the $Option cycle via WMI. Will retry every 10 seconds until [StopWatch $($StopWatch.Elapsed) -ge 5 minutes] Error: $($_.Exception.Message)"
                            Severity  = 2
                            Folder    = $Folder
                            Component = $ComputerName
                            FileName  = $FileName
                        }
                        Write-CMLogEntry @writeCMLogEntrySplat
                        Start-Sleep -Seconds 10
                    }
                }
                until ($Invocation -or $StopWatch.Elapsed -ge $TimeSpan)
                if ($Invocation) {
                    $writeCMLogEntrySplat = @{
                        Value     = "Successfully invoked the $Option Cycle on $Computer via the 'TriggerSchedule' WMI method"
                        Folder    = $Folder
                        Component = $ComputerName
                        FileName  = $FileName
                    }
                    Write-CMLogEntry @writeCMLogEntrySplat
                    [string]$Time = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), 'Eastern Standard Time')
                    $ScanInvokedQuery = [string]::Format("UPDATE [dbo].[ServerStatus] SET LastStatus = '{0} Invoked', TimeStamp='{1}' Where Servername = '{2}'", $Option, $Time, $ComputerName)
                    $startCompPatchQuerySplat = @{
                        Query     = $ScanInvokedQuery
                        SQLServer = $SQLServer
                        Database  = $Database
                    }
                    Start-CompPatchQuery @startCompPatchQuerySplat		
                    Start-Sleep -Seconds $Delay
                }
                $StopWatch.Reset()    
            }
        }
    }
    end {
        $writeCMLogEntrySplat = @{
            Value     = "Following actions invoked - $Schedule"
            Folder    = $Folder
            Component = $ComputerName
            FileName  = $FileName
        }
        Write-CMLogEntry @writeCMLogEntrySplat
    }
}