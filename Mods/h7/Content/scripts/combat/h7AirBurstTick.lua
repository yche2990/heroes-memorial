--- Discharge of Lightning Burst (H7): when the stack carrying this bonus "gets its turn" (the first event of the action: before moving, before attacking,
--- wait, defend, cast), hitSpell is cast on all adjacent stacks (Air damage, values in the spell).
--- With no adjacent stack to hit nothing happens and the effect stays until the next action (H7 text). Removed after discharging once.
--- Expert (H7 Understanding I): only hits the casting side's enemies, and stacks hit have Speed at most 1 for 3 rounds (H7 sets Initiative to 1).
--- Parameters (written by spells/h7AirBurst):
---   val          effect value passed to castSpell (encodes level and Spell Power)
---   casterSide   0 attacker / 1 defender (the casting hero's side)
---   expert       whether Expert
---   hitSpell     damage spell
local Base = require("combat/combatScript")
local Air = require("heroes-memorial.h7:spells/h7AirLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local DONE = "H7_AIRBURST_DONE_H7C"
local SHOCK_TURNS = 3

local function myBonuses(unit)
	return unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b)
		local st = b:getSubtype()
		return type(st) == "string" and string.find(st, "h7AirBurst", 1, true) ~= nil
	end)
end

function Script:fire(server, battle, unit)
	if not unit:isAlive() then return end
	if unit:hasBonuses({ type = DONE }) then return end
	-- Checked only once per action (removed when the action ends)
	server:addUnitBonus(battle, unit, {
		type = DONE, val = 1, duration = "N_TURNS", turns = 1,
		sourceType = "OTHER", sourceID = "h7AirBurst", hidden = true
	}, false)

	local expert = self.expert == true
	local side = self.casterSide
	local victims = Air.adjacentUnits(battle, unit, function(u)
		if u:isInvincible() then return false end
		if expert and Air.sideNum(u:getSide()) == side then return false end
		return true
	end)
	if #victims == 0 then return end

	local spell = LIBRARY:getSpellByName(self.hitSpell or "heroes-memorial.h7:h7LightningBurstHit")
	if spell == nil then return end

	local before = {}
	for _, v in ipairs(victims) do before[v:unitID()] = v:getAvailableHealth() end

	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7aStaticAttack", "", 1.0, true)
	server:castSpell(battle, unit, spell, victims, self.val or 0)

	if expert then
		local key = spell:getJsonKey()
		for _, v in ipairs(victims) do
			-- Only stacks actually shocked (not blocked by immunity) get "Electrified"
			if v:isAlive() and v:getAvailableHealth() < (before[v:unitID()] or 0) then
				server:addUnitBonus(battle, v, {
					type = "STACKS_SPEED", val = 1, valueType = "AT_MOST",
					duration = "N_TURNS", turns = SHOCK_TURNS,
					sourceType = "SPELL_EFFECT", sourceID = key, sourceSecondaryID = 3, stacking = "h7AirShock" -- Only Expert electrifies; H7 audit A1 writes the level
				}, false)
			end
		end
		server:refreshBattleUnits(battle)
	end

	local list = myBonuses(unit)
	if list:size() > 0 then server:removeUnitBonuses(battle, unit, list) end
end

function Script:onBeforeMove(server, battle, unit, other, payload)
	self:fire(server, battle, unit)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload and payload.isCounter then return end
	if payload and (payload.attackIndex or 0) > 0 then return end
	self:fire(server, battle, unit)
end

function Script:onWait(server, battle, unit, other, payload)
	self:fire(server, battle, unit)
end

function Script:onDefend(server, battle, unit, other, payload)
	self:fire(server, battle, unit)
end

function Script:onUnitSpellcast(server, battle, unit, other, payload)
	self:fire(server, battle, unit)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	local list = unit:getBonuses({ type = DONE })
	if list:size() > 0 then server:removeUnitBonuses(battle, unit, list) end
end

return Script
