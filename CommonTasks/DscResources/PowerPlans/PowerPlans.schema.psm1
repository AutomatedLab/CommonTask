configuration PowerPlans
{
    param
    (
        [Parameter()]
        [hashtable[]]
        $Plans,

        [Parameter()]
        [hashtable[]]
        $Settings
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName DSCR_PowerPlan

    foreach ($pwrPlan in $Plans)
    {
        # Remove Case Sensitivity of ordered Dictionary or Hashtables
        $pwrPlan = @{}+$pwrPlan

        if (-not $pwrPlan.ContainsKey('Ensure'))
        {
            $pwrPlan.Ensure = 'Present'
        }

        $executionName = "pwrplan_$($pwrPlan.GUID -replace '[{}\-\s]','')"

        (Get-DscSplattedResource -ResourceName cPowerPlan -ExecutionName $executionName -Properties $pwrPlan -NoInvoke).Invoke($pwrPlan)
    }

    foreach ($pwrSetting in $Settings)
    {
        # Remove Case Sensitivity of ordered Dictionary or Hashtables
        $pwrSetting = @{}+$pwrSetting

        $executionName = "pwrsetting_$($pwrSetting.PlanGuid -replace '[{}\-\s]','')_$($pwrSetting.SettingGuid -replace '[{}\-\s]','')"

        (Get-DscSplattedResource -ResourceName cPowerPlanSetting -ExecutionName $executionName -Properties $pwrSetting -NoInvoke).Invoke($pwrSetting)
    }
}
