-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2008 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local fs  = require "nixio.fs" 
local sys = require "luci.sys"

local m, s, p, ok
local cur_temp, cur_speed

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
	local uci = (require "luci.model.uci").cursor()
	local tmp_sens = uci:get("alpine-fan-control", "@alpine-fan-control[0]", "tmp_sens") or ""
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

function get_cur_speed()
	local FILE_SPEED
	local uci = (require "luci.model.uci").cursor()
	local drv_speed_max = uci:get("alpine-fan-control", "@alpine-fan-control[0]", "drv_speed_max") or "255"
	local fan_cont = uci:get("alpine-fan-control", "@alpine-fan-control[0]", "fan_cont") or ""
	if fan_cont ~= "" then
		FILE_SPEED = luci.sys.exec("grep -l -F " .. fan_cont .. " /sys/class/hwmon/hwmon*/name 2>/dev/null") or ""
		if FILE_SPEED ~= "" then
			FILE_SPEED = luci.sys.exec("dirname '" .. FILE_SPEED .. "' 2>/dev/null | xargs echo -n") or ""
			FILE_SPEED = FILE_SPEED .. "/pwm1"
			local cur_speed = luci.sys.exec("cat " .. FILE_SPEED .. " 2>/dev/null") or ""
			if cur_speed ~= "" then
				cur_speed = tonumber(cur_speed)
				drv_speed_max = tonumber(drv_speed_max)
				return tostring(math.floor(cur_speed * 100.0 / drv_speed_max))
			end
		end
	end
	return ""
end
ok, cur_speed = pcall(get_cur_speed)
if ok and cur_speed ~= nil and cur_speed ~= "" then
	msg = msg .. cur_speed .. "%"
end

msg = msg .. "<br />" .. translate("Current fan RPM:") .. " "
local rpm = luci.sys.exec("cat /sys/class/hwmon/hwmon*/fan1_input 2>/dev/null") or ""
msg = msg .. rpm 
m = Map("alpine-fan-control", translate("Fan Control"),	msg)

s = m:section(TypedSection, "alpine-fan-control", translate("Settings"))
s.addremove = false
s.anonymous = true

e = s:option(Flag, "enable", translate("Enabled"), translate("Start or stop the fan control daemon."))
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
dbg.default = "0"
dbg.rmempty = false
dbg.optional = false

min_temp = s:option(Value, "min_temp", translate("min_temp"), translate("Fan turn-on threshold (Celsius). Fan runs at T >= min_temp."))
min_temp.datatype = "range(1,150)"
min_temp.default = "45"
min_temp.rmempty = false
min_temp.optional = false

min_speed = s:option(Value, "min_speed", translate("min_speed"), translate("Fan speed (percent 0-100) at min_temp. Linear curve point."))
min_speed.datatype = "range(0,100)"
min_speed.default = "40"
min_speed.rmempty = false
min_speed.optional = false

med_temp = s:option(Value, "med_temp", translate("med_temp"), translate("Middle fan curve point (Celsius)."))
med_temp.datatype = "range(1,150)"
med_temp.default = "50"
med_temp.rmempty = false
med_temp.optional = false

med_speed = s:option(Value, "med_speed", translate("med_speed"), translate("Fan speed (percent 0-100) at med_temp. Linear curve point."))
med_speed.datatype = "range(0,100)"
med_speed.default = "60"
med_speed.rmempty = false
med_speed.optional = false

max_temp = s:option(Value, "max_temp", translate("max_temp"), translate("Upper fan curve point (Celsius). Above max_temp, max_speed is used."))
max_temp.datatype = "range(1,150)"
max_temp.default = "55"
max_temp.rmempty = false
max_temp.optional = false

max_speed = s:option(Value, "max_speed", translate("max_speed"), translate("Fan speed (percent 0-100) at max_temp and above. 100% maps to full drv_speed_max PWM."))
max_speed.datatype = "range(0,100)"
max_speed.default = "100"
max_speed.rmempty = false
max_speed.optional = false

interval = s:option(Value, "interval", translate("interval"), translate("Temperature polling interval in the daemon loop (seconds)."))
interval.datatype = "range(1,3600)"
interval.default = "5"
interval.rmempty = false
interval.optional = false

temp_hyst = s:option(Value, "temp_hyst", translate("temp_hyst"), translate("Hysteresis (Celsius). Fan off below (min_temp - temp_hyst). Speed increases apply immediately; speed decreases apply only after temperature drops by temp_hyst since the last speed change."))
temp_hyst.datatype = "range(0,99)"
temp_hyst.default = "2"
temp_hyst.rmempty = false
temp_hyst.optional = false

tmp_sens = s:option(Value, "tmp_sens", translate("tmp_sens"), translate("Thermal zone type name (sysfs: thermal_zone*/type)."))
tmp_sens.datatype = "string"
tmp_sens.default = "cpu0"
tmp_sens.rmempty = false
tmp_sens.optional = false

fan_cont = s:option(Value, "fan_cont", translate("fan_cont"), translate("Hwmon device name (sysfs: hwmon*/name; pwm1 is used for fan control)."))
fan_cont.datatype = "string"
fan_cont.default = "emc230"
fan_cont.rmempty = false
fan_cont.optional = false

drv_speed_min = s:option(Value, "drv_speed_min", translate("drv_speed_min"), translate("Minimum PWM value (0-65535, 16-bit). If the calculated speed maps to a PWM below this, the fan is turned off completely."))
drv_speed_min.datatype = "range(0,65535)"
drv_speed_min.default = "60"
drv_speed_min.rmempty = false
drv_speed_min.optional = false

drv_speed_max = s:option(Value, "drv_speed_max", translate("drv_speed_max"), translate("PWM value for 100% fan speed (16-bit, 1-65535; default 255 for 8-bit EMC230)."))
drv_speed_max.datatype = "range(1,65535)"
drv_speed_max.default = "255"
drv_speed_max.rmempty = false
drv_speed_max.optional = false

return m
