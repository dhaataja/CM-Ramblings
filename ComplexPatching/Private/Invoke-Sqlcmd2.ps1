function Invoke-Sqlcmd2 {
    [CmdletBinding(DefaultParameterSetName = 'Ins-Que')]
    [OutputType([System.Management.Automation.PSCustomObject], [System.Data.DataRow], [System.Data.DataTable], [System.Data.DataTableCollection], [System.Data.DataSet])]
    param (
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQL Server Instance required...')]
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQL Server Instance required...')]
        [Alias('Instance', 'Instances', 'ComputerName', 'Server', 'Servers')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ServerInstance,
        [Parameter(Position = 1,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [string]$Database,
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 2,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Con-Que',
            Position = 2,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [string]$Query,
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 2,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Con-Fil',
            Position = 2,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [ValidateScript( {
                Test-Path $_
            })]
        [string]$InputFile,
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 3,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 3,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 4,
            Mandatory = $false,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 4,
            Mandatory = $false,
            ValueFromRemainingArguments = $false)]
        [switch]$Encrypt,
        [Parameter(Position = 5,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Int32]$QueryTimeout = 600,
        [Parameter(ParameterSetName = 'Ins-Fil',
            Position = 6,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 6,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [Int32]$ConnectionTimeout = 15,
        [Parameter(Position = 7,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "SingleValue")]
        [string]$As = "DataRow",
        [Parameter(Position = 8,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [System.Collections.IDictionary]$SqlParameters,
        [Parameter(Position = 9,
            Mandatory = $false)]
        [switch]$AppendServerInstance,
        [Parameter(ParameterSetName = 'Con-Que',
            Position = 10,
            Mandatory = $false,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $false,
            ValueFromRemainingArguments = $false)]
        [Parameter(ParameterSetName = 'Con-Fil',
            Position = 10,
            Mandatory = $false,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $false,
            ValueFromRemainingArguments = $false)]
        [Alias('Connection', 'Conn')]
        [ValidateNotNullOrEmpty()]
        [System.Data.SqlClient.SQLConnection]$SQLConnection,
        [Parameter(ParameterSetName = 'Ins-Que',
            Position = 11,
            Mandatory = $false,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $false,
            ValueFromRemainingArguments = $false)]
        [switch]$AlwaysEncrypted
    )
	
    Begin {
        if ($InputFile) {
            $filePath = $(Resolve-Path $InputFile).path
            $Query = [System.IO.File]::ReadAllText("$filePath")
        }
		
        Write-Verbose "Running Invoke-Sqlcmd2 with ParameterSet '$($PSCmdlet.ParameterSetName)'.  Performing query '$Query'"
		
        If ($As -eq "PSObject") {
            #This code scrubs DBNulls.  Props to Dave Wyatt
            $cSharp = @'
                using System;
                using System.Data;
                using System.Management.Automation;

                public class DBNullScrubber
                {
                    public static PSObject DataRowToPSObject(DataRow row)
                    {
                        PSObject psObject = new PSObject();

                        if (row != null && (row.RowState & DataRowState.Detached) != DataRowState.Detached)
                        {
                            foreach (DataColumn column in row.Table.Columns)
                            {
                                Object value = null;
                                if (!row.IsNull(column))
                                {
                                    value = row[column];
                                }

                                psObject.Properties.Add(new PSNoteProperty(column.ColumnName, value));
                            }
                        }

                        return psObject;
                    }
                }
'@
			
            Try {
                Add-Type -TypeDefinition $cSharp -ReferencedAssemblies 'System.Data', 'System.Xml' -ErrorAction stop
            }
            Catch {
                If (-not $_.ToString() -like "*The type name 'DBNullScrubber' already exists*") {
                    Write-Warning "Could not load DBNullScrubber.  Defaulting to DataRow output: $_"
                    $As = "Datarow"
                }
            }
        }
		
        #Handle existing connections
        if ($PSBoundParameters.ContainsKey('SQLConnection')) {
            if ($SQLConnection.State -notlike "Open") {
                Try {
                    Write-Verbose "Opening connection from '$($SQLConnection.State)' state"
                    $SQLConnection.Open()
                }
                Catch {
                    Throw $_
                }
            }
			
            if ($Database -and $SQLConnection.Database -notlike $Database) {
                Try {
                    Write-Verbose "Changing SQLConnection database from '$($SQLConnection.Database)' to $Database"
                    $SQLConnection.ChangeDatabase($Database)
                }
                Catch {
                    Throw "Could not change Connection database '$($SQLConnection.Database)' to $Database`: $_"
                }
            }
			
            if ($SQLConnection.state -like "Open") {
                $ServerInstance = @($SQLConnection.DataSource)
            }
            else {
                Throw "SQLConnection is not open"
            }
        }
		
    }
    Process {
        foreach ($SQLInstance in $ServerInstance) {
            Write-Verbose "Querying ServerInstance '$SQLInstance'"
			
            if ($PSBoundParameters.Keys -contains "SQLConnection") {
                $Conn = $SQLConnection
            }
            else {
                if ($Credential) {
                    $ConnectionString = "Server={0};Database={1};User ID={2};Password=`"{3}`";Trusted_Connection=False;Connect Timeout={4};Encrypt={5}" -f $SQLInstance, $Database, $Credential.UserName, $Credential.GetNetworkCredential().Password, $ConnectionTimeout, $Encrypt
                }
                else {
                    $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2};Encrypt={3}" -f $SQLInstance, $Database, $ConnectionTimeout, $Encrypt
                }
                if ($AlwaysEncrypted) {
                    $ConnectionString = "{0};Column Encryption Setting = Enabled" -f $ConnectionString
                }
				
                $conn = New-Object System.Data.SqlClient.SQLConnection
                $conn.ConnectionString = $ConnectionString
                Write-Debug "ConnectionString $ConnectionString"
				
                Try {
                    $conn.Open()
                }
                Catch {
                    Write-Error $_
                    continue
                }
            }
			
            #Following EventHandler is used for PRINT and RAISERROR T-SQL statements. Executed when -Verbose parameter specified by caller
            if ($PSBoundParameters.Verbose) {
                $conn.FireInfoMessageEventOnUserErrors = $false # Shiyang, $true will change the SQL exception to information
                $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] {
                    Write-Verbose "$($_)"
                }
                $conn.add_InfoMessage($handler)
            }
			
            $cmd = New-Object system.Data.SqlClient.SqlCommand($Query, $conn)
            $cmd.CommandTimeout = $QueryTimeout
			
            if ($null -ne $SqlParameters) {
                $SqlParameters.GetEnumerator() |
                ForEach-Object {
                    If ($null -ne $_.Value) {
                        $cmd.Parameters.AddWithValue($_.Key, $_.Value)
                    }
                    Else {
                        $cmd.Parameters.AddWithValue($_.Key, [DBNull]::Value)
                    }
                } > $null
            }
			
            $ds = New-Object system.Data.DataSet
            $da = New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
			
            Try {
                [void]$da.fill($ds)
            }
            Catch [System.Data.SqlClient.SqlException] {
                # For SQL exception
                $Err = $_
				
                Write-Verbose "Capture SQL Error"
				
                if ($PSBoundParameters.Verbose) {
                    Write-Verbose "SQL Error:  $Err"
                } #Shiyang, add the verbose output of exception
				
                switch ($ErrorActionPreference.tostring()) {
                    {
                        'SilentlyContinue', 'Ignore' -contains $_
                    } {
                    }
                    'Stop' {
                        Throw $Err
                    }
                    'Continue' {
                        Throw $Err
                    }
                    Default {
                        Throw $Err
                    }
                }
            }
            Catch {
                # For other exception
                Write-Verbose "Capture Other Error"
				
                $Err = $_
				
                if ($PSBoundParameters.Verbose) {
                    Write-Verbose "Other Error:  $Err"
                }
				
                switch ($ErrorActionPreference.tostring()) {
                    {
                        'SilentlyContinue', 'Ignore' -contains $_
                    } {
                    }
                    'Stop' {
                        Throw $Err
                    }
                    'Continue' {
                        Throw $Err
                    }
                    Default {
                        Throw $Err
                    }
                }
            }
            Finally {
                #Close the connection
                if (-not $PSBoundParameters.ContainsKey('SQLConnection')) {
                    $conn.Close()
                }
            }
			
            if ($AppendServerInstance) {
                #Basics from Chad Miller
                $Column = New-Object Data.DataColumn
                $Column.ColumnName = "ServerInstance"
                $ds.Tables[0].Columns.Add($Column)
                Foreach ($row in $ds.Tables[0]) {
                    $row.ServerInstance = $SQLInstance
                }
            }
			
            switch ($As) {
                'DataSet' {
                    $ds
                }
                'DataTable' {
                    $ds.Tables
                }
                'DataRow' {
                    $ds.Tables[0]
                }
                'PSObject' {
                    #Scrub DBNulls - Provides convenient results you can use comparisons with
                    #Introduces overhead (e.g. ~2000 rows w/ ~80 columns went from .15 Seconds to .65 Seconds - depending on your data could be much more!)
                    foreach ($row in $ds.Tables[0].Rows) {
                        [DBNullScrubber]::DataRowToPSObject($row)
                    }
                }
                'SingleValue' {
                    $ds.Tables[0] | Select-Object -ExpandProperty $ds.Tables[0].Columns[0].ColumnName
                }
            }
        }
    }
}