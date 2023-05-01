#!/bin/bash
# shellcheck disable=SC2016 disable=SC2034  # Unused variable (according to shellcheck), SSHPASS, is used by sshpass
# Script called by systemd ExecStartPost to run pppd on remote Dasan router
# There is no bash / tmux / screen / nohup available
# We keep a persistent SSH session open running pppd
#
# Finally, dial PPPoE via nas0 reqeusting only IPv6 via IPCP
# On connect grep the remote Link-Local address and set it as the default IPv6 gateway via device ppp0

# The trap "" HUP command sets a trap to ignore the SIGHUP signal, which is sent to the process
# when the terminal it is attached to is closed. By setting the trap to ignore this signal
# the pppd command will continue running even if the user disconnects from the remote shell.
# We could request IPv4 via the ppp connection by not appending noip

# s/nas2/ppp0/g: replace all occurrences of "nas2" with "ppp0"
# s/^ ia/#&/: comment out any line that starts with "ia" and has two spaces before
# it (the ^ matches the start of a line, and & in the replacement refers to the matched text)
# s/^ ta/#&/: comment out any line that starts with "ta" and has two spaces before it
# s/^ #\?pd/pd/: uncomment any line that starts with "pd" and has two spaces before
# it (the \? makes the # character optional, so this matches both commented and uncommented "pd" lines)

SSHPASS='xxx'
SSH_CMD="sshpass -e ssh dasan"
ROUTER="192.168.1.1"
PPPD_EXIT_CODE=$(${SSH_CMD} "/bin/pidof pppd 1>/dev/null ; echo \$? " 2>/dev/null)
RADV_EXIT_CODE=$(${SSH_CMD} "/usr/bin/test -f /etc/dibbler/radvd.conf ; echo \$? " 2>/dev/null)
# Cat create a connection-specific ppp.conf since Busybox is built without SCP / sFTP support
# /userfs/bin/bftpd could be an option too but fsck ftp
read -r -d '' FILE_CONTENTS << HEREDOC
unit 0
user 020xxxxxxxxx_mh@airtelbroadband.in
password xxxxxxxxxx
holdoff 4
maxfail 0
usepeerdns
plugin libpppoe.so
nas0_0
lcp-echo-interval 30
lcp-max-terminate 3
lcp-echo-failure 3
persist
mtu 1492
mru 1492
ipv6 ,::220
noip
HEREDOC
echo "${FILE_CONTENTS}" | ${SSH_CMD} 'cat > /etc/ppp/ppp0.conf'

LOCAL_IPV6_SETUP() {
	# Delete any 6Bone / Teredo IPs if the router assigns one from the default broken (when IPv4 is static) radvd.conf
	ip -6 addr | awk '$2 ~ /^3ffe:/ {system("sudo ip -6 addr del " $2 " dev enp2s0")}'
	# Grok link-global IPv6 address and update DNS via aws-cliv2
	local IPV6_IP
	IPV6_IP=$(ip -6 addr show dev enp2s0 scope global | awk '/inet6/ {split($2, a, "/"); print a[1]}')
	[[ -n "${IPV6_IP}" ]] && \
AWS_ACCESS_KEY_ID=xxx \
AWS_SECRET_ACCESS_KEY=xxx \
/usr/bin/aws route53 change-resource-record-sets \
    --hosted-zone-id "xxx" \
    --change-batch '{
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "xxx",
                    "Type": "AAAA",
                    "TTL": 60,
                    "ResourceRecords": [
                        {
                            "Value": "'"${IPV6_IP}"'"
                        }
                    ]
                }
            }
        ]
    }' \
    --region "us-east-1" \
    --cli-connect-timeout 5 \
    --query 'ChangeInfo.Id' \
    --output text
	# Delete any existing port forwarding rules and add new one's for the HTTPS mirror
	local IPT6_CMD="sshpass -e ssh dasan ip6tables"
	local LAN6_CIDR=fe80::/10
	local WAN6_CIDR
	WAN6_CIDR=$(${SSH_CMD} "sed -n '/prefix 2/s/.*prefix \([^ ]*\).*/\1/p' /etc/dibbler/radvd.conf")
	${IPT6_CMD} -t nat -L PREROUTING -n -v --line-numbers | awk '/tcp dpt:80/ && /2[0-9]{3}:/{print $1}' | tac | while read -r IP6RULE; do ip6tables -t nat -D PREROUTING "${IP6RULE}"; done > /dev/null 2>&1
	${IPT6_CMD} -t nat -L PREROUTING -n -v --line-numbers | awk '/udp dpt:80/ && /2[0-9]{3}:/{print $1}' | tac | while read -r IP6RULE; do ip6tables -t nat -D PREROUTING "${IP6RULE}"; done > /dev/null 2>&1
	${IPT6_CMD} -t nat -L PREROUTING -n -v --line-numbers | awk '/tcp dpt:443/ && /2[0-9]{3}:/{print $1}' | tac | while read -r IP6RULE; do ip6tables -t nat -D PREROUTING "${IP6RULE}"; done > /dev/null 2>&1
	${IPT6_CMD} -t nat -L PREROUTING -n -v --line-numbers | awk '/udp dpt:443/ && /2[0-9]{3}:/{print $1}' | tac | while read -r IP6RULE; do ip6tables -t nat -D PREROUTING "${IP6RULE}"; done > /dev/null 2>&1
	${IPT6_CMD} -t nat -A PREROUTING -i ppp0 -p tcp --dport 22 -j DNAT --to-destination "${IPV6_IP}" || \
		{ echo "Failed to port forward TCP/22 via ppp0 at ${ROUTER} to ${IPV6_IP}" >&2; exit 1; }
	${IPT6_CMD} -t nat -A PREROUTING -i ppp0 -p tcp --dport 80 -j DNAT --to-destination "${IPV6_IP}" || \
		{ echo "Failed to port forward TCP/80 via ppp0 at ${ROUTER} to ${IPV6_IP}" >&2; exit 1; }
	${IPT6_CMD} -t nat -A PREROUTING -i ppp0 -p udp --dport 80 -j DNAT --to-destination "${IPV6_IP}" || \
		{ echo "Failed to port forward UDP/80 via ppp0 at ${ROUTER} to ${IPV6_IP}" >&2; exit 1; }
	${IPT6_CMD} -t nat -A PREROUTING -i ppp0 -p tcp --dport 443 -j DNAT --to-destination "${IPV6_IP}" || \
		{ echo "Failed to port forward TCP/443 via ppp0 at ${ROUTER} to ${IPV6_IP}" >&2; exit 1; }
	${IPT6_CMD} -t nat -A PREROUTING -i ppp0 -p udp --dport 443 -j DNAT --to-destination "${IPV6_IP}" || \
		{ echo "Failed to port forward UDP/443 via ppp0 at ${ROUTER} to ${IPV6_IP}" >&2; exit 1; }
	sudo sed -i "s/AllowAccessFromWebToFollowingIPAddresses=\"\*\"/AllowAccessFromWebToFollowingIPAddresses=\"127.0.0.1 192.168.1.10 70.71.186.189 182.70.116.80 \${IPV6_IP}\"/" /etc/awstats/awstats.site.conf
	ip -6 addr | awk '$2 ~ /^3ffe:/ {system("sudo ip -6 addr del " $2 " dev enp2s0")}'
}

DASAN_START_IPV6() {
    ${SSH_CMD} "trap \"\" HUP;/usr/bin/pppd file /etc/ppp/ppp0.conf" || \
        { echo "Failed to start ppp daemon at ${ROUTER}" >&2; exit 1; }
	${SSH_CMD} "/bin/sleep 5"
    local IP6_GW
    IP6_GW=$(${SSH_CMD} "tail /data/log/messages | awk '/remote LL address/{last=\$NF} END{print last}'")
	[ -z "${IP6_GW}" ] && echo "Error: Failed to grep remote link-local address from syslog. IP6_GW variable is empty" && exit 1
	${SSH_CMD} "/bin/sed -i 's/nas2/ppp0/g; s/^  ia/#&/; s/^  ta/#&/; s/^  # *pd/pd/' /etc/dibbler/client.conf" || \
		{ echo "Failed to sed /etc/dibbler/client.conf for ppp0 at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "/userfs/bin/dibbler-client start > /dev/null 2>&1" || \
        { echo "Failed to start Dibbler client at ${ROUTER}" >&2; exit 1; }
	${SSH_CMD} "/bin/sleep 5"
    ${SSH_CMD} "/userfs/bin/radvd -C /etc/dibbler/radvd.conf -p /var/run/radvd.pid -l /var/log/radvd.log -m logfile" || \
        { echo "Failed to start radvd -C /etc/dibbler/radvd.conf at ${ROUTER}" >&2; exit 1; }
    ${SSH_CMD} "/bin/ip -6 route add default via ${IP6_GW} dev ppp0" || \
        { echo "Failed to set default IPv6 gateway at ${ROUTER}" >&2; exit 1; }
#	${SSH_CMD} "/usr/bin/ip6tables -I FORWARD -o ppp0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu" || \
#		{ echo "Failed to clamp MSS to PMTU on ppp0 at ${ROUTER}" >&2; exit 1; }
#	${SSH_CMD} "/bin/ping6 -c 3 ipv6.google.com"
#	/usr/bin/ip -c -6 addr
	LOCAL_IPV6_SETUP
}

# If pppd is running and our custom config file exists, exit
if [[ ${PPPD_EXIT_CODE} -eq 0 && ${RADV_EXIT_CODE} -eq 0 ]]; then
    # pppd and dibbler-client are correctly setup
    printf "%s\n" "$(/usr/bin/date): [NOK]  NOCHANGE: pppd is already running on the Dasan router at ${ROUTER}. Exiting!"
else
    # If pppd is not running and our custom config does not exist, start pppd
	if [[ ${PPPD_EXIT_CODE} -eq 1 && ${RADV_EXIT_CODE} -eq 1 ]]; then 
        DASAN_START_IPV6
			echo "$(/usr/bin/date): [OK]  SUCCESS: ${ROUTER} and its /24 LAN are now dual-stacked, congrats!" >&1
        else
            echo "$(/usr/bin/date): [ERROR]  RULEFAIL: Function DASAN_START_IPV6 failed on ${ROUTER}" >&2
            exit 1
    fi
fi
