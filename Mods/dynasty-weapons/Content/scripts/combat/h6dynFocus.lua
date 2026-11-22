--- H6 Dynasty Weapon, Asha's Eight-Headed Staff level 5 "Magic Focus": the first spell the hero casts each battle is +val% stronger.
--- Approximation: the script is on enemy stacks; at battle start enemy stacks take +val% spell damage, and after the hero first hits an enemy with a damage / negative spell this bonus is removed from all enemy stacks.
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local TAG = "h6dynFocus"

function Script:onBattleStart(server, battle, unit)
	if not unit:isAlive() or unit:isTurret() then return end
	server:addUnitBonus(battle, unit, {
		type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = -(self.val or 100),
		duration = "ONE_BATTLE", sourceType = "OTHER", stacking = TAG, description = self.text and ("@" .. self.text) or nil, icon = self.icon
	}, false)
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if other ~= nil then return end
	local spell = payload.spell
	if not spell or not (spell:isNegative() or spell:isDamage()) then return end
	local side = unit:getSide()
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side end)) do
		local l = Lib.byStacking(u, { type = "SPELL_DAMAGE_REDUCTION" }, TAG)
		if l:size() > 0 then server:removeUnitBonuses(battle, u, l) end
	end
end

return Script
