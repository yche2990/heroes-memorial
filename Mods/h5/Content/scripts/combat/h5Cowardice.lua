local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local B3 = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Cowardice (H5 Goblin)
--- After being attacked in melee (not retaliation), at the end of this round's action it flees to a random free hex within its own movement range.
--- Not retaliating is handled by the hidden NO_RETALIATION on the creature.
--- How: when hit, note "must flee", then teleport after the action ends (pushes and teleports are all done after the action ends).

local FLEE = "h5CowardiceFlee"

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter then return end
	if not unit:isAlive() or unit:isGhost() then return end
	A.setMark(server, battle, unit, FLEE, 1, 1)
end

local function speedOf(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "STACKS_SPEED" }) end)
	if ok and type(v) == "number" then return v end
	return 0
end

function Script:onActionFinished(server, battle, unit, other)
	if A.markValue(unit, FLEE) == nil then return end
	A.clearMark(server, battle, unit, FLEE)
	if not unit:isAlive() or unit:isGhost() then return end
	if unit:hasBonuses({ type = "BIND_EFFECT" }) or unit:hasBonuses({ type = "NOT_ACTIVE" }) then return end
	if A.has(unit, "H5_HOLD_GROUND_H5C") then return end
	local speed = speedOf(unit)
	if speed <= 0 then return end
	local pos = unit:getPosition()
	if pos == nil then return end

	local cands = {}
	local arr = battle:getAllPossibleHexes()
	for i = 1, arr:size() do
		local h = arr:at(i)
		local d = A.hexDistance(pos, h)
		if d >= 1 and d <= speed and h:isAvailable() and not unit:coversPos(h)
			and battle:getUnitByPos(h, false) == nil and battle:isAccessibleForUnit(unit, h) then
			table.insert(cands, h)
		end
	end
	if #cands == 0 then return end
	local dest = cands[server:rngInt(1, #cands)]
	server:moveUnit(battle, unit, dest, true)
	B3.rageEvent(server, battle, unit, -100)
	server:refreshBattleUnits(battle)
end

return Script
