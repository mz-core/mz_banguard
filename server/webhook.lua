MZBan = MZBan or {}
MZBan.Webhook = {}

local colors = {
    info = 5814783,
    success = 3654553,
    warning = 16763904,
    danger = 16724787
}

local function enabled(eventName)
    if not Config.Webhook or not Config.Webhook.Enabled then return false end
    if not Config.Webhook.Url or Config.Webhook.Url == '' then return false end
    if eventName and Config.Webhook.Events and Config.Webhook.Events[eventName] == false then return false end
    return true
end

function MZBan.Webhook.Send(eventName, title, description, fields, level)
    if not enabled(eventName) then return end

    local embed = {
        title = title or 'MZ BanGuard',
        description = description or '',
        color = colors[level or 'info'] or colors.info,
        fields = fields or {},
        footer = { text = 'MZ BanGuard ' .. tostring(Config.Version or '') },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    local payload = {
        username = Config.Webhook.Username or 'MZ BanGuard',
        avatar_url = Config.Webhook.AvatarUrl or nil,
        embeds = { embed }
    }

    PerformHttpRequest(Config.Webhook.Url, function() end, 'POST', MZBan.JsonEncode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

function MZBan.Webhook.Field(name, value, inline)
    return {
        name = tostring(name or 'Campo'),
        value = MZBan.Truncate(value or 'N/A', 1000),
        inline = inline == true
    }
end
