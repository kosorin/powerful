local capi = {
    mouse = mouse,
    mousegrabber = mousegrabber,
    screen = screen,
}
local math = math
local select = select
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

--- Minimum client size (excluding `border_width` and `useless_gap`).
-- @field powerful.layout.tilted.minimum_client_size
tilted.minimum_client_size = 8

local function any_button(buttons)
    for i = 1, #buttons do
        if buttons[i] then
            return true
        end
    end
    return false
end

local function get_titlebar_sizes(client)
    local _, top = client:titlebar_top()
    local _, bottom = client:titlebar_bottom()
    local _, left = client:titlebar_left()
    local _, right = client:titlebar_right()
    return left, right, top, bottom
end

local function get_geometry(client, useless_gap)
    local left, right, top, bottom = get_titlebar_sizes(client)
    local border_width = client.border_width
    local real_geometry = client:geometry()
    local geometry = {
        x = real_geometry.x - useless_gap - border_width,
        y = real_geometry.y - useless_gap - border_width,
        width = real_geometry.width + (2 * (border_width + useless_gap)),
        height = real_geometry.height + (2 * (border_width + useless_gap)),
    }
    local min_size = {
        width = (geometry.width - real_geometry.width) + tilted.minimum_client_size + left + right,
        height = (geometry.height - real_geometry.height) + tilted.minimum_client_size + top + bottom,
    }
    return geometry, min_size
end

local function apply_size_hints(client, width, height, useless_gap)
    local left, right, top, bottom = get_titlebar_sizes(client)
    local border_width = 2 * (client.border_width + useless_gap)
    width, height = width - border_width, height - border_width
    width, height = client:apply_size_hints(
        math.max(width, tilted.minimum_client_size + top + bottom + border_width),
        math.max(height, tilted.minimum_client_size + left + right + border_width))
    return width + border_width, height + border_width
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
    return _x, _y, _width, _height, is_horizontal, is_reversed, is_reversed_x, is_reversed_y
end

local function resize(orientation, screen, tag, client, corner)
    if not screen or not tag or not client or not client.valid then
        return
    end

    capi.mousegrabber.stop()

    local layout_descriptor = tag.tilted_layout_descriptor
    if not layout_descriptor then
        return
    end

    local parameters = alayout.parameters(tag, screen)

    local column_descriptor, index = layout_descriptor:find_client(client, parameters.clients)
    if not column_descriptor then
        return
    end

    local _x, _y, _width, _height, is_horizontal, _, is_reversed_x, is_reversed_y = get_orientation_info(orientation)
    local _fx, _fy = is_horizontal and _x or _y, is_horizontal and _y or _x

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

    local workarea = parameters.workarea
    local useless_gap = parameters.useless_gap

    local initial_geometry = get_geometry(client, useless_gap)
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

    capi.mousegrabber.run(function(coords)
        if client.valid and any_button(coords.buttons) then
            local current_column_descriptor, current_index = layout_descriptor:find_client(client, aclient.tiled(screen))
            if column_descriptor ~= current_column_descriptor or index ~= current_index then
                return false
            end

            coords.x = coords.x + coords_offset.x
            coords.y = coords.y + coords_offset.y

            local min_size = select(2, get_geometry(client, useless_gap))
            local factors = {}

            if directions[_fx] ~= 0 then
                local value = directions[_fx] < 0
                    and (initial_geometry[_x] + initial_geometry[_width] - coords[_x])
                    or (coords[_x] - initial_geometry[_x])
                factors[_fx] = math.max(min_size[_width], value) / workarea[_width]
            end

            if directions[_fy] ~= 0 then
                local value = directions[_fy] < 0
                    and (initial_geometry[_y] + initial_geometry[_height] - coords[_y])
                    or (coords[_y] - initial_geometry[_y])
                factors[_fy] = math.max(min_size[_height], value) / workarea[_height]
            end

            layout_descriptor:set_factors(column_descriptor, index, factors, original_directions)
            return true
        else
            return false
        end
    end, cursor)
end

local function arrange(parameters, orientation)
    local tag = parameters.tag
    local screen = parameters.screen and capi.screen[parameters.screen]
    if not tag and screen then
        tag = screen.selected_tag
    end
    if not tag or not screen then
        return
    end

    local clients = parameters.clients
    local workarea = parameters.workarea
    local useless_gap = parameters.useless_gap

    local layout_descriptor = tilted_layout_descriptor.update(tag, clients)

    local _x, _y, _width, _height, _, is_reversed = get_orientation_info(orientation)

    local geometries = parameters.geometries
    local width = workarea[_width]
    local x = workarea[_x]
    local offset_x = x

    for column = 1, layout_descriptor.size do
        column = is_reversed and (layout_descriptor.size - column + 1) or column
        local column_descriptor = layout_descriptor[column]
        local column_width = column_descriptor.factor * width

        for index = column_descriptor.from, column_descriptor.to do
            local client = clients[index]
            local size_hints = client.size_hints
            local width_hint = size_hints["min_" .. _width] or size_hints["base_" .. _width] or 0
            column_width = math.max(width_hint, column_width)
        end

        local available_width = width - (x - offset_x)
        column_width = math.max(1, math.min(column_width, available_width))

        local actual_column_width = 0
        local height = workarea[_height]
        local y = workarea[_y]

        for index = column_descriptor.from, column_descriptor.to do
            local client = clients[index]
            local i = index - column_descriptor.from + 1

            local geometry = {}
            geometry[_width] = column_width
            geometry[_height] = math.max(1, math.floor(column_descriptor[i].factor * height))
            geometry[_x] = x
            geometry[_y] = y
            geometries[client] = geometry

            geometry.width, geometry.height = apply_size_hints(client, geometry.width, geometry.height, useless_gap)

            actual_column_width = math.max(actual_column_width, geometry[_width])
            y = y + geometry[_height]
        end
        x = x + actual_column_width
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

function tilted.right.arrange(p)
    return arrange(p, "right")
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

function tilted.left.arrange(p)
    return arrange(p, "left")
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

function tilted.bottom.arrange(p)
    return arrange(p, "bottom")
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

function tilted.top.arrange(p)
    return arrange(p, "top")
end

function tilted.top.resize(...)
    return resize("top", ...)
end

tilted.is_tilted = true
tilted.name = tilted.right.name
tilted.arrange = tilted.right.arrange
tilted.resize = tilted.right.resize

amouse.resize.add_enter_callback(function(client, args)
    local screen = client.screen
    local tag = screen.selected_tag
    local layout = tag and tag.layout or nil
    if layout and layout.is_tilted then
        if client.floating then
            return
        end
        if layout.resize then
            layout.resize(screen, tag, client, args.corner)
        end
        return false
    end
end, "mouse.resize")

tilted_layout_descriptor.tilted = tilted

return tilted
