# OpenWrt 25.12 NSS build for the NEC Aterm WG2600HP

This branch builds OpenWrt 25.12.6 with Qualcomm NSS offloading for the first
generation NEC Aterm WG2600HP (IPQ8064) only.

- What is changed, how to build and how to install:
  [custom/README.md](custom/README.md)
- Images: the Releases page of this repository
- Base: [gyimesibalazs/openwrt-ipq806x-nss-25.12](https://github.com/gyimesibalazs/openwrt-ipq806x-nss-25.12),
  branch `ipq806x-nss-25.12.6`, commit `a0d03e3b8b`. Its README, which
  describes its own images for other devices, is kept as
  [README.base.md](README.base.md). This repository does not provide those
  images.
- The original OpenWrt README: [README.openwrt.md](README.openwrt.md)

This image was tested on one WG2600HP only. Use it at your own risk.
