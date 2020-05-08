-- timeControlledslidingGateHarinsur
-- @author: Daniel (Desperados93) W.
-- @date: 01.03.2011

-- Copyright (©) by Daniel "Desperados93" W.
   
  timeControlledslidingGateHarinsur = {};
  
  local timeControlledslidingGateHarinsur_mt = Class(timeControlledslidingGateHarinsur);
  
  function timeControlledslidingGateHarinsur.onCreate(id)
      g_currentMission:addUpdateable(timeControlledslidingGateHarinsur:new(id));

  end;
  
  function timeControlledslidingGateHarinsur:new(id, customMt)
  
      local instance = {};
      if customMt ~= nil then
          setmetatable(instance, customMt);
      else
          setmetatable(instance, timeControlledslidingGateHarinsur_mt);
      end;
  
      instance.triggerId = id;
      addTrigger(id, "triggerCallback", instance);
  
      instance.gate = {};
      
      local num = getNumOfChildren(id);
      for i=0, num-1 do
          local childLevel1 = getChildAt(id, i);
          if childLevel1 ~= 0 and getNumOfChildren(id) >= 1 then
              local gate2Id = getChildAt(childLevel1, 0);
              if gate2Id ~= 0 then
                  table.insert(instance.gate, gate2Id);
              end;
          end;
      end;
  
      instance.isEnabled = true;
  
      self.count = 0;
  
      self.trans = 0;
      self.maxTrans = 13;
      self.minTrans = 0;
  	  
      return instance;
  end;
  
  function timeControlledslidingGateHarinsur:delete()
 
      removeTrigger(self.triggerId);
  end;
  	
  
function timeControlledslidingGateHarinsur:update(dt)
 
    
	local available = false;
	
	if  (g_currentMission.environment.dayTime > 29000000 and g_currentMission.environment.dayTime < 60000000) then --or -- 8h06 - 18.00 Uhr
		--(g_currentMission.environment.dayTime > 54000000 and g_currentMission.environment.dayTime < 65865000) then --15 - 18.30 Uhr

		available = true;
	end;
	
	if available == true then 
		local old = self.trans;
		if self.count > 0 then
			if self.trans < self.maxTrans then
				self.trans = self.trans + dt*0.003;    
			end;
		else  
			if self.trans > self.minTrans then
				self.trans = self.trans - dt*0.003;    
			end;
		end;
      
		for i=1, table.getn(self.gate) do
			setTranslation(self.gate[i], self.trans, 0, 0);
		end;
	end;
      
end;
    
  function timeControlledslidingGateHarinsur:triggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
  
      if onEnter and self.isEnabled then

          self.count = self.count + 1;
      elseif onLeave then
         self.count = self.count - 1;
      end; 
  end;
    
g_onCreateUtil.addOnCreateFunction("timeControlledslidingGateHarinsurOnCreate", timeControlledslidingGateHarinsur.onCreate);

print("Time Controlled Gates Loaded Successfully");