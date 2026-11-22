local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Death Seal (H6 Ghost, Spectre)
---
--- Two bonuses, both using this script:
---   1. The Ghost's own (visible, role = "carrier"): after its own attack hits an enemy, it and the living enemies adjacent to it get the "Death Seal" status
---      (spell, lasting turns rounds). Living creatures only. The stack's health at that moment is recorded (hidden mark h6SealBase).
---   2. The battle-wide one (hidden, role = "zone"): whenever an action a sealed stack took part in ends, its current health is compared with the recorded one:
---      any extra (from healing, resurrection, life drain, regeneration... any source) is taken back by the seal's percentage, then recorded again.
---      This way no engine change is needed and any healing is reduced.
--- Parameters: role, spell, turns, animation, sound

local MARK = "H6_DEATH_SEAL_H6C"
local BASE = "h6SealBase"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if self.role ~= "carrier" then return end
	if not unit:isAlive() or payload.isCounter or (payload.attackIndex or 0) > 0 then return end
	local target = nil
	for _, t in ipairs(payload.targets or {}) do
		if t.unit then target = t.unit; break end
	end
	if target == nil or not L.real(target) or not battle:isHostile(unit, target) then return end
	local spell = L.spell(self.spell or "heroes-memorial.h6:h6DeathSealed")
	if spell == nil then return end
	local list = {}
	if L.isLiving(target) then list[1] = target end
	for _, u in ipairs(L.around(battle, target, function(u) return battle:isHostile(unit, u) and L.isLiving(u) end)) do list[#list + 1] = u end
	if #list == 0 then return end
	server:applySpellEffects(battle, unit, spell, list, 3, self.turns or 2, false)
	local hit = {}
	for _, u in ipairs(list) do
		if u:hasBonuses({ type = MARK }) then
			L.setMark(server, battle, u, BASE, u:getAvailableHealth(), self.turns or 2)
			hit[#hit + 1] = u
		end
	end
	L.show(server, battle, hit, self.animation, self.sound)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if self.role ~= "zone" then return end
	if not unit:isAlive() then return end
	local base = L.markValue(unit, BASE)
	if base == nil then return end
	local seal = unit:getBonuses({ type = MARK })
	if seal:size() == 0 then
		L.clearMark(server, battle, unit, BASE)
		return
	end
	local pct = 0
	for i = 1, seal:size() do pct = math.max(pct, seal:getBonus(i):getVal()) end
	local cur = unit:getAvailableHealth()
	if cur > base and pct > 0 then
		local cut = math.floor((cur - base) * pct / 100)
		if cut > 0 then
			local state = unit:copy()
			state:damage(cut)
			server:changeUnit(battle, state, 0)
			L.log(server, battle, MARK, 1, { L.name(unit) }, { cut })
			cur = cur - cut
		end
	end
	L.setMark(server, battle, unit, BASE, cur, 2)
end

return Script
