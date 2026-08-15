# openwrt-alpine-fan-control
Fan control daemon for OpenWrt with LuCI web interface.

Supports **sysfs** (kernel hwmon driver) and **I2C** (direct register access via `i2cset`/`i2cget`) PWM output methods.

## How it works

### Fan curve

Two-point linear interpolation:

```
min_temp / min_speed  ──linear──►  max_temp / max_speed
```

Above `max_temp` — fan runs at **100%** (not `max_speed`).

Example (default settings for AX9000):

| Temperature | Fan speed |
|-------------|-----------|
| < 52°C | 0% (off) |
| 55°C | 20% |
| 62.5°C | ~45% |
| 70°C | 70% |
| > 70°C | 100% |

### Speed control

- **Speed increases**: applied immediately (no delay).
- **Speed decreases**: gradual — half the PWM difference each cycle, until reaching target or within 1 PWM.
- **Fan off**: only when temperature drops below `(min_temp - temp_hyst)`, via forced PWM=0.

### Hysteresis (`temp_hyst`)

Hysteresis **only** controls on/off transitions:
- Fan turns **off** below `min_temp - temp_hyst`
- Fan turns **on** at `min_temp`

It does **not** delay speed changes — speed decreases are always gradual.

### Minimum PWM (`drv_speed_min`)

Calculated PWM values below `drv_speed_min` are **clamped** to `drv_speed_min` (fan stays on at minimum speed). The fan only turns off when temperature drops below the hysteresis threshold.

### PWM output methods

| Method | Description |
|--------|-------------|
| **sysfs** | Write PWM via `/sys/class/hwmon/.../pwm1` (kernel hwmon driver). Default. |
| **i2c** | Write EMC230 Fan Drive register directly via `i2cset` (full 8-bit PWM, bypasses kernel quantization on AX9000). Requires `i2c-tools`. |

When using I2C, optionally disable EMC2305 kernel thermal zones to prevent the kernel from overwriting PWM.

### Startup sequence

1. Set PWM to `drv_speed_start` (kickstart).
2. Verify fan RPM > 0 (up to 5 attempts × 1 second).
3. Enter main loop — first temperature-based interpolation after `interval` seconds.

### Emergency mode

Triggered if:
- Startup fan test fails (no RPM at `drv_speed_start`).
- Fan stall detected (PWM > 0 but RPM = 0 for 5 consecutive cycles).

Actions:
1. PWM set to `drv_speed_max`, verify RPM.
2. If still no RPM → PWM = 0 (fan stopped).
3. Temperature control disabled until service restart.

## Default configuration (AX9000)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `min_temp` | 55 | Fan turn-on threshold (°C) |
| `min_speed` | 20 | Fan speed (%) at min_temp |
| `max_temp` | 70 | Upper curve point (°C) |
| `max_speed` | 70 | Fan speed (%) at max_temp |
| `temp_hyst` | 3 | Hysteresis (°C) — on/off only |
| `interval` | 5 | Polling interval (seconds) |
| `drv_speed_min` | 50 | Minimum PWM (clamped, not off) |
| `drv_speed_start` | 120 | Kickstart PWM |
| `drv_speed_max` | 255 | Maximum PWM (100%) |
| `pwm_method` | i2c | PWM output: sysfs or i2c |
| `i2c_bus` | 0 | I2C bus |
| `i2c_addr` | 0x2f | EMC230 I2C address |
| `i2c_reg` | 0x30 | Fan Drive Setting register |

## Building

### Step 1
Add this feed to your `feeds.conf` in a fully set-up OpenWrt SDK:

```
echo "src-git alpinefancontrol https://github.com/kostik00/openwrt-alpine-fan-control.git" >> feeds.conf

./scripts/feeds update -a
./scripts/feeds install -a
```

### Step 2
Enable building the packages:
```
make menuconfig

LuCI -> 3. Applications -> luci-app-alpine-fan-control <*>
Utilities -> alpine-fan-control <*>
```

### Step 3
Build the packages:
```
make package/alpine-fan-control/compile V=s
make package/luci-app-alpine-fan-control/compile V=s
```

### Step 4
Install on the router:
```sh
apk add ./alpine-fan-control-*.apk ./luci-app-alpine-fan-control-*.apk
/etc/init.d/alpine-fan-control restart
```

## Diagnostics

```sh
# daemon logs
logread | grep alpine-fan-controller

# current config
uci show alpine-fan-control

# PWM / RPM / temperature
cat /sys/class/hwmon/hwmon*/pwm1
cat /sys/class/hwmon/hwmon*/fan1_input
cat /sys/class/thermal/thermal_zone*/temp
```

## License
GPL-3.0
