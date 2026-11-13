-- Character notes shared with the guild (Notes.lua keeps them in KureqUtilsDB.notes.guilds). While "Share guild notes"
-- is on and the module is on, your notes (all but Private ones) go to the guild over addon messages, and guildmates'
-- come in. Only stars, note text and categories leave your client. Nothing is sent or taken while sharing is off.
--
-- Wire (GUILD channel, prefix KureqUtils): "1" (the protocol version) then either a whole message or "+id.i/n:" and
-- the i-th of n chunks of message id, under 255 bytes each. A message is tab-separated fields, each with control
-- characters, "%" and "|" written as %XX:
--   N  player, author, at, rating ("" for none), note, then a category name and its rrggbb color per category
--   D  player, author, at                         a deletion (or a note made Private), kept for good
--   H  since, then per author: name, count, newest at, digest of (player, at)s, passed-along count, over the notes
--      the sender holds updated after since (when they last cleared guild notes)
-- On login (and when sharing turns on) you send H; whoever holds notes you lack sends them (in shuffled order, and
-- anything someone else sends first is dropped from your queue), and answers with their own H when the summaries
-- differ. An author who sees their notes held as passed along sends them again themselves, which clears the mark.
-- Your own changes go out as you make them, under every character of yours the note went out under. Sends are paced,
-- one message every PACE seconds, and each is checked again (sharing, guild, Private, still current) before it goes.
local _, ns = ...
local N = ns.notes
local Y = {}
N.sync = Y

local PREFIX, VERSION = "KureqUtils", "1"
local CHUNK = 220 -- message bytes per chunk, with the header well under the 255 limit
local PACE, RETRY = 0.5, 3 -- seconds between sends; after Blizzard's throttle refused one
local MAX_CHUNKS, BUFFER_TTL = 64, 60 -- a longer message is dropped; so is one not finished within BUFFER_TTL seconds
local MAX_TEXT, MAX_CATS, MAX_PER_AUTHOR, MAX_NAME = 500, 10, 500, 48 -- caps from the design; bigger is dropped
local MAX_RECORDS, MAX_BYTES = 2500, 600000 -- per guild, every author together
local MAX_SENDER_NEW = 1500 -- new notes taken from one sender per hour, passed-along ones included
local HELLO_GAP, ANSWER_GAP = 60, 30 -- seconds between your summaries; between answers to one sender's
local MAX_TIME = 1e11 -- times in messages are whole seconds below this
local MOD = 2147483647 -- digests are below this
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle or 3
local CHANNEL_THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.ChannelThrottle or 8

local function send(msg)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD") end
end
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end

local function enc(s)
    return (tostring(s):gsub("[%c%%|]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function dec(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
local function hexColor(c)
    local function byte(v) return math.floor(math.min(1, math.max(0, tonumber(v) or 0)) * 255 + 0.5) end
    return ("%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end
-- s cut to at most n bytes, not inside a UTF-8 character
local function cut(s, n)
    if #s <= n then return s end
    while n > 0 and s:byte(n + 1) and s:byte(n + 1) >= 0x80 and s:byte(n + 1) < 0xC0 do n = n - 1 end
    return s:sub(1, n)
end
-- a whole number written in digits only, lo to hi; else nil
local function int(s, lo, hi)
    if type(s) ~= "string" or #s > 15 or not s:match("^%d+$") then return nil end
    local v = tonumber(s)
    if v >= lo and v <= hi then return v end
end
local function hash(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % MOD end
    return h
end

local function me()
    local name = N.unitName("player")
    return name and N.key(name), name
end
-- sharing runs: notes on, sharing on, in a guild whose name is known
function Y.active()
    return ns.db ~= nil and ns.IsOn("notes") and ns.db.notes.share == true and N.guildKey() ~= nil
end

-- Messages -----------------------------------------------------------------------------------------------------------

-- a note record as an N or D message; author is the author's name
local function encode(rec, author)
    local head = enc(rec.player) .. "\t" .. enc(author) .. "\t" .. (rec.at or 0)
    if rec.deleted then return "D\t" .. head end
    local parts = {"N\t" .. head, rec.rating or "", enc(rec.note or "")}
    for _, c in ipairs(rec.cats or {}) do
        parts[#parts + 1] = enc(c[1])
        parts[#parts + 1] = hexColor(c[2])
    end
    return table.concat(parts, "\t")
end
local function fields(body)
    local f = {}
    for field in (body .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = dec(field) end
    return f
end
local function goodName(s) return type(s) == "string" and s ~= "" and #s <= MAX_NAME end
-- an N or D message's record, or nil when anything is off (data only: nothing in it is ever run)
local function parse(body)
    local f = fields(body)
    local kind, player, author, at = f[1], f[2], f[3], int(f[4], 1, time() + N.AHEAD)
    if not (goodName(player) and goodName(author) and at) then return nil end
    local rec = {player = player, author = author, at = at}
    if kind == "D" then
        if #f ~= 4 then return nil end
        rec.deleted = true
        return rec
    end
    if kind ~= "N" or #f < 6 or (#f - 6) % 2 ~= 0 or (#f - 6) / 2 > MAX_CATS then return nil end
    if f[5] ~= "" then
        rec.rating = int(f[5], 0, 5)
        if not rec.rating then return nil end
    end
    if #f[6] > MAX_TEXT then return nil end
    rec.note, rec.cats = f[6], {}
    for i = 7, #f, 2 do
        local name, hex = f[i], f[i + 1]
        if name == "" or #name > 30 or not hex:match("^%x%x%x%x%x%x$") then return nil end
        rec.cats[#rec.cats + 1] = {name, {tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255}}
    end
    return rec
end

-- Your notes as shared (notes.shared[guild key][player key] = a record with authors, deleted when gone) -------------

-- what of entry is shared (nil when nothing: no stars, text or category)
local function sharedRecord(entry)
    local cats = {}
    for _, c in ipairs(N.categoryList()) do
        if entry.tags and entry.tags[c.id] and #cats < MAX_CATS then cats[#cats + 1] = {cut(c.name, 30), c.color} end
    end
    local note = cut(entry.note or "", MAX_TEXT)
    if not entry.rating and note == "" and #cats == 0 then return nil end
    return {player = entry.name, rating = entry.rating, note = note, cats = cats}
end
local function shareable(pkey) -- your note on pkey as it may be shared now, or nil
    local entry = N.people()[pkey]
    return entry and not entry.private and sharedRecord(entry) or nil
end
local function same(a, b) -- the shared parts match (times aside)
    if not (a and b) then return false end
    return encode({player = a.player, rating = a.rating, note = a.note, cats = a.cats, deleted = a.deleted}, "")
        == encode({player = b.player, rating = b.rating, note = b.note, cats = b.cats, deleted = b.deleted}, "")
end

-- The send queue: messages by key ("player key\tauthor key", or "H"), sent in order, one chunk per PACE. Each item
-- belongs to a guild; before every chunk it's checked to still be current and allowed, else dropped.
local queue, queued = {}, {} -- keys in order; key -> item {kind = "H" or "R", gkey, pkey, akey, at, msg}
local current -- {item, chunks, i} being sent
local pumping = false
local function enqueue(item)
    item.gkey = N.guildKey()
    if not queued[item.key] then queue[#queue + 1] = item.key end
    queued[item.key] = item
end
local function enqueueRecord(pkey, akey, name, rec)
    enqueue({key = pkey .. "\t" .. akey, kind = "R", pkey = pkey, akey = akey, at = rec.at, msg = encode(rec, name)})
end
local function clearQueue()
    wipe(queue)
    wipe(queued)
    current = nil
end
local function valid(item)
    if not Y.active() or N.guildKey() ~= item.gkey then return false end
    if item.kind == "H" then return true end
    if N.myChars()[item.akey] then -- yours: still the shared version, and still allowed to go
        local rec = (N.perGuild("shared") or {})[item.pkey]
        return rec ~= nil and rec.at == item.at and (rec.deleted or shareable(item.pkey) ~= nil)
    end
    local byAuthor = (N.guildStore() or {})[item.pkey]
    local rec = byAuthor and byAuthor[item.akey]
    return rec ~= nil and rec.at == item.at
end
local nextId -- message ids: seeded per session, so a reload doesn't reuse the last session's ids
local function chunks(msg)
    if #msg <= CHUNK + 8 then return {VERSION .. msg} end
    local parts = {}
    while #msg > 0 do
        local part = cut(msg, CHUNK)
        if part == "" then part = msg:sub(1, CHUNK) end -- not UTF-8: cut anywhere
        parts[#parts + 1] = part
        msg = msg:sub(#part + 1)
    end
    nextId = (nextId or time() + math.random(0, 9998)) % 9999 + 1
    for i, part in ipairs(parts) do parts[i] = VERSION .. "+" .. nextId .. "." .. i .. "/" .. #parts .. ":" .. part end
    return parts
end
local pump
local function schedule(seconds)
    if pumping then return end
    pumping = true
    C_Timer.After(seconds, pump)
end
function pump()
    pumping = false
    while not (current and valid(current.item)) do -- a dropped message's chunks stop; receivers let it expire
        current = nil
        local key = table.remove(queue, 1)
        if not key then return end
        local item = queued[key]
        queued[key] = nil
        if valid(item) then current = {item = item, chunks = chunks(item.msg), i = 1} end
    end
    local result = send(current.chunks[current.i])
    if result == THROTTLED or result == CHANNEL_THROTTLED then return schedule(RETRY) end -- the same chunk again
    current.i = current.i + 1
    if result ~= nil and result ~= 0 and result ~= true then current = nil end -- refused: skip the message
    if current and current.i > #current.chunks then current = nil end
    if current or queue[1] then schedule(PACE) end
end
Y.PACE, Y.RETRY = PACE, RETRY

-- Compares your notes with what you last shared with this guild and queues what changed: a new or edited note, and a
-- deletion for one deleted, emptied or made Private. Each goes out under every character of yours it went out under
-- before (a new one under this character), so a change on an alt reaches every copy.
local function scan()
    if not Y.active() then return end
    local mkey, myName = me()
    if not mkey then return end
    N.myChars()
    local shared, now, waiting = N.perGuild("shared", true), time(), false
    local function put(pkey, rec, old)
        -- stamped now, never ahead; a second change to a note within its second waits for the next scan
        if old and old.at >= now then waiting = true return end
        rec.at = now
        rec.authors = old and old.authors or {[mkey] = myName}
        shared[pkey] = rec
        for akey, name in pairs(rec.authors) do enqueueRecord(pkey, akey, name, rec) end
    end
    for pkey in pairs(N.people()) do
        local rec = shareable(pkey)
        if rec and not same(rec, shared[pkey]) then put(pkey, rec, shared[pkey]) end
    end
    for pkey, old in pairs(shared) do
        if not old.deleted and not shareable(pkey) then put(pkey, {player = old.player, deleted = true}, old) end
    end
    if queue[1] then schedule(PACE) end
    if waiting then Y.changed() end
end
-- a note changed: scan once things settle (typing changes it on every key)
local scanning = false
function Y.changed()
    if scanning or not Y.active() then return end
    scanning = true
    C_Timer.After(2, function()
        scanning = false
        scan()
    end)
end

-- Summaries ----------------------------------------------------------------------------------------------------------

-- every record you hold updated after since, by author key: {author key = {name, list = {{pkey, rec}, ...}}}; yours
-- from shared, under each of your characters it went out under
local function holdings(since)
    local chars = N.myChars()
    local by = {}
    local function add(akey, name, pkey, rec)
        if rec.at <= since then return end
        by[akey] = by[akey] or {name = name, list = {}}
        local list = by[akey].list
        list[#list + 1] = {pkey, rec}
    end
    for pkey, rec in pairs(N.perGuild("shared") or {}) do
        for akey, name in pairs(rec.authors or {}) do add(akey, name, pkey, rec) end
    end
    for pkey, byAuthor in pairs(N.guildStore() or {}) do
        for akey, rec in pairs(byAuthor) do
            if not chars[akey] then add(akey, rec.author, pkey, rec) end
        end
    end
    return by
end
local function summary(list) -- count, newest, digest, passed-along count
    local count, newest, digest, relayed = #list, 0, 0, 0
    for _, item in ipairs(list) do
        newest = math.max(newest, item[2].at)
        digest = (digest + hash(item[1] .. "\t" .. item[2].at)) % MOD
        if item[2].relay then relayed = relayed + 1 end
    end
    return count, newest, digest, relayed
end
local function since() return ns.db.notes.cleared[N.guildKey()] or 0 end
local lastHello = nil -- GetTime() of your last summary
local function hello(now) -- now: even within HELLO_GAP of the last one
    if not now and lastHello and GetTime() - lastHello < HELLO_GAP then return end
    lastHello = GetTime()
    local from = since()
    local parts = {"H", from}
    for _, h in pairs(holdings(from)) do
        parts[#parts + 1] = enc(h.name) .. "\t" .. table.concat({summary(h.list)}, "\t")
    end
    enqueue({key = "H", kind = "H", msg = table.concat(parts, "\t")})
    schedule(PACE)
end

-- a summary's authors, key -> {count, newest, digest, passed along}, and its since; nil when anything is off
local function parseHello(body)
    local f = fields(body)
    if (#f - 2) % 5 ~= 0 then return nil end
    local from = int(f[2], 0, MAX_TIME)
    if not from then return nil end
    local theirs = {}
    for i = 3, #f, 5 do
        local count = int(f[i + 1], 0, MAX_RECORDS * 10)
        local t = {count, int(f[i + 2], 0, MAX_TIME), int(f[i + 3], 0, MOD), int(f[i + 4], 0, count or 0)}
        if not (goodName(f[i]) and t[1] and t[2] and t[3] and t[4]) then return nil end
        theirs[N.key(f[i])] = t
    end
    return theirs, from
end

local answered = {} -- sender key -> GetTime() of the last answer to their summary
local function onHello(body, skey)
    if answered[skey] and GetTime() - answered[skey] < ANSWER_GAP then return end
    local theirs, from = parseHello(body)
    if not theirs then return end
    answered[skey] = GetTime()
    local sends, behind, author = {}, false, false
    local mine = holdings(from)
    local mkey = me()
    for akey, h in pairs(mine) do
        local count, newest, digest, relayed = summary(h.list)
        local t = theirs[akey]
        if akey == skey and relayed > 0 then author = true end -- tell the author: they send theirs again
        if akey == mkey and t and t[4] > 0 then -- they hold yours passed along: send them all yourself
            for _, item in ipairs(h.list) do sends[#sends + 1] = {item[1], akey, h.name, item[2]} end
        elseif not (t and t[1] == count and t[2] == newest and t[3] == digest) then -- they differ
            if t then behind = true end -- they may hold some you lack: ask them back
            if not (t and t[1] >= count and t[2] > newest) then -- unless they're plainly ahead, send
                local newer = {}
                for _, item in ipairs(h.list) do if not t or item[2].at > t[2] then newer[#newer + 1] = item end end
                -- they have the rest when the counts add up; else send all of this author's notes
                local list = (t and #newer > 0 and #newer + t[1] == count) and newer or h.list
                for _, item in ipairs(list) do sends[#sends + 1] = {item[1], akey, h.name, item[2]} end
            end
        end
    end
    for akey in pairs(theirs) do if not mine[akey] then behind = true end end
    -- shuffled, so guildmates answering the same summary send different notes first and drop what they hear
    for i = #sends, 2, -1 do
        local j = math.random(i)
        sends[i], sends[j] = sends[j], sends[i]
    end
    for _, s in ipairs(sends) do enqueueRecord(s[1], s[2], s[3], s[4]) end
    if behind or author then hello(author) end
    if queue[1] then schedule(PACE + math.random() * 2) end
end

-- Receiving ----------------------------------------------------------------------------------------------------------

local counts -- the guild store's totals {store, n, bytes, authors = {author key = n}}, counted when first needed
local admitted = {} -- sender key -> {since = GetTime(), n} new notes taken from them this hour
local function size(rec)
    local n = #rec.player + #rec.author + #(rec.note or "") + 40
    for _, c in ipairs(rec.cats or {}) do n = n + #c[1] + 8 end
    return n
end
local function tally(store)
    if counts and counts.store == store then return counts end
    counts = {store = store, n = 0, bytes = 0, authors = {}}
    for _, byAuthor in pairs(store) do
        for akey, rec in pairs(byAuthor) do
            counts.n, counts.bytes = counts.n + 1, counts.bytes + size(rec)
            counts.authors[akey] = (counts.authors[akey] or 0) + 1
        end
    end
    return counts
end

-- takes rec from sender: the author's own copy always replaces a passed-along one; else only a newer one counts
local function take(rec, skey)
    local akey, pkey = N.key(rec.author), N.key(rec.player)
    if N.myChars()[akey] then return end -- your own notes only change on your client
    -- heard: drop the same or an older copy from the queue (yours, as author, still go out)
    local q = queued[pkey .. "\t" .. akey]
    if q and q.at <= rec.at then
        queued[pkey .. "\t" .. akey] = nil
        for i, key in ipairs(queue) do if key == pkey .. "\t" .. akey then table.remove(queue, i) break end end
    end
    local notes, gkey = ns.db.notes, N.guildKey()
    if rec.at <= (notes.cleared[gkey] or 0) then return end -- from before you cleared guild notes
    local store = N.guildStore(true)
    local old = store[pkey] and store[pkey][akey]
    local direct = skey == akey
    if old and not (rec.at > old.at or (direct and old.relay)) then return end
    local c = tally(store)
    local bytes = c.bytes + size(rec) - (old and size(old) or 0)
    if bytes > MAX_BYTES then return end
    if not old then
        if (c.authors[akey] or 0) >= MAX_PER_AUTHOR or c.n >= MAX_RECORDS then return end
        local a = admitted[skey]
        if not a or GetTime() - a.since > 3600 then
            a = {since = GetTime(), n = 0}
            admitted[skey] = a
        end
        if a.n >= MAX_SENDER_NEW then return end
        a.n = a.n + 1
        c.n, c.authors[akey] = c.n + 1, (c.authors[akey] or 0) + 1
    end
    c.bytes = bytes
    rec.relay = not direct or nil
    store[pkey] = store[pkey] or {}
    store[pkey][akey] = rec
    if N.frame and N.frame:IsShown() then N.open() end -- redraw the window
end

local buffers = {} -- sender key -> {id, n, parts, at, gkey} of a chunked message coming in
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    -- only the GUILD channel, which the server carries only from your guild's members
    if prefix ~= PREFIX or channel ~= "GUILD" or type(text) ~= "string" or type(sender) ~= "string" then return end
    if not Y.active() or text:sub(1, 1) ~= VERSION or #text > 255 then return end -- another version's is left alone
    local skey = N.key(sender)
    if N.myChars()[skey] then return end -- your own, echoed back
    local gkey = N.guildKey()
    local body = text:sub(2)
    local id, i, n, part = body:match("^%+(%d+)%.(%d+)/(%d+):(.*)$")
    if id then
        id, i, n = int(id, 1, 9999), int(i, 1, MAX_CHUNKS), int(n, 2, MAX_CHUNKS)
        for key, b in pairs(buffers) do -- unfinished for too long, or from another guild: dropped
            if GetTime() - b.at > BUFFER_TTL or b.gkey ~= gkey then buffers[key] = nil end
        end
        if not (id and i and n and i <= n) then return end
        local buf = buffers[skey]
        if i == 1 then buf = {id = id, n = n, parts = {}, at = GetTime(), gkey = gkey} end
        -- a chunk of another message, or out of order (one went missing): the message is dropped
        if not buf or buf.id ~= id or buf.n ~= n or #buf.parts ~= i - 1 then buffers[skey] = nil return end
        buf.parts[i] = part
        buffers[skey] = buf
        if i < n then return end
        buffers[skey] = nil
        body = table.concat(buf.parts)
    end
    local kind = body:sub(1, 1)
    if kind == "H" then return onHello(body, skey) end
    local rec = parse(body)
    if rec then take(rec, skey) end
end)
ns.watch("Guild notes", listener)

-- Starting: once per guild after login, and when sharing or the module turns on --------------------------------------
local started -- the guild key sharing started for
-- forgets what's queued and coming in, and the counts (guild changed, sharing off, guild notes cleared)
function Y.reset()
    clearQueue()
    wipe(buffers)
    counts = nil
end
function Y.start()
    if not Y.active() then
        started = nil
        Y.reset()
        return
    end
    local gkey = N.guildKey()
    if started == gkey then return end
    if started then Y.reset() end -- another guild: nothing of the last one goes on
    started = gkey
    lastHello = nil
    counts = nil
    scan()
    hello()
end
local starter = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE"}) do
    starter:RegisterEvent(event)
end
starter:SetScript("OnEvent", function(_, event, login, reload)
    if event == "PLAYER_ENTERING_WORLD" and (login or reload) then started = nil end
    if started ~= (Y.active() and N.guildKey() or nil) then C_Timer.After(5, Y.start) end -- after the login settles
end)
ns.OnModuleChange("notes", function() Y.start() end)
function Y.cleared() counts = nil end
