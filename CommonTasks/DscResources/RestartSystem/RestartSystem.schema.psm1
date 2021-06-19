configuration RestartSystem
{
    param
    (
        [Parameter()]
        [Boolean]
        $ForceReboot = $false,
     
        [Parameter()]
        [Boolean]
        $PendingReboot = $false,

        [Parameter()]
        [Boolean]
        $SkipComponentBasedServicing = $false,

        [Parameter()]
        [Boolean]
        $SkipWindowsUpdate = $false,

        [Parameter()]
        [Boolean]
        $SkipPendingFileRename = $false,

        [Parameter()]
        [Boolean]
        $SkipPendingComputerRename = $false,

        [Parameter()]
        [Boolean]
        $SkipCcmClientSDK = $true
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDsc

    if( $PendingReboot -eq $true )
    {
        PendingReboot CheckPendingReboot
        {
            Name                        = 'CheckPendingReboot'
            SkipComponentBasedServicing = $SkipComponentBasedServicing
            SkipWindowsUpdate           = $SkipWindowsUpdate
            SkipPendingFileRename       = $SkipPendingFileRename
            SkipPendingComputerRename   = $SkipPendingComputerRename
            SkipCcmClientSDK            = $SkipCcmClientSDK
        }
    }

    if( $ForceReboot -eq $true )
    {
        $rebootKeyName = 'HKLM:\SOFTWARE\DSC Community\CommonTasks\RebootRequests'
        $rebootVarName = 'Reboot_RestartSystem'

        Script $rebootVarName
        {
            TestScript = {
                $val = Get-ItemProperty -Path $using:rebootKeyName -Name $using:rebootVarName -ErrorAction SilentlyContinue

                if ($null -ne $val -and $val.$using:rebootVarName -gt 0) 
                { 
                    return $true
                }   
                return $false
            }
            SetScript = {
                if( -not (Test-Path -Path $using:rebootKeyName) )
                {
                    New-Item -Path $using:rebootKeyName -Force
                }
                Set-ItemProperty -Path $using:rebootKeyName -Name $using:rebootVarName -value 1
                $global:DSCMachineStatus = 1             
            }
            GetScript = { return @{result = 'result'}}
        }        
    }
}
