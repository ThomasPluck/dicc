
// Mismatches are measured at different points, and affect the
// propagation delay from that point.
//
// Intended to be instantiated in an NxN array.

`timescale 1ns/1ps

`include "defines.vh"

`ifdef SIM
    `include "buffer.v"
`endif

module coupled_counter #(parameter NUM_WEIGHTS = 15) (
		       // Oscillator RST
		       input  wire ising_rstn,

		       // Synchronous phase IO
	               input  wire sout, // previous coupled counter stage rotated
		       input  wire din , // previous coupled counter stage unrotated
		       output wire dout, // to next coupled counter stage

		       // Synchronous AXI write interface
		       input  wire        clk,
		       input  wire        axi_rstn,
                       input  wire        wready,
		       input  wire        wr_addr_match,
		       input  wire [31:0] wdata,
		       output wire [31:0] rdata
	               );
    genvar i;

    // Local registers for storing weights.
    reg  [$clog2(NUM_WEIGHTS)-1:0] weight;
    wire [$clog2(NUM_WEIGHTS)-1:0] weight_nxt;

    // Local registers for counter + controlling output        reg  [$clog2(NUM_WEIGHTS)-1:0] counter;
    reg [$clog2(NUM_WEIGHTS)-1:0] counter;
    reg output_enable;


    assign rdata = weight;

    assign weight_nxt = (wready & wr_addr_match) ? wdata[NUM_WEIGHTS-1:0] :
	                                           weight                 ;
    always @(posedge clk) begin
	if (!axi_rstn) begin
      	    weight <= (NUM_WEIGHTS/2); //NUM_WEIGHTS must be odd.
        end else begin
            weight <= weight_nxt;
        end
    end

    wire [NUM_WEIGHTS-1:0] weight_oh;
    generate for (i = 0; i < NUM_WEIGHTS; i = i + 1) begin
        assign weight_oh[i] = (weight == i);
    end endgenerate

    // If coupling is positive, we want to slow down the destination
    // oscillator when it doesn't match the source oscillator, and speed it up
    // otherwise.
    //
    // If coupling is negative, we want to slow down the destination
    // oscillator when it does match the source oscillator, and speed it up
    // otherwise.
   
    assign mismatch_d  = sout ^ din; // coupling mismatch
    assign mismatch_w  = din ^ dout; // wavefront mismatch

    wire should_countdown

    // Determine countdown condition based on weight polarity
    assign should_countdown = (weight[($clog2(NUM_WEIGHTS)-1)]) ?  // Check sign bit
                            (~mismatch_d & mismatch_w) :           // Negative weight case
                            (mismatch_d & mismatch_w);             // Positive weight case

    // Counter logic
    always @(posedge clk or negedge ising_rstn) begin
        if (!ising_rstn) begin
            counter <= '0;
            output_enable <= 1'b0;
        end else begin
            if (counter == '0) begin
                if ((weight[($clog2(NUM_WEIGHTS)-1)] && ~mismatch_d & mismatch_w) ||  // Negative weight, correct condition
                    (~weight[($clog2(NUM_WEIGHTS)-1)] && mismatch_d & mismatch_w)) begin  // Positive weight, correct condition
                    counter <= weight;
                end
            end else if (should_countdown) begin
                counter <= counter - 1'b1;
            end
        end
    end

    // Output enable logic
    always @(posedge clk or negedge ising_rstn) begin
        if (!ising_rstn) begin
            output_enable <= 1'b0;
        end else begin
            output_enable <= (counter == '0);
        end
    end
    // Allow spin programming
    assign dout = output_enable ? din : 1'bz;

endmodule
