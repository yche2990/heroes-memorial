local Base = require("combat/combatScript")
local Lib = require("heroes-memorial.h7:spells/h7SWLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Ice Strike (H7): put on a friendly stack by the spell h7IceStrike (heroes-memorial:h5Attach) for 3 rounds.
--- Each time the stack's attacks or counterattacks hit enemies, every enemy that took damage takes val extra Water damage
--- (hidden spell h7AbIceStrikeHit; the engine applies school reduction, Water immunity and magic resistance and plays the hit effect).
--- chill = true (Expert): enemies hit are also slowed by 3 for 3 rounds (hidden spell h7AbWaterChill).
--- Parameters: val (damage computed from Spell Power at cast time), chill

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local dmg = self.val or 0
	if dmg <= 0 or payload == nil or payload.targets == nil then return end
	local hit = {}
	for _, t in ipairs(payload.targets) do
		local u = t.unit
		if u ~= nil and u:isAlive() and not u:isGhost() and (t.damage or 0) > 0
			and u:getSide() ~= unit:getSide() and not u:isInvincible() then
			table.insert(hit, u)
		end
	end
	if #hit == 0 then return end
	local spell = Lib.spell("h7AbIceStrikeHit")
	if spell ~= nil then server:castSpell(battle, unit, spell, hit, dmg) end
	if self.chill then
		local chill = Lib.spell("h7AbWaterChill")
		local alive = {}
		for _, u in ipairs(hit) do
			if u:isAlive() then table.insert(alive, u) end
		end
		if chill ~= nil and #alive > 0 then server:castSpell(battle, unit, chill, alive, 0) end
	end
end

return Script
