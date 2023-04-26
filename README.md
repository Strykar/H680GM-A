# H680GM-A
My notes and scripts for the Dasan Networks H680GM-A (Airtel) GPON ONT / router to:
1. Dual-stack my router and LAN via the IPv6 /64 that Airtel provides to all residential customers natively now.
2. Port-forward ports 80 and 443 so I can run an HTTP(S) server on my new symmetric 1 Gigabit connection.

![image](https://user-images.githubusercontent.com/2946372/231237158-4f1219e7-9183-4921-bf03-ff17f6652395.png)
[Image courtesy - https://twitter.com/geekyranjit/status/1403558141002850307]

---
Review the `dasan.service` unit in this repository to understand how I set things up from a PC in the LAN.
If you have Qs, use the [Discussions](https://github.com/Strykar/H680GM-A/discussions) option, open issues only for the scripts.

India specific discussion at https://broadbandforum.co/threads/enabling-ipv6-with-a-static-ipv4-dasan-h680gm-a.221385/

Poke around the scripts, they have tips and examples for figuring this out on any router.

WARNING: DO NOT ATTEMPT to run these scripts without ensuring they will work for your environment / router, they will 100% break things.
### TLDR
* [Getting port 80 and 443 forwards to work](https://github.com/Strykar/H680GM-A#tldr---getting-port-80-and-443-forwarded)

* [Getting native IPv6 to work with a static IPv4 assigned](https://github.com/Strykar/H680GM-A#tldr---getting-native-ipv6-to-work-with-a-static-ipv4-assigned)
---

|     Pros               |     Cons           |
| ---------------------- | ------------------ |
| Decent RAM / Flash size  |     No SQM, terrible for gaming         |
| Ships with `/bin/tcpdump`| Ancient kernel and userland   |
| Root access available | No GPL sources |
| Ships with `/userfs/bin/tcapi`| Busybox gimps available binary options |
| XPON module is 2.1 Gbps Down / 1 Gbps Up | 1 Gbit LAN NICs |


---
This should list all the tables / chains / rules
```
iptables -tfilter -vnxL;iptables -tnat -vnxL;iptables -tmangle -vnxL;iptables -traw -vnxL;iptables -tsecurity -vnxL | grep -vE 'pkts|Chain'"
```
### Router hardware
The firmware was built as recently as 2021, the kernel , and sadly the Openwrt release it is based on is ancient:
```
# uname -a
Linux tc 3.18.21 #6 SMP Wed Mar 31 07:52:27 UTC 2021 mips unknown
```
The CPU appears to be a Dual Core (+2 threads) MIPS SoC with 256 MB RAM, similar to the [model_here] Xiaomi router.

It has 256 MB RAM and loads the / partition as read-only SquashFS: `/dev/mtdblock3 on / type squashfs (ro,relatime)`

It does mount /data/ read-write: `/dev/mtdblock9 on /data type jffs2 (rw,relatime)` onto a 256MB flash memory chip which ships with 11 partitions from factory.

```
# cat /proc/cpuinfo 
system type		: EcoNet EN7528 SOC
machine			: econet,en751221
processor		: 0
cpu model		: MIPS 1004Kc V2.15
BogoMIPS		: 591.87
wait instruction	: yes
microsecond timers	: yes
tlb_entries		: 32
extra interrupt vector	: yes
hardware watchpoint	: yes, count: 4, address/irw mask: [0x0ffc, 0x0ffc, 0x0ffb, 0x0ffb]
isa			: mips1 mips2 mips32r1 mips32r2
ASEs implemented	: mips16 dsp mt
shadow register sets	: 1
kscratch registers	: 0
package			: 0
core			: 0
VCED exceptions		: not available
VCEI exceptions		: not available
VPE			: 0
```

I get a static IPv4 from my ISP (Airtel, via IPoE apparently) and this works well for the most part.

![wan_v4](https://user-images.githubusercontent.com/2946372/233778264-339855cf-560f-4d5c-8634-cc767c253f9e.png)

Airtel's prepping for IPTV and the IPoE / PPPoE requests only see responses over VLAN 100.

Unfortunately the Dasan firmware on the device does not account for this mysterious customer configuration.
Thus it is impossible to configure a static IPv4 WAN address with IPv6, unless the IPv6 type is static too.. yea.

![reserved_port_range](https://user-images.githubusercontent.com/2946372/233778081-4d427d18-4ab8-4be0-a055-99318b78b435.png)

Take note that port 22 is not on the list above.[^1]
Having root ssh access helped..

---

### TLDR - Getting port 80 and 443 forwarded
The startup scripts invoke [`/etc/acl.sh`](https://gist.github.com/Strykar/13193cbeb57bfea8d2aa69a47afe2918) which prevents some ports from being forwarded

The line `iptables -A ACL -p tcp -m multiport --dports 80,443,21,23,22,69,161,53,7547 -j acl_chain` is the culprit.

- Delete the factory created rule:
```
iptables -D ACL -p tcp -m multiport --dports 80,443,21,23,22,69,161,53,7547 -j acl_chain - Deletes the factory created rule
```
- Recreate the rule without the the ports we need
```
iptables -A ACL -p tcp -m multiport --dports 21,23,22,69,161,53,7547 -j acl_chain
```

### TLDR - Getting native IPv6 to work with a static IPv4 assigned
It appears that the router was never configured to be dual-stacked for a customer with static IPv4.
IPv6 is available only via PPPoE tunnel (1492 MTU) and static IPv4 is assigned via IPoE (1500 MTU) over VLAN 100.

We dial ppp using `pppd` directly over the same VLAN (`100`) via the same virtual interface (`nas0_0`) used for our IPv4 traffic.
There are no responses to PPPoE discovery (`PAD*`) requests over any other VLAN.

Some of this stuff is convoluted for no reason and kept throwing me off.
The `ip6` binary, is basically a stripped down `dibbler-server` binary and in non-static mode (dual-stack PPPoE), the router uses both `dibbler-server` and `ip6` binaries to setup DHCPv6 because reasons I guess..
```
# ls -la /userfs/bin/ip6
-rwxrwxr-x    1 0        0          145508 /userfs/bin/ip6
# ls -la /userfs/bin/dibbler-server 
-rwxrwxr-x    1 0        0         1551488 /userfs/bin/dibbler-server
```
The way to get IPv6 working on the LAN, is to disable `dibbler-server`, setup `dibbler-client` to get a `/64` via the `ppp0` interface and then start restart `radvd` with the conveniently created `/etc/dibbler/radvd.conf`(by `dibbler-client`).
```
trap "" HUP;/usr/bin/pppd unit 0 user 020xxx_mh@airtelbroadband.in password 70xxx nodetach holdoff 4 maxfail 0 usepeerdns plugin libpppoe.so nas0_0 lcp-echo-interval 30 lcp-max-terminate 3 lcp-echo-failure 3 persist mtu 1492 mru 1492 ipv6 ,::220 noip &

tail /data/log/messages | awk '/remote LL address/{print $NF}'
/userfs/bin/dibbler-client stop; start
/userfs/bin/radvd -C /etc/dibbler/radvd.conf -p /var/run/radvd.pid -l /var/log/radvd.log -m logfile
/bin/ip -6 route add default ${REMOTE_LL} dev ppp0
```
Boom! Native (SLAAC) IPv6 for the LAN.
