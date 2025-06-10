`timescale 1ns / 1ps

// ============================================================================
// UART TRANSMITTER MODULE
// - Sends 8-bit data serially at specified baud rate
// - Pulse data_valid high for one clk to send a byte
// - 'busy' is high while transmitting
// ============================================================================

module uart_tx #(
    parameter CLK_FREQ  = 50000000, // System clock frequency in Hz
    parameter BAUD_RATE = 115200    // UART baud rate
)(
    input  wire clk,                // System clock
    input  wire rst_n,              // Active-low reset
    input  wire [7:0] data_in,      // Byte to transmit
    input  wire data_valid,         // Pulse high to send data_in
    output reg  tx,                 // UART TX output
    output reg  busy                // High while transmitting
);

    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0]  state = IDLE;
    reg [15:0] baud_cnt = 0;
    reg [3:0]  bit_idx = 0;
    reg [7:0]  data_buf = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx       <= 1'b1;
            baud_cnt <= 0;
            bit_idx  <= 0;
            data_buf <= 0;
            busy     <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx   <= 1'b1;
                    busy <= 0;
                    if (data_valid) begin
                        data_buf <= data_in;
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        state    <= START;
                        busy     <= 1;
                    end
                end
                START: begin
                    tx <= 1'b0; // Start bit
                    if (baud_cnt == BAUD_DIV-1) begin
                        baud_cnt <= 0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                DATA: begin
                    tx <= data_buf[bit_idx];
                    if (baud_cnt == BAUD_DIV-1) begin
                        baud_cnt <= 0;
                        if (bit_idx == 7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                STOP: begin
                    tx <= 1'b1; // Stop bit
                    if (baud_cnt == BAUD_DIV-1) begin
                        baud_cnt <= 0;
                        state    <= IDLE;
                        busy     <= 0;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule