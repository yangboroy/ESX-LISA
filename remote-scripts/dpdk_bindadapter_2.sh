#!/bin/bash

###############################################################################
##
## Description:
##  Bind Network Adapter to DPDK driver
##
###############################################################################
##
## Revision:
## v1.0 - Ruowen Qin - 7/5/2018 - Build the script.
##
###############################################################################

: '
        <test>
            <testName>dpdk_bindadapter</testName>
            <testID>ESX-DPDK-002</testID>
            <testScript>dpdk_bindadapter_2.sh</testScript>
            <files>remote-scripts/dpdk_bindadapter_2.sh</files>
            <files>remote-scripts/utils.sh</files>
            <RevertDefaultSnapshot>False</RevertDefaultSnapshot>
            <testParams>
                <param>TC_COVERED=RHEL-136145</param>
            </testParams>
            <timeout>240</timeout>
            <onError>Continue</onError>
            <noReboot>True</noReboot>
        </test>

'


dos2unix utils.sh

#
# Source utils.sh
#
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 1
}

#
# Source constants file and initialize most common variables
#
UtilsInit

###############################################################################
##
## Put your test script here
## NOTES:
## 1. Please use LogMsg to output log to terminal.
## 2. Please use UpdateSummary to output log to summary.log file.
## 3. Please use SetTestStateFailed, SetTestStateAborted, SetTestStateCompleted,
##    and SetTestStateRunning to mark test status.
##
###############################################################################


# Printout current Guest OS
GetDistro
LogMsg $DISTRO
# This case cannot run on rhel6
if [ "$DISTRO" == "redhat_6" ]
then
    SetTestStateSkipped
    LogMsg "Not support rhel6"
    exit 1
fi


# This will bind second and thrid network adapter to DPDK
source /etc/profile.d/dpdk.sh

if [ ! "$?" -eq 0 ]
then
    LogMsg "Source Code Compile Failed"
    SetTestStateAborted
    exit 1
fi


# Show nic status
cd "$RTE_SDK" || exit 1
python2 $RTE_SDK/usertools/dpdk-devbind.py -s


# Load required DPDK modules
modprobe uio_pci_generic
insmod "$RTE_SDK/$RTE_TARGET/kmod/igb_uio.ko"


# Start Network Manager
systemctl restart NetworkManager


# Get SSH Server IP address
Server_IP=$(echo "$SSH_CONNECTION"| awk '{print $3}')
LogMsg "$Server_IP"

# Get connected nic
Server_Adapter=$(ip a|grep "$Server_IP"| awk '{print $(NF)}')


# Make Sure we have more than 3 network adapter
if [ "$(python2 ./usertools/dpdk-devbind.py -s | grep unused=igb_uio | wc -l)"  -gt 3 ];
then
    count=0
    # For each adapter, get device name, disconnect with kernel and bind with DPDK
    for i in $(python2 ./usertools/dpdk-devbind.py -s | grep unused=igb_uio | awk 'NR>0{print}'\
    |  awk 'BEGIN{FS="="}{print $2}' | awk '{print $1}');
    do
        if [ "$i" != "$Server_Adapter" ];
        then
            # disconnect nic with kernel and bind to dpdk
            LogMsg "Will Disconnect $i"
            nmcli device disconnect "$i"
            count=$((count + 1))
            
            LogMsg "Start Bind $i"
            python2 ./usertools/dpdk-devbind.py -b igb_uio "$i"
            if [ $count -eq 2 ]; then
                break
            fi
        fi
    done
else
    LogMsg "Failed Not Enough Netowrk Adapter"
    SetTestStateAborted
    exit 1
fi


# Make sure we have two bind DPDK network adapter
if [ "$(python2 ./usertools/dpdk-devbind.py -s | grep drv=igb_uio | wc -l)" -eq 2 ];
then
    LogMsg "Successfully bind two network adapter to DPDK igb_uio"
    UpdateSummary "Successfully bind two network adapter to DPDK igb_uio"
    SetTestStateCompleted
    exit 0
else
    LogMsg "Failed to bind two network adapter to DPDK igb_uio"
    UpdateSummary "Failed to bind two network adapter to DPDK igb_uio"
    SetTestStateFailed
    exit 1
fi
