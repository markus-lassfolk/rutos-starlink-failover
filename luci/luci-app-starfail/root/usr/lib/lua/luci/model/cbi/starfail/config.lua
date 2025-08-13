--[[
LuCI - Starfail Configuration Model
Copyright (c) 2024 Starfail Team
Licensed under GPL-3.0-or-later
--]]

local uci = require "luci.model.uci".cursor()

m = Map("starfail", translate("Starfail Multi-Interface Failover Configuration"))

-- Main configuration section
s = m:section(TypedSection, "main", translate("Main Settings"))
s.anonymous = true

-- Enable/Disable
enable = s:option(Flag, "enable", translate("Enable Starfail"))
enable.default = "1"
enable.rmempty = false

-- Use mwan3 integration
use_mwan3 = s:option(Flag, "use_mwan3", translate("Use mwan3 Integration"))
use_mwan3.default = "1"
use_mwan3.description = translate("Enable integration with mwan3 for policy routing")

-- Poll interval
poll_interval = s:option(Value, "poll_interval_ms", translate("Poll Interval (ms)"))
poll_interval.default = "5000"
poll_interval.datatype = "uinteger"

-- Decision interval
decision_interval = s:option(Value, "decision_interval_ms", translate("Decision Interval (ms)"))
decision_interval.default = "5000"
decision_interval.datatype = "uinteger"

-- Log level
log_level = s:option(ListValue, "log_level", translate("Log Level"))
log_level:value("debug", translate("Debug"))
log_level:value("info", translate("Info"))
log_level:value("warn", translate("Warning"))
log_level:value("error", translate("Error"))
log_level.default = "info"

-- Switch margin
switch_margin = s:option(Value, "switch_margin", translate("Switch Margin"))
switch_margin.default = "10"
switch_margin.datatype = "uinteger"

-- Min uptime
min_uptime = s:option(Value, "min_uptime_s", translate("Minimum Uptime (seconds)"))
min_uptime.default = "30"
min_uptime.datatype = "uinteger"

-- Cooldown
cooldown = s:option(Value, "cooldown_s", translate("Cooldown Period (seconds)"))
cooldown.default = "60"
cooldown.datatype = "uinteger"

-- Metrics section
s2 = m:section(TypedSection, "main", translate("Monitoring"))
s2.anonymous = true

-- Metrics listener
metrics_listener = s2:option(Flag, "metrics_listener", translate("Enable Metrics Server"))
metrics_listener.default = "0"

-- Metrics port
metrics_port = s2:option(Value, "metrics_port", translate("Metrics Port"))
metrics_port.default = "9090"
metrics_port.datatype = "port"
metrics_port:depends("metrics_listener", "1")

-- Health listener
health_listener = s2:option(Flag, "health_listener", translate("Enable Health Server"))
health_listener.default = "1"

-- Health port
health_port = s2:option(Value, "health_port", translate("Health Port"))
health_port.default = "8080"
health_port.datatype = "port"
health_port:depends("health_listener", "1")

return m
