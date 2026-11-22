local Base = require("combat/combatScript")
local H5R = require("combat/h5Common")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Magnetic Golem: Magic Magnetism
---
--- When the Magnetic Golem is hit by area damage magic (damage magic hitting two or more stacks, Armageddon excepted),
--- allies in the same cast take less damage: ratio = 5% x Magnetic Golem count / weekly growth (original MagicMagnetism_DamageRedirectPercentPerWeeklyGrowth),
--- limited to 50%-100%. Half the damage avoided restores the Magnetic Golem's health (can resurrect).
--- How: after the cast is settled, the damage each ally took is worked out from its health before and after, and the corresponding share is given back.
--- Weekly growth is read from H5_GROWTH_H5C (original H5 weekly growth), otherwise the creature's growth is used.
--- With several Magnetic Golem stacks in the same cast, only the one with the lowest id settles.


local function lostHealth(entry)
	if entry == nil or entry.unit == nil or entry.unitBefore == nil then return 0 end
	return math.max(0, entry.unitBefore:getAvailableHealth() - entry.unit:getAvailableHealth())
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local spell = payload.spell
	if spell == nil or not spell:isDamage() then return end
	if string.find(string.lower(spell:getJsonKey()), "armageddon", 1, true) then return end
	local targets = payload.targets or {}
	if #targets < 2 then return end

	-- Only settled once with several Magnetic Golem stacks
	for _, e in ipairs(targets) do
		if e.unit and e.unit:unitID() < unit:unitID() and (L.has(e.unit, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h5:h5MagicMagnetism" }) or L.has(e.unit, { type = "COMBAT_EVENT_TRIGGER", subtype = "h5MagicMagnetism" })) then
			return
		end
	end

	local growth = L.value(unit, { type = "H5_GROWTH_H5C" })
	if growth <= 0 then growth = math.max(1, unit:getCreature():getGrowth()) end
	local count = unit:isAlive() and unit:getCount() or 0
	local pct = 5 * math.floor(count / growth)
	pct = math.max(50, math.min(100, pct))

	local side = unit:getSide()
	local saved, dests = 0, {}
	for _, e in ipairs(targets) do
		local u = e.unit
		if u and u:unitID() ~= unit:unitID() and not battle:isHostile(unit, u) and not L.isSummoned(u) and not u:isClone() then
			local back = math.floor(lostHealth(e) * pct / 100)
			if back > 0 then
				local healed = server:healUnit(battle, u, back, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
				saved = saved + (healed or 0)
				table.insert(dests, { unit = u })
			end
		end
	end
	if saved <= 0 then return end

	if unit:isAlive() then
		local amt, lvl = H5R.reviveHeal(unit, math.floor(saved / 2))
		if amt > 0 then server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.permanent) end
		table.insert(dests, { unit = unit })
	end
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append = { "core.bonus.H5_MAGNETISM_H5C.description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(math.max(1, unit:getCount())) },
		replaceNumbers = { saved }
	})
end

return Script
