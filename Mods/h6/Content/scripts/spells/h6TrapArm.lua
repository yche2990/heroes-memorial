local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Companion effect of the Crippling Trap (H6 Goblin, Goblin Hunter): records this Goblin stack's current trap power (per x count,
--- hidden mark h6TrapPower, the larger one is kept), read by h6TrapHit when the trap is sprung. Also refunds the cast. Parameter: per

--- 2026-11-08 (AI skill fixes): in the AI simulation a trap (hidden obstacle) is worth 0, so the AI never set one. The simulation now reports a proxy value instead:
--- only the one enemy most likely to step on it counts (a trap works once): enemies that cannot fly and are no farther from the trap hex than their Speed + 1;
--- 35% chance if the trap lies between it and our nearest stack (the trap hex is closer to that stack than the enemy is), otherwise 10%;
--- value = chance x (trap damage per x number of Goblins + Speed -3 for two rounds counted as 2% of its remaining health); the largest is reported with Proxy.damage.
--- For neutral location spells like this the AI picks the spot through the engine's defaultLocationSpellHeuristics: for each stack, a random free adjacent hex is a candidate,
--- and free hexes next to enemies facing our side are among them, so with the added value they can be chosen. Real casting (below) is unchanged.
local function trialValue(battle, caster, hex, per)
	local power = per * caster:getCount()
	local best, bestHp = nil, 0
	for _, e in ipairs(battle:getUnitsIf(function(u) return L.hostile(battle, caster, u) and not u:hasBonuses({ type = "FLYING" }) end)) do
		local ok, speed = pcall(function() return e:getBonusesValue({ type = "STACKS_SPEED" }) end)
		if not ok or type(speed) ~= "number" then speed = 0 end
		local d = Proxy.unitDistance(e, hex)
		if d >= 1 and d <= speed + 1 then
			local p = 0.1
			local friend, fd = Proxy.nearestHostile(battle, e)
			if friend ~= nil and Proxy.unitDistance(friend, hex) < fd then p = 0.35 end
			local hp = p * (power + e:getAvailableHealth() * 0.02)
			if hp > bestHp then best, bestHp = e, hp end
		end
	end
	return best, bestHp
end

function Script:apply(mechanics, server, target)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local battle = mechanics:getBattle()
	if Proxy.trial(server) then
		local hex = target[1] and target[1].hex
		if hex and hex:isValid() then
			local e, hp = trialValue(battle, caster, hex, self.per or 2)
			if e then Proxy.damage(server, battle, e, hp) end
		end
		L.useCast(server, battle, caster, "h6TrapArm", nil)
		return
	end
	local v = (self.per or 2) * caster:getCount()
	L.setMark(server, battle, caster, "h6TrapPower", math.max(v, L.markValue(caster, "h6TrapPower") or 0))
	L.useCast(server, battle, caster, "h6TrapArm", nil)
end

return Script
