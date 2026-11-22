local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 warfare unit, Sylvan Ballista Fast Reload (Tears of Ashan link, round 428).
--- After hitting a marked enemy (Avenger marks AVENGER01/02/03 from the Tears of Ashan Avenger skill, Death Mark MARKED from Anwen's specialty),
--- it immediately shoots the same target again (once per round).
--- The original is "attacks +1, may switch targets"; VCMI scripts cannot let a stack act again this round, only add a hit to the same shot
--- (the engine counts the hits of this shot after the first one, so the ADDITIONAL_ATTACK added here is included), so the second hit goes to the same target.

local MARKS = { "tears-of-ashan:AVENGER01", "tears-of-ashan:AVENGER02", "tears-of-ashan:AVENGER03", "tears-of-ashan:MARKED" }
local USED = "h7WfFastReload"

local function marked(t)
	for _, ty in ipairs(MARKS) do
		local ok, has = pcall(function() return t:hasBonuses({ type = ty }) end)
		if ok and has then return true end
	end
	return false
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload == nil or payload.isCounter or not payload.ranged or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() or other == nil or not other:isAlive() then return end
	if W.mark(unit, USED) ~= nil or not marked(other) then return end
	W.setMark(server, battle, unit, USED, 1, 1)
	server:addUnitBonus(battle, unit, {
		type = "ADDITIONAL_ATTACK", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true,
		sourceType = ENUM.BonusSource.other, valueType = ENUM.BonusValueType.additiveValue, stacking = USED
	}, false)
	W.log(server, battle, 9, { W.name(unit) }, {})
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	W.removeKey(server, battle, unit, "ADDITIONAL_ATTACK", USED)
end

return Script
