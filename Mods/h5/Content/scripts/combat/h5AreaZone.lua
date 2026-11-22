local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 creatures: hidden area script (passed BATTLE_WIDE to every stack on the field by creatures with Lizard Bite, Shield Wall, Fright Aura or Searing Aura).
--- Handles: recording how many hexes each stack walked in this action (for Shield Wall); settling Lizard Bite after an ally attacks; settling Searing Aura before an enemy acts;
--- recalculating Fright Aura and adjacent-ally auras after each action (h5AllyAura: Magic Resist Aura, Aura of Bravery, Leadership, Protect Ally). Real stacks only (arrow towers excepted).

local function lizard() return require("heroes-memorial.h5:combat/h5LizardBite") end
local function searing() return require("heroes-memorial.h5:combat/h5SearingAura") end
local function fright() return require("heroes-memorial.h5:combat/h5FrightAura") end
local function allyAura() return require("heroes-memorial.h5:combat/h5AllyAura") end

local function present(battle, name)
	local found = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() and A.ability(u, name) ~= nil end)
	return #found > 0
end

local function acts(server, battle, unit)
	if battle:getTacticDistance() > 0 then return end
	if present(battle, "h5SearingAura") then searing().onEnemyActs(server, battle, unit) end
end

function Script:onBeforeMove(server, battle, unit)
	if unit:isTurret() then return end
	acts(server, battle, unit)
	A.beforeMove(server, battle, unit)
end

function Script:onAfterMove(server, battle, unit)
	if unit:isTurret() then return end
	A.afterMove(server, battle, unit)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	acts(server, battle, unit)
end

function Script:onWait(server, battle, unit) acts(server, battle, unit) end
function Script:onDefend(server, battle, unit) acts(server, battle, unit) end
function Script:onUnitSpellcast(server, battle, unit) acts(server, battle, unit) end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not present(battle, "h5LizardBite") then return end
	local target = A.primary(payload, other)
	if target ~= nil and battle:isHostile(unit, target) then
		lizard().onAllyAttack(server, battle, unit, target, 50)
	end
end

function Script:onActionFinished(server, battle, unit, other)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	A.clearMove(server, battle, unit)
	searing().onActionDone(server, battle, unit)
	if present(battle, "h5FrightAura") then fright().refresh(server, battle) end
	if present(battle, "h5AllyAura") then allyAura().refresh(server, battle) end
end

return Script
