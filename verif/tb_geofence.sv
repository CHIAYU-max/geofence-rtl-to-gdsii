// Open self-checking testbench for geofence, driven by gen_patterns.py.
// Checks the result, the one-cycle valid pulse and that valid stays low otherwise.
// +PAT=<file> pattern file, +MAXCASE=<n> stop early, -define SDF for post-layout runs,
// RECV receivers per case (default 6), FSDB dumps switching activity.
`timescale 1ns/10ps
`ifndef CYCLE
`define CYCLE 30.0
`endif
`ifndef RECV
`define RECV 6
`endif
`ifndef SDFFILE
`define SDFFILE "./geofence_syn.sdf"
`endif

module tb_geofence;
    reg         clk = 0;
    reg         reset = 0;
    reg  [9:0]  X = 0;
    reg  [9:0]  Y = 0;
    wire        valid;
    wire        is_inside;

    geofence u_geofence (.clk(clk), .reset(reset), .X(X), .Y(Y), .valid(valid), .is_inside(is_inside));

`ifdef SDF
    initial $sdf_annotate(`SDFFILE, u_geofence);
`endif

    always #(`CYCLE/2) clk = ~clk;

`ifdef FSDB
    initial begin
        $fsdbDumpfile("novas.fsdb");
        $fsdbDumpvars();
    end
`endif

    integer fd, n, i, wait_cycles, code;
    integer errors = 0, cases = 0, inside_cases = 0, cycles_sum = 0, cycles_max = 0, maxcase = 0;
    integer c[0:2*`RECV+1];
    integer expected;
    string  pat, category;
    bit     expect_valid = 0;
    bit     seen_reset = 0;

    function automatic void fail(string msg);
        errors = errors + 1;
        if (errors <= 20) $display("ERROR case %0d (%s): %s", cases, category, msg);
    endfunction

    // valid may only be high in the cycle the main loop is waiting for
    always @(negedge clk) begin
        if (reset) seen_reset = 1;
        else if (seen_reset) begin
            if (valid === 1'bx || valid === 1'bz) fail("valid is unknown");
            else if (valid && !expect_valid) fail("unexpected valid");
        end
    end

    initial begin
        if (!$value$plusargs("PAT=%s", pat)) pat = "patterns.txt";
        void'($value$plusargs("MAXCASE=%d", maxcase));
        fd = $fopen(pat, "r");
        if (fd == 0) begin $display("cannot open %s", pat); $finish; end

        @(posedge clk); #2 reset = 1'b1;
        #(`CYCLE*2);
        @(posedge clk); #2 reset = 1'b0;

        forever begin
            n = 0;
            for (i = 0; i < 2*`RECV+2; i = i + 1) n = n + $fscanf(fd, "%d", c[i]);
            n = n + $fscanf(fd, "%d %s", expected, category);
            if (n != 2*`RECV+4 || (maxcase != 0 && cases >= maxcase)) break;

            for (i = 0; i < `RECV+1; i = i + 1) begin
                @(negedge clk);
                X = c[2*i];
                Y = c[2*i+1];
            end
            // inputs are only guaranteed during the load cycles
            @(negedge clk);
            X = $random;
            Y = $random;
            expect_valid = 1;
            wait_cycles = `RECV+2;
            while (valid !== 1'b1) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100000) begin
                    fail("valid never rose");
                    $finish;
                end
            end
            if (is_inside !== expected[0]) fail($sformatf("is_inside=%b expected=%0d", is_inside, expected));
            expect_valid = 0;
            cases = cases + 1;
            inside_cases = inside_cases + expected;
            cycles_sum = cycles_sum + wait_cycles;
            if (wait_cycles > cycles_max) cycles_max = wait_cycles;
            // the sample above is one half cycle into the valid pulse; the first load
            // cycle of the next case starts right after the pulse ends
            @(posedge clk);
            #1;
        end

        @(negedge clk);
        @(negedge clk);
        $display("cases %0d inside %0d cycles avg %.1f max %0d errors %0d",
                 cases, inside_cases, 1.0*cycles_sum/cases, cycles_max, errors);
        if (errors == 0 && cases > 0) $display("ALL PASS");
        else $display("FAILED");
        $finish;
    end
endmodule
