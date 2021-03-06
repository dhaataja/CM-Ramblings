function Get-StoredCredential {
    [OutputType([pscredential])]
    param(
        # Purpose of the credential you are trying to retrieve
        [Parameter(Mandatory = $true, ParameterSetName = 'PurposeBased')]
        [ValidateSet('DevExchange', 'Exchange', 'PowerCLI', 'Solarwinds')]
        [string]$Purpose,
        # Purpose of the credential you are trying to retrieve
        [Parameter(Mandatory = $true, ParameterSetName = 'RemotingCredential')]
        [string]$ComputerName,
        [parameter(Mandatory = $true)]
        [string]$SQLServer,
        [parameter(Mandatory = $true)]
        [string]$Database
    )
    switch ($PSCmdlet.ParameterSetName) {
        'PurposeBased' {
            $CredentialQuery = [string]::Format(@"
            DECLARE @RemotingCredentialID UNIQUEIDENTIFIER
            SET @RemotingCredentialID = (SELECT RemotingCredentialID FROM [dbo].[CredentialMap] WHERE CredentialPurpose = '{0}')
            DECLARE @return_value  INT
            EXEC @return_value = [dbo].[GetCredential]
            @UniqueID = @RemotingCredentialID
            SELECT 'Return Value' = @return_value
"@, $Purpose)
        }
        'RemotingCredential' {
            $CredentialQuery = [string]::Format(@"
            DECLARE @RemotingCredentialID UNIQUEIDENTIFIER
            SET @RemotingCredentialID = (SELECT RemotingCredentialID FROM [dbo].[ServerStatus] WHERE ServerName = '{0}')
            DECLARE @return_value  INT
            EXEC @return_value = [dbo].[GetCredential]
            @UniqueID = @RemotingCredentialID
            SELECT 'Return Value' = @return_value
"@, $ComputerName)
        }
    }
    $startCompPatchQuerySplat = @{
        Query           = $CredentialQuery
        SQLServer       = $SQLServer
        AlwaysEncrypted = $true
        Database        = $Database
    }
    $RawCred = Start-CompPatchQuery @startCompPatchQuerySplat
    $UserName = [string]::Format("{0}\{1}", $RawCred.Domain, $RawCred.Username)
    New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, ($RawCred | Select-Object -ExpandProperty Password | ConvertTo-SecureString -AsPlainText -Force)
}