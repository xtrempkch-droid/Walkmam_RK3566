#!/bin/sh
modprobe g_ether dev_addr=02:00:00:00:00:01 host_addr=02:00:00:00:00:02
sleep 2
ip link set dev usb0 up 2>/dev/null || true
ip addr add 10.55.0.1/24 dev usb0 2>/dev/null || true
