local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 critical hits that incapacitate the target (batch B): Breath of Light (Gold Dragon); the same script is also registered as
--- Bash h7Bash, Sweeping Bash h7SweepingBash, Blinding Light h7BlindingLight, Mesmerize h7Mesmerize, Petrification h7Petrification.
---
--- After an attack (counterattacks and second strikes included) hits an enemy, a critical hit is rolled once (H7 critical hit = lucky strike; chance see h7StatusLib.crit);
--- on a critical hit, the targets hit cannot act or counterattack until the end of their next action (this hit is not counterattacked either), and cannot be incapacitated again for the following 2 rounds.
---
--- Parameters:
---   all      true: every enemy hit by this blow counts (breath, sweep); otherwise only the main target
---   fragile  true: ends when the target takes damage (Mesmerize, Petrification)
---   mind     true: mind-immune stacks are not affected (Mesmerize)
---   school   school: stacks immune to this school or to its negative spells are not affected (light / dark / earth)
---   spell    stacks immune to this original spell are not affected (e.g. stoneGaze, blind)
---   anim     animation (default h7/fx/h7Incap); sound (default PARALYZE)

function Script:onBattleStart(server, battle, unit, other, payload)
	L.ensureTracker(server, battle, unit)
end

function Script:eligible(battle, unit, t)
	if not L.canHit(battle, unit, t) then return false end
	if self.mind and t:hasBonuses({ type = "MIND_IMMUNITY" }) then return false end
	if self.mind and t:hasBonuses({ type = "H7_INDOMITABLE_H7C" }) then return false end   -- Indomitable: cannot be mesmerized
	if self.school and L.schoolImmune(t, self.school) then return false end
	if self.spell and L.spellImmune(t, self.spell) then return false end
	return true
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local victims = {}
	for i, entry in ipairs(payload.targets or {}) do
		local primary = (other ~= nil and entry.unit ~= nil and entry.unit:unitID() == other:unitID()) or (other == nil and i == 1)
		if (self.all or primary) and entry.unit ~= nil and (entry.damage or 0) > 0 and self:eligible(battle, unit, entry.unit) then
			table.insert(victims, entry.unit)
		end
	end
	if #victims == 0 then return end
	if not L.crit(server, battle, unit) then return end
	L.ensureTracker(server, battle, unit)
	for _, t in ipairs(victims) do
		L.incapacitate(server, battle, unit, t, {
			fragile = self.fragile, acting = payload.isCounter,
			showType = self.fragile and "H7_INCAP_FRAGILE_H7C" or "H7_INCAP_H7C",
			anim = self.anim, sound = self.sound, logN = self.fragile and 7 or 1
		})
	end
end

return Script
