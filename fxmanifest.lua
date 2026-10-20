fx_version "cerulean"
game "gta5"
author "https://discord.zykeresources.com"
description "Car lifts other resources stand where they want, with a power unit, arms set by hand and an export surface for integrations"
lua54 "yes"
version "1.0.1"

shared_scripts {
    "@zyke_lib/imports.lua",
    "shared/config.lua",
    "shared/lifts.lua",
    "shared/lift.lua",
    "shared/twopost.lua",
}

client_scripts {
    "client/can_checks.lua",
    "client/server_clock.lua",
    "client/busy.lua",
    "client/keybinds.lua",
    "client/draw.lua",
    "client/scene.lua",
    "client/interactions.lua",
    "client/measure.lua",
    "client/sound_occlusion.lua",
    "client/twopost_set.lua",
    "client/lifts.lua",
    "client/cars.lua",
    "client/twopost_arms.lua",
    "client/admin.lua",
}

server_scripts {
    "@oxmysql/lib/MySQL.lua",
    "server/can_checks.lua",
    "server/hooks.lua",
    "server/rules.lua",
    "server/measure.lua",
    "server/sounds.lua",
    "server/lifts.lua",
    "server/database.lua",
    "server/admin.lua",
}

ui_page "nui/index.html"

files {
    "nui/**/*",
    "stream/zyke_vehiclelifts_twopost.ytyp",
    "locales/*.lua",
}

data_file "DLC_ITYP_REQUEST" "stream/zyke_vehiclelifts_twopost.ytyp"

dependencies {
    "zyke_lib",
    "oxmysql",
}