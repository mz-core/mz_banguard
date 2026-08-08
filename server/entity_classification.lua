MZBan = MZBan or {}
MZBan.EntityClassification = MZBan.EntityClassification or {}

local counters = {}

local function config()
    return type(Config.EntityClassification) == 'table' and Config.EntityClassification or {}
end

local function safeToken(value, fallback)
    value = tostring(value or ''):lower():gsub('[^a-z0-9_%-]', ''):sub(1, 48)
    return value ~= '' and value or fallback
end

function MZBan.EntityClassification.Classify(populationType)
    populationType = math.floor(tonumber(populationType) or -1)
    local definitions = type(config().populationTypes) == 'table' and config().populationTypes or {}
    local definition = type(definitions[populationType]) == 'table' and definitions[populationType] or {}
    local class = safeToken(definition.class, 'unknown')
    local policies = type(config().classes) == 'table' and config().classes or {}
    local policy = type(policies[class]) == 'table' and policies[class] or {}
    return {
        populationType = populationType,
        name = safeToken(definition.name, 'unknown'),
        class = class,
        alertOnRate = config().enabled ~= true or policy.alertOnRate == true,
        confidence = safeToken(policy.confidence, 'medium'),
        mappingVersion = tostring(config().mappingVersion or 'unknown'):sub(1, 48),
        mappingValidated = config().mappingValidated == true
    }
end

function MZBan.EntityClassification.Observe(kind, classification)
    classification = type(classification) == 'table' and classification or MZBan.EntityClassification.Classify(-1)
    kind = safeToken(kind, 'unknown')
    local key = kind .. ':' .. classification.class
    counters[key] = (counters[key] or 0) + 1
    return counters[key]
end

function MZBan.EntityClassification.Status()
    local output = {}
    for key, count in pairs(counters) do output[key] = count end
    return {
        enabled = config().enabled == true,
        mappingVersion = tostring(config().mappingVersion or 'unknown'),
        mappingValidated = config().mappingValidated == true,
        counters = output
    }
end
