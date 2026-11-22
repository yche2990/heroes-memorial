local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local BattleLog = require("battleLog")
local AttackLib = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Aura of Pestilence (Plague Lamasu)
---
--- At the start of each round (round 1 at battle start), each enemy adjacent to the Plague Lamasu takes perCreature x number of Lamasu Earth damage (regardless of Attack and Defense),
--- then gets Attack -attack and Speed -speed for 2 rounds (repeats only refresh).
--- Undead, non-living (constructs, elementals), mechanical stacks, war machines, and stacks immune to poison or Earth are not affected.
--- Parameters: perCreature (scaled by level), attack (scaled), speed

function Script:eligible(battle, unit, t)
	if not L.canHit(battle, unit, t) then return false end
	if t:hasBonuses({ type = "UNDEAD" }) or t:hasBonuses({ type = "NON_LIVING" }) or t:hasBonuses({ type = "MECHANICAL" }) then return false end
	if L.spellImmune(t, "poison") or L.schoolImmune(t, "earth") then return false end
	return true
end

function Script:pulse(server, battle, unit)
	if not unit:isAlive() or unit:isGhost() then return end
	local victims = L.adjacentUnits(battle, unit, function(t) return self:eligible(battle, unit, t) end)
	if #victims == 0 then return end
	local src = unit:getCreature():getJsonKey()
	local amount = (self.perCreature or 10) * unit:getCount()
	local att = self.attack or 5
	local spd = self.speed or 1
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7PestilenceCast", "", 1.0, true)
	for _, t in ipairs(victims) do
		if t:isAlive() then
			server:showBattleAnimation(battle, { { unit = t } }, "h7/fx/h7Pestilence", "", 1.0, true)
			local name = L.name(t)
			-- H7 audit B2: Earth damage, reduced by the target's Earth / all-school magic damage reduction
			local dealt, killed = 0, 0
			local hit = AttackLib.schoolDamage(t, amount, "earth")
			if hit > 0 then dealt, killed = server:damageUnit(battle, t, hit) end
			L.log(server, battle, 12, { name }, { dealt })
			BattleLog.creaturesPerish(server, battle, t, killed)
			if t:isAlive() then
				local function add(d)
					d.duration = ENUM.BonusDuration.nTurns; d.turns = 2; d.hidden = true
					d.sourceType = ENUM.BonusSource.other; d.sourceID = src; d.stacking = "h7AuraOfPestilence"
					server:addUnitBonus(battle, t, d, true)
				end
				L.removeByStacking(server, battle, t, "PRIMARY_SKILL", "h7AuraOfPestilence")
				L.removeByStacking(server, battle, t, "STACKS_SPEED", "h7AuraOfPestilence")
				add({ type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = -att })
				add({ type = "STACKS_SPEED", val = -spd })
				L.setShow(server, battle, t, "H7_PESTILENCE_H7C", att, 2, "h7AuraOfPestilence", src)
			end
		end
	end
	server:refreshBattleUnits(battle)
end

function Script:onBattleStart(server, battle, unit, other, payload)
	self:pulse(server, battle, unit)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	self:pulse(server, battle, unit)
end

return Script
