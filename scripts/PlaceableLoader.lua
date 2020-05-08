--[[
Interface: 1.5.1.0 b6732

Author: GtX | Andy
Date: 02.02.2019
Version: 1.0.0.0

Contact:
https://forum.giants-software.com
https://github.com/GtX-Andy

History:
V 1.0.0.0 @ 02.02.2019 - Release Version
V 1.0.0.1 @ 09.12.2019 - Optimisations

About:
Simple loader script for placeables. This saves having 2 or 3 loader scripts in maps or mods for custom scripts.
Unfortunately not supported in modDesc as it should be, but now it is. ;-)

Example:
<modDesc>
    <placeables>
        <placeable typeName="myPlaceable" className="MyPlaceableClass" filename="scripts/MyPlaceableScript.lua"/>
    </placeables>
</modDesc>
]]


local modName = g_currentModName
local modDirectory = g_currentModDirectory

local function errorPrint(name, key)
    print(string.format("  Error: [%s] Missing '%s' at %s. Placeable will not be added!", modName, name, key))
    return false
end

local function placeableLoaderInit()
    if g_currentMission ~= nil then
        return
    end

    local loaded = {}
    local xmlFile = loadXMLFile("modDesc", modDirectory .. "modDesc.xml")

    if xmlFile ~= 0 then
        local i = 0
        while true do
            local key = string.format("modDesc.placeables.placeable(%d)", i)
            if not hasXMLProperty(xmlFile, key) then
                break
            end

            local isValid = true

            local typeName = getXMLString(xmlFile, key .. "#typeName")
            if typeName == nil then
                isValid = errorPrint("typeName", key)
            end

            local className = getXMLString(xmlFile, key .. "#className")
            if className == nil then
                isValid = errorPrint("className", key)
            end

            local filename = getXMLString(xmlFile, key .. "#filename")
            if filename == nil then
                isValid = errorPrint("filename", key)
            end

            if isValid and not loaded[typeName] then
                local placeablePath = modDirectory .. filename

                if fileExists(placeablePath) then
                    g_placeableTypeManager:addPlaceableType(typeName, className, placeablePath)
                    loaded[typeName] = true
                else
                    print(string.format("  Error: [%s] File %s could not be found!", placeablePath))
                end
            end

            i = i + 1
        end

        delete(xmlFile)
    end

    xmlFile = nil
    loaded = nil
end

placeableLoaderInit()
