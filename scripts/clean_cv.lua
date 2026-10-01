-- Pandoc Lua filter: clean up LaTeX CV artifacts for GitHub-Flavored Markdown.
--
-- Expects the reader to be run as `-f latex+raw_tex-latex_macros` so custom
-- macros (\cvsection, \cvlink) reach this filter as raw LaTeX instead of
-- being expanded or dropped by Pandoc.

-- Commands that only affect PDF layout and have no Markdown equivalent.
local STRIP = {
  vspace = true, hspace = true, pagebreak = true, newpage = true,
  clearpage = true, smallskip = true, medskip = true, bigskip = true,
  vfill = true, hfill = true, noindent = true, centering = true,
  huge = true, Huge = true, large = true, Large = true, LARGE = true,
  small = true, footnotesize = true, normalsize = true,
  newcommand = true, renewcommand = true, pagestyle = true,
  thispagestyle = true, titleformat = true, setlist = true,
}

local function is_latex(fmt)
  return fmt == "latex" or fmt == "tex"
end

-- Parse a LaTeX fragment into a list of inlines.
local function latex_inlines(src)
  local doc = pandoc.read(src, "latex+raw_tex-latex_macros")
  local first = doc.blocks[1]
  if first and first.content then
    return pandoc.Inlines(first.content)
  end
  return pandoc.Inlines(pandoc.Str(src))
end

-- Read N brace-delimited arguments starting at `pos`, honoring nesting.
local function read_args(src, pos, n)
  local args = {}
  for _ = 1, n do
    pos = src:find("{", pos, true)
    if not pos then return nil end
    local depth, start = 0, pos + 1
    for i = pos, #src do
      local c = src:sub(i, i)
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
        if depth == 0 then
          table.insert(args, src:sub(start, i - 1))
          pos = i + 1
          break
        end
      end
    end
    if depth ~= 0 then return nil end
  end
  return args, pos
end

local function command_name(src)
  return src:match("^%s*\\(%a+)%*?")
end

local function make_link(src)
  local args = read_args(src, 1, 2)
  if not args then return nil end
  return pandoc.Link(latex_inlines(args[2]), args[1])
end

-- Created at level 1; the Header pass below shifts it to level 2 (##).
local function make_header(title)
  return pandoc.Header(1, latex_inlines(title), pandoc.Attr("", { "unnumbered" }))
end

function RawInline(el)
  if not is_latex(el.format) then return nil end
  local cmd = command_name(el.text)
  if cmd == "cvlink" or cmd == "href" then
    return make_link(el.text) or {}
  end
  if STRIP[cmd] then
    return {}
  end
  return nil
end

function RawBlock(el)
  if not is_latex(el.format) then return nil end
  local cmd = command_name(el.text)
  if cmd == "cvsection" then
    local args = read_args(el.text, 1, 1)
    if args then return make_header(args[1]) end
  elseif cmd == "cvlink" or cmd == "href" then
    local link = make_link(el.text)
    if link then return pandoc.Para({ link }) end
  end
  if STRIP[cmd] then
    return {}
  end
  return nil
end

-- \cvsection and \section map to level 1, \subsection to 2. Shift every
-- header down one level so CV sections become ## and entries ###.
function Header(el)
  el.level = math.min(el.level + 1, 6)
  el.classes = el.classes:filter(function(c) return c ~= "unnumbered" end)
  el.classes:insert("unnumbered")
  return el
end

-- Unwrap layout-only environments (e.g. center) so GFM gets plain content.
function Div(el)
  if el.classes:includes("center") then
    return el.content
  end
  return nil
end

return {
  { RawInline = RawInline, RawBlock = RawBlock },
  { Header = Header, Div = Div },
}
