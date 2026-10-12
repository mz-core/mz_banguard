fx_version 'cerulean'
game 'gta5'

author 'Mazus / MZ'
description 'MZ BanGuard - local ban, cloud ban intelligence, risk flags and audit for FiveM'
version '1.6.0'
lua54 'yes'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/security_telemetry.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/utils.lua',
    'server/webhook.lua',
    'server/identifiers.lua',
    'server/db.lua',
    'server/cloud.lua',
    'server/bans.lua',
    'server/detector_catalog.lua',
    'server/lab_mode.lua',
    'server/security_correlation.lua',
    'server/detector_health.lua',
    'server/security_leases.lua',
    'server/security_lifecycle.lua',
    'server/event_contracts.lua',
    'server/incidents.lua',
    'server/enforcement.lua',
    'server/flags.lua',
    'server/weapon_guard.lua',
    'server/entity_classification.lua',
    'server/entity_guard.lua',
    'server/telemetry_guard.lua',
    'server/event_guard.lua',
    'server/aim_guard.lua',
    'server/security_status.lua',
    'server/alerts_api.lua',
    'server/api.lua',
    'server/commands.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql',
    'mz_core',
    'mz_inventory'
}
