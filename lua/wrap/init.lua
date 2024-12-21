-- TODO: Add support for justification to TODO markers
-- TODO: Recognize strings comments and allow for their formatting (python)
-- FIXME: When wrapped line has a word which is shorted than available characters, it will loop endlessly and freeze nvim

local fmts = require 'wrap.fmts'
local rules = require 'wrap.rules'
local temp = require 'utils' -- TODO: Temporary, delete
local utils = require 'wrap.utils'
local p = temp.pprint

local M = {}

local _config = {
    line_width = 40,
}

local tr = vim.treesitter

function M.setup(config)
    config = config or {}
    _config = vim.tbl_deep_extend('force', _config, config)
end

---Find all row-adjacent nodes of the same type which create a block
---@param initial_node TSNode
---@param bufnr integer
---@return TSNode[]
local function find_adjacent_nodes(initial_node, bufnr)
    local initial_type = initial_node:type()
    local cur_start, _, cur_end, _ = tr.get_node_range(initial_node)
    local found_nodes = { initial_node }

    -- Find upward row-adjacent comments
    ---@type TSNode|nil
    local prev_node = initial_node
    while prev_node ~= nil do -- Redundant, acts as a type guard so LSP does not complain
        prev_node = prev_node:prev_named_sibling() ---@diagnostic disable-line: need-check-nil
        if prev_node == nil then
            break
        end

        local prev_start, _, prev_end, _ = tr.get_node_range(prev_node)
        local prev_text = tr.get_node_text(prev_node, bufnr)
        if prev_node:type() ~= initial_type or cur_start - prev_end > 1 or utils.is_whitespace_only(prev_text) then
            break
        end
        cur_start = prev_start
        table.insert(found_nodes, 1, prev_node) -- Prepend to table
    end

    -- Find downward row-adjacent comments
    ---@type TSNode|nil
    local next_node = initial_node
    while next_node ~= nil do -- Redundant, acts as a type guard so LSP does not complain
        next_node = next_node:next_named_sibling()
        if next_node == nil then
            break
        end

        local next_start, _, next_end, _ = tr.get_node_range(next_node)
        local next_text = tr.get_node_text(next_node, bufnr)
        if next_node:type() ~= initial_type or next_start - cur_end > 1 or utils.is_whitespace_only(next_text) then
            break
        end
        cur_end = next_end
        table.insert(found_nodes, next_node) -- Append to table
    end

    return found_nodes
end

--- Take in a string and split it into lines of maximum `line_width`.
--- Respects word boundaries, and split the string only on whitespaces.
--- @param comment string
--- @param line_width integer
--- @return table
local function wrap_string(comment, line_width)
    local wrapped_lines, _ = {}, nil

    --- @type integer|nil
    local com_split_end = 1
    --- @type integer|nil
    local com_split_start = 0

    local is_final_substr = false
    -- Iterate over `comment`, cutting chunks out of it and building lines out of it
    while not is_final_substr do
        comment = string.sub(comment, com_split_start + com_split_end, -1)
        -- Skip over leading whitspaces first
        _, com_split_start = string.find(comment, '^%s*')
        if com_split_start == nil then
            com_split_start = 1
        else
            com_split_start = com_split_start + 1
        end

        -- Find limits of a new line, accounting for comment length available left
        local line_start = com_split_start
        local line_end
        if line_start + line_width > #comment then
            line_end = #comment
            is_final_substr = true
        else
            line_end = line_start + line_width
        end

        -- Substring a new line
        local substring = string.sub(comment, line_start, line_end)
        if not is_final_substr then
            -- Find if the new line is not splitting a word in a middle
            -- If it does, find the closest whitespace to the left of that word
            com_split_end, _ = string.find(substring, '%s*%S*$')
            if com_split_end == nil then -- Text occupies a full line width
                com_split_end = line_width
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

---Parse a comment string to identify whether it's single-line
---@param com_text string Comment raw string
---@return string comment_body
---@return string comment_symbol Opening character/s denoting a comment
local function parse_singleline(com_text)
    local single_symbols = utils.get_comment_symbol('single', vim.bo.filetype, rules)
    if single_symbols ~= nil then
        -- Some languages have multiple symbols denoting a single-line comment
        for _, symbol in ipairs(single_symbols) do
            local prefix_rgx = '^%s*' .. utils.escape(symbol) -- Match opening symbol
            local body_rgx = '%s*(.-)%s*$' -- Match comment content, but strip all outer whitespaces
            local com_body = string.match(com_text, prefix_rgx .. body_rgx)
            if com_body ~= nil then
                return com_body, symbol
            end
        end
    else
        -- TODO: Implement inferred parsing
        -- infer_singleline()
    end
    vim.notify(('Failed to match single-line %s comment - `%s`'):format(vim.bo.filetype, com_text))
    error(('Failed to match single-line %s comment - `%s`'):format(vim.bo.filetype, com_text))
end

function M.wrap_comment()
    local bufnr = vim.api.nvim_get_current_buf()
    local cur_win = vim.api.nvim_get_current_win()

    local cur_pos = vim.api.nvim_win_get_cursor(0)
    local cur_y, cur_x = unpack(cur_pos)
    cur_y, cur_x = cur_y - 1, cur_x -- Switch from (1,0) to (0,0) indexing

    -- Extract the node pointed at with the cursor and find the comment
    tr.get_parser(bufnr):parse()
    local init_node = tr.get_node { bufnr = bufnr, pos = { cur_y, cur_x } }
    init_node = utils.find_node(init_node, 'comment')
    if init_node == nil then
        vim.notify 'Did not find a comment node'
        return
    end

    local init_row_start, init_col_start, init_row_end, _ = tr.get_node_range(init_node)
    local init_text = tr.get_node_text(init_node, bufnr)

    local multi_fmtr = fmts.MultiFormatter:new(_config.line_width, init_node, { cur_x, cur_y }, vim.bo.filetype)
    -- Try parsing as a multiline comment
    local success, com_lines = pcall(multi_fmtr.parse, multi_fmtr, init_text)
    if success then
        -- Extract paragraph pointed by the cursor
        local paragraph_lines, left, right = multi_fmtr:isolate_paragraph(com_lines)
        -- Rewrap (reformat) the paragraph
        local com_text = table.concat(paragraph_lines, ' ')
        local wrapped_lines = multi_fmtr:wrap(com_text)
        -- Merge the paragraph into original comment lines
        local merged_lines = multi_fmtr:merge_paragraph(com_lines, wrapped_lines, left, right)
        -- Replace buffer lines
        local buffer_lines = multi_fmtr:build_buf_lines(merged_lines)
        local row_start, row_end = init_row_start, init_row_end
        vim.api.nvim_buf_set_lines(bufnr, row_start, row_end + 1, true, buffer_lines)
        -- vim.api.nvim_win_set_cursor(cur_win, { rstart + 1, cur_x })

    -- Multiline didn't match, must be single-line
    else
        local string_length, wrapped_lines, buffer_lines = nil, nil, {}
        -- Find all row-adjacent comment nodes
        local comment_nodes = find_adjacent_nodes(init_node, bufnr)
        -- Extract node texts
        com_lines = {}
        for _, node in ipairs(comment_nodes) do
            local line = tr.get_node_text(node, bufnr)
            local com_body, com_symbol = parse_singleline(line)
            table.insert(com_lines, com_body)
        end
        local com_text = table.concat(com_lines, ' ')

        -- Set comment length based on the current indentation
        local com_symbol = utils.get_comment_symbol('single', vim.bo.filetype, rules)
        string_length = _config.line_width - init_col_start - #(com_symbol .. ' ')
        wrapped_lines = wrap_string(com_text, string_length)
        local indent = string.rep(' ', init_col_start)
        for i, line in ipairs(wrapped_lines) do
            buffer_lines[i] = indent .. com_symbol .. ' ' .. line
        end
        -- Replace buffer lines
        local rstart, _, _, _ = tr.get_node_range(comment_nodes[1])
        local _, _, rend, _ = tr.get_node_range(comment_nodes[#comment_nodes])
        vim.api.nvim_buf_set_lines(bufnr, rstart, rend + 1, true, buffer_lines)
        -- vim.api.nvim_win_set_cursor(cur_win, { rstart + 1, cur_x })
    end
end

-- vim.keymap.set('n', '<leader>F', M.wrap_comment, { desc = '[F]ormat comment string' })

return M
