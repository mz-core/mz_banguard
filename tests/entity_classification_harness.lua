local checks, failures = 0, {}
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

Config = {
    EntityClassification = {
        enabled = true, mappingVersion = 'test-map', mappingValidated = false,
        populationTypes = {
            [0] = { name = 'unknown_or_script_created', class = 'scripted_unknown' },
            [5] = { name = 'random_ambient', class = 'ambient' },
            [7] = { name = 'mission', class = 'scripted' }
        },
        classes = {
            ambient = { alertOnRate = false, confidence = 'low' },
            scripted = { alertOnRate = true, confidence = 'high' },
            scripted_unknown = { alertOnRate = true, confidence = 'medium' },
            unknown = { alertOnRate = true, confidence = 'medium' }
        }
    }
}
MZBan = {}
dofile('mz_banguard/server/entity_classification.lua')

local ambient = MZBan.EntityClassification.Classify(5)
check(ambient.class == 'ambient' and ambient.alertOnRate == false, 'ambient population alerts on rate')
local mission = MZBan.EntityClassification.Classify(7)
check(mission.class == 'scripted' and mission.alertOnRate == true and mission.confidence == 'high',
    'mission population is not strict')
local scriptCreated = MZBan.EntityClassification.Classify(0)
check(scriptCreated.class == 'scripted_unknown' and scriptCreated.alertOnRate == true,
    'script-created/unknown population was relaxed')
local unknown = MZBan.EntityClassification.Classify(99)
check(unknown.class == 'unknown' and unknown.alertOnRate == true, 'unmapped population failed open')
check(ambient.mappingValidated == false and ambient.mappingVersion == 'test-map', 'mapping status missing')

MZBan.EntityClassification.Observe('ped', ambient)
MZBan.EntityClassification.Observe('ped', ambient)
MZBan.EntityClassification.Observe('vehicle', mission)
local status = MZBan.EntityClassification.Status()
check(status.counters['ped:ambient'] == 2 and status.counters['vehicle:scripted'] == 1,
    'classification counters are incorrect')

if #failures > 0 then
    io.stderr:write(('entity_classification_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end
print(('entity_classification_harness: ok (%d checks)'):format(checks))
