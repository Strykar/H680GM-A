#!/bin/bash
# SSH in to Airtel Dasan Fiber gateway and update the clock
# This is called every hour because the router's clock is broken

SSHPASS='xxx'
ROUTER="192.168.1.1"
SSH_CMD="sshpass -e ssh dasan"
NTP_TIME=$(${SSH_CMD} "date | awk '{print \$6}'") # Check router time and if year if 1970, fix the time
NTP_CONF=$(${SSH_CMD} "/usr/bin/test -f /etc/timezone.conf ; echo \$? " 2>/dev/null)
ROUTER_TIME=$(${SSH_COMMAND} "date")

DASAN_FIX_NTP() {
${SSH_CMD} "echo -e TZ=\\'Asia/Kolkata\\' > /etc/timezone.conf" || \
	{ echo "Failed to set Time Zone (TZ) on ${ROUTER}" >&2; exit 1; }
${SSH_CMD} "ntpclient -s -c 3 -h ntp.server.host" || \
	{ echo "Failed to update time from NTP server on ${ROUTER}" >&2; exit 1; }
#${SSH_CMD} "date"
}

# If the router thinks its 1970 and the TZ file does not exist, call the DASAN_FIX_NTP function
if [[ ${NTP_TIME} -gt 2022 && ${NTP_CONF} ]]; then
    # Time is correctly setup
	printf "%s\n" "$(/usr/bin/date): [NOK]  NOCHANGE: Correct date and time (${ROUTER_TIME}) set on the Dasan router at ${ROUTER}. Exiting!"
else
    # Check if year is 1970 and non-existence of /etc/timezone,conf
	if [[ ${NTP_TIME} == 1970 && ${NTP_CONF} != 0 ]]; then 
        DASAN_FIX_NTP
            echo "$(/usr/bin/date): [OK]  SUCCESS: Fixed Dasan router's time with NTPClient at ${ROUTER}" >&1
        else
            echo "$(/usr/bin/date): [ERROR]  RULEFAIL: Function DASAN_FIX_NTP failed on ${ROUTER}" >&2
            exit 1
    fi
fi
