local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Expert Entangle (H7) (added by the spell h7Entangle at Expert through spells/h7EarthAttach, 3 rounds):
--- the stack takes val Earth damage each time it moves on its own (H7 original ignores resistance).
--- H7 creatures that move by "teleport" are unaffected; in VCMI they are flyers, so they are excluded by a creature list (Simurgh, Vampires etc.).

local TELEPORTERS = {
	h7AcademySimurgh = true,
	h7NecropolisVampire = true,
	h7NecropolisVampireLord = true,
	h7DungeonTroglodyte = true,
	h7DungeonChthonian = true,
	h7NeutralDarknessElemental = true,
	h7NeutralLightElemental = true,
}

local function teleporter(unit)
	local ok, key = pcall(function() return unit:getCreature():getJsonKey() end)
	if not ok or key == nil then return false end
	local short = tostring(key):match(":(.+)$") or tostring(key)
	return TELEPORTERS[short] == true
end

function Script:onAfterMove(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() or unit:isInvincible() then return end
	local amount = self.val or 0
	if amount <= 0 or teleporter(unit) then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7eEntangleTick", "h7/spell_entangle_tick.ogg", 1.0, true)
	local _, killed = server:damageUnit(battle, unit, amount)
	BattleLog.creaturesPerish(server, battle, unit, killed)
end

return Script
