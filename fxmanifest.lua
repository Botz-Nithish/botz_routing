--[[
    Forza Horizon-Style DUI Navigation System
    Uses ox_lib for DUI management
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'botz'
description 'Forza-style world-space DUI navigation arrows'
version '1.0.0'

-- Requires ox_lib for DUI helper
shared_script '@ox_lib/init.lua'

-- Client-side only
client_script 'client.lua'

-- DUI files (loaded via nui:// protocol)
files {
    'dui/arrow.html'
}
