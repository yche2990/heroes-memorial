local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Memorial Sanctum, Rune of Scattering (Fortress ultimate Rune of Scattering; a permanent bonus on the hero, passed to the whole army).
--- Original: when an enemy in your rune aura is attacked in melee, an extra 50% of the damage is split evenly among all other enemies in your rune aura.
--- Yu's decision: only the H7 memorial Rune Stones count (not the Highlands' own runes): a Rune Stone puts the hidden bonus H7_RUNE_AURA_H7C on stacks in its aura,
--- val = side of the Rune Stone + 1 (left/attacker 1, right/defender 2); a stack may carry two (overlapping auras of both sides).
--- After a friendly stack's melee attack (counterattacks included), if the main target is in its side's aura and took damage: take val% of the damage (default 50)
--- and split it evenly among the other enemies in its side's aura (physical damage, without Defense again; at least 1 each; invincible ones excluded).

local AURA = "H7_RUNE_AURA_H7C"
local ANIM = "C07SPA1"

local function inFriendlyAura(u, side)
	if u == nil then return false end
	local list = u:getBonuses({ type = AURA })
	for i = 1, list:size() do
		if list:getBonus(i):getVal() == side + 1 then return true end
	end
	return false
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or other == nil then return end
	local side = unit:getSide()
	if not inFriendlyAura(other, side) then return end
	local dealt = 0
	for _, t in ipairs(payload.targets or {}) do
		if t.unit ~= nil and t.unit:unitID() == other:unitID() then dealt = t.damage or 0 end
	end
	local extra = math.floor(dealt * (self.val or 50) / 100)
	if extra <= 0 then return end
	local victims = battle:getUnitsIf(function(u)
		return L.damageable(u) and u:getSide() ~= side and u:unitID() ~= other:unitID() and inFriendlyAura(u, side)
	end)
	if #victims == 0 then return end
	local each = math.max(1, math.floor(extra / #victims))
	local total = 0
	for _, v in ipairs(victims) do
		local d = L.hit(server, battle, v, each, ANIM, "")
		total = total + (d or 0)
	end
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append = { "core.bonus.H7_SANCTUM_H7C.description.6" },
		replaceStrings = {},
		replaceNumbers = { total, #victims }
	})
end

return Script
