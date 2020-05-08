--[[
Interface: 1.5.1.0 b6732

Copyright (C) GtX (Andy), 2017

Author: GtX | Andy
Date: 21.09.2019
Version: 1.0.0.0

Contact:
https://forum.giants-software.com
https://github.com/GtX-Andy

History:
V 0.9.0.0 @ 14.04.2017 - FS17 Beta Version (Internal and selected testers only no public release).
V 1.0.0.0 @ 21.09.2019 - Release Version for FS19 with pallet spawner and animal trigger options.
V 1.0.1.0 @ 29.11.2019 - Fix scaling issue with popup UI, add option to use manual start/stop,
                         add Particle System option for exhausts and other non fillType particles,
                         add option to disable of change text shown in UI when using pallet spawners.
V 1.0.2.0 @ 11.01.2020 - Fix typo in wood trigger code, fix manual start/stop draw information bug.
V 1.0.3.0 @ 03.02.2020 - Add option to save current update time and ignore missing fill type warnings when needed.
V 1.0.3.1 @ 02.04.2020 - Add active and engine sounds. Fix fill plane scaling bug.
V 1.0.3.2 @ 29.04.2020 - Improvements and fixes to pallet spawner.

About:
A light weight no frills fillType converter script that can be added directly to a placeable mod.
Will perform all the required needs for farm mixers and greenhouses without adding unneeded features.
I enjoy FS as a farm game so this script is designed for making farm style objects only.

Important:
No changes are to be made to this script without permission from GtX | Andy!
An diesem Skript dürfen ohne Genehmigung von GtX | Andy keine Änderungen vorgenommen werden!
]]


FillTypeConverter = {}

-- Do not show a warning if a fillType from my friends at 'Realismus Modding' if found but not available.
-- This lets me add their fillTypes but only use them if Seasons is active ;-).
FillTypeConverter.IGNORE_FILLTYPE_WARNINGS = {
    SNOW = true,
    SALT = true,
    SEMIDRY_GRASS_WINDROW = true
}

-- Easy access for display colours.
FillTypeConverter.DISPLAY_COLOURS = {
    RED = {1, 0, 0, 1},
    GREEN = {0, 1, 0, 1},
    WHITE = {1, 1, 1, 1},
    YELLOW = {1, 1, 0, 1},
    ORANGE = {1, 0.5, 0, 1},
    GREY = {0.3, 0.3, 0.3, 1},
    BLACK = {0.05, 0.05, 0.05, 1},
    LIGHT_RED = {1, 0.5, 0.25, 1},
    LIGHT_GREEN = {0.05, 0.15, 0.05, 1}
}

-- On some maps these do not use l10n entries so make them look nice in UI.
FillTypeConverter.TITLE_CORRECTIONS = {
    ["SEMIDRY_GRASS_WINDROW"] = "Semidry Grass",
    ["Alfalfa_windrow"] = "Alfalfa",
    ["Alfalfa_hay_windrow"] = "Dry Alfalfa"
}

local FillTypeConverter_mt = Class(FillTypeConverter, Placeable)
InitObjectClass(FillTypeConverter, "FillTypeConverter")


function FillTypeConverter:new(isServer, isClient, customMt)
    local self = Placeable:new(isServer, isClient, customMt or FillTypeConverter_mt)

    registerObjectClassName(self, "FillTypeConverter")

    -- Identifier for mods such as 'CoursePlay' etc. --
    self.isFillTypeConverterMod = true

    self.inputs = {}
    self.numInputs = 0
    self.fillTypeToInput = {}

    self.outputs = {}
    self.numOutputs = 0
    self.fillTypeToOutput = {}

    self.extraPalletDelta = false

    self.updateMinute = 0
    self.updateInterval = 0
    self.rainWaterCollected = 0

    self.fillPlaneMaterials = {}

    self.sortedFillTypes = {}
    self.providedFillTypes = {}

    self.loadTriggers = {}
    self.unloadTriggers = {}

    self.woodTriggers = {}
    self.animalTriggers = {}
    self.triggerIdToTrigger = {}

    self.beaconLights = {}
    self.beaconLightsActive = false

    self.animationNodes = {}
    self.sequencedAnimationNodes = {}

    self.animationClips = {}
    self.sequencedAnimationClips = {}

    self.changedParts = {}
    self.sequencedChangedParts = {}

    self.effects = {}
    self.sequencedEffects = {}

    self.shaders = {}
    self.sequencedShaders = {}

    self.linkedInputEffects = {}
    self.linkedInputAnimationNodes = {}

    self.partsCheckTimer = 0
    self.partsSequencing = {
        id = 0,
        time =  0.0,
        sequence = {},
        numSequence = 0,
        state = false,
        active = false
    }

    self.activeSamples = {}
    self.engineSamples = nil
    self.sequencedActiveSamples = {}

    self.partsState = false
    self.isEnabled = true

    self.activateText = "N/A"
    self.customDischargeNotAllowedText = nil
    self.statusUiButtonText = "(Status UI)"

    self.manualStartInputAction = nil
    self.loadedFromSaveGame = false

    return self
end

function FillTypeConverter:load(xmlFilename, x,y,z, rx,ry,rz, initRandom)
    if not FillTypeConverter:superClass().load(self, xmlFilename, x,y,z, rx,ry,rz, initRandom) then
        return false
    end

    local key = "placeable.fillTypeConverter"
    local xmlFile = loadXMLFile("TempXML", xmlFilename)
    local animalTriggerAvailable = false

    local rawName = Utils.getNoNil(getXMLString(xmlFile, key .. "#stationName"), "Converter")
    self.stationName = g_i18n:convertText(rawName, self.customEnvironment)

    -- If true then 'perHour' will be adjusted when using seasons based on the length to stop certain mods becoming a cheat (e.g Fermenting Silo).
    self.adjustForSeasonsLength = Utils.getNoNil(getXMLBool(xmlFile, key .. "#adjustForSeasonsLength"), false)

    -- Intervals as low as 1 Minute are allowed but not recommended as this is a waste of network data and may perform bad for some users.
    -- 10 Minutes is the recommended minimum and is the minimum that will be applied if using animals. Base Game animals are set to 20.
    -- This Script is for converting fillTypes over time with optional animations and effects not as storage so 10 - 20 minutes is fine.
    self.updateInterval = math.max(Utils.getNoNil(getXMLInt(xmlFile, key .. "#updateInterval"), 20), 1)

    -- If false the current update time will be reset to '0' each game load and will not be saved with the game.
    self.saveUpdateTime = Utils.getNoNil(getXMLBool(xmlFile, key .. "#saveUpdateTime"), true)

    -- Combines the 'Input 1' and 'Output 1' fill level values for use as a true converter (e.g Fermenting Silo).
    -- Max 'Capacity' is calculated using the capacity of the input only. A maximum of 1 input can be used with this feature.
    -- Converting of 'Input 1 > Output 1' will continue even if other outputs are full.
    local combinedCapacity = Utils.getNoNil(getXMLBool(xmlFile, key .. "#combinedCapacity"), false)

    -- Is the UI enabled on first placement.
    self.statusUiEnabled = Utils.getNoNil(getXMLBool(xmlFile, key .. "#statusUiEnabled"), true)

    -- Show warnings when converter stops due to no output space, input or no pallet space.
    self.showFillLevelWarnings = Utils.getNoNil(getXMLBool(xmlFile, key .. ".fillLevelWarnings#active"), true)

    -- FUTURE USE: Allows certain mods to be hidden in global UI mods if required.
    self.showInGlobalMods = Utils.getNoNil(getXMLBool(xmlFile, key .. "#showInGlobalMods"), true)

    local inputEmptyWarning = getXMLString(xmlFile, key .. ".fillLevelWarnings#inputEmpty")
    if inputEmptyWarning ~= nil and g_i18n:hasText(inputEmptyWarning, self.customEnvironment) then
        self.inputEmptyWarning = self.stationName .. ": " .. g_i18n:getText(inputEmptyWarning, self.customEnvironment)
    else
        self.inputEmptyWarning = self.stationName .. ": %s is empty!"
    end

    local outputFullWarning = getXMLString(xmlFile, key .. ".fillLevelWarnings#outputFull")
    if outputFullWarning ~= nil and g_i18n:hasText(outputFullWarning, self.customEnvironment) then
        self.outputFullWarning = self.stationName .. ": " .. g_i18n:getText(outputFullWarning, self.customEnvironment)
    else
        self.outputFullWarning = self.stationName .. ": %s capacity reached!"
    end

    -- Allow for hotspot as then mapHotspots in the placeable does not call with customEnvironment so can not use l10n entries.
    if hasXMLProperty(xmlFile, key .. ".hotspot") then
        local hotspot = self:loadHotspotFromXML(xmlFile, key .. ".hotspot")
        if hotspot ~= nil then
            -- Correct the 'fullName' using 'customEnvironment' before adding.
            local fullViewName = g_i18n:convertText(Utils.getNoNil(getXMLString(xmlFile, key .. ".hotspot#fullName"), ""), self.customEnvironment)
            if fullViewName ~= "" then
                hotspot.fullViewName = fullViewName
            end

            hotspot:setOwnerFarmId(self:getOwnerFarmId(), false)

            g_currentMission:addMapHotspot(hotspot)
            table.insert(self.mapHotspots, hotspot)
        end
    end

    local i = 0
    while true do
        local inputKey = string.format("%s.inputs.input(%d)", key, i)
        if not hasXMLProperty(xmlFile, inputKey) or (self.numInputs >= 8) then
            break
        end

        local isValid = false
        local input = {fillLevel = 0, fillTypes = {}, sortedFillTypeTitles = {}, displayName = " "}

        local fillTypeNames = getXMLString(xmlFile, inputKey .. "#fillTypes")
        if fillTypeNames ~= nil then
            local names = StringUtil.splitString(" ", fillTypeNames)

            -- If 'true' fillTypes not available in the current map will be ignored. Should be used in conjunction with base game fillTypes. I.E (grass_windrow alfalfa)
            local ignoreMissingFillTypes = Utils.getNoNil(getXMLBool(xmlFile, inputKey .. "#ignoreMissingFillTypes"), false)

            for _, name in pairs(names) do
                local fillType = g_fillTypeManager:getFillTypeByName(name)
                if fillType ~= nil then
                    local fillTypeIndex = fillType.index

                    if self.fillTypeToInput[fillTypeIndex] == nil then
                        isValid = true

                        if input.lastFillType == nil then
                            input.lastFillType = fillTypeIndex
                        end

                        input.isFillTypes = true
                        input.fillTypes[fillTypeIndex] = true
                        self.fillTypeToInput[fillTypeIndex] = input

                        local title = fillType.title
                        if FillTypeConverter.TITLE_CORRECTIONS[title] ~= nil then
                            title = FillTypeConverter.TITLE_CORRECTIONS[title]
                        end

                        table.insert(input.sortedFillTypeTitles, title)
                    else
                        g_logManager:xmlWarning(xmlFilename, "Duplicate input fillType %s given at '%s'.", name, inputKey)
                    end
                else
                    if (ignoreMissingFillTypes == false) or (#names < 2) then
                        local nameUpper = string.upper(name)
                        if FillTypeConverter.IGNORE_FILLTYPE_WARNINGS[nameUpper] == nil then
                            g_logManager:xmlWarning(xmlFilename, "Invalid fillType %s given at '%s'!", name, inputKey)
                        end
                    end
                end
            end
        else
            local animalTypeStr = getXMLString(xmlFile, inputKey .. "#animalTypes")
            if animalTypeStr ~= nil then
                local animalTypeNames = StringUtil.splitString(" ", animalTypeStr)

                for _, name in pairs (animalTypeNames) do
                    local animalType = g_animalManager:getAnimalsByType(name)
                    if animalType ~= nil then
                        local lastTitle = ""
                        for _, subType in pairs (animalType.subTypes) do
                            local fillTypeIndex = subType.fillTypeDesc.index

                            if input.lastFillType == nil then
                                input.lastFillType = fillTypeIndex
                            end

                            input.isFillTypes = false
                            input.fillTypes[fillTypeIndex] = true
                            self.fillTypeToInput[fillTypeIndex] = input

                            local title = subType.fillTypeDesc.title
                            if title ~= lastTitle then
                                isValid = true
                                lastTitle = title

                                table.insert(input.sortedFillTypeTitles, title)
                            end

                            animalTriggerAvailable = true
                        end
                    else
                        g_logManager:xmlWarning(xmlFilename, "Invalid animalType %s given at '%s'!", inputKey, name)
                    end
                end
            end
        end

        if isValid then
            self.numInputs = self.numInputs + 1

            input.inputId = self.numInputs
            input.type = "INPUT"

            if input.isFillTypes then
                input.perHour = math.max(Utils.getNoNil(getXMLInt(xmlFile, inputKey .. "#perHour"), 100), 1)
            else
                -- I allow float values (e.g 0.25) for animals so you can use less per interval :-)
                -- Seasons length adjustment is disabled for animals as the values will be too small and minimum update interval is 10 min.
                input.perHour = Utils.getNoNil(getXMLFloat(xmlFile, inputKey .. "#perHour"), 1)
                self.adjustForSeasonsLength = false
                self.updateInterval = math.max(self.updateInterval, 10)
            end
            input.perInterval = (input.perHour / 60) * self.updateInterval

            input.capacity = Utils.getNoNil(getXMLInt(xmlFile, inputKey .. "#capacity"), 100000)
            input.combinedCapacity = false

            if Utils.getNoNil(getXMLBool(xmlFile, inputKey .. "#useDisplayName"), true) then
                local displayName = getXMLString(xmlFile, inputKey .. "#displayName")
                if displayName ~= nil then
                    local text = g_i18n:getText(displayName, self.customEnvironment)
                    if Utils.getNoNil(getXMLBool(xmlFile, inputKey .. "#displayNameAddIndex"), false) then
                        input.displayName = string.format("%s %d", text, input.inputId)
                    else
                        input.displayName = text
                    end
                else
                    input.displayName = string.format("Input %d", input.inputId)
                end
            end

            if self.isClient then
                input.visNodes, input.numVisNodes = self:loadVisNodes(xmlFile, inputKey)
                input.displays, input.numDisplays = self:loadDisplays(xmlFile, inputKey, input)
                input.fillPlanes, input.numFillPlanes = self:loadFillPlanes(xmlFile, inputKey, input.capacity)
            end

            input.sortedAndConcatedTitles = table.concat(input.sortedFillTypeTitles, ", ")
            self.inputs[input.inputId] = input

            if self.rainInputPerHour == nil then
                local rainInputPerHour = Utils.getNoNil(getXMLInt(xmlFile, inputKey .. "#rainInputPerHour"), 0)
                if rainInputPerHour > 0 and input.fillTypes[FillType.WATER] then
                    self.rainInputPerHour = {value = rainInputPerHour, source = input}
                end
            end

            if combinedCapacity then
                break
            end
        else
            input = nil
            g_logManager:xmlWarning(xmlFilename, "Failed to load input %d, missing required Fill Types on this map, this may cause an undesired effect!", i)
        end

        i = i + 1
    end

    i = 0
    while true do
        local outputKey = string.format("%s.outputs.output(%d)", key, i)
        if not hasXMLProperty(xmlFile, outputKey) or (self.numOutputs >= 8) then
            break
        end

        local output = {fillLevel = 0, displayName = " "}
        local fillTypeName = getXMLString(xmlFile, outputKey .. "#fillType")
        if fillTypeName ~= nil then
            local fillType = g_fillTypeManager:getFillTypeByName(fillTypeName)

            if fillType ~= nil then
                local fillTypeIndex = fillType.index
                if self.fillTypeToOutput[fillTypeIndex] == nil then
                    self.numOutputs = self.numOutputs + 1

                    output.outputId = self.numOutputs
                    output.type = "OUTPUT"

                    if Utils.getNoNil(getXMLBool(xmlFile, outputKey .. "#useDisplayName"), true) then
                        local displayName = getXMLString(xmlFile, outputKey .. "#displayName")
                        if displayName ~= nil then
                            local text = g_i18n:getText(displayName, self.customEnvironment)
                            if Utils.getNoNil(getXMLBool(xmlFile, outputKey .. "#displayNameAddIndex"), false) then
                                output.displayName = string.format("%s %d", text, output.outputId)
                            else
                                output.displayName = text
                            end
                        else
                            output.displayName = string.format("Output %d", output.outputId)
                        end
                    end

                    output.perHour = Utils.getNoNil(getXMLInt(xmlFile, outputKey .. "#perHour"), 100)
                    output.perInterval = (output.perHour / 60) * self.updateInterval

                    local outputId = output.outputId
                    if outputId == 1 and combinedCapacity and self.inputs[outputId] ~= nil then
                        output.combinedCapacity = true
                        self.inputs[outputId].combinedCapacity = true
                        output.capacity = tonumber(self.inputs[outputId].capacity)

                        -- "The maximum combined capacity has been reached!" --
                        local dischargeNotAllowedText = getXMLString(xmlFile, outputKey .. "#dischargeNotAllowedText")
                        if dischargeNotAllowedText == nil then
                            dischargeNotAllowedText = "fillUnit_unload_nospace"
                        end

                        self.customDischargeNotAllowedText = g_i18n:getText(dischargeNotAllowedText, self.customEnvironment)
                    else
                        output.combinedCapacity = false
                        output.capacity = Utils.getNoNil(getXMLInt(xmlFile, outputKey .. "#capacity"), 100000)
                    end

                    output.isFillTypes = true
                    output.fillType = fillTypeIndex
                    output.lastFillType = fillTypeIndex

                    output.lastPalletFullMessage = 0
                    output.palletSpawners, output.numPalletSpawners = self:loadPalletSpawner(xmlFile, outputKey, output)
                    output.hasPalletSpawner = (output.numPalletSpawners > 0)

                    if output.numPalletSpawners <= 0 then
                        output.warningFillTypeTitle = ""
                        output.fillTypeTitle = fillType.title
                    else
                        output.warningFillTypeTitle = fillType.title

                        -- Allow spawner info type name to be changed (Default: Pallets) or disabled if not required.
                        if Utils.getNoNil(getXMLBool(xmlFile, outputKey .. ".palletSpawners#showSpawnerCount"), true) then
                            local spawnerCountName = Utils.getNoNil(getXMLString(xmlFile, outputKey .. ".palletSpawners#spawnerCountName"), "category_pallets")
                            output.fillTypeTitle = string.format("%s  (%s x %d)", fillType.title, g_i18n:getText(spawnerCountName), output.numPalletSpawners)
                        else
                            output.fillTypeTitle = fillType.title
                        end
                    end

                    if self.isClient then
                        output.visNodes, output.numVisNodes = self:loadVisNodes(xmlFile, outputKey)
                        output.displays, output.numDisplays = self:loadDisplays(xmlFile, outputKey, output)
                        output.fillPlanes, output.numFillPlanes = self:loadFillPlanes(xmlFile, outputKey, output.capacity)
                    end

                    self.fillTypeToOutput[fillTypeIndex] = output
                    self.providedFillTypes[fillTypeIndex] = (not output.hasPalletSpawner)

                    self.outputs[output.outputId] = output

                    if self.rainInputPerHour == nil and output.fillType == FillType.WATER then
                        local rainInputPerHour = Utils.getNoNil(getXMLInt(xmlFile, outputKey .. "#rainInputPerHour"), 0)
                        if rainInputPerHour > 0 then
                            self.rainInputPerHour = {value = rainInputPerHour, source = output}
                        end
                    end
                else
                    g_logManager:xmlWarning(xmlFilename, "Duplicate output fillType '%s' given at '%s'.", fillType.name, outputKey)
                end
            end
        end

        i = i + 1
    end

    if self.numInputs > 0 then
        i = 0
        while true do
            local unloadTriggerKey = string.format("%s.unloadTriggers.unloadTrigger(%d)", key, i)
            if not hasXMLProperty(xmlFile, unloadTriggerKey) then
                break
            end

            local unloadTrigger = UnloadTrigger:new(self.isServer, self.isClient)
            if unloadTrigger:load(self.nodeId, xmlFile, unloadTriggerKey, self) then
                -- Changed to allow 'fillTypes' to be set to use for limiting if 'avoidFillTypes' would be too long.
                unloadTrigger.getIsFillTypeSupported = Utils.overwrittenFunction(unloadTrigger.getIsFillTypeSupported, function(self, superFunc, fillType)
                    if self.fillTypes ~= nil then
                        if not self.fillTypes[fillType] then
                            return false
                        end
                    end

                    if self.avoidFillTypes ~= nil then
                        if self.avoidFillTypes[fillType] then
                            return false
                        end
                    end

                    if self.target ~= nil then
                        if not self.target:getIsFillTypeAllowed(fillType) then
                            return false
                        end
                    end

                    return true
                end)

                unloadTrigger.getCustomDischargeNotAllowedWarning = Utils.overwrittenFunction(unloadTrigger.getCustomDischargeNotAllowedWarning, function(self, superFunc)
                    if self.target ~= nil and self.target.inputs ~= nil and self.target.customDischargeNotAllowedText ~= nil then
                        local input = self.target.inputs[1]
                        if self.target:getAdjustedInputFillLevel(input) >= input.capacity then
                            return self.target.customDischargeNotAllowedText
                        end
                    end

                    return superFunc(self)
                end)

                -- Fix for 'baleTriggerCallback' mistake where checks are done after bale is added to table and bale is added twice.
                unloadTrigger.baleTriggerCallback = Utils.overwrittenFunction(unloadTrigger.baleTriggerCallback, function(self, superFunc, triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
                    if self.isEnabled then
                        local object = g_currentMission:getNodeObject(otherId)
                        if object ~= nil and object:isa(Bale) then
                            if onEnter  then
                                local fillType = object:getFillType()
                                if self:getIsFillTypeSupported(fillType) and self:getIsToolTypeAllowed(ToolType.BALE) then
                                    self:raiseActive()
                                    table.insert(self.balesInTrigger, object)
                                end
                            elseif onLeave then
                                for index, bale in pairs(self.balesInTrigger) do
                                    if bale == object then
                                        table.remove(self.balesInTrigger, index)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end)

                -- Easy access for CoursePlay to see the trigger 'acceptedFillTypes' if they decide to add support. --
                unloadTrigger.acceptedFillTypes = unloadTrigger.fillTypes
                if unloadTrigger.acceptedFillTypes == nil then
                    unloadTrigger.acceptedFillTypes = {}

                    for fillTypeIndex, _ in pairs (self.fillTypeToInput) do
                        if unloadTrigger.avoidFillTypes ~= nil then
                            if not unloadTrigger.avoidFillTypes[fillTypeIndex] then
                                unloadTrigger.acceptedFillTypes[fillTypeIndex] = true
                            end
                        else
                            unloadTrigger.acceptedFillTypes[fillTypeIndex] = true
                        end
                    end
                end

                unloadTrigger:setTarget(self)
                unloadTrigger:register(true)

                table.insert(self.unloadTriggers, unloadTrigger)
            else
                unloadTrigger:delete()
            end

            i = i + 1
        end

        i = 0
        while true do
            local woodTriggerKey = string.format("%s.woodTriggers.woodTrigger(%d)", key, i)
            if not hasXMLProperty(xmlFile, woodTriggerKey) then
                break
            end

            local triggerId = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, woodTriggerKey .. "#triggerNode"))
            if triggerId ~= nil then
                local colMask = getCollisionMask(triggerId)
                if bitAND(SplitTypeManager.COLLISIONMASK_TRIGGER, colMask) == 0 then
                    g_logManager:xmlWarning(xmlFilename, "Invalid collision mask for wood trigger '%s'. Bit 24 needs to be set!", woodTriggerKey)
                end

                local maxLength = Utils.getNoNil(getXMLFloat(xmlFile, woodTriggerKey .. "#maxLength"), 12) + 0.3
                local limitAttachments = Utils.getNoNil(getXMLBool(xmlFile, woodTriggerKey .. "#limitAttachments"), false)
                addTrigger(triggerId, "woodTriggerCallback", self)

                local woodTrigger = {triggerId = triggerId, maxLength = maxLength, limitAttachments = limitAttachments}

                self.triggerIdToTrigger[triggerId] = woodTrigger
                table.insert(self.woodTriggers, woodTrigger)
            end

            i = i + 1
        end

        if animalTriggerAvailable and hasXMLProperty(xmlFile, key .. ".animalUnloadingTriggers") then
            i = 0
            while true do
                local animalTriggerKey = string.format("%s.animalUnloadingTriggers.animalUnloadingTrigger(%d)", key, i)
                if not hasXMLProperty(xmlFile, animalTriggerKey) then
                    break
                end

                local animalTrigger = FillTypeConverterAnimalTrigger:new(self.isServer, self.isClient, self.customEnvironment, self.configFileName)
                if animalTrigger:load(self.nodeId, xmlFile, animalTriggerKey, self) then
                    animalTrigger:register(true)
                    table.insert(self.animalTriggers, animalTrigger)
                else
                    animalTrigger:delete()
                end

                i = i + 1
            end
        end
    end

    if self.numOutputs > 0 then
        i = 0
        while true do
            local loadTriggerKey = string.format("%s.loadTriggers.loadTrigger(%d)", key, i)
            if not hasXMLProperty(xmlFile, loadTriggerKey) then
                break
            end

            local loadTrigger = LoadTrigger:new(self.isServer, self.isClient)
            if loadTrigger:load(self.nodeId, xmlFile, loadTriggerKey) then

                local playerInteractionTrigger = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, loadTriggerKey .. ".playerInteraction#triggerNode"))
                if playerInteractionTrigger ~= nil then

                    loadTrigger.playerCanInteract = false
                    loadTrigger.playerInteractionTrigger = playerInteractionTrigger

                    loadTrigger.playerInteractionTriggerCallback = function(trigger, triggerId, otherId, onEnter, onLeave, onStay)
                        if g_currentMission.controlPlayer then
                            if (g_currentMission.player ~= nil) and (otherId == g_currentMission.player.rootNode) then
                                if onEnter or onLeave then
                                    if onEnter then
                                        trigger.playerCanInteract = g_currentMission.accessHandler:canFarmAccess(g_currentMission:getFarmId(), trigger.source)
                                    else
                                        trigger.playerCanInteract = false
                                    end

                                    trigger:raiseActive()
                                end
                            end
                        end
                    end

                    loadTrigger.delete = Utils.prependedFunction(loadTrigger.delete, function(trigger)
                        if trigger.playerInteractionTrigger ~= nil then
                            trigger.playerCanInteract = false
                            removeTrigger(trigger.playerInteractionTrigger)
                            trigger.playerInteractionTrigger = nil
                        end
                    end)

                    loadTrigger.getIsActivatable = Utils.overwrittenFunction(loadTrigger.getIsActivatable, function(trigger, superFunc)
                        if next(trigger.fillableObjects) == nil then
                            return false
                        else
                            if trigger.isLoading then
                                if trigger.currentFillableObject ~= nil then
                                    if trigger.playerInteractionTrigger == nil then
                                        if trigger.currentFillableObject:getRootVehicle() == g_currentMission.controlledVehicle then
                                            return true
                                        end
                                    else
                                        return trigger.playerCanInteract == true
                                    end
                                end
                            else
                                if trigger.playerInteractionTrigger ~= nil then
                                    if trigger.playerCanInteract ~= true then
                                        return false
                                    end
                                end

                                trigger.validFillableObject = nil
                                trigger.validFillableFillUnitIndex = nil

                                -- last object that was filled has lower prio than the other objects in the trigger
                                -- so we can guarantee that all objects will be filled
                                local hasLowPrioObject = false
                                local numOfObjects = 0
                                for _, fillableObject in pairs(trigger.fillableObjects) do
                                    if fillableObject.lastWasFilled then
                                        hasLowPrioObject = true
                                    end
                                    numOfObjects = numOfObjects + 1
                                end
                                hasLowPrioObject = hasLowPrioObject and (numOfObjects > 1)

                                for _, fillableObject in pairs(trigger.fillableObjects) do
                                    if not fillableObject.lastWasFilled or not hasLowPrioObject then

                                        local isActivatable = false
                                        if trigger.playerInteractionTrigger ~= nil then
                                            isActivatable = trigger.playerCanInteract == true
                                        else
                                            isActivatable = validFillableObject:getRootVehicle() == g_currentMission.controlledVehicle
                                        end

                                        if isActivatable then
                                            if fillableObject.object:getFillUnitSupportsToolType(fillableObject.fillUnitIndex, ToolType.TRIGGER) then

                                                if not trigger.source:getIsFillAllowedToFarm(trigger:farmIdForFillableObject(fillableObject.object)) then
                                                    return false
                                                end

                                                trigger.validFillableObject = fillableObject.object
                                                trigger.validFillableFillUnitIndex = fillableObject.fillUnitIndex

                                                return true
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        return false
                    end)

                    loadTrigger.onFillTypeSelection = Utils.overwrittenFunction(loadTrigger.onFillTypeSelection, function(trigger, superFunc, fillType)
                        if fillType ~= nil and fillType ~= FillType.UNKNOWN then
                            local validFillableObject = trigger.validFillableObject

                            if validFillableObject ~= nil then
                                local canConfirmSelection = false
                                if trigger.playerInteractionTrigger ~= nil then
                                    canConfirmSelection = trigger.playerCanInteract == true
                                else
                                    canConfirmSelection = validFillableObject:getRootVehicle() == g_currentMission.controlledVehicle
                                end

                                if canConfirmSelection then
                                    local fillUnitIndex = trigger.validFillableFillUnitIndex
                                    trigger:setIsLoading(true, validFillableObject, fillUnitIndex, fillType)
                                end
                            end
                        end
                    end)

                    loadTrigger.shouldRemoveActivatable = Utils.overwrittenFunction(loadTrigger.shouldRemoveActivatable, function(trigger, superFunc)
                        return trigger.playerInteractionTrigger == nil
                    end)

                    loadTrigger.update = Utils.appendedFunction(loadTrigger.update, function(trigger, dt)
                        if trigger.playerInteractionTrigger ~= nil and trigger.playerCanInteract == true then
                            if trigger.source ~= nil then
                                if g_currentMission.controlPlayer and g_currentMission.accessHandler:canFarmAccess(g_currentMission:getFarmId(), trigger.source) then
                                    trigger:raiseActive()
                                else
                                    trigger.playerCanInteract = false
                                end
                            else
                                trigger.playerCanInteract = false
                            end
                        end
                    end)

                    addTrigger(loadTrigger.playerInteractionTrigger, "playerInteractionTriggerCallback", loadTrigger)
                end

                loadTrigger.onActivateObject = Utils.overwrittenFunction(loadTrigger.onActivateObject, function(trigger, superFunc)
                    if not trigger.isLoading then
                        local fillLevels, capacity = trigger.source:getAllFillLevels(g_currentMission:getFarmId())
                        local fillableObject = trigger.validFillableObject
                        local fillUnitIndex = trigger.validFillableFillUnitIndex
                        local firstFillType = nil
                        local validFillLevels = {}

                        for fillTypeIndex, fillLevel in pairs(fillLevels) do
                            if trigger.fillTypes == nil or trigger.fillTypes[fillTypeIndex] then
                                if fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex) then
                                    validFillLevels[fillTypeIndex] = fillLevel
                                    if firstFillType == nil then
                                        firstFillType = fillTypeIndex
                                    end
                                end
                            end
                        end

                        if not trigger.autoStart then
                            g_gui:showSiloDialog({title = tostring(trigger.source.stationName), fillLevels = validFillLevels, capacity = capacity, callback = trigger.onFillTypeSelection, target = trigger, hasInfiniteCapacity = false})
                        else
                            trigger:onFillTypeSelection(firstFillType)
                        end
                    else
                        trigger:setIsLoading(false)
                    end

                    g_currentMission:addActivatableObject(trigger)
                end)

                loadTrigger.hasInfiniteCapacity = false
                loadTrigger:setSource(self)
                loadTrigger:register(true)

                table.insert(self.loadTriggers, loadTrigger)
            else
                loadTrigger:delete()
            end

            i = i + 1
        end
    end

    if self.numInputs > 0 or self.numOutputs > 0 then
        local startTime = getXMLFloat(xmlFile, key .. ".openingHours#startTime")
        local endTime = getXMLFloat(xmlFile, key .. ".openingHours#endTime")
        if startTime ~= nil and endTime ~= nil then
            local closedText = getXMLString(xmlFile, key .. ".openingHours#closedText")
            if closedText ~= nil and g_i18n:hasText(closedText, self.customEnvironment) then
                closedText = g_i18n:getText(closedText, self.customEnvironment)
            else
                if Utils.getNoNil(getXMLBool(xmlFile, key .. ".openingHours#useDefaultClosedText"), true) then
                    closedText = string.format("%s: %02d:00 - %02d:00 h", g_i18n:getText("ui_operatingHours"), startTime, endTime)
                end
            end

            self.openingHours = {startTime = startTime, endTime = endTime, closedText = closedText}
        end

        self.interactionTrigger = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. ".interactionTrigger#node"))
        if self.interactionTrigger ~= nil then
            local colMask = getCollisionMask(self.interactionTrigger)
            if bitAND(Player.COLLISIONMASK_TRIGGER, colMask) == 0 then
                g_logManager:xmlWarning(xmlFilename, "Invalid collision mask for interaction trigger '%s.interactionTrigger#node'. Bit 20 needs to be set!", key)
            end

            addTrigger(self.interactionTrigger, "interactionTriggerCallback", self)

            if g_dedicatedServerInfo == nil then
                self.fillTypeConverterUI = FillTypeConverterStatusUI:new(self, true)

                if self.fillTypeConverterUI ~= nil then
                    local statusUiButtonText = getXMLString(xmlFile, key .. ".interactionTrigger#statusUiButtonText")
                    if statusUiButtonText ~= nil then
                        self.statusUiButtonText = g_i18n:getText(statusUiButtonText, self.customEnvironment)
                    end
                end

                local startStopAction = getXMLString(xmlFile, key .. ".interactionTrigger#startStopAction")
                if startStopAction ~= nil then
                    if self.openingHours == nil then
                        if InputAction[startStopAction] then
                            self.manualStartInputAction = startStopAction
                        else
                            g_logManager:xmlWarning(self.configFileName, "Manual Start / Stop action '%s' not a defined InputAction!", startStopAction)
                        end
                    else
                        g_logManager:xmlWarning(self.configFileName, "'%s.interactionTrigger#startStopAction' is not available when using '<openingHours>'!", key)
                    end
                end
            end
        end

        local sequence
        local sequenceText = getXMLString(xmlFile, key .. ".parts#sequence")
        if sequenceText ~= nil then
            local sequenceValues = StringUtil.splitString(" ", sequenceText)
            local numSequence = #sequenceValues

            if numSequence > 0 then
                for i = 1, numSequence do
                    self.partsSequencing.sequence[i] = tonumber(sequenceValues[i]) * 1000
                end

                sequence = self.partsSequencing.sequence
                self.partsSequencing.numSequence = numSequence
            else
                sequence = nil
            end
        end

        local j = 0
        while true do
            local materialKey = string.format("%s.fillPlaneMaterials.fillPlaneMaterial(%d)", key, j)
            if not hasXMLProperty(xmlFile, materialKey) then
                break
            end

            local fillTypeName = getXMLString(xmlFile, materialKey .. "#fillType")
            if fillTypeName ~= nil then
                local fillType = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
                if fillType ~= nil then
                    local refMaterialNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, materialKey .. "#refNode"))
                    if refMaterialNode ~= nil and getHasClassId(refMaterialNode, ClassIds.SHAPE) then
                        if self.fillPlaneMaterials[fillType] == nil then
                            self.fillPlaneMaterials[fillType] = getMaterial(refMaterialNode, 0)
                        else
                            g_logManager:xmlWarning(self.configFileName, "Duplicate material for %s at '%s'!", fillTypeName, materialKey)
                        end
                    else
                        g_logManager:xmlError(self.configFileName, "No reference material or node is not a shape for '%s'!", materialKey)
                    end
                else
                    g_logManager:xmlWarning(self.configFileName, "Invalid fillType '%s' for '%s'!", fillTypeName, materialKey)
                end
            end

            j = j + 1
        end

        if self.isClient then
            local partsKey = key .. ".parts"
            self:loadAnimationNodes(xmlFile, partsKey, sequence)
            self:loadAnimationClips(xmlFile, partsKey, sequence)
            self:loadChangedParts(xmlFile, partsKey, sequence)

            self:loadEffects(xmlFile, partsKey .. ".effects.effect", sequence, false)
            self:loadEffects(xmlFile, partsKey .. ".particleSystems.particleSystem", sequence, true)

            self:loadShaders(xmlFile, partsKey, sequence)
            self:loadSounds(xmlFile, partsKey, sequence)
            self:loadBeaconLights(xmlFile, partsKey)
        end

        if hasXMLProperty(xmlFile, key .. ".automaticAnimatedObjects") then
            self.automaticAnimatedObjects = {}

            local i = 0
            while true do
                local animationKey = string.format("%s.automaticAnimatedObjects.animatedObject(%d)", key, i)
                if not hasXMLProperty(xmlFile, animationKey) then
                    break
                end

                local animatedObject = AutomaticAnimatedObject:new(self.isServer, self.isClient)
                animatedObject:setOwnerFarmId(self:getOwnerFarmId(), false)

                if not animatedObject:load(self.nodeId, xmlFile, animationKey, self.configFileName) then
                    animatedObject:delete()
                    g_logManager:xmlError(self.configFileName, "Failed to load automatic animated object at '%s'!", animationKey)
                else
                    animatedObject:register(true)
                    table.insert(self.automaticAnimatedObjects, animatedObject)
                end

                i = i + 1
            end
        end

        -- Debug
        if self.isServer and hasXMLProperty(xmlFile, key .. ".debug") then
            self.debug = {}
            self.debug.fillPercentInputs = math.min(Utils.getNoNil(getXMLInt(xmlFile, key .. ".debug#fillPercentInputs"), 0), 100)
            self.debug.fillPercentOutputs = math.min(Utils.getNoNil(getXMLInt(xmlFile, key .. ".debug#fillPercentOutputs"), 0), 100)
        end
    end

    self.fillTypeConverterDirtyFlag = self:getNextDirtyFlag()

    delete(xmlFile)
    xmlFile = nil

    return true
end

function FillTypeConverter:finalizePlacement()
    FillTypeConverter:superClass().finalizePlacement(self)

    if self.isServer then
        if self.openingHours ~= nil then
            g_currentMission.environment:addHourChangeListener(self)
            self:hourChanged()
        end

        g_currentMission.environment:addMinuteChangeListener(self)

        if self.debug ~= nil then
            -- Only when placed for the first time.
            if not self.loadedFromSaveGame then
                if self.debug.fillPercentInputs > 0 then
                    if self.numInputs > 0 then
                        for _, input in pairs (self.inputs) do
                            local fillLevel = (self.debug.fillPercentInputs / 100) * input.capacity
                            self:setFillLevel(fillLevel, input.lastFillType, input, false, false)
                        end
                    end
                end

                if self.debug.fillPercentOutputs > 0 then
                    if self.numOutputs > 0 then
                        for _, output in pairs (self.outputs) do
                            if not output.hasPalletSpawner then
                                local fillLevel = (self.debug.fillPercentOutputs / 100) * output.capacity
                                self:setFillLevel(fillLevel, output.lastFillType, output, false, false)
                            end
                        end
                    end
                end

                if not self:getIsManualStartStop() and self:getConvertorFactor() > 0 then
                    self:setPartsState(true, false, true)
                end

                self:raiseDirtyFlags(self.fillTypeConverterDirtyFlag)
            end
        end
    end

    g_messageCenter:subscribe(MessageType.FARM_DELETED, self.farmDestroyed, self)

    return true
end

function FillTypeConverter:loadDisplays(xmlFile, key, owner)
    local displays = {}
    local numDisplays = 0

    local i = 0
    while true do
        local displayKey = string.format("%s.displays.display(%d)", key, i)
        if not hasXMLProperty(xmlFile, displayKey) then
            break
        end

        local baseNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, displayKey .. "#baseNode"))
        if baseNode ~= nil then
            local displayType = getXMLString(xmlFile, displayKey .. "#type")
            if displayType ~= nil then
                displayType = displayType:upper()

                if displayType ~= "CAPACITY" then
                    local precision = getXMLInt(xmlFile, displayKey .. "#precision") or 0
                    local showZero = Utils.getNoNil(getXMLBool(xmlFile, displayKey .. "#showZero"), true)
                    local isPercent = displayType == "PERCENT"

                    if displayType ~= "PER_HOUR" then
                        numDisplays = numDisplays + 1
                        I3DUtil.setNumberShaderByValue(baseNode, 0, precision, showZero)
                        displays[numDisplays] = {baseNode = baseNode, precision = precision, showZero = showZero, isPercent = isPercent}
                    else
                        local lengthFactor, seasonsActive = self:getIntervalLengthFactor()
                        if seasonsActive and SeasonsMessageType ~= nil then
                            if self.perHourDisplays ~= nil then
                                table.insert(self.perHourDisplays, {baseNode = baseNode, owner = owner})
                            else
                                self.perHourDisplays = {{baseNode = baseNode, owner = owner}}
                                g_messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
                            end
                        end

                        I3DUtil.setNumberShaderByValue(baseNode, owner.perHour / lengthFactor, 0, true)
                    end
                else
                    I3DUtil.setNumberShaderByValue(baseNode, owner.capacity, 0, true)
                end

                local numberColour = self:getDisplayColour(getXMLString(xmlFile, displayKey .. "#numberColor"))
                if numberColour ~= nil then
                    for node, _ in pairs(I3DUtil.getNodesByShaderParam(baseNode, "numberColor")) do
                        setShaderParameter(node, "numberColor", numberColour[1], numberColour[2], numberColour[3], numberColour[4], false)
                    end
                end
            end
        end

        i = i + 1
    end

    return displays, numDisplays
end

function FillTypeConverter:loadVisNodes(xmlFile, key)
    local visNodes
    local numVisNodes = 0

    local baseNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. ".visibilityNodes#baseNode"))
    if baseNode ~= nil then
        local numInGroup = getNumOfChildren(baseNode)
        if numInGroup > 0 then
            visNodes = {}

            for id = 0, numInGroup - 1 do
                local node = getChildAt(baseNode, id)
                local rigidBodyType = getRigidBodyType(node)

                setVisibility(node, false)
                setRigidBodyType(node, "NoRigidBody")

                local childCollision
                local childId = getUserAttribute(node, "childCollision")
                if childId ~= nil then
                    childCollision = getChildAt(node, tonumber(childId))
                    setRigidBodyType(childCollision, "NoRigidBody")
                end

                numVisNodes = numVisNodes + 1
                visNodes[numVisNodes] = {node = node, rigidBodyType = rigidBodyType, childCollision = childCollision}
            end
        end
    end

    return visNodes, numVisNodes
end

function FillTypeConverter:loadFillPlanes(xmlFile, key, capacity)
    local fillPlanes = {}
    local numFillPlanes = 0

    local i = 0
    while true do
        local fillPlaneKey = string.format("%s.fillPlanes.fillPlane(%d)", key, i)
        if not hasXMLProperty(xmlFile, fillPlaneKey) then
            break
        end

        local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, fillPlaneKey .. "#node"))
        if node ~= nil then
            fillPlane = {minY = 0, maxY = 0, minRY = 0, maxRY = 0, minSY = 0, maxSY = 0, maxFillLevel = capacity}

            local maxFillLevel = getXMLInt(xmlFile, fillPlaneKey .. "#maxFillLevel")
            if maxFillLevel ~= nil then
                fillPlane.maxFillLevel = maxFillLevel
            end

            local minY, maxY = StringUtil.getVectorFromString(getXMLString(xmlFile, fillPlaneKey .. "#minMaxY"))
            fillPlane.updateTranslation = (minY ~= nil and maxY ~= nil)
            if fillPlane.updateTranslation then
                fillPlane.minY = minY
                fillPlane.maxY = maxY
            end

            local minRY, maxRY = StringUtil.getVectorFromString(getXMLString(xmlFile, fillPlaneKey .. "#minMaxRY"))
            fillPlane.updateRotation = (minRY ~= nil and maxRY ~= nil)
            if fillPlane.updateRotation then
                fillPlane.minRY = math.rad(minRY)
                fillPlane.maxRY = math.rad(maxRY)
            end

            local minSY, maxSY = StringUtil.getVectorFromString(getXMLString(xmlFile, fillPlaneKey .. "#minMaxSY"))
            fillPlane.updateScale = (minSY ~= nil and maxSY ~= nil)
            if fillPlane.updateScale then
                fillPlane.minSY = minSY
                fillPlane.maxSY = maxSY
            end

            fillPlane.node = node
            fillPlane.alwaysVisible = Utils.getNoNil(getXMLBool(xmlFile, fillPlaneKey .. "#alwaysVisible"), false)

            fillPlane.useMaterials = Utils.getNoNil(getXMLBool(xmlFile, fillPlaneKey .. "#useMaterials"), false)
            if fillPlane.useMaterials then
                if getHasClassId(node, ClassIds.SHAPE) then
                    fillPlane.originalMaterial = getMaterial(node, 0)
                else
                    fillPlane.useMaterials = false
                    g_logManager:xmlError(self.configFileName, "'useMaterials' is not available, given node is not a shape for '%s'!", fillPlaneKey)
                end
            end

            setVisibility(fillPlane.node, fillPlane.alwaysVisible)

            numFillPlanes = numFillPlanes + 1
            fillPlanes[numFillPlanes] = fillPlane
        end

        i = i + 1
    end

    return fillPlanes, numFillPlanes
end

function FillTypeConverter:loadAnimationNodes(xmlFile, key, sequence)
    local i = 0
    while true do
        local animationNodesKey = string.format("%s.animationNodeGroups.animationNodes(%d)", key, i)
        if not hasXMLProperty(xmlFile, animationNodesKey) then
            break
        end

        local nodes = g_animationManager:loadAnimations(xmlFile, animationNodesKey, self.nodeId, self, nil)
        if nodes ~= nil then

            local linkedInputId = getXMLInt(xmlFile, animationNodesKey .. "#linkedInputId")
            if linkedInputId ~= nil then
                if self.linkedInputAnimationNodes[linkedInputId] == nil then
                    self.linkedInputAnimationNodes[linkedInputId] = {}
                end

                table.insert(self.linkedInputAnimationNodes[linkedInputId], nodes)
            end

            local animationNodes = {nodes = nodes}
            if self:loadSequenceDataFromXML(xmlFile, animationNodesKey, sequence, animationNodes) then
                table.insert(self.sequencedAnimationNodes, animationNodes)
            else
                table.insert(self.animationNodes, animationNodes)
            end
        end

        i = i + 1
    end

    self.numAnimationNodes = #self.animationNodes
    self.numSequencedAnimationNodes = #self.sequencedAnimationNodes
end

function FillTypeConverter:loadAnimationClips(xmlFile, key, sequence)
    local i = 0
    while true do
        local animationKey = string.format("%s.animationClips.animationClip(%d)", key, i)
        if not hasXMLProperty(xmlFile, animationKey) then
            break
        end

        local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, animationKey .. "#node"))
        if node ~= nil then
            local clipName = getXMLString(xmlFile, animationKey .. "#clipName")
            if clipName ~= nil then
                local clip = {}

                clip.characterSet = getAnimCharacterSet(node)
                clip.index = getAnimClipIndex(clip.characterSet, clipName)

                if clip.index ~= nil then
                    assignAnimTrackClip(clip.characterSet, 0, clip.index)

                    clip.speedScale = Utils.getNoNil(getXMLFloat(xmlFile, animationKey .. "#speedScale"), 1)
                    setAnimTrackSpeedScale(clip.characterSet, 0, clip.speedScale)

                    clip.loop = Utils.getNoNil(getXMLBool(xmlFile, animationKey .. "#loop"), true)
                    setAnimTrackLoopState(clip.characterSet, 0, clip.loop)

                    clip.duration = getAnimClipDuration(clip.characterSet, clip.index)

                    if self:loadSequenceDataFromXML(xmlFile, animationKey, sequence, clip) then
                        table.insert(self.sequencedAnimationClips, clip)
                    else
                        table.insert(self.animationClips, clip)
                    end
                end
            end
        end

        i = i + 1
    end

    self.numAnimationClips = #self.animationClips
    self.numSequencedAnimationClips = #self.sequencedAnimationClips
end

function FillTypeConverter:loadChangedParts(xmlFile, key, sequence)
    local i = 0
    while true do
        local changedPartKey = string.format("%s.changedParts.changedPart(%d)", key, i)
        if not hasXMLProperty(xmlFile, changedPartKey) then
            break
        end

        local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, changedPartKey .. "#node"))
        if node ~= nil then
            local startValues = self:loadChangedPartValues(xmlFile, changedPartKey .. "#off", node)
            local endValues = self:loadChangedPartValues(xmlFile, changedPartKey .. "#on", node)

            if startValues.translation ~= nil then
                setTranslation(node, startValues.translation[1], startValues.translation[2], startValues.translation[3])
            end

            if startValues.rotation ~= nil then
                setRotation(node, startValues.rotation[1], startValues.rotation[2], startValues.rotation[3])
            end

            if startValues.scale ~= nil then
                setScale(node, startValues.scale[1], startValues.scale[2], startValues.scale[3])
            end

            if startValues.visibility ~= nil then
                setVisibility(node, startValues.visibility)
            end

            local part = {node = node, startValues = startValues, endValues = endValues}
            if self:loadSequenceDataFromXML(xmlFile, changedPartKey, sequence, part) then
                table.insert(self.sequencedChangedParts, part)
            else
                table.insert(self.changedParts, part)
            end
        end

        i = i + 1
    end

    self.numChangedParts = #self.changedParts
    self.numSequencedChangedParts = #self.sequencedChangedParts
end

function FillTypeConverter:loadChangedPartValues(xmlFile, key, node)
    local translation = getXMLString(xmlFile, key .. "Translation")
    if translation ~= nil then
        local x, y, z = StringUtil.getVectorFromString(translation)
        local dx, dy, dz = getTranslation(node)

        x = Utils.getNoNil(x, dx)
        y = Utils.getNoNil(y, dy)
        z = Utils.getNoNil(z, dz)

        translation = {x, y, z}
    end

    local rotation = getXMLString(xmlFile, key .. "Rotation")
    if rotation ~= nil then
        local rx, ry, rz = StringUtil.getVectorFromString(rotation)
        local drx, dry, drz = getRotation(node)

        rx = Utils.getNoNilRad(rx, drx)
        ry = Utils.getNoNilRad(ry, dry)
        rz = Utils.getNoNilRad(rz, drz)

        rotation = {rx, ry, rz}
    end

    local scale = getXMLString(xmlFile, key .. "Scale")
    if scale ~= nil then
        local sx, sy, sz = StringUtil.getVectorFromString(scale)
        local dsx,dsy,dsz = getScale(node)

        sx = Utils.getNoNil(sx, dsx)
        sy = Utils.getNoNil(sy, dsy)
        sz = Utils.getNoNil(sz, dsz)

        scale = {sx, sy, sz}
    end

    local visibility = Utils.getNoNil(getXMLBool(xmlFile, key .. "Visibility"), true)

    return {translation = translation, rotation = rotation, scale = scale, visibility = visibility}
end

function FillTypeConverter:loadEffects(xmlFile, key, sequence, isParticalSystem)
    local i = 0
    while true do
        local effectKey = string.format("%s(%d)", key, i)
        if not hasXMLProperty(xmlFile, effectKey) then
            break
        end

        local loadedEffects

        if isParticalSystem then
            loadedEffects = {}
            ParticleUtil.loadParticleSystem(xmlFile, loadedEffects, effectKey, self.nodeId, false, nil, self.baseDirectory)
        else
            loadedEffects = g_effectManager:loadEffect(xmlFile, effectKey, self.nodeId, self)
        end

        if loadedEffects ~= nil then
            local cycleInputEffects = false

            local effects = {effects = loadedEffects, fillTypesCycle = 0, isParticalSystem = isParticalSystem}

            if not isParticalSystem then
                local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(getXMLString(xmlFile, effectKey .. "#fillType"))
                effects.fillType = Utils.getNoNil(fillTypeIndex, FillType.WHEAT)

                cycleInputEffects = Utils.getNoNil(getXMLBool(xmlFile, effectKey .. "#cycleInputEffects"), cycleInputEffects)

                local linkedInputId = getXMLInt(xmlFile, effectKey .. "#linkedInputId")
                if not cycleInputEffects and linkedInputId ~= nil then
                    if self.linkedInputEffects[linkedInputId] == nil then
                        self.linkedInputEffects[linkedInputId] = {}
                    end

                    table.insert(self.linkedInputEffects[linkedInputId], effects)
                end
            end

            if self:loadSequenceDataFromXML(xmlFile, effectKey, sequence, effects) then
                if self.numInputs > 0 and cycleInputEffects then
                    effects.fillTypesCycle = self.numInputs

                    if self.cycledInputEffects == nil then
                        self.cycledInputEffects = {}
                    end

                    table.insert(self.cycledInputEffects, effects)
                end

                table.insert(self.sequencedEffects, effects)
            else
                table.insert(self.effects, effects)
            end
        end

        i = i + 1
    end

    self.numEffects = #self.effects
    self.numSequencedEffects = #self.sequencedEffects
end

function FillTypeConverter:loadShaders(xmlFile, key, sequence)
    local i = 0
    while true do
        local shaderKey = string.format("%s.shaders.shader(%d)", key, i)
        if not hasXMLProperty(xmlFile, shaderKey) then
            break
        end

        local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, shaderKey .. "#node"))
        local parameter = getXMLString(xmlFile, shaderKey .. "#parameter")

        if node ~= nil and parameter ~= nil then
            if getHasShaderParameter(node, parameter) then
                local shader = {node = node, parameter = parameter}
                local currentParameter = {getShaderParameter(node, parameter)}

                shader.startValues = Utils.getNoNil(StringUtil.getVectorNFromString(getXMLString(xmlFile, shaderKey .. "#startValues", 4)), currentParameter)
                shader.endValues = Utils.getNoNil(StringUtil.getVectorNFromString(getXMLString(xmlFile, shaderKey .. "#endValues", 4)), currentParameter)

                setShaderParameter(node, parameter, shader.startValues[1], shader.startValues[2], shader.startValues[3], shader.startValues[4], false)

                if self:loadSequenceDataFromXML(xmlFile, shaderKey, sequence, shader) then
                    table.insert(self.sequencedShaders, shader)
                else
                    table.insert(self.shaders, shader)
                end
            end
        end

        i = i + 1
    end

    self.numShaders = #self.shaders
    self.numSequencedShaders = #self.sequencedShaders
end

function FillTypeConverter:loadSounds(xmlFile, key, sequence)
    -- Engine sounds.
    local engineSoundKey = string.format("%s.sounds.engine", key)
    if hasXMLProperty(xmlFile, engineSoundKey) then
        self.engineSamples = {}

        self.engineSamples.start = g_soundManager:loadSampleFromXML(xmlFile, engineSoundKey, "start", self.baseDirectory, self.nodeId, 1, AudioGroup.VEHICLE, nil, self)
        self.engineSamples.stop = g_soundManager:loadSampleFromXML(xmlFile, engineSoundKey, "stop", self.baseDirectory, self.nodeId, 1, AudioGroup.VEHICLE, nil, self)
        self.engineSamples.run = g_soundManager:loadSampleFromXML(xmlFile, engineSoundKey, "run", self.baseDirectory, self.nodeId, 0, AudioGroup.VEHICLE, nil, self)

        if next(self.engineSamples) == nil then
            self.engineSamples = nil
        end
    end

    -- General sounds when active.
    local i = 0
    while true do
        local activeSoundsKey = string.format("%s.sounds.active", key)
        local soundKey = string.format("%s.sound(%d)", activeSoundsKey, i)

        if not hasXMLProperty(xmlFile, soundKey) then
            break
        end

        local sample = g_soundManager:loadSampleFromXML(xmlFile, activeSoundsKey, string.format("sound(%d)", i), self.baseDirectory, self.nodeId, 0, AudioGroup.VEHICLE, nil, self)
        if sample ~= nil then
            if self:loadSequenceDataFromXML(xmlFile, soundKey, sequence, sample) then
                table.insert(self.sequencedActiveSamples, sample)
            else
                table.insert(self.activeSamples, sample)
            end
        end

        i = i + 1
    end

    self.numSamples = #self.activeSamples
    self.numSequencedSamples = #self.sequencedActiveSamples
end

function FillTypeConverter:loadSequenceDataFromXML(xmlFile, key, sequence, part)
    local useSequence = Utils.getNoNil(getXMLBool(xmlFile, key .. "#useSequence"), false)
    if useSequence and sequence ~= nil then
        part.invert = Utils.getNoNil(getXMLBool(xmlFile, key .. "#invertSequence"), false)

        -- Only when using a sequence. Blocks the parts operation if Output fill level is zero.
        local requiredOutputId = getXMLInt(xmlFile, key .. "#requiredOutputId")
        if requiredOutputId ~= nil then
            part.requiredOutput = self.outputs[requiredOutputId]

            if part.requiredOutput == nil then
                g_logManager:xmlWarning(self.configFileName, "Ignoring invalid 'requiredOutputId' given at '%s'!", key)
            end
        end

        return true
    end

    return false
end

function FillTypeConverter:loadBeaconLights(xmlFile, key)
    local i = 0
    while true do
        local beaconLightKey = string.format("%s.beaconLights.beaconLight(%d)", key, i)
        if not hasXMLProperty(xmlFile, beaconLightKey) then
            break
        end

        local rotatorNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, beaconLightKey .. "#rotatorNode"))
        if rotatorNode ~= nil and getHasShaderParameter(rotatorNode, "lightControl") then
            local light = {rotatorNode = rotatorNode}

            light.intensity = getXMLFloat(xmlFile, beaconLightKey .. "#intensity") or 1000
            local _, y, z, w = getShaderParameter(rotatorNode, "lightControl")
            setShaderParameter(rotatorNode, "lightControl", 0, y, z, w, false)

            light.speed = getXMLFloat(xmlFile, beaconLightKey .. "#speed") or 0.015
            if light.speed > 0 then
                local rot = math.random(0, math.pi*2)
                setRotation(light.rotatorNode, 0, rot, 0)
            end

            light.realLightNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, beaconLightKey .. "#realLightNode"))
            if light.realLightNode ~= nil then
                light.defaultColor = {getLightColor(light.realLightNode)}
                setVisibility(light.realLightNode, false)
            end

            table.insert(self.beaconLights, light)
        end

        i = i + 1
    end

    self.numBeaconLights = #self.beaconLights
end

function FillTypeConverter:loadPalletSpawner(xmlFile, key, output)
    if output.combinedCapacity then
        return nil, 0
    end

    local numSpawners = 0
    local palletSpawners = {spawners = {}}

    local i = 0
    while true do
        local palletSpawnerKey = string.format("%s.palletSpawners.palletSpawner(%d)", key, i)
        if not hasXMLProperty(xmlFile, palletSpawnerKey) then
            break
        end

        local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, palletSpawnerKey .. "#node"))
        local triggerId = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, palletSpawnerKey .. "#triggerNode"))

        if node ~= nil and triggerId ~= nil then
            addTrigger(triggerId, "palletSpawnerTriggerCallback", self)

            if self.palletSpawnerTriggers == nil then
                self.palletSpawnerTriggers = {}
            end

            table.insert(self.palletSpawnerTriggers, triggerId)

            self.triggerIdToTrigger[triggerId] = palletSpawners

            numSpawners = numSpawners + 1
            palletSpawners.spawners[numSpawners] = {node = node, triggerId = triggerId}
        end

        i = i + 1
    end

    if numSpawners > 0 then
        local configFilename = Utils.getNoNil(getXMLString(xmlFile, key .. ".palletSpawners#filename"), "")
        if configFilename ~= "" then
            configFilename = Utils.getFilename(configFilename, self.baseDirectory)
            if g_storeManager:getItemByXMLFilename(configFilename) ~= nil then
                palletSpawners.sizeWidth, palletSpawners.sizeLength, _, _ = StoreItemUtil.getSizeValues(configFilename, "vehicle", 0, {})

                local storeItem = g_storeManager:getItemByXMLFilename(configFilename)
                local capacity, _ = FillUnit.getSpecValueCapacity(storeItem, nil, true, nil)
                if capacity == nil then
                   capacity = 1000
                end

                if Utils.getNoNil(getXMLBool(xmlFile, key .. ".palletSpawners#capacityFromStoreItem"), true) then
                    output.capacity = capacity * numSpawners
                end

                if capacity < output.perInterval then
                    local factor = capacity / output.perInterval
                    local originalIntervalValue = math.ceil(output.perInterval)
                    local reducedPercent = (1 - factor) * 100

                    output.perHour = output.perHour * factor
                    output.perInterval = output.perInterval * factor

                    g_logManager:xmlWarning(self.configFileName, "Pallet capacity '%s' is less than interval value '%s' at '%s'! Reducing interval value by %d%%.", capacity, originalIntervalValue, key, reducedPercent)
                    g_logManager:xmlInfo(self.configFileName, "Pallet capacity should be increased or 'perHour' value reduced at '%s'.", key)
                end
            else
                configFilename = ""
                palletSpawners.sizeWidth, palletSpawners.sizeLength = 2, 2
                g_logManager:xmlError(self.configFileName, "Invalid store item given at '%s.palletSpawners#filename'.", key)
            end
        end

        palletSpawners.numSpawners = numSpawners

        palletSpawners.owner = output
        palletSpawners.fillDelta = 0

        palletSpawners.objects = {}
        palletSpawners.numObjects = 0

        palletSpawners.configFilename = configFilename
        palletSpawners.fillTypeIndex = output.fillType

        palletSpawners.fillUnitIndex = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".palletSpawners#fillUnitIndex"), 1)
    else
        palletSpawners = nil
    end

    return palletSpawners, numSpawners
end

function FillTypeConverter:delete()
    if self.loadTriggers ~= nil then
        for _, loadTrigger in pairs(self.loadTriggers) do
            loadTrigger:delete()
        end
        self.loadTriggers = nil
    end

    if self.unloadTriggers ~= nil then
        for _, unloadTrigger in pairs(self.unloadTriggers) do
            unloadTrigger:delete()
        end
        self.unloadTriggers = nil
    end

    if self.woodTriggers ~= nil then
        for _, woodTrigger in pairs(self.woodTriggers) do
            removeTrigger(woodTrigger.triggerId)
        end
        self.woodTriggers = nil
    end

    if self.animalTriggers ~= nil then
        for _, animalTrigger in pairs(self.animalTriggers) do
            animalTrigger:delete()
        end
        self.animalTriggers = nil
    end

    if self.palletSpawnerTriggers ~= nil then
        for _, triggerId in pairs (self.palletSpawnerTriggers) do
            removeTrigger(triggerId)
        end
        self.palletSpawnerTriggers = nil
    end

    if self.interactionTrigger ~= nil then
        removeTrigger(self.interactionTrigger)

        self.playerInRange = false
        g_currentMission:removeActivatableObject(self)
    end

    self:addRemoveActionEvents(false)

    if self.fillTypeConverterUI ~= nil then
        self.fillTypeConverterUI:delete()
        self.fillTypeConverterUI = nil
    end

    if self.automaticAnimatedObjects ~= nil then
        for _, animatedObject in pairs(self.automaticAnimatedObjects) do
            animatedObject:delete()
        end
    end

    if self.isClient then
        if self.numEffects > 0 then
            for i = 1, self.numEffects do
                if self.effects[i].isParticalSystem then
                    ParticleUtil.deleteParticleSystem(self.effects[i].effects)
                else
                    g_effectManager:deleteEffects(self.effects[i].effects)
                end
            end
            self.numEffects = 0
        end

        if self.numSequencedEffects > 0 then
            for i = 1, self.numSequencedEffects do
                if self.sequencedEffects[i].isParticalSystem then
                    ParticleUtil.deleteParticleSystem(self.sequencedEffects[i].effects)
                else
                    g_effectManager:deleteEffects(self.sequencedEffects[i].effects)
                end
            end
            self.numSequencedEffects = 0
        end

        if self.numAnimationNodes > 0 then
            for i = 1, self.numAnimationNodes do
                g_animationManager:deleteAnimations(self.animationNodes[i].nodes)
            end
            self.numAnimationNodes = 0
        end

        if self.numSequencedAnimationNodes > 0 then
            for i = 1, self.numSequencedAnimationNodes do
                g_animationManager:deleteAnimations(self.sequencedAnimationNodes[i].nodes)
            end
            self.numSequencedAnimationNodes = 0
        end

        if self.numSamples > 0 then
            g_soundManager:deleteSamples(self.activeSamples)
            self.numSamples = 0
        end

        if self.engineSamples ~= nil then
            g_soundManager:deleteSamples(self.engineSamples)
            self.engineSamples = nil
        end

        if self.numSequencedSamples > 0 then
            g_soundManager:deleteSamples(self.sequencedActiveSamples)
            self.numSequencedSamples = 0
        end
    end

    if self.isServer then
        g_currentMission.environment:removeMinuteChangeListener(self)
        g_currentMission.environment:removeHourChangeListener(self)
    end

    g_messageCenter:unsubscribeAll(self)

    unregisterObjectClassName(self)
    FillTypeConverter:superClass().delete(self)
end

function FillTypeConverter:readStream(streamId, connection)
    FillTypeConverter:superClass().readStream(self, streamId, connection)

    if connection:getIsServer() then
        for _, loadTrigger in ipairs(self.loadTriggers) do
            local loadTriggerId = NetworkUtil.readNodeObjectId(streamId)
            loadTrigger:readStream(streamId, connection)
            g_client:finishRegisterObject(loadTrigger, loadTriggerId)
        end

        for _, unloadTrigger in ipairs(self.unloadTriggers) do
            local unloadTriggerId = NetworkUtil.readNodeObjectId(streamId)
            unloadTrigger:readStream(streamId, connection)
            g_client:finishRegisterObject(unloadTrigger, unloadTriggerId)
        end

        for _, animalTrigger in ipairs(self.animalTriggers) do
            local animalTriggerId = NetworkUtil.readNodeObjectId(streamId)
            animalTrigger:readStream(streamId, connection)
            g_client:finishRegisterObject(animalTrigger, animalTriggerId)
        end

        if self.automaticAnimatedObjects ~= nil then
            for _, animatedObject in ipairs(self.automaticAnimatedObjects) do
                local animatedObjectId = NetworkUtil.readNodeObjectId(streamId)
                animatedObject:readStream(streamId, connection)
                g_client:finishRegisterObject(animatedObject, animatedObjectId)
            end
        end

        if self.numInputs > 0 then
            for i = 1, self.numInputs do
                local lastFillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
                local fillLevel = streamReadFloat32(streamId)
                self:setFillLevel(fillLevel, lastFillType, self.inputs[i], false, false)
            end
        end

        if self.numOutputs > 0 then
            for i = 1, self.numOutputs do
                local output = self.outputs[i]
                local fillLevel = streamReadFloat32(streamId)
                self:setFillLevel(fillLevel, output.lastFillType, output, false, false)
            end
        end

        local partsState = streamReadBool(streamId)
        self:setPartsState(partsState, false, false)
    end
end

function FillTypeConverter:writeStream(streamId, connection)
    FillTypeConverter:superClass().writeStream(self, streamId, connection)

    if not connection:getIsServer() then
        for _, loadTrigger in ipairs(self.loadTriggers) do
            NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(loadTrigger))
            loadTrigger:writeStream(streamId, connection)
            g_server:registerObjectInStream(connection, loadTrigger)
        end

        for _, unloadTrigger in ipairs(self.unloadTriggers) do
            NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(unloadTrigger))
            unloadTrigger:writeStream(streamId, connection)
            g_server:registerObjectInStream(connection, unloadTrigger)
        end

        for _, animalTrigger in ipairs(self.animalTriggers) do
            NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(animalTrigger))
            animalTrigger:writeStream(streamId, connection)
            g_server:registerObjectInStream(connection, animalTrigger)
        end

        if self.automaticAnimatedObjects ~= nil then
            for _, animatedObject in ipairs(self.automaticAnimatedObjects) do
                NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(animatedObject))
                animatedObject:writeStream(streamId, connection)
                g_server:registerObjectInStream(connection, animatedObject)
            end
        end

        if self.numInputs > 0 then
            for i = 1, self.numInputs do
                streamWriteUIntN(streamId, self.inputs[i].lastFillType, FillTypeManager.SEND_NUM_BITS)
                streamWriteFloat32(streamId, self.inputs[i].fillLevel)
            end
        end

        if self.numOutputs > 0 then
            for i = 1, self.numOutputs do
                streamWriteFloat32(streamId, self.outputs[i].fillLevel)
            end
        end

        streamWriteBool(streamId, self.partsState)
    end
end

function FillTypeConverter:readUpdateStream(streamId, timestamp, connection)
    FillTypeConverter:superClass().readUpdateStream(self, streamId, timestamp, connection)

    if connection:getIsServer() then
        if streamReadBool(streamId) then
            if self.numInputs > 0 then
                for i = 1, self.numInputs do
                    local lastFillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
                    local fillLevel = streamReadFloat32(streamId)
                    self:setFillLevel(fillLevel, lastFillType, self.inputs[i], false, false)
                end
            end

            if self.numOutputs > 0 then
                for i = 1, self.numOutputs do
                    local output = self.outputs[i]
                    local fillLevel = streamReadFloat32(streamId)
                    self:setFillLevel(fillLevel, output.lastFillType, output, false, false)
                end
            end
        end
    end
end

function FillTypeConverter:writeUpdateStream(streamId, connection, dirtyMask)
    FillTypeConverter:superClass().writeUpdateStream(self, streamId, connection, dirtyMask)

    if not connection:getIsServer() then
        if streamWriteBool(streamId, bitAND(dirtyMask, self.fillTypeConverterDirtyFlag) ~= 0) then
            if self.numInputs > 0 then
                for i = 1, self.numInputs do
                    local input = self.inputs[i]
                    streamWriteUIntN(streamId, input.lastFillType, FillTypeManager.SEND_NUM_BITS)
                    streamWriteFloat32(streamId, input.fillLevel)
                end
            end

            if self.numOutputs > 0 then
                for i = 1, self.numOutputs do
                    streamWriteFloat32(streamId, self.outputs[i].fillLevel)
                end
            end
        end
    end
end

function FillTypeConverter:saveToXMLFile(xmlFile, key, usedModNames)
    FillTypeConverter:superClass().saveToXMLFile(self, xmlFile, key, usedModNames)

    if self.saveUpdateTime then
        setXMLInt(xmlFile, key .. ".fillTypeConverter#updateMinute", self.updateMinute)
    end

    setXMLBool(xmlFile, key .. ".fillTypeConverter#statusUiEnabled", self.statusUiEnabled)
    setXMLBool(xmlFile, key .. ".fillTypeConverter#partsState", self.partsState)

    for i = 1, self.numInputs do
        local input = self.inputs[i]
        local inputKey = string.format("%s.fillTypeConverter.inputs.input%d", key, i)

        local lastFillTypeName = g_fillTypeManager:getFillTypeNameByIndex(input.lastFillType)

        setXMLString(xmlFile, inputKey .. "#lastFillType", lastFillTypeName)
        setXMLFloat(xmlFile, inputKey .. "#fillLevel", input.fillLevel)
    end

    for i = 1, self.numOutputs do
        local output = self.outputs[i]
        local outputKey = string.format("%s.fillTypeConverter.outputs.output%d", key, i)

        local lastFillTypeName = g_fillTypeManager:getFillTypeNameByIndex(output.lastFillType)

        setXMLString(xmlFile, outputKey .. "#lastFillType", lastFillTypeName)
        setXMLFloat(xmlFile, outputKey .. "#fillLevel", output.fillLevel)

        if output.hasPalletSpawner and output.palletSpawners.fillDelta > 0 then
            setXMLFloat(xmlFile, outputKey .. "#palletSpawnerFillDelta", output.palletSpawners.fillDelta)
        end
    end

    if self.automaticAnimatedObjects ~= nil then
        for i = 1, #self.automaticAnimatedObjects do
            self.automaticAnimatedObjects[i]:saveToXMLFile(xmlFile, string.format("%s.automaticAnimatedObjects.animatedObject(%d)", key, i - 1), usedModNames)
        end
    end
end

function FillTypeConverter:loadFromXMLFile(xmlFile, key, resetVehicles)
    if not FillTypeConverter:superClass().loadFromXMLFile(self, xmlFile, key, resetVehicles) then
        return false
    end

    if self.saveUpdateTime then
        self.updateMinute = math.max(Utils.getNoNil(getXMLInt(xmlFile, key .. ".fillTypeConverter#updateMinute"), 0), 0)
    end

    self.statusUiEnabled = Utils.getNoNil(getXMLBool(xmlFile, key .. ".fillTypeConverter#statusUiEnabled"), true)

    for i = 1, self.numInputs do
        local input = self.inputs[i]
        local inputKey = string.format("%s.fillTypeConverter.inputs.input%d", key, i)

        if hasXMLProperty(xmlFile, inputKey) then
            local lastFillTypeName = getXMLString(xmlFile, inputKey .. "#lastFillType")
            local lastFillType = g_fillTypeManager:getFillTypeIndexByName(lastFillTypeName)
            if lastFillType == nil then
                lastFillType = input.lastFillType
            end

            local fillLevel = getXMLFloat(xmlFile, inputKey .. "#fillLevel")
            if fillLevel == nil or fillLevel < 0 then
                fillLevel = 0
            end

            self:setFillLevel(fillLevel, lastFillType, input, false, false)
        end
    end

    for i = 1, self.numOutputs do
        local output = self.outputs[i]
        local outputKey = string.format("%s.fillTypeConverter.outputs.output%d", key, i)

        if hasXMLProperty(xmlFile, outputKey) then
            local lastFillTypeName = getXMLString(xmlFile, outputKey .. "#lastFillType")
            local lastFillType = g_fillTypeManager:getFillTypeIndexByName(lastFillTypeName)
            if lastFillType == nil then
                lastFillType = output.lastFillType
            end

            local fillLevel = getXMLFloat(xmlFile, outputKey .. "#fillLevel")
            if fillLevel == nil or fillLevel < 0 then
                fillLevel = 0
            end

            self:setFillLevel(fillLevel, lastFillType, output, false, false)

            if output.hasPalletSpawner then
                local fillDelta = getXMLFloat(xmlFile, outputKey .. "#palletSpawnerFillDelta")
                if fillDelta ~= nil and fillDelta > 0 then
                    output.palletSpawners.fillDelta = fillDelta

                    if fillDelta > HusbandryModulePallets.fillLevelThresholdForDeletion then
                        self.extraPalletDelta = true
                    end
                end
            end
        end
    end

    local canStart = true

    if self:getIsManualStartStop() then
        canStart = Utils.getNoNil(getXMLBool(xmlFile, key .. ".fillTypeConverter#partsState"), false)
    end

    if canStart and self:getConvertorFactor() > 0 then
        self:setPartsState(true, false, false)
    end

    if self.automaticAnimatedObjects ~= nil then
        for i = 1, #self.automaticAnimatedObjects do
            self.automaticAnimatedObjects[i]:loadFromXMLFile(xmlFile, string.format("%s.automaticAnimatedObjects.animatedObject(%d)", key, i - 1))
        end
    end

    self.loadedFromSaveGame = true

    return true
end

function FillTypeConverter:update(dt)
    if self.isClient then
        if not self.isEnabled then
            if (self.openingHours ~= nil and self.openingHours.closedText ~= nil) and (g_currentMission.controlPlayer and self.playerInRange) then
                g_currentMission:addExtraPrintText(self.openingHours.closedText)
                self:raiseActive()
            end
        end

        if self.partsSequencing.active then
            self.partsSequencing.time = self.partsSequencing.time - dt

            if self.partsSequencing.time <= 0 then
                self.partsSequencing.id = self.partsSequencing.id + 1

                if self.partsSequencing.id > self.partsSequencing.numSequence then
                    self.partsSequencing.id = 1
                end

                self.partsSequencing.time = self.partsSequencing.time + self.partsSequencing.sequence[self.partsSequencing.id]
                self:setSequencedPartsState(not self.partsSequencing.state, false)
            end

            self:raiseActive()
        end

        if self.numBeaconLights > 0 and self.beaconLightsActive then
            for i = 1, self.numBeaconLights do
                local beaconLight = self.beaconLights[i]
                if beaconLight.speed > 0 then
                    rotate(beaconLight.rotatorNode, 0, beaconLight.speed * dt, 0)
                end
            end
            self:raiseActive()
        end
    end
end

function FillTypeConverter:updateTick(dt)
    if self.isServer then
        if self.partsCheckTimer > 0 then
            self.partsCheckTimer = self.partsCheckTimer - 1
            self:raiseActive()
        else
            self.partsCheckFillType = nil
            self.partsCheckType = nil
        end
    end
end

function FillTypeConverter:hourChanged()
    if self.isServer and self.openingHours ~= nil then
        local currentHour = g_currentMission.environment.currentHour

        if currentHour >= self.openingHours.startTime and currentHour < self.openingHours.endTime then
            if not self.isEnabled then
                self.isEnabled = true
                self:serverStartPartsCheck(false, false)
            end
        else
            if self.isEnabled then
                self.isEnabled = false
                self:setPartsState(false, false, true)
            end
        end
    end
end

function FillTypeConverter:minuteChanged(minute)
    if not self.isServer then
        return
    end

    -- Push all updates at the end to save network traffic :-)
    local raiseDirtyFlag = false

    if self:getIsConverterEnabled() then
        if self.updateMinute == 0 and self.extraPalletDelta then
            self.extraPalletDelta = false

            for i = 1, self.numOutputs do
                local output = self.outputs[i]
                if output.hasPalletSpawner and output.fillLevel < output.capacity and output.palletSpawners.fillDelta > HusbandryModulePallets.fillLevelThresholdForDeletion then
                    local _, _, nextPallet, _ = self:getPalletsFillLevels(output.palletSpawners)
                    self:resetCurrentPallet(output.palletSpawners, nextPallet)

                    local fillLevel = self:updatePalletFillLevel(output.palletSpawners, 0)
                    if fillLevel ~= nil and fillLevel > 0 then
                        self:setFillLevel(fillLevel, output.fillType, output, false, false)
                        raiseDirtyFlag = true
                    end
                end
            end
        end

        self.updateMinute = self.updateMinute + 1

        if self.updateMinute >= self.updateInterval then
            self.updateMinute = 0

            local factor, lengthFactor = self:getConvertorFactor()
            local canOperate = factor > 0

            if canOperate then
                for i = 1, self.numOutputs do
                    local output = self.outputs[i]
                    local outputToAdd = (output.perInterval / lengthFactor) * factor
                    local fillLevel = output.fillLevel + outputToAdd

                    if output.hasPalletSpawner then
                        fillLevel = self:updatePalletFillLevel(output.palletSpawners, outputToAdd)
                        if fillLevel == nil then
                            fillLevel, _, _, _ = self:getPalletsFillLevels(output.palletSpawners)
                        end
                    end

                    self:setFillLevel(fillLevel, output.fillType, output, false, false)

                    if output.fillLevel >= output.capacity then
                        if not self.outputs[1].combinedCapacity then
                            canOperate = false
                        else
                            if i == 1 then
                                canOperate = false
                            end
                        end
                    end
                end

                for i = 1, self.numInputs do
                    local input = self.inputs[i]
                    local inputToRemove = (input.perInterval / lengthFactor) * factor

                    self:setFillLevel(input.fillLevel - inputToRemove, input.lastFillType, input, false, false)

                    if input.fillLevel <= 0 then
                        canOperate = false
                    end
                end

                raiseDirtyFlag = true
            end

            self:setPartsState(canOperate, false, true)
        end
    end

    -- Same as Animal Pen Extension but no need to use update loop.
    -- This is the best way for performance both system and network.
    if self.rainInputPerHour ~= nil and self.rainInputPerHour.value > 0 then
        local rainWaterSource = self.rainInputPerHour.source

        if rainWaterSource ~= nil then
            local fillLevel = rainWaterSource.fillLevel
            if rainWaterSource.inputId ~= nil then
                fillLevel = self:getAdjustedInputFillLevel(rainWaterSource)
            end

            if (fillLevel < rainWaterSource.capacity) then
                if g_currentMission.environment.weather:getIsRaining() then
                    local rainToAdd = (self.rainInputPerHour.value / 60) * g_currentMission.environment.weather:getRainFallScale()
                    self.rainWaterCollected = self.rainWaterCollected + rainToAdd

                    if self.rainWaterCollected >= 15 then
                        self:setFillLevel(rainWaterSource.fillLevel + self.rainWaterCollected, FillType.WATER, rainWaterSource, false, false)
                        self:serverStartPartsCheck(false, false)
                        self.rainWaterCollected = 0
                        raiseDirtyFlag = true
                    end
                else
                    if self.rainWaterCollected ~= 0 then
                        if self.rainWaterCollected > 6 then
                            self:setFillLevel(rainWaterSource.fillLevel + self.rainWaterCollected, FillType.WATER, rainWaterSource, false, false)
                            self:serverStartPartsCheck(false, false)
                            raiseDirtyFlag = true
                        end

                        self.rainWaterCollected = 0
                    end
                end
            end
        end
    end

    if raiseDirtyFlag then
        self:raiseDirtyFlags(self.fillTypeConverterDirtyFlag)
    end
end

function FillTypeConverter:getConvertorFactor()
    local factor = 1

    local numOutputs = self.numOutputs
    local numInputs = self.numInputs

    local lengthFactor, _ = self:getIntervalLengthFactor()

    if numOutputs > 0 then
        if self.outputs[1].combinedCapacity then
            numOutputs = 1
            numInputs = math.min(self.numInputs, 1)
        end

        for i = 1, numOutputs do
            local output = self.outputs[i]

            local fillLevel = output.fillLevel
            local capacity = output.capacity

            if output.hasPalletSpawner then
                local palletFillLevel, _, nextPallet, freeArea = self:getPalletsFillLevels(output.palletSpawners)
                self:resetCurrentPallet(output.palletSpawners, nextPallet)

                if output.palletSpawners.currentPallet ~= nil or freeArea ~= nil then
                    fillLevel = palletFillLevel
                else
                    fillLevel = capacity
                end
            end

            local availableFactor = 0.0
            local perInterval = output.perInterval / lengthFactor

            if perInterval > 0 then
                local availableStorage = math.min(perInterval, capacity - fillLevel)
                availableFactor = availableStorage / perInterval
            end

            if availableFactor < factor then
                factor = availableFactor
            end

            if factor <= 0 then
                return 0, 1
            end
        end
    end

    if numInputs > 0 then
        for i = 1, numInputs do
            local input = self.inputs[i]

            local availableFactor = 0.0
            local perInterval = input.perInterval / lengthFactor

            if perInterval > 0 then
                local availableFillLevel = math.min(perInterval, input.fillLevel)
                availableFactor = availableFillLevel / perInterval
            end

            if availableFactor < factor then
                factor = availableFactor
            end

            if factor <= 0 then
                return 0, 1
            end
        end
    end

    return factor, lengthFactor
end

function FillTypeConverter:getIntervalLengthFactor()
    if self.adjustForSeasonsLength and g_seasons ~= nil and g_seasons.environment ~= nil then
        return g_seasons.environment.daysPerSeason / 3, true
    end

    return 1, false
end

function FillTypeConverter:setFillLevel(fillLevel, fillType, converterType, doPartsCheck, raiseDirtyFlag)
    if converterType == nil then
        converterType = self.fillTypeToOutput[fillType]
    end

    if converterType ~= nil then
        fillLevel = MathUtil.clamp(fillLevel, 0, converterType.capacity)

        if fillLevel ~= converterType.fillLevel then
            converterType.fillLevel = fillLevel

            if self.isClient then
                if converterType.inputId then
                    local effectsGroup = self.linkedInputEffects[converterType.inputId]
                    if effectsGroup ~= nil then
                        for i = 1, #effectsGroup do
                            local effects = effectsGroup[i]

                            if fillType ~= effects.fillType then
                                effects.fillType = fillType
                                g_effectManager:setFillType(effects.effects, fillType)
                            end
                        end
                    end

                    if self.cycledInputEffects ~= nil then
                        for i = 1, #self.cycledInputEffects do
                            local effects = self.cycledInputEffects[i]

                            if effects.fillTypesCycle > 0 and effects.fillTypesCycle == converterType.inputId then
                                if fillType ~= effects.fillType then
                                    effects.fillType = fillType
                                    g_effectManager:setFillType(effects.effects, fillType)
                                end
                            end
                        end
                    end

                    local animationNodesGroup = self.linkedInputAnimationNodes[converterType.inputId]
                    if animationNodesGroup ~= nil then
                        g_animationManager:setFillType(animationNodesGroup, fillType)
                    end
                end

                if converterType.numDisplays > 0 then
                    local level, percent = 0, 0
                    if converterType.isFillTypes then
                        level = math.floor(fillLevel + 0.5)
                    else
                        level = math.ceil(fillLevel)
                    end

                    if level > 0 then
                        percent = MathUtil.clamp(level / converterType.capacity, 0, 1) * 100
                    end

                    for i = 1, converterType.numDisplays do
                        local display = converterType.displays[i]

                        if not display.isPercent then
                            I3DUtil.setNumberShaderByValue(display.baseNode, level, 0, display.showZero)
                        else
                            I3DUtil.setNumberShaderByValue(display.baseNode, percent + 0.5, 0, display.showZero)
                        end
                    end
                end

                if converterType.numFillPlanes > 0 ~= nil then
                    for i = 1, converterType.numFillPlanes do
                        local fillPlane = converterType.fillPlanes[i]

                        if fillPlane.updateTranslation then
                            local x, y, z = getTranslation(fillPlane.node)
                            y = math.min(fillPlane.minY + fillLevel / fillPlane.maxFillLevel * (fillPlane.maxY - fillPlane.minY), fillPlane.maxY)
                            setTranslation(fillPlane.node, x, y, z)
                        end

                        if fillPlane.updateRotation then
                            local rx, ry, rz = getRotation(fillPlane.node)
                            ry = math.min(fillPlane.minRY + fillLevel / fillPlane.maxFillLevel * (fillPlane.maxRY - fillPlane.minRY), fillPlane.maxRY)
                            setRotation(fillPlane.node, rx, ry, rz)
                        end

                        if fillPlane.updateScale then
                            local sx, sy, sz = getScale(fillPlane.node)
                            sy = math.min(fillPlane.minSY + fillLevel / fillPlane.maxFillLevel * (fillPlane.maxSY - fillPlane.minSY), fillPlane.maxSY)
                            setScale(fillPlane.node, sx, sy, sz)
                        end

                        if converterType.lastFillType ~= fillType and fillPlane.useMaterials then
                            local newMaterial = self.fillPlaneMaterials[fillType]
                            if newMaterial ~= nil then
                                local nodeMaterial = getMaterial(fillPlane.node, 0)
                                if nodeMaterial ~= newMaterial then
                                    setMaterial(fillPlane.node, newMaterial, 0)
                                end
                            else
                                local nodeMaterial = getMaterial(fillPlane.node, 0)
                                if nodeMaterial ~= fillPlane.originalMaterial then
                                    setMaterial(fillPlane.node, fillPlane.originalMaterial, 0)
                                end
                            end
                        end

                        setVisibility(fillPlane.node, fillLevel > 0.0001 or fillPlane.alwaysVisible)
                    end
                end

                local numVisNodes = converterType.numVisNodes
                if numVisNodes > 0 then
                    local visibleNodes = math.ceil((numVisNodes * fillLevel) / converterType.capacity)

                    for i = 1, numVisNodes do
                        local visNode = converterType.visNodes[i]
                        local stateActive = i <= visibleNodes

                        if stateActive ~= visNode.stateActive then
                            visNode.stateActive = stateActive

                            local rigidBodyType = "NoRigidBody"
                            if visNode.stateActive then
                                rigidBodyType = visNode.rigidBodyType
                            end

                            setVisibility(visNode.node, visNode.stateActive)
                            setRigidBodyType(visNode.node, rigidBodyType)

                            if visNode.childCollision ~= nil then
                                setVisibility(visNode.childCollision, visNode.stateActive)
                                setRigidBodyType(visNode.childCollision, rigidBodyType)
                            end
                        end
                    end
                end
            end

            converterType.lastFillType = fillType

            if self.isServer and raiseDirtyFlag == true then
                self.partsCheckTimer = 30

                if doPartsCheck == true and ((self.partsCheckFillType ~= fillType) or (self.partsCheckType ~= converterType.type)) then
                    self.partsCheckFillType = fillType
                    self.partsCheckType = converterType.type
                    self:serverStartPartsCheck(false, false)
                end

                self:raiseActive()
                self:raiseDirtyFlags(self.fillTypeConverterDirtyFlag)
            end
        end
    end
end

function FillTypeConverter:serverStartPartsCheck(force, isManualInput)
    if self:getIsManualStartStop() then
        if isManualInput == nil or isManualInput == false then
            return self.partsState, -1
        end
    end

    local startParts = true
    local stateIndex = 0

    local numOutputs = self.numOutputs
    local numInputs = self.numInputs

    if numOutputs > 0 then
        if self.outputs[1].combinedCapacity then
            numOutputs = 1
            numInputs = math.min(self.numInputs, 1)
        end

        for i = 1, numOutputs do
            local output = self.outputs[i]

            if not output.hasPalletSpawner then
                if (output.capacity - output.fillLevel) <= 0 then
                    startParts = false
                    stateIndex = 2
                    break
                end
            else
                local fillLevel, capacity, _, freeArea, nonFillLevel = self:getPalletsFillLevels(palletSpawners)
                if output.capacity - (fillLevel + nonFillLevel) <= 0 then
                    startParts = false
                    stateIndex = 2
                    break
                end
            end
        end
    end

    if startParts and numInputs > 0 then
        for i = 1, numInputs do
            if self.inputs[i].fillLevel <= 0 then
                startParts = false
                stateIndex = 1
                break
            end
        end
    end

    if isManualInput == nil or isManualInput == false then
        self:setPartsState(startParts, force, true)
    end

    return startParts, stateIndex
end

function FillTypeConverter:addRemoveActionEvents(addActionEvent)
    if self:getIsManualStartStop() then
        g_inputBinding:beginActionEventsModification(Player.INPUT_CONTEXT_NAME)

        if addActionEvent then
            local _, actionEventId = g_inputBinding:registerActionEvent(self.manualStartInputAction, self, self.onStartStopInputPressed, false, true, false, false)
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
            self.manualStartInputEventId = actionEventId
        else
            g_inputBinding:removeActionEventsByTarget(self)
            self.manualStartInputEventId = nil
        end

        g_inputBinding:endActionEventsModification()
    end
end

function FillTypeConverter:onStartStopInputPressed(actionName, inputValue)
    if self.isServer then
        local setActive = not self.partsState

        if setActive then
            local active, stateIndex = self:serverStartPartsCheck(false, true)

            if active then
                self:setPartsState(true, true, true)
            else
                if stateIndex > 0 then
                    g_currentMission:showBlinkingWarning(g_i18n:getText("warning_actionNotAllowedNow"))
                end
            end
        else
            self:setPartsState(false, true, true)
        end
    else
        g_client:getServerConnection():sendEvent(FillTypeConverterStartStopEvent:new(self, 0))
    end
end

function FillTypeConverter:setPartsState(state, force, eventSend)
    if self.partsState ~= state or force then
        self.partsState = state

        if self.isServer and eventSend == true then
            g_server:broadcastEvent(FillTypeConverterStateEvent:new(self, self.partsState))
        end

        if self.isClient then
            if self.showFillLevelWarnings and not self.partsState and g_dedicatedServerInfo == nil then
                local message = self:getActiveWarningMessage()
                if message ~= "" then
                    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
                end
            end

            if self.partsSequencing.numSequence > 0 then
                if state then
                    self.partsSequencing.active = true
                    self:raiseActive()
                else
                    self.partsSequencing.active = false
                    self:setSequencedPartsState(false, true)
                    self.partsSequencing.id = 0
                    self.partsSequencing.time = 0.0
                end
            end

            if self.numAnimationNodes > 0 then
                self:setAnimationNodesState(self.animationNodes, false, state, false)
            end

            if self.numAnimationClips > 0 then
                self:setAnimationsState(self.animationClips, false, state, false)
            end

            if self.numChangedParts > 0 then
                self:setChangedPartsState(self.changedParts, false, state, false)
            end

            if self.numEffects > 0 then
                self:setEffectsState(self.effects, false, state, false)
            end

            if self.numShaders > 0 then
                self:setShaderState(self.shaders, false, state, false)
            end

            if self.engineSamples ~= nil then
                if state then
                    g_soundManager:playSample(self.engineSamples.start)
                    g_soundManager:playSample(self.engineSamples.run, 0, self.engineSamples.start)
                else
                    g_soundManager:stopSample(self.engineSamples.start)
                    g_soundManager:playSample(self.engineSamples.stop)
                    g_soundManager:stopSample(self.engineSamples.run)
                end
            end

            if self.numSamples > 0 then
                self:setActiveSamplesState(self.activeSamples, false, state, false)
            end

            if self.numBeaconLights > 0 then
                self.beaconLightsActive = state

                local realBeaconLights = g_gameSettings:getValue("realBeaconLights")
                for i = 1, self.numBeaconLights do
                    local beaconLight = self.beaconLights[i]

                    if realBeaconLights and beaconLight.realLightNode ~= nil then
                        setVisibility(beaconLight.realLightNode, state)
                    end

                    local value = 0
                    if state then
                        value = 1 * beaconLight.intensity
                        self:raiseActive()
                    end

                    local _,y,z,w = getShaderParameter(beaconLight.rotatorNode, "lightControl")
                    setShaderParameter(beaconLight.rotatorNode, "lightControl", value, y, z, w, false)
                end
            end
        end
    end
end

function FillTypeConverter:setSequencedPartsState(state, force)
    if self.partsSequencing.state ~= state or force then
        self.partsSequencing.state = state

        if self.numSequencedAnimationNodes > 0 then
            self:setAnimationNodesState(self.sequencedAnimationNodes, true, state, force)
        end

        if self.numSequencedAnimationClips > 0 then
            self:setAnimationsState(self.sequencedAnimationClips, true, state, force)
        end

        if self.numSequencedChangedParts > 0 then
            self:setChangedPartsState(self.sequencedChangedParts, true, state, force)
        end

        if self.numSequencedEffects > 0 then
            self:setEffectsState(self.sequencedEffects, true, state, force)
        end

        if self.numSequencedShaders > 0 then
            self:setShaderState(self.sequencedShaders, true, state, force)
        end

        if self.numSequencedSamples > 0 then
            self:setActiveSamplesState(self.sequencedActiveSamples, true, state, force)
        end
    end
end

function FillTypeConverter:setChangedPartsState(changedParts, isSequenced, state, force)
    for i = 1, #changedParts do
        local part = changedParts[i]
        local values

        if self:getPartStateIsActive(state, isSequenced, part, force) then
            if not part.active then
                part.active = true
                values = part.endValues
            end
        else
            if part.active then
                part.active = false
                values = part.startValues
            end
        end

        if values ~= nil then
            if values.translation ~= nil then
                setTranslation(part.node, values.translation[1], values.translation[2], values.translation[3])
            end

            if values.rotation ~= nil then
                setRotation(part.node, values.rotation[1], values.rotation[2], values.rotation[3])
            end

            if values.scale ~= nil then
                setScale(part.node, values.scale[1], values.scale[2], values.scale[3])
            end

            if values.visibility ~= nil then
                setVisibility(part.node, values.visibility)
            end
        end
    end
end

function FillTypeConverter:setAnimationNodesState(animationNodes, isSequenced, state, force)
    for i = 1, #animationNodes do
        local animationNodeGroup = animationNodes[i]

        if self:getPartStateIsActive(state, isSequenced, animationNodeGroup, force) then
            if not animationNodeGroup.active then
                animationNodeGroup.active = true
                g_animationManager:startAnimations(animationNodeGroup.nodes)
            end
        else
            if animationNodeGroup.active then
                animationNodeGroup.active = false
                g_animationManager:stopAnimations(animationNodeGroup.nodes)
            end
        end
    end
end

function FillTypeConverter:setAnimationsState(animations, isSequenced, state, force)
    for i = 1, #animations do
        local clip = animations[i]

        if self:getPartStateIsActive(state, isSequenced, clip, force) then
            if not clip.active then
                clip.active = true

                enableAnimTrack(clip.characterSet, 0)
                setAnimTrackSpeedScale(clip.characterSet, 0, clip.speedScale)

                if not clip.loop then
                    local animTime = math.max(getAnimTrackTime(clip.characterSet, 0), 0.0)
                    setAnimTrackTime(clip.characterSet, 0, animTime)
                end
            end
        else
            if clip.active then
                clip.active = false

                if clip.loop then
                    setAnimTrackTime(clip.characterSet, 0, 0.0, true)
                    disableAnimTrack(clip.characterSet, 0)
                else
                    local animTime = math.min(getAnimTrackTime(clip.characterSet, 0), clip.duration)
                    enableAnimTrack(clip.characterSet, 0)
                    setAnimTrackTime(clip.characterSet, 0, animTime)
                    setAnimTrackSpeedScale(clip.characterSet, 0, -clip.speedScale)
                end
            end
        end
    end
end

function FillTypeConverter:setEffectsState(effectsGroup, isSequenced, state, force)
    for i = 1, #effectsGroup do
        local effects = effectsGroup[i]

        if self:getPartStateIsActive(state, isSequenced, effects, force) then
            if effects.fillTypesCycle > 0 then
                effects.fillTypesCycle = effects.fillTypesCycle + 1

                if effects.fillTypesCycle > self.numInputs then
                    effects.fillTypesCycle = 1
                end

                effects.fillType = self.inputs[effects.fillTypesCycle].lastFillType
            end

            if effects.isParticalSystem then
                ParticleUtil.setEmittingState(effects.effects, true)
            else
                g_effectManager:setFillType(effects.effects, effects.fillType)
                g_effectManager:startEffects(effects.effects)
            end
        else
            if effects.isParticalSystem then
                ParticleUtil.setEmittingState(effects.effects, false)
            else
                g_effectManager:stopEffects(effects.effects)
            end
        end
    end
end

function FillTypeConverter:setShaderState(shaderGroup, isSequenced, state, force)
    for i = 1, #shaderGroup do
        local shader = shaderGroup[i]

        if self:getPartStateIsActive(state, isSequenced, shader, force) then
            setShaderParameter(shader.node, shader.parameter, shader.endValues[1], shader.endValues[2], shader.endValues[3], shader.endValues[4], false)
        else
            setShaderParameter(shader.node, shader.parameter, shader.startValues[1], shader.startValues[2], shader.startValues[3], shader.startValues[4], false)
        end
    end
end

function FillTypeConverter:setActiveSamplesState(samples, isSequenced, state, force)
    local startSample
    if self.engineSamples ~= nil and not isSequenced then
        startSample = self.engineSamples.start
    end

    for _, sample in pairs (samples) do
        if self:getPartStateIsActive(state, isSequenced, sample, force) then
            -- Only play after 'start' sample is finished if feature is used.
            g_soundManager:playSample(sample, sample.loops or 0, startSample)
        else
            g_soundManager:stopSample(sample)
        end
    end
end

function FillTypeConverter:getPartStateIsActive(state, isSequenced, part, force)
    if state == nil then
        state = false
        force = true
    end

    if isSequenced and part.invert and not force then
        state = not state
    end

    if state and part.requiredOutput ~= nil then
        return part.requiredOutput.fillLevel > 0
    end

    return state
end

function FillTypeConverter:getFillLevel(fillTypeIndex, isInput)
    if isInput then
        if self.fillTypeToInput[fillTypeIndex] ~= nil then
            return self.fillTypeToInput[fillTypeIndex].fillLevel
        end
    else
        if self.fillTypeToOutput[fillTypeIndex] ~= nil then
            return self.fillTypeToOutput[fillTypeIndex].fillLevel
        end
    end

    return 0
end

function FillTypeConverter:getCapacity(fillTypeIndex, isInput)
    if isInput then
        if self.fillTypeToInput[fillTypeIndex] ~= nil then
            return self.fillTypeToInput[fillTypeIndex].capacity
        end
    else
        if self.fillTypeToOutput[fillTypeIndex] ~= nil then
            return self.fillTypeToOutput[fillTypeIndex].capacity
        end
    end

    return 0
end

function FillTypeConverter:getIsFillTypeSupported(fillTypeIndex, isInput)
    if isInput then
        return self.fillTypeToInput[fillTypeIndex] ~= nil
    else
        return self.fillTypeToOutput[fillTypeIndex] ~= nil
    end

    return false
end

function FillTypeConverter:getIsManualStartStop()
    return self.manualStartInputAction ~= nil
end

function FillTypeConverter:getIsConverterEnabled()
    if self.manualStartInputAction ~= nil and self.isEnabled then
        return self.partsState
    end

    return self.isEnabled
end

function FillTypeConverter:onSeasonLengthChanged()
    local displays = self.perHourDisplays
    if displays ~= nil then
        local lengthFactor, _ = self:getIntervalLengthFactor()
        for i = 1, #displays do
            I3DUtil.setNumberShaderByValue(displays[i].baseNode, displays[i].owner.perHour / lengthFactor, 0, true)
        end
    end
end

function FillTypeConverter:collectPickObjects(node)
    local foundNode = false

    for _, unloadTrigger in ipairs(self.unloadTriggers) do
        if node == unloadTrigger.exactFillRootNode then
            foundNode = true
            break
        end
    end

    if not foundNode then
        for _, loadTrigger in ipairs(self.loadTriggers) do
            if node == loadTrigger.triggerNode then
                foundNode = true
                break
            end
        end
    end

    if not foundNode then
        FillTypeConverter:superClass().collectPickObjects(self, node)
    end
end

function FillTypeConverter:farmDestroyed(farmId)
    if self:getOwnerFarmId() == farmId then
        for i = 1, self.numInputs do
            local input = self.inputs[i]
            self:setFillLevel(0.0, input.lastFillType, input, false, false)
        end

        for i = 1, self.numOutputs do
            local output = self.outputs[i]
            self:setFillLevel(0.0, output.lastFillType, output, false, false)
        end

        self:setPartsState(false, true, false)
    end
end

function FillTypeConverter:getDisplayColour(numberColorStr)
    if numberColorStr == nil then
        return nil
    end

    local numberColorUpper = numberColorStr:upper()
    if FillTypeConverter.DISPLAY_COLOURS[numberColorUpper] ~= nil then
        return FillTypeConverter.DISPLAY_COLOURS[numberColorUpper]
    end

    local brandColor = g_brandColorManager:getBrandColorByName(numberColorStr)
    if brandColor ~= nil then
        return brandColor
    end

    local vector = StringUtil.getVectorNFromString(numberColorStr, 4)
    if vector ~= nil then
        return vector
    end
end

function FillTypeConverter:getFreeCapacity(fillTypeIndex, farmId, isOutput)
    if not isOutput then
        local input = self.fillTypeToInput[fillTypeIndex]
        if input ~= nil then
            local adjustedFillLevel = self:getAdjustedInputFillLevel(input)
            return input.capacity - adjustedFillLevel
        end
    else
        if self.fillTypeToOutput[fillTypeIndex] ~= nil then
            return self.fillTypeToOutput[fillTypeIndex].capacity - self.fillTypeToOutput[fillTypeIndex].fillLevel
        end
    end

    return 0
end

function FillTypeConverter:getAdjustedInputFillLevel(input)
    local fillLevel = input.fillLevel
    if input.combinedCapacity and self.outputs[input.inputId] ~= nil then
        fillLevel = input.fillLevel + self.outputs[input.inputId].fillLevel
    end

    return fillLevel
end

function FillTypeConverter:getIsToolTypeAllowed(fillTypeIndex, farmId)
    return true
end

function FillTypeConverter:getIsFillTypeAllowed(fillType, farmId)
    return self.fillTypeToInput[fillType] ~= nil
end

function FillTypeConverter:addFillLevelFromTool(farmId, deltaFillLevel, fillType, fillInfo, toolType)
    assert(deltaFillLevel >= 0)

    local movedFillLevel = 0
    if g_currentMission.accessHandler:canFarmAccess(farmId, self) and self:getIsFillTypeAllowed(fillType, farmId) then
        local input = self.fillTypeToInput[fillType]

        local adjustedFillLevel = self:getAdjustedInputFillLevel(input)
        local space = input.capacity - adjustedFillLevel

        if space > 0 then
            local deltaToAdd = deltaFillLevel
            if deltaToAdd > space then
                deltaToAdd = space
            end

            local oldFillLevel = input.fillLevel
            self:setFillLevel(oldFillLevel + deltaToAdd, fillType, input, true, true)
            movedFillLevel = movedFillLevel + (input.fillLevel - oldFillLevel)
        end

        if movedFillLevel >= deltaFillLevel - 0.001 then
            return deltaFillLevel
        end
    end

    return movedFillLevel
end

function FillTypeConverter:getIsFillAllowedToFarm(farmId)
    if g_currentMission.accessHandler:canFarmAccess(farmId, self) then
        return true
    end

    return false
end

function FillTypeConverter:getAllFillLevels(farmId, isInput, getCapacities)
    local fillLevels = {}
    local capacity = 0

    if g_currentMission.accessHandler:canFarmAccess(farmId, self) then
        if not isInput then
            for fillType, output in pairs(self.fillTypeToOutput) do
                if not output.hasPalletSpawner then
                    fillLevels[fillType] = output.fillLevel or 0

                    if getCapacities == true then
                        capacity[fillType] = output.capacity or 0
                    end
                end
            end
        else
            for fillType, input in pairs(self.fillTypeToInput) do
                fillLevels[fillType] = input.fillLevel or 0

                if getCapacities == true then
                    capacity[fillType] = input.capacity or 0
                end
            end
        end
    end

    return fillLevels, capacity
end

function FillTypeConverter:addFillLevelToFillableObject(fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)
    if fillableObject == nil or fillTypeIndex == FillType.UNKNOWN or fillDelta == 0 or toolType == nil then
        return 0
    end

    local farmId = fillableObject:getOwnerFarmId()
    if fillableObject:isa(Vehicle) then
        farmId = fillableObject:getActiveFarm()
    end

    local availableFillLevel = 0
    local output = self.fillTypeToOutput[fillTypeIndex]
    local canFarmAccess = g_currentMission.accessHandler:canFarmAccess(farmId, self)

    if canFarmAccess and output ~= nil then
        availableFillLevel = output.fillLevel or 0
    end

    fillDelta = math.min(fillDelta, availableFillLevel)
    if fillDelta == 0 then
        return 0
    end

    local usedFillLevel = fillableObject:addFillUnitFillLevel(farmId, fillUnitIndex, fillDelta, fillTypeIndex, toolType, fillInfo)
    local appliedFillLevel = usedFillLevel

    local oldFillLevel = output.fillLevel
    if oldFillLevel > 0 then
        self:setFillLevel(oldFillLevel - usedFillLevel, fillTypeIndex, output, true, true)
    end

    usedFillLevel = usedFillLevel - (oldFillLevel - output.fillLevel)
    if usedFillLevel < 0.0001 then
        usedFillLevel = 0
    end

    fillDelta = appliedFillLevel - usedFillLevel

    return fillDelta
end

function FillTypeConverter:getProvidedFillTypes()
    return self.providedFillTypes
end

function FillTypeConverter:getActiveWarningMessage()
    for _, output in pairs (self.outputs) do
        if output.fillLevel >= output.capacity then
            if output.hasPalletSpawner then
                local fillTypeTitle = output.warningFillTypeTitle or "N/A"
                return string.format(g_i18n:getText("ingameNotification_palletSpawnerBlocked"), fillTypeTitle, self.stationName)
            else
                return string.format(self.outputFullWarning, output.displayName)
            end
        end
    end

    for _, input in pairs (self.inputs) do
        if input.fillLevel <= 0 then
            return string.format(self.inputEmptyWarning, input.displayName)
        end
    end

    return ""
end

function FillTypeConverter:woodTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    if self.isServer then
        if onEnter and otherId ~= 0 then
            local woodTrigger = self.triggerIdToTrigger[triggerId]
            local input = self.fillTypeToInput[FillType.WOODCHIPS]

            if woodTrigger ~= nil and input ~= nil then
                local splitTypeIndex = getSplitType(otherId)
                local splitType = g_splitTypeManager.typesByIndex[splitTypeIndex]

                if splitType ~= nil and splitType.woodChipsPerLiter > 0 then
                    local sizeX, sizeY, sizeZ, _, numAttachments = getSplitShapeStats(otherId)
                    local volume = getVolume(otherId) * 1000
                    if sizeX ~= nil and volume > 0 then
                        local fillDelta = volume * splitType.woodChipsPerLiter

                        if fillDelta > 0 and (input.capacity - input.fillLevel) >= (fillDelta * 0.5) then
                            if math.max(sizeX, math.max(sizeY, sizeZ)) <= woodTrigger.maxLength then
                                if not woodTrigger.limitAttachments or (woodTrigger.limitAttachments and numAttachments <= 3) then
                                    self:setFillLevel(input.fillLevel + fillDelta, FillType.WOODCHIPS, input, true, true)
                                    delete(otherId)
                                else
                                    g_currentMission:showBlinkingWarning(string.format("First remove all attachments!", text)) -- SP / Server Only
                                end
                            else
                                local text = string.format(g_i18n:getText("warning_notAcceptedHere"), "( SIZE )")
                                g_currentMission:showBlinkingWarning(string.format("%s  Max: %d meters", text, woodTrigger.maxLength)) -- SP / Server Only
                            end
                        end
                    end
                end
            end
        end
    end
end

function FillTypeConverter:palletSpawnerTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    if self.isServer and (onEnter or onLeave) then
        local palletSpawners = self.triggerIdToTrigger[triggerId]

        if palletSpawners ~= nil then
            local object = g_currentMission:getNodeObject(otherId)
            if object ~= nil and object.isa ~= nil and object:isa(Vehicle) then

                local storeItem = g_storeManager:getItemByXMLFilename(object.configFileName:lower())
                if object.spec_fillUnit ~= nil and object.typeName:lower():find("pallet") or (storeItem ~= nil and storeItem.categoryName == "pallets") then
                    if onEnter then
                        if palletSpawners.objects[object] == nil then
                            palletSpawners.objects[object] = object
                            palletSpawners.numObjects = palletSpawners.numObjects + 1

                            if palletSpawners.currentPallet == nil then
                                palletSpawners.currentPallet = object
                                palletSpawners.currentNode = nil
                            end
                        end
                    else
                        if palletSpawners.objects[object] ~= nil then
                            palletSpawners.objects[object] = nil
                            palletSpawners.numObjects = palletSpawners.numObjects - 1

                            if palletSpawners.currentPallet == object then
                                palletSpawners.currentPallet = nil
                                palletSpawners.currentNode = nil
                            end
                        end
                    end

                    if palletSpawners.ignorePallet then
                        palletSpawners.ignorePallet = false
                    else
                        local fillLevel, _, _, _ = self:getPalletsFillLevels(palletSpawners)
                        self:setFillLevel(fillLevel, palletSpawners.fillTypeIndex, palletSpawners.owner, true, true)
                    end
                end
            end
        end
    end
end

function FillTypeConverter:getPalletsFillLevels(palletSpawners)
    local nextPallet, freeArea
    local fillLevel, capacity, nonFillLevel = 0, 0, 0

    if palletSpawners ~= nil then
        local usedPallets = {}

        for i = 1, palletSpawners.numSpawners do
            local spawner = palletSpawners.spawners[i]
            self:resetSpawner(spawner.node)

            local x, y, z = getWorldTranslation(spawner.node)
            local rx, ry, rz = getWorldRotation(spawner.node)

            local numShapes = overlapBox(x, y, z, rx, ry, rz, palletSpawners.sizeWidth * 0.5, 10, palletSpawners.sizeLength * 0.5, "spawnNodeCallback", self, nil, true, false, true)
            if self.spawnerPallet ~= nil then
                if not usedPallets[self.spawnerPallet] and self.spawnerPallet:getFillUnitFillType(palletSpawners.fillUnitIndex) == palletSpawners.fillTypeIndex then
                    usedPallets[self.spawnerPallet] = true

                    local palletCapacity = self.spawnerPallet:getFillUnitCapacity(palletSpawners.fillUnitIndex)
                    local palletFillLevel = self.spawnerPallet:getFillUnitFillLevel(palletSpawners.fillUnitIndex)

                    if (palletCapacity - palletFillLevel) > 0 then
                        if nextPallet == nil then
                            nextPallet = self.spawnerPallet
                        end
                    else
                        if self.spawnerPallet == palletSpawners.currentPallet then
                            palletSpawners.currentNode = nil
                            palletSpawners.currentPallet = nil
                        end
                    end

                    fillLevel = fillLevel + palletFillLevel
                    capacity = capacity + palletCapacity
                else
                    nonFillLevel = nonFillLevel + (capacity * palletSpawners.numSpawners)
                end
            else
                if self.spawnerObject == nil then
                    if freeArea == nil then
                        freeArea = spawner.node
                    end
                else
                    nonFillLevel = nonFillLevel + (capacity * palletSpawners.numSpawners)
                end
            end
        end

        usedPallets = nil
        self:resetSpawner(nil)
    end

    return fillLevel, capacity, nextPallet, freeArea, nonFillLevel
end

function FillTypeConverter:getNextPalletOrFreeArea(palletSpawners)
    local nextPallet, nextPalletArea, freeArea
    local x, y, z, rotY = 0, 0, 0, 0

    if palletSpawners ~= nil then
        for i = 1, palletSpawners.numSpawners do
            local spawner = palletSpawners.spawners[i]
            self:resetSpawner(spawner.node)

            x, y, z = getWorldTranslation(spawner.node)
            local rx, ry, rz = getWorldRotation(spawner.node)

            local numShapes = overlapBox(x, y, z, rx, ry, rz, palletSpawners.sizeWidth * 0.5, 10, palletSpawners.sizeLength * 0.5, "spawnNodeCallback", self, nil, true, false, true)
            if self.spawnerPallet ~= nil then
                if self.spawnerPallet:getFillUnitFillType(palletSpawners.fillUnitIndex) == palletSpawners.fillTypeIndex then
                    if self.spawnerPallet:getFillUnitFreeCapacity(palletSpawners.fillUnitIndex) > 0 then
                        nextPallet = self.spawnerPallet
                        nextPalletArea = spawner.node
                    end
                end
            elseif self.spawnerObject == nil then
                local dx, _, dz = mathEulerRotateVector(rx, ry, rz, 0, 0, 1)
                rotY = MathUtil.getYRotationFromDirection(dx, dz)

                local terrainHeight = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 300, z) + 0.5
                y = math.max(terrainHeight, y)

                freeArea = spawner.node
            end

            if (nextPallet ~= nil) or (freeArea ~= nil) then
                break
            end
        end

        self:resetSpawner(nil)
    end

    return nextPallet, nextPalletArea, freeArea, x, y, z, rotY
end

function FillTypeConverter:updatePalletFillLevel(palletSpawners, fillDelta)
    if palletSpawners ~= nil then
        palletSpawners.fillDelta = palletSpawners.fillDelta + fillDelta

        if palletSpawners.configFilename ~= "" and palletSpawners.currentPallet == nil and palletSpawners.fillDelta > HusbandryModulePallets.fillLevelThresholdForDeletion then
            local nextPallet, nextPalletArea, freeArea, x, y, z, rotY = self:getNextPalletOrFreeArea(palletSpawners)

            if nextPallet == nil then
                if freeArea ~= nil then
                    palletSpawners.ignorePallet = true
                    palletSpawners.currentNode = freeArea

                    palletSpawners.currentPallet = g_currentMission:loadVehicle(palletSpawners.configFilename, x, y, z, 0, rotY, true, 0, Vehicle.PROPERTY_STATE_OWNED, self:getOwnerFarmId(), nil, nil)
                else
                    palletSpawners.currentPallet = nil
                    palletSpawners.currentNode = nil
                end
            else
                palletSpawners.currentPallet = nextPallet
                palletSpawners.currentNode = nextPalletArea
            end
        end

        if palletSpawners.currentPallet ~= nil then
            local fillLevel, _, _, _ = self:getPalletsFillLevels(palletSpawners)
            local fillDeltaAdded = palletSpawners.currentPallet:addFillUnitFillLevel(self:getOwnerFarmId(), palletSpawners.fillUnitIndex, palletSpawners.fillDelta, palletSpawners.fillTypeIndex, ToolType.UNDEFINED)

            palletSpawners.fillDelta = palletSpawners.fillDelta - fillDeltaAdded
            fillLevel = fillLevel + fillDeltaAdded

            if palletSpawners.fillDelta > HusbandryModulePallets.fillLevelThresholdForDeletion then
                self.extraPalletDelta = true
            end

            return fillLevel
        elseif self.showFillLevelWarnings and palletSpawners.fillDelta > HusbandryModulePallets.fillLevelThresholdForDeletion then
            if g_dedicatedServerInfo == nil and palletSpawners.owner ~= nil then
                local fillTypeTitle = palletSpawners.owner.warningFillTypeTitle or "N/A"
                local message = string.format(g_i18n:getText("ingameNotification_palletSpawnerBlocked"), fillTypeTitle, self.stationName)
                g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
            end
        end
    end

    return nil
end

function FillTypeConverter:resetSpawner(node)
    self.spawnerObject = nil
    self.spawnerPallet = nil
    self.currentSpawner = node
end

function FillTypeConverter:resetCurrentPallet(palletSpawners, nextPallet)
    if palletSpawners.currentPallet ~= nil then
        local currentPalletValid = false

        if entityExists(palletSpawners.currentPallet.rootNode) and palletSpawners.currentNode ~= nil then
            local x, _, z = localToLocal(palletSpawners.currentPallet.rootNode, palletSpawners.currentNode, 0, 0, 0)
            if (x < palletSpawners.sizeWidth) and (z < palletSpawners.sizeLength) then
                currentPalletValid = true
            end
        end

        if not currentPalletValid then
            palletSpawners.currentPallet = nextPallet

            if palletSpawners.objects[palletSpawners.currentPallet] ~= nil then
                palletSpawners.objects[palletSpawners.currentPallet] = nil
                palletSpawners.numObjects = palletSpawners.numObjects - 1
            end
        end
    else
        palletSpawners.currentPallet = nextPallet
    end
end

function FillTypeConverter:spawnNodeCallback(transformId)
    if transformId ~= nil and transformId ~= self.currentSpawner and transformId ~= g_currentMission.terrainRootNode then
        local object = g_currentMission:getNodeObject(transformId)

        if object ~= nil and object.isa ~= nil and object:isa(Vehicle) then
            if object.spec_fillUnit ~= nil and object.typeName:lower():find("pallet") then
                self.spawnerPallet = object
            else
                self.spawnerObject = object
            end
        elseif g_currentMission.players[transformId] ~= nil or getHasClassId(transformId, ClassIds.MESH_SPLIT_SHAPE) then
            self.spawnerObject = transformId
        end
    end

    return
end

function FillTypeConverter:interactionTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    if onEnter or onLeave then
        if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
            if onEnter then
                if g_currentMission.accessHandler:canFarmAccessOtherId(g_currentMission:getFarmId(), self:getOwnerFarmId()) then
                    if not self.playerInRange then
                        self.playerInRange = true
                        g_currentMission:addActivatableObject(self)
                        self:addRemoveActionEvents(true)
                    end
                end
            else
                if self.playerInRange then
                    self.playerInRange = false
                    g_currentMission:removeActivatableObject(self)
                    self:addRemoveActionEvents(false)
                end
            end

            if self.fillTypeConverterUI ~= nil then
                self.fillTypeConverterUI.stationNameTimer = 200
            end

            self:raiseActive()
        end
    end
end

function FillTypeConverter:onActivateObject()
    self.statusUiEnabled = not self.statusUiEnabled
    self:raiseActive()
end

function FillTypeConverter:getIsActivatable()
    local stateText = "action_turnOnOBJECT"
    if self.statusUiEnabled then
        stateText = "action_turnOffOBJECT"
    end

    self.activateText = string.format(g_i18n:getText(stateText), self.statusUiButtonText)

    if g_currentMission.controlPlayer and (self:getOwnerFarmId() == 0 or g_currentMission:getFarmId() == self:getOwnerFarmId()) then
        return true
    end

    if self.fillTypeConverterUI ~= nil then
        self.fillTypeConverterUI.stationNameTimer = 200
    end

    self.playerInRange = false
    g_currentMission:removeActivatableObject(self)
    self:addRemoveActionEvents(false)

    return false
end

function FillTypeConverter:drawActivate()
    if self.statusUiEnabled and self.fillTypeConverterUI ~= nil then
        self.fillTypeConverterUI:drawOverlays()
    end

    if self.manualStartInputEventId ~= nil then
        if self.isEnabled then
            if self.partsState then
                g_inputBinding:setActionEventText(self.manualStartInputEventId, string.format(g_i18n:getText("action_turnOffOBJECT"), self.stationName))
            else
                g_inputBinding:setActionEventText(self.manualStartInputEventId, string.format(g_i18n:getText("action_turnOnOBJECT"), self.stationName))
            end
        end

        g_inputBinding:setActionEventActive(self.manualStartInputEventId, self.isEnabled)
        g_inputBinding:setActionEventTextVisibility(self.manualStartInputEventId, self.isEnabled)
    end
end

function FillTypeConverter:shouldRemoveActivatable()
    return false
end

---------------
-- Status UI --
---------------

FillTypeConverterStatusUI = {}
local FillTypeConverterStatusUI_mt = Class(FillTypeConverterStatusUI)

function FillTypeConverterStatusUI:new(owner, isEnabled)
    local slots = 0
    if owner ~= nil then
        slots = math.min(math.max(owner.numInputs, owner.numOutputs), 8)
    end

    if slots < 1 then
        return nil
    end

    local self = {}
    setmetatable(self, FillTypeConverterStatusUI_mt)

    local uiScale = g_gameSettings:getValue("uiScale") or 1.0
    local hudAtlasPath = g_baseHUDFilename
    local uiAtlasPath = g_baseUIFilename

    self.owner = owner
    self.uiScale = uiScale
    self.isEnabled = isEnabled
    self.stationNameTimer = 200

    self.customEnvironment = owner.customEnvironment
    self.configFileName = owner.configFileName

    self.colourWhite = {1, 1, 1, 1}
    self.colourRed = {0.8069, 0.0097, 0.0097, 1}
    self.colourOrange = {0.991, 0.3865, 0.01, 1}
    self.colourGreen = {0.3763, 0.6038, 0.0782, 1}

    self.overlays = {}

    local fillUVs = getNormalizedUVs(HUDElement.UV.FILL)
    local width, height = self:getScaledNormalizedScreenValues(800, 110)
    local posX, posY = 0.5 - width * 0.5, g_safeFrameOffsetY

    local backgroundOverlay = self:createOverlay(hudAtlasPath, posX, posY, width, height * slots, fillUVs, HUD.COLOR.FRAME_BACKGROUND, true)

    local baseX, baseY = backgroundOverlay.x, backgroundOverlay.y
    local baseWidth, baseHeight = backgroundOverlay.width, backgroundOverlay.height

    _, self.fillTypeTextOffsetY = self:scalePixel(backgroundOverlay, 44, 78, uiScale)
    self.headerTextOffsetX, self.headerTextOffsetY = self:scalePixel(backgroundOverlay, 0, 10, uiScale)
    self.fillLevelTextOffsetX, self.fillLevelTextOffsetY = self:scalePixel(backgroundOverlay, 20, 20, uiScale)
    self.individualFrameWidth, self.individualFrameHeight = self:scalePixel(backgroundOverlay, 400, 110, uiScale)

    self.textWrapWidth, _ = self:scalePixel(backgroundOverlay, 360, 20, uiScale)
    self.headerTextSize = 30 * backgroundOverlay.scaleHeight * g_aspectScaleY / g_referenceScreenHeight * uiScale
    self.fillLevelTextSize = 16 * backgroundOverlay.scaleHeight * g_aspectScaleY / g_referenceScreenHeight * uiScale

    self.headerText = Utils.limitTextToWidth(string.upper(owner.stationName), self.headerTextSize, self.individualFrameWidth * 1.7, false, "...")
    self.headerTextX, self.headerTextY = baseX + self.headerTextOffsetX, baseY + ((self.individualFrameHeight * slots) + self.headerTextOffsetY)

    local refPixelX, refPixelY = 1 / g_referenceScreenWidth, 1 / g_referenceScreenHeight
    local screenPixelX, screenPixelY = 1 / g_screenWidth, 1 / g_screenHeight
    local onePixelX, onePixelY = math.max(refPixelX, screenPixelX), math.max(refPixelY, screenPixelY)

    local frameWidth, frameHeight = self:getScaledNormalizedScreenValues(1, 1)
    local pixelsX, pixelsY = math.ceil(frameWidth / onePixelX), math.ceil(frameHeight / onePixelY)
    frameWidth, frameHeight = pixelsX * onePixelX, pixelsY * onePixelY

    local lineOverlay
    for i = 1, slots do
        self:createOverlay(hudAtlasPath, baseX, baseY + height * i, width, frameHeight, fillUVs, HUDFrameElement.COLOR.FRAME, true)
    end

    self:createOverlay(hudAtlasPath, baseX, baseY + frameHeight, frameWidth, baseHeight - frameHeight, fillUVs, HUDFrameElement.COLOR.FRAME, true)
    self:createOverlay(hudAtlasPath, baseX + (width * 0.5) - (frameWidth * 0.5), baseY + frameHeight, frameWidth, baseHeight - frameHeight, fillUVs, HUDFrameElement.COLOR.FRAME, true)
    self:createOverlay(hudAtlasPath, baseX + width - frameWidth, baseY + frameHeight, frameWidth, baseHeight - frameHeight, fillUVs, HUDFrameElement.COLOR.FRAME, true)

    local _, barHeight = self:getScaledNormalizedScreenValues(0, 4)
    pixelsY = math.ceil(barHeight / onePixelY)
    self:createOverlay(hudAtlasPath, baseX, baseY, width, pixelsY * onePixelY, fillUVs, HUDFrameElement.COLOR.BAR, true)

    local iconWidth, iconHeight = self:getScaledNormalizedScreenValues(48, 48)
    local iconUVs = getNormalizedUVs({2, 98, 44, 44})
    self.iconOverlay = self:createOverlay(hudAtlasPath, baseX + (baseWidth - iconWidth) + self.headerTextOffsetX, baseY + baseHeight, iconWidth, iconHeight, iconUVs, self.colourWhite, true)

    local frameX, frameY = self:getScaledNormalizedScreenValues(0, 0)
    local posX, posY = baseX + frameX, baseY + frameY
    local barWidth, barHeight = self:getScaledNormalizedScreenValues(360, 20)
    local barX, barY = self:getScaledNormalizedScreenValues(20, 54)

    self.inputStatusBars = {}
    self.inputTextPositions = {}
    for i = 1, owner.numInputs do
        local barPosX, barPosY = posX + barX, posY + (height * i) - barY
        self:createOverlay(hudAtlasPath, barPosX, barPosY, barWidth, barHeight, fillUVs, FillLevelsDisplay.COLOR.BAR_BACKGROUND, true)

        local statusBar = self:createOverlay(hudAtlasPath, barPosX, barPosY, barWidth, barHeight, fillUVs, self.colourRed, false)
        statusBar:setScale(1.0, 1.0)
        self.inputStatusBars[i] = statusBar

        local nameX, nameY = baseX + self.fillLevelTextOffsetX, baseY + (self.individualFrameHeight * i) - self.fillLevelTextOffsetY
        local fillLevelX, fillLevelY = baseX + (width * 0.5) - self.fillLevelTextOffsetX, nameY

        local fillTypeTitlesX, fillTypeTitlesY = nameX, baseY + (self.individualFrameHeight * i) - self.fillTypeTextOffsetY

        local fillTypeTitles = owner.inputs[i].sortedAndConcatedTitles
        local wrap = getTextWidth(self.fillLevelTextSize, fillTypeTitles) >= self.textWrapWidth

        if wrap then
            local lastWrapCharacter = getTextLineLength(self.fillLevelTextSize, fillTypeTitles, self.textWrapWidth)
            local textLine1 = utf8Substr(fillTypeTitles, 0, lastWrapCharacter)
            local textLine1End = string.find(textLine1, "%s(%S+)$")
            textLine1 = string.sub(fillTypeTitles, 1, textLine1End - 1)

            local textLine2 = string.sub(fillTypeTitles, textLine1End + 1)
            textLine2, _, _ = Utils.limitTextToWidth(textLine2, self.fillLevelTextSize, self.textWrapWidth, false, "...")

            fillTypeTitles = string.format("%s %s", textLine1, textLine2)
        end

        self.inputTextPositions[i] = {
            wrap = wrap,
            nameX = nameX,
            nameY = nameY,
            fillLevelX = fillLevelX,
            fillLevelY = fillLevelY,
            fillTypeTitles = fillTypeTitles,
            fillTypeTitlesX = fillTypeTitlesX,
            fillTypeTitlesY = fillTypeTitlesY
        }
    end

    self.outputStatusBars = {}
    self.outputTextPositions = {}
    for i = 1, owner.numOutputs do
        local barPosX, barPosY = posX + (width * 0.5) + barX, posY + (height * i) - barY
        self:createOverlay(hudAtlasPath, barPosX, barPosY, barWidth, barHeight, fillUVs, FillLevelsDisplay.COLOR.BAR_BACKGROUND, true)

        local statusBar = self:createOverlay(hudAtlasPath, barPosX, barPosY, barWidth, barHeight, fillUVs, self.colourRed, false)
        statusBar:setScale(1.0, 1.0)
        self.outputStatusBars[i] = statusBar

        local nameX, nameY = baseX + (width * 0.5) + self.fillLevelTextOffsetX, baseY + (self.individualFrameHeight * i) - self.fillLevelTextOffsetY
        local fillLevelX, fillLevelY = baseX + width - self.fillLevelTextOffsetX, nameY
        local fillTypeTitlesX, fillTypeTitlesY = nameX, baseY + (self.individualFrameHeight * i) - self.fillTypeTextOffsetY

        self.outputTextPositions[i] = {
            wrap = false,
            nameX = nameX,
            nameY = nameY,
            fillLevelX = fillLevelX,
            fillLevelY = fillLevelY,
            fillTypeTitles = owner.outputs[i].fillTypeTitle,
            fillTypeTitlesX = fillTypeTitlesX,
            fillTypeTitlesY = fillTypeTitlesY
        }
    end

    return self
end

function FillTypeConverterStatusUI:delete()
    self.isEnabled = false

    if self.overlays ~= nil then
        for i = 1, #self.overlays do
            self.overlays[i]:delete()
        end
        self.overlays = nil
    end

    if self.inputStatusBars ~= nil then
        for i = 1, #self.inputStatusBars do
            self.inputStatusBars[i]:delete()
        end
        self.inputStatusBars = nil
    end

    if self.outputStatusBars ~= nil then
        for i = 1, #self.outputStatusBars do
            self.outputStatusBars[i]:delete()
        end
        self.outputStatusBars = nil
    end
end

function FillTypeConverterStatusUI:drawOverlays()
    if self.isEnabled and self.overlays ~= nil then
        for i = 1, #self.overlays do
            self.overlays[i]:render()
        end

        setTextBold(true)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(self.colourWhite[1], self.colourWhite[2], self.colourWhite[3], self.colourWhite[4])

        if self.owner.isEnabled or (self.owner.openingHours == nil or self.owner.openingHours.closedText == nil) then
            renderText(self.headerTextX, self.headerTextY, self.headerTextSize, self.headerText)
        else
            self.stationNameTimer = self.stationNameTimer - 1
            if self.stationNameTimer < 0 then
                renderText(self.headerTextX, self.headerTextY, self.headerTextSize, self.owner.openingHours.closedText)
            else
                renderText(self.headerTextX, self.headerTextY, self.headerTextSize, self.headerText)
            end
        end

        setTextBold(false)

        for i = 1, self.owner.numInputs do
            self:drawBarAndText(self.owner.inputs[i], self.inputStatusBars[i], self.inputTextPositions[i])
        end

        for i = 1, self.owner.numOutputs do
            self:drawBarAndText(self.owner.outputs[i], self.outputStatusBars[i], self.outputTextPositions[i])
        end

        if self.owner.partsState then
            self.iconOverlay:setColor(self.colourGreen[1], self.colourGreen[2], self.colourGreen[3], self.colourGreen[4])
        else
            if self.owner.isEnabled then
                self.iconOverlay:setColor(self.colourWhite[1], self.colourWhite[2], self.colourWhite[3], self.colourWhite[4])
            else
                self.iconOverlay:setColor(self.colourRed[1], self.colourRed[2], self.colourRed[3], self.colourRed[4])
            end
        end
    end
end

function FillTypeConverterStatusUI:drawBarAndText(data, statusBar, textPositions)
    local value, fillLevel = 0, 0

    if data.isFillTypes then
        fillLevel = MathUtil.round(data.fillLevel)
    else
        fillLevel = MathUtil.round(math.ceil(data.fillLevel))
    end

    if fillLevel > 0 and data.capacity > 0 then
        value = MathUtil.round(MathUtil.clamp(fillLevel / data.capacity, 0, 1) * 100)
    end

    if statusBar ~= nil then
        if statusBar.value ~= value then
            statusBar:setScale((value / 100), 1.0)

            if value <= 20 then
                statusBar:setColor(self.colourRed[1], self.colourRed[2], self.colourRed[3], self.colourRed[4])
            elseif value <= 60 then
                statusBar:setColor(self.colourOrange[1], self.colourOrange[2], self.colourOrange[3], self.colourOrange[4])
            else
                statusBar:setColor(self.colourGreen[1], self.colourGreen[2], self.colourGreen[3], self.colourGreen[4])
            end

            statusBar.value = value
        end

        statusBar:render()
    end

    if textPositions ~= nil then
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(textPositions.nameX, textPositions.nameY, self.fillLevelTextSize, data.displayName)

        if not textPositions.wrap then
            renderText(textPositions.fillTypeTitlesX, textPositions.fillTypeTitlesY, self.fillLevelTextSize, textPositions.fillTypeTitles)
        else
            setTextWrapWidth(self.textWrapWidth)
            renderText(textPositions.fillTypeTitlesX, textPositions.fillTypeTitlesY, self.fillLevelTextSize, textPositions.fillTypeTitles)
            setTextWrapWidth(0)
        end

        setTextAlignment(RenderText.ALIGN_RIGHT)
        renderText(textPositions.fillLevelX, textPositions.fillLevelY, self.fillLevelTextSize, string.format("%d (%d%%)", fillLevel, value))
    end
end

function FillTypeConverterStatusUI:createOverlay(hudAtlasPath, posX, posY, width, height, uvs, colour, insert)
    if uvs == nil then
        uvs = getNormalizedUVs({8, 8, 1, 1})
    end

    if colour == nil then
        colour = self.colourWhite
    end

    local overlay = Overlay:new(hudAtlasPath, posX, posY, width, height)
    overlay:setUVs(uvs)
    overlay:setColor(colour[1], colour[2], colour[3], colour[4])

    if insert then
        self.overlays[#self.overlays + 1] = overlay
    end

    return overlay
end

function FillTypeConverterStatusUI:scalePixel(overlay, width, height, uiScale)
    if uiScale == nil then
        uiScale = 1
    end

    return width * uiScale * g_aspectScaleX / g_referenceScreenWidth,
        height * uiScale * g_aspectScaleY / g_referenceScreenHeight
end

function FillTypeConverterStatusUI:getScaledNormalizedScreenValues(x, y)
    local normalizedX, normalizedY = getNormalizedScreenValues(x, y)
    return normalizedX * self.uiScale, normalizedY * self.uiScale
end

------------------------------------------------------------------------------------------------------------------------
-- Animal Trigger                                                                                                     --
-- Base Code: https://gdn.giants-software.com/documentation_scripting_fs19.php?version=script&category=67&class=10081 --
------------------------------------------------------------------------------------------------------------------------

FillTypeConverterAnimalTrigger = {}
local FillTypeConverterAnimalTrigger_mt = Class(FillTypeConverterAnimalTrigger, Object)
InitObjectClass(FillTypeConverterAnimalTrigger, "FillTypeConverterAnimalTrigger")

function FillTypeConverterAnimalTrigger:new(isServer, isClient, customEnvironment, configFileName)
    local self = Object:new(isServer, isClient, FillTypeConverterAnimalTrigger_mt)

    self.isActivatableAdded = false
    self.objectActivated = false

    self.triggerNode = nil
    self.loadingVehicle = nil
    self.activatedTarget = nil

    self.animalTypes = {}
    self.numAnimalTypes = 0

    self.requireTradePermission = false

    self.customEnvironment = customEnvironment
    self.configFileName = configFileName

    self.activateText = g_i18n:getText("info_tipSideUnload")

    return self
end

function FillTypeConverterAnimalTrigger:load(rootNode, xmlFile, xmlNode, target)
    self.target = target
    self.rootNode = rootNode

    local triggerNode = I3DUtil.indexToObject(rootNode, getXMLString(xmlFile, xmlNode .. "#triggerNode"))
    if target ~= nil and triggerNode ~= nil then
        self.triggerNode = triggerNode
        addTrigger(self.triggerNode, "triggerCallback", self)

        self.requireTradePermission = Utils.getNoNil(getXMLBool(xmlFile, xmlNode .. "#requireTradePermission"), false)

        local animalTypesString = getXMLString(xmlFile, xmlNode .. "#animalTypes")
        if animalTypesString ~= nil then
            local animalTypes = StringUtil.splitString(" ", animalTypesString)

            for _, animalTypeStr in pairs(animalTypes) do
                local animalType = g_animalManager:getAnimalsByType(animalTypeStr)
                if animalType ~= nil then
                    self.animalTypes[animalType.type] = true
                    self.numAnimalTypes = self.numAnimalTypes + 1
                else
                    if self.configFileName == nil then
                        g_logManager:warning("Invalid animal type '%s' for animalUnloadingTrigger '%s'!", animalTypeStr, getName(triggerNode))
                    else
                        g_logManager:xmlWarning(self.configFileName, "Invalid animal type '%s' given at '%s'.", animalTypeStr, xmlNode)
                    end
                end
            end
        end
    end

    return self.numAnimalTypes > 0
end

function FillTypeConverterAnimalTrigger:delete()
    g_currentMission:removeActivatableObject(self)

    if self.triggerNode ~= nil then
        removeTrigger(self.triggerNode)
        self.triggerNode = nil
    end

    FillTypeConverterAnimalTrigger:superClass().delete(self)
end

function FillTypeConverterAnimalTrigger:triggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if onEnter or onLeave then
        local vehicle = g_currentMission.nodeToObject[otherId]
        if vehicle ~= nil and vehicle.getSupportsAnimalType ~= nil then
            if onEnter then
                self:setLoadingTrailer(vehicle)
            elseif onLeave then
                if vehicle == self.loadingVehicle then
                    self:setLoadingTrailer(nil)
                end

                if self.objectActivated then
                    if vehicle == self.activatedTarget then
                        g_gui:closeAllDialogs()
                        self.objectActivated = false
                    end
                end
            end
        end
    end
end

function FillTypeConverterAnimalTrigger:updateActivatableObject()
    if self.loadingVehicle ~= nil then
        if not self.isActivatableAdded then
            self.isActivatableAdded = true
            g_currentMission:addActivatableObject(self)
        end
    else
        if self.isActivatableAdded and self.loadingVehicle == nil then
            g_currentMission:removeActivatableObject(self)
            self.isActivatableAdded = false
            self.objectActivated = false
        end
    end
end

function FillTypeConverterAnimalTrigger:setLoadingTrailer(loadingVehicle)
    if self.loadingVehicle ~= nil and self.loadingVehicle.setLoadingTrigger ~= nil then
        self.loadingVehicle:setLoadingTrigger(nil)
    end

    self.loadingVehicle = loadingVehicle

    if self.loadingVehicle ~= nil and self.loadingVehicle.setLoadingTrigger ~= nil then
        self.loadingVehicle:setLoadingTrigger(self)
    end

    self:updateActivatableObject()
end

function FillTypeConverterAnimalTrigger:getIsActivatable()
    if g_gui.currentGui == nil and self.target:getOwnerFarmId() == g_currentMission:getFarmId() then
        if not self.requireTradePermission or g_currentMission:getHasPlayerPermission("tradeAnimals") then
            local animals = self.loadingVehicle:getAnimals()
            if animals ~= nil and #animals > 0 then
                if self.loadingVehicle ~= nil and g_currentMission.controlledVehicle then
                    local rootAttacherVehicle = self.loadingVehicle:getRootVehicle()
                    return rootAttacherVehicle == g_currentMission.controlledVehicle
                end
            end
        end
    end

    return false
end

function FillTypeConverterAnimalTrigger:drawActivate()
end

function FillTypeConverterAnimalTrigger:onActivateObject()
    g_currentMission:removeActivatableObject(self)
    self.isActivatableAdded = false

    self.animalsToTransfer = 0
    self.activatedTarget = self.loadingVehicle

    local animals = self.activatedTarget:getAnimals()
    if animals ~= nil and animals[1] ~= nil then
        local subType = animals[1]:getSubType()
        if subType ~= nil then
            if self.animalTypes[subType.type] and self.target:getIsFillTypeAllowed(subType.fillType, nil) then
                local freeCapacity = self.target:getFreeCapacity(subType.fillType, g_currentMission:getFarmId(), false)
                if math.floor(freeCapacity) > 0 then
                    self.animalsToTransfer = math.min(freeCapacity, #animals)
                    g_gui:showYesNoDialog({
                        title = self.target.stationName,
                        text = string.format(g_i18n:getText("animals_unload"), self.animalsToTransfer),
                        callback = self.onConfirmOverload,
                        target = self
                    })

                    self.objectActivated = true
                else
                    local title = ""
                    if subType.fillTypeDesc ~= nil and subType.fillTypeDesc.title ~= nil then
                        title = subType.fillTypeDesc.title
                    else
                        title = g_i18n:getText("category_animals")
                    end

                    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("warning_noMoreFreeCapacity"), title))
                end
            else
                if subType.fillTypeDesc ~= nil and subType.fillTypeDesc.title ~= nil then
                    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("warning_notAcceptedHere"), subType.fillTypeDesc.title))
                else
                    g_currentMission:showBlinkingWarning(g_i18n:getText("animals_invalidAnimalType"))
                end
            end
        end
    end
end

function FillTypeConverterAnimalTrigger:onConfirmOverload(yes)
    if yes then
        if self.animalsToTransfer > 0 then
            if self.isServer then
                self:doAnimalsTransfer(self.animalsToTransfer, self.activatedTarget)
            else
                g_client:getServerConnection():sendEvent(FillTypeConverterAnimalTriggerEvent:new(self, self.animalsToTransfer, self.activatedTarget))
            end
        end
    end

    self.objectActivated = false
    self.animalsToTransfer = 0
end

function FillTypeConverterAnimalTrigger:doAnimalsTransfer(numberToTransfer, loadingVehicle)
    if self.isServer and numberToTransfer > 0 and loadingVehicle ~= nil then
        local animals = loadingVehicle:getAnimals()
        if animals ~= nil and animals[1] ~= nil then
            local subType = animals[1]:getSubType()
            if subType ~= nil then
                local fillType = subType.fillType

                local input = self.target.fillTypeToInput[fillType]
                local freeCapacity = math.floor(self.target:getFreeCapacity(fillType, g_currentMission:getFarmId(), false))

                if input ~= nil and freeCapacity > 0 then
                    local value = math.min(freeCapacity, math.min(numberToTransfer, #animals))

                    local animalsToTransfer = {}
                    for i = 1, value do
                        animalsToTransfer[i] = animals[i]
                    end

                    loadingVehicle:removeAnimals(animalsToTransfer)
                    self.target:setFillLevel(input.fillLevel + value, fillType, input, true, true)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------------------------------------------------
-- Automatic Animated Objects (A MP synced animation plays when a vehicle or player enters trigger.)                    --
-- Super Class: https://gdn.giants-software.com/documentation_scripting_fs19.php?version=script&category=65&class=10321 --
--------------------------------------------------------------------------------------------------------------------------

AutomaticAnimatedObject = {}
local AutomaticAnimatedObject_mt = Class(AutomaticAnimatedObject, AnimatedObject)
InitObjectClass(AutomaticAnimatedObject, "AutomaticAnimatedObject")

function AutomaticAnimatedObject:new(isServer, isClient, customMt)
    local self = AnimatedObject:new(isServer, isClient, customMt or AutomaticAnimatedObject_mt)

    self.nodeId = 0
    self.isMoving = false
    self.wasPressed = false

    self.controls = {active = false}
    self.networkTimeInterpolator = InterpolationTime:new(1.2)
    self.networkAnimTimeInterpolator = InterpolatorValue:new(0)

    self.numPlayersInRange = 0
    self.numVehiclesInRange = 0

    self.playersInRange = {}
    self.vehiclesInRange = {}

    return self
end

function AutomaticAnimatedObject:load(nodeId, xmlFile, key, xmlFilename)
    local modName, baseDirectory = Utils.getModNameAndBaseDirectory(xmlFilename)

    self.baseDirectory = baseDirectory
    self.customEnvironment = modName
    self.nodeId = nodeId
    self.samples = {}

    self.saveId = getXMLString(xmlFile, key .. "#saveId")
    if self.saveId == nil then
        self.saveId = "AutomaticAnimatedObject_" .. getName(nodeId)
    end

    local animKey = key .. ".animation"

    -- This can be controlled using correct collision masks but added anyways.
    self.allowPlayers = Utils.getNoNil(getXMLBool(xmlFile, key .. "#allowPlayers"), true)
    self.allowVehicles = Utils.getNoNil(getXMLBool(xmlFile, key .. "#allowVehicles"), true)

    if self.allowPlayers == false and self.allowVehicles == false then
        self.allowPlayers = true -- Just correct to player only with no warning.
    end

    self.animation = {}
    self.animation.parts = {}
    self.animation.duration = Utils.getNoNil(getXMLFloat(xmlFile, animKey .. "#duration"), 3) * 1000

    if self.animation.duration == 0 then
        self.animation.duration = 1000
    end

    self.animation.time = 0
    self.animation.direction = 0

    local i = 0
    while true do
        local partKey = string.format("%s.part(%d)", animKey, i)
        if not hasXMLProperty(xmlFile, partKey) then
            break
        end

        local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, partKey .. "#node"))
        if node ~= nil then
            local part = {}

            part.node = node
            part.animCurve = AnimCurve:new(linearInterpolatorN)

            local hasFrames = false

            local j = 0
            while true do
                local frameKey = string.format("%s.keyFrame(%d)", partKey, j)
                if not hasXMLProperty(xmlFile, frameKey) then
                    break
                end
                local keyTime = getXMLFloat(xmlFile, frameKey.."#time")
                local keyframe = {self:loadFrameValues(xmlFile, frameKey, node)}
                keyframe.time = keyTime
                part.animCurve:addKeyframe(keyframe)
                hasFrames = true
                j = j + 1
            end
            if hasFrames then
                table.insert(self.animation.parts, part)
            end
        end
        i = i + 1
    end

    local initialTime = Utils.getNoNil(getXMLFloat(xmlFile, animKey.."#initialTime"), 0)*1000
    self:setAnimTime(initialTime / self.animation.duration, true)
    self.isEnabled = true

    local triggerId = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. ".trigger#node"))
    if triggerId ~= nil then
        self.controls.triggerId = triggerId

        addTrigger(self.controls.triggerId, "triggerCallback", self)
        for i = 0, getNumOfChildren(self.controls.triggerId) - 1 do
            addTrigger(getChildAt(self.controls.triggerId, i), "triggerCallback", self)
        end
    end

    if g_client ~= nil then
        local soundsKey = key .. ".sounds"
        self.sampleMoving = g_soundManager:loadSampleFromXML(xmlFile, soundsKey, "moving", self.baseDirectory, self.nodeId, 1, AudioGroup.ENVIRONMENT, nil, nil)
        self.samplePosEnd = g_soundManager:loadSampleFromXML(xmlFile, soundsKey, "posEnd", self.baseDirectory, self.nodeId, 1, AudioGroup.ENVIRONMENT, nil, nil)
        self.sampleNegEnd = g_soundManager:loadSampleFromXML(xmlFile, soundsKey, "negEnd", self.baseDirectory, self.nodeId, 1, AudioGroup.ENVIRONMENT, nil, nil)
    end

    self.animatedObjectDirtyFlag = self:getNextDirtyFlag()

    return true
end

function AutomaticAnimatedObject:triggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    if self.isServer and (onEnter or onLeave) then
        if self.allowPlayers and g_currentMission.players ~= nil and g_currentMission.players[otherId] ~= nil then
            local player = g_currentMission.players[otherId]

            if onEnter then
                if self.ownerFarmId == nil or self.ownerFarmId == AccessHandler.EVERYONE or g_currentMission.accessHandler:canFarmAccessOtherId(player.farmId, self.ownerFarmId) then
                    if self.playersInRange[player] == nil then
                        self.playersInRange[player] = otherId
                        self.numPlayersInRange = self.numPlayersInRange + 1
                    end
                end
            else
                if self.playersInRange[player] ~= nil then
                    self.playersInRange[player] = nil
                    self.numPlayersInRange = math.max(self.numPlayersInRange - 1, 0)
                    self:doCleanUp()
                end
            end
        elseif self.allowVehicles then
            local vehicle = g_currentMission.nodeToObject[otherShapeId]
            if vehicle ~= nil then
                if vehicle.spec_enterable ~= nil or vehicle.spec_attachable ~= nil or vehicle.spec_rideable ~= nil then
                    if onEnter then
                        if self.ownerFarmId == nil or self.ownerFarmId == AccessHandler.EVERYONE or g_currentMission.accessHandler:canFarmAccessOtherId(vehicle:getOwnerFarmId(), self.ownerFarmId) then
                            if self.vehiclesInRange[vehicle] == nil then
                                self.vehiclesInRange[vehicle] = otherShapeId
                                self.numVehiclesInRange = self.numVehiclesInRange + 1
                            end
                        end
                    elseif onLeave then
                        if self.vehiclesInRange[vehicle] ~= nil then
                            self.vehiclesInRange[vehicle] = nil
                            self.numVehiclesInRange = math.max(self.numVehiclesInRange - 1, 0)
                            self:doCleanUp()
                        end
                    end
                end
            end
        end

        if self.numPlayersInRange > 0 or self.numVehiclesInRange > 0 then
            if self.animation.time < 1 then
                self.animation.direction = 1
            end
        else
            if self.animation.time > 0 then
                self.animation.direction = -1
            end
        end

        self:raiseActive()
    end
end

function AutomaticAnimatedObject:doCleanUp()
    if self.numPlayersInRange > 0 then
        for player, otherId in pairs (self.playersInRange) do
            if g_currentMission.players[otherId] == nil then
                self.playersInRange[player] = nil
                self.numPlayersInRange = math.max(self.numPlayersInRange - 1, 0)
            end
        end
    end

    if self.numVehiclesInRange > 0 then
        for vehicle, otherShapeId in pairs (self.vehiclesInRange) do
            if g_currentMission.nodeToObject[otherShapeId] == nil then
                self.vehiclesInRange[vehicle] = nil
                self.numVehiclesInRange = math.max(self.numVehiclesInRange - 1, 0)
            end
        end
    end
end

---------------
-- MP Events --
---------------

FillTypeConverterStartStopEvent = {}
FillTypeConverterStartStopEvent_mt = Class(FillTypeConverterStartStopEvent, Event)
InitEventClass(FillTypeConverterStartStopEvent, "FillTypeConverterStartStopEvent")

function FillTypeConverterStartStopEvent:emptyNew()
    local self = Event:new(FillTypeConverterStartStopEvent_mt)
    return self
end

function FillTypeConverterStartStopEvent:new(object, stateIndex)
    local self = FillTypeConverterStartStopEvent:emptyNew()

    self.object = object
    self.stateIndex = MathUtil.clamp(stateIndex, -127, 127)

    return self
end

function FillTypeConverterStartStopEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.stateIndex = streamReadInt8(streamId)

    self:run(connection)
end

function FillTypeConverterStartStopEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteInt8(streamId, self.stateIndex)
end

function FillTypeConverterStartStopEvent:run(connection)
    if self.object ~= nil then
        if not connection:getIsServer() then
            local setActive = not self.object.partsState

            if setActive then
                local active, stateIndex = self.object:serverStartPartsCheck(false, true)

                if active then
                    self.object:setPartsState(true, true, true)
                else
                    self.stateIndex = stateIndex or 0
                    connection:sendEvent(FillTypeConverterStartStopEvent:new(self.object, self.stateIndex))
                end
            else
                self.object:setPartsState(false, true, true)
            end
        else
            if self.stateIndex > 0 then
                g_currentMission:showBlinkingWarning(g_i18n:getText("warning_actionNotAllowedNow"))
            end
        end
    end
end

FillTypeConverterStateEvent = {}
FillTypeConverterStateEvent_mt = Class(FillTypeConverterStateEvent, Event)
InitEventClass(FillTypeConverterStateEvent, "FillTypeConverterStateEvent")

function FillTypeConverterStateEvent:emptyNew()
    local self = Event:new(FillTypeConverterStateEvent_mt)
    return self
end

function FillTypeConverterStateEvent:new(object, partsState)
    local self = FillTypeConverterStateEvent:emptyNew()

    self.object = object
    self.partsState = partsState

    return self
end

function FillTypeConverterStateEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.partsState = streamReadBool(streamId)

    self:run(connection)
end

function FillTypeConverterStateEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteBool(streamId, self.partsState)
end

function FillTypeConverterStateEvent:run(connection)
    if connection:getIsServer() then
        if self.object ~= nil then
            self.object:setPartsState(self.partsState, false, false)
        end
    end
end

FillTypeConverterAnimalTriggerEvent = {}
FillTypeConverterAnimalTriggerEvent_mt = Class(FillTypeConverterAnimalTriggerEvent, Event)
InitEventClass(FillTypeConverterAnimalTriggerEvent, "FillTypeConverterAnimalTriggerEvent")

function FillTypeConverterAnimalTriggerEvent:emptyNew()
    local self = Event:new(FillTypeConverterAnimalTriggerEvent_mt)
    return self
end

function FillTypeConverterAnimalTriggerEvent:new(object, numberToTransfer, loadingVehicle)
    local self = FillTypeConverterAnimalTriggerEvent:emptyNew()
    self.object = object
    self.numberToTransfer = numberToTransfer
    self.loadingVehicle = loadingVehicle

    return self
end

function FillTypeConverterAnimalTriggerEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.numberToTransfer = streamReadInt16(streamId)
    self.loadingVehicle = NetworkUtil.readNodeObject(streamId)

    if not connection:getIsServer() then
        self.object:doAnimalsTransfer(self.numberToTransfer, self.loadingVehicle)
    end
end

function FillTypeConverterAnimalTriggerEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteInt16(streamId, self.numberToTransfer)
    NetworkUtil.writeNodeObject(streamId, self.loadingVehicle)
end
