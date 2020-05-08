-- timeControlledslidingGate
-- @author: Daniel (Desperados93) W.
-- @date: 01.03.2011

-- Copyright (©) by Daniel "Desperados93" W.
   
  timeControlledslidingGate = {};
  
  local timeControlledslidingGate_mt = Class(timeControlledslidingGate);
  
  function timeControlledslidingGate.onCreate(id)
      g_currentMission:addUpdateable(timeControlledslidingGate:new(id));

  end;
  
  function timeControlledslidingGate:new(id, customMt)
  
      local instance = {};
      if customMt ~= nil then
          setmetatable(instance, customMt);
      else
          setmetatable(instance, timeControlledslidingGate_mt);
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
      self.maxTrans = 17;
      self.minTrans = 0;
  	  
      return instance;
  end;
  
  function timeControlledslidingGate:delete()
 
      removeTrigger(self.triggerId);
  end;
  	
  
function timeControlledslidingGate:update(dt)
 
    
	local available = false;
	
	if  (g_currentMission.environment.dayTime > 29000000 and g_currentMission.environment.dayTime < 50400000) or -- 8h04 - 14.00 Uhr
		(g_currentMission.environment.dayTime > 57600000 and g_currentMission.environment.dayTime < 72000000) then -- 16h - 20.00 Uhr

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
    
  function timeControlledslidingGate:triggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
  
      if onEnter and self.isEnabled then

          self.count = self.count + 1;
      elseif onLeave then
         self.count = self.count - 1;
      end; 
  end;
    
g_onCreateUtil.addOnCreateFunction("timeControlledslidingGateOnCreate", timeControlledslidingGate.onCreate);

print("Time Controlled Gates Loaded Successfully");