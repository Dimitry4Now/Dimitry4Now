-- Pandoc Lua filter: turn the "Jake's Resume" style cv.tex into clean
-- GitHub-Flavored Markdown for the README.
--
-- Pandoc expands the resume macros (\resumeSubheading, \resumeItem, ...)
-- itself, which leaves each entry as a list item whose first block is a
-- layout table. This filter rewrites those tables into headings and plain
-- text, and drops what only matters for the PDF layout.

local function is_latex(fmt)
  return fmt == "latex" or fmt == "tex"
end

local function trim(inlines)
  while #inlines > 0 and (inlines[1].t == "Space" or inlines[1].t == "SoftBreak") do
    inlines:remove(1)
  end
  while #inlines > 0 and (inlines[#inlines].t == "Space" or inlines[#inlines].t == "SoftBreak") do
    inlines:remove(#inlines)
  end
  return inlines
end

local function cell_inlines(cell)
  local inlines = trim(pandoc.utils.blocks_to_inlines(cell.contents))
  -- Empty macro arguments still leave e.g. an empty \textit{} behind.
  if pandoc.utils.stringify(inlines):match("^%s*$") then
    return pandoc.Inlines({})
  end
  return inlines
end

-- All rows of a layout table as lists of inlines, skipping empty rows.
local function table_rows(tbl)
  local rows = {}
  local function add(row)
    local cells, empty = {}, true
    for _, cell in ipairs(row.cells) do
      local inl = cell_inlines(cell)
      if #inl > 0 then empty = false end
      table.insert(cells, inl)
    end
    if not empty then table.insert(rows, cells) end
  end
  for _, row in ipairs(tbl.head.rows) do add(row) end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.head) do add(row) end
    for _, row in ipairs(body.body) do add(row) end
  end
  return rows
end

local function join(parts, sep)
  local out = pandoc.Inlines({})
  for _, part in ipairs(parts) do
    if #part > 0 then
      if #out > 0 then out:extend(sep) end
      out:extend(part)
    end
  end
  return out
end

local function separator()
  return pandoc.Inlines({ pandoc.Space(), pandoc.Str("|"), pandoc.Space() })
end

-- Rewrite one list item that starts with a layout table. Returns either
-- blocks (heading entry) or nil plus inlines (simple one-line entry).
local function rewrite_entry(item)
  local rows = table_rows(item[1])
  local rest = { table.unpack(item, 2) }

  if #rows == 1 and #rest == 0 then
    return nil, join(rows[1], separator())
  end

  local title = pandoc.Inlines(rows[1] and rows[1][1] or {})
  -- Headings are bold already, so drop a leading bold wrapper.
  if #title > 0 and title[1].t == "Strong" then
    local name = title[1].content
    title:remove(1)
    local rest_of_title = title
    title = pandoc.Inlines(name)
    title:extend(rest_of_title)
  end

  -- Remaining left-column cells first (role/degree), then right-column
  -- cells (dates), e.g. "*Sorsix, Skopje* | *04/2023 – Present*".
  local meta = {}
  for i, row in ipairs(rows) do
    if i > 1 then table.insert(meta, row[1]) end
  end
  for _, row in ipairs(rows) do
    for j = 2, #row do table.insert(meta, row[j]) end
  end

  local blocks = { pandoc.Header(3, title) }
  local meta_inlines = join(meta, separator())
  if #meta_inlines > 0 then
    table.insert(blocks, pandoc.Para(meta_inlines))
  end
  for _, b in ipairs(rest) do table.insert(blocks, b) end
  return blocks
end

function BulletList(el)
  local has_table = false
  for _, item in ipairs(el.content) do
    if item[1] and item[1].t == "Table" then has_table = true end
  end
  if not has_table then return nil end

  local out, pending = {}, {}
  local function flush()
    if #pending > 0 then
      table.insert(out, pandoc.BulletList(pending))
      pending = {}
    end
  end
  for _, item in ipairs(el.content) do
    if item[1] and item[1].t == "Table" then
      local blocks, inlines = rewrite_entry(item)
      if blocks then
        flush()
        for _, b in ipairs(blocks) do table.insert(out, b) end
      else
        table.insert(pending, { pandoc.Plain(inlines) })
      end
    else
      table.insert(pending, item)
    end
  end
  flush()
  return out
end

-- Split inlines on LineBreak into separate lines.
local function split_lines(inlines)
  local lines, current = {}, pandoc.Inlines({})
  for _, inl in ipairs(inlines) do
    if inl.t == "LineBreak" then
      table.insert(lines, trim(current))
      current = pandoc.Inlines({})
    else
      current:insert(inl)
    end
  end
  table.insert(lines, trim(current))
  local out = {}
  for _, line in ipairs(lines) do
    if #line > 0 then table.insert(out, line) end
  end
  return out
end

function Div(el)
  -- Centered title block: drop the name, keep the contact line.
  if el.classes:includes("center") then
    local para = el.content[1]
    if not para or not para.content then return {} end
    local lines = split_lines(para.content)
    table.remove(lines, 1)
    if #lines == 0 then return {} end
    return pandoc.Para(join(lines, { pandoc.Space() }))
  end

  -- Label-less itemize with \\-separated lines (Technical Skills).
  if el.classes:includes("itemize") then
    local items = {}
    for _, block in ipairs(el.content) do
      if block.content then
        for _, line in ipairs(split_lines(pandoc.utils.blocks_to_inlines({ block }))) do
          table.insert(items, { pandoc.Plain(line) })
        end
      end
    end
    return pandoc.BulletList(items)
  end
  return nil
end

-- Unwrap spans so blocks_to_inlines/line splitting see the real content.
function Span(el)
  if el.identifier == "" and #el.classes == 0 then
    return el.content
  end
  return nil
end

-- $|$ and $\sim$ are used as plain text separators in the PDF.
function Math(el)
  if el.mathtype == "InlineMath" then
    local text = el.text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "|" then return pandoc.Str("|") end
    if text == "\\sim" then return pandoc.Str("~") end
  end
  return nil
end

function RawInline(el)
  if is_latex(el.format) then return {} end
  return nil
end

function RawBlock(el)
  if is_latex(el.format) then return {} end
  return nil
end

-- \section is level 1. Shift down one level so CV sections become ##.
function Header(el)
  if el.level < 3 then
    el.level = el.level + 1
  end
  el.classes = el.classes:filter(function(c) return c ~= "unnumbered" end)
  return el
end

return {
  { Span = Span, Math = Math, RawInline = RawInline, RawBlock = RawBlock },
  { Div = Div },
  { Header = Header },
  { BulletList = BulletList },
}
