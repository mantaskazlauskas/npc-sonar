--------------------------------------------------------------------------------
-- NPC Sonar -- flat widget kit
--
-- Every widget is a BackdropTemplate frame with a 1px border painted from a
-- plain white texture, so colours are all in one palette below and nothing
-- depends on Blizzard's panel art. Shared by UI.lua and MarkButton.lua.
--------------------------------------------------------------------------------

local _, ns = ...

local S = {}
ns.Style = S

local WHITE = "Interface\\Buttons\\WHITE8x8"

S.C = {
    bg          = { 0.055, 0.06, 0.075, 0.96 },
    header      = { 0.08, 0.085, 0.105, 1 },
    panel       = { 0.10, 0.105, 0.13, 1 },
    hover       = { 0.15, 0.16, 0.20, 1 },
    border      = { 0.20, 0.21, 0.26, 1 },
    accent      = { 0.25, 0.70, 0.95, 1 },
    accentHover = { 0.38, 0.79, 1.00, 1 },
    text        = { 0.93, 0.94, 0.96, 1 },
    muted       = { 0.55, 0.57, 0.63, 1 },
    good        = { 0.32, 0.85, 0.48, 1 },
}
local C = S.C

function S.Backdrop(f, bg, border)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border or C.border))
end

function S.Font(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, flags or "")
    fs:SetTextColor(unpack(color or C.text))
    return fs
end

-- Small upper-case section caption.
function S.Caption(parent, text)
    local fs = S.Font(parent, 10, C.muted)
    fs:SetText(text:upper())
    return fs
end

--------------------------------------------------------------------------------
-- Buttons. kind = "primary" (accent fill) or "secondary" (panel fill).
-- `template` mixes in another template (e.g. SecureActionButtonTemplate).

local function PaintButton(b)
    local enabled = b:IsEnabled()
    local primary = b.kind == "primary"
    local bg
    if not enabled then
        bg = C.panel
    elseif primary then
        bg = b.hovered and C.accentHover or C.accent
    else
        bg = b.hovered and C.hover or C.panel
    end
    b:SetBackdropColor(unpack(bg))
    b:SetBackdropBorderColor(unpack((primary and enabled) and bg or (b.hovered and enabled) and C.accent or C.border))
    if not enabled then
        b.label:SetTextColor(unpack(C.muted))
    elseif primary then
        b.label:SetTextColor(0.03, 0.06, 0.09, 1)
    else
        b.label:SetTextColor(unpack(C.text))
    end
end

function S.Button(parent, text, width, height, kind, name, template)
    local tpl = template and (template .. ", BackdropTemplate") or "BackdropTemplate"
    local b = CreateFrame("Button", name, parent, tpl)
    b:SetSize(width, height or 26)
    b.kind = kind or "secondary"
    S.Backdrop(b, C.panel)
    b.label = S.Font(b, 12, C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:HookScript("OnEnter", function(self) self.hovered = true; PaintButton(self) end)
    b:HookScript("OnLeave", function(self) self.hovered = false; PaintButton(self) end)
    b:HookScript("OnEnable", PaintButton)
    b:HookScript("OnDisable", PaintButton)
    b.Paint = PaintButton
    function b:SetLabel(t) self.label:SetText(t) end
    PaintButton(b)
    return b
end

--------------------------------------------------------------------------------
-- Toggle: a small box that fills with the accent colour, plus its label. The
-- whole row is the hit area.

function S.Toggle(parent, text, onChange)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(18)

    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    S.Backdrop(box, C.panel)

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(unpack(C.accent))

    local label = S.Font(row, 12, C.text)
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(text)
    row:SetWidth(16 + 8 + label:GetStringWidth() + 4)

    function row:SetChecked(on)
        self.checked = on and true or false
        fill:SetShown(self.checked)
        box:SetBackdropBorderColor(unpack(self.checked and C.accent or C.border))
    end
    row:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        onChange(self.checked)
    end)
    row:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1, 1) end)
    row:SetScript("OnLeave", function() label:SetTextColor(unpack(C.text)) end)
    row:SetChecked(false)
    return row
end

--------------------------------------------------------------------------------
-- Text input with a placeholder and an accent border while focused.

function S.Input(parent, width, height, placeholder)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, height or 26)
    e:SetAutoFocus(false)
    e:SetFont(STANDARD_TEXT_FONT, 12, "")
    e:SetTextColor(unpack(C.text))
    e:SetTextInsets(8, 8, 0, 0)
    S.Backdrop(e, C.panel)

    local hint = S.Font(e, 12, C.muted)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(placeholder or "")

    local function Update(self)
        hint:SetShown(self:GetText() == "" and not self:HasFocus())
    end
    e:HookScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(unpack(C.accent)); Update(self)
    end)
    e:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(C.border)); Update(self)
    end)
    e:HookScript("OnTextChanged", Update)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end
