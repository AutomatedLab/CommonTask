configuration HostsFileEntries
{
    param
    (
        [Parameter(Mandatory)]
        [hashtable[]]
        $Entries
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName NetworkingDsc

    foreach ($entry in $Entries)
    {
        # Remove Case Sensitivity of ordered Dictionary or Hashtables
        $entry = @{}+$entry

        if (-not $entry.ContainsKey('Ensure'))
        {
            $entry.Ensure = 'Present'
        }

        $executionName = "hosts_$($entry.Hostname)"

        (Get-DscSplattedResource -ResourceName HostsFile -ExecutionName $executionName -Properties $entry -NoInvoke).Invoke($entry)
    }
}
