`timescale 1ns / 1ps

module top_module(
    input wire clk, rst_n,
    input wire[3:0] key,
    // camera pinouts
    input wire cmos_pclk, cmos_href, cmos_vsync,
    input wire[7:0] cmos_db,
    inout cmos_sda, cmos_scl,
    output wire cmos_rst_n, cmos_pwdn, cmos_xclk,
    // Debugging
    output[3:0] led,
    // controller to sdram
    output wire sdram_clk,
    output wire sdram_cke,
    output wire sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    output wire[12:0] sdram_addr,
    output wire[1:0] sdram_ba,
    output wire[1:0] sdram_dqm,
    inout[15:0] sdram_dq,
    // UART output
    output wire uart_tx,
    // VGA output (can be left unconnected or commented out if not used)
    output wire[4:0] vga_out_r,
    output wire[5:0] vga_out_g,
    output wire[4:0] vga_out_b,
    output wire vga_out_vs, vga_out_hs
);

    wire f2s_data_valid;
    wire[9:0] data_count_r;
    wire[15:0] dout, din;
    wire clk_sdram;
    wire empty_fifo;
    wire clk_vga;
    wire state;
    wire rd_en;

    // --- Camera Interface ---
    wire pixel_valid_cam, frame_valid_cam;
    wire [9:0] pixel_x_cam, pixel_y_cam;
    wire [15:0] pixel_data_cam;

    camera_interface m0 (
        .clk(clk),
        .clk_100(clk_sdram),
        .rst_n(rst_n),
        .key(key),
        .rd_en(f2s_data_valid),
        .data_count_r(data_count_r),
        .dout(dout),
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
        // Pixel stream outputs
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

    // --- UART TX Integration ---
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
            uart_state <= 0;
            uart_data <= 0;
            uart_data_valid <= 0;
            centroid_x_reg <= 0;
            centroid_y_reg <= 0;
        end else begin
            uart_data_valid <= 0;
            case (uart_state)
                0: begin
                    if (centroid_valid && !uart_busy) begin
                        centroid_x_reg <= centroid_x;
                        centroid_y_reg <= centroid_y;
                        uart_data <= centroid_x[7:0]; // Send X LSB
                        uart_data_valid <= 1;
                        uart_state <= 1;
                    end
                end
                1: begin
                    if (!uart_busy) begin
                        uart_data <= centroid_x[9:8]; // Send X MSB (only 2 bits)
                        uart_data_valid <= 1;
                        uart_state <= 2;
                    end
                end
                2: begin
                    if (!uart_busy) begin
                        uart_data <= centroid_y[7:0]; // Send Y LSB
                        uart_data_valid <= 1;
                        uart_state <= 3;
                    end
                end
                3: begin
                    if (!uart_busy) begin
                        uart_data <= centroid_y[9:8]; // Send Y MSB (only 2 bits)
                        uart_data_valid <= 1;
                        uart_state <= 0;
                    end
                end
            endcase
        end
    end

    // --- SDRAM Interface ---
    sdram_interface m1 (
        .clk(clk_sdram),
        .rst_n(rst_n),
        .clk_vga(clk_vga),
        .rd_en(rd_en),
        .data_count_r(data_count_r),
        .f2s_data(dout),
        .f2s_data_valid(f2s_data_valid),
        .empty_fifo(empty_fifo),
        .dout(din),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_addr(sdram_addr),
        .sdram_ba(sdram_ba),
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq),
        .sdram_clk(sdram_clk)
    );

    // --- VGA Interface (optional, can be commented out) ---
    vga_interface m2 (
        .clk(clk),
        .rst_n(rst_n),
        .empty_fifo(empty_fifo),
        .din(din),
        .clk_vga(clk_vga),
        .rd_en(rd_en),
        .vga_out_r(vga_out_r),
        .vga_out_g(vga_out_g),
        .vga_out_b(vga_out_b),
        .vga_out_vs(vga_out_vs),
        .vga_out_hs(vga_out_hs)
    );

    // --- SDRAM Clock Generation ---
    ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) oddr2_primitive (
        .D0(1'b0),
        .D1(1'b1),
        .C0(clk_sdram),
        .C1(~clk_sdram),
        .CE(1'b1),
        .R(1'b0),
        .S(1'b0),
        .Q(sdram_clk)
    );

    dcm_165MHz m3 (
        .clk(clk),
        .clk_sdram(clk_sdram),
        .RESET(~rst_n),
        .LOCKED()
    );

endmodule