fx_version 'cerulean'
game 'gta5'

author 'Mazus / MZ'
description 'MZ BanGuard - local ban, cloud ban intelligence, risk flags and audit for FiveM'
version '1.2.0'
lua54 'yes'

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/utils.lua',
    'server/webhook.lua',
    'server/identifiers.lua',
    'server/db.lua',
    'server/cloud.lua',
    'server/bans.lua',
    'server/flags.lua',
    'server/api.lua',
    'server/commands.lua',
    'server/main.lua'
}

dependency 'oxmysql'
