########################################################################################
## Description:
##  
##
## Revision:
##  v1.0.0 - ldu - 12/09/2019 - Build the script
##  v1.1.0 - ldu - 01/02/2020 - add remove clone vm function
##  v2.0.0 - ldu - 18/02/2020 - Redesign the case to use nonpersistent OS spec
########################################################################################


<#
.Synopsis
   

.Description
<test>
        <testName>ovt_customization_static</testName>
        <testID>ESX-ovt-037</testID>
        <setupScript>setupscripts\add_vmxnet3.ps1</setupScript>
        <testScript>testscripts/ovt_customization_static.ps1</testScript  >
        <files>remote-scripts/utils.sh</files>
        <testParams>
            <param>nicName=auto-test</param>
            <param>TC_COVERED=RHEL6-0000,RHEL-180199</param>
        </testParams>
        <RevertDefaultSnapshot>True</RevertDefaultSnapshot>
        <timeout>1800</timeout>
        <onError>Continue</onError>
        <noReboot>False</noReboot>
    </test>

.Parameter vmName
    Name of the test VM.

.Parameter testParams
    Semicolon separated list of test parameters.
#>


param([String] $vmName, [String] $hvServer, [String] $testParams)


# Checking the input arguments
if (-not $vmName) {
    "Error: VM name cannot be null!"
    exit 100
}

if (-not $hvServer) {
    "Error: hvServer cannot be null!"
    exit 100
}

if (-not $testParams) {
    Throw "Error: No test parameters specified"
}


# Output test parameters so they are captured in log file
"TestParams : '${testParams}'"


# Parse the test parameters
$rootDir = $null
$sshKey = $null
$ipv4 = $null

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    switch ($fields[0].Trim()) {
        "sshKey" { $sshKey = $fields[1].Trim() }
        "rootDir" { $rootDir = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }
        default {}
    }
}


# Check all parameters are valid
if (-not $rootDir) {
    "Warn : no rootdir was specified"
}
else {
    if ( (Test-Path -Path "${rootDir}") ) {
        Set-Location $rootDir
    }
    else {
        "Warn : rootdir '${rootDir}' does not exist"
    }
}


if ($null -eq $sshKey) {
    "FAIL: Test parameter sshKey was not specified"
    return $False
}


if ($null -eq $ipv4) {
    "FAIL: Test parameter ipv4 was not specified"
    return $False
}


# Source the tcutils.ps1 file
. .\setupscripts\tcutils.ps1

PowerCLIImport
ConnectToVIServer $env:ENVVISIPADDR `
    $env:ENVVISUSERNAME `
    $env:ENVVISPASSWORD `
    $env:ENVVISPROTOCOL


########################################################################################
# Main Body
########################################################################################
$retVal = $Failed


$vmObj = Get-VMHost -Name $hvServer | Get-VM -Name $vmName
if (-not $vmObj) {
    LogPrint "ERROR: Unable to Get-VM with $vmName"
    DisconnectWithVIServer
    return $Aborted
}


# Get the Guest version
$DISTRO = GetLinuxDistro ${ipv4} ${sshKey}
LogPrint "DEBUG: DISTRO: ${DISTRO}."
if (-not $DISTRO) {
    LogPrint "ERROR: Guest OS version is NULL."
    DisconnectWithVIServer
    return $Aborted
}
LogPrint "INFO: Guest OS version is ${DISTRO}."


# Set clone vm name
$cloneName = $vmName + "-clone-" + (Get-Random -Maximum 300 -Minimum 1)
LogPrint "DEBUG: cloneName: ${cloneName}."


# Acquire a new static IP
$ip = "172.18.1." + (Get-Random -Maximum 254 -Minimum 10)
LogPrint "DEBUG: ip: ${ip}."


# Create the customization specification
$linuxSpec = New-OSCustomizationSpec -Type NonPersistent -OSType Linux -Domain redhat.com -NamingScheme VM
if ($null -eq $linuxSpec) {
    LogPrint "ERROR: Create linuxspec failed."
    DisconnectWithVIServer
    return $Aborted
}
LogPrint "INFO: Create linuxspec well."


# Remove any NIC mappings from the specification
$nicMapping = Get-OSCustomizationNicMapping -OSCustomizationSpec $linuxSpec
Remove-OSCustomizationNicMapping -OSCustomizationNicMapping $nicMapping -Confirm:$false


# Create a new NIC mapping for the first NIC - it will use DHCP IP
New-OSCustomizationNicMapping -OSCustomizationSpec $linuxSpec -IpMode UseDhcp -Position 1
if (-not $?) {
    LogPrint "ERROR: Failed when New-OSCustomizationNicMapping with dhcp IP."
    DisconnectWithVIServer
    return $Aborted
}
LogPrint "INFO: DHCP NIC config done."


# Create another NIC mapping for the second NIC - it will use static IP
New-OSCustomizationNicMapping -OSCustomizationSpec $linuxSpec -IpMode UseStaticIP -IpAddress $ip -SubnetMask 255.255.255.0 -DefaultGateway 10.73.199.254 -Position 2
if (-not $?) {
    LogPrint "ERROR: Failed when New-OSCustomizationNicMapping with static IP."
    DisconnectWithVIServer
    return $Aborted
}
LogPrint "INFO: Static NIC config done."


# Clone the vm with new OSCustomization Spec
$clone = New-VM -VM $vmObj -Name $cloneName -OSCustomizationSpec $linuxSpec -VMHost $hvServer -Confirm:$false
LogPrint "INFO: Complete clone operation. Below will check VM cloned."


# Refresh the new cloned vm
$cloneVM = Get-VMHost -Name $hvServer | Get-VM -Name $cloneName
if (-not $cloneVM) {
    LogPrint "ERROR: Unable to Get-VM with ${cloneName}."
    DisconnectWithVIServer
    return $Aborted
}
LogPrint "INFO: Found the VM cloned - ${cloneName}."


# Power on the clone vm
LogPrint "INFO: Powering on $cloneName"
$on = Start-VM -VM $cloneVM -Confirm:$false -ErrorAction SilentlyContinue


# Wait for clone VM SSH ready
LogPrint "INFO: Wait for SSH to confirm VM booting."
if ( -not (WaitForVMSSHReady $cloneName $hvServer $sshKey 300)) {
    LogPrint "ERROR : Cannot start SSH."
    RemoveVM -vmName $cloneName -hvServer $hvServer
    DisconnectWithVIServer
    return $Aborted
}
else {
    LogPrint "INFO: Ready SSH."
}


# Get another VM IP addr
$ipv4Addr_clone = GetIPv4 -vmName $cloneName -hvServer $hvServer
LogPrint "DEBUG: ipv4Addr_clone: ${ipv4Addr_clone}."


# Check the static IP for second NIC
$ip_debug = bin\plink.exe -i ssh\${sshKey} root@${ipv4Addr_clone} "ip addr"
LogPrint "DEBUG: ip_debug: ${ip_debug}."

$staticIP = bin\plink.exe -i ssh\${sshKey} root@${ipv4Addr_clone} "ip addr | grep $ip"
LogPrint "DEBUG: staticIP: ${staticIP}."
if ($null -eq $staticIP)
{
    LogPrint "ERROR: The customization guest Failed with static IP for second NIC."
    RemoveVM -vmName $cloneName -hvServer $hvServer
    return $Failed
}


# Check the log 
$loginfo = bin\plink.exe -i ssh\${sshKey} root@${ipv4Addr_clone} "cat /var/log/vmware-imc/toolsDeployPkg.log | grep 'Ran DeployPkg_DeployPackageFromFile successfully'"
LogPrint "DEBUG: loginfo: ${loginfo}."
if ($null -eq $loginfo)
{
    LogPrint "ERROR: The customization guest failed with log ${loginfo}."
}
else
{
    LogPrint "INFO: The customization guest passed with log ${loginfo}."
    $retVal = $Passed
}


#Delete the clone VM
$remove = RemoveVM -vmName $cloneName -hvServer $hvServer


DisconnectWithVIServer
return $retVal
