local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 warfare units: replacement at battle start (round 428).
--- Carrier: hidden combat events of Artillery, Ballistics and First Aid (warfareSkills.json of heroes-memorial.h7), only on the four original machines
--- (Ballista, Ammo Cart <- Artillery; Catapult <- Ballistics; First Aid Tent <- First Aid).
--- During battle setup (before tactics deployment) the first machine to trigger replaces every qualifying original machine on the battlefield at once, playing the replacement animation once for all:
---   * the hero got this slot's mark (h7WfSlot|slot) and the faction mark (h7WfFaction) at the H7 Memorial Smithy;
---   * the hero still has the skill matching this slot (no swap if it was forgotten before battle);
---   * the hero's faction has an H7 machine for this slot (Necropolis and Stronghold have no ranged / support slots and stay original).
--- The swapped-in H7 machines are added after battle setup, so they do not get the battle setup event, but they do get the battle start event (sent by the engine to all stacks after deployment).

local ANIM = "h7/fx/h7wfDeploy" -- The original's vanishing smoke FX_Disappearing (chosen by Yu on 11-11)

local function core(u)
	local k = u:getCreature():getJsonKey()
	return k:find(":", 1, true) == nil or k:sub(1, 5) == "core:"
end

local function candidate(u)
	if u:isGhost() or not u:isAlive() or not core(u) then return nil end
	local slot = W.SLOT_OF[W.creatureKey(u)]
	if slot == nil then return nil end
	if W.mark(u, "h7WfSlot|" .. slot) == nil then return nil end
	local fac = W.factionOf(u)
	local units = fac and W.UNITS[fac]
	local key = units and units[slot]
	if key == nil then return nil end
	local level = W.levelFor(u, slot)
	if level == nil then return nil end
	if level == 5 and W.LV5[key] then key = W.LV5[key] end
	return key, level
end

function Script:onBattleSetup(server, battle, unit, other, payload)
	if candidate(unit) == nil then return end
	local list = battle:getUnitsIf(function(u) return candidate(u) ~= nil end)
	local shown, failed = {}, {}
	for _, O in ipairs(list) do
		local key, level = candidate(O)
		local G = W.swap(server, battle, O, key, level)
		if G ~= nil then
			shown[#shown + 1] = { hex = G:getPosition() }
		else
			failed[#failed + 1] = O
		end
	end
	if #shown > 0 then
		server:showBattleAnimation(battle, shown, ANIM, "", 1.0)
		server:refreshBattleUnits(battle)
	end
	for _, O in ipairs(failed) do
		server:appendLog(battle, {
			append = { "core.bonus.H7_LOG_W_H7C.description.2" },
			replaceStrings = { O:getCreature():getNameTextID(1) }
		})
	end
end

return Script
