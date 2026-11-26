local Base = require("spells/unitEffect")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Healing of the normal creature version (round 428, Dream Walker's Shamanic Healing): a living friendly stack (undead, constructs and war machines excluded) regains per x casting stack size health, no resurrection.
--- The warfare version uses engine healing (amount = SPECIFIC_SPELL_POWER); normal creatures count by stack size, so it is written separately. The AI simulation follows the actual healing. Parameter: per

function Script:isValidTarget(mechanics, unit)
	return W.healable(unit, false)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local v = (self.per or 0) * caster:getCount()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and W.healable(u, false) then
			local h = W.heal(server, battle, u, v)
			if h > 0 and server:describeChanges() then
				server:showBattleAnimation(battle, { { unit = u } }, self.animation or "h7/fx/h7wfShamanHeal", "", 1.0, true)
				server:refreshBattleUnits(battle)
			end
		end
	end
end

--- Amount restored shown in the mouse hint

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Shaman Heal
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "combatHeal" } -- step number -> cursor
	local AIM = { ["*"] = "creature" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Healing shown in the mouse tooltip: same formula as apply, per x number of casting creatures, only the top creature is healed (no resurrection)
function Script:getHealthChange(mechanics, spellTarget)
	local ok, result = pcall(function()
		local out = { hpDelta = 0, unitsDelta = 0 }
		local caster = mechanics:getUnitCaster()
		if caster == nil then return out end
		local v = (self.per or 0) * caster:getCount()
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget or {})) do
			local u = dest.unit
			if u and W.healable(u, false) then
				local h = math.min(math.floor(v), u:getMaxHealth() - u:getFirstHPleft())
				if h > 0 then out.hpDelta = out.hpDelta + h end
			end
		end
		return out
	end)
	if ok and result then return result end
	return { hpDelta = 0, unitsDelta = 0 }
end

return Script
