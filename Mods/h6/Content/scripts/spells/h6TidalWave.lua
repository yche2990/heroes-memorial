local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Tidal Wave (H6 Mermaid), cast on itself, once per battle: all enemies get the status status (Soaked), and single-hex enemies are washed back up to knock hexes
--- in the direction away from the Mermaid (stopping where a hex does not fit). usedType: after casting, a whole-battle hidden bonus on itself; with a limiter on the casting bonus this makes "once per battle".
--- near (round 352): only enemies within near hexes of the caster (Thunderbird "Hurricane"); per: each enemy first takes per damage of school (Enraged Kirin "Great Tsunami").
--- Parameters: status, turns, knock, near, per, school, key, usedType, animation, sound
--- Round 419: the AI simulation (Proxy.trial) does not wash anyone back (repositioning is worth 0 in the estimate, and stacks are not moved on the imaginary battlefield); damage and statuses as usual

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
	end
	if self.near then
		local battle = mechanics:getBattle()
		if #battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) and L.unitDistance(caster, u) <= self.near end) == 0 then
			problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
		end
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local list = battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) and not u:isInvincible()
		and (self.near == nil or L.unitDistance(caster, u) <= self.near) end)
	if (self.per or 0) > 0 then
		for _, u in ipairs(list) do
			L.hit(server, battle, u, math.floor(self.per * (100 - L.schoolReduction(u, self.school)) / 100), nil, nil)
		end
	end
	local sp = self.status and L.spell(self.status)
	if sp and #list > 0 then server:applySpellEffects(battle, caster, sp, list, 3, self.turns or 2, false) end
	local hexes = L.hexTable(battle)
	for _, u in ipairs(list) do
		if u:isAlive() and u:getHexes():size() == 1 and not Proxy.trial(server) then
			local a, b = caster:getPosition(), u:getPosition()
			local bd = L.hexDistance(a, b)
			local dest = nil
			for k = 1, (self.knock or 2) do
				local idx = L.lineIndex(a, b, bd + k)
				local h = idx and hexes[idx]
				if h and h:isAvailable() and battle:isAccessibleForUnit(u, h) then dest = h else break end
			end
			if dest then server:moveUnit(battle, u, dest, true) end
		end
	end
	L.show(server, battle, list, self.animation, self.sound)
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
	if self.usedType then
		server:addUnitBonus(battle, caster, { type = self.usedType, val = 1, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), hidden = true }, true)
	end
end

return Script
