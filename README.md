# H680GM-A
Notes and scripts for the Dasan Networks H680GM-A (Airtel) GPON ONT / router

Poke around the scripts, they have tips and examples for figuring this out on any router.
### TLDR
[Getting port 80 and 443 forwards to work](https://github.com/Strykar/H680GM-A#tldr---getting-port-80-and-443-forwarded)

[Getting native IPv6 to work with a static IPv4 assigned]

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

![image](https://user-images.githubusercontent.com/2946372/231237158-4f1219e7-9183-4921-bf03-ff17f6652395.png)
[Image courtesy - https://twitter.com/geekyranjit/status/1403558141002850307]

I get a static IPv4 from my ISP (Airtel, via IPoE apparently) and this works well for the most part.

![wan_v4](https://user-images.githubusercontent.com/2946372/233778264-339855cf-560f-4d5c-8634-cc767c253f9e.png)

Airtel's prepping for IPTV and the IPoE / PPPoE requests only see responses over VLAN 100.

Unfortunately the Dasan firmware on the device does not account for this mysterious customer configuration.
Thus it is impossible to configure a static IPv4 WAN address with IPv6, unless the IPv6 type is static too.. yea.

![reserved_port_range](https://user-images.githubusercontent.com/2946372/233778081-4d427d18-4ab8-4be0-a055-99318b78b435.png)

Take note that port 22 is not on the list above.[^1]

The other issue that was getting my goat was that the router was preventing port forwarding for a few ports.
I needed ports 80 and 443 open and forwarded and this made me dig into the router a little bit.

Having root ssh access helped..

## TLDR - Getting port 80 and 443 forwarded
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
