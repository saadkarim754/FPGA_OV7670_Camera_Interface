`timescale 1ns / 1ps

module uart_downscaled_streamer (
    input  wire        clk,           // System clock
    input  wire        rst_n,         // Active-low reset
    input  wire        frame_valid,   // Frame is being captured
    input  wire        pixel_valid,   // New pixel available
    input  wire [9:0]  pixel_x,       // Pixel X coordinate
    input  wire [9:0]  pixel_y,       // Pixel Y coordinate
    input  wire [15:0] pixel_data,    // RGB565 pixel data
    output wire        tx,            // UART TX line
    output reg         led_activity   // Blinks when sending data
);
    // Parameters
    parameter CLK_FREQ = 50_000_000;  // 50 MHz
    parameter BAUD = 115200;          // UART baud rate
    
    // Downscaling parameters
    parameter H_SCALE = 8;            // Horizontal downscale factor (1 of every 8 pixels)
    parameter V_SCALE = 8;            // Vertical downscale factor (1 of every 8 lines)
    
    // Optional: Region of interest cropping
    parameter ROI_ENABLE = 1;         // Enable region of interest (center of image)
    parameter ROI_WIDTH = 80;         // ROI width
    parameter ROI_HEIGHT = 60;        // ROI height
    
    // Derived parameters
    localparam ROI_X_START = (640 - ROI_WIDTH)/2;
    localparam ROI_X_END = ROI_X_START + ROI_WIDTH;
    localparam ROI_Y_START = (480 - ROI_HEIGHT)/2;
    localparam ROI_Y_END = ROI_Y_START + ROI_HEIGHT;

    // Internal signals
    reg [15:0] data_latch;            // Latched pixel data
    reg [1:0] tx_state;               // TX state machine
    reg tx_start;                     // Start UART transmission
    reg [7:0] tx_data;                // Byte to transmit
    wire tx_busy;                     // UART busy signal
    
    // Frame header/trailer constants
    localparam FRAME_START_MARKER = 8'hA5;
    localparam FRAME_END_MARKER = 8'h5A;

    // Frame parameters to send at start of transmission
    reg [3:0] frame_param_idx;
    reg [7:0] frame_params [0:7];
    
    // TX state machine states
    localparam IDLE = 0;
    localparam SEND_PARAMS = 1;
    localparam SEND_HIGH_BYTE = 2;
    localparam SEND_LOW_BYTE = 3;
    
    // Frame state tracking
    reg prev_frame_valid;
    reg frame_started;
    reg [2:0] activity_counter;
    
    // Initialize frame parameters
    initial begin
        frame_params[0] = FRAME_START_MARKER;
        frame_params[1] = 8'h00;            // Reserved/version
        frame_params[2] = ROI_WIDTH[7:0];   // Width low byte
        frame_params[3] = ROI_WIDTH[15:8];  // Width high byte
        frame_params[4] = ROI_HEIGHT[7:0];  // Height low byte
        frame_params[5] = ROI_HEIGHT[15:8]; // Height high byte
        frame_params[6] = 8'd16;            // Bits per pixel
        frame_params[7] = FRAME_END_MARKER;
    end
    
    // UART transmitter instance
    uart_tx_byte #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD(BAUD)
    ) uart_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(tx_start),
        .data(tx_data),
        .tx(tx),
        .busy(tx_busy)
    );
    
    // Activity LED
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            activity_counter <= 0;
            led_activity <= 0;
        end else if (tx_start) begin
            activity_counter <= activity_counter + 1;
            led_activity <= activity_counter[2]; // Toggle every 8 transmissions
        end
    end
    
    // Frame detection and downscaling state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= IDLE;
            tx_start <= 0;
            data_latch <= 0;
            frame_started <= 0;
            prev_frame_valid <= 0;
            frame_param_idx <= 0;
        end else begin
            tx_start <= 0; // Default state
            prev_frame_valid <= frame_valid;
            
            // Detect frame start
            if (frame_valid && !prev_frame_valid) begin
                frame_started <= 1;
                tx_state <= SEND_PARAMS;
                frame_param_idx <= 0;
            end
            
            // Detect frame end
            if (!frame_valid && prev_frame_valid) begin
                frame_started <= 0;
                tx_state <= IDLE;
            end
            
            case (tx_state)
                IDLE: begin
                    // Wait for next frame or pixel
                end
                
                SEND_PARAMS: begin
                    if (!tx_busy && frame_param_idx < 8) begin
                        tx_data <= frame_params[frame_param_idx];
                        tx_start <= 1;
                        frame_param_idx <= frame_param_idx + 1;
                    end else if (frame_param_idx >= 8) begin
                        tx_state <= SEND_HIGH_BYTE;
                    end
                end
                
                SEND_HIGH_BYTE: begin
                    // Check if this pixel should be transmitted based on downscaling and ROI
                    if (pixel_valid && 
                        ((pixel_x % H_SCALE == 0) && (pixel_y % V_SCALE == 0)) &&
                        (!ROI_ENABLE || 
                         (pixel_x >= ROI_X_START && pixel_x < ROI_X_END && 
                          pixel_y >= ROI_Y_START && pixel_y < ROI_Y_END))) begin
                        
                        if (!tx_busy) begin
                            data_latch <= pixel_data;
                            tx_data <= pixel_data[15:8]; // High byte first
                            tx_start <= 1;
                            tx_state <= SEND_LOW_BYTE;
                        end
                    end
                end
                
                SEND_LOW_BYTE: begin
                    if (!tx_busy) begin
                        tx_data <= data_latch[7:0];
                        tx_start <= 1;
                        tx_state <= SEND_HIGH_BYTE;
                    end
                end
            endcase
            
            // If we lose frame_valid, go back to IDLE
            if (!frame_valid && tx_state != SEND_PARAMS) begin
                tx_state <= IDLE;
            end
        end
    end

endmodule

// Include the UART transmitter in the same file
module uart_tx_byte (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [7:0] data,
    output reg  tx,
    output reg  busy
);

    parameter CLK_FREQ = 50_000_000;    // 50 MHz
    parameter BAUD     = 115200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

    reg [3:0] bit_index;
    reg [13:0] clk_count;
    reg [9:0] tx_shift;  // Start + 8 data + Stop

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx        <= 1'b1;
            busy      <= 0;
            clk_count <= 0;
            bit_index <= 0;
            tx_shift  <= 10'b1111111111;
        end else begin
            if (start && !busy) begin
                // Format: start(0) + data[7:0] + stop(1)
                tx_shift  <= {1'b1, data, 1'b0};
                busy      <= 1;
                clk_count <= 0;
                bit_index <= 0;
            end else if (busy) begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    tx        <= tx_shift[bit_index];
                    bit_index <= bit_index + 1;

                    if (bit_index == 9) begin
                        busy <= 0;
                        tx   <= 1'b1; // idle
                    end
                end else begin
                    clk_count <= clk_count + 1;
                end
            end
        end
    end
endmodule