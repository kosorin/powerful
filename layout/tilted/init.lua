local capi = {
    mouse = mouse,
    mousegrabber = mousegrabber,
    screen = screen,
}
local math = math
local infinity = math.huge
local find = string.find
local aclient = require("awful.client")
local amouse = require("awful.mouse")
local alayout = require("awful.layout")
local tilted_layout_descriptor = require("powerful.layout.tilted.layout_descriptor")


local tilted = {}

--- Cursors for each corner (3x3 matrix).
-- @field powerful.layout.tilted.cursors
tilted.cursors = {
    { "top_left_corner", "top_side", "top_right_corner" },
    { "left_side", "pirate", "right_side" },
    { "bottom_left_corner", "bottom_side", "bottom_right_corner" },
}

--- Resize only neighbor clients.
-- @field powerful.layout.tilted.resize_only_neighbors
tilted.resize_only_neighbors = false

--- Jump mouse cursor to the client's corner when resizing it.
-- @field powerful.layout.tilted.resize_jump_to_corner
tilted.resize_jump_to_corner = true

local function any_button(buttons)
    for i = 1, #buttons do
        if buttons[i] then
            return true
        end
    end
    return false
end

local function get_titlebar_size(client)
    local _, top = client:titlebar_top()
    local _, bottom = client:titlebar_bottom()
    local _, left = client:titlebar_left()
    local _, right = client:titlebar_right()
    return {
        width = left + right,
        height = top + bottom,
    }
end

local function get_decoration_size(client, useless_gap)
    local border_width = 2 * (client.border_width + useless_gap)
    local decoration_size = get_titlebar_size(client)
    decoration_size.width = decoration_size.width + border_width
    decoration_size.height = decoration_size.height + border_width
    return decoration_size
end

local function inflate(geometry, size)
    return {
        x = geometry.x - size,
        y = geometry.y - size,
        width = geometry.width + (2 * size),
        height = geometry.height + (2 * size),
    }
end

local function get_orientation_info(orientation)
    local is_reversed_x = orientation == "left"
    local is_reversed_y = orientation == "top"
    local is_reversed = is_reversed_x or is_reversed_y
    local is_horizontal = orientation == "left" or orientation == "right"
    local _x, _y, _width, _height
    if is_horizontal then
        _x = "x"
        _y = "y"
        _width = "width"
        _height = "height"
    else
        _x = "y"
        _y = "x"
        _width = "height"
        _height = "width"
    end
    local _fx, _fy = is_horizontal and _x or _y, is_horizontal and _y or _x
    return _x, _y, _width, _height, is_horizontal, is_reversed, is_reversed_x, is_reversed_y, _fx, _fy
end

local function resize(orientation, screen, tag, client, corner)
    if not screen or not tag or not client or not client.valid then
        return
    end

    local layout_descriptor = tag.tilted_layout_descriptor
    if not layout_descriptor then
        return
    end

    local parameters = alayout.parameters(tag, screen)

    local column_descriptor, item_descriptor = layout_descriptor:find_client(client, parameters.clients)
    if not column_descriptor then
        return
    end

    local index = item_descriptor.index
    local _x, _y, _width, _height, is_horizontal, _, is_reversed_x, is_reversed_y, _fx, _fy = get_orientation_info(orientation)

    local directions = { x = 0, y = 0 }
    if find(corner, is_reversed_x and "right" or "left", nil, true) then
        directions[_x] = is_horizontal
            and (column_descriptor.index > 1 and -1 or 0)
            or (index > column_descriptor.from and -1 or 0)
    elseif find(corner, is_reversed_x and "left" or "right", nil, true) then
        directions[_x] = is_horizontal
            and (column_descriptor.index < layout_descriptor.size and 1 or 0)
            or (index < column_descriptor.to and 1 or 0)
    end
    if find(corner, is_reversed_y and "bottom" or "top", nil, true) then
        directions[_y] = is_horizontal
            and (index > column_descriptor.from and -1 or 0)
            or (column_descriptor.index > 1 and -1 or 0)
    elseif find(corner, is_reversed_y and "top" or "bottom", nil, true) then
        directions[_y] = is_horizontal
            and (index < column_descriptor.to and 1 or 0)
            or (column_descriptor.index < layout_descriptor.size and 1 or 0)
    end

    local original_directions = { x = directions.x, y = directions.y }

    if is_reversed_x then
        directions[_x] = directions[_x] * -1
    end
    if is_reversed_y then
        directions[_y] = directions[_y] * -1
    end

    local cursor = tilted.cursors[directions[_y] + 2][directions[_x] + 2]

    if directions.x == 0 and directions.y == 0 then
        capi.mousegrabber.run(function(coords) return any_button(coords.buttons) end, cursor)
        return
    end

    local initial_geometry = inflate(client:geometry(), client.border_width + parameters.useless_gap)
    initial_geometry = {
        x = initial_geometry.x,
        y = initial_geometry.y,
        width = (is_horizontal and column_descriptor or item_descriptor).factor * parameters.workarea.width,
        height = (is_horizontal and item_descriptor or column_descriptor).factor * parameters.workarea.height,
    }
    local initial_coords = {
        x = initial_geometry.x + ((directions[_x] + 1) * 0.5 * initial_geometry.width),
        y = initial_geometry.y + ((directions[_y] + 1) * 0.5 * initial_geometry.height),
    }

    local coords_offset
    if tilted.resize_jump_to_corner then
        capi.mouse.coords(initial_coords)
        coords_offset = { x = 0, y = 0 }
    else
        local mouse_coords = capi.mouse.coords()
        coords_offset = {
            x = initial_coords.x - mouse_coords.x,
            y = initial_coords.y - mouse_coords.y,
        }
    end

    layout_descriptor.resize = nil

    capi.mousegrabber.stop()
    capi.mousegrabber.run(function(coords)
        if not client.valid then
            layout_descriptor.resize = nil
            return false
        end

        local current_cd, current_id = layout_descriptor:find_client(client, aclient.tiled(screen))
        if column_descriptor ~= current_cd or item_descriptor ~= current_id then
            layout_descriptor.resize = nil
            return false
        end

        if not any_button(coords.buttons) then
            if layout_descriptor.resize then
                layout_descriptor.resize.apply = true
                alayout.arrange(screen)
            end
            return false
        end

        coords.x = coords.x + coords_offset.x
        coords.y = coords.y + coords_offset.y

        local size = {}

        if directions[_fx] ~= 0 then
            local value = directions[_fx] < 0
                and (initial_geometry[_x] + initial_geometry[_width] - coords[_x])
                or (coords[_x] - initial_geometry[_x])
            if value < 1 then
                value = 1
            end
            size[_fx] = value
        end

        if directions[_fy] ~= 0 then
            local value = directions[_fy] < 0
                and (initial_geometry[_y] + initial_geometry[_height] - coords[_y])
                or (coords[_y] - initial_geometry[_y])
            if value < 1 then
                value = 1
            end
            size[_fy] = value
        end

        layout_descriptor.resize = {
            apply = false,
            column = column_descriptor.index,
            item = index - column_descriptor.from + 1,
            size = size,
            directions = original_directions,
        }
        alayout.arrange(screen)
        return true
    end, cursor)
end

local function fit(items, total_size)
    local count = #items
    local new_adjusted
    local adjusted = {}
    local factors = {}
    local available_size = total_size
    repeat
        new_adjusted = false
        local total_factor = 0
        for i = 1, count do
            local item = items[i]
            if not adjusted[i] then
                if item.size < item.min_size then
                    available_size = available_size - item.min_size
                else
                    if not factors[i] then
                        factors[i] = item.factor
                    end
                    total_factor = total_factor + factors[i]
                end
            end
        end
        for i = 1, count do
            local item = items[i]
            if not adjusted[i] then
                if item.size < item.min_size then
                    item.size = item.min_size
                    adjusted[i] = true
                    new_adjusted = true
                else
                    factors[i] = factors[i] / total_factor
                    item.size = available_size * factors[i]
                end
            end
        end
        if #adjusted >= count then
            break
        end
    until not (new_adjusted and #adjusted < count)
end

local function resize_fit(items, start, direction, new_size, apply)
    local resize_item = items[start]
    if resize_item.size == new_size then
        return
    end

    local min_size = resize_item.min_size
    if new_size < min_size then
        new_size = min_size
    end

    local full_factor = resize_item.factor
    local full_size = resize_item.size
    local total_size = 0
    local total_min_size = 0

    local new_items = {}
    local stop = direction < 0 and 1 or #items
    for i = start + direction, stop, direction do
        local item = items[i]
        full_factor = full_factor + item.factor
        full_size = full_size + item.size
        total_size = total_size + item.size
        total_min_size = total_min_size + item.min_size
        new_items[#new_items + 1] = {
            old_item = item,
            size = item.size,
            min_size = item.min_size,
        }
    end

    if new_size > full_size - total_min_size then
        new_size = full_size - total_min_size
    end

    local new_total_size = full_size - new_size
    if new_total_size < total_min_size then
        new_total_size = total_min_size
    end

    local new_total_factor = 0
    for i = 1, #new_items do
        local new_item = new_items[i]
        new_item.factor = new_item.size / total_size
        new_item.size = new_item.factor * new_total_size
        new_total_factor = new_total_factor + new_item.factor
    end
    for i = 1, #new_items do
        local new_item = new_items[i]
        new_item.factor = new_item.factor / new_total_factor
    end

    fit(new_items, new_total_size)

    new_items[0] = {
        old_item = resize_item,
        size = new_size,
    }
    for i = 0, #new_items do
        local new_item = new_items[i]
        new_item.old_item.factor = full_factor * (new_item.size / full_size)
        new_item.old_item.size = new_item.size
        if apply then
            new_item.old_item.descriptor.factor = new_item.old_item.factor
        end
    end
end

local function arrange(orientation, parameters)
    local tag = parameters.tag
    local screen = parameters.screen and capi.screen[parameters.screen]
    if not tag and screen then
        tag = screen.selected_tag
    end
    if not tag or not screen then
        return
    end

    local _x, _y, _width, _height, _, is_reversed = get_orientation_info(orientation)

    local clients = parameters.clients
    local workarea = parameters.workarea
    local useless_gap = parameters.useless_gap
    local width = workarea[_width]
    local height = workarea[_height]

    local layout_descriptor = tilted_layout_descriptor.update(tag, clients)

    local layout_data = {
        descriptor = layout_descriptor,
    }

    for column = 1, layout_descriptor.size do
        column = is_reversed and (layout_descriptor.size - column + 1) or column
        local column_descriptor = layout_descriptor[column]

        local column_data = {
            descriptor = column_descriptor,
            factor = column_descriptor.factor,
            size = column_descriptor.factor * width,
            min_size = 0,
        }
        for item = 1, column_descriptor.size do
            local index = column_descriptor.from + item - 1
            local item_descriptor = column_descriptor[item]
            local client = clients[index]

            local size_hints = client.size_hints
            local decoration_size = get_decoration_size(client, useless_gap)
            local min_width = decoration_size[_width]
                + math.max(1, size_hints["min_" .. _width] or size_hints["base_" .. _width] or 0)
            local min_height = decoration_size[_height]
                + math.max(1, size_hints["min_" .. _height] or size_hints["base_" .. _height] or 0)
            local max_width = decoration_size[_width]
                + (size_hints["max_" .. _width] or infinity)
            local max_height = decoration_size[_height]
                + (size_hints["max_" .. _height] or infinity)

            column_data[item] = {
                descriptor = item_descriptor,
                factor = item_descriptor.factor,
                size = item_descriptor.factor * height,
                min_size = min_height,
            }

            if column_data.min_size < min_width then
                column_data.min_size = min_width
            end
        end

        layout_data[column] = column_data
    end

    fit(layout_data, width)
    for i = 1, #layout_data do
        fit(layout_data[i], height)
    end

    local resize = layout_descriptor.resize
    if resize then
        if resize.size.x and resize.directions.x ~= 0 then
            resize_fit(layout_data, resize.column, resize.directions.x, resize.size.x, resize.apply)
        end
        if resize.size.y and resize.directions.y ~= 0 then
            resize_fit(layout_data[resize.column], resize.item, resize.directions.y, resize.size.y, resize.apply)
        end
        if resize.apply then
            layout_descriptor.resize = nil
        end
    end

    local x = workarea[_x]
    for column = 1, layout_descriptor.size do
        column = is_reversed and (layout_descriptor.size - column + 1) or column
        local column_descriptor = layout_descriptor[column]
        local column_data = layout_data[column]
        local column_width = column_data.size

        local y = workarea[_y]
        for item = 1, column_descriptor.size do
            local index = column_descriptor.from + item - 1
            local item_data = column_data[item]
            local item_height = item_data.size

            parameters.geometries[clients[index]] = {
                [_width] = column_width,
                [_height] = item_height,
                [_x] = x,
                [_y] = y,
            }

            y = y + item_height
        end
        x = x + column_width
    end
end

function tilted.skip_gap(tiled_client_count, tag)
    return tiled_client_count == 1 and tag.master_fill_policy == "expand"
end

--- The extended tile layout, on the right.
-- @param screen The screen number to tile.
-- @usebeautiful beautiful.layout_tilted
tilted.right = {}
tilted.right.is_tilted = true
tilted.right.name = "tilted"
tilted.right.skip_gap = tilted.skip_gap

function tilted.right.arrange(...)
    return arrange("right", ...)
end

function tilted.right.resize(...)
    return resize("right", ...)
end

--- The extended tile layout, on the left.
-- @param screen The screen number to tile.
-- @usebeautiful beautiful.layout_tiltedleft
tilted.left = {}
tilted.left.is_tilted = true
tilted.left.name = "tiltedleft"
tilted.left.skip_gap = tilted.skip_gap

function tilted.left.arrange(...)
    return arrange("left", ...)
end

function tilted.left.resize(...)
    return resize("left", ...)
end

--- The extended tile layout, on the bottom.
-- @param screen The screen number to tile.
-- @usebeautiful beautiful.layout_tiltedbottom
tilted.bottom = {}
tilted.bottom.is_tilted = true
tilted.bottom.name = "tiltedbottom"
tilted.bottom.skip_gap = tilted.skip_gap

function tilted.bottom.arrange(...)
    return arrange("bottom", ...)
end

function tilted.bottom.resize(...)
    return resize("bottom", ...)
end

--- The extended tile layout, on the top.
-- @param screen The screen number to tile.
-- @usebeautiful beautiful.layout_tiltedtop
tilted.top = {}
tilted.top.is_tilted = true
tilted.top.name = "tiltedtop"
tilted.top.skip_gap = tilted.skip_gap

function tilted.top.arrange(...)
    return arrange("top", ...)
end

function tilted.top.resize(...)
    return resize("top", ...)
end

tilted.is_tilted = true
tilted.name = tilted.right.name
tilted.arrange = tilted.right.arrange
tilted.resize = tilted.right.resize

amouse.resize.add_enter_callback(function(client, args)
    if client.floating then
        return
    end
    local screen = client.screen
    local tag = screen.selected_tag
    local layout = tag and tag.layout or nil
    if layout and layout.is_tilted then
        if layout.resize then
            layout.resize(screen, tag, client, args.corner)
        end
        return false
    end
end, "mouse.resize")

tilted_layout_descriptor.tilted = tilted

return tilted
