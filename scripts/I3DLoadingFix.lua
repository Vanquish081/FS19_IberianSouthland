--[[
	I3DLoadingFix
	Specialization to fix the filename of i3d files to allow them load out from an mod!
	
	@author:    Ifko[nator]
	@date:      26.05.2019
	@version:	1.0
]]

I3DLoadingFix = {};
I3DLoadingFix.currentModDirectory = g_currentModDirectory;

local function loadSharedI3DFileFix(self, superFunc, filename, baseDir, callOnCreate, addToPhysics, verbose, asyncCallbackFunction, asyncCallbackObject, asyncCallbackArguments)
    callOnCreate = Utils.getNoNil(callOnCreate, false);
    addToPhysics = Utils.getNoNil(addToPhysics, false);

    local filenameToFix = filename;
    local filename = Utils.getFilename(filename, baseDir);

    --print("filenameToFix = " .. tostring(filenameToFix));
	
	if not fileExists(filename) then
		--print("Can't load '" .. filename .. "'! Try to fix it now!");
		
        local filenameTryToFix = Utils.getFilename(filenameToFix, I3DLoadingFix.currentModDirectory); 

        if fileExists(filenameTryToFix) then
            filename = filenameTryToFix; --## here we fix the filename!
            
            --print("Fixed filename '" .. filename .. "'.");
        end;
	end;

    local sharedI3D = self.sharedI3DFiles[filename];

    --## always print all loading texts
    verbose = true;

    if asyncCallbackFunction ~= nil then
        if sharedI3D == nil then
            local callbacks = self.sharedI3DFilesPendingCallbacks[filename];

            if callbacks == nil then
                self.sharedI3DFilesPendingCallbacks[filename] = {};
                table.insert(self.sharedI3DFilesPendingCallbacks[filename], {callOnCreate, addToPhysics, asyncCallbackFunction, asyncCallbackObject, asyncCallbackArguments});
                streamI3DFile(filename, "loadSharedI3DFileFinished", self, {filename}, false, false, verbose);
            else
                table.insert(callbacks, {callOnCreate, addToPhysics, asyncCallbackFunction, asyncCallbackObject, asyncCallbackArguments});
            end;
        else
            local id = 0;

            if sharedI3D.nodeId == 0 then
                print("Error: failed to load i3d file '" .. filename .. "'.");
            else
                id = clone(sharedI3D.nodeId, false, callOnCreate, addToPhysics);
            end;

            sharedI3D.refCount = sharedI3D.refCount + 1;

            asyncCallbackFunction(asyncCallbackObject, id, asyncCallbackArguments);
        end;
    else
        if sharedI3D == nil then
            local nodeId = loadI3DFile(filename, false, false, verbose);

            sharedI3D = {nodeId = nodeId, refCount = 0};

            self.sharedI3DFiles[filename] = sharedI3D;
        end;

        local id = 0;

        if sharedI3D.nodeId == 0 then
            print("Error: failed to load i3d file '" .. filename .. "'.");
        else
            id = clone(sharedI3D.nodeId, false, callOnCreate, addToPhysics);
        end;

        sharedI3D.refCount = sharedI3D.refCount + 1;

        return id;
    end;
end;

--[[
local function createBaleFix(self, superFunc, baleFillType, fillLevel)
    local specBaler = self.spec_baler;

    if specBaler.knotingAnimation ~= nil then
        self:playAnimation(specBaler.knotingAnimation, specBaler.knotingAnimationSpeed, nil, true);
    end;

    if specBaler.dummyBale.currentBale ~= nil then
        delete(specBaler.dummyBale.currentBale);

        specBaler.dummyBale.currentBale = nil;
    end;

    local baleTable = specBaler.baleTypes[specBaler.currentBaleTypeId];
    local baleType = g_baleTypeManager:getBale(baleFillType, baleTable.isRoundBale, baleTable.width, baleTable.height, baleTable.length, baleTable.diameter);
    local bale = {};

    bale.filename = baleType.filename;
    bale.time = 0;
    bale.fillType = baleFillType;
    bale.fillLevel = fillLevel;

    if specBaler.baleUnloadAnimationName ~= nil then
        local baleRoot = g_i3DManager:loadSharedI3DFile(baleType.filename, self.baseDirectory, false, false);
        local baleId = getChildAt(baleRoot, 0);

        link(specBaler.baleAnimRoot, baleId);
        delete(baleRoot);

        bale.id = baleId;
    end;

    if self.isServer and specBaler.baleUnloadAnimationName == nil then
        local x,y,z = getWorldTranslation(specBaler.baleAnimRoot);
        local rx,ry,rz = getWorldRotation(specBaler.baleAnimRoot);
        local baleObject = Bale:new(self.isServer, self.isClient);

        baleObject:load(bale.filename, x,y,z,rx,ry,rz, bale.fillLevel);
        baleObject:setOwnerFarmId(self:getActiveFarm(), true);
        baleObject:register();
        baleObject:setCanBeSold(false);

        local baleJointNode = createTransformGroup("BaleJointTG");

        link(specBaler.baleAnimRoot, baleJointNode);
        setTranslation(baleJointNode, 0,0,0);
        setRotation(baleJointNode, 0,0,0);
        
        local constr = JointConstructor:new();

        constr:setActors(specBaler.baleAnimRootComponent, baleObject.nodeId);
        constr:setJointTransforms(baleJointNode, baleObject.nodeId);

        for i = 1, 3 do
            constr:setRotationLimit(i-1, 0, 0);
            constr:setTranslationLimit(i-1, true, 0, 0);
        end;

        constr:setEnableCollision(false);
        
        local baleJointIndex = constr:finalize();

        g_currentMission:removeItemToSave(baleObject);
        bale.baleJointNode = baleJointNode;
        bale.baleJointIndex = baleJointIndex;
        bale.baleObject = baleObject;
    end;

    table.insert(specBaler.bales, bale);
end;

Baler.createBale = Utils.overwrittenFunction(Baler.createBale, createBaleFix); ]]--
I3DManager.loadSharedI3DFile = Utils.overwrittenFunction(I3DManager.loadSharedI3DFile, loadSharedI3DFileFix);

--[[tal cual]]--