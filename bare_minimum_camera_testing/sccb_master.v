`timescale 1ns / 1ps

module sccb_master
    #(parameter CLK_FREQ = 50_000_000,  // 50 MHz default clock
      parameter SCCB_FREQ = 100_000)    // 100 kHz SCCB frequency (OV7670 can handle up to 400kHz)
    (
    // System signals
    input wire clk,                     // System clock
    input wire rst_n,                   // Active low reset
    
    // Control interface
    input wire start_transaction,       // Pulse to start an SCCB transaction
    input wire [7:0] device_addr,       // Device/slave address (typically 0x42 for OV7670 write)
    input wire [7:0] register_addr,     // Register address to write
    input wire [7:0] register_data,     // Data to write to register
    output reg ready,                   // High when module is ready for new transaction
    output reg done_tick,               // Pulses high when transaction completes
    
    // SCCB interface
    output wire scl,                    // Serial clock line
    inout wire sda                      // Serial data line
    );
    
    // Calculate timing constants
    localparam integer DIVIDER = (CLK_FREQ)/(2*SCCB_FREQ);
    localparam integer HALF_DIVIDER = DIVIDER/2;
    localparam integer COUNTER_WIDTH = $clog2(DIVIDER);
    
    // SCCB state machine states
    localparam [3:0] 
        IDLE = 0,
        START = 1,
        TX_BYTE = 2,
        ACK = 3,
        STOP_1 = 4,
        STOP_2 = 5,
        DELAY = 6;
        
    // Phase states for 3-phase write
    localparam [1:0]
        PHASE_DEVICE = 0,    // Device address phase
        PHASE_REGISTER = 1,  // Register address phase
        PHASE_DATA = 2;      // Data phase
        
    // Internal registers
    reg [3:0] state_q = IDLE, state_d;
    reg [1:0] phase_q = PHASE_DEVICE, phase_d;
    reg [7:0] tx_data_q = 0, tx_data_d;
    reg [2:0] bit_cnt_q = 0, bit_cnt_d;
    reg [COUNTER_WIDTH-1:0] counter_q = 0, counter_d;
    reg scl_q = 1, scl_d;
    reg sda_q = 1, sda_d;
    reg [7:0] delay_q = 0, delay_d; // For delays between transactions
    
    // Register logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= IDLE;
            phase_q <= PHASE_DEVICE;
            tx_data_q <= 0;
            bit_cnt_q <= 0;
            counter_q <= 0;
            scl_q <= 1;
            sda_q <= 1;
            delay_q <= 0;
        end
        else begin
            state_q <= state_d;
            phase_q <= phase_d;
            tx_data_q <= tx_data_d;
            bit_cnt_q <= bit_cnt_d;
            counter_q <= counter_d;
            scl_q <= scl_d;
            sda_q <= sda_d;
            delay_q <= delay_d;
        end
    end
    
    // Clock generation logic
    always @* begin
        counter_d = counter_q + 1;
        scl_d = scl_q;
        
        if (state_q == IDLE || state_q == START) begin
            scl_d = 1'b1;
            counter_d = 0;
        end
        else if (counter_q == DIVIDER-1) begin
            counter_d = 0;
            scl_d = (scl_q == 0) ? 1'b1 : 1'b0;
        end
    end
    
    // Detect SCL edges for state transitions
    wire scl_high = (scl_q == 1'b1) && (counter_q == HALF_DIVIDER);
    wire scl_low = (scl_q == 1'b0) && (counter_q == HALF_DIVIDER);
    
    // Main state machine
    always @* begin
        // Default values
        state_d = state_q;
        phase_d = phase_q;
        tx_data_d = tx_data_q;
        bit_cnt_d = bit_cnt_q;
        sda_d = sda_q;
        ready = (state_q == IDLE);
        done_tick = 1'b0;
        delay_d = delay_q;
        
        case (state_q)
            IDLE: begin
                sda_d = 1'b1;  // SDA high when idle
                phase_d = PHASE_DEVICE;
                
                if (start_transaction) begin
                    state_d = START;
                    tx_data_d = {device_addr[7:1], 1'b0}; // Address with write bit (0)
                end
            end
            
            START: begin
                if (scl_high) begin
                    sda_d = 1'b0;  // Start condition: SDA goes low while SCL is high
                    bit_cnt_d = 3'd7;  // Start with MSB
                    state_d = TX_BYTE;
                end
            end
            
            TX_BYTE: begin
                if (scl_low) begin
                    // Set SDA for next bit
                    sda_d = tx_data_q[bit_cnt_q] ? 1'b1 : 1'b0;
                    
                    if (bit_cnt_q == 0) begin
                        state_d = ACK;
                    end else begin
                        bit_cnt_d = bit_cnt_q - 1;
                    end
                end
            end
            
            ACK: begin
                if (scl_high) begin
                    // For SCCB, we don't read the ACK bit, just proceed
                    // Prepare next phase
                    case (phase_q)
                        PHASE_DEVICE: begin
                            phase_d = PHASE_REGISTER;
                            tx_data_d = register_addr;
                            state_d = TX_BYTE;
                            bit_cnt_d = 3'd7;
                        end
                        
                        PHASE_REGISTER: begin
                            phase_d = PHASE_DATA;
                            tx_data_d = register_data;
                            state_d = TX_BYTE;
                            bit_cnt_d = 3'd7;
                        end
                        
                        PHASE_DATA: begin
                            state_d = STOP_1;
                        end
                    endcase
                end
            end
            
            STOP_1: begin
                if (scl_low) begin
                    sda_d