local matrix = require("gears.matrix")


local helper_widget = {}

local function find_geometry_core(widget, drawable, hierarchy)
    if hierarchy:get_widget() == widget then
        local width, height = hierarchy:get_size()
        local x, y, w, h = matrix.transform_rectangle(hierarchy:get_matrix_to_device(), 0, 0, width, height)
        return {
            drawable = drawable,
            hierarchy = hierarchy,
            widget = hierarchy:get_widget(),
            widget_width = width,
            widget_height = height,
            x = x,
            y = y,
            width = w,
            height = h,
        }
    end

    for _, child in ipairs(hierarchy:get_children()) do
        local geometry = find_geometry_core(widget, drawable, child)
        if geometry then
            return geometry
        end
    end
end

function helper_widget.find_geometry(widget, wibox)
    local drawable = wibox._drawable
    if drawable._widget_hierarchy then
        return find_geometry_core(widget, drawable, drawable._widget_hierarchy)
    end
end

return helper_widget
