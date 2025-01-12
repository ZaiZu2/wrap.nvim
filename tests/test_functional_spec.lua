---@class State
---@field mode 'n'|'v'
---@field pos [integer, integer]|[integer, integer, integer, integer]

---@class TestCase
---@field id integer
---@field func 'Wrap comment'|'Wrap block'|'Wrap line' Name of a test function
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
			id = tonumber(line:match("TEST CASE: (%d+)"))
			goto continue
		end

		if func == nil then
			func = line:match("FUNCTION: (.*)")
			if not vim.tbl_contains({ "Wrap comment", "Wrap block", "Wrap line" }, func) then
				error(("Failed to parse FUNCTION of test case id=%s - `%s`"):format(id, func))
			end
			goto continue
		end

		if state == nil then
			local mode, pos
			temp = line:match("STATE: (.*)")
			if temp == nil then
				goto continue
			end

			mode, temp = temp:match("([nv]):(.*)")
			if mode == "n" then
				pos = { temp:match("^(%d+):(%d+)$") }
			elseif mode == "v" then
				pos = { temp:match("^(%d+):(%d+):(%d+):(%d+)$") }
			end
			pos = vim.tbl_map(tonumber, pos)

			if (mode == "n" and #pos == 2) or (mode == "v" and #pos == 4) then
				state = { mode = mode, pos = pos }
			else
				error("Failed to parse STATE of test case id=" .. id)
			end

			goto continue
		end

		if desc == nil then
			desc = line:match("DESCRIPTION: (.*)")
			goto continue
		else
			cur_index = i + 1
			break
		end

		::continue::
	end

	if not (id and func and state and desc) then
		error("Parsing failed for one of chunks")
	end

	local blocks = { {}, {} } ---@type [string[], string[]]
	for block_index, block_name in ipairs({ "INPUT", "OUTPUT" }) do
		local start_index, end_index
		for i = cur_index, #chunk do
			local temp

			if start_index == nil then
				temp = chunk[i]:match(block_name .. " START")
				if temp ~= nil then
					start_index = i
				end
				goto continue
			end

			if end_index == nil then
				temp = chunk[i]:match(block_name .. " END")
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
		error("Parsing failed for one of chunks")
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
---@return TestCase[] cases: List of parsed test cases
local function parse_test_file(fname)
	local lines = vim.fn.readfile(fname) ---@type string[]
	local chunks = {}
	local chunk = {}
	for _, line in ipairs(lines) do
		if line:match("TEST CASE:%s*%d+") then
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
	return test_cases
end

---Setup nvim buffer for a test case
---@param case TestCase
---@param ft string
local function setup_buffer(case, ft)
	-- Set up buffer
	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.bo.filetype = ft
	vim.api.nvim_buf_set_lines(bufnr, 0, 1, true, case.input)

	-- Set cursor/selection and mode
	local pos, mode = case.state.pos, case.state.mode
	if mode == "n" then
		vim.api.nvim_win_set_cursor(0, pos)
	elseif mode == "v" then
		vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] })
		vim.cmd("normal! v")
		vim.api.nvim_win_set_cursor(0, { pos[3], pos[4] })
	end
end

local rtp = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter/"
if not vim.tbl_contains(vim.opt.runtimepath:get(), rtp) then
	vim.opt.runtimepath:append(rtp)
end

---Assert that the resulting buffer is the same as expected
---@param case TestCase
local function assert_correct(case)
	local output = vim.api.nvim_buf_get_lines(0, 0, -1, true)

	local expected = case.output
	MiniTest.expect.equality(#expected, #output)
	for i, line in ipairs(output) do
		MiniTest.expect.equality(
			expected[i],
			line
			-- ('Line #%d differs - %s != %s'):format(i, line, expected[i])
		)
	end
end

local function setup_ts()
	local test_input_dir = vim.uv.cwd() .. "/tests/inputs/"
	for file_name in vim.fs.dir(test_input_dir, {}) do
		local ft = vim.filetype.match({ filename = file_name })
		if ft == nil then
			error("Unknown test input file: " .. test_input_dir .. file_name)
		end
		-- vim.print(vim.treesitter.language.get_lang(ft))
		-- vim.print(require("nvim-treesitter.info").installed_parsers())
		local parsers = require("nvim-treesitter.info").installed_parsers()
		--               vim.print(parsers)
		-- vim.print(vim.tbl_contains(parsers, 'javascript'))
		if not vim.tbl_contains(parsers, ft) then
			print("Trying to install " .. ft)
			vim.cmd("TSInstallSync " .. ft)
		end
	end
	require("wrap").setup({ line_width = 90 })
end

local new_set = MiniTest.new_set
local T = new_set({ hooks = { pre_once = setup_ts } })

local test_input_dir = vim.uv.cwd() .. "/tests/inputs/"
for file_name in vim.fs.dir(test_input_dir, {}) do
	local file_path = test_input_dir .. file_name
	local ft = vim.filetype.match({ filename = file_name })
	if ft == nil then
		error("Unknown filetype " .. ft)
	end

	local cases = parse_test_file(file_path)
	T["functional - " .. ft] = new_set({ parametrize = vim.tbl_map(function(case)
		return { case }
	end, cases) })
	T["functional - " .. ft]["works"] = function(case)
		setup_buffer(case, ft)
		vim.cmd(case.func)
		assert_correct(case)
		vim.api.nvim_buf_delete(0, { force = true })
	end
end

return T
-- local test_input_dir = vim.uv.cwd() .. "/tests/inputs/"
-- for file_name in vim.fs.dir(test_input_dir, {}) do
-- 	local file_path = test_input_dir .. file_name
-- 	local ft = vim.filetype.match({ filename = file_name })
-- 	if ft == nil then
-- 		error("Unknown filetype " .. ft)
-- 	end
--
-- 	describe(file_name .. ":", function()
-- 		before_each(function()
-- 			require("wrap").setup({
-- 				line_width = 90,
-- 			})
-- 		end)
--
-- 		local cases = parse_test_file(file_path)
-- 		for _, case in ipairs(cases) do
-- 			it(("%s: %s"):format(case.id, case.desc), function()
-- 				setup_buffer(case, ft)
-- 				vim.cmd(case.func)
-- 				assert_correct(case)
-- 			end)
-- 		end
--
-- 		after_each(function()
-- 			local bufnr = vim.api.nvim_get_current_buf()
-- 			vim.api.nvim_buf_delete(bufnr, { force = true })
-- 		end)
-- 	end)
-- end
