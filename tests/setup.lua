---@class State
---@field mode string
---@field pos [integer, integer]|[integer, integer, integer, integer]

---@class TestCase
---@field id integer
---@field func string Name of a test function
---@field state State
---@field desc string
---@field input string[]
---@field output string[]

---Parse a test chunk into TestCase
---@param chunk string[]
---@return TestCase
local function parse_chunk(chunk)
    local cur_index = 1
    local id, func, state, desc
    for i, line in ipairs(chunk) do
        local temp

        if id == nil then
            id = tonumber(line:match 'TEST CASE: (%d+)')
            goto continue
        end

        if func == nil then
            func = line:match 'FUNCTION: (.*)'
            goto continue
        end

        if state == nil then
            local mode, pos
            temp = line:match 'STATE: (.*)'
            if temp == nil then
                goto continue
            end

            mode, temp = temp:match '([nv]):(.*)'
            if mode == 'n' then
                pos = { temp:match '^(%d+):(%d+)$' }
            elseif mode == 'v' then
                pos = { temp:match '^(%d+):(%d+):(%d+):(%d+)$' }
            end

            if (mode == 'n' and #pos == 2) or (mode == 'v' and #pos == 4) then
                state = { mode = mode, pos = pos }
            end

            goto continue
        end

        if desc == nil then
            desc = line:match 'DESCRIPTION: (.*)'
            goto continue
        else
            cur_index = i + 1
            break
        end

        ::continue::
    end

    if not (id and func and state and desc) then
        error 'Parsing failed for one of chunks'
    end

    local blocks = {{}, {}}---@type [string[], string[]]
    for block_index, block_name in ipairs { 'INPUT', 'OUTPUT' } do
        local start_index, end_index
        for i = cur_index, #chunk do
            local temp

            if start_index == nil then
                temp = chunk[i]:match(block_name .. ' START')
                if temp ~= nil then
                    start_index = i
                end
                goto continue
            end

            if end_index == nil then
                temp = chunk[i]:match(block_name .. ' END')
                if temp ~= nil then
                    end_index = i
                    blocks[block_index] = vim.list_slice(chunk, start_index + 1, end_index - 1)
                    cur_index = i + 1
                    break
                end
                goto continue
            end

            ::continue::
        end
    end
    local input, output = unpack(blocks)

    if not (input and output) then
        error 'Parsing failed for one of chunks'
    end

    return {
        id = id,
        func = func,
        state = state,
        desc = desc,
        input = input,
        output = output,
    }
end

---Parse test cases out of the input test file
---@param fname string Path to a test file
local function parse_test_file(fname)
    local lines = vim.fn.readfile(fname) ---@type string[]
    local chunks = {}
    local chunk = {}
    for _, line in ipairs(lines) do
        if line:match 'TEST CASE:%s*%d+' then
            if #chunk > 0 then
                table.insert(chunks, chunk)
            end
            chunk = {}
        end
        table.insert(chunk, line)
    end
    table.insert(chunks, chunk)

    local test_cases = {} ---@type TestCase[]
    for _, chunk in ipairs(chunks) do
        local test_case = parse_chunk(chunk)
        table.insert(test_cases, test_case)
    end
    vim.print(test_cases)
end

parse_test_file './tests/js.js'
