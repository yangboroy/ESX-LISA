###############################################################################
##
## Description:
##  Check the VM OS boot time
##
##
## Revision:
##  v1.0.0 - ldu - 05/18/2020 - Build Scripts
##
###############################################################################


<#
.Synopsis
go_check_dmesg_unknowsymbol

.Description
    <test>
        <testName>go_check_boot_time</testName>
        <testID>ESX-GO-028</testID>
        <testScript>testscripts/go_check_boot_time.ps1</testScript  >
        <files>remote-scripts/utils.sh</files>
        <testParams>
            <param>TC_COVERED=RHEL6-0000,RHEL-186407</param>
        </testParams>
        <RevertDefaultSnapshot>True</RevertDefaultSnapshot>
        <timeout>600</timeout>
        <onError>Continue</onError>
        <noReboot>False</noReboot>
    </test>

.Parameter vmName
    Name of the test VM.

.Parameter testParams
    Semicolon separated list of test parameters.
#>


param([String] $vmName, [String] $hvServer, [String] $testParams)


#
# Checking the input arguments
#
if (-not $vmName)
{
    "Error: VM name cannot be null!"
    exit 100
}

if (-not $hvServer)
{
    "Error: hvServer cannot be null!"
    exit 100
}

if (-not $testParams)
{
    Throw "Error: No test parameters specified"
}


#
# Output test parameters so they are captured in log file
#
"TestParams : '${testParams}'"


#
# Parse the test parameters
#
$rootDir = $null
$sshKey = $null
$ipv4 = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "sshKey"       { $sshKey = $fields[1].Trim() }
    "rootDir"      { $rootDir = $fields[1].Trim() }
    "ipv4"         { $ipv4 = $fields[1].Trim() }
    default        {}
    }
}


#
# Check all parameters are valid
#
if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    if ( (Test-Path -Path "${rootDir}") )
    {
        cd $rootDir
    }
    else
    {
        "Warn : rootdir '${rootDir}' does not exist"
    }
}


#
# Source the tcutils.ps1 file
#
. .\setupscripts\tcutils.ps1

PowerCLIImport
ConnectToVIServer $env:ENVVISIPADDR `
                  $env:ENVVISUSERNAME `
                  $env:ENVVISPASSWORD `
                  $env:ENVVISPROTOCOL


###############################################################################
#
# Main Body
#
###############################################################################
$retVal = $Failed


$vmObj = Get-VMHost -Name $hvServer | Get-VM -Name $vmName
if (-not $vmObj)
{
    LogPrint "ERROR: Unable to Get-VM with $vmName"
    DisconnectWithVIServer
	return $Aborted
}

# Check the guest boot time via systemd-analyze 
$boot_time = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemd-analyze | grep -o -e  '= [1-9]*' | awk '{print `$NF}'"
if ($boot_time -lt 60)
{
    $retVal = $Passed
    LogPrint "INFO: The guest boot time less then 60s, used $boot_time second."
}
else{
    $blame_log = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemd-analyze blame"
    LogPrint "ERROR: After boot, FOUND the boot time more then 60s,used $boot_time second.please check the systemd-analyze blame log $blame_log."
}


DisconnectWithVIServer
return $retVal
