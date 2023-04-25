#!/bin/bash
# Script to kill and restart daemons with our config on the Dasan router
SSHPASS='xxx'
SSH_CMD="sshpass -e ssh dasan"
ROUTER="192.168.1.1"
HTTP_BIND=$(${SSH_CMD} "grep '192.168.1.1' /etc/lighttpd_clone_oneweb.conf > /dev/null 2>&1 ; echo \$? ") # Check if Lighttpd listens on 192.168.1.1
HTTP_PID=$(${SSH_CMD} "pidof lighttpd")
TELN_PID=$(${SSH_CMD} "pidof utelnetd") # Check if utelnet daemon is running
EXIT_CODE_TELN=$(${SSH_CMD} "pidof utelnetd > /dev/null 2>&1 ; echo \$? ")
TR69_PID=$(${SSH_CMD} "pidof tr69") # Check if ACS (TR-069) daemon is running and store its exit code
EXIT_CODE_TR69=$(${SSH_CMD} "pidof tr69 > /dev/null 2>&1 ; echo \$? ")
IP6B_PID=$(${SSH_CMD} "pidof ip6")
RADV_PID=$(${SSH_CMD} "pidof radvd")
IGMP_PID=$(${SSH_CMD} "pidof igmpproxy")
UPNP_PID=$(${SSH_CMD} "pidof miniupnpd")
SSH_CMD="sshpass -e ssh dasan"

# Kill ultelnetd and tr69, restart dropbear and lighttpd with their new config
DASAN_FIX_DAEMON() {
    ${SSH_CMD} "kill ${HTTP_PID}" || \
		{ echo "Failed to kill Lighttpd ${HTTP_PID} at ${ROUTER}" >&2; exit 1; }
	${SSH_CMD} "kill ${UPNP_PID}" || \
		{ echo "Failed to kill miniuPnPd ${UPNP_PID} at ${ROUTER}" >&2; exit 1; }		
    ${SSH_CMD} "kill ${TELN_PID}" || \
        { echo "Failed to kill utelnetd ${TELN_PID} at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "kill ${TR69_PID}" || \
        { echo "Failed to kill tr69 ${TR69_PID} at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "/userfs/bin/dibbler-server stop > /dev/null 2>&1" || \
        { echo "Failed to stop Dibbler server at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "kill ${IP6B_PID}" || \
        { echo "Failed to kill ip6 at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "kill ${RADV_PID}" || \
        { echo "Failed to kill radvd -C /etc/radvd.conf at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "kill ${IGMP_PID}" || \
        { echo "Failed to kill igmpproxy at ${ROUTER}" >&2; exit 1; }
#   ${SSH_CMD} "kill $(pidof callmgr)" || \
#       { echo "Failed to kill /userfs/bin/callmgr at ${ROUTER}" >&2; exit 1; }
	${SSH_CMD} "sed -i 's/USERLIMIT_GLOBAL=\"0\"/USERLIMIT_GLOBAL=\"1\"/; s/BIND_TO_ADDR=\"any\"/BIND_TO_ADDR=\"192.168.1.1\"/; s/ANONYMOUS_USER=\"no\"/ANONYMOUS_USER=\"yes\"/; s/ROOTDIR=\"\/mnt\"/ROOTDIR=\"\/data\"/' /tmp/etc/bftpd.conf && /userfs/bin/bftpd -d -c /tmp/etc/bftpd.conf" || \
		{ echo "Failed to start bftpd daemon at ${ROUTER}" >&2; exit 1; } 
	${SSH_CMD} "sed -i 's/^listening_ip=.*/listening_ip=br0/' /tmp/miniupnpd.conf && /userfs/bin/miniupnpd -f /tmp/miniupnpd.conf" || \
		{ echo "Failed to re[configure|start] miniuPnPd ${UPNP_PID} at ${ROUTER}" >&2; exit 1; }
	${SSH_CMD} "echo -e 'server.bind = \"192.168.1.1\"' >> /etc/lighttpd_clone_oneweb.conf" || \
        { echo "Failed to append Bind:IP to Lighttpd config at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "/bin/lighttpd -f /etc/lighttpd_clone_oneweb.conf" || \
        { echo "Failed to start Lighttpd daemon at ${ROUTER}" >&2; exit 1; }
#	${SSH_CMD} "netstat -aln"
}

# If the Telnet and ACS daemons are running and Lighttpd is not configured to only listen on LAN_INT, call DASAN_FIX_DAEMON
if ! [[ ${EXIT_CODE_TELN} == 0 && ${EXIT_CODE_TR69} == 0 && ${HTTP_BIND} == 1 ]]; then
    printf "%s\n" "$(/usr/bin/date): [NOK]  NOCHANGE: Utelnetd and TR69 daemons not running. SSHD and Lighttpd daemons are running correctly configured on ${ROUTER}. Exiting!"
else
    # Check if year is 1970 and non-existence of /etc/timezone,conf
    if [[ ${EXIT_CODE_TELN} == 0 && ${EXIT_CODE_TR69} == 0 && ${HTTP_BIND} == 1 ]]; then
        DASAN_FIX_DAEMON
            echo "$(/usr/bin/date): [OK]  SUCCESS: Killed Telnet, ACS. Re-{started|configured} Dropbear SSHD and Lighttpd on ${ROUTER}" >&1
        else
            echo "$(/usr/bin/date): [ERROR]  RULEFAIL: Function DASAN_FIX_DAEMON at ${ROUTER}" >&2
            exit 1
    fi
fi
