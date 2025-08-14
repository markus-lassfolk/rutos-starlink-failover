-- Luacheck configuration for LuCI development
-- https://luacheck.readthedocs.io/en/stable/config.html

std = "lua54"
cache = true

-- Global LuCI variables and functions
globals = {
    -- LuCI core globals
    "luci",
    "uci",
    "nixio",
    "sys",
    "util",
    "ip",
    "fs",
    "dispatcher",
    "http",
    "template",
    "model",
    "cbi",
    
    -- OpenWrt/UCI globals
    "_",
    "translate",
    "translatef",
    "ntranslate",
    
    -- Common Lua web development patterns
    "arg",
    "module",
    "require",
    "pcall",
    "xpcall",
    "getfenv",
    "setfenv",
    "loadstring",
    "unpack",
    
    -- LuCI HTTP/Template globals
    "REQUEST_URI",
    "SCRIPT_NAME",
    "PATH_INFO",
    "QUERY_STRING",
}

-- Ignore certain warnings
ignore = {
    "211", -- Unused local variable
    "212", -- Unused argument
    "213", -- Unused loop variable
    "221", -- Local variable is accessed but never set
    "231", -- Local variable is set but never accessed
    "311", -- Value assigned to a local variable is unused
    "314", -- Value of field is unused
    "431", -- Shadowing upvalue
    "432", -- Shadowing upvalue argument
    "433", -- Shadowing upvalue loop variable
}

-- File-specific overrides
files["applications/"] = {
    globals = {
        "entry",
        "call",
        "alias",
        "leaf",
        "arcombine",
        "form",
        "cbi",
        "template",
    }
}

files["luasrc/"] = {
    std = "lua54+luci"
}

files["htdocs/"] = {
    std = "lua54+luci+web"
}

-- Exclude certain directories/files
exclude_files = {
    "luasrc/version.lua",
    "**/build/**",
    "**/dist/**",
    "**/node_modules/**",
    "**/tmp/**",
}

-- Maximum line length
max_line_length = 120
