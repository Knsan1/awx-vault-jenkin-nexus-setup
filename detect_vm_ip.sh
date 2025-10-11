#!/usr/bin/env bash
set -euo pipefail

# Try common interfaces first, then fall back
for iface in eth0 ens3 ens4 enp0s3 enp0s8 ens160 wlan0 eno1; do
  if ip -4 addr show "$iface" &>/dev/null; then
    ip -4 addr show "$iface" | awk '/inet /{print $2}' | cut -d/ -f1 | head -1 && exit 0
  fi
done

# Generic fallback
ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1"
