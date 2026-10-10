#!/usr/bin/env bash
# uninstall.sh — remove x550vx-fanctl and restore automatic fan control
set -euo pipefail

PROG=x550vx-fanctl
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }

echo "==> Restoring automatic fan control (SFNV 0 0)"
if [[ -e /proc/acpi/call ]]; then
  echo '\_SB.PCI0.LPCB.EC0.SFNV 0 0' > /proc/acpi/call && echo "    OK" || true
else
  echo "    /proc/acpi/call missing — nothing to restore (EC is already auto after reboot)"
fi

echo "==> Stopping and removing service"
systemctl disable --now $PROG.service 2>/dev/null || true
rm -f /etc/systemd/system/$PROG.service
systemctl daemon-reload

echo "==> Removing files"
rm -f /usr/local/sbin/$PROG
rm -rf /usr/local/share/doc/$PROG
rm -f /etc/modules-load.d/$PROG.conf
read -r -p "Remove config /etc/$PROG.conf too? [y/N] " a
[[ "${a:-}" =~ ^[yY]$ ]] && rm -f /etc/$PROG.conf /etc/$PROG.conf.dist

echo "Done. Kernel module acpi_call left loaded (harmless)."
