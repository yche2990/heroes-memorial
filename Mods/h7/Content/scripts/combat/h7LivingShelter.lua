local Base = require("combat/combatScript")
local L = require("combat/h7dLib")
local Z = require("combat/h7dZones")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Treant, Ancient Treant: Living Shelter
---
--- Original: active ability, Defense +10, provides cover for allies; enemies walking next to it are stopped, allies may pass through it; lasts until it moves or attacks.
--- In this pack: raised when it chooses "Defend" (the AI uses it too), Defense +def (scaled by level 7, original 10), and the adjacent free hexes block enemies
--- (enemies entering those hexes stop, and pathfinding does not cross them; its own side is unaffected, see combat/h7dZones), until this stack moves or attacks on its own (shots included, counterattacks not).
--- Allies passing through the Treant and ranged cover cannot be done and are not included.
--- Display: H7_SHELTER_H7C (value = Defense bonus); the Defense bonus is a hidden PRIMARY_SKILL (stacking h7Shelter).
--- Parameter: def

local DEF_TAG = "h7Shelter"

local function off(server, battle, unit)
	if not unit:hasBonuses({ type = Z.SHELTER }) then return false end
	Z.removeSideShelters(server, battle, unit:getSide())
	L.clearMark(server, battle, unit, Z.SHELTER, DEF_TAG)
	L.clearMark(server, battle, unit, "PRIMARY_SKILL", DEF_TAG)
	Z.refreshShelters(server, battle)
	return true
end

function Script:onDefend(server, battle, unit, other, payload)
	if not L.isReal(unit) then return end
	local def = self.def or 7
	L.setMark(server, battle, unit, "PRIMARY_SKILL", def, nil, DEF_TAG, true, { subtype = "primarySkill.defence" })
	L.setMark(server, battle, unit, Z.SHELTER, def, nil, DEF_TAG, false, { icon = "h7/abilities/h7LivingShelter" })
	Z.ensureCarrier(server, battle, unit, "h7LivingShelterZone", "h7LivingShelterZone")
	Z.refreshShelters(server, battle)
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7dShelter", "", 1.0, true)
	server:refreshBattleUnits(battle)
	L.log(server, battle, 11, { L.name(unit) }, { def })
end

function Script:onBeforeMove(server, battle, unit, other, payload)
	if battle:getTacticDistance() > 0 then return end
	off(server, battle, unit)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter then return end
	off(server, battle, unit)
end

function Script:onDeath(server, battle, unit, other, payload)
	off(server, battle, unit)
end

return Script
