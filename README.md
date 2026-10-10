# x550vx-fanctl

Configurable fan control for the **ASUS X550VX** (and likely other X55x models
sharing the same EC/ACPI interface) — including a true fan-off, which the
kernel driver (`asus-nb-wmi`, Spec 8.3) cannot do.

Works by calling the ACPI methods exposed by the notebook's embedded
controller through `acpi_call`.

## How it works

From the decompiled X550VX DSDT (`_SB.PCI0.LPCB.EC0`):

| Method | Meaning |
|---|---|
| `SFNV 0 x`  | **Automatic** — sets bit `0x80` in `EC[0x0521]`/`EC[0x0522]` (auto flag per fan) |
| `SFNV 1 v`  | **Fan1 manual** — clears `EC[0x0521].bit7`, then `ST84(0, v)` writes raw speed (0–255, verified: `0` = fan fully stopped) |
| `SFNV 2 v`  | **Fan2 manual** — same via `EC[0x0522]` (GPU fan on dual-fan models; X550VX has only one fan) |
| `TACH n`    | Real RPM of fan `n` |
| `RRAM`/`WRAM` | Raw EC RAM read/write (16-bit address space) |

The standard `pwm1_enable` sysfs knob on this model only accepts `0` (full
speed) and `2` (auto) — manual mode is rejected (`EINVAL`), and `pwm1` does
not exist. `SFNV` is the way in.

> Manual mode persists until firmware calls `SFNV 0` again — e.g. on a
> thermal event or suspend/resume. The daemon re-asserts the configured
> speed every `KEEPALIVE_INTERVAL` seconds to be safe.

## Requirements

- ASUS X550VX (or a compatible ASUS with `SFNV`/`RRAM`/`WRAM`/`TACH` in DSDT)
- `acpi_call` kernel module: `apt install acpi-call-dkms linux-headers-$(uname -r)`
- root (all EC writes)

## Install

```bash
sudo ./install.sh        # installs script, config, systemd unit; loads acpi_call
```

This installs:

| Path | Purpose |
|---|---|
| `/usr/local/sbin/x550vx-fanctl` | the tool |
| `/etc/x550vx-fanctl.conf` | daemon configuration (curve, safety) |
| `/etc/systemd/system/x550vx-fanctl.service` | curve daemon |
| `/etc/modules-load.d/x550vx-fanctl.conf` | loads `acpi_call` at boot |

Remove later with `sudo ./uninstall.sh` (restores auto control first).

## Usage

```
x550vx-fanctl status            temp, RPM (TACH 0/1), manual/auto mode
x550vx-fanctl set <0-255>       manual speed (0 = off)
x550vx-fanctl off               stop the fan completely
x550vx-fanctl auto              return to automatic EC control
x550vx-fanctl daemon            foreground curve loop (what systemd runs)
x550vx-fanctl ec TACH 0         raw acpi_call passthrough (debugging)
```

Daemon operation:

```bash
sudo systemctl enable --now x550vx-fanctl.service
journalctl -u x550vx-fanctl -f
```

## Configuration — `/etc/x550vx-fanctl.conf`

| Variable | Default | Meaning |
|---|---|---|
| `POLL_INTERVAL` | `2` | seconds between temperature checks |
| `FANS` | `"1"` | fans to manage (`1`, `2`, or `"1 2"`; X550VX = `1`) |
| `CRIT_TEMP` | `90` | °C emergency — restore auto + exit |
| `MIN_SPEED_DELTA` | `10` | raw-unit change required to re-write (jitter filter) |
| `KEEPALIVE_INTERVAL` | `30` | s — re-assert manual speed (0 disables) |
| `RESTORE_AUTO_ON_EXIT` | `yes` | hand control back to EC on daemon stop |
| `CURVE_TEMPS` | `(45 60 70 80)` | °C, strictly ascending |
| `CURVE_SPEEDS` | `(0 80 160 255)` | raw EC speed units at each point |

The curve is piecewise-linear between points; outside the range, the nearest
endpoint is used. The default keeps the fan **off below 45 °C** and reaches
full speed at 80 °C.

Raw speed units are EC command `0x84` data (0–255). If you calibrate the
mapping to RPM for your unit, please contribute the numbers back.

## Safety

- **Fan off under load = overheating.** `CRIT_TEMP` is the last-resort guard;
  keep it ≥ 85 °C. Below that, CPU thermal throttling / emergency shutdown is
  handled by the hardware itself.
- `uninstall.sh` restores automatic control before removing anything.
- EC register writes are outside kernel control — this tool only uses
  documented `SFNV` semantics verified on X550VX, but always verify on your
  own hardware first (`status`, `ec` passthrough).

## Troubleshooting

- `/proc/acpi/call missing` → `acpi_call` not built/loaded; run `install.sh`
  or `modprobe acpi_call` (needs `acpi-call-dkms` + `linux-headers`).
- Fan speeds back up by itself → firmware ran `SFNV 0` (thermal event /
  suspend). The daemon's keepalive re-asserts the manual speed; check
  `journalctl -u x550vx-fanctl`.
- `SFNV …` returns an error → your model's DSDT differs; inspect methods with
  `sudo iasl -d` (package `acpica-tools`) and adjust.

## Credits / references

- [dominiksalvet/asus-fan-control](https://github.com/dominiksalvet/asus-fan-control)
  — model detection & EC curve approach (issue
  [#176](https://github.com/dominiksalvet/asus-fan-control/issues/176) tracked
  X550VX support)
- [nbfc-linux docs](https://nbfc-linux.github.io/creating-config/) — EC fan
  methods on ASUS laptops
- DSDT analysis of X550VX.305 BIOS (methods `SFNV`, `ST84`, `TACH`, `RRAM`,
  `WRAM`)

## License

Unreleased / private work-in-progress — decide before publishing.
