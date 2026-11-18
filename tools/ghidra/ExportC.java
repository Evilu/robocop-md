// Post-analysis export: function table and decompiled C.
// args: <output directory>
import java.io.File;
import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;

public class ExportC extends GhidraScript {
    @Override
    public void run() throws Exception {
        File dir = new File(getScriptArgs()[0]);
        dir.mkdirs();
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        int n = 0;
        int failed = 0;
        try (PrintWriter tsv = new PrintWriter(new File(dir, "functions.tsv"));
             PrintWriter c = new PrintWriter(new File(dir, "decomp.c"))) {
            tsv.println("address\tsize\tname\tcallers\tcallees");
            FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
            while (it.hasNext() && !monitor.isCancelled()) {
                Function f = it.next();
                tsv.println(f.getEntryPoint() + "\t" + f.getBody().getNumAddresses() + "\t" + f.getName() + "\t"
                    + f.getCallingFunctions(monitor).size() + "\t" + f.getCalledFunctions(monitor).size());
                DecompileResults r = dec.decompileFunction(f, 30, monitor);
                c.println("// ---- " + f.getEntryPoint() + " " + f.getName());
                if (r != null && r.decompileCompleted()) {
                    c.println(r.getDecompiledFunction().getC());
                } else {
                    c.println("// decompile failed");
                    failed++;
                }
                n++;
            }
        }
        println("exported " + n + " functions, " + failed + " failed, to " + dir);
    }
}
