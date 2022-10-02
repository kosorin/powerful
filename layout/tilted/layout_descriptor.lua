local capi = {
    tag = tag,
}
local math = math
local setmetatable = setmetatable
local alayout = require("awful.layout")


local layout_descriptor = { object = {} }

function layout_descriptor.object:find_client(client, clients)
    if not client or not clients then
        return
    end

    local column_descriptor = nil
    local index = nil

    for i = 1, #clients do
        if clients[i] == client then
            index = i
            break
        end
    end

    if index then
        for i = 1, self.size do
            local cd = self[i]
            if cd.from <= index and index <= cd.to then
                if cd[index - cd.from + 1].window == client.window then
                    column_descriptor = cd
                end
                break
            end
        end
    end

    if column_descriptor then
        return column_descriptor, index
    end
end

local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

local function set_factor(descriptor, index, factor, direction)
    assert(direction ~= 0)

    local start = index - descriptor.from + 1

    if layout_descriptor.tilted.resize_only_neighbors then
        local neighbor = clamp(start + direction, 1, descriptor.size)
        if start ~= neighbor then
            local total = descriptor[start].factor + descriptor[neighbor].factor
            descriptor[start].factor = clamp(factor, 0.01, total - 0.01)
            descriptor[neighbor].factor = total - descriptor[start].factor
        end
    else
        descriptor[start].factor = clamp(factor, 0.01, 0.99)

        local stop = direction < 0 and 1 or descriptor.size
        local reverse_stop = direction > 0 and 1 or descriptor.size

        local rest = 1
        for i = start, reverse_stop, -direction do
            rest = rest - descriptor[i].factor
        end
        if rest > 0 then
            local total = 0
            for i = start + direction, stop, direction do
                total = total + descriptor[i].factor
            end
            if total > 0 then
                local f = rest / total
                for i = start + direction, stop, direction do
                    descriptor[i].factor = clamp(descriptor[i].factor * f, 0.01, 0.99)
                end
            end
        end
    end
end

function layout_descriptor.object:set_factors(column_descriptor, index, factors, directions)
    if directions.x ~= 0 then
        set_factor(self, column_descriptor.index, factors.x, directions.x)
    end
    if directions.y ~= 0 then
        set_factor(column_descriptor, index, factors.y, directions.y)
    end
    self.tag:emit_signal("property::tilted_layout_descriptor")
end

local function normalize_factors(descriptor, size, last_size)
    if not size or size < 1 then
        return
    end
    if not last_size or last_size < 1 then
        last_size = 1
    end

    local total = 0

    for i = 1, size do
        local item = descriptor[i]
        if not item then
            item = {}
            descriptor[i] = item
        end
        if not item.factor then
            item.factor = 1 / last_size
        end
        total = total + item.factor
    end

    if total > 0 then
        for i = 1, #descriptor do
            local item = descriptor[i]
            item.factor = item.factor / total
        end
    end
end

function layout_descriptor.update(tag, clients)
    local is_new = false
    local self = tag.tilted_layout_descriptor

    if not self then
        is_new = true
        self = setmetatable({ tag = tag }, { __index = layout_descriptor.object })
    end

    local total_count = #clients
    local primary_count = total_count <= tag.master_count and total_count or tag.master_count
    local secondary_count = total_count - primary_count
    local secondary_column_count = secondary_count <= tag.column_count and secondary_count or tag.column_count

    local column = 1
    local index = 1

    local function update_next_column_descriptor(size, is_primary)
        local column_descriptor = self[column]
        if not column_descriptor then
            column_descriptor = {}
            self[column] = column_descriptor
        end
        column_descriptor.is_primary = is_primary
        column_descriptor.index = column
        column_descriptor.from = index
        column_descriptor.to = index + size - 1

        local last_size = column_descriptor.size
        column_descriptor.size = size

        normalize_factors(column_descriptor, size, last_size)

        for i = 1, size do
            column_descriptor[i].window = clients[column_descriptor.from + i - 1].window
        end

        column = column + 1
        index = index + size
    end

    if primary_count > 0 then
        update_next_column_descriptor(primary_count, true)
    end

    if secondary_count > 0 and secondary_column_count > 0 then
        local column_size = math.floor(secondary_count / secondary_column_count)
        local extra_count = math.fmod(secondary_count, secondary_column_count)
        local last_simple_column = column - 1 + (secondary_column_count - extra_count)
        repeat
            local size = column_size
            if column > last_simple_column then
                size = size + 1
            end
            update_next_column_descriptor(size)
        until index > total_count
    end

    local size = column - 1
    local last_size = self.size

    self.from = size > 0 and 1 or 0
    self.to = size
    self.size = size

    normalize_factors(self, size, last_size)

    if is_new then
        tag.tilted_layout_descriptor = self
    else
        tag:emit_signal("property::tilted_layout_descriptor")
    end

    return self
end

capi.tag.connect_signal("property::tilted_layout_descriptor", function(t)
    alayout.arrange(t.screen)
end)

return layout_descriptor
