#!/bin/bash
# Open a few SSH connections to create missing files and let them linger
# Killall dropbear and restart it with no timeout (-I 0)

SSHPASS='xxx'
ROUTER="192.168.1.1"
SSH_CMD="sshpass -e ssh dasan"
EXIT_CODE_DROP=$(${SSH_CMD} "ps | grep -q '[/]userfs/bin/dropbear -I 0' ; echo \$? " 2>/dev/null)

DASAN_FIX_SSH() {
	${SSH_CMD} "ps > /dev/null 2>&1"
    ${SSH_CMD} "cat /dev/null > /var/log/lastlog; sleep 5 &"
    ${SSH_CMD} "cat /dev/null > /var/log/wtmp; sleep 5 &"
    ${SSH_CMD} "/usr/bin/killall dropbear && /userfs/bin/dropbear -I 0 -p 192.168.1.1:22 > /dev/null 2>&1" && \
		{ echo "Failed to reconfigure Dropbear daemon at ${ROUTER}" >&2; exit 1; }
	sleep 2		
		return 0
}

# If Dropbear is running with the '-I 0' switch, it is already configured, exit
if [[ ${EXIT_CODE_DROP} == 0 ]]; then
    printf "%s\n" "$(/usr/bin/date): [NOK]  NOCHANGE: Dropbear SSHD is running without timeouts configured on ${ROUTER}. Exiting!"
else
    # Check if dropbear is not running the '-I 0' switch, reconfigure
    if [[ ${EXIT_CODE_DROP} != 0 ]]; then
        DASAN_FIX_SSH
            echo "$(/usr/bin/date): [OK]  SUCCESS: Re-(started|configured) Dropbear SSHD on ${ROUTER}" >&1
        else
            echo "$(/usr/bin/date): [ERROR]  RULEFAIL: Function DASAN_FIX_SSH at ${ROUTER}" >&2
            exit 1
    fi
fi
