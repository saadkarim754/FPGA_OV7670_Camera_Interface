`timescale 1ns / 1ps

module clk_24mhz (
    input  wire clk_in,       // 50 MHz system clock
    input  wire rst,          // Active-high reset
    output wire clk_out,      // 24 MHz output
    output wire locked        // DCM lock status
);

    wire clkfx;

    DCM_SP #(
        .CLKFX_MULTIPLY(24),
        .CLKFX_DIVIDE(50),
        .CLKIN_PERIOD(20.0), // 1 / 50MHz = 20ns
        .CLK_FEEDBACK("NONE")
    ) dcm_inst (
        .CLKIN(clk_in),
        .CLKFX(clkfx),
        .RST(rst),
        .CLKFB(1'b0),
        .CLK0(),
        .LOCKED(locked),
        .CLKDV(),
        .PSCLK(1'b0),
        .PSEN(1'b0),
        .PSINCDEC(1'b0),
        .PSDONE()
    );

    assign clk_out = clkfx;

endmodule
