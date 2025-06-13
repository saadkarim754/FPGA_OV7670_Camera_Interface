`timescale 1ns / 1ps

module top_camera_uart (
    input  wire clk_50mhz,       // 50MHz system clock
    input  wire rst_n,           // Active low reset
    
    // Camera interface pins
    input  wire cmos_pclk,       // Pixel clock from camera
    input  wire cmos_href,       // Horizontal sync
    input  wire cmos_vsync,      // Vertical sync
    input  wire [7:0] cmos_db,   // 8-bit pixel data
    inout  wire cmos_scl,        // SCCB clock
    inout  wire cmos_sda,        // SCCB data
    output wire cmos_rst_n,      // Camera reset
    output wire cmos_pwdn,       // Camera power down
    output wire cmos_xclk,       // Camera external clock
    
    // UART output
    output wire uart_tx,         // UART transmit line
    
    // Debug outputs
    output wire [3:0] led        // Status LEDs
);
    
    // === Camera interface connections ===
    wire pixel_valid;            // Indicates valid pixel data
    wire frame_valid;            // Indicates active frame
    wire [15:0] pixel_data;      // 16-bit RGB565 pixel data
    wire [9:0] pixel_x;          // Pixel X coordinate (0-639)
    wire [9:0] pixel_y;          // Pixel Y coordinate (0-479)
    
    // === UART activity indicator ===
    wire uart_activity;          // UART transmission activity indicator
    
    // === Camera Interface Module ===
    camera_interface cam_inst (
        .clk(clk_50mhz),         // System clock input
        .rst_n(rst_n),           // System reset (active low)
        .key(4'b0000),           // No buttons connected
        
        // Camera signals
        .cmos_pclk(cmos_pclk),
        .cmos_href(cmos_href),
        .cmos_vsync(cmos_vsync),
        .cmos_db(cmos_db),
        .cmos_sda(cmos_sda),
        .cmos_scl(cmos_scl),
        .cmos_rst_n(cmos_rst_n),
        .cmos_pwdn(cmos_pwdn),
        .cmos_xclk(cmos_xclk),
        
        // Output interface
        .led(led),               // Status LEDs
        .pixel_valid(pixel_valid),
        .frame_valid(frame_valid),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_data(pixel_data)
    );

    // === UART Downscaling Streamer ===
    // Downscale and send pixel data over UART
    uart_downscaled_streamer #(
        .CLK_FREQ(50_000_000),   // 50 MHz clock
        .BAUD(115200),           // 115200 baud UART
        .H_SCALE(8),             // Horizontal scaling factor
        .V_SCALE(8),             // Vertical scaling factor
        .ROI_ENABLE(1),          // Enable region of interest
        .ROI_WIDTH(80),          // ROI width
        .ROI_HEIGHT(60)          // ROI height
    ) uart_inst (
        .clk(clk_50mhz),
        .rst_n(rst_n),
        .frame_valid(frame_valid),
        .pixel_valid(pixel_valid),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_data(pixel_data),
        .tx(uart_tx),
        .led_activity(uart_activity)  // Can connect to additional LED if needed
    );
    
    // Additional debugging: Uncomment to add more LEDs if available
    // assign debug_leds = {frame_valid, pixel_valid, uart_activity, led[0]};

endmodule