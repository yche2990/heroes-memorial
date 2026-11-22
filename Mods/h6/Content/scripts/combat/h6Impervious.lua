local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Impervious (H6 Cyclops, Wrathful Cyclops)
---
--- Attack damage taken (counterattacks included) is deferred: right after the hit the damage is restored (killed creatures stand up again) and booked as "damage owed"
--- (shown on H6_IMPERVIOUS_H6C), settled at once at the start of the next round. A whole stack killed in one blow cannot be restored. Parameter: animation
---
--- "Already restored" convention (review A5 2026-11-08, see the healedValue section of combat/h6Lib): only restores the part other scripts (shields, Sacrifice...) have not restored yet,
--- and only books that part as debt; then records the amount in a MEMORIAL_MARK on the target (stacking "h6Healed|<attacker id>"); onBeforeAttacked clears these marks.
--- Several restoring effects together restore at most one share of the same hit.
--- If it is invincible when the debt is settled at round start (swallowed by the Abyssal Worm etc.), the debt is still settled, as damage "inside" (L.rawHit, review B8)

local DEBT = "h6Debt"

local function setDebt(server, battle, unit, v)
	L.removeByStacking(server, battle, unit, "H6_IMPERVIOUS_H6C", DEBT)
	L.clearMark(server, battle, unit, DEBT)
	if v > 0 then
		L.setMark(server, battle, unit, DEBT, v)
		L.addBonus(server, battle, unit, { type = "H6_IMPERVIOUS_H6C", val = v, stacking = DEBT }, false)
	end
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	L.clearHealed(server, battle, unit)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = self:ownEntry(unit, payload)
	local d = entry and L.unhealed(unit, other, entry.damage) or 0
	if d <= 0 then return end
	server:healUnit(battle, unit, d, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	L.addHealed(server, battle, unit, other, d)
	setDebt(server, battle, unit, (L.markValue(unit, DEBT) or 0) + d)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

function Script:onRoundStart(server, battle, unit)
	local d = L.markValue(unit, DEBT)
	if d == nil or not unit:isAlive() then return end
	setDebt(server, battle, unit, 0)
	-- Review B8: L.hit does nothing against invincibility, so the debt would be lost; the debt is damage already taken, so it is settled with rawHit
	local dealt, killed = L.rawHit(server, battle, unit, d, self.animation, self.sound)
	L.log(server, battle, "H6_IMPERVIOUS_H6C", 1, { L.name(unit) }, { dealt or 0, killed or 0 })
end

return Script
