local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Renewal (Mother Tree, see spells/h7wfRenewal): put on an ally; for the next 3 rounds it regains val health at the start of each round (no resurrection).

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local v = W.effectVal(unit, "h7WarfareRenewal")
	if v == nil then return end
	local h = W.heal(server, battle, unit, v)
	if h > 0 then
		server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7wfRenewal", "", 1.0, true)
		server:refreshBattleUnits(battle)
		W.log(server, battle, 4, { W.name(unit) }, { h })
	end
	W.tickLeft(server, battle, unit, "h7WarfareRenewal")
end

return Script
