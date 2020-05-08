--[[
Copy all mod-environment-l10n-texts into the game-root-l10n-text object.

Author: 	Ifko[nator]
Date: 		21.06.2019
Version:	1.0
]]

local root_i18n = getfenv(0).g_i18n;

for l10nTAG, text in pairs(g_i18n.texts) do
	root_i18n:setText(l10nTAG, text);
end;

InGameMenuMapFrame.L10N_SYMBOL.DIALOG_VEHICLE_RESET_DONE = "ui_vehicleReset";
InGameMenuMapFrame.L10N_SYMBOL.DIALOG_VEHICLE_RESET_FAILED = "ui_failedVehicleReset";