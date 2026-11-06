local r = reaper
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local gfx = require "gfx2imgui"
local script_folder = string.gsub(debug.getinfo(1).source:match("@?(.*[\\|/])"),"\\","/")
local assets_folder = script_folder .. "assets/"
local settings_file = script_folder .. "settings.ini"
local settings = {
    scale = 0.5,
    labelsVisible = false,
    labelColor = {r = 1, g = 1, b = 0},
    handAlpha = 1
}

local function LoadSettings()
    local file = io.open(settings_file, "r")
    if not file then return end

    local values = {}
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
        if key then values[key] = value end
    end
    file:close()

    local savedScale = tonumber(values.scale)
    if savedScale then
        for _, validScale in ipairs({0.25, 0.375, 0.5, 0.75, 1}) do
            if savedScale == validScale then
                settings.scale = savedScale
                break
            end
        end
    end
    if values.labels_visible == "true" then
        settings.labelsVisible = true
    elseif values.labels_visible == "false" then
        settings.labelsVisible = false
    end
    for _, channel in ipairs({"r", "g", "b"}) do
        local value = tonumber(values["label_color_" .. channel])
        if value and value >= 0 and value <= 1 then
            settings.labelColor[channel] = value
        end
    end
    local handAlpha = tonumber(values.hand_alpha)
    if handAlpha and handAlpha >= 0 and handAlpha <= 1 then
        settings.handAlpha = handAlpha
    end
end

local function SaveSettings()
    local file, err = io.open(settings_file, "w")
    if not file then
        r.ShowConsoleMsg("DrumAnimView: Could not write " .. settings_file .. ": " .. tostring(err) .. "\n")
        return
    end

    local ok, writeError = file:write(
        "scale=", tostring(settings.scale), "\n",
        "labels_visible=", tostring(settings.labelsVisible), "\n",
        "label_color_r=", tostring(settings.labelColor.r), "\n",
        "label_color_g=", tostring(settings.labelColor.g), "\n",
        "label_color_b=", tostring(settings.labelColor.b), "\n",
        "hand_alpha=", tostring(settings.handAlpha), "\n"
    )
    local closeOk, closeError = file:close()
    if not ok or not closeOk then
        r.ShowConsoleMsg("DrumAnimView: Could not write " .. settings_file .. ": "
            .. tostring(writeError or closeError) .. "\n")
    end
end

LoadSettings()

local SCALE = settings.scale
local window = {
    width = 1600 * SCALE,
    height = 1000 * SCALE
}
local COLS = 4
local ROWS = 2
local HAND_MOVE_MIN_TIME = 0.01
local HAND_MOVE_MAX_TIME = 0.8
local HAND_MOVE_AFTER_HIT = 0.05
local HAND_HARD_LIFT = 120
local HAND_HIT_DURATION = 0.30
local HAND_HIT_DROP = 20
local HAND_GAP_TIMEOUT = 1.45
local HAND_FADE_IN_TIME = 0.25
local HAND_FADE_OUT_TIME = 0.5
local HAND_SCALE_MIN = 0.8
local HAND_SCALE_MAX = 1.0
local HAND_SCALE_TOP_Y = 236
local HAND_SCALE_BOTTOM_Y = 578
local HAND_POSITION_OFFSET_Y = -220
local slider = {
    offset = {
        x = 20,
        y = 60,
        w = 400,
        h = 40,
        value = 0.5,
        min = -1000,
        max = 1000,
        default = 0,
        displayScale = 1,
        unit = " ms"
    },
    handAlpha = {
        x = 20,
        y = 140,
        w = 400,
        h = 40,
        value = settings.handAlpha,
        min = 0,
        max = 1,
        default = 1,
        displayScale = 100,
        unit = "%"
    }
}
local scaleSelector = {
    x = 460,
    y = 60,
    buttonW = 200,
    buttonH = 40
}
local handLabels = {
    x = 680,
    y = 60,
    buttonW = 200,
    buttonH = 40,
    visible = settings.labelsVisible,
    color = settings.labelColor
}
local labelColorPicker = {
    x = 900,
    y = 60,
    buttonW = 235,
    buttonH = 40,
    open = false,
    dragChannel = nil
}

local scaleOptions = {  --Scale values are halved compared to its labels to compensate for texture sizes.
    {value = 0.25, label = "0.5x"},
    {value = 0.375, label = "0.75x"},
    {value = 0.5, label = "1x"},
    {value = 0.75, label = "1.5x"},
    {value = 1, label = "2x"}
}
local hands = {
    L = {
        posX = 0,
        posY = 0,
        restX = 555,
        restY = 600,
        offsetX = -30,
        hitOffsetY = -60,
        scale = HAND_SCALE_MAX,
        alpha = 0,
        frame = 7,
        visible = false
    },
    R = {
        posX = 0,
        posY = 0,
        restX = 690,
        restY = 600,
        offsetX = 30,
        hitOffsetY = -60,
        scale = HAND_SCALE_MAX,
        alpha = 0,
        frame = 7,
        visible = false
    }
}
local att_rel={
    kick= {20,85},
    hihat={70,40}
}
local draggingSlider = nil
local sliderMouseDown = false
local ignoreSliderDrag = false
local lastSliderClickTime = nil
local lastSliderClickX = nil
local lastSliderClickY = nil
local hihat={
    state=0.0,
    posX=280 * SCALE,
    posY=270* SCALE,
    curframe=0
}
local kick={
    state=0.0,
    posX=756 * SCALE,
    posY=626* SCALE,
    curframe=0
}
local noteHash = ""
local drumsTrack = nil
local animNotes = {}
local kickNotes = {}
local hhPedalNotes = {}
local lHandNotes = {}
local rHandNotes = {}
local drumMap = {
    [51] = {'FLOOR TOM', 'R',970,495},
    [50] = {'FLOOR TOM', 'L',950,506},
    [49] = {'TOM2', 'R',875,370},
    [48] = {'TOM2', 'L',850,370},
    [47] = {'TOM1', 'R',675,370},
    [46] = {'TOM1', 'L',625,370},
    [45] = {'CRASH2 SOFT', 'L',900,256},
    [44] = {'CRASH2 HARD', 'L',900,256},
    [43] = {'RIDE CYM', 'L',1060,494},
    [42] = {'RIDE CYM', 'R',1100,494},
    [41] = {'CRASH2 CHOKE', 'R',940,256},
    [40] = {'CRASH1 CHOKE', 'R',530,256},
    [39] = {'CRASH2 SOFT', 'R',940,256},
    [38] = {'CRASH2 HARD', 'R',940,256},
    [37] = {'CRASH1 SOFT', 'R',570,256},
    [36] = {'CRASH1 HARD', 'R',570,256},
    [35] = {'CRASH1 SOFT', 'L',530,256},
    [34] = {'CRASH1 HARD', 'L',530,256},
    [33] = {'PERCUSSION', 'L',810,494},
    [32] = {'PERCUSSION', 'R',820,494},
    [31] = {'HI-HAT', 'R',420,445},
    [30] = {'HI-HAT', 'L',380,445},
    [29] = {'SNARE RIM', 'R',645,550},
    [28] = {'SNARE RIM', 'L',585,550},
    [27] = {'SNARE HARD', 'R',645,536},
    [26] = {'SNARE HARD', 'L',585,536},
}

local function LoadImages()
    gfx.loadimg(0,assets_folder.."background.png")
    gfx.loadimg(1,assets_folder.."hihatOpenAnim.png")
    gfx.loadimg(2,assets_folder.."kickPedalAnim.png")
    gfx.loadimg(3,assets_folder.."handLAnim.png")
    gfx.loadimg(4,assets_folder.."handRAnim.png")
end

gfx.init("DrumAnimView", window.width, window.height)
LoadImages()

local function FindTrack(trackName)
	local numTracks = r.CountTracks(0)
	for i = 0, numTracks - 1 do
		local track = r.GetTrack(0, i)
		local _, currentTrackName = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
		if currentTrackName == trackName then
			return track
		end
	end
end

--makes a list of all the notes in the PART DRUMS track and stores them in animNotes table
local function updEvents()
    drumsTrack = FindTrack("PART DRUMS")
    if not drumsTrack or r.CountTrackMediaItems(drumsTrack) == 0 then
        noteHash = ""
        animNotes = {}
        kickNotes = {}
        hhPedalNotes = {}
        lHandNotes = {}
        rHandNotes = {}
        return
    end

    local item = r.GetTrackMediaItem(drumsTrack, 0)
    local take = item and r.GetActiveTake(item)
    if not take or not r.TakeIsMIDI(take) then
        noteHash = ""
        animNotes = {}
        kickNotes = {}
        hhPedalNotes = {}
        lHandNotes = {}
        rHandNotes = {}
        return
    end

    local _, hash = r.MIDI_GetHash(take, true)
    if noteHash == hash then return end

    noteHash = hash
    animNotes = {}
    kickNotes = {}
    hhPedalNotes = {}
    lHandNotes = {}
    rHandNotes = {}
    local _, noteCount = r.MIDI_CountEvts(take)
    for n = 0, noteCount - 1 do
        local _, _, _, startPpq, endPpq, _, pitch = r.MIDI_GetNote(take, n)
        local startTime = r.MIDI_GetProjTimeFromPPQPos(take, startPpq)
        local endTime = r.MIDI_GetProjTimeFromPPQPos(take, endPpq)
        if pitch == 25 then
            table.insert(hhPedalNotes, {pitch, startTime, endTime})
        elseif pitch == 24 or pitch == 23 then
            table.insert(kickNotes, {pitch, startTime})
        elseif pitch >= 26 and pitch <= 51 then
            table.insert(animNotes, {pitch, startTime})
        end
    end
end

local function eventLevel(time, startTime, endTime, attackMs, releaseMs)
    if time < startTime then return 0 end

    local attack = math.max(0, attackMs) / 1000
    local release = math.max(0, releaseMs) / 1000
    local endLevel = attack > 0 and math.min(1, (endTime - startTime) / attack) or 1

    if time <= endTime then
        if attack == 0 then return 1 end
        return math.min(1, (time - startTime) / attack)
    end

    if release == 0 then return 0 end
    return endLevel * math.max(0, 1 - (time - endTime) / release)
end

local function updatePedalStates(time)
    local kickLevel = 0
    local kickAttack = math.max(0, att_rel.kick[1]) / 1000
    for _, note in ipairs(kickNotes) do
        local startTime = note[2]
        local level = eventLevel(time, startTime - kickAttack, startTime, att_rel.kick[1], att_rel.kick[2])
        kickLevel = math.max(kickLevel, level)
    end
    kick.state = kickLevel

    local hihatLevel = 0
    for _, note in ipairs(hhPedalNotes) do
        local level = eventLevel(time, note[2], note[3]-att_rel.hihat[2]/1000, att_rel.hihat[1], att_rel.hihat[2])
        hihatLevel = math.max(hihatLevel, level)
    end
    hihat.state = hihatLevel
end

--process the notes to make a list of notes to animate per hand
local function updateNotes(time)
    lHandNotes = {}
    rHandNotes = {}
    for _, note in ipairs(animNotes) do
        local pitch = note[1]
        local mapping = drumMap[pitch]
        if mapping and mapping[3] and mapping[4] then
            local handNotes = mapping[2] == "L" and lHandNotes or rHandNotes
            table.insert(handNotes, {pitch, note[2]})
        end
    end

    local function updateHand(hand, notes)
        local previousNote = nil
        local nextNote = nil
        local followingNote = nil
        for _, note in ipairs(notes) do
            if note[2] <= time then
                if not previousNote or note[2] >= previousNote[2] then
                    previousNote = note
                end
            elseif not nextNote or note[2] < nextNote[2] then
                followingNote = nextNote
                nextNote = note
            elseif not followingNote or note[2] < followingNote[2] then
                followingNote = note
            end
        end

        local hitNote
        local isReturningAfterGap = not previousNote
            or (nextNote and nextNote[2] - previousNote[2] > HAND_GAP_TIMEOUT)
            or (not nextNote and time - previousNote[2] >= HAND_GAP_TIMEOUT)
        local restX = hand.restX * SCALE
        local restY = hand.restY * SCALE

        if nextNote then
            local nextMapping = drumMap[nextNote[1]]
            local targetX = nextMapping[3] * SCALE
            local targetY = nextMapping[4] * SCALE
            local startX, startY
            local sameSpot = false
            local liftAmount = 0
            if previousNote and not isReturningAfterGap then
                local previousMapping = drumMap[previousNote[1]]
                startX = previousMapping[3] * SCALE
                startY = previousMapping[4] * SCALE
                sameSpot = previousMapping[3] == nextMapping[3]
                    and previousMapping[4] == nextMapping[4]
            else
                startX = restX
                startY = restY
            end
            if not sameSpot and not isReturningAfterGap then
                if string.find(nextMapping[1], "HARD", 1, true) then
                    liftAmount = HAND_HARD_LIFT * SCALE
                elseif string.find(nextMapping[1], "TOM", 1, true) then
                    liftAmount = HAND_HARD_LIFT * SCALE
                end
            end

            local moveTime = HAND_MOVE_MIN_TIME
            if sameSpot then
                moveTime = 0
            elseif previousNote and not isReturningAfterGap then
                local noteInterval = nextNote[2] - previousNote[2]
                moveTime = math.min(HAND_MOVE_MAX_TIME,
                    math.max(HAND_MOVE_MIN_TIME, noteInterval - HAND_MOVE_AFTER_HIT))
            elseif isReturningAfterGap then
                moveTime = HAND_MOVE_MAX_TIME
            end
            local fadeInTime = isReturningAfterGap and HAND_FADE_IN_TIME or 0
            local movementStart
            if sameSpot then
                movementStart = nextNote[2]
            elseif previousNote and not isReturningAfterGap then
                movementStart = previousNote[2] + HAND_MOVE_AFTER_HIT
            else
                movementStart = nextNote[2] - moveTime
            end
            local fadeAlphaAtMovementStart = 0
            if isReturningAfterGap and previousNote then
                local previousMapping = drumMap[previousNote[1]]
                local fadeOutStart = previousNote[2] + HAND_GAP_TIMEOUT
                local fadeProgressAtMovementStart
                if HAND_FADE_OUT_TIME > 0 then
                    fadeProgressAtMovementStart = math.min(1, math.max(0,
                        (movementStart - fadeOutStart) / HAND_FADE_OUT_TIME))
                else
                    fadeProgressAtMovementStart = movementStart >= fadeOutStart and 1 or 0
                end
                startX = previousMapping[3] * SCALE
                    + (restX - previousMapping[3] * SCALE) * fadeProgressAtMovementStart
                startY = previousMapping[4] * SCALE
                    + (restY - previousMapping[4] * SCALE) * fadeProgressAtMovementStart
                fadeAlphaAtMovementStart = 1 - fadeProgressAtMovementStart
            end
            if time >= movementStart then
                local progress = moveTime > 0
                    and math.min(1, math.max(0,
                        (time - movementStart) / moveTime))
                    or 1
                local easedProgress = progress * progress * (3 - 2 * progress) --Smooth animation
                hand.posX = startX + (targetX - startX) * easedProgress
                hand.posY = startY + (targetY - startY) * easedProgress
                    - liftAmount * math.sin(math.pi * easedProgress)
                if isReturningAfterGap then  
                    local fadeInProgress = fadeInTime > 0
                        and math.min(1, math.max(0,
                            (time - movementStart) / fadeInTime))
                        or 1
                    hand.alpha = fadeAlphaAtMovementStart
                        + (1 - fadeAlphaAtMovementStart) * fadeInProgress
                else
                    hand.alpha = 1
                end
                hitNote = nextNote
            end
        end

        if not hitNote and previousNote then
            local idleTime = time - previousNote[2] - HAND_GAP_TIMEOUT
            local fadeProgress = HAND_FADE_OUT_TIME > 0
                and math.min(1, math.max(0, idleTime / HAND_FADE_OUT_TIME))
                or (idleTime >= 0 and 1 or 0)
            hand.alpha = 1 - fadeProgress
            if hand.alpha <= 0 then
                hand.visible = false
                hand.hitOffsetY = 0
                hand.frame = 7
                hand.posX = restX
                hand.posY = restY
                return
            end
            local previousMapping = drumMap[previousNote[1]]
            hand.posX = previousMapping[3] * SCALE
                + (restX - previousMapping[3] * SCALE) * fadeProgress
            hand.posY = previousMapping[4] * SCALE
                + (restY - previousMapping[4] * SCALE) * fadeProgress
            hitNote = previousNote
        elseif not hitNote then
            hand.alpha = 0
            hand.visible = false
            hand.hitOffsetY = 0
            hand.frame = 7
            hand.posX = restX
            hand.posY = restY
            return
        end

        local function hitAnimationDuration(note, neighbor)
            if not neighbor then return HAND_HIT_DURATION end
            return math.min(HAND_HIT_DURATION, math.abs(neighbor[2] - note[2]))
        end

        local animationNote = nil
        local animationDuration = HAND_HIT_DURATION
        if nextNote then
            local nextDuration = hitAnimationDuration(nextNote, previousNote)
            if time >= nextNote[2] - nextDuration / 2 then
                animationNote = nextNote
                animationDuration = nextDuration
            end
        end
        if not animationNote and previousNote then
            local previousDuration = hitAnimationDuration(previousNote, nextNote)
            if time <= previousNote[2] + previousDuration / 2 then
                animationNote = previousNote
                animationDuration = previousDuration
            end
        end

        if animationNote then
            local mapping = drumMap[animationNote[1]]
            local nextAnimationNote = animationNote == nextNote and followingNote or nextNote
            local nextMapping = nextAnimationNote and drumMap[nextAnimationNote[1]]
            local isSoftOrRim = string.find(mapping[1], "SOFT", 1, true)
                or string.find(mapping[1], "RIM", 1, true)
            local nextIsHard = nextMapping
                and string.find(nextMapping[1], "HARD", 1, true)
            local maxFrameIndex = isSoftOrRim and not nextIsHard and 2 or 7
            local halfHitDuration = animationDuration / 2
            if time <= animationNote[2] then
                local attackProgress = halfHitDuration > 0
                    and math.min(1, math.max(0,
                        1 - (animationNote[2] - time) / halfHitDuration))
                    or 1
                hand.frame = math.floor(maxFrameIndex * (1 - attackProgress) + 0.5)
            else
                local releaseProgress = halfHitDuration > 0
                    and math.min(1, math.max(0,
                        (time - animationNote[2]) / halfHitDuration))
                    or 1
                hand.frame = math.floor(maxFrameIndex * releaseProgress + 0.5)
            end
        end

        local hitPhase = animationNote and animationDuration > 0
            and (time - animationNote[2] + animationDuration / 2) / animationDuration
            or 1
        local hitStrength = math.max(0, 1 - math.abs(hitPhase * 2 - 1))
        hand.hitOffsetY = HAND_HIT_DROP * hitStrength
        --Hand height modifies scale to simulate distance from camera
        local heightScale = math.min(1, math.max(0,
            (hand.posY / SCALE - HAND_SCALE_TOP_Y) /
            (HAND_SCALE_BOTTOM_Y - HAND_SCALE_TOP_Y)))
        hand.scale = HAND_SCALE_MIN + (HAND_SCALE_MAX - HAND_SCALE_MIN) * heightScale
        hand.visible = true
    end

    updateHand(hands.L, lHandNotes)
    updateHand(hands.R, rHandNotes)
end

--draw current frame of part
local function DrawPart(image, part)
    local frame = part.curframe
    local dx = part.posX
    local dy = part.posY
    local w, h = gfx.getimgdim(image)
    local fw = w / COLS
    local fh = h / ROWS

    local sx = (frame % COLS) * fw
    local sy = math.floor(frame / COLS) * fh
    gfx.blit(
        image,SCALE,0,
        sx,sy,fw,fh,
        dx,dy,fw*SCALE,fh*SCALE
    )
end

local function DrawHand(image, hand)
    if not hand.visible then return end
    local char = {[3] = 'L', [4] = 'R'}
    local w, h = gfx.getimgdim(image)
    local fw, fh = w / COLS, h / ROWS
    local sx = (hand.frame % COLS) * fw
    local sy = math.floor(hand.frame / COLS) * fh
    local handScale = SCALE * hand.scale
    local drawW, drawH = fw * handScale, fh * handScale
    local drawX = hand.posX + hand.offsetX * SCALE - drawW / 2
    local drawY = hand.posY + (hand.hitOffsetY + HAND_POSITION_OFFSET_Y) * SCALE
    local alpha = hand.alpha * slider.handAlpha.value
    gfx.a = alpha
    gfx.blit(image, SCALE, 0, sx, sy, fw, fh, drawX, drawY, drawW, drawH)
    if handLabels.visible then
        gfx.x = drawX + (fw / 2 - 7) * handScale
        gfx.y = drawY + 340 * handScale
        gfx.set(handLabels.color.r, handLabels.color.g, handLabels.color.b, alpha)
        gfx.setfont(1,nil,math.max(1, math.floor(40 * handScale)),tonumber("b"))
        gfx.drawstr(char[image])
    end
    gfx.a = 1
end
--test sliders
local function UpdateSlider(curslider, mousePressed)

    local mx = gfx.mouse_x
    local my = gfx.mouse_y
    local control = slider[curslider]
    local x, y, w, h = control.x * SCALE, control.y * SCALE,
        control.w * SCALE, control.h * SCALE

    local hovered =
        mx >= x and
        mx <= x + w and
        my >= y and
        my <= y + h
        --vertically spaced filters for clarity
    local mouseDown = gfx.mouse_cap & 1 == 1

    if mousePressed and hovered then
        local clickTime = r.time_precise()
        local isDoubleClick = lastSliderClickTime
            and clickTime - lastSliderClickTime <= 0.35
            and math.abs(mx - lastSliderClickX) <= 12 * SCALE
            and math.abs(my - lastSliderClickY) <= 12 * SCALE

        if isDoubleClick then
            local currentSlider = slider[curslider]
            currentSlider.value = (currentSlider.default - currentSlider.min)
                / (currentSlider.max - currentSlider.min)
            ignoreSliderDrag = true
            lastSliderClickTime = nil
        else
            lastSliderClickTime = clickTime
            lastSliderClickX = mx
            lastSliderClickY = my
        end
    end

    if hovered and mouseDown and draggingSlider == nil and not ignoreSliderDrag then
        draggingSlider = curslider
    end

    if not mouseDown then
        draggingSlider = nil
        ignoreSliderDrag = false
    end

    if draggingSlider == curslider and not ignoreSliderDrag then
        local sv = (mx - x) / w

        if sv < 0 then sv = 0 end
        if sv > 1 then sv = 1 end

        slider[curslider].value = sv

    end
end

local function SetControlFont()
    gfx.setfont(1, "Arial", math.max(1, math.floor(32 * SCALE)))
end

local function DrawSlider(curslider, label)
    local control = slider[curslider]
    local x, y, w, h = control.x * SCALE, control.y * SCALE,
        control.w * SCALE, control.h * SCALE
    SetControlFont()
    gfx.set(0.2,0.2,0.2,1)
    gfx.rect(x, y, w, h, 1)

    local knob_x = x + control.value * w

    gfx.set(0.9,0.9,0.9,1)
    gfx.circle(knob_x, y + h / 2, 16 * SCALE, 1)

    local currentSlider = control
    local value = currentSlider.min + currentSlider.value * (currentSlider.max - currentSlider.min)
    local text = label .. string.format(": %.0f%s", value * currentSlider.displayScale, currentSlider.unit)
    local _, textH = gfx.measurestr(text)
    gfx.x = x
    gfx.y = y - textH - 2 * SCALE
    gfx.drawstr(text)
end

local function SetScale(scale)
    if SCALE == scale then return end

    SCALE = scale
    settings.scale = scale
    SaveSettings()
    window.width = math.floor(1600 * SCALE)
    window.height = math.floor(1000 * SCALE)
    hihat.posX = 280 * SCALE
    hihat.posY = 270 * SCALE
    kick.posX = 756 * SCALE
    kick.posY = 626 * SCALE

    gfx.quit()
    gfx.init("DrumAnimView", window.width, window.height)
    LoadImages()
end

local function UpdateScaleSelector(mousePressed)
    if not mousePressed then return end

    local mx = gfx.mouse_x
    local my = gfx.mouse_y
    local x, y, buttonW, buttonH = scaleSelector.x * SCALE,
        scaleSelector.y * SCALE, scaleSelector.buttonW * SCALE,
        scaleSelector.buttonH * SCALE
    if mx < x or mx > x + buttonW or my < y or my > y + buttonH then
        return
    end

    local menuItems = {}
    local selectedOption = nil
    for index, option in ipairs(scaleOptions) do
        local label = option.label
        if SCALE == option.value then
            label = "!" .. label
            selectedOption = index
        end
        menuItems[index] = label
    end
    local selection = gfx.showmenu(table.concat(menuItems, "|"))
    if selection > 0 and selection ~= selectedOption then
        SetScale(scaleOptions[selection].value)
    end
end

local function DrawScaleSelector()
    local x, y, buttonW, buttonH = scaleSelector.x * SCALE,
        scaleSelector.y * SCALE, scaleSelector.buttonW * SCALE,
        scaleSelector.buttonH * SCALE
    SetControlFont()
    gfx.set(0.2, 0.2, 0.2, 1)
    gfx.rect(x, y, buttonW, buttonH, 1)
    gfx.set(0.9, 0.9, 0.9, 1)
    local selectedLabel = scaleOptions[2].label
    for _, option in ipairs(scaleOptions) do
        if SCALE == option.value then
            selectedLabel = option.label
            break
        end
    end
    local text = "Scale:  " .. selectedLabel
    local textW, textH = gfx.measurestr(text)
    gfx.x = x + (buttonW - textW) / 2
    gfx.y = y + (buttonH - textH) / 2
    gfx.drawstr(text)
end

local function UpdateHandLabels(mousePressed)
    if not mousePressed then return end

    local mx = gfx.mouse_x
    local my = gfx.mouse_y
    local x, y, buttonW, buttonH = handLabels.x * SCALE,
        handLabels.y * SCALE, handLabels.buttonW * SCALE,
        handLabels.buttonH * SCALE
    if mx >= x and mx <= x + buttonW and my >= y and my <= y + buttonH then
        handLabels.visible = not handLabels.visible
        settings.labelsVisible = handLabels.visible
        SaveSettings()
    end
end

local function DrawHandLabelsToggle()
    local x, y, buttonW, buttonH = handLabels.x * SCALE,
        handLabels.y * SCALE, handLabels.buttonW * SCALE,
        handLabels.buttonH * SCALE
    SetControlFont()
    gfx.set(0.2, 0.2, 0.2, 1)
    gfx.rect(x, y, buttonW, buttonH, 1)
    gfx.set(0.9, 0.9, 0.9, 1)
    local text = "Labels: " .. (handLabels.visible and "On" or "Off")
    local textW, textH = gfx.measurestr(text)
    gfx.x = x + (buttonW - textW) / 2
    gfx.y = y + (buttonH - textH) / 2
    gfx.drawstr(text)
end

local labelColorChannels = {"r", "g", "b"}
local labelColorChannelNames = {"R", "G", "B"}

local function GetLabelColorChannelRect(channel)
    local x = (labelColorPicker.x + 120) * SCALE
    local y = (labelColorPicker.y + 52 + (channel - 1) * 38) * SCALE
    local w = 220 * SCALE
    local h = 24 * SCALE
    return x, y, w, h
end

local function SetLabelColorChannel(channel, mouseX)
    local x, _, w = GetLabelColorChannelRect(channel)
    local value = math.max(0, math.min(1, (mouseX - x) / w))
    handLabels.color[labelColorChannels[channel]] = value
    settings.labelColor[labelColorChannels[channel]] = value
end

local function UpdateLabelColorPicker(mousePressed, mouseDown)
    if not mouseDown then
        labelColorPicker.dragChannel = nil
    elseif labelColorPicker.dragChannel then
        SetLabelColorChannel(labelColorPicker.dragChannel, gfx.mouse_x)
    end
    if not mousePressed then return end

    local mx = gfx.mouse_x
    local my = gfx.mouse_y
    local buttonX, buttonY = labelColorPicker.x * SCALE,
        labelColorPicker.y * SCALE
    if mx >= buttonX and mx <= buttonX + labelColorPicker.buttonW * SCALE
        and my >= buttonY and my <= buttonY + labelColorPicker.buttonH * SCALE then
        labelColorPicker.open = not labelColorPicker.open
        return
    end
    if not labelColorPicker.open then return end

    for channel = 1, #labelColorChannels do
        local x, y, w, h = GetLabelColorChannelRect(channel)
        if mx >= x and mx <= x + w and my >= y and my <= y + h then
            labelColorPicker.dragChannel = channel
            SetLabelColorChannel(channel, mx)
            return
        end
    end
end

local function DrawLabelColorPicker()
    local x, y = labelColorPicker.x * SCALE, labelColorPicker.y * SCALE
    local buttonW, buttonH = labelColorPicker.buttonW * SCALE,
        labelColorPicker.buttonH * SCALE
    SetControlFont()
    gfx.set(0.2, 0.2, 0.2, 1)
    gfx.rect(x, y, buttonW, buttonH, 1)
    gfx.set(0.9, 0.9, 0.9, 1)
    local buttonText = "Label Color"
    local textW, textH = gfx.measurestr(buttonText)
    gfx.x = x + 12 * SCALE
    gfx.y = y + (buttonH - textH) / 2
    gfx.drawstr(buttonText)
    gfx.set(handLabels.color.r, handLabels.color.g, handLabels.color.b, 1)
    gfx.rect(x + buttonW - 44 * SCALE, y + 8 * SCALE, 32 * SCALE, 24 * SCALE, 1)

    if not labelColorPicker.open then return end

    local panelX, panelY = x, (labelColorPicker.y + 44) * SCALE
    local panelW, panelH = 420 * SCALE, 160 * SCALE
    gfx.set(0.12, 0.12, 0.12, 0.96)
    gfx.rect(panelX, panelY, panelW, panelH, 1)
    SetControlFont()
    for channel = 1, #labelColorChannels do
        local trackX, trackY, trackW, trackH = GetLabelColorChannelRect(channel)
        local key = labelColorChannels[channel]
        gfx.set(0.9, 0.9, 0.9, 1)
        gfx.x = x + 12 * SCALE
        local _, channelTextH = gfx.measurestr(labelColorChannelNames[channel])
        gfx.y = trackY + (trackH - channelTextH) / 2
        gfx.drawstr(labelColorChannelNames[channel])
        for segment = 0, 31 do
            local value = segment / 31
            local red = key == "r" and value or handLabels.color.r
            local green = key == "g" and value or handLabels.color.g
            local blue = key == "b" and value or handLabels.color.b
            gfx.set(red, green, blue, 1)
            gfx.rect(trackX + trackW * segment / 32, trackY,
                trackW / 32 + 1, trackH, 1)
        end
        gfx.set(1, 1, 1, 1)
        gfx.circle(trackX + handLabels.color[key] * trackW,
            trackY + trackH / 2, 5 * SCALE, 1)
        gfx.set(0.7, 0.7, 0.7, 1)
        gfx.x = trackX + trackW + 8 * SCALE
        gfx.y = trackY
        gfx.drawstr(string.format("%d", math.floor(handLabels.color[key] * 255 + 0.5)))
    end
end

local function loop()
    updEvents()
    local playstate = r.GetPlayState()
    if playstate == 1 then
        CurPos = r.GetPlayPosition()
    else
        CurPos = r.GetCursorPosition()
    end

    local offset = slider.offset.min
        + slider.offset.value * (slider.offset.max - slider.offset.min)
    CurPos = CurPos + (offset / 1000)
    updatePedalStates(CurPos)

    if not drumsTrack or r.CountTrackMediaItems(drumsTrack) == 0 then
        gfx.set(1,0,0,1)
        gfx.x = 20
        gfx.y = 20
        gfx.drawstr("No PART DRUMS track found or no items in track")
    end
    updateNotes(CurPos)
    gfx.blit(0,SCALE,0,0,0,1600,1000,0,0)

    local mouseDown = gfx.mouse_cap & 1 == 1
    local mousePressed = mouseDown and not sliderMouseDown
    local wasDraggingHandAlpha = draggingSlider == "handAlpha"
    UpdateSlider("offset", mousePressed)
    UpdateSlider("handAlpha", mousePressed)
    if wasDraggingHandAlpha and not mouseDown then
        settings.handAlpha = slider.handAlpha.value
        SaveSettings()
    end
    UpdateScaleSelector(mousePressed)
    UpdateHandLabels(mousePressed)
    local wasDraggingLabelColor = labelColorPicker.dragChannel ~= nil
    UpdateLabelColorPicker(mousePressed, mouseDown)
    if wasDraggingLabelColor and not mouseDown then
        SaveSettings()
    end
    sliderMouseDown = mouseDown
    kick.curframe = math.floor(kick.state * 7 + 0.5)
    hihat.curframe = math.floor(hihat.state * 7 + 0.5)
    DrawPart(1,hihat)       --param 1 = image idx, param 2 = part 
    DrawPart(2,kick)
    DrawHand(3, hands.L)    --same params as DrawPart, but using hands
    DrawHand(4, hands.R)
    DrawSlider("offset", "Offset")
    DrawSlider("handAlpha", "Hand Opacity")
    DrawScaleSelector()
    DrawHandLabelsToggle()
    DrawLabelColorPicker()
    
    gfx.update()
        if gfx.getchar() ~= -1 then
            r.defer(loop)
    end
end

r.defer(loop)