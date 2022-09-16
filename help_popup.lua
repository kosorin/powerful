local awful = require("awful")
local wibox = require("wibox")
local gtable = require("gears.table")
local pbinding = require("powerful.binding")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi


local help_popup = {}

local HelpPopup = {}

local function get_modifier_label(self, modifier)
    return self.style.labels[modifier] or modifier
end

local function get_trigger_label(self, trigger)
    if type(trigger) == "string" then
        local keysym, keyprint = awful.keyboard.get_key_name(trigger)
        return self.style.labels[keysym] or keyprint or keysym or trigger
    end
    return self.style.labels[trigger] or tostring(trigger)
end

local function highlight_text(self, text, args)

    text = text or ""

    local function clear()
        return text, true
    end

    if not args then
        return clear()
    end

    local function dim()
        if args.clear_on_dim then
            return clear()
        end
        local dim_begin = "<span"
        if self.style.search_dim_bg then
            dim_begin = dim_begin .. " background='" .. self.style.search_dim_bg .. "'"
        end
        dim_begin = dim_begin .. " foreground='" .. self.style.search_dim_fg .. "'"
        dim_begin = dim_begin .. ">"
        local dim_end = "</span>"
        return dim_begin .. text .. dim_end, false
    end

    if not args.search_terms or #text == 0 then
        return clear()
    elseif #args.search_terms == 0 then
        return dim()
    end

    local substitutions = {}

    local function is_available(from, to)
        for _, s in ipairs(substitutions) do
            if from <= s.to and to >= s.from then
                return false
            end
        end
        return true
    end

    local lower_text = string.lower(text)
    for _, st in ipairs(args.search_terms) do
        local from = 1
        local to
        while true do
            from, to = string.find(lower_text, st, from, true)
            if from == nil then
                break
            end
            if is_available(from, to) then
                table.insert(substitutions, { matched = true, from = from, to = to })
            end
            from = to + 1
        end
    end

    if #substitutions == 0 then
        return dim()
    end

    table.sort(substitutions, function(a, b) return a.from < b.from end)

    local parts = {}
    local length = #text
    local next_substitution = substitutions[1]
    local i = 1
    while i <= length do
        if next_substitution then
            if next_substitution.from == i then
                table.insert(parts, next_substitution)
                i = next_substitution.to + 1
                table.remove(substitutions, 1)
                next_substitution = substitutions[1]
            else
                table.insert(parts, { from = i, to = next_substitution.from - 1 })
                i = next_substitution.from
            end
        else
            table.insert(parts, { from = i, to = length })
            break
        end
    end

    local highlight_begin = "<span"
    if self.style.search_highlight_bg then
        highlight_begin = highlight_begin .. " background='" .. self.style.search_highlight_bg .. "' bgalpha='100%'"
    end
    highlight_begin = highlight_begin .. " foreground='" .. self.style.search_highlight_fg .. "'"
    highlight_begin = highlight_begin .. ">"
    local highlight_end = "</span>"

    return table.concat(gtable.map(function(part)
        local capture = string.sub(text, part.from, part.to)
        if part.matched then
            return highlight_begin .. capture .. highlight_end
        else
            return capture
        end
    end, parts), ""), true
end

local function get_group_markup(self, node, path)
    local is_ruled = node:find_parent(function(n) return n.state.ruled end, true)
    local bg = select(2, node:find_parent(function(n) return n.state.bg end, true))
        or (is_ruled and self.style.group_ruled_bg or self.style.group_bg)
    local fg = select(2, node:find_parent(function(n) return n.state.fg end, true))
        or (is_ruled and self.style.group_ruled_fg or self.style.group_fg)
    local style = "background='" .. bg .. "' foreground='" .. fg .. "'"
    local text = table.concat(path, self.style.group_path_separator_markup)
    return "<span " .. style .. "> " .. text .. " </span>"
end

local function get_trigger_markup(self, binding, max_triggers)

    local function trigger_box(content)
        return "<span background='" .. self.style.trigger_bg .. "' bgalpha='" .. self.style.trigger_bg_alpha .. "'> "
            .. content .. " </span>"
    end

    local function trigger_target(target)
        return "<span fgalpha='50%' size='smaller'> (" .. target .. ")</span>"
    end

    local modifier_markup = ""
    if #binding.modifiers > 0 then
        local modifier_label_markups = gtable.map(function(m)
            return trigger_box(get_modifier_label(self, m))
        end, binding.modifiers)
        modifier_markup = table.concat(modifier_label_markups, self.style.plus_separator_markup) ..
            self.style.plus_separator_markup
    end

    local trigger_text
    if binding.text then
        trigger_text = binding.text
    else
        if binding.from and binding.to then
            local from = get_trigger_label(self, binding.from)
            local to = get_trigger_label(self, binding.to)
            trigger_text = from .. self.style.range_separator_markup .. to
        else
            local trigger_labels = gtable.map(function(t)
                return get_trigger_label(self, t.trigger)
            end, binding.triggers)
            local trigger_count = math.min(max_triggers or math.maxinteger, #trigger_labels)
            trigger_text = table.concat(trigger_labels, self.style.slash_separator_markup, 1, trigger_count)
        end
    end

    if binding.target then
        trigger_text = trigger_text .. trigger_target(binding.target)
    end

    return modifier_markup .. trigger_box(trigger_text)
end

local function get_description_markup(self, binding, highlight_args)
    return highlight_text(self, binding.description, highlight_args)
end

local function get_markup_geometry(self, markup)
    return wibox.widget.textbox.get_markup_geometry(
        markup,
        self.context.screen,
        self.style.font)
end

local function parse_data(self)
    local data = {
        max_trigger_width = 0,
        max_description_width = 0, -- also used for group header
    }
    for node, path in self.context.binding_tree:traverse() do
        local group = node.state
        if #path > 0 and #group > 0 then
            local group_markup = get_group_markup(self, node, path)
            local group_size = get_markup_geometry(self, group_markup)
            local group_data = {
                markup = group_markup,
                size = group_size,
                page_break = group.page_break,
                items = {},
            }
            if data.max_description_width < group_size.width then
                data.max_description_width = group_size.width
            end
            for _, binding in ipairs(group) do
                if binding.description then
                    local trigger_markup = get_trigger_markup(self, binding)
                    local trigger_size = get_markup_geometry(self, trigger_markup)
                    local description_markup = get_description_markup(self, binding)
                    local description_size = get_markup_geometry(self, description_markup)
                    local item = {
                        binding = binding,
                        trigger = {
                            markup = trigger_markup,
                            size = trigger_size,
                            highlighted = nil,
                            widget = nil,
                        },
                        description = {
                            markup = description_markup,
                            size = description_size,
                            highlighted = nil,
                            widget = nil,
                        },
                    }
                    table.insert(group_data.items, item)
                    if data.max_trigger_width < trigger_size.width then
                        data.max_trigger_width = trigger_size.width
                    end
                    if data.max_description_width < description_size.width then
                        data.max_description_width = description_size.width
                    end
                end
            end
            if #group_data.items > 0 then
                table.insert(data, group_data)
            end
        end
    end
    self.context.data = data
end

local function create_pages(self, filter_highlighted)
    self.context.page_widgets = {}

    local data = self.context.data

    local line_size = get_markup_geometry(self, "foobar")

    local status_bar_height = line_size.height + self.style.padding

    local width = math.floor(self.context.width / self.style.columns) - ((self.style.columns - 1) * self.style.padding)
    local height = self.context.height - (2 * self.style.padding) - status_bar_height

    local max_description_width = width - data.max_trigger_width - self.style.spacing

    -- It's useless to have too narrow description column,
    -- so set the minimum width according to the width of the "foobar" text
    local show_description_column = max_description_width >= line_size.width

    if width < 0 or width < data.max_trigger_width or height < 0 then
        self:set_page(nil, true)
        return
    end

    local columns = {}
    local function add_column(column)
        if #column == 0 then
            return false
        end
        local widget = wibox.layout.manual(table.unpack(column))
        widget:set_forced_width(width)
        widget:set_forced_height(height)
        table.insert(columns, widget)
        return true
    end

    local next_column = { group = 1, item = 1 }
    local ignore_page_break = {}
    ::next_column::
    local current_column = {}
    local is_first_column = (#columns % self.style.columns) == 0
    local is_last_column = (#columns % self.style.columns) == (self.style.columns - 1)
    local offset_x = 0
    local offset_y = 0
    for i = next_column.group, #data do
        local initial_offset_y = offset_y

        local group = data[i]

        if not ignore_page_break[i] and group.page_break then
            ignore_page_break[i] = true
            if #columns > 0 then
                next_column.group = i
                next_column.item = 1
                if add_column(current_column) then
                    goto next_column
                else
                    goto done
                end
            end
        end

        local group_widget
        if show_description_column and (next_column.item == 1 or is_first_column) then
            group_widget = wibox.widget {
                widget = wibox.widget.textbox,
                font = self.style.font,
                align = "left",
                valign = "top",
                markup = group.markup,
                point = {
                    x = offset_x + data.max_trigger_width + self.style.spacing,
                    y = offset_y,
                    width = max_description_width,
                    height = group.size.height,
                },
            }
            offset_y = offset_y + group_widget.point.height
            if offset_y > height then
                next_column.group = i
                next_column.item = 1
                if add_column(current_column) then
                    goto next_column
                else
                    goto done
                end
            end
            offset_y = offset_y + self.style.spacing
        end

        local item_count = 0
        for j = next_column.item, #group.items do
            local item = group.items[j]
            if not filter_highlighted or item.trigger.highlighted or item.description.highlighted then
                local trigger_offset_x = data.max_trigger_width - item.trigger.size.width
                local trigger_widget = wibox.widget {
                    widget = wibox.widget.textbox,
                    font = self.style.font,
                    align = "right",
                    valign = "top",
                    markup = item.trigger.highlighted or item.trigger.markup,
                    point = {
                        x = offset_x + (show_description_column and trigger_offset_x or 0),
                        y = offset_y,
                        width = item.trigger.size.width,
                        height = item.trigger.size.height,
                    }
                }
                item.trigger.widget = trigger_widget
                local description_widget
                if show_description_column then
                    description_widget = wibox.widget {
                        widget = wibox.widget.textbox,
                        font = self.style.font,
                        align = "left",
                        valign = "top",
                        markup = item.description.highlighted or item.description.markup,
                        point = {
                            x = offset_x + data.max_trigger_width + self.style.spacing,
                            y = offset_y,
                            width = max_description_width,
                        },
                    }
                    item.description.widget = description_widget
                    description_widget.line_spacing_factor = 1 + (self.style.spacing / item.description.size.height)
                    description_widget.point.height = description_widget:get_height_for_width(
                        max_description_width, self.context.screen) + self.style.spacing
                    offset_y = offset_y +
                        math.max(trigger_widget.point.height, description_widget.point.height - self.style.spacing)
                else
                    offset_y = offset_y + trigger_widget.point.height
                end
                if offset_y > height then
                    next_column.group = i
                    next_column.item = j
                    if add_column(current_column) then
                        goto next_column
                    else
                        goto done
                    end
                end
                offset_y = offset_y + self.style.spacing

                if group_widget then
                    -- Add a group widget only if at least one item fits in the column
                    table.insert(current_column, group_widget)
                    group_widget = nil
                end
                table.insert(current_column, trigger_widget)
                if description_widget then
                    table.insert(current_column, description_widget)
                end
                item_count = item_count + 1
            end
        end
        next_column.item = 1

        if item_count > 0 then
            offset_y = offset_y + self.style.padding
        else
            offset_y = initial_offset_y
        end
    end
    if #current_column > 0 then
        add_column(current_column)
    end
    ::done::
    if self.style.columns > 1 then
        for i = 1, #columns, self.style.columns do
            local page_layout = wibox.layout.fixed.horizontal()
            page_layout:set_spacing(self.style.padding)
            for j = 1, self.style.columns do
                local column = columns[i + j - 1]
                if column then
                    page_layout:add(column)
                end
            end
            table.insert(self.context.page_widgets, page_layout)
        end
    else
        self.context.page_widgets = columns
    end
    self:set_page(nil, true)
end

local function get_search_terms(query)
    if not query then
        return {}
    end

    local unique_term_map = {}
    local terms = {}
    query = string.gsub(query, "%s+", " ")
    for term in string.gmatch(query, "([^%s]+)") do
        term = string.lower(term)
        if #term > 0 and not unique_term_map[term] then
            unique_term_map[term] = true
            if pcall(string.find, "", term) then
                table.insert(terms, term)
            end
        end
    end

    table.sort(terms, function(a, b) return #a > #b end)

    return terms
end

local function search(self, query, is_end_of_search)
    if not self.context.is_searching then
        return
    end

    self.context.last_search_args.query = query

    local terms = get_search_terms(query)

    local hash = tostring(not not is_end_of_search) .. "\t" .. (table.concat(terms, " ") or "")
    if self.context.last_search_args.hash == hash then
        return
    end
    self.context.last_search_args.hash = hash

    local highlight_args = {
        search_terms = terms,
        clear_on_dim = is_end_of_search,
    }

    for _, group in ipairs(self.context.data) do
        for _, item in ipairs(group.items) do
            item.trigger.highlighted = get_trigger_markup(self, item.binding)
            item.trigger.widget:set_markup(item.trigger.highlighted)
            item.description.highlighted = get_description_markup(self, item.binding, highlight_args)
            item.description.widget:set_markup(item.description.highlighted)
        end
    end
end

function HelpPopup:start_search()
    if not self:is_shown() then
        return
    end

    local initial_query = self.context.last_search_args.query or ""

    self.context.is_searching = true
    search(self, initial_query, false)
    self.widgets.status_bar_container.set_status_bar(self.widgets.search_status_bar)

    local executed_input = nil
    awful.prompt.run {
        textbox = self.widgets.search_textbox,
        prompt = "Search: ",
        text = initial_query,
        font = self.style.font,
        bg_cursor = self.style.search_cursor_bg,
        fg_cursor = self.style.search_cursor_fg,
        ul_cursor = self.style.search_cursor_underline,
        exe_callback = function(input)
            executed_input = input
        end,
        changed_callback = function(input)
            search(self, input, false)
        end,
        done_callback = function()
            self.widgets.status_bar_container.set_status_bar(self.widgets.main_status_bar)
            search(self, executed_input, true)
            self.context.is_searching = false
        end,
        hooks = pbinding.awful_hooks {
            self.bindings.previous_page_search,
            self.bindings.next_page_search,
        },
    }
end

local function create_status_bar(self)

    local spacing = self.style.spacing * 4

    local function get_binding_widget(binding)
        return wibox.widget {
            widget = wibox.widget.textbox,
            font = self.style.font,
            align = "left",
            valign = "top",
            markup = get_trigger_markup(self, binding, 2) ..
                (binding.description and (" " .. get_description_markup(self, binding)) or ""),
        }
    end

    self.widgets.page_number = wibox.widget {
        widget = wibox.widget.textbox,
        font = self.style.font,
        align = "left",
        valign = "top",
        markup = "-",
    }

    local page_number = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        {
            widget = wibox.widget.textbox,
            font = self.style.font,
            align = "left",
            valign = "top",
            markup = "Page: ",
        },
        self.widgets.page_number,
    }

    self.widgets.search_textbox = wibox.widget {
        widget = wibox.widget.textbox,
        font = self.style.font,
        align = "left",
        valign = "top",
        ellipsize = "start",
    }

    self.widgets.main_status_bar = wibox.widget {
        layout = wibox.layout.align.horizontal,
        {
            layout = wibox.layout.fixed.horizontal,
            spacing = spacing,
            get_binding_widget(self.bindings.hide),
            get_binding_widget(self.bindings.search),
        },
        nil,
        {
            layout = wibox.layout.fixed.horizontal,
            spacing = spacing,
            get_binding_widget(self.bindings.previous_page),
            get_binding_widget(self.bindings.next_page),
            page_number,
        },
    }

    self.widgets.search_status_bar = wibox.widget {
        layout = wibox.layout.align.horizontal,
        {
            layout = wibox.layout.fixed.horizontal,
            spacing = spacing,
            self.widgets.search_textbox,
        },
        nil,
        {
            layout = wibox.layout.fixed.horizontal,
            spacing = spacing,
            get_binding_widget(pbinding.new { "Escape", description = "cancel search" }),
            get_binding_widget(self.bindings.previous_page_search),
            get_binding_widget(self.bindings.next_page_search),
            page_number,
        },
    }

    self.widgets.status_bar_container = wibox.widget {
        widget = wibox.container.background,
        bg = self.style.status_bg,
        fg = self.style.status_fg,
        set_status_bar = function(widget)
            self.widgets.status_bar_container.widget.children = { widget }
        end,
        {
            widget = wibox.container.margin,
            left = self.style.padding,
            right = self.style.padding,
            top = self.style.padding / 2,
            bottom = self.style.padding / 2,
        },
    }

    self.widgets.status_bar_container.set_status_bar(self.widgets.main_status_bar)
end

local function create_popup(self)
    self.widgets.page_container = wibox.container.margin(nil,
        self.style.padding, self.style.padding, self.style.padding, self.style.padding)
    self.widgets.popup = awful.popup {
        ontop = true,
        visible = false,
        placement = false,
        widget = {
            layout = wibox.container.constraint,
            strategy = "exact",
            buttons = pbinding.awful_buttons {
                self.bindings.hide,
                self.bindings.previous_page,
                self.bindings.next_page,
            },
            {
                widget = wibox.container.margin,
                margins = self.style.border_width,
                color = self.style.border_color,
                wibox.widget {
                    layout = wibox.layout.align.vertical,
                    nil,
                    self.widgets.page_container,
                    self.widgets.status_bar_container,
                }
            },
        },
        bg = self.style.bg,
        fg = self.style.fg,
        opacity = self.style.opacity,
        shape = self.style.shape,
    }
end

local function set_page_content(self, page, page_number)
    self.widgets.page_container:set_widget(page)
    self.widgets.page_number:set_markup(page_number or "-/-")
end

function HelpPopup:set_page(page, force)
    if not self:is_shown() and not force then
        return
    end

    local page_count = #self.context.page_widgets

    page = page or self.context.current_page or 1
    if page < 1 then
        page = 1
    end
    if page > page_count then
        page = page_count
    end

    if page > 0 then
        self.context.current_page = page
        set_page_content(self,
            self.context.page_widgets[self.context.current_page],
            tostring(self.context.current_page) .. "/" .. tostring(page_count))
    else
        self.context.current_page = nil
        set_page_content(self)
    end
end

function HelpPopup:change_page(relative_change)
    if not self:is_shown() then
        return
    end

    if not self.context.current_page then
        return
    end
    self:set_page(self.context.current_page + relative_change)
end

function HelpPopup:show(s, binding_tree)
    if self:is_shown() then
        return false
    end

    local wa = s.workarea

    self.context = {
        binding_tree = binding_tree,
        data = nil,
        current_page = nil,
        page_widgets = nil,
        is_searching = false,
        last_search_args = {
            query = nil,
            hash = nil,
        },
        screen = s,
        width = (self.style.width < wa.width and self.style.width or wa.width),
        height = (self.style.height < wa.height and self.style.height or wa.height),
    }

    self.widgets.popup.screen = self.context.screen
    self.widgets.popup.x = wa.x + ((wa.width - self.context.width) / 2)
    self.widgets.popup.y = wa.y + ((wa.height - self.context.height) / 2)
    self.widgets.popup.width = self.context.width
    self.widgets.popup.height = self.context.height
    self.widgets.popup.widget.width = self.context.width
    self.widgets.popup.widget.height = self.context.height

    parse_data(self)
    create_pages(self)

    self.widgets.popup.visible = true

    return true
end

function HelpPopup:hide()
    if not self:is_shown() or self.context.is_searching then
        return false
    end
    set_page_content(self)
    self.widgets.popup.visible = false
    self.context = nil
    return true
end

function HelpPopup:is_shown()
    return self.widgets.popup.visible and self.context
end

function help_popup.new(args)
    local self = setmetatable({
        context = nil,
        widgets = {
            popup = nil,
            page_container = nil,
            status_bar_container = nil,
            main_status_bar = nil,
            page_number = nil,
            search_status_bar = nil,
            search_textbox = nil,
        },
        bindings = args.bindings,
        style = args.style,
    }, { __index = HelpPopup })

    create_status_bar(self)
    create_popup(self)

    return self
end

return help_popup
