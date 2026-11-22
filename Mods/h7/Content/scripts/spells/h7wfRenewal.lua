local Base = require("spells/unitEffect")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local P = require("lib/kadAiProxy")
--- Parameter per (for the normal creature version): when the caster is not a warfare unit, value = per x casting stack size (Touch of Darkness uses per directly).
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Renewal (Mother Tree, round 428): a living friendly stack regains X health at the start of each of the next 3 rounds (X by Mother Tree level, W.SKILL.renewal).
--- Settled in combat/h7WarfareRenewal. AI simulation: half of the 3-round total is restored at once (proxy value).

function Script:isValidTarget(mechanics, unit)
	return W.healable(unit, false)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local lv = caster and W.levelOf(caster)
	local v
	if lv == nil and self.per and caster then
		-- Normal creature version (round 428): per x casting stack size per creature (Touch of Darkness counts per creature of the target; per is the extra damage per creature per hit)
		v = self.per * (caster:getCount())
	else
		lv = lv or 2
		v = W.SKILL.renewal[lv] or W.SKILL.renewal[2]
	end
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and W.healable(u, false) then
			if P.trial(server) then
				W.heal(server, battle, u, v * 3 / 2)
			else
				W.setEffect(server, battle, u, "h7WarfareRenewal", v, 3, "h7/abilities/h7wfRenewal")
				server:showBattleAnimation(battle, { { unit = u } }, "h7/fx/h7wfRenewal", "", 1.0, true)
				server:refreshBattleUnits(battle)
			end
		end
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
