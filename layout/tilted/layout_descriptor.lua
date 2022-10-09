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
                local id = cd[index - cd.from + 1]
                if id.index == index and id.window == client.window then
                    return cd, id
                end
                break
            end
        end
    end
end

local function normalize_factors(descriptor)
    local size = descriptor.size
    local last_size = descriptor.last_size or 1
    if size < 1 then
        return
    end
    if last_size < 1 then
        last_size = 1
    end

    local total = 0

    for i = 1, size do
        local item_descriptor = descriptor[i]
        if not item_descriptor.factor then
            item_descriptor.factor = 1 / last_size
        end
        total = total + item_descriptor.factor
    end

    if total > 0 then
        for i = 1, #descriptor do
            local item_descriptor = descriptor[i]
            item_descriptor.factor = item_descriptor.factor / total
        end
    end
end

function layout_descriptor.new(tag)
    return setmetatable({
        tag = tag,
        padding = {
            left = 0,
            right = 0,
            top = 0,
            bottom = 0,
        },
    }, { __index = layout_descriptor.object })
end

function layout_descriptor.update(tag, clients)
    local is_new = false
    local self = tag.tilted_layout_descriptor

    if not self then
        is_new = true
        self = layout_descriptor.new(tag)
    end

    local column = 1
    local index = 1

    local function update_next_column_descriptor(size)
        local column_descriptor = self[column]
        if not column_descriptor then
            column_descriptor = {}
            self[column] = column_descriptor
        end
        column_descriptor.index = column
        column_descriptor.from = index
        column_descriptor.to = index + size - 1
        column_descriptor.last_size = column_descriptor.size
        column_descriptor.size = size

        for i = 1, size do
            local item_descriptor = column_descriptor[i]
            if not item_descriptor then
                item_descriptor = {}
                column_descriptor[i] = item_descriptor
            end
            item_descriptor.index = index
            item_descriptor.window = clients[index].window

            index = index + 1
        end

        column = column + 1
    end

    local total_count = #clients
    local primary_count = total_count <= tag.master_count and total_count or tag.master_count
    local secondary_count = total_count - primary_count
    local secondary_column_count = secondary_count <= tag.column_count and secondary_count or tag.column_count

    if primary_count > 0 then
        update_next_column_descriptor(primary_count)
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
    self.from = size > 0 and 1 or 0
    self.to = size
    self.last_size = self.size
    self.size = size

    for i = 1, self.size do
        normalize_factors(self[i])
    end
    normalize_factors(self)

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
