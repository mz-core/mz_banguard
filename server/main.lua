MZBan = MZBan or {}

local function checkWhitelist(sourceId, playerName)
    local whitelistConfig = type(Config.Whitelist) == 'table' and Config.Whitelist or {}
    local resourceName = tostring(whitelistConfig.Resource or 'mz_whitelist')
    if GetResourceState(resourceName) ~= 'started' then return true end

    local ok, response = pcall(function()
        return exports[resourceName]:CheckConnection(sourceId, playerName)
    end)
    if not ok or type(response) ~= 'table' or response.ok ~= true then
        if whitelistConfig.FailClosedWhenStarted == false then return true end
        return false, Config.Messages.WhitelistUnavailable, 'contract_unavailable'
    end

    local data = type(response.data) == 'table' and response.data or {}
    if data.allowed == true then return true, nil, data.status end
    return false, tostring(data.message or 'Whitelist negada.'), data.status or 'denied'
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    MZBan.DB.Init()
    print(('[mz_banguard] started v%s'):format(Config.Version or '1.1.0'))
end)

AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source

    deferrals.defer()
    Wait(0)
    deferrals.update(Config.Messages.Checking)

    local dbCallOk, databaseReady, databaseError = pcall(MZBan.DB.IsReady)
    if not dbCallOk or databaseReady ~= true then
        print(('[mz_banguard] playerConnecting denied: database not ready (%s)'):format(
            tostring(dbCallOk and databaseError or databaseReady)
        ))
        deferrals.done(Config.Messages.DatabaseUnavailable)
        return
    end

    local identifiers = MZBan.GetIdentifiers(src, {
        includeIp = Config.Privacy.StoreIpLocal == true
    })

    local requiredOk, missingType = MZBan.HasRequiredIdentifiers(identifiers)
    if not requiredOk then
        deferrals.done(Config.Messages.NoLicense .. ' Missing: ' .. tostring(missingType))
        return
    end

    local tokens = MZBan.GetPlayerTokensSafe(src)

    -- Histórico local, mesmo se não houver ban.
    pcall(function()
        MZBan.DB.SaveSeen(src, playerName, identifiers, tokens)
    end)

    local localBan = MZBan.Bans.CheckLocal(identifiers, tokens)
    if localBan then
        MZBan.DB.Audit('join.denied.local_ban', {
            target_source = src,
            target_name = playerName,
            ban_public_id = localBan.public_id,
            meta = { match_type = localBan.match_type }
        })

        deferrals.done(MZBan.Bans.FormatKickMessage(localBan))
        return
    end

    deferrals.update('Verificando whitelist...')
    local whitelistAllowed, whitelistMessage, whitelistStatus = checkWhitelist(src, playerName)
    if not whitelistAllowed then
        MZBan.DB.Audit('join.denied.whitelist', {
            target_source = src,
            target_name = playerName,
            meta = {
                status = tostring(whitelistStatus or 'denied')
            }
        })
        deferrals.done(whitelistMessage)
        return
    end

    if Config.Cloud.Enabled then
        deferrals.update(Config.Messages.Checking .. ' Cloud...')
        local cloudResponse, cloudErr = MZBan.Cloud.CheckPlayer(src, playerName, identifiers)

        if cloudResponse then
            local activeBan = cloudResponse.active_bans and cloudResponse.active_bans[1]
            local risk = tonumber(cloudResponse.risk_score or 0) or 0
            local shouldBlock = false

            if cloudResponse.action == 'deny' then
                shouldBlock = true
            elseif Config.Cloud.AutoBlock and activeBan and risk >= Config.Cloud.RiskDenyThreshold then
                shouldBlock = true
            end

            if shouldBlock then
                local publicId = activeBan and activeBan.public_id or 'CLOUD'
                local reason = activeBan and activeBan.reason or 'Banimento ativo na rede'

                MZBan.DB.Audit('join.denied.cloud_ban', {
                    target_source = src,
                    target_name = playerName,
                    ban_public_id = publicId,
                    meta = {
                        risk_score = risk,
                        cloud_action = cloudResponse.action
                    }
                })

                MZBan.Webhook.Send('CloudDenied', '⛔ Entrada bloqueada pela cloud', ('Código: `%s`'):format(publicId), {
                    MZBan.Webhook.Field('Player', playerName or 'N/A', true),
                    MZBan.Webhook.Field('Risco', tostring(risk), true),
                    MZBan.Webhook.Field('Motivo', reason, false)
                }, 'danger')

                deferrals.done(string.format(Config.Messages.CloudBan, publicId, reason))
                return
            elseif activeBan then
                MZBan.DB.Audit('join.flagged.cloud_ban', {
                    target_source = src,
                    target_name = playerName,
                    ban_public_id = activeBan.public_id,
                    meta = {
                        risk_score = risk,
                        cloud_action = cloudResponse.action
                    }
                })

                MZBan.Webhook.Send('CloudFlagged', '⚠️ Player com histórico cloud entrou', ('Código cloud: `%s`'):format(activeBan.public_id or 'N/A'), {
                    MZBan.Webhook.Field('Player', playerName or 'N/A', true),
                    MZBan.Webhook.Field('Risco', tostring(risk), true),
                    MZBan.Webhook.Field('Ação', tostring(cloudResponse.action), true),
                    MZBan.Webhook.Field('Motivo', activeBan.reason or 'N/A', false)
                }, 'warning')
            end
        else
            MZBan.Log('Cloud unavailable during playerConnecting:', cloudErr or 'unknown')
        end
    end

    deferrals.done()
end)
