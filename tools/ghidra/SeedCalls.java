// Second-pass seeding: disassemble at every absolute JSR/JMP target and every
// "lea abs.l,An" / "pea abs.l" target that lands in ROM, when the referencing
// instruction itself sits in code Ghidra has already accepted or decodes cleanly.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.mem.Memory;

public class SeedCalls extends GhidraScript {
    @Override
    public void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        long size = mem.getBlock("rom").getSize();
        int seeded = 0;
        for (int pass = 0; pass < 3; pass++) {
            int before = seeded;
            for (long o = 0; o + 6 <= size; o += 2) {
                int op = mem.getShort(toAddr(o)) & 0xffff;
                boolean call = op == 0x4eb9 || op == 0x4ef9;
                boolean lea = (op & 0xf1ff) == 0x41f9 || op == 0x4879;
                if (!call && !lea) {
                    continue;
                }
                long t = mem.getInt(toAddr(o + 2)) & 0xffffffffL;
                if (t < 0x100 || t >= size || (t & 1) != 0) {
                    continue;
                }
                Address site = toAddr(o);
                Instruction ins = getInstructionAt(site);
                if (ins == null) {
                    if (getInstructionContaining(site) != null || getDataContaining(site) != null && pass == 0) {
                        continue;
                    }
                    if (pass < 2) {
                        continue;
                    }
                }
                Address target = toAddr(t);
                if (getInstructionAt(target) != null) {
                    if (call && getFunctionAt(target) == null) {
                        createFunction(target, null);
                    }
                    continue;
                }
                if (getInstructionContaining(target) != null) {
                    continue;
                }
                if (lea) {
                    int first = mem.getShort(target) & 0xffff;
                    boolean plausible = first == 0x48e7 || first == 0x4e56 || (first & 0xf000) == 0x6000
                        || (first & 0xf1c0) == 0x41c0 || (first & 0xc000) == 0 && first != 0 && first != 0xffff
                        || first == 0x4eb9 || first == 0x4a2d || first == 0x4a2e || first == 0x7000;
                    if (!plausible) {
                        continue;
                    }
                }
                disassemble(target);
                if (call || getInstructionAt(target) != null) {
                    createFunction(target, null);
                }
                seeded++;
            }
            analyzeChanges(currentProgram);
            println("pass " + pass + " seeded " + (seeded - before));
        }
    }
}
