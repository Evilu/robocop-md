// Pre-analysis seeding for a flat 68000 ROM image loaded at 0.
// args: <machine: dec0|md> [A5 value in hex, or "-"]
import java.math.BigInteger;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.PointerDataType;
import ghidra.program.model.lang.Register;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.SourceType;

public class Seed68k extends GhidraScript {
    private void ram(String name, long start, long size) throws Exception {
        MemoryBlock b = currentProgram.getMemory().createUninitializedBlock(name, toAddr(start), size, false);
        b.setRead(true);
        b.setWrite(true);
    }

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String machine = args.length > 0 ? args[0] : "dec0";
        Memory mem = currentProgram.getMemory();
        MemoryBlock rom = mem.getBlocks()[0];
        rom.setName("rom");
        rom.setWrite(false);
        rom.setExecute(true);
        long size = rom.getSize();
        if (machine.equals("dec0")) {
            ram("shared_ram", 0x180000L, 0x1000);
            ram("bac06_1", 0x240000L, 0x6000);
            ram("bac06_2", 0x246000L, 0x6000);
            ram("bac06_3", 0x24c000L, 0x2000);
            ram("io", 0x30c000L, 0x20);
            ram("palette_rg", 0x310000L, 0x800);
            ram("palette_b", 0x314000L, 0x800);
            ram("workram", 0xff8000L, 0x4000);
            ram("spriteram", 0xffc000L, 0x800);
        } else {
            ram("z80", 0xa00000L, 0x10000);
            ram("io", 0xa10000L, 0x4200);
            ram("vdp", 0xc00000L, 0x20);
            ram("workram_mirror", 0xe0ff0000L, 0x10000);
            ram("workram", 0xff0000L, 0x10000);
        }
        String[] names = {"ssp", "reset", "bus_error", "address_error", "illegal", "zero_divide", "chk", "trapv",
            "privilege", "trace", "line_a", "line_f"};
        int seeded = 0;
        for (int i = 0; i < 64; i++) {
            Address slot = toAddr(i * 4L);
            long v = mem.getInt(slot) & 0xffffffffL;
            try {
                createData(slot, PointerDataType.dataType);
            } catch (Exception e) {
            }
            if (i == 0 || v >= size || (v & 1) != 0 || v < 0x100 && machine.equals("md")) {
                continue;
            }
            String n = i < names.length ? names[i] : i >= 25 && i <= 31 ? "irq" + (i - 24) : i >= 32 && i <= 47 ? "trap" + (i - 32) : "vec" + i;
            Address t = toAddr(v);
            disassemble(t);
            if (getFunctionAt(t) == null) {
                createFunction(t, n + "_handler");
                seeded++;
            }
        }
        if (args.length > 1 && !args[1].equals("-")) {
            Register a5 = currentProgram.getRegister("A5");
            currentProgram.getProgramContext().setValue(a5, rom.getStart(), rom.getEnd(),
                new BigInteger(args[1], 16));
        }
        setAnalysisOption(currentProgram, "Aggressive Instruction Finder", "true");
        println("seeded " + seeded + " entry points, rom size " + size);
    }
}
