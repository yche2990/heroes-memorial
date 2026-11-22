local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Putrescence Aura, Contagion (H6 Lamasu, Pestilent Lamasu)
---
--- Two bonuses, both using this script:
---   1. The Lamasu's own (visible, role = "carrier"): at the start of each round, each adjacent living enemy stack gets one layer of "Putrescence":
---      max health -pct% (of the base value), lasting turns rounds, at most max layers (each layer timed separately).
---      If contagion is true (Pestilent Lamasu), stacks hit by Putrescence also get the "Contagion" mark.
---   2. The battle-wide one (hidden, role = "zone"): at the start of each round, a stack with the "Contagion" mark that still has Putrescence passes one layer
---      to the living friendly stacks next to it (that is, enemies of the Lamasu's side).
--- There is no "round start" event in the first round (the engine counts it as part of battle start), so the aura works from round 2.
--- Parameters: role, pct, max, turns, contagion, animation, sound

local SHOW = "H6_PUTRESCENCE_H6C"
local CMARK = "h6PutreC"

local function layers(unit)
	local n, used = 0, {}
	local list = unit:getBonuses({ type = "STACK_HEALTH" })
	for i = 1, list:size() do
		local k = list:getBonus(i):getStacking()
		local idx = k:match("^h6Putre(%d+)$")
		if idx then n = n + 1; used[tonumber(idx)] = true end
	end
	return n, used
end

local function addLayer(server, battle, target, pct, max, turns, srcSide, contagion)
	local n, used = layers(target)
	if n < max then
		local k = 1
		while used[k] do k = k + 1 end
		L.addBonus(server, battle, target, {
			type = "STACK_HEALTH", val = -pct, valueType = ENUM.BonusValueType.percentToBase,
			duration = ENUM.BonusDuration.nTurns, turns = turns, stacking = "h6Putre" .. k, hidden = true
		}, false)
		n = n + 1
	end
	L.removeByStacking(server, battle, target, SHOW, "h6Putre")
	L.addBonus(server, battle, target, { type = SHOW, val = n * pct, duration = ENUM.BonusDuration.nTurns, turns = turns, stacking = "h6Putre" }, false)
	if contagion then L.setMark(server, battle, target, CMARK, srcSide + 1, turns) end
end

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() then return end
	local pct, max, turns = self.pct or 5, self.max or 5, self.turns or 2
	if self.role == "carrier" then
		local list = L.around(battle, unit, function(u) return battle:isHostile(unit, u) and L.isLiving(u) end)
		for _, u in ipairs(list) do addLayer(server, battle, u, pct, max, turns, unit:getSide(), self.contagion) end
		if #list > 0 then
			L.show(server, battle, list, self.animation, self.sound)
			L.log(server, battle, SHOW, 1, { L.name(unit) }, { #list })
		end
	elseif self.role == "zone" then
		local side = L.markValue(unit, CMARK)
		if side == nil or layers(unit) == 0 then return end
		side = side - 1
		local list = L.around(battle, unit, function(u) return u:getSide() ~= side and L.isLiving(u) end)
		for _, u in ipairs(list) do addLayer(server, battle, u, pct, max, turns, side, true) end
		if #list > 0 then
			L.show(server, battle, list, self.animation, self.sound)
			L.log(server, battle, SHOW, 2, { L.name(unit) }, { #list })
		end
	end
end

return Script
