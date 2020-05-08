--[[
SprayerFix

Specialization to allow the helper buy compost.

Author: 	Ifko[nator]
Date: 		15.06.2019
Version:	1.0
]]

SprayerFix = {};

function SprayerFix.prerequisitesPresent(specializations)
	return SpecializationUtil.hasSpecialization(Sprayer, specializations);
end;

function SprayerFix.registerEventListeners(vehicleType)
	local functionNames = {
		"onLoad"
	};
	
	for _, functionName in ipairs(functionNames) do
		SpecializationUtil.registerEventListener(vehicleType, functionName, SprayerFix);
	end;
end;

function SprayerFix:onLoad(savegame)
	self.getExternalFill = Utils.overwrittenFunction(self.getExternalFill, SprayerFix.getExternalFill);
end;

function SprayerFix:getExternalFill(superFunc, fillType, dt)
    local found = false;
    
    local isUnknownFillType = fillType == FillType.UNKNOWN;
    local allowLiquidManure = self:getFillUnitAllowsFillType(self:getSprayerFillUnitIndex(), FillType.LIQUIDMANURE);
    local allowDigestate = self:getFillUnitAllowsFillType(self:getSprayerFillUnitIndex(), FillType.DIGESTATE);
    local allowManure = self:getFillUnitAllowsFillType(self:getSprayerFillUnitIndex(), FillType.MANURE);
    local allowLiquidFertilizer = self:getFillUnitAllowsFillType(self:getSprayerFillUnitIndex(), FillType.LIQUIDFERTILIZER);
    local allowFertilizer = self:getFillUnitAllowsFillType(self:getSprayerFillUnitIndex(), FillType.FERTILIZER);
    local allowsLiquidManureDigistate = allowLiquidManure or allowDigestate;
    
    local usage = 0;
    
    local farmId = self:getActiveFarm();
    local farmStats = g_currentMission:farmStats(self:getLastTouchedFarmlandFarmId());

    if fillType == FillType.LIQUIDMANURE or fillType == FillType.DIGESTATE or (isUnknownFillType and allowsLiquidManureDigistate) then
        if g_currentMission.missionInfo.helperSlurrySource == 2 then --## buy manure
            found = true;

            if g_currentMission.economyManager:getCostPerLiter(FillType.LIQUIDMANURE, false) then
                fillType = FillType.LIQUIDMANURE;
            else
                fillType = FillType.DIGESTATE;
            end;

            usage = self:getSprayerUsage(fillType, dt);

            if self.isServer then
                local price = usage * g_currentMission.economyManager:getCostPerLiter(fillType, false) * 1.5;  --## increase price if AI is active to reward the player's manual work
                
                farmStats:updateStats("expenses", price);
                
                g_currentMission:addMoney(-price, farmId, MoneyType.PURCHASE_FERTILIZER);
            end;

        elseif g_currentMission.missionInfo.helperSlurrySource > 2 then
            local info = g_currentMission.liquidManureTriggers[g_currentMission.missionInfo.helperSlurrySource-2];

            if info ~= nil then -- Can be nil if pen was removed
                local fillLevel = info.silo:getFillLevel(FillType.LIQUIDMANURE);

                if fillLevel > 0 then
                    found = true;
                    usage = self:getSprayerUsage(FillType.LIQUIDMANURE, dt);

                    if self.isServer then
                        info.silo:setFillLevel(FillType.LIQUIDMANURE, fillLevel-usage);
                    end;
                end;
            end;
        end;    --
    elseif fillType == FillType.MANURE or (isUnknownFillType and allowManure) then
        if g_currentMission.missionInfo.helperManureSource == 2 then -- buy manure
            found = true;
            fillType = FillType.MANURE;
            usage = self:getSprayerUsage(fillType, dt);

            if self.isServer then
                local price = usage * g_currentMission.economyManager:getCostPerLiter(fillType, false) * 1.5;  --## increase price if AI is active to reward the player's manual work
                
                farmStats:updateStats("expenses", price);
                
                g_currentMission:addMoney(-price, farmId, MoneyType.PURCHASE_FERTILIZER);
            end
        elseif g_currentMission.missionInfo.helperManureSource > 2 then
            local info = g_currentMission.manureHeaps[g_currentMission.missionInfo.helperManureSource-2];
            
            if info ~= nil then --## Can be nil if pen was removed
                usage = self:getSprayerUsage(FillType.MANURE, dt);

                if self.isServer then
                    if info.manureHeap:removeManure(usage) > 0 then
                        found = true;
                        fillType = FillType.MANURE;
                    end;
                end;
            end;
        end;  --
    elseif fillType == FillType.FERTILIZER or
           fillType == FillType.LIQUIDFERTILIZER or
           fillType == FillType.HERBICIDE or
           fillType == FillType.LIME or
           fillType == FillType.COMPOST or
          (fillType == FillType.UNKNOWN and (allowLiquidFertilizer or allowFertilizer)) then
        if g_currentMission.missionInfo.helperBuyFertilizer then
            found = true;

            if fillType == FillType.UNKNOWN then
                if self:getFillUnitAllowsFillType(self:getSprayerFillUnitIndex(), FillType.LIQUIDFERTILIZER) then
                    fillType = FillType.LIQUIDFERTILIZER;
                else
                    fillType = FillType.FERTILIZER;
                end;
            end;

            usage = self:getSprayerUsage(fillType, dt);

            if self.isServer then
                local price = usage * g_currentMission.economyManager:getCostPerLiter(fillType, false) * 1.5;  -- increase price if AI is active to reward the player's manual work
                
                farmStats:updateStats("expenses", price);
                
                g_currentMission:addMoney(-price, farmId, MoneyType.PURCHASE_FERTILIZER);
            end;
        end;
    end;

    if found then
        return fillType, usage;
    end;
    
    return FillType.UNKNOWN, 0;
end;