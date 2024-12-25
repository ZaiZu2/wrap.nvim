-- TODO: Add support for justification to TODO markers
-- TODO: Recognize strings comments and allow for their formatting (python)
-- TODO: Add indentation level based on currently pointed line
-- TODO: Add visual mode formatting?
-- FIXME: when rewrapped, empty lines are prepended with trailing whitespaces
-- FIXME: Handle comments which are part of a line with code on
-- FIXME: When wrapped line has a word which is shorted than available characters, it will loop endlessly and freeze nvim
-- FIXME: Weirdly acting custom node formatting when first line is tracing code
-- FIXME: Code gets deleted when above happens ^

local fmts = require 'wrap.fmts'
local temp = require 'utils' -- TODO: Temporary, delete
local utils = require 'wrap.utils'
local rules = require 'wrap.rules'
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

local function wrap_custom_paragraph(fmtr, com_lines, cur_y, node_range, bufnr)
    local row_start, col_start, row_end, col_end = unpack(node_range)
    -- Extract paragraph pointed by the cursor
    local rel_cur_y = cur_y - row_start + 1
    local paragraph_lines, left, right = fmtr:isolate_paragraph(com_lines, rel_cur_y)
    if paragraph_lines == nil then
        vim.notify 'Selected line consists only of whitespaces'
        return
    end
    -- Rewrap (reformat) the paragraph
    local paragraph_text = utils.concatenate_lines(paragraph_lines)
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(paragraph_text, com_length)
    -- Merge the paragraph into original comment lines
    com_lines = fmtr:merge_paragraph(com_lines, wrapped_lines, left, right)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(com_lines, col_start)
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(bufnr, row_start, col_start, row_end, col_end, buffer_lines)
end

local function wrap_multi_paragraph(fmtr, com_lines, cur_y, node_range, bufnr)
    local row_start, col_start, row_end, col_end = unpack(node_range)
    -- Extract paragraph pointed by the cursor
    local rel_cur_y = cur_y - row_start + 1
    local paragraph_lines, left, right = fmtr:isolate_paragraph(com_lines, rel_cur_y)
    if paragraph_lines == nil then
        vim.notify 'Selected line consists only of whitespaces'
        return
    end
    p { com_lines = com_lines }
    p { paragraph_lines = paragraph_lines, left = left, right = right }
    -- Rewrap (reformat) the paragraph
    local paragraph_text = utils.concatenate_lines(paragraph_lines)
    p { paragraph_text = paragraph_text }
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(paragraph_text, com_length)
    -- Merge the paragraph into original comment lines
    com_lines = fmtr:merge_paragraph(com_lines, wrapped_lines, left, right)
    p { com_lines = com_lines }
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(com_lines, col_start)
    p { buffer_lines = buffer_lines }
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(bufnr, row_start, col_start, row_end, col_end, buffer_lines)
end

local function wrap_single_paragraph(fmtr, init_node, cur_y, node_range, bufnr)
    local _, col_start, _, _ = unpack(node_range)
    -- Find all row-adjacent comment nodes
    local com_nodes = fmtr:find_adjacent_nodes(init_node)
    -- Parse all found nodes
    local com_lines = fmtr:parse_block(com_nodes, bufnr)
    -- Extract paragraph pointed by the cursor
    local first_row_start, _, _, _ = tr.get_node_range(com_nodes[1])
    local rel_cur_y = cur_y - first_row_start + 1
    local paragraph_lines, left, right = fmtr:isolate_paragraph(com_lines, rel_cur_y)
    if paragraph_lines == nil then
        vim.notify 'Selected line consists only of whitespaces'
        return
    end
    -- Rewrap (reformat) the paragraph
    local com_text = utils.concatenate_lines(paragraph_lines)
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(wrapped_lines, col_start)
    -- Replace buffer lines
    local paragraph_row_start, _, _, _ = tr.get_node_range(com_nodes[left])
    local _, _, paragraph_row_end, _ = tr.get_node_range(com_nodes[right])
    vim.api.nvim_buf_set_lines(
        bufnr,
        paragraph_row_start,
        paragraph_row_end + 1,
        true,
        buffer_lines
    )
end

local function wrap_custom_whole(fmtr, com_lines, node_range, bufnr)
    local row_start, col_start, row_end, col_end = unpack(node_range)
    -- Wrap comment
    local com_text = utils.concatenate_lines(com_lines)
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    table.insert(wrapped_lines, 1, '') -- Keep comment symbols on separate lines
    table.insert(wrapped_lines, #wrapped_lines + 1, '')
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(wrapped_lines, col_start)
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(bufnr, row_start, col_start, row_end, col_end, buffer_lines)
end

local function wrap_multi_whole(fmtr, com_lines, node_range, bufnr)
    local row_start, col_start, row_end, col_end = unpack(node_range)
    -- Rewrap (reformat) the paragraph
    local com_text = utils.concatenate_lines(com_lines)
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    table.insert(wrapped_lines, 1, '') -- Keep comment symbols on separate lines
    table.insert(wrapped_lines, #wrapped_lines + 1, '')
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(wrapped_lines, col_start)
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(bufnr, row_start, col_start, row_end, col_end, buffer_lines)
end

local function wrap_single_whole(fmtr, init_node, node_range, bufnr)
    local _, col_start, _, _ = unpack(node_range)
    -- Find all row-adjacent comment nodes
    local com_nodes = fmtr:find_adjacent_nodes(init_node)
    -- Parse all found nodes
    local com_lines = fmtr:parse_block(com_nodes, bufnr)
    -- Rewrap (reformat) the paragraph
    local com_text = utils.concatenate_lines(com_lines)
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(wrapped_lines, col_start)
    -- Replace buffer lines
    local block_row_start, block_col_start, _, _ = tr.get_node_range(com_nodes[1])
    local _, _, block_row_end, block_col_end = tr.get_node_range(com_nodes[#com_nodes])
    vim.api.nvim_buf_set_text(
        bufnr,
        block_row_start,
        block_col_start,
        block_row_end,
        block_col_end,
        buffer_lines
    )
end

function M.wrap(paragraph_only)
    paragraph_only = paragraph_only or false

    print ''
    print '-----------------'
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo.filetype
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    local cur_y, cur_x = unpack(cur_pos)
    cur_y, cur_x = cur_y - 1, cur_x -- Switch from (1,0) to (0,0) indexing
    local pointed_node, init_types, init_node, init_type

    -- Extract the node pointed at with the cursor
    -- tr.get_parser(bufnr):parse()
    pointed_node = tr.get_node { bufnr = bufnr, pos = { cur_y, cur_x } }
    if pointed_node == nil then
        vim.notify 'No Treesitter node under the cursor'
        return
    end

    -- Read filetype specific parsing rules
    init_types = utils.get_custom_nodes(ft, rules)
    if init_types == nil then
        vim.notify('wrap.nvim does not support ' .. ft)
        return
    end

    -- Find a relevant node
    init_node, init_type = utils.find_node(pointed_node, init_types)
    if init_node == nil or init_type == nil then
        vim.notify 'Did not find a node'
        return
    end

    local init_node_range = { tr.get_node_range(init_node) }
    local init_text = tr.get_node_text(init_node, bufnr)
    local multi_symbols, single_symbols = utils.get_node_symbols(init_type, ft, rules)
    p { modified_type = init_type, init_text = init_text }

    -- Try parsing as a multiline comment
    local multi_fmtr = fmts.MultiFormatter:new(multi_symbols, ft)
    local success, com_lines = pcall(multi_fmtr.parse, multi_fmtr, init_text)
    if success then
        if paragraph_only then
            wrap_multi_paragraph(multi_fmtr, com_lines, cur_y, init_node_range, bufnr)
        else
            wrap_multi_whole(multi_fmtr, com_lines, init_node_range, bufnr)
        end
        return
    end

    -- Multiline failed to parse, must be single-line
    local single_fmtr = fmts.SingleFormatter:new(single_symbols, ft)
    if paragraph_only then
        wrap_single_paragraph(single_fmtr, init_node, cur_y, init_node_range, bufnr)
    else
        wrap_single_whole(single_fmtr, init_node, init_node_range, bufnr)
    end
end

return M
