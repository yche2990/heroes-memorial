--- H5 resurrection spells (Raise Dead, Resurrection):
---   healing = base[mastery] + perPower[mastery] x SP, can resurrect;
---   each cast also lowers the target's max health per creature by hpReduce% (multiplied on the current max: 80% / 90% of the current each time, this battle),
---   keeping at least MIN_KEEP% of the original max (audit B-7, Yu's decision); original Raise Dead 20%, Resurrection 10%;
---   with the Ring of Oblivion (HOTA_RING_OF_OBLIVION) in play there is no resurrection, only the top creature is healed (h5Common.reviveHeal, checklist section 10);
---   undeadPermanent = true: resurrected undead stay permanently, other creatures only until the end of this battle (Raise Dead).
--- Parameters: base, perPower, hpReduce, undeadPermanent, requireAny, exclude, plus healLevel/healPower/minFullUnits of the core heal
local Base = require("spells/heal")
local Lib = require("spells/h5SpellLib")
local C = require("combat/h5Common")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local HP_STACK = "h5HpReduce"
local MIN_KEEP = 20   -- Max health keeps at least 20% of the original
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:getHealAmount(mechanics, unit, server)
	local raw = Lib.value(self.base, self.perPower, Lib.level(mechanics), Lib.power(mechanics))
	return mechanics:applySpellBonus(math.floor(raw), unit)
end

function Script:isValidTarget(mechanics, unit)
	if not Lib.passesFilter(unit, self.requireAny, self.exclude) then return false end
	-- The core heal's check uses mechanics:getEffectValue(); here it is replaced by the H5 healing amount
	local allowDead = self:getHealLevel() ~= ENUM.HealLevel.heal
	if not unit:isValidTarget(allowDead) then return false end
	-- When only healing, only the top creature is healed; lost creatures do not count as wounds (as the core heal in newer engines)
	local injuries
	if allowDead then
		injuries = unit:getTotalHealth() - unit:getAvailableHealth()
	else
		injuries = unit:getMaxHealth() - unit:getFirstHPleft()
	end
	if injuries <= 0 then return false end
	local mfu = self:getMinFullUnits()
	if mfu > 0 then
		local hpGained = math.min(self:getHealAmount(mechanics, unit, nil), injuries)
		if hpGained < mfu * unit:getMaxHealth() then return false end
	end
	if unit:isDead() then
		local hexes = unit:getHexes()
		for i = 1, hexes:size() do
			local hex = hexes:at(i)
			local blockers = mechanics:getBattle():getUnitsIf(function(other)
				return other:unitID() ~= unit:unitID() and other:isValidTarget(false) and other:coversPos(hex)
			end)
			if #blockers > 0 then return false end
			if #mechanics:getBattle():getObstaclesOnPos(hex, true) > 0 then return false end
		end
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit then
			local power = self:getHealPower()
			if self.undeadPermanent then
				power = Lib.has(unit, "UNDEAD") and ENUM.HealPower.permanent or ENUM.HealPower.oneBattle
			end
			local amount, level = self:getHealAmount(mechanics, unit, server), self:getHealLevel()
			if level == ENUM.HealLevel.resurrect then amount, level = C.reviveHeal(unit, amount) end
			local healed, resurrected = 0, 0
			if amount > 0 then healed, resurrected = server:healUnit(battle, unit, amount, level, power) end
			if (self.hpReduce or 0) > 0 and (healed > 0 or resurrected > 0) and unit:isAlive() then
				-- Multiplied: remaining max % = current remaining % x (100 - hpReduce)%, not below MIN_KEEP%; only one kept (the old one replaced)
				local old = unit:getBonuses({ type = "STACK_HEALTH" }):filter(function(b) return b:getStacking() == HP_STACK end)
				local cut = 0
				for i = 1, old:size() do cut = cut - old:getBonus(i):getVal() end
				local keep = math.max(MIN_KEEP, math.floor((100 - cut) * (100 - self.hpReduce) / 100))
				if 100 - keep ~= cut then
					-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
					if old:size() > 0 then Proxy.removeExact(server, battle, unit, old) end
					server:addUnitBonus(battle, unit, {
						type       = "STACK_HEALTH",
						val        = -(100 - keep),
						valueType  = ENUM.BonusValueType.percentToAll,
						duration   = ENUM.BonusDuration.oneBattle,
						sourceType = ENUM.BonusSource.other,
						sourceID   = mechanics:getSpell():getJsonKey(), -- Not a spell effect, cannot be dispelled
						stacking   = HP_STACK
					}, true)
				end
			end
			if resurrected > 0 and server:describeChanges() then
				server:appendLog(battle, {
					append         = { resurrected == 1 and "core.genrltxt.117" or "core.genrltxt.116" },
					replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
					replaceNumbers = { resurrected }
				})
			end
		end
	end
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Animate Dead, Reincarnation, Resurrection (H4/H7), Divine Intervention (H4), Call of Death: heal and resurrect
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
		-- When pointing at an enemy stack (damage or no effect) use the engine default
		if unit ~= nil and unit:getSide() ~= mechanics:getCasterSide() then return nil end
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

--- Hover estimate: same formula as apply (Heroes V healing amounts; with the Ring of Oblivion on the field only the top creature is healed, no resurrection); healing and resurrected counts of all targets are summed
function Script:getHealthChange(mechanics, spellTarget)
	local ok, result = pcall(function()
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget)) do
			local unit = dest.unit
			if unit then
				local amount, level = self:getHealAmount(mechanics, unit, nil), self:getHealLevel()
				if level == ENUM.HealLevel.resurrect then amount, level = C.reviveHeal(unit, amount) end
				if amount > 0 then
					local copy = unit:copy()
					local healed, resurrected = copy:heal(amount, level, self:getHealPower())
					out.hpDelta = out.hpDelta + healed
					if resurrected > 0 then
						out.unitsDelta = out.unitsDelta + resurrected
						local cr = unit:getCreature()
						if out.unitType == nil then out.unitType = cr
						elseif out.unitType:getJsonKey() ~= cr:getJsonKey() then out.mixed = true end
					end
				end
			end
		end
		-- When more than one kind of creature is resurrected it cannot be written as "+N creature", so only the restored health is shown
		if out.mixed or out.unitType == nil then out.unitsDelta = 0 end
		out.mixed = nil
		return out
	end)
	if ok and result and (result.unitsDelta <= 0 or result.unitType) then return result end
	return { hpDelta = 0, unitsDelta = 0 }
end

return Script
