`timescale 1ns / 1ps

// ============================================================================
//  CAMERA INTERFACE (Simplified for Real-Time Object Tracking)
//  - Captures pixel data from OV7670 camera
//  - SCCB (I2C) configuration included
//  - Instantiates dcm_24MHz for camera XCLK
//  - Outputs pixel stream with coordinates and valid signals
// ============================================================================

module camera_interface(
    input  wire        clk,           // System clock (50MHz)
    input  wire        rst_n,         // Active-low reset
    input  wire [3:0]  key,           // For brightness/contrast control (optional)
    // Camera pinouts
    input  wire        cmos_pclk,     // Pixel clock from camera
    input  wire        cmos_href,     // Line valid
    input  wire        cmos_vsync,    // Frame valid
    input  wire [7:0]  cmos_db,       // 8-bit pixel data from camera
    inout  wire        cmos_sda,      // SCCB data
    inout  wire        cmos_scl,      // SCCB clock
    output wire        cmos_rst_n,    // Camera reset (active low)
    output wire        cmos_pwdn,     // Camera power down (active high)
    output wire        cmos_xclk,     // Camera external clock (24MHz)
    // Debugging
    output wire [3:0]  led,

    // --- Pixel stream outputs for object tracking ---
    output reg         pixel_valid,   // High for 1 clk when pixel_data is valid
    output reg         frame_valid,   // High during active frame
    output reg [9:0]   pixel_x,       // X coordinate of current pixel
    output reg [9:0]   pixel_y,       // Y coordinate of current pixel
    output reg [15:0]  pixel_data     // RGB565 pixel data
);

    // =========================================================================
    // Camera SCCB (I2C-like) Configuration
    // =========================================================================

    // Example: Minimal SCCB config for RGB565 output
    reg [15:0] message [0:7];
    initial begin
        message[0] = 16'h12_80; // Reset all registers
        message[1] = 16'h12_04; // COM7: Set RGB output
        message[2] = 16'h15_20; // PCLK does not toggle during HBLANK
        message[3] = 16'h40_d0; // COM15: RGB565, full range
        message[4] = 16'h3A_04; // TSLB: Set correct output data sequence
        message[5] = 16'h11_80; // CLKRC: Internal PLL matches input clock
        message[6] = 16'h0C_00; // COM3: Default
        message[7] = 16'h3E_00; // COM14: No scaling, normal pclk
    end

    // SCCB state machine signals
    reg [3:0]  sccb_state = 0;
    reg [2:0]  sccb_index = 0;
    reg        sccb_start = 0;
    reg        sccb_busy;
    reg        sccb_done;
    reg [7:0]  sccb_reg_addr;
    reg [7:0]  sccb_reg_data;

    // SCCB configuration state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sccb_state <= 0;
            sccb_index <= 0;
            sccb_start <= 0;
        end else begin
            case (sccb_state)
                0: begin // Idle, start config
                    sccb_index <= 0;
                    sccb_state <= 1;
                end
                1: begin // Start SCCB write
                    if (sccb_index < 8) begin
                        sccb_reg_addr <= message[sccb_index][15:8];
                        sccb_reg_data <= message[sccb_index][7:0];
                        sccb_start    <= 1;
                        sccb_state    <= 2;
                    end else begin
                        sccb_state <= 3; // Done
                    end
                end
                2: begin // Wait for SCCB write to finish
                    sccb_start <= 0;
                    if (sccb_done) begin
                        sccb_index <= sccb_index + 1;
                        sccb_state <= 1;
                    end
                end
                3: begin
                    // Configuration done, stay here
                    sccb_state <= 3;
                end
            endcase
        end
    end

    // SCCB (I2C) write module instantiation
    sccb_write sccb_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(sccb_start),
        .reg_addr(sccb_reg_addr),
        .reg_data(sccb_reg_data),
        .busy(sccb_busy),
        .done(sccb_done),
        .scl(cmos_scl),
        .sda(cmos_sda)
    );

    // =========================================================================
    // Camera Control Signals
    // =========================================================================
    assign cmos_pwdn  = 1'b0; // Always powered on
    assign cmos_rst_n = 1'b1; // Always out of reset

    // =========================================================================
    // Camera XCLK Generation (24MHz)
    // =========================================================================
    wire xclk_locked;
    dcm_24MHz dcm_xclk_inst (
        .clk(clk),           // 50MHz input
        .cmos_xclk(cmos_xclk), // 24MHz output
        .RESET(~rst_n),
        .LOCKED(xclk_locked)
    );

    // =========================================================================
    // Pixel Stream Capture Logic
    // =========================================================================

    reg [15:0] pixel_buf;    // Buffer for assembling 16-bit pixel
    reg        byte_toggle;  // Toggle between high and low byte
    reg [9:0]  x_cnt, y_cnt; // Pixel and line counters
    reg        href_d, vsync_d;

    // Frame valid logic (active when VSYNC is low)
    always @(posedge cmos_pclk or negedge rst_n) begin
        if (!rst_n) begin
            frame_valid <= 0;
            vsync_d     <= 0;
        end else begin
            vsync_d     <= cmos_vsync;
            frame_valid <= ~cmos_vsync;
        end
    end

    // Pixel and line counters, pixel assembly
    always @(posedge cmos_pclk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt       <= 0;
            y_cnt       <= 0;
            pixel_x     <= 0;
            pixel_y     <= 0;
            pixel_valid <= 0;
            pixel_data  <= 0;
            pixel_buf   <= 0;
            byte_toggle <= 0;
            href_d      <= 0;
        end else begin
            href_d <= cmos_href;

            // Reset counters at frame start
            if (!frame_valid) begin
                x_cnt <= 0;
                y_cnt <= 0;
            end else if (!cmos_href) begin
                x_cnt <= 0;
                if (href_d && !cmos_href) // falling edge of HREF
                    y_cnt <= y_cnt + 1;
            end else if (cmos_href) begin
                // Assemble RGB565 pixel: two bytes per pixel
                if (!byte_toggle) begin
                    pixel_buf[15:8] <= cmos_db;
                    byte_toggle     <= 1;
                    pixel_valid     <= 0;
                end else begin
                    pixel_buf[7:0]  <= cmos_db;
                    byte_toggle     <= 0;
                    pixel_valid     <= 1;
                    pixel_data      <= {pixel_buf[15:8], cmos_db};
                    pixel_x         <= x_cnt;
                    pixel_y         <= y_cnt;
                    x_cnt           <= x_cnt + 1;
                end
            end

            // If not assembling a pixel, pixel_valid is 0
            if (!cmos_href || !frame_valid)
                pixel_valid <= 0;
        end
    end

    // =========================================================================
    // Debug LEDs (optional: show frame/line activity)
    // =========================================================================
    assign led = {frame_valid, cmos_href, pixel_valid, byte_toggle};

endmodule

// ============================================================================
// SCCB (I2C) Write Module for Camera Register Configuration
// Simplified, blocking write for each register (not multi-master safe)
// ============================================================================
module sccb_write(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [7:0] reg_addr,
    input  wire [7:0] reg_data,
    output reg  busy,
    output reg  done,
    inout  wire scl,
    inout  wire sda
);
    // For brevity, this is a placeholder.
    // In your real project, use your existing SCCB/I2C master module here.
    // This module should:
    //  - On 'start', send a write transaction to the OV7670 at address 0x42
    //  - Write reg_addr and reg_data
    //  - Set 'done' high for one clk when finished
    //  - Set 'busy' high while in progress

    // For now, tie off signals to avoid synthesis errors.
    assign scl = 1'bz;
    assign sda = 1'bz;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            done <= 0;
        end else begin
            busy <= 0;
            done <= 1; // Pretend done immediately (replace with real logic)
        end
    end
endmodule