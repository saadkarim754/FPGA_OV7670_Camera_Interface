`timescale 1ns / 1ps

module top_module(
    input  wire        clk,           // System clock (50MHz)
    input  wire        rst_n,         // Active-low reset
    input  wire [3:0]  key,           // For camera control (optional)
    // Camera pins
    input  wire        cmos_pclk,
    input  wire        cmos_href,
    input  wire        cmos_vsync,
    input  wire [7:0]  cmos_db,
    inout  wire        cmos_sda,
    inout  wire        cmos_scl,
    output wire        cmos_rst_n,
    output wire        cmos_pwdn,
    output wire        cmos_xclk,
    // UART output
    output wire        uart_tx,
    // Debug LEDs
    output wire [3:0]  led
);

    // --- Camera Interface ---
    wire        pixel_valid_cam, frame_valid_cam;
    wire [9:0]  pixel_x_cam, pixel_y_cam;
    wire [15:0] pixel_data_cam;

    camera_interface cam_inst (
        .clk(clk),
        .rst_n(rst_n),
        .key(key),
        .cmos_pclk(cmos_pclk),
        .cmos_href(cmos_href),
        .cmos_vsync(cmos_vsync),
        .cmos_db(cmos_db),
        .cmos_sda(cmos_sda),
        .cmos_scl(cmos_scl),
        .cmos_rst_n(cmos_rst_n),
        .cmos_pwdn(cmos_pwdn),
        .cmos_xclk(cmos_xclk),
        .led(led),
        .pixel_valid(pixel_valid_cam),
        .frame_valid(frame_valid_cam),
        .pixel_x(pixel_x_cam),
        .pixel_y(pixel_y_cam),
        .pixel_data(pixel_data_cam)
    );

    // --- Object Extraction ---
    wire object_pixel;
    wire [9:0] x, y;
    wire pixel_valid, frame_valid;

    object_extract obj_ext (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_data(pixel_data_cam),
        .pixel_valid(pixel_valid_cam),
        .frame_valid(frame_valid_cam),
        .pixel_x(pixel_x_cam),
        .pixel_y(pixel_y_cam),
        .object_pixel(object_pixel),
        .x(x),
        .y(y),
        .pixel_valid_out(pixel_valid),
        .frame_valid_out(frame_valid)
    );

    // --- Centroid Finder ---
    wire [9:0] centroid_x, centroid_y;
    wire centroid_valid;

    centroid_finder centroid_inst (
        .clk(clk),
        .rst_n(rst_n),
        .frame_valid(frame_valid),
        .pixel_valid(pixel_valid),
        .x(x),
        .y(y),
        .object_pixel(object_pixel),
        .centroid_x(centroid_x),
        .centroid_y(centroid_y),
        .centroid_valid(centroid_valid)
    );

    // --- UART TX ---
    reg [7:0] uart_data;
    reg uart_data_valid;
    wire uart_busy;

    uart_tx #(
        .CLK_FREQ(50000000), // Set to your system clock
        .BAUD_RATE(115200)
    ) uart_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(uart_data),
        .data_valid(uart_data_valid),
        .tx(uart_tx),
        .busy(uart_busy)
    );

    // --- UART Send State Machine ---
    reg [1:0] uart_state = 0;
    reg [9:0] centroid_x_reg, centroid_y_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_state      <= 0;
            uart_data       <= 0;
            uart_data_valid <= 0;
            centroid_x_reg  <= 0;
            centroid_y_reg  <= 0;
        end else begin
            uart_data_valid <= 0;
            case (uart_state)
                0: begin
                    if (centroid_valid && !uart_busy) begin
                        centroid_x_reg <= centroid_x;
                        centroid_y_reg <= centroid_y;
                        uart_data      <= centroid_x[7:0]; // X LSB
                        uart_data_valid<= 1;
                        uart_state     <= 1;
                    end
                end
                1: begin
                    if (!uart_busy) begin
                        uart_data      <= centroid_x[9:8]; // X MSB (only 2 bits)
                        uart_data_valid<= 1;
                        uart_state     <= 2;
                    end
                end
                 2: begin
                    if (!uart_busy) begin
                        uart_data      <= centroid_y[7:0]; // Y LSB
                        uart_data_valid<= 1;
                        uart_state     <= 3;
                    end
                end
                3: begin
                    if (!uart_busy) begin
                        uart_data      <= centroid_y[9:8]; // Y MSB (only 2 bits)
                        uart_data_valid<= 1;
                        uart_state     <= 0;
                    end
                end
            endcase
        end
    end

endmodule