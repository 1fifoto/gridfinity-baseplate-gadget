-- Pure geometry and validation helpers for the Gridfinity Baseplate gadget.
-- This file deliberately has no Vectric API dependencies so it can be unit tested.

local M = {}

M.PITCH_MM = 42.0
M.CLEARANCE_MM = 0.25
M.TOP_OPENING_MM = M.PITCH_MM - 2.0 * M.CLEARANCE_MM
M.TOP_RADIUS_MM = 3.75
M.UPPER_CHAMFER_MM = 2.15
M.VERTICAL_WALL_MM = 1.8
M.LOWER_CHAMFER_MM = 0.7
M.MID_OPENING_MM = M.TOP_OPENING_MM - 2.0 * M.UPPER_CHAMFER_MM
M.MID_RADIUS_MM = M.TOP_RADIUS_MM - M.UPPER_CHAMFER_MM
M.BOTTOM_OPENING_MM = M.MID_OPENING_MM - 2.0 * M.LOWER_CHAMFER_MM
M.BOTTOM_RADIUS_MM = M.MID_RADIUS_MM - M.LOWER_CHAMFER_MM
M.MID_DEPTH_MM = M.UPPER_CHAMFER_MM
M.LOWER_START_DEPTH_MM = M.UPPER_CHAMFER_MM + M.VERTICAL_WALL_MM
M.TOTAL_DEPTH_MM = M.LOWER_START_DEPTH_MM + M.LOWER_CHAMFER_MM

function M.to_job_units(value_mm, job_in_mm)
  if job_in_mm then
    return value_mm
  end
  return value_mm / 25.4
end

function M.tool_value_in_job_units(value, tool_in_mm, job_in_mm)
  if tool_in_mm == job_in_mm then
    return value
  end
  if tool_in_mm then
    return value / 25.4
  end
  return value * 25.4
end

function M.profile_at_depth_mm(depth_mm)
  local d = math.max(0.0, math.min(depth_mm, M.TOTAL_DEPTH_MM))
  if d <= M.MID_DEPTH_MM then
    return M.TOP_OPENING_MM - 2.0 * d, M.TOP_RADIUS_MM - d
  end
  if d <= M.LOWER_START_DEPTH_MM then
    return M.MID_OPENING_MM, M.MID_RADIUS_MM
  end
  local lower_depth = d - M.LOWER_START_DEPTH_MM
  return M.MID_OPENING_MM - 2.0 * lower_depth,
         M.MID_RADIUS_MM - lower_depth
end

function M.profile_dimensions_at_depth_mm(depth_mm, cell_width_mm, cell_height_mm)
  local standard_width, radius = M.profile_at_depth_mm(depth_mm)
  local inset = (M.TOP_OPENING_MM - standard_width) * 0.5
  return cell_width_mm - 2.0 * M.CLEARANCE_MM - 2.0 * inset,
         cell_height_mm - 2.0 * M.CLEARANCE_MM - 2.0 * inset,
         radius
end

-- Return a conservative centerline region for a circular cutter. When the
-- cutter is larger than the desired corner radius, stay inside the rectangular
-- core instead of approximating an unsafe negative corner radius.
function M.inset_profile(width, height, radius, offset)
  if offset <= radius then
    return width - 2.0 * offset, height - 2.0 * offset, radius - offset
  end
  return width - 2.0 * radius - 2.0 * offset,
         height - 2.0 * radius - 2.0 * offset,
         0.0
end

function M.grid_size_mm(columns, rows)
  return columns * M.PITCH_MM, rows * M.PITCH_MM
end

function M.validate_grid(columns, rows, origin_x, origin_y, job_min_x, job_min_y,
                         job_width, job_height, pitch_x, pitch_y)
  if columns < 1 or rows < 1 then
    return false, "Rows and columns must both be at least 1."
  end
  if columns > 100 or rows > 100 then
    return false, "Rows and columns are limited to 100 to avoid oversized toolpaths."
  end
  if pitch_x <= 0.0 or pitch_y <= 0.0 then
    return false, "Cell width and height must both be positive."
  end
  local width = columns * pitch_x
  local height = rows * pitch_y
  local eps = math.max(pitch_x, pitch_y) * 0.000001
  if origin_x < job_min_x - eps or origin_y < job_min_y - eps or
     origin_x + width > job_min_x + job_width + eps or
     origin_y + height > job_min_y + job_height + eps then
    return false, "The baseplate does not fit inside the current job."
  end
  return true, nil
end

function M.validate_tool_geometry(rough_dia, finish_dia, vbit_dia, vbit_angle,
                                  allowance, total_depth, material_thickness,
                                  minimum_opening)
  if rough_dia <= 0.0 or finish_dia <= 0.0 or vbit_dia <= 0.0 then
    return false, "All selected tools must have a positive diameter."
  end
  local smallest_opening = minimum_opening or M.BOTTOM_OPENING_MM
  if smallest_opening <= 0.0 then
    return false, "The custom cell size is too small for the Gridfinity profile."
  end
  if rough_dia >= smallest_opening or finish_dia >= smallest_opening then
    return false, string.format(
      "The selected end mills do not fit the %.3f mm bottom opening. " ..
      "Roughing: %.3f mm (%.4f in); finishing: %.3f mm (%.4f in). " ..
      "Choose smaller end mills.",
      smallest_opening, rough_dia, rough_dia / 25.4,
      finish_dia, finish_dia / 25.4)
  end
  if finish_dia * 0.5 > M.BOTTOM_RADIUS_MM + 0.000001 then
    return false, string.format(
      "The selected finishing end mill is %.3f mm (%.4f in). " ..
      "It is too large for the 0.9 mm bottom corner radius. " ..
      "Change it to a 1/16 inch end mill (1.5875 mm), or another cutter no larger than 1.8 mm.",
      finish_dia, finish_dia / 25.4)
  end
  if math.abs(vbit_angle - 90.0) > 0.5 then
    return false, string.format(
      "The selected V-bit has a %.1f degree included angle. " ..
      "Change it to a 90 degree included-angle V-bit (45 degrees per side).",
      vbit_angle)
  end
  local lower_chamfer_max_diameter = 2.0 * M.LOWER_CHAMFER_MM
  if vbit_dia > lower_chamfer_max_diameter + 0.000001 then
    return false, string.format(
      "The selected 90 degree V-bit is %.3f mm (%.4f in) in diameter. " ..
      "Its cone will gouge the 1.8 mm vertical wall when its tip reaches the 0.7 mm bottom chamfer. " ..
      "A lower-chamfer V-cutter can be no larger than %.3f mm (%.4f in), " ..
      "but that is too small to cut the 2.15 mm upper chamfer. " ..
      "One conventional V-bit cannot safely cut both chamfers; the bottom-chamfer toolpath strategy must change.",
      vbit_dia, vbit_dia / 25.4,
      lower_chamfer_max_diameter, lower_chamfer_max_diameter / 25.4)
  end
  if vbit_dia + 0.000001 < 2.0 * M.UPPER_CHAMFER_MM then
    return false, string.format(
      "The selected V-bit is %.3f mm (%.4f in) in diameter. " ..
      "Change it to a V-bit at least 4.3 mm in diameter for the 2.15 mm upper chamfer.",
      vbit_dia, vbit_dia / 25.4)
  end
  if allowance < 0.0 or allowance >= 1.0 then
    return false, "Roughing allowance must be between 0 and 1 mm."
  end
  if material_thickness + 0.000001 < total_depth then
    return false, "Material must be at least 4.65 mm thick."
  end
  return true, nil
end


function M.validate_magnets(include_magnets, hole_diameter, hole_depth, chamfer,
                            edge_inset, base_thickness, cell_width, cell_height,
                            finish_diameter, total_depth, material_thickness)
  if not include_magnets then
    return true, nil
  end
  if hole_diameter <= 0.0 or hole_depth <= 0.0 then
    return false, "Magnet-hole diameter and depth must be positive."
  end
  if finish_diameter >= hole_diameter then
    return false, "The finishing end mill must be smaller than the magnet-hole diameter."
  end
  if chamfer < 0.0 or chamfer >= hole_diameter * 0.5 then
    return false, "Magnet-hole chamfer must be non-negative and smaller than the hole radius."
  end
  if edge_inset <= hole_diameter * 0.5 + chamfer or
     edge_inset >= math.min(cell_width, cell_height) * 0.5 then
    return false, "Magnet-hole inset does not keep the chamfer inside each cell."
  end
  if base_thickness < 0.0 then
    return false, "Magnet base thickness cannot be negative."
  end
  if material_thickness + 0.000001 < total_depth + hole_depth + base_thickness then
    return false, "The material is too thin for the socket, magnet depth, and retained base."
  end
  return true, nil
end

return M
