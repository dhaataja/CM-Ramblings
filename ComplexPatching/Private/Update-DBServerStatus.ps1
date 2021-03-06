function Update-DBServerStatus {
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = 'LogDuration')]
        [parameter(ParameterSetName = 'UpdateDB')]
        [string]$ComputerName,
        [parameter(Mandatory = $true, ParameterSetName = 'LogDuration')]
        [parameter(ParameterSetName = 'UpdateDB')]
        [string]$RBInstance,
        [parameter(Mandatory = $false, ParameterSetName = 'UpdateDB')]
        [switch]$SetRBInstance,
        [parameter(Mandatory = $false, ParameterSetName = 'UpdateDB')]
        [string]$Status,
        [parameter(Mandatory = $false, ParameterSetName = 'UpdateDB')]
        [string]$LastStatus,
        [parameter(Mandatory = $true, ParameterSetName = 'LogDuration')]
        [ValidateSet('Start', 'End')]
        [string]$Stage,
        [parameter(Mandatory = $true, ParameterSetName = 'LogDuration')]
        [string]$Component,
        [parameter(Mandatory = $false, ParameterSetName = 'LogDuration')]
        [bool]$DryRun = $false,
        [parameter(Mandatory = $true)]
        [string]$SQLServer,
        [parameter(Mandatory = $true)]
        [string]$Database
    )
    [string]$Time = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), 'Eastern Standard Time')
    switch ($PSCmdlet.ParameterSetName) {
        'UpdateDB' {
            $Query = [string]::Format("UPDATE [dbo].[ServerStatus] SET TimeStamp='{0}'", $Time)
            if ($PSBoundParameters.ContainsKey('Status')) {
                $Query = [string]::Format("{0}, Status='{1}'", $Query, $Status)
            }
            
            if ($PSBoundParameters.ContainsKey('LastStatus')) {
                $Query = [string]::Format("{0}, LastStatus='{1}'", $Query, $LastStatus)
            }
            
            switch ($SetRBInstance) {
                $true {
                    $Query = [string]::Format("{0}, RBInstance='{1}' WHERE ServerName='{2}'", $Query, $RBInstance, $ComputerName)
                }
                $false {
                    $Query = [string]::Format("{0} WHERE ServerName='{1}' AND RBInstance='{2}'", $Query, $ComputerName, $RBInstance)
                }
            }
        }
        'LogDuration' {
            switch ($Stage) {
                'Start' {
                    #region create query for marking StartTime of component
                    $Query = [string]::Format("INSERT INTO [dbo].[ComponentDuration] (ServerName, Component, StartTime, RBInstance, DryRun) VALUES ('{0}', '{1}', '{2}', '{3}', '{4}')", $ComputerName, $Component, $Time, $RBInstance, $DryRun)
                    #endregion create query for marking StartTime of component
                }
                'End' {
                    #region mark EndTime for Component and calculate duration
                    $StartTimeQuery = [string]::Format("SELECT StartTime FROM [dbo].[ComponentDuration] WHERE ServerName = '{0}' AND RBinstance = '{1}' AND EndTime IS NULL", $ComputerName, $RBInstance)
                    $startCompPatchQuerySplat = @{
                        Query     = $StartTimeQuery
                        SQLServer = $SQLServer
                        Database  = $Database
                    }
                    [datetime[]]$StartTime = Start-CompPatchQuery @startCompPatchQuerySplat | Select-Object -ExpandProperty StartTime
                    if ($StartTime) {
                        [string]$StartTime = $StartTime | Sort-Object | Select-Object -Last 1
                        $Query = [string]::Format("UPDATE [dbo].[ComponentDuration] SET EndTime = '{0}' WHERE ServerName = '{1}' AND RBinstance = '{2}' AND Component = '{3}' AND EndTime IS NULL", $Time, $ComputerName, $RBInstance, $Component)
                    }
                    #endregion mark EndTime for Component and calculate duration
                }
            }
        }
    }
    $startCompPatchQuerySplat = @{
        Query     = $Query
        SQLServer = $SQLServer
        Database  = $Database
    }
    Start-CompPatchQuery @startCompPatchQuerySplat
}