configuration Wds
{
    param
    (
        [Parameter(Mandatory)]
        [string]
        $RemInstPath,

        [Parameter(Mandatory=$false)]
        [pscredential]
        $RunAsUser = $null,

        [Parameter(Mandatory=$false)]
        [boolean]
        $UseExistingDhcpScope = $false,

        [Parameter(Mandatory=$false)]
        [string]
        $ScopeStart,

        [Parameter(Mandatory=$false)]
        [string]
        $ScopeEnd,

        [Parameter(Mandatory=$false)]
        [string]
        $ScopeId,

        [Parameter(Mandatory=$false)]
        [string]
        $SubnetMask,

        [Parameter(Mandatory=$false)]
        [string]
        $DomainName,

        [Parameter(Mandatory=$false)]
        [string]
        $DefaultDeviceOU,

        [Parameter(Mandatory=$false)]
        [hashtable[]]
        $BootImages,

        [Parameter(Mandatory=$false)]
        [hashtable[]]
        $InstallImages,

        [Parameter(Mandatory=$false)]
        [hashtable[]]
        $DeviceReservations
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName WdsDsc
    Import-DscResource -ModuleName xDhcpServer

    $dependsOnClientScope = ''

    if( $UseExistingDhcpScope -eq $false )
    {
        WindowsFeature dhcpFeature
        {
            Name   = 'DHCP'
            IncludeAllSubFeature = $true
            Ensure = 'Present'
        }

        xDhcpServerScope clientScope
        {
            ScopeId      = $ScopeId
            IPStartRange = $ScopeStart
            IPEndRange   = $ScopeEnd
            SubnetMask   = $SubnetMask
            Name         = 'WdsClients'
            Ensure       = 'Present'
            DependsOn    = '[WindowsFeature]dhcpFeature'
        }

        $dependsOnClientScope = '[xDhcpServerScope]clientScope'
    }
    else
    {
        if( -not [string]::IsNullOrWhiteSpace($ScopeStart) -or
            -not [string]::IsNullOrWhiteSpace($ScopeEnd) -or
            -not [string]::IsNullOrWhiteSpace($SubnetMask) )
        {
            throw "ERROR: if 'UseExistingDhcpScope' is set to 'true' the DHCP scope definition shall be empty."
        }
    }

    WindowsFeature wdsFeature
    {
        Name                 = 'WDS'
        IncludeAllSubFeature = $true
        Ensure               = 'Present'
    }

    WdsInitialize wdsInit
    {
        IsSingleInstance     = 'Yes'
        PsDscRunAsCredential = $runAsCred
        Path                 = $RemInstPath
        Authorized           = $true
        Standalone           = $false
        Ensure               = 'Present'
        DependsOn            = '[WindowsFeature]wdsFeature'
    }

    $dependsOnWdsInit = '[WdsInitialize]wdsInit'

    if( $null -ne $BootImages )
    {
        foreach( $image in $BootImages )
        {
            $image.DependsOn = $dependsOnWdsInit
            $executionName = "bootImg_$($image.NewImageName -replace '[().:\s]', '')"

            (Get-DscSplattedResource -ResourceName WdsBootImage -ExecutionName $executionName -Properties $image -NoInvoke).Invoke($image)
        }
    }

    if( $null -ne $InstallImages )
    {
        foreach( $image in $InstallImages )
        {
            $image.DependsOn = $dependsOnWdsInit
            $executionName = "instImg_$($image.NewImageName -replace '[().:\s]', '')"

            (Get-DscSplattedResource -ResourceName WdsInstallImage -ExecutionName $executionName -Properties $image -NoInvoke).Invoke($image)
        }
    }

    if( $null -ne $DeviceReservations )
    {
        foreach( $devRes in $DeviceReservations )
        {
            # Remove Case Sensitivity of ordered Dictionary or Hashtables
            $devRes = @{}+$devRes

            if( -not $devRes.ContainsKey('Ensure') )
            {
                $devRes.Ensure = 'Present'
            }

            # make a DHCP reservation
            if( -not [string]::IsNullOrWhiteSpace($devRes.IpAddress) )
            {
                if( [string]::IsNullOrWhiteSpace($ScopeId) )
                {
                    throw "ERROR: if 'IpAddress' is specified the parameter ScopeId is required to make a DHCP reservation."
                }

                xDhcpServerReservation "dhcpRes_$($devRes.DeviceName -replace '[().:\s]', '')"
                {
                    IPAddress        = $devRes.IpAddress
                    ClientMACAddress = $devRes.MacAddress
                    Name             = $devRes.DeviceName
                    ScopeID          = $ScopeId
                    Ensure           = $devRes.Ensure
                    DependsOn        = $dependsOnClientScope
                }                
            }

            $devRes.DeviceID  = $devRes.MacAddress
            $devRes.DependsOn = $dependsOnWdsInit

            $devRes.Remove('IpAddress')
            $devRes.Remove('MacAddress')

            if( $devRes.JoinDomain -eq $true )
            {
                if( [string]::IsNullOrWhiteSpace($DomainName) )
                {
                    throw "ERROR: DomainName shall be specified to make a domain join."
                }

                $devRes.Domain = $DomainName

                if( -not [string]::IsNullOrWhiteSpace($DefaultDeviceOU) -and [string]::IsNullOrWhiteSpace($devRes.OU))
                {
                    $devRes.OU = $DefaultDeviceOU
                }

                if( [string]::IsNullOrWhiteSpace($devRes.JoinRights) )
                {
                    $devRes.JoinRights = 'JoinOnly'
                }
            }

            if( [string]::IsNullOrWhiteSpace($devRes.PxePromptPolicy) )
            {
                $devRes.PxePromptPolicy = 'NoPrompt'
            }

            $executionName = "wdsRes_$($devRes.DeviceName -replace '[().:\s]', '')"

            (Get-DscSplattedResource -ResourceName WdsDeviceReservation -ExecutionName $executionName -Properties $devRes -NoInvoke).Invoke($devRes)
        }
    }
}
