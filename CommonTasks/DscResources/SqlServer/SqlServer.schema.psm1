configuration SqlServer
{
    param
    (
        [Parameter()]
        [String]$DefaultInstanceName = 'MSSQLSERVER',
        
        [Parameter()]
        [hashtable]
        $Setup,

        [Parameter()]
        [hashtable[]]
        $SqlLogins
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName SqlServerDsc

    if( $null -ne $Setup )
    {
        # Remove Case Sensitivity of ordered Dictionary or Hashtables
        $Setup = @{}+$Setup

        if( [string]::IsNullOrWhiteSpace($Setup.InstanceName)  )
        {
            $Setup.InstanceName = $DefaultInstanceName
        }

        # remove an empty Productkey
        if( [string]::IsNullOrWhiteSpace($Setup.ProductKey) )
        {
            $Setup.Remove('ProductKey')
        }

        # FileStreamAccessLevel is not supported by SqlSetup and must be enabled later
        $fileStreamAccessLevel = $Setup.FileStreamAccessLevel
        $Setup.Remove( 'FileStreamAccessLevel' )

        (Get-DscSplattedResource -ResourceName SqlSetup -ExecutionName "sqlSetup" -Properties $Setup -NoInvoke).Invoke($Setup)

        # enable/disable FileStream
        if( $null -ne $fileStreamAccessLevel )
        {        
            [string]$instanceName = $Setup.InstanceName

            Script sqlFileStreamAccess
            {
                TestScript = 
                {
                    # get installed SQL Server version
                    [string]$cmgmt = (Get-CimInstance -NameSpace 'ROOT\Microsoft\SQLServer' -Class “__NAMESPACE” | Where-Object { $_.Name.StartsWith( 'ComputerManagement' ) }).Name

                    $cim = Get-CimInstance -Namespace "ROOT\Microsoft\SqlServer\$cmgmt" -Class FilestreamSettings | Where-Object {$_.InstanceName -eq $using:instanceName}

                    Write-Verbose "Expected FilestreamAccessLevel is: $using:fileStreamAccessLevel"
 
                    Write-Verbose "Current FilestreamAccessLevel is: $($cim.AccessLevel) with file share name '$($cim.ShareName)'."
                   
                    if( $cim.AccessLevel -eq $using:fileStreamAccessLevel )
                    {
                        $sqlServer = "localhost$( if($using:instanceName -ne 'MSSQLSERVER') { "\$using:instanceName" })"

                        $sqlFileStreamAccessLevel = Invoke-Sqlcmd "SELECT SERVERPROPERTY( 'FilestreamEffectiveLevel' ) AS FileStreamAccessLevel" -ServerInstance $sqlServer | `
                                                    Select-Object -ExpandProperty FileStreamAccessLevel

                        Write-Verbose "The current SERVERPROPERTY 'FilestreamEffectiveLevel' is: $sqlFileStreamAccessLevel."

                        if( $sqlFileStreamAccessLevel -eq $using:fileStreamAccessLevel )
                        {
                            return $true
                        }
                    }

                    return $false
                }
                SetScript = 
                {
                    # get installed SQL Server version
                    [string]$cmgmt = (Get-CimInstance -NameSpace 'ROOT\Microsoft\SQLServer' -Class “__NAMESPACE” | Where-Object { $_.Name.StartsWith( 'ComputerManagement' ) }).Name

                    $cim = Get-CimInstance -Namespace "ROOT\Microsoft\SqlServer\$cmgmt" -Class FilestreamSettings | Where-Object {$_.InstanceName -eq $using:instanceName}

                    Write-Verbose "Set FilestreamAccessLevel to: $using:fileStreamAccessLevel."

                    Invoke-CimMethod -InputObject $cim -MethodName 'EnableFilestream' `
                                     -Arguments @{ AccessLevel = $using:fileStreamAccessLevel; ShareName = $using:instanceName }

                    Get-Service -Name $using:instanceName | Restart-Service -Force
                     
                    $sqlServer = "localhost$( if($using:instanceName -ne 'MSSQLSERVER') { "\$using:instanceName" })"

                    Invoke-Sqlcmd -Query "EXEC sp_configure filestream_access_level, $((2,$using:fileStreamAccessLevel | Measure-Object -Min).Minimum)" -ServerInstance $sqlServer
                    Invoke-Sqlcmd -Query "RECONFIGURE" -ServerInstance $sqlServer
                }
                GetScript = { return 'NA' }   
                DependsOn = '[SqlSetup]sqlSetup'
            }
        }
    }


    if( $null -ne $SqlLogins )
    {
        foreach( $login in $SqlLogins )
        {
            # Remove Case Sensitivity of ordered Dictionary or Hashtables
            $login = @{}+$login

            if( -not $login.ContainsKey('Ensure') )
            {
                $login.Ensure = 'Present'
            }

            if( [string]::IsNullOrWhiteSpace($login.InstanceName) )
            {
                $login.InstanceName = $DefaultInstanceName
            }
            
            $executionName = "sqllogin_$($login.Name -replace '[().:\s]', '_')" 
            (Get-DscSplattedResource -ResourceName SqlLogin -ExecutionName $executionName -Properties $login -NoInvoke).Invoke($login)
        }
    }
}
