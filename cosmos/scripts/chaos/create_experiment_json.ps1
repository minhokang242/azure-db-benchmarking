<#
.SYNOPSIS
    Creates a JSON file for a chaos experiment.

.DESCRIPTION
    This script creates a JSON file that defines a chaos experiment. The experiment can be used to simulate faults and test the resiliency of Azure resources.

.PARAMETER filterString
    Specifies the filter string to select the target resources for the chaos experiment.

.PARAMETER durationOfFaultInMinutes
    Specifies the duration of the fault in minutes. During this time, the selected resources will experience simulated faults.

.PARAMETER faultRegion
    Specifies the region where the faults will be simulated. Only resources in this region will be affected.

.PARAMETER resourceGroup
    Specifies the name of the resource group containing the target resources.

.PARAMETER subscriptionId
    Specifies the ID of the Azure subscription containing the target resources.

.PARAMETER delayInMs
    Specifies the delay in milliseconds between each fault injection.

.PARAMETER chaosExperimentManagedIdentityName
    Specifies the name of the managed identity used to authenticate with Azure resources.

.PARAMETER experimentName
    Specifies the name of the chaos experiment.

.PARAMETER targetVMSubRGNameList
    Specifies a comma-separated list of names for the target virtual machines in the format: "subscriptionId/resourceGroup/virtualMachineName".

.PARAMETER targetVMSSSubRGName
    Specifies the name for the target virtual machine scale set in the format: "subscriptionId/resourceGroup/virtualMachineScaleSetName". Only one virtual machine scale set can be specified.

.PARAMETER vmssInstanceIdList
    Specifies a comma-separated list of instance IDs for the target virtual machine scale set.

.EXAMPLE
    create_experiment_json.ps1 -filterString "<destinationFliterList>" -durationOfFaultInMinutes 60 -faultRegion "eastus" -resourceGroup "myResourceGroup" -subscriptionId "12345678-1234-1234-1234-1234567890ab" -delayInMs 1000 -chaosExperimentManagedIdentityName "myManagedIdentity" -experimentName "MyExperiment" -targetVMSubRGNameList "sub1/RG1/VM1,sub2/RG2/VM2" -targetVMSSSubRGName "sub1/RG1/VMSS" -vmssInstanceIdList "1,2,3"

.NOTES
    Author: Darshan Patnekar
    Date: 02/08/2024
    Version: 1.0
#>

param (
    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $filterString,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $durationOfFaultInMinutes,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $faultRegion,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $resourceGroup,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $subscriptionId,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $delayInMs,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $chaosExperimentManagedIdentityName,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string] $experimentName,

    [string] $targetVMSubRGNameList,
    [string] $targetVMSSSubRGName,
    [string] $vmssInstanceIdList

)

# Function to create the targetId for the experiment
function create_targetId {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [string] $inputString,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [string] $computeType
    )

    try {
        $parts = $inputString -split '/'
        $subscriptionId = $parts[0]
        $resourceGroupName = $parts[1]
        $vmName = $parts[2]

        $targetId = "/subscriptions/" + $subscriptionId + "/resourceGroups/" + $resourceGroupName + "/providers/Microsoft.Compute/$computeType/" + $vmName + "/providers/Microsoft.Chaos/targets/Microsoft-Agent"
        return $targetId
    }
    catch {
        Write-Error "An error occurred while creating the targetId: $_"
    }
}

$json = ""
$experimentIdPrefix = "/subscriptions/" + $subscriptionId + "/resourceGroups/" + $resourceGroup + "/providers/Microsoft.Chaos/experiments/"
$jsonPath = ""

try {
    if ($delayInMs -and $delayInMs -gt 0)
    {
        $jsonPath = 'network-delay-fault.json'
        $json = Get-Content -Path $jsonPath | ConvertFrom-Json
        $json.name = $experimentName
        $json.id = $experimentIdPrefix + $experimentName
        if ($json.properties.steps[0].branches[0].actions[0].parameters)
        {
            foreach ($parameter in $json.properties.steps[0].branches[0].actions[0].parameters) {
                if ($parameter.key -eq "latencyInMilliseconds") {
                    $parameter.value = $delayInMs
                    break
                }
            }
        }
    }
    else {
        $jsonPath = 'network-disconnect-fault.json'
        $json = Get-Content -Path $jsonPath | ConvertFrom-Json
        $json.name = $experimentName
        $json.id = $experimentIdPrefix + $experimentName
    }

    # Set the identity for the experiment 
    $json.identity = @{
        "type" = "UserAssigned"
        "userAssignedIdentities"= @{
            "/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$chaosExperimentManagedIdentityName"= @{}
        }
    }

    # Set the location of the experiment
    if ($faultRegion)
    {
        $faultRegion = $faultRegion -replace '\s', '' # Remove whitespace
        $json.location = $faultRegion
    }

    # Set the duration of the experiment
    if ($durationOfFaultInMinutes)
    {
        $json.properties.steps[0].branches[0].actions[0].duration = "PT" + $durationOfFaultInMinutes +"M"
    }

    # Set the targets for the experiment
    $targetIndex = 0
    if ($targetVMSubRGNameList) {
        $targets = $targetVMSubRGNameList -split ","

        foreach ($target in $targets) {
            $targetId = create_targetId -inputString $target -computeType "virtualMachines"
            $json.properties.selectors[0].targets[$targetIndex].id = $targetId
            $json.properties.selectors[0].targets[$targetIndex].type = "ChaosTarget"
            $targetIndex++
        }
    }

    if ($targetVMSSSubRGName) {
        $targetId = create_targetId -inputString $targetVMSSSubRGName -computeType "virtualMachineScaleSets"
        $json.properties.selectors[0].targets[$targetIndex].id = $targetId
        $json.properties.selectors[0].targets[$targetIndex].type = "ChaosTarget"
        $targetIndex++
    }

    # Set the destinationFilters and virtualMachineScaleSetInstances for the experiment
    if ($json.properties.steps[0].branches[0].actions[0].parameters)
    {
        foreach ($parameter in $json.properties.steps[0].branches[0].actions[0].parameters) {
            switch ($parameter.key) {
                "destinationFilters" {
                    $parameter.value = $filterString
                    break
                }
                "virtualMachineScaleSetInstances" {
                    $parameter.value = $vmssInstanceIdList
                    break
                }
            }
        }
    }

    # Convert the modified PowerShell object back to JSON
    $newJson = ConvertTo-Json -InputObject $json -Depth 20

    # Remove the escape characters
    $newJson = $newJson.Replace('\\\','\')

    # Write the new JSON back to the file
    $newJson | Set-Content -Path $jsonPath

    # Return the updated experiment JSON
    return Get-Content -Path $jsonPath -Raw
}
catch {
    Write-Error "An error occurred while creating the experiment JSON: $_"
}

