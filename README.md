# H680GM-A
My notes and scripts for the Dasan Networks H680GM-A (Airtel) GPON ONT / router to:
1. Dual-stack my router and LAN via the IPv6 /64 that Airtel provides to all residential customers natively now.
2. Port-forward ports 80 and 443 so I can run an HTTP(S) server on my new symmetric 1 Gigabit connection.

![image](https://user-images.githubusercontent.com/2946372/231237158-4f1219e7-9183-4921-bf03-ff17f6652395.png)
[Image courtesy - https://twitter.com/geekyranjit/status/1403558141002850307]

---
Review the `dasan.service` unit in this repository to understand how I set things up from a PC in the LAN.
If you have Qs, use the [Discussions](https://github.com/Strykar/H680GM-A/discussions) option, open issues only for the scripts.

* India specific discussion at https://broadbandforum.co/threads/enabling-ipv6-with-a-static-ipv4-dasan-h680gm-a.221385/
* The solution for me is to roll my own optics, you can read about other user's success to get rid of their ISP ONT's at https://github.com/Anime4000/RTL960x
* Reliance Jio Fiber customers in India have an identical device supplied, which users have managed to tweak, see https://github.com/JFC-Group/JF-Customisation
Sadly, the firmware is quite different and none of the options there worked on the Airtel unit.

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

## The long version
This is _not_ a half bad router, gimped mostly (besides 1Gbit NICs and not enough oomph for Gigabit SQM) because it it locked by ISP firmware, but leagues ahead of other telco's provided firmware. The key, figuratively speaking, to unlocking this router is in it: `/userfs/bin/tcapi` assuming we can get / brute force a map of all the settings and their options, `tcapi`'s built-in help is sadly disabled.

See :video_camera: YT user MxBNET's approach to disabling TR-069 using tcapi [here](https://www.youtube.com/watch?v=h8v3pOaA24c).

`/userfs/bin/tcapi readAll` will dump the config, with all the serial numbers and passwords. It's definitely the _right way_ to configure things but I have not made much progress with it.
```
# /userfs/bin/tcapi
set
unset
get
show
commit
save
read
readAll
staticGet
```

It does ship with tcpdump, which made troubleshooting DHCPv6-PD and ICMPv6 traffic trivial.

Regarding [OpenWRT, there is zero chance](https://forum.openwrt.org/t/openwrt-support-for-en7528-based-xpon-router/78121/4) a driver for the Huawei / HiSense LTY9775M XPON module will ever be available, there is a non-zero chance it could boot OpenWRT based off the Xiaomi (MIPS 1004Kc V2.15) router _if_ someone took the effort.

##### Decent router, but not for gamers
Personally, the fact that it can't SQM Gigabit traffic visibly ruins online games for me (my RTT to Valve's Mumbai servers is 7ms).
It has a ton of shit running and phoning home that I do not have visiblity into (not just TR-069), in spite of having root, this list doesn't even include any wifi modules:
```
# lsmod
Module                  Size  Used by
mt7615_whnat 66505 0 - Live 0xc446e000
mt7603eap 2035359 0 - Live 0xc41f7000 (O)
sw_rps_for_wifi 6771 0 - Live 0xc3363000 (O)
mac_anti_spoofing 7136 0 - Live 0xc2c83000 (O)
ebt_tc 1152 0 - Live 0xc267a000
ebt_ftos 1248 0 - Live 0xc2661000
iptable_filter 928 1 - Live 0xc1c9b000
ovdsp 293630 2 - Live 0xc1c0f000 (O)
foip 390174 1 ovdsp, Live 0xc1b23000 (PO)
acodec_x 297679 1 ovdsp, Live 0xc1a03000 (PO)
ortp 135973 1 ovdsp, Live 0xc1948000 (O)
ksocket 4310 2 ovdsp,ortp, Live 0xc18f6000 (PO)
hw_nat 333826 0 - Live 0xc1837000 (PO)
swqos 15797 0 - Live 0xc17af000 (PO)
fxs3 375916 4 ovdsp,ortp, Live 0xc1732000 (PO)
multiwan 75126 0 - Live 0xc1711000 (O)
ponmacfilter 11658 0 - Live 0xc1657000 (O)
xpon_igmp 114938 1 multiwan, Live 0xc1620000 (O)
slic3 867101 1 fxs3, Live 0xc1534000 (PO)
ponvlan 221094 2 multiwan,xpon_igmp, Live 0xc149a000 (O)
spi 33792 1 slic3, Live 0xc12e4000 (PO)
lec 67858 1 fxs3, Live 0xc12bd000 (PO)
pcm1 25579 2 slic3,spi, Live 0xc1298000 (PO)
DSPCore 39551 6 ovdsp,ortp,fxs3,slic3,lec,pcm1, Live 0xc1279000 (PO)
sys_mod 5953 7 ovdsp,ortp,fxs3,slic3,spi,pcm1,DSPCore, Live 0xc1266000 (O)
xponmap 42290 3 hw_nat,multiwan,ponvlan, Live 0xc1189000 (O)
xpon 334602 6 ponmacfilter,xpon_igmp,ponvlan,xponmap, Live 0xc10e7000 (O)
phy 335486 0 - Live 0xc100d000 (O)
qdma_wan 271272 1 xpon, Live 0xc0f32000 (PO)
tcportbind 23781 2 multiwan,ponvlan, Live 0xc0eb8000 (O)
vlantag_ct 24311 2 multiwan,ponvlan, Live 0xc0e9f000 (O)
eth_ephy 96112 0 - Live 0xc0e71000 (PO)
eth 195713 6 ortp,hw_nat,xpon_igmp,ponvlan,xpon,eth_ephy, Live 0xc0e0a000 (PO)
ds_pm_counter 15424 0 - Live 0xc0daf000 (O)
qdma_lan 273198 1 hw_nat, Live 0xc0d5e000 (PO)
ifc 78371 2 qdma_wan,qdma_lan, Live 0xc0cd5000 (PO)
fe_core 61258 2 qdma_wan,ds_pm_counter, Live 0xc0ca2000 (PO)
ds_mdio 2610 1 eth, Live 0xc0c82000 (PO)
nlk_msg 1622 0 - Live 0xc0c47000 (O)
soft_rate_limit 10064 0 - Live 0xc0c1a000 (PO)
sif 24063 1 phy,[permanent], Live 0xc0bd3000 (PO)
tccicmd 80680 5 swqos,xpon,eth_ephy,eth,sif, Live 0xc0b94000 (PO)
tcledctrl 34358 9 mt7603eap,hw_nat,fxs3,slic3,xpon,eth,tccicmd, Live 0xc0b51000 (PO)
urlfilter 13402 0 - Live 0xc0b34000 (O)
accesslimit 25754 0 - Live 0xc0b15000 (O)
fuse 88201 0 - Live 0xc0acb000
usb_storage 41055 0 - Live 0xc0a6d000
vfat 9808 0 - Live 0xc0a4d000
fat 56735 1 vfat, Live 0xc0a34000
nls_cp936 120704 0 - Live 0xc09f8000
sd_mod 31411 0 - Live 0xc09c8000
scsi_mod 102263 2 usb_storage,sd_mod, Live 0xc0993000
ip6table_filter 864 1 - Live 0xc095a000
omci_intf_db 71421 8 multiwan,xpon_igmp,ponvlan,xponmap,xpon,tcportbind,vlantag_ct,eth, Live 0xc093d000 (PO)
dsnetutils 7837 2 ponvlan,omci_intf_db, Live 0xc091f000 (PO)
ds_dbg 6949 1 omci_intf_db, Live 0xc0911000 (PO)
module_sel 2392 1 pcm1, Live 0xc0904000 (PO)
maxnetdpi 4970 0 - Live 0xc08f7000 (O)
ebt_arp 1680 0 - Live 0xc088f000
ebt_vlan 1088 0 - Live 0xc0889000
ebt_mark 816 8 - Live 0xc0883000
ebtable_broute 912 1 - Live 0xc0879000
xt_connlimit 5200 0 - Live 0xc0872000
ebt_ip6 2080 5 - Live 0xc0866000
ebt_ip 2000 8 - Live 0xc085f000
ebtable_filter 1088 1 - Live 0xc0854000
ebtables 18668 2 ebtable_broute,ebtable_filter, Live 0xc084a000
ds_btn 1072 0 - Live 0xc083a000 (PO)
ds_notifier_chain 1024 0 - Live 0xc082f000 (PO)
dskproxy 10600 7 mt7603eap,multiwan,xpon,eth,ds_btn,ds_notifier_chain, Live 0xc0824000 (O)
jffs2 110654 1 - Live 0xc0741000
```
This one-liner should list all the tables / chains / rules
```
iptables -tfilter -vnxL;iptables -tnat -vnxL;iptables -tmangle -vnxL;iptables -traw -vnxL;iptables -tsecurity -vnxL | grep -vE 'pkts|Chain'
```
### Router hardware
The firmware was built as recently as 2021, the kernel , and sadly the Openwrt release it is based on is ancient:
```
# uname -a
Linux tc 3.18.21 #6 SMP Wed Mar 31 07:52:27 UTC 2021 mips unknown
```
The CPU appears to be a Dual Core (+2 threads) MIPS SoC with 256 MB RAM, similar to the [model_here] Xiaomi router.

It has 256 MB RAM and loads the / partition as: `/dev/mtdblock3 on / type squashfs (ro,relatime)`

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
- Recreate the rule without the the ports we need. This prevents traffic destined to {80,443} from being blackholed down the _acl_chain_ chain:
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
