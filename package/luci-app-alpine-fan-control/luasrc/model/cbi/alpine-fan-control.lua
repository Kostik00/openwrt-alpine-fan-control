-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2008 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local m, s, p, ok
local cur_temp, cur_pwm, rpm

local defaults = {
	enable = "1",
	debug = "0",
	min_temp = "55",
	min_speed = "20",
	max_temp = "70",
	max_speed = "70",
	interval = "5",
	temp_hyst = "3",
	tmp_sens = "cpu0",
	fan_cont = "emc230",
	drv_speed_min = "50",
	drv_speed_start = "120",
	drv_speed_max = "255",
	pwm_method = "i2c",
	disable_thermal = "0",
	i2c_bus = "0",
	i2c_addr = "0x2f",
	i2c_reg = "0x30",
}

local function defaults_to_js(d)
	local t = {}
	for k, v in pairs(d) do
		t[#t + 1] = string.format("%q:%q", k, v)
	end
	return "{" .. table.concat(t, ",") .. "}"
end

local uci = (require "luci.model.uci").cursor()
local cfg = "@alpine-fan-control[0]"

local msg = translate("Service status:") .. " "

local service_running = (luci.sys.call("pgrep -f \"/alpine-fan-controller\" > /dev/null"))==0
if service_running then
    msg = msg .. "<span style=\"color:green;font-weight:bold\">" .. translate("Active") .. "</span>"
else
    msg = msg .. "<span style=\"color:red;font-weight:bold\">" .. translate("Inactive") .. "</span>"
end

msg = msg .. "<br />" .. translate("Current temperature:") .. " "

function get_cur_temp()
	local FILE_TEMP
	local tmp_sens = uci:get("alpine-fan-control", cfg, "tmp_sens") or ""
	if tmp_sens ~= "" then
		FILE_TEMP = luci.sys.exec("grep -l -F " .. tmp_sens .. " /sys/class/thermal/thermal_zone*/type 2>/dev/null") or ""
		if FILE_TEMP ~= "" then
			FILE_TEMP = luci.sys.exec("dirname '" .. FILE_TEMP .. "' 2>/dev/null | xargs echo -n") or ""
			FILE_TEMP = FILE_TEMP .. "/temp"
			local cur_temp = luci.sys.exec("cat " .. FILE_TEMP .. " 2>/dev/null") or ""
			if cur_temp ~= "" then
				cur_temp = tonumber(cur_temp)
				cur_temp = cur_temp / 1000.0
				return tostring(cur_temp)
			end
		end
	end
	return ""
end
ok, cur_temp = pcall(get_cur_temp)
if ok and cur_temp ~= nil and cur_temp ~= "" then
	msg = msg .. cur_temp .. " °C"
end

msg = msg .. "<br />" .. translate("Current fan speed:") .. " "

function get_cur_pwm()
	local FILE_PWM
	local fan_cont = uci:get("alpine-fan-control", cfg, "fan_cont") or ""
	if fan_cont ~= "" then
		FILE_PWM = luci.sys.exec("grep -l -F " .. fan_cont .. " /sys/class/hwmon/hwmon*/name 2>/dev/null") or ""
		if FILE_PWM ~= "" then
			FILE_PWM = luci.sys.exec("dirname '" .. FILE_PWM .. "' 2>/dev/null | xargs echo -n") or ""
			FILE_PWM = FILE_PWM .. "/pwm1"
			local pwm = luci.sys.exec("cat " .. FILE_PWM .. " 2>/dev/null") or ""
			if pwm ~= "" then
				return tonumber(pwm)
			end
		end
	end
	return nil
end

ok, cur_pwm = pcall(get_cur_pwm)
if ok and cur_pwm ~= nil and type(cur_pwm) == "number" then
	local drv_speed_max = tonumber(uci:get("alpine-fan-control", cfg, "drv_speed_max") or "255") or 255
	msg = msg .. tostring(math.floor(cur_pwm * 100.0 / drv_speed_max)) .. "%"
	msg = msg .. "<br />" .. translate("Current PWM:") .. " " .. tostring(cur_pwm)
end

msg = msg .. "<br />" .. translate("Current fan RPM:") .. " "

function get_cur_rpm()
	local fan_cont = uci:get("alpine-fan-control", cfg, "fan_cont") or ""
	if fan_cont ~= "" then
		local hwmon = luci.sys.exec("grep -l -F " .. fan_cont .. " /sys/class/hwmon/hwmon*/name 2>/dev/null") or ""
		if hwmon ~= "" then
			hwmon = luci.sys.exec("dirname '" .. hwmon .. "' 2>/dev/null | xargs echo -n") or ""
			local rpm = luci.sys.exec("cat " .. hwmon .. "/fan1_input 2>/dev/null") or ""
			return rpm
		end
	end
	return ""
end

ok, rpm = pcall(get_cur_rpm)
if ok and rpm ~= nil and rpm ~= "" then
	msg = msg .. rpm
end

m = Map("alpine-fan-control", translate("Fan Control"), msg)

function m.on_commit(self)
	luci.sys.call("/etc/init.d/alpine-fan-control reload >/dev/null 2>&1")
end

s = m:section(TypedSection, "alpine-fan-control", translate("Settings"))
s.addremove = false
s.anonymous = true

e = s:option(Flag, "enable", translate("Enabled"), translate("Start or stop the fan control daemon."))
e.default = defaults.enable
e.rmempty = false
function e.write(self, section, value)
    if value == "1" then
        luci.sys.call("/etc/init.d/alpine-fan-control start >/dev/null")
    else
        luci.sys.call("/etc/init.d/alpine-fan-control stop >/dev/null")
    end
    return Flag.write(self, section, value)
end

dbg = s:option(Flag, "debug", translate("Debug"), translate("Log debug messages to syslog."))
dbg.datatype = "uinteger"
dbg.default = defaults.debug
dbg.rmempty = false
dbg.optional = false

min_temp = s:option(Value, "min_temp", translate("min_temp"), translate("Fan turn-on threshold (Celsius). Fan runs at T >= min_temp."))
min_temp.datatype = "range(1,150)"
min_temp.default = defaults.min_temp
min_temp.rmempty = false
min_temp.optional = false

min_speed = s:option(Value, "min_speed", translate("min_speed"), translate("Fan speed (percent 0-100) at min_temp. Lower point of the linear curve."))
min_speed.datatype = "range(0,100)"
min_speed.default = defaults.min_speed
min_speed.rmempty = false
min_speed.optional = false

max_temp = s:option(Value, "max_temp", translate("max_temp"), translate("Upper point of the fan curve (Celsius). Linear ramp ends here at max_speed; above max_temp the fan runs at 100%."))
max_temp.datatype = "range(1,150)"
max_temp.default = defaults.max_temp
max_temp.rmempty = false
max_temp.optional = false

max_speed = s:option(Value, "max_speed", translate("max_speed"), translate("Fan speed (percent 0-100) at max_temp. Upper point of the linear curve."))
max_speed.datatype = "range(0,100)"
max_speed.default = defaults.max_speed
max_speed.rmempty = false
max_speed.optional = false

interval = s:option(Value, "interval", translate("interval"), translate("Temperature polling interval in the daemon loop (seconds)."))
interval.datatype = "range(1,3600)"
interval.default = defaults.interval
interval.rmempty = false
interval.optional = false

temp_hyst = s:option(Value, "temp_hyst", translate("temp_hyst"), translate("Hysteresis (Celsius). Fan off below (min_temp - temp_hyst). Speed increases apply immediately; speed decreases apply only after temperature drops by temp_hyst since the last speed change."))
temp_hyst.datatype = "range(0,99)"
temp_hyst.default = defaults.temp_hyst
temp_hyst.rmempty = false
temp_hyst.optional = false

tmp_sens = s:option(Value, "tmp_sens", translate("tmp_sens"), translate("Thermal zone type name (sysfs: thermal_zone*/type)."))
tmp_sens.datatype = "string"
tmp_sens.default = defaults.tmp_sens
tmp_sens.rmempty = false
tmp_sens.optional = false

fan_cont = s:option(Value, "fan_cont", translate("fan_cont"), translate("Hwmon device name (sysfs: hwmon*/name; pwm1 is used for fan control)."))
fan_cont.datatype = "string"
fan_cont.default = defaults.fan_cont
fan_cont.rmempty = false
fan_cont.optional = false

drv_speed_min = s:option(Value, "drv_speed_min", translate("drv_speed_min"), translate("Minimum PWM value (0-65535, 16-bit). If the calculated speed maps to a PWM below this, the fan is turned off completely."))
drv_speed_min.datatype = "range(0,65535)"
drv_speed_min.default = defaults.drv_speed_min
drv_speed_min.rmempty = false
drv_speed_min.optional = false

drv_speed_start = s:option(Value, "drv_speed_start", translate("drv_speed_start"), translate("Kickstart PWM (0-65535): used for startup fan test and when spinning up from stop (0.5s before the target PWM)."))
drv_speed_start.datatype = "range(0,65535)"
drv_speed_start.default = defaults.drv_speed_start
drv_speed_start.rmempty = false
drv_speed_start.optional = false

drv_speed_max = s:option(Value, "drv_speed_max", translate("drv_speed_max"), translate("PWM value for 100% fan speed (16-bit, 1-65535; default 255 for 8-bit EMC230)."))
drv_speed_max.datatype = "range(1,65535)"
drv_speed_max.default = defaults.drv_speed_max
drv_speed_max.rmempty = false
drv_speed_max.optional = false

pwm_method = s:option(ListValue, "pwm_method", translate("PWM output method"),
	translate("'sysfs' uses kernel hwmon driver. 'i2c' writes EMC230 Fan Drive register directly via i2cset (full 8-bit PWM, bypasses kernel quantization on AX9000)."))
pwm_method:value("sysfs", translate("sysfs (kernel hwmon)"))
pwm_method:value("i2c", translate("I2C (direct i2cset)"))
pwm_method.default = defaults.pwm_method
pwm_method.rmempty = false

disable_thermal = s:option(Flag, "disable_thermal", translate("Disable kernel thermal"),
	translate("Disable EMC2305 kernel thermal zones on start. Prevents the kernel from overwriting PWM set via I2C. Enable if the kernel thermal driver interferes with direct I2C control."))
disable_thermal.default = defaults.disable_thermal
disable_thermal.rmempty = false
disable_thermal:depends("pwm_method", "i2c")

i2c_bus = s:option(Value, "i2c_bus", translate("i2c_bus"), translate("I2C bus number (AX9000: 0)."))
i2c_bus.datatype = "range(0,99)"
i2c_bus.default = defaults.i2c_bus
i2c_bus:depends("pwm_method", "i2c")

i2c_addr = s:option(Value, "i2c_addr", translate("i2c_addr"), translate("EMC230 I2C address (AX9000: 0x2f)."))
i2c_addr.datatype = "string"
i2c_addr.default = defaults.i2c_addr
i2c_addr:depends("pwm_method", "i2c")

i2c_reg = s:option(Value, "i2c_reg", translate("i2c_reg"), translate("Fan Drive Setting register (PWM1: 0x30)."))
i2c_reg.datatype = "string"
i2c_reg.default = defaults.i2c_reg
i2c_reg:depends("pwm_method", "i2c")

reset_link = s:option(DummyValue, "_reset", translate("Reset to defaults"),
	translate("Fill the form with factory defaults. Press Save to apply changes."))
reset_link.rawhtml = true

function reset_link.cfgvalue()
	return string.format(
		'<input type="button" class="btn cbi-button-action important" id="alpine-fan-reset-btn" ' ..
		'style="cursor:pointer" value="%s" />',
		translate("Reset to defaults"))
end

function m.render(self, ...)
	Map.render(self, ...)
	luci.http.write(string.format([[
<script type="text/javascript">
function alpineFanControlApplyDefaults() {
	var d = %s;
	if (!confirm(%s)) return;
	for (var k in d) {
		if (!Object.prototype.hasOwnProperty.call(d, k)) continue;
		var nodes = document.querySelectorAll("[name$='." + k + "']");
		for (var i = 0; i < nodes.length; i++) {
			var el = nodes[i];
			if (el.type === "checkbox") el.checked = (d[k] === "1");
			else if (el.tagName === "SELECT") { el.value = d[k]; el.dispatchEvent(new Event("change", {bubbles:true})); }
			else el.value = d[k];
		}
	}
}
(function() {
	function bind() {
		var btn = document.getElementById("alpine-fan-reset-btn");
		if (!btn || btn._alpineBound) return;
		btn._alpineBound = true;
		btn.addEventListener("click", alpineFanControlApplyDefaults);
	}
	if (document.readyState === "loading")
		document.addEventListener("DOMContentLoaded", bind);
	else
		bind();
})();
</script>]], defaults_to_js(defaults), string.format("%q", translate("Restore factory defaults?"))))
end

return m
