#!/usr/bin/env bash
# install.sh — install x550vx-fanctl (script, config, systemd unit)
set -euo pipefail

PROG=x550vx-fanctl
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN=/usr/local/sbin/$PROG
CONF=/etc/$PROG.conf
UNIT=/etc/systemd/system/$PROG.service
DOC=/usr/local/share/doc/$PROG
MODULES_LOAD=/etc/modules-load.d/$PROG.conf

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }

echo "==> Checking dependencies"
missing=0
modinfo acpi_call >/dev/null 2>&1 || {
  echo "    acpi_call module not built. Install:"
  echo "      apt install acpi-call-dkms linux-headers-\$(uname -r) && dkms autoinstall"
  missing=1
}
if (( missing )); then
  read -r -p "    Install dependencies now via apt? [y/N] " a
  if [[ "${a:-}" =~ ^[yY]$ ]]; then
    apt update
    apt install -y acpi-call-dkms "linux-headers-$(uname -r)"
    dkms autoinstall
  else
    echo "Aborted — install dependencies first." >&2
    exit 1
  fi
fi

echo "==> Installing files"
install -Dm755 "$SRC_DIR/x550vx-fanctl" "$BIN"
install -Dm644 "$SRC_DIR/x550vx-fanctl.service" "$UNIT"
install -Dm644 "$SRC_DIR/README.md" "$DOC/README.md"
if [[ -f "$CONF" ]]; then
  echo "    $CONF already exists — keeping it (new default: $CONF.dist)"
  install -Dm644 "$SRC_DIR/x550vx-fanctl.conf" "$CONF.dist"
else
  install -Dm644 "$SRC_DIR/x550vx-fanctl.conf" "$CONF"
fi

echo "==> Loading acpi_call (persistent via modules-load.d)"
echo "acpi_call" > "$MODULES_LOAD"
modprobe acpi_call
[[ -e /proc/acpi/call ]] || { echo "ERROR: /proc/acpi/call still missing" >&2; exit 1; }

systemctl daemon-reload

echo
read -r -p "Enable + start $PROG.service now? [y/N] " a
if [[ "${a:-}" =~ ^[yY]$ ]]; then
  systemctl enable --now $PROG.service
  systemctl --no-pager --full status $PROG.service || true
else
  echo "Skipped. Later: systemctl enable --now $PROG.service"
fi

echo
echo "Done. Try:  sudo $BIN status"
