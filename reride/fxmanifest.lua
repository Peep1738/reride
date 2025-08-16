fx_version 'cerulean'
game 'gta5'

author 'sky1738'
version '2.0'

-- クライアントスクリプト（実行順序: config.lua -> main.lua）
client_scripts {
    'client/main.lua'
}

-- サーバースクリプト（実行順序: config.lua -> server.lua）
server_scripts {
    'server/server.lua'
}

dependencies {
    'qb-core'
}