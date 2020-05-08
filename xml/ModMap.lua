-- Version from @[Team LTW] kingkalle in the official Giants Forums
-- https://forum.giants-software.com/viewtopic.php?f=884&t=103797&start=90#p1083352
-- also other people that have contributed to making this script work in Fs19 @elky and probably others 
-- THANKS! 

ModMap = {}
local ModMap_mt = Class(ModMap, Mission00)

function ModMap:new(baseDirectory, customMt, missionCollaborators)
    local mt = customMt
    if mt == nil then
        mt = ModMap_mt
    end
    local self = ModMap:superClass():new(baseDirectory, mt, missionCollaborators)

    -- Number of additional channels that are used compared to the original setting (2)
    local numAdditionalAngleChannels = 3;

    self.terrainDetailAngleNumChannels = self.terrainDetailAngleNumChannels + numAdditionalAngleChannels;
    self.terrainDetailAngleMaxValue = (2^self.terrainDetailAngleNumChannels) - 1;

    self.terrainDetailHeightTypeNumChannels = self.terrainDetailHeightTypeNumChannels + 1;

    self.sprayLevelFirstChannel = self.sprayLevelFirstChannel + numAdditionalAngleChannels;

    self.plowCounterFirstChannel = self.plowCounterFirstChannel + numAdditionalAngleChannels;
    self.limeCounterFirstChannel = self.limeCounterFirstChannel + numAdditionalAngleChannels;

    return self
end

-- Beta PC