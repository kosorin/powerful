local capi = {
    client = client,
}
local awful = require("awful")
local gtable = require("gears.table")
local gmatcher = require("gears.matcher")
local pbinding, mod, btn = require("powerful.binding").require()
local tree = require("powerful.tree")
local help_popup = require("powerful.help_popup")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi


local mouse_label_icon = beautiful.help_mouse_label_icon or "🖱️"

local help = {
    default_labels = {
        [btn.left]            = mouse_label_icon .. " Left",
        [btn.middle]          = mouse_label_icon .. " Middle",
        [btn.right]           = mouse_label_icon .. " Right",
        [btn.wheel_up]        = mouse_label_icon .. " Wheel Up",
        [btn.wheel_down]      = mouse_label_icon .. " Wheel Down",
        [btn.wheel_left]      = mouse_label_icon .. " Wheel Left",
        [btn.wheel_right]     = mouse_label_icon .. " Wheel Right",
        [btn.extra_back]      = mouse_label_icon .. " Back",
        [btn.extra_forward]   = mouse_label_icon .. " Forward",
        Control               = "Ctrl",
        Mod1                  = "Alt",
        ISO_Level3_Shift      = "Alt Gr",
        Mod4                  = "Super",
        Insert                = "Ins",
        Delete                = "Del",
        Next                  = "PgDn",
        Prior                 = "PgUp",
        Left                  = "←",
        Up                    = "↑",
        Right                 = "→",
        Down                  = "↓",
        KP_End                = "Num1",
        KP_Down               = "Num2",
        KP_Next               = "Num3",
        KP_Left               = "Num4",
        KP_Begin              = "Num5",
        KP_Right              = "Num6",
        KP_Home               = "Num7",
        KP_Up                 = "Num8",
        KP_Prior              = "Num9",
        KP_Insert             = "Num0",
        KP_Delete             = "Num.",
        KP_Divide             = "Num/",
        KP_Multiply           = "Num*",
        KP_Subtract           = "Num-",
        KP_Add                = "Num+",
        KP_Enter              = "NumEnter",
        -- Some "obvious" entries are necessary for the Escape sequence
        -- and whitespace characters:
        Escape                = "Esc",
        Tab                   = "Tab",
        space                 = "Space",
        Return                = "Enter",
        -- Dead keys aren't distinct from non-dead keys because no sane
        -- layout should have both of the same kind:
        dead_acute            = "´",
        dead_circumflex       = "^",
        dead_grave            = "`",
        -- Basic multimedia keys:
        XF86MonBrightnessUp   = "🔆+",
        XF86MonBrightnessDown = "🔅-",
        XF86AudioRaiseVolume  = "🕩+",
        XF86AudioLowerVolume  = "🕩-",
        XF86AudioMute         = "🔇",
        XF86AudioPlay         = "⏯",
        XF86AudioPrev         = "⏮",
        XF86AudioNext         = "⏭",
        XF86AudioStop         = "⏹",
    }
}

local Help = {}

local last_group_order = 0

local function default_group_sort(a, b)
    local ga, gb = a.state, b.state
    local ra, rb = not not ga.ruled, not not gb.ruled
    if ra == rb then
        local oa, ob = ga.order, gb.order
        if oa and ob then
            return oa < ob
        elseif not oa and not ob then
            return a.name < b.name
        else
            return oa
        end
    else
        return ra
    end
end

local function default_binding_sort(a, b)
    local oa, ob = a.order, b.order
    if oa and ob then
        return oa < ob
    elseif not oa and not ob then
        return (a.description or "") < (b.description or "")
    else
        return oa
    end
end

local function sort_node(node, group_sort, binding_sort)
    table.sort(node.children, group_sort)
    table.sort(node.state, binding_sort)
end

local function merge_binding(node, binding)
    table.insert(node.state, binding)
end

local function merge_group(tree, node, group_args)
    if not group_args or not group_args.groups then
        return
    end
    for _, child_args in ipairs(group_args.groups) do
        local child, is_new = tree:get_or_add_node(node, child_args.name, child_args)
        if is_new then
            if not child_args.order then
                child_args.order = last_group_order + 1
            end
            last_group_order = child_args.order
        end
        for i = 1, #child_args do
            local binding = pbinding.new(child_args[i])
            if is_new then
                -- Just replace binding args with an actual binding
                child_args[i] = binding
            else
                merge_binding(child, binding)
            end
        end
        merge_group(tree, child, child_args)
    end
end

local function merge_awesome_bindings(tree)
    for _, binding in ipairs(pbinding.awesome_bindings) do
        local node = tree:ensure_path(binding.path)
        merge_binding(node, binding)
    end
end

function Help:add_group(group_args)
    self:add_groups { group_args }
end

function Help:add_groups(groups)
    merge_group(self.binding_tree, self.binding_tree.root, { groups = groups })
end

function Help:show(c, s)
    c = c or capi.client.focus
    s = s or (c and c.screen) or awful.screen.focused()

    local function group_clone(node, path)
        return gtable.clone(node.state, false)
    end

    local function node_filter(node)
        local ruled = node.state.ruled
        return not ruled or (c and self.matcher:matches_rule(c, ruled))
    end

    local binding_tree = self.binding_tree:clone(group_clone, node_filter)

    if self.include_awesome_bindings then
        merge_awesome_bindings(binding_tree)
    end

    for node in binding_tree:traverse() do
        sort_node(node, self.group_sort, self.binding_sort)
    end

    if self.popup:show(s, binding_tree) then
        self.keygrabber:start()
    end
end

function Help:hide()
    if self.popup:hide() then
        self.keygrabber:stop()
    end
end

local function create_bindings(self, bindings)
    bindings = bindings or {}

    local function create(args, default_args, on_press)
        local new_args = args and gtable.clone(args, false) or default_args
        if not new_args.description then
            new_args.description = default_args.description
        end
        new_args.on_press = on_press
        new_args.on_release = nil
        return pbinding.new(new_args)
    end

    self.bindings = {
        global = create(bindings.global, {}, function() self:hide() end),
        hide = create(bindings.hide,
            {
                triggers = { "q", "Escape", btn.left, btn.right, btn.middle },
                description = "hide",
            },
            function() self:hide() end),
        previous_page = create(bindings.previous_page,
            {
                triggers = { "k", "Up", "Prior", btn.wheel_up },
                description = "previous page",
            },
            function() self.popup:change_page(-1) end),
        next_page = create(bindings.next_page,
            {
                triggers = { "j", "Down", "Next", btn.wheel_down },
                description = "next page",
            },
            function() self.popup:change_page(1) end),
        search = create(bindings.search,
            {
                triggers = { "s" },
                description = "search",
            },
            function() self.popup:start_search() end),
        previous_page_search = create(bindings.previous_page_search,
            {
                triggers = { "Up" },
                description = "previous page",
            },
            function() self.popup:change_page(-1) return true, false end),
        next_page_search = create(bindings.next_page_search,
            {
                triggers = { "Down" },
                description = "next page",
            },
            function() self.popup:change_page(1) return true, false end),
    }

    local keygrabber_bindings = {
        self.bindings.global,
        self.bindings.hide,
        self.bindings.search,
        self.bindings.next_page,
        self.bindings.previous_page,
    }

    self.keygrabber = awful.keygrabber {
        keybindings = pbinding.awful_keys(keygrabber_bindings),
    }
end

local function create_style(self, style)
    style = style or {}

    local theme = beautiful.get()

    self.style = {
        width = style.width or theme.help_width or dpi(1200),
        height = style.height or theme.help_height or dpi(800),
        columns = math.floor(style.columns or theme.help_columns or 2),
        padding = style.padding or theme.help_padding or dpi(16),
        spacing = style.spacing or theme.help_spacing or dpi(8),
        font = style.font or theme.help_font or "Monospace 9",
        bg = style.bg or theme.help_bg or theme.bg_normal,
        fg = style.fg or theme.help_fg or theme.fg_normal,
        trigger_bg = style.trigger_bg or theme.help_trigger_bg or theme.fg_normal,
        trigger_bg_alpha = style.trigger_bg_alpha or theme.help_trigger_bg_alpha or "17%",
        status_bg = style.status_bg or theme.help_status_bg or theme.bg_focus,
        status_fg = style.status_fg or theme.help_status_fg or theme.fg_focus,
        status_spacing = style.status_spacing or theme.help_status_spacing or dpi(32),
        search_highlight_bg = style.search_highlight_bg or theme.help_search_highlight_bg,
        search_highlight_fg = style.search_highlight_fg or theme.help_search_highlight_fg or theme.bg_urgent,
        search_dim_bg = style.search_dim_bg or theme.help_search_dim_bg,
        search_dim_fg = style.search_dim_fg or theme.help_search_dim_fg or "#818181",
        search_cursor_bg = style.search_cursor_bg or theme.help_search_cursor_bg or theme.fg_focus,
        search_cursor_fg = style.search_cursor_fg or theme.help_search_cursor_fg or theme.bg_focus,
        search_cursor_underline = style.search_cursor_underline or theme.help_search_cursor_underline or "none",
        border_width = style.border_width or theme.help_border_width or theme.border_width,
        border_color = style.border_color or theme.help_border_color or theme.border_color_active,
        group_bg = style.group_bg or theme.help_group_bg or theme.bg_focus,
        group_fg = style.group_fg or theme.help_group_fg or theme.fg_focus,
        group_ruled_bg = style.group_ruled_bg or theme.help_group_ruled_bg or theme.bg_urgent,
        group_ruled_fg = style.group_ruled_fg or theme.help_group_ruled_fg or theme.fg_urgent,
        opacity = style.opacity or theme.help_opacity or 1,
        shape = style.shape or theme.help_shape or nil,
        labels = gtable.crush(gtable.clone(help.default_labels, false), style.labels or theme.help_labels or {}),
        group_path_separator_markup = style.group_path_separator_markup or theme.help_group_path_separator_markup or
            "<span fgalpha='50%' size='smaller'> / </span>",
        slash_separator_markup = style.slash_separator_markup or theme.help_slash_separator_markup or
            "<span fgalpha='50%' size='smaller'> / </span>",
        plus_separator_markup = style.plus_separator_markup or theme.help_plus_separator_markup or
            "<span fgalpha='50%'>+</span>",
        range_separator_markup = style.range_separator_markup or theme.help_range_separator_markup or
            "<span fgalpha='50%'>..</span>",
    }
end

function help.new(args)
    args = args or {}

    local self = {
        matcher = gmatcher(),
        binding_tree = tree.new(),
        group_sort = args.group_sort or default_group_sort,
        binding_sort = args.binding_sort or default_binding_sort,
        include_awesome_bindings = args.include_awesome_bindings == nil or args.include_awesome_bindings,
        bindings = nil,
        keygrabber = nil,
        style = nil,
        popup = nil,
    }

    create_bindings(self, args.bindings)
    create_style(self, args.style)

    self.popup = help_popup.new({
        bindings = self.bindings,
        style = self.style,
    })

    return setmetatable(self, { __index = Help })
end

return help
