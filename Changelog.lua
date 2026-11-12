-- The Changelog settings page: the version you have and what changed in each release (ChangelogData.lua, written by
-- tools/release_kureq_utils.py from the public CHANGELOG.md). Not a module.
local _, ns = ...

-- all releases as one wrapped text: "Version 1.5" in gold with its date in grey, then that release's notes
local function changelogText()
    local parts = {}
    for _, e in ipairs(ns.changelog or {}) do
        parts[#parts + 1] = ("|cffffd100Version %s|r  |cff9d9d9d%s|r\n\n%s"):format(e[1], e[2], e[3])
    end
    return #parts > 0 and table.concat(parts, "\n\n\n") or "No changes listed."
end

local panel = ns.AddSettingsPage("Changelog", "You have version " .. ns.version .. ". What changed in each release:")
local top = panel.y
local text = ns.Label(panel, changelogText())
table.insert(panel.refreshers, function()
    panel.y = top - math.max(text:GetStringHeight() or 0, 14) - 8 -- the text wraps to the page width and grows down
end)
