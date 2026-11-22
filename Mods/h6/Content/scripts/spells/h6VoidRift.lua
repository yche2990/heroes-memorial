local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Void Rift (H6 Void Avatar): tears a rift at an enemy stack. Enemies within radius hexes (it included) are pulled 1 hex closer to the rift,
--- then take per damage of no school at the start of each of the next turns rounds (settled by h6Dot). Parameters: radius, per, turns, key, animation, sound
--- Round 419: the AI simulation (Proxy.trial) pulls no one; damage over time is reported as half its amount in proxy damage (per x turns / 2) so the AI can see it

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	return caster ~= nil and L.real(unit) and not unit:isInvincible() and mechanics:getBattle():isHostile(caster, unit)
end
function Script:applicableGeneral(mechanics, problem)
	if #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
	end
	return true
end
function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget); return false
end
function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or main == nil then return end
	local c = main:getPosition()
	local hexes = L.hexTable(battle)
	local list = battle:getUnitsIf(function(u) return self:isValidTarget(mechanics, u) and L.unitDistance(main, u) <= (self.radius or 2) end)
	if Proxy.trial(server) then
		for _, u in ipairs(list) do Proxy.damage(server, battle, u, (self.per or 200) * (self.turns or 4) / 2) end
		L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
		return
	end
	for _, u in ipairs(list) do
		if u:unitID() ~= main:unitID() and u:getHexes():size() == 1 then
			local p = u:getPosition()
			local idx = L.lineIndex(p, c, 1)
			local h = idx and hexes[idx]
			if h and h:isAvailable() and battle:isAccessibleForUnit(u, h) then server:moveUnit(battle, u, h, true) end
		end
		L.addDot(server, battle, u, "bleedVoid" .. tostring(caster:getSide()), self.per or 200, self.turns or 4)
	end
	L.show(server, battle, list, self.animation, self.sound)
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

return Script
