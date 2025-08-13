--[[
LuCI - Starfail Multi-Interface Failover Controller
Copyright (c) 2024 Starfail Team
Licensed under GPL-3.0-or-later
--]]

local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local util = require "luci.util"
local json = require "luci.jsonc"

module("luci.controller.starfail", package.seeall)

function index()
    -- Main menu entry
    entry({"admin", "network", "starfail"}, alias("admin", "network", "starfail", "overview"), _("Starfail Failover"), 60)
    
    -- Overview page
    entry({"admin", "network", "starfail", "overview"}, template("starfail/overview"), _("Overview"), 1)
    
    -- Configuration page
    entry({"admin", "network", "starfail", "config"}, cbi("starfail/config"), _("Configuration"), 2)
    
    -- Members page
    entry({"admin", "network", "starfail", "members"}, template("starfail/members"), _("Members"), 3)
    
    -- Telemetry page
    entry({"admin", "network", "starfail", "telemetry"}, template("starfail/telemetry"), _("Telemetry"), 4)
    
    -- Logs page
    entry({"admin", "network", "starfail", "logs"}, template("starfail/logs"), _("Logs"), 5)
    
    -- AJAX endpoints for dynamic data
    entry({"admin", "network", "starfail", "status"}, call("action_status")).leaf = true
    entry({"admin", "network", "starfail", "members_data"}, call("action_members_data")).leaf = true
    entry({"admin", "network", "starfail", "telemetry_data"}, call("action_telemetry_data")).leaf = true
    entry({"admin", "network", "starfail", "logs_data"}, call("action_logs_data")).leaf = true
    entry({"admin", "network", "starfail", "control"}, call("action_control")).leaf = true
end

-- Get overall status from starfaild
function action_status()
    local status = {
        daemon_running = false,
        current_member = nil,
        total_members = 0,
        active_members = 0,
        last_switch = nil,
        uptime = nil,
        errors = {}
    }
    
    -- Check if daemon is running
    local pid = sys.process.list()["starfaild"]
    status.daemon_running = pid ~= nil
    
    if status.daemon_running then
        -- Get status via ubus
        local result = util.exec("ubus call starfail status 2>/dev/null")
        if result and result ~= "" then
            local data = json.parse(result)
            if data then
                status.current_member = data.current_member
                status.total_members = data.total_members or 0
                status.active_members = data.active_members or 0
                status.last_switch = data.last_switch
                status.uptime = data.uptime
            end
        end
        
        -- Get errors if any
        local errors = util.exec("ubus call starfail errors 2>/dev/null")
        if errors and errors ~= "" then
            local error_data = json.parse(errors)
            if error_data and error_data.errors then
                status.errors = error_data.errors
            end
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(status)
end

-- Get members data
function action_members_data()
    local members = {}
    
    -- Get members list via ubus
    local result = util.exec("ubus call starfail members 2>/dev/null")
    if result and result ~= "" then
        local data = json.parse(result)
        if data and data.members then
            members = data.members
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(members)
end

-- Get telemetry data
function action_telemetry_data()
    local telemetry = {
        samples = {},
        events = {},
        health = {}
    }
    
    -- Get telemetry data via ubus
    local result = util.exec("ubus call starfail telemetry 2>/dev/null")
    if result and result ~= "" then
        local data = json.parse(result)
        if data then
            telemetry.samples = data.samples or {}
            telemetry.events = data.events or {}
            telemetry.health = data.health or {}
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(telemetry)
end

-- Get logs data
function action_logs_data()
    local logs = {}
    
    -- Get recent logs from starfaild
    local result = util.exec("logread | grep starfaild | tail -50 2>/dev/null")
    if result and result ~= "" then
        for line in result:gmatch("[^\r\n]+") do
            table.insert(logs, line)
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(logs)
end

-- Control actions (start/stop/restart/reload)
function action_control()
    local action = luci.http.formvalue("action")
    local response = { success = false, message = "" }
    
    if action == "start" then
        local result = util.exec("/etc/init.d/starfail start 2>&1")
        response.success = result:match("Starting") ~= nil
        response.message = result
    elseif action == "stop" then
        local result = util.exec("/etc/init.d/starfail stop 2>&1")
        response.success = result:match("Stopping") ~= nil
        response.message = result
    elseif action == "restart" then
        local result = util.exec("/etc/init.d/starfail restart 2>&1")
        response.success = result:match("Restarting") ~= nil
        response.message = result
    elseif action == "reload" then
        local result = util.exec("ubus call starfail reload 2>&1")
        response.success = result ~= "" and result:match("error") == nil
        response.message = result
    else
        response.message = "Invalid action"
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(response)
end
