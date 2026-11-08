# Custom NSS build for the NEC Aterm WG2600HP

This branch is an OpenWrt 25.12.6 build with NSS offloading for the first
generation NEC Aterm WG2600HP (IPQ8064). It is based on
gyimesibalazs/openwrt-ipq806x-nss-25.12, with a few fixes.

- Base: [gyimesibalazs/openwrt-ipq806x-nss-25.12](https://github.com/gyimesibalazs/openwrt-ipq806x-nss-25.12),
  branch `ipq806x-nss-25.12.6`, commit `a0d03e3b8b` (OpenWrt 25.12.6
  `r33311`, kernel 6.12.112, swconfig, qca-nss-gmac, NSS and ECM). The base
  is a port of the NSS support of tingalvin/r7800 to OpenWrt 25.12.
- Feeds: pinned to fixed commits in `feeds.conf.default` of the base, used as
  is. tailscale 1.104.1 and Go 1.27 come from the openwrt-25.12 packages feed.
- Package manager: apk (OpenWrt 25.12).
- Images: see the Releases page of this repository.

The GitHub fork relation of this repository (tingalvin/r7800) is from an
earlier 24.10 build, which has been removed.

## Changes from the base

| # | Change | Where |
|---|---|---|
| 1 | qca-nss-ecm: start the standard profile at boot, work with firewall4 | commit on this branch |
| 2 | qca-nss-ecm: `accel_delay_pkts` 1 → 24 | commit on this branch |
| 3 | qca-nss-clients tunipip6: fix the dst leak in the encap exception path | commit on this branch |
| 4 | qca-nss-ecm: enable interface features only for kmods built into the image | commit on this branch |
| 5 | qca-nss-ecm: enable conntrack events while ECM is loaded (MAP-E fix) | commit on this branch |
| 6 | Image: check that the sysupgrade image fits (24192k) | commit on this branch |
| 7 | The GitHub workflow of the base is removed | commit on this branch |
| 8 | First-boot defaults for NSS | `custom/files/wg2600hp/etc/uci-defaults/98-wg2600hp-nss-defaults` |
| 9 | Config: WG2600HP only, package selection, `CONFIG_ALL_KMODS=y` | `custom/configs/wg2600hp.config` |
| 10 | Top-level README points here; the base's README is kept as `README.base.md` | commit on this branch |

These parts of the base are kept unchanged:

- NSS CPU spreading: the init script of qca-nss-drv moves the IRQ of the
  second NSS core to CPU1, and the packet steering hook of qca-nss-drv sets
  the RPS of `eth*` to 0 after the generic packet steering script.
- The kernel, NSS firmware and drivers, and the swconfig device tree of the
  WG2600HP.

These parts of the base are not used:

- The config seeds `diff` and `diff-c2600` (distribution name "OpenWrt NSS",
  other devices). The config of this build is `custom/configs/wg2600hp.config`.
- `VHTNSS.zip` (LuCI patches that the base's workflow applies to the feeds).

### 1. ECM start-up and firewall4

- `kmod-qca-nss-ecm-standard` now depends on `iptables-nft` and
  `iptables-mod-physdev`, which its firewall script uses.
- Its init script is installed as an `rc.common` script, so ECM starts at boot.
- The firewall include is registered as `fw4_compatible`. It starts ECM, in
  case the firewall comes up first, and flushes the accelerated connections
  after a firewall reload.
- The bridge netfilter sysctls are written to
  `/etc/sysctl.d/99-qca-nss-ecm.conf`, so they are applied after the
  defaults.

### 2. `accel_delay_pkts=24`

ECM handles the first `accel_delay_pkts` packets of each connection on the CPU
and then passes the connection to NSS.

- With the original `1`, ECM does not accelerate non-TCP connections until it
  has seen packets in both directions. DS-Lite, MAP-E and one-way UDP therefore
  stayed on the CPU.
- With `24`, NSS handles all of these.

Notes:

- Any value other than `1` applies the DSCP and mark seen in one direction to
  both directions. This can affect QoS classification and mwan3 or policy
  routing marks.
- To change the value, edit the `echo 24 > .../accel_delay_pkts` line in
  `load_ecm()` of `/etc/init.d/qca-nss-ecm`, then run
  `/etc/init.d/qca-nss-ecm restart`. A sysupgrade restores 24.

### 3. tunipip6 (DS-Lite/MAP-E) dst leak

This is the upstream Qualcomm fix (qca-nss-clients `ec7a57b`). It releases the
route looked up in `nss_tunipip6_encap_exception()`. Without it, every such
packet leaks a dst entry, and `ip_dst_cache` grows without bound. The patch is
`140-...`, because `130` is used by the Linux 6.12 patch of the package.

### 4. ECM features and `CONFIG_ALL_KMODS`

`CONFIG_ALL_KMODS=y` builds every kmod, so that kmods can be added later. It
also turns `kmod-sit`, `kmod-pppol2tp`, `kmod-macvlan` and `kmod-ipsec` into
`=m`. The original Makefile then built ECM with features that the NSS driver
of this tree does not have, and the build failed. ECM now enables those
features only for kmods that are built into the image (`=y`).

### 5. Conntrack events (MAP-E fix)

On Linux 6.x, `net.netfilter.nf_conntrack_events` defaults to `2`: the
per-connection event data is allocated only while a ctnetlink listener (such
as `conntrack -E`) is running. Without one, ECM is not told when a connection
is destroyed, and the NSS rule of a closed connection stays.

With MAP-E, which maps source ports into a small port set, a new connection
that reuses a LAN-side address and port was then translated with the old rule
and stalled. In a test with many short TCP connections, 19 of 141 test runs
had stalled connections.

The ECM init script now sets `nf_conntrack_events` to `1` when it loads ECM
and back to `2` when it unloads ECM, as qosmio/nss-packages does. With this, no
connection stalled in 284 test runs. The extra memory is about 16 bytes per
connection.

### 6. Image size check

The sysupgrade image must fit the firmware partitions (24192k). With this
check, an image that is too large fails the build instead of being produced.

### 7. GitHub workflow

The base has a workflow that builds images for other devices with another
config and publishes them on `v*` tags. This branch is built locally with
`custom/build.sh`, so the workflow is removed.

### 8. First-boot defaults

On the first boot, `98-wg2600hp-nss-defaults` makes these settings:

- Turns off the firewall's software and hardware flow offloading. These are
  not NSS switches, and with software flow offloading on, IPv4 and PPPoE
  traffic bypasses NSS.
- Turns off packet steering.
- Sets the ECM acceleration engine to `nss`.

### 9. Config

The config contains the following:

| Area | Packages and settings |
|---|---|
| Device | ipq806x / generic / NEC WG2600HP |
| Switch and Ethernet | swconfig, qca-nss-gmac |
| Offloading | qca-nss-drv, qca-nss-ecm-standard, NSS PPPoE and tunipip6 clients |
| WAN | PPPoE, DS-Lite, MAP-E (`map`), odhcp6c |
| VPN | WireGuard (`kmod-wireguard`, `wireguard-tools`, `luci-proto-wireguard`), tailscale |
| Management and monitoring | LuCI, conntrack, `collectd`, `luci-app-statistics`, `collectd-mod-sensors` |
| Wireless | QCA99x0 board data, ath10k-ct |
| Build | `CONFIG_ALL_KMODS=y`; `CONFIG_KERNEL_BUILD_USER="builder"` and `CONFIG_KERNEL_BUILD_DOMAIN="buildhost"` |

`CONFIG_ALL_KMODS=y` alone would also select some NSS-related kmods and change
the NSS driver and ECM that go into the image. The config disables them. This
covers `kmod-bonding` and the kmods that select it (`kmod-qca-mcs` and the
other ECM variant), and the optional NSS feature kmods (crypto, qdisc, L2TP,
6rd, ...). These NSS kmods cannot be added later.

## tailscale

- The image includes tailscale 1.104.1 from the openwrt-25.12 packages feed
  (`tailscale` and `tailscaled`). tailscale is licensed under the BSD-3-Clause
  license; see its
  [LICENSE](https://github.com/tailscale/tailscale/blob/v1.104.1/LICENSE).
  This build is not affiliated with Tailscale Inc.
- The image contains no tailscale login or state. `tailscaled` starts at boot
  but is not logged in. Run `tailscale up` on the router and log in with the
  URL it prints.
- The version is fixed when the image is built. There is no room in the
  overlay to update it on the router. To update tailscale, rebuild the image
  with a newer packages feed and run `sysupgrade` without `-n`. This keeps
  `/etc/config` and the tailscale login in `/etc/tailscale`.

### Building without tailscale

1. In `custom/configs/wg2600hp.config`, replace

   ```
   CONFIG_PACKAGE_tailscale=y
   ```

   with

   ```
   # CONFIG_PACKAGE_tailscale is not set
   ```

2. Build as below.

Go is then not built at all, which saves most of the build time, and the image
is much smaller.

## Building

On a host that can build OpenWrt (see the OpenWrt build system documentation):

```sh
git clone -b custom/ipq806x-nss-25.12.6 https://github.com/<this repository>.git openwrt
cd openwrt
custom/build.sh wg2600hp -j$(nproc)
```

`custom/build.sh` does the following:

1. Sets `LC_ALL=C`, because the prerequisite checks parse English output.
2. Checks that every feed in `feeds.conf.default` is pinned to a commit,
   writes `feeds.conf` from it, updates the feeds and checks the checked-out
   commits.
3. Installs the feeds.
4. Puts `custom/files/wg2600hp` in place as `files/`.
5. Copies the config to `.config`.
6. Runs `make defconfig`, `make download` and `make`.

The image is in `bin/targets/ipq806x/generic/`. Building Go from source takes a
while.

## Installing

These steps apply to a WG2600HP that already runs OpenWrt. For the first
installation from the NEC stock firmware (serial console and TFTP), see the
[OpenWrt wiki page for the WG2600HP](https://openwrt.org/toh/hwdata/nec/nec_aterm_wg2600hp).

**Install without keeping settings (`sysupgrade -n`)** when coming from
another build. This includes the earlier 24.10 build of this repository:

- Official OpenWrt releases use DSA, and this image uses swconfig, so their
  network configuration is not compatible.
- OpenWrt 25.12 uses apk instead of opkg. Packages added to a 24.10 build
  cannot be kept.

```sh
ssh root@192.168.1.1 'sysupgrade -b /tmp/backup.tar.gz && cat /tmp/backup.tar.gz' > backup-before.tar.gz
cat openwrt-ipq806x-generic-nec_wg2600hp-squashfs-sysupgrade.bin | ssh root@192.168.1.1 'cat > /tmp/fw.bin'
ssh root@192.168.1.1 'sha256sum /tmp/fw.bin; sysupgrade -T /tmp/fw.bin && echo OK'
ssh root@192.168.1.1 'sysupgrade -n /tmp/fw.bin'
```

The router then starts in the default state:

- LAN address 192.168.1.1
- no root password
- wireless disabled

Set a root password first. To check that NSS is working:

```sh
dmesg | grep -E "nss core [01] booted"
lsmod | grep -E "^(ecm|qca_nss_drv|qca_nss_gmac|qca_nss_pppoe|qca_nss_tunipip6) "
cat /sys/kernel/debug/ecm/ecm_classifier_default/accel_delay_pkts    # 24
cat /proc/sys/net/netfilter/nf_conntrack_events                      # 1
```

## Notes

- Do not turn on software or hardware flow offloading in LuCI. Leave packet
  steering off. SQM (`sqm-scripts`) runs on the CPU and bypasses NSS.
- You can add other packages (`apk add`) from the official 25.12.6 feeds.
  The exception is kernel modules (`kmod-*`): the official ones do not match
  this kernel, so use the ones from your own build of this branch
  (`bin/targets/ipq806x/generic/packages/`).
- The overlay has about 6.4 MiB free after the first boot.

## Tests

The image was tested on one WG2600HP, with wired traffic only:

- NSS offloading: TCP and UDP over plain IPv4, PPPoE, IPv6, DS-Lite and MAP-E
  ran at line rate with the CPU mostly idle. WireGuard runs on the CPU (about
  330 to 380 Mbit/s for one TCP flow).
- A two-hour load test over these WAN types, with many short connections:
  no reboot, no kernel warning, no growth of memory use. This test found the
  MAP-E stall that change 5 fixes.
- MAP-E with many short connections after the fix in change 5: no stalled
  connection in 284 test runs.

Not tested: wireless throughput, long-term use, repeated reboots.

This image was tested on one WG2600HP only. Use it at your own risk.

## License

Same as OpenWrt and the respective packages (mostly GPL-2.0). The patches in this
branch are under the license of the files they modify.
