local rules = require 'wrap.rules'
local tr = require 'vim.treesitter'
local utils = require 'wrap.utils'

MultiFormatter = {}

function MultiFormatter:new(node, cur_pos, filetype)
    local row_start, col_start, init_row_end, _ = tr.get_node_range(node)
    local new = {
        row_start = row_start,
        col_start = col_start,
        node = node,
        cur_pos = cur_pos,
        com_type = 'multi',
        filetype = filetype,
        symbols = utils.get_comment_symbol('multi', filetype, rules),
    }
    self.__index = self
    setmetatable(new, self)
    return new
end

function MultiFormatter:parse(text)
    local com_text
    -- Parse comment content out of a raw string
    if self.symbols ~= nil then
        local prefix_rgx = '^%s*' .. utils.escape(self.symbols[1]) -- Match opening symbol
        local body_rgx = '(.*)' -- Match comment content with all whitespaces and newline chars
        local suffix_rgx = utils.escape(self.symbols[2]) .. '%s*$' -- Match closing symbol
        com_text = string.match(text, prefix_rgx .. body_rgx .. suffix_rgx)
    else
        -- TODO: Implement inferred parsing
    end

    if com_text == nil then
        vim.notify(('Failed to match multiline %s comment - `%s`'):format(self.filetype, text))
        error(('Failed to match multiline %s comment - `%s`'):format(self.filetype, text))
    end

    -- Split comment content into lines
    com_text = com_text .. '\n' -- Needed for capturing last line
    local com_lines = {}
    for line in com_text:gmatch '(.-)\n' do -- Match groups separated by \n (split string)
        local trimmed_line = string.match(line, '^%s*(.-)%s*$')
        table.insert(com_lines, trimmed_line)
    end
    return com_lines
end

function MultiFormatter:isolate_paragraph(com_lines)
    local left, right
    -- Find and isolate a paragraph
    local rel_cur_y = self.cur_pos[1] - self.row_start + 1
    left, right = utils.find_subarray(com_lines, rel_cur_y, function(str)
        return not utils.is_whitespace_only(str)
    end)
    if left == -1 then
        vim.notify 'Selected line consists only of whitespaces'
        return
    end
    return table.move(com_lines, left, right, 1, {})
end

function MultiFormatter:wrap(com_text, line_length)
    local wrapped_lines, _ = {}, nil
    --- @type integer|nil
    local com_split_end = 1
    --- @type integer|nil
    local com_split_start = 0

    local is_final_substr = false
    -- Iterate over `comment`, cutting chunks out of it and building lines out of it
    while not is_final_substr do
        com_text = string.sub(com_text, com_split_start + com_split_end, -1)
        -- Skip over leading whitspaces first
        _, com_split_start = string.find(com_text, '^%s*')
        if com_split_start == nil then
            com_split_start = 1
        else
            com_split_start = com_split_start + 1
        end

        -- Find limits of a new line, accounting for comment length available left
        local line_start = com_split_start
        local line_end
        if line_start + line_length > #com_text then
            line_end = #com_text
            is_final_substr = true
        else
            line_end = line_start + line_length
        end

        -- Substring a new line
        local substring = string.sub(com_text, line_start, line_end)
        if not is_final_substr then
            -- Find if the new line is not splitting a word in a middle
            -- If it does, find the closest whitespace to the left of that word
            com_split_end, _ = string.find(substring, '%s*%S*$')
            if com_split_end == nil then -- Text occupies a full line width
                com_split_end = line_length
            -- TODO: Line might consist of only whitespaces (?), this is not handled here
            else
                com_split_end = com_split_end - 1
            end
            substring = string.sub(substring, 1, com_split_end)
        end

        table.insert(wrapped_lines, substring)
    end
    return wrapped_lines
end

function MultiFormatter:build_buffer_lines(lines)
    local buffer_lines
    local indent = string.rep(' ', self.init_col_start)
    for i, line in ipairs(lines) do
        local buffer_line, space
        space = utils.is_whitespace_only(line) and '' or ' ' -- Ternary expr alternative
        if #lines == 1 then -- If comment spans only 1 line
            buffer_line = indent .. self.symbols[1] .. space .. line .. space .. self.symbols[2]
        elseif i == 1 then -- If first line
            buffer_line = indent .. self.symbols[1] .. space .. line
        elseif i == #lines then -- If last line
            buffer_line = indent .. line .. space .. self.symbols[2]
        else -- If a generic line
            buffer_line = indent .. line
        end
        table.insert(buffer_lines, buffer_line)
    end
end

SingleFormatter = {}

function SingleFormatter:new()
    local new = {}
    setmetatable(new, { __index = self })
    self.__index = self
    return new
end

function SingleFormatter:parse(text) end

function SingleFormatter:find_adjacent_nodes(node, bufnr) end

function SingleFormatter:wrap(com_text, length) end

function SingleFormatter:build_buffer_lines(lines) end
