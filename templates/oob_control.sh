#!/bin/bash

# This file specifies the Out-Of-Band management of hosts
#
# The following environment variables are available
#
# IPMI_HOST      -- IPMI IP address
# IPMI_USER      -- IPMI Account User
# IPMI_PASSWORD  -- IPMI Account Password
#
# HOST_NAME -- DNS Name of the host
# HOST_IP   -- DHCP IP address of host
#


manual_startup() {
    echo "Power on $IPMI_HOST_NAME($IPMI_HOST_IP) and initiate PXE boot"
}

manual_shutdown() {
    echo "Power off $IPMI_HOST_NAME($IPMI_HOST_IP)..."
}

ipmi_startup() {
    ipmitool -I lanplus -H "$IPMI_HOST" -U "$IPMI_USER" -P "$IPMI_PASSWORD" chassis bootdev pxe
    ipmitool -I lanplus -H "$IPMI_HOST" -U "$IPMI_USER" -P "$IPMI_PASSWORD" power cycle ||
        ipmitool -I lanplus -H "$IPMI_HOST" -U -U "$IPMI_USER" -P "$IPMI_PASSWORD" power on
}

ipmi_shutdown() {
    ipmitool -I lanplus -H "$IPMI_HOST" -U "$IPMI_USER" -P "$IPMI_PASSWORD" power off
}

_startup() {
    
}

_shutdown() {

}
if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    2>&1 printf "Command missing...!" 
    return 1
fi

case "$COMMAND" in
startup)
    _startup
    ;;
shutdown)
    _shutdown
    ;;
*)
    2>&1 echo "Unknown command: ${COMMAND}"
    exit 1
    ;;
esac
