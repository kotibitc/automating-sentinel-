Param(
[string][parameter(Mandatory=$false,HelpMessage="SubscriptioId of the Tenant where we are willing to link log analytics to sentinel")]$SubscriptionId,
[string][Parameter(Mandatory=$false)]$WorkspaceName,
[string][Parameter(Mandatory=$false)]$Sentinelalertfile,
[string][Parameter(Mandatory=$false)]$SentinelHuntingalertfile,
[string][Parameter(Mandatory=$false)]$Inputfile="Inputparameters.csv"
)

  $Azmodule= (Get-Module -Name Az -ListAvailable).Version
if($Azmodule)
{
    Write-Host "Az module exist with version $($Azmodule.Major):$($Azmodule.Minor):$($Azmodule.Revision)"
}
else
{
    Write-Host "Installing Az module"
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force -Verbose
}
$powershellyamlmodule=Get-Module -Name powershell-yaml -ListAvailable
if(!$powershellyamlmodule)
{
    Write-Host "Installing powershell-yaml module"
    Install-Module -Name powershell-yaml -Force -AllowClobber
}
else
{
    Write-Host "exist powershell-yaml module"
}
$AzSentinelmodule=Get-Module -Name AzSentinel -ListAvailable
if(!$AzSentinelmodule)
{
    Write-Host "Installing AzSentinel module"
    Install-Module AzSentinel -Scope CurrentUser -Force -AllowClobber -Verbose
}
else
{
    Write-Host "exist AzSentinel module"
}
Import-Module AzSentinel
Set-Location $PSScriptRoot
$RootFolder = Split-Path $MyInvocation.MyCommand.Path
$Sentinelalertfile=$RootFolder + "\sentinelalertrules.json"
$SentinelHuntingalertfile=$RootFolder + "\allhuntingrules.json"
$ParameterCSVPath =  $RootFolder + "\Inputparameters.csv"
Function Main()
{
    try
    {
        $csv = Import-Csv $ParameterCSVPath
        $TenantId=$csv.Where({$PSItem.parameter -eq 'TenantId'}).value
        $SubscriptionId=$csv.Where({$PSItem.parameter -eq 'SubscriptionId'}).value
        $ClientId=$csv.Where({$PSItem.parameter -eq 'ClientId'}).value
        $ClientSecret=$csv.Where({$PSItem.parameter -eq 'ClientSecret'}).value
        $WorkspaceName=$csv.Where({$PSItem.parameter -eq 'WorkspaceName'}).value
        $passwd = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $pscredential = New-Object System.Management.Automation.PSCredential($ClientId, $passwd)
        Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $TenantId
        Set-AzContext -Subscription $SubscriptionId -Tenant $TenantId | Out-Null
        Write-Host "Checking for workspace enabled with sentinetl or not. if not enabled  enabling it" -ForegroundColor Yellow
        Set-AzSentinel -SubscriptionId $SubscriptionId -WorkspaceName $WorkspaceName -confirm:$false
        $azurealert= Get-Content  $Sentinelalertfile | ConvertFrom-Json
        $azurehuntingrule= Get-Content $SentinelHuntingalertfile | ConvertFrom-Json
        foreach($item in $azurealert)
        {
         $sentinelalerte= Get-AzSentinelAlertRule -SubscriptionId $SubscriptionId -WorkspaceName $WorkspaceName -RuleName $item.displayName
         if(!$sentinelalerte)
         {
             $queryFrequency =$item.queryFrequency
             $qf = $queryFrequency -replace 'PT',''
             $queryPeriod=$item.queryPeriod
             $qp = $queryPeriod -replace 'PT',''
             $suppressionDuration=$item.suppressionDuration
             $sd = $suppressionDuration -replace 'PT',''
             Write-host "Creating sentinel alert $($item.displayName)" -ForegroundColor Yellow
             try
             {
             New-AzSentinelAlertRule -SubscriptionId $SubscriptionId -WorkspaceName $WorkspaceName  -DisplayName $item.displayName `
                                     -Description $item.description -Severity $item.severity -Enabled $item.enabled -Query $item.query -QueryFrequency $qf `
                                     -QueryPeriod $qp -TriggerOperator $item.triggerOperator -TriggerThreshold $item.triggerThreshold -SuppressionDuration $sd -SuppressionEnabled $item.suppressionEnabled -Tactics $item.tactics -Confirm:$false -ErrorAction SilentlyContinue
             }
             catch
             {
                continue
             }
            Write-Host "Created sentinel alert $($item.displayName)" -ForegroundColor Green
         }
         else
         {
            Write-Output "Sentinel alert $($item.displayName) is exists"
         }

       }
        foreach($huntingalert in $azurehuntingrule)
        {
            $sentinelhuntingalert=Get-AzSentinelHuntingRule -SubscriptionId $SubscriptionId -WorkspaceName $WorkspaceName -RuleName $huntingalert.displayName
            if(!$sentinelhuntingalert)
            {
                try 
                {
                    Write-Host "Creating sentinel alert $($huntingalert.displayName)" -ForegroundColor Yellow
                    New-AzSentinelHuntingRule -SubscriptionId $SubscriptionId  -WorkspaceName $WorkspaceName  -DisplayName $huntingalert.displayName -Query $huntingalert.query -Description $huntingalert.Description -Tactics $huntingalert.Tactics -Confirm:$false
                    Write-Host "Created sentinel alert $($item.displayName)" -ForegroundColor Green
                }
                catch
                {
                    continue
                }
            }
            else
            {
                Write-Output "Sentinel alert $($huntingalert.displayName) is exists"
            }
        }
    }
    catch
    {
        throw $_.exception
    }
    finally
    {
    }
}

Main