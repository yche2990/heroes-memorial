--- H6 Dynasty Weapon, Iron Feather level 5 "Burning Light": after each attack, the stack carrying it takes val% of the damage that attack dealt.
--- Parameter: anim (reflected damage effect)
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isInvincible() then return end
	local total = 0
	for _, t in ipairs(payload.targets or {}) do total = total + (t.damage or 0) end
	local back = math.floor(total * (self.val or 0) / 100)
	if back <= 0 then return end
	Lib.anim(server, battle, unit, self.anim)
	local dmg = Lib.damage(server, battle, unit, back)
	if (not dmg or dmg <= 0) and self.anim then server:refreshBattleUnits(battle) end
end

return Script
