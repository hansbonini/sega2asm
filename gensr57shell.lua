-- -------------------------------------------- --
-- Sega Genesis/Mega Drive ROM Segment Tracer   --
-- -------------------------------------------- --
-- Generates a segments.yaml file for sega2asm  --
-- based on executed code and data references.  --
-- -------------------------------------------- --
-- Usage: Run this script in Gens R57SHELL Mod. --
-- press 'S' to export the segments.yaml file.  --
-- -------------------------------------------  --

-- Configuration
local OUTPUT_FILE = "segments.yaml"

function get_dynamic_rom_size()
    if memory.getromsize then return memory.getromsize() end
    local rom_end = memory.readlongunsigned(0x0001A4)
    if rom_end < 0x0001FF or rom_end > 0x3FFFFF then return 0x400000 end
    return rom_end + 1
end

local ROM_SIZE = get_dynamic_rom_size()
local segments = {}
local current_start = nil

-- BITMASK: 0 = unknown, 1 = discovered
local bitmask = {} 

-- Function to mark bytes as discovered in the bitmask
function mark_discovered(addr, size)
    if not addr or addr < 0 or addr >= ROM_SIZE then return end
    for i = 0, (size - 1) do
        local target = addr + i
        if target < ROM_SIZE then
            bitmask[target] = 1
        end
    end
end

-- Function to calculate real coverage based on bitmask
function get_real_coverage()
    local count = 0
    for k, v in pairs(bitmask) do
        count = count + 1
    end
    return (count / ROM_SIZE) * 100
end

function close_current(end_addr)
    if current_start and end_addr > current_start then
        if not segments[current_start] then
            segments[current_start] = {
                stop = end_addr,
                type = "m68k",
                subdir = "code",
                name = string.format("sub_%06X", current_start)
            }
            -- Mark the range as discovered in the mask
            mark_discovered(current_start, end_addr - current_start)
        end
    end
    current_start = nil
end

function add_data_seg(addr, size)
    if not addr or addr < 0 or addr >= ROM_SIZE then return end
    if not segments[addr] then
        segments[addr] = {
            stop = addr + size,
            type = "bin",
            subdir = "assets",
            name = string.format("data_%06X", addr)
        }
        mark_discovered(addr, size)
    end
end

memory.registerexec(0x000000, ROM_SIZE, function(pc)
    if pc >= ROM_SIZE then return end
    
    -- Every byte executed is a discovered byte
    mark_discovered(pc, 2) 

    local opcode = memory.readwordunsigned(pc)
    if not current_start then current_start = pc end

    -- Flow Terminators
    local is_return = (opcode == 0x4E75 or opcode == 0x4E73 or opcode == 0x4E77)
    local is_jump = (bit.band(opcode, 0xFF00) == 0x6000 or bit.band(opcode, 0xFFC0) == 0x4EC0)

    if is_return or is_jump then
        close_current(pc + 2)
        return
    end

    -- Subroutine Calls
    if bit.band(opcode, 0xFF00) == 0x6100 or bit.band(opcode, 0xFFC0) == 0x4E80 then
        close_current(pc + 4)
        return
    end

    -- Data Tracking (LEA / PEA / MOVE.L)
    if opcode == 0x41F9 or opcode == 0x4879 then
        local ptr = memory.readlongunsigned(pc + 2)
        add_data_seg(ptr, 2) -- Start with 2 bytes, increase as seen
    elseif bit.band(opcode, 0xF1FF) == 0x203C then
        local ptr = memory.readlongunsigned(pc + 2)
        add_data_seg(ptr, 4) -- MOVE.L usually points to at least a long
    elseif opcode == 0x41FA then
        local offset = memory.readword(pc + 2)
        add_data_seg(pc + 2 + offset, 2)
    end
end)

function export_to_yaml()
    local file = io.open(OUTPUT_FILE, "w")
    if not file then return end
    file:write("segments:\n")
    local sorted = {}
    for s in pairs(segments) do table.insert(sorted, s) end
    table.sort(sorted)

    for i, s in ipairs(sorted) do
        local data = segments[s]
        local end_addr = data.stop
        
        -- YAML continuity logic (for sega2asm)
        if sorted[i+1] then
            end_addr = sorted[i+1]
        else
            end_addr = ROM_SIZE
        end

        file:write(string.format("  - name: %s\n", data.name))
        file:write(string.format("    type: %s\n", data.type))
        file:write(string.format("    start: 0x%06X\n", s))
        file:write(string.format("    end:   0x%06X\n", end_addr))
        file:write(string.format("    subdir: %s\n\n", data.subdir))
    end
    file:close()
    print("YAML Exported.")
end

gui.register(function()
    local perc = get_real_coverage()
    if current_start then
        gui.text(10, 10, string.format("Tracing: %06X | Real Map: %.4f%%", current_start, perc))
    else
        gui.text(10, 10, string.format("Idle | Real Map: %.4f%%", perc))
    end
    if input.get()['S'] then export_to_yaml() end
end)