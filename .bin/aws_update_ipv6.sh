#!/bin/bash
# Script to update the AAAA RR of V6_URL below using aws-cli-v2 to the current IP on V6_INT
# Assumes AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment vars exist or export them

V6_INT=enp2s0
RR_TTL=60
RR_TYPE=AAAA
RR_ACTION=UPSERT
AWS_REGION=xxx
V6_URL=xxx
ZONE_ID=xxx
#export AWS_ACCESS_KEY_ID=xxx
#export AWS_SECRET_ACCESS_KEY=xxx

# Delete any 6Bone / Teredo IPs if the router assigns one from the default broken (when IPv4 is static) radvd.conf
ip -6 addr | awk '$2 ~ /^3ffe:/ {system("sudo ip -6 addr del " $2 " dev enp2s0")}'

# Get IPv6 GUA 
IPV6_IP=$(ip -6 addr show dev ${V6_INT} scope global | awk '/inet6/ {split($2, a, "/"); print a[1]}')

if [[ "$(dig +short -r AAAA ${V6_URL})" == "${IPV6_IP}" ]]; then
	echo "$(/usr/bin/date): [NOK]  NOCHANGE: AWS_R53 AAAA RR is correct, exiting."
	exit 0
else
	echo "$(/usr/bin/date): [AWS_CLIv2]  UPSERT: Stale IPv6 address [$(dig +short -r AAAA ${V6_URL})] detected, updating Route53.."
	sudo sed -i "s/AllowAccessFromWebToFollowingIPAddresses=\"[^\"]*\"/AllowAccessFromWebToFollowingIPAddresses=\"127.0.0.1 192.168.1.3 192.168.1.10 70.71.186.189 182.70.116.80 ${IPV6_IP}\"/" /etc/awstats/awstats.mirror.4v1.in.conf
	/usr/bin/aws route53 change-resource-record-sets \
    --hosted-zone-id "${ZONE_ID}" \
    --change-batch '{
        "Changes": [
            {
                "Action": "'"${RR_ACTION}"'",
                "ResourceRecordSet": {
                    "Name": "'"${V6_URL}"'",
                    "Type": "'"${RR_TYPE}"'",
                    "TTL": '"${RR_TTL}"',
                    "ResourceRecords": [
                        {
                            "Value": "'"${IPV6_IP}"'"
                        }
                    ]
                }
            }
        ]
    }' \
    --region "${AWS_REGION}" \
    --cli-connect-timeout 5 \
    --query 'ChangeInfo.Id' \
    --output text
fi
