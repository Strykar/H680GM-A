#!/bin/bash
#
# Function that logs in to remote Dasan router and updates iptables for HTTPS port forwarding
SSHPASS='xxx'
ROUTER="192.168.1.1"
CHAIN="acl_chain"
IPT_CMD="sshpass -e ssh dasan iptables"
# Default Dasan rules to grep. HTTPS port-forwarding does not work when this exits true
TCP_ACL_CHAIN="-A ACL -p tcp -m multiport --dports 80,443,21,23,22,69,161,53,7547 -j ${CHAIN}"
UDP_ACL_CHAIN="-A ACL -p udp -m multiport --dports 80,443,21,23,22,69,161,53,7547 -j ${CHAIN}"

DASAN_FIREWALL_SETUP() {
    local WAN_INT="nas0_0"
    #local LAN_INT="br0"
    local LAN_CIDR=192.168.1.0/24
    local WAN_CIDR=182.70.116.80/32 # Static IPv4
    local DST_IP="192.168.1.10" # PC in LAN to port forward to
	local IPT_CMD="sshpass -e ssh dasan iptables"
    local DEL_PRT="80,443,ftp,telnet,ssh,tftp,snmp,domain,7547" # Default list in port rule
    local ADD_PRT="ftp,telnet,ssh,tftp,snmp,domain,7547" # We trim http(s) from the default list
    # SSH, match and delete exact rule (ACL) auto-created by Dasan router (/etc/acl.sh), fsck you Airtel
    ${IPT_CMD} -t filter -D ACL -p TCP -m multiport --dport ${DEL_PRT} -j ${CHAIN} || \
        { echo "[FAIL]: Delete default TCP rules for ports {${DEL_PRT}} in the ${CHAIN} chain" >&2; exit 1; }
    ${IPT_CMD} -t filter -D ACL -p UDP -m multiport --dport ${DEL_PRT} -j ${CHAIN} || \
        { echo "[FAIL]: Delete default UDP rules for ports {${DEL_PRT}} in the ${CHAIN} chain" >&2; exit 1; }
    # SSH, re-create old rule (ACL) without HTTP and HTTPS ports
    ${IPT_CMD} -t filter -A ACL -p TCP -m multiport --dport ${ADD_PRT} -j ${CHAIN} || \
        { echo "[FAIL]: Re-create TCP rules for ports {${ADD_PRT}} in the ${CHAIN} chain" >&2; exit 1; }
    ${IPT_CMD} -t filter -A ACL -p UDP -m multiport --dport ${ADD_PRT} -j ${CHAIN} || \
        { echo "[FAIL]: Re-create UDP rules for ports {${ADD_PRT}} in the ${CHAIN} chain" >&2; exit 1; }
    ${IPT_CMD} -t nat -A VS_${WAN_INT} -i ${WAN_INT} -p tcp -m tcp -m multiport \
        --dports 80,443 -j DNAT --to-destination ${DST_IP}:80-443 || \
        { echo "[FAIL]: Create TCP / HTTP(S) port-forward rule on ${WAN_INT}" >&2; exit 1; }
    ${IPT_CMD} -t nat -A VS_${WAN_INT} -i ${WAN_INT} -p udp -m udp -m multiport \
        --dports 80,443 -j DNAT --to-destination ${DST_IP}:80-443 || \
        { echo "[FAIL]: Create UDP / HTTP(S) port-forward rule on ${WAN_INT}" >&2; exit 1; }
    ${IPT_CMD} -t nat -A NATLB_PRE_${WAN_INT} -s ${LAN_CIDR} -d ${WAN_CIDR} -p tcp -m tcp -m multiport \
        --dports 80,443 -j DNAT --to-destination ${DST_IP}:80-443 || \
        { echo "[FAIL]: Create TCP / HTTP(S) PREROUTING DNAT rule for ${LAN_CIDR}" >&2; exit 1; }
    ${IPT_CMD} -t nat -A NATLB_PRE_${WAN_INT} -s ${LAN_CIDR} -d ${WAN_CIDR} -p udp -m udp -m multiport \
        --dports 80,443 -j DNAT --to-destination ${DST_IP}:80-443 || \
        { echo "[FAIL]: Create UDP / HTTP(S) PREROUTING DNAT rule for ${LAN_CIDR}" >&2; exit 1; }
}

# Remotely check the HTTPS URLs and store the exit code and HTTP response
HTTP_RESPONSE_LAIR=$(ssh lair 'curl -s --retry 2 --max-time 6 -o /dev/null -w "%{http_code}" https://my.site')                                                                                                                    
EXIT_CODE_LAIR=$?

# Function that logs into remote Dasan router and updates iptables to remove HTTPS port forwarding blocks
if [[ ${EXIT_CODE_LAIR} == 0 && ${HTTP_RESPONSE_LAIR} == 200 ]]; then
    # HTTPS is working, exit the script
    printf "%s\n" "$(/usr/bin/date): [NOK]  NOCHANGE: HTTPS port-forwarding correctly configured on the Dasan router at ${ROUTER}. Exiting!"
else
    # Grep the default iptables rules on the dasan router
    ${IPT_CMD} -S | grep -q -- "${TCP_ACL_CHAIN}" || \
        { echo "Failed to grok default TCP rules in ${CHAIN} on Dasan router" >&2; exit 1; }
    TCP_RULE=$?
    ${IPT_CMD} -S | grep -q -- "${UDP_ACL_CHAIN}" || \
        { echo "Failed to grok default UDP rules in ${CHAIN} on Dasan router" >&2; exit 1; }
    UDP_RULE=$?

    # If both rules exist (return 0), HTTPS is not working, call the DASAN_FIREWALL_SETUP function to fix
    if [[ ${TCP_RULE} == 0 && ${UDP_RULE} == 0 ]]; then
        if DASAN_FIREWALL_SETUP; then
            echo "$(/usr/bin/date): [OK]  SUCCESS: Fixed Dasan router's HTTPS port-forwarding at ${ROUTER}" >&1
        else
            echo "$(/usr/bin/date): [ERROR]  RULEFAIL: Function DASAN_FIREWALL_SETUP failed at ${ROUTER}" >&2
            exit 1
        fi
    fi
fi
