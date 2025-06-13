`timescale 1ns / 1ps

module camera_interface (
    input  wire        clk,         // 50MHz
    input  wire        rst_n,       // Active-low reset
    input  wire [3:0]  key,         // Optional input
    input  wire        cmos_pclk,
    input  wire        cmos_href,
    input  wire        cmos_vsync,
    input  wire [7:0]  cmos_db,
    inout  wire        cmos_sda,
    inout  wire        cmos_scl,
    output wire        cmos_rst_n,
    output wire        cmos_pwdn,
    output wire        cmos_xclk,
    output wire [3:0]  led,
    output reg         pixel_valid,
    output reg         frame_valid,
    output reg [9:0]   pixel_x,
    output reg [9:0]   pixel_y,
    output reg [15:0]  pixel_data
);

    // =========================================================================
    // Camera Control
    // =========================================================================
    // Power down is active high, reset is active low
    assign cmos_pwdn  = 1'b0;  // Normal operation
    assign cmos_rst_n = 1'b1;  // Not in reset

    // =========================================================================
    // Clock Generator (24 MHz)
    // =========================================================================
    wire clk_24;
    wire clk_locked;

    clk_24mhz clk24_inst (
        .clk_in(clk),
        .rst(~rst_n),
        .clk_out(clk_24),
        .locked(clk_locked)
    );

    assign cmos_xclk = clk_24;  // Camera external clock

    // =========================================================================
    // SCCB Camera Configuration
    // =========================================================================
    // Register address and data pairs for OV7670 configuration
    // Each element is {register_address, register_value}
    // Comprehensive set of registers for better image quality
    reg [15:0] config_regs [0:29];
    initial begin
        // Core functionality
        config_regs[0]  = 16'h1280; // COM7: Reset all registers
        config_regs[1]  = 16'h1280; // COM7: Reset all registers (do twice to ensure reset)
        config_regs[2]  = 16'h1204; // COM7: Set RGB output format, enable color bar
        config_regs[3]  = 16'h1100; // CLKRC: Use external clock directly
        config_regs[4]  = 16'h0C00; // COM3: Enable DCW & scaling
        config_regs[5]  = 16'h3E00; // COM14: Normal PCLK
        
        // Format and resolution
        config_regs[6]  = 16'h8C00; // RGB444: Disable RGB444
        config_regs[7]  = 16'h0400; // COM1: Disable CCIR656
        config_regs[8]  = 16'h40D0; // COM15: RGB565 output
        
        // Image adjustments
        config_regs[9]  = 16'h3DC0; // COM13: Enable gamma and UV auto adjustment
        config_regs[10] = 16'h1418; // COM9: AGC, AWB and AEC enable with 4x gain
        config_regs[11] = 16'h4FB0; // MTX1: Matrix coefficient 1
        config_regs[12] = 16'h50B1; // MTX2: Matrix coefficient 2
        config_regs[13] = 16'h5100; // MTX3: Matrix coefficient 3
        config_regs[14] = 16'h523A; // MTX4: Matrix coefficient 4
        config_regs[15] = 16'h5340; // MTX5: Matrix coefficient 5
        config_regs[16] = 16'h5434; // MTX6: Matrix coefficient 6
        config_regs[17] = 16'h581E; // MTXS: Matrix sign and auto contrast
        
        // Additional settings
        config_regs[18] = 16'h3A04; // TSLB: Set correct output data sequence (magic)
        config_regs[19] = 16'h3D80; // COM13: Gamma enable, UV auto adjust
        config_regs[20] = 16'h1E31; // MVFP: Mirror/flip enable, black sun enable
        config_regs[21] = 16'h6B00; // DBLV: Bypass PLL
        config_regs[22] = 16'h7402; // REG74: Digital gain control
        config_regs[23] = 16'hB084; // RSVD: Magic value from OV
        config_regs[24] = 16'hB10C; // ABLC1: Enable ABLC function
        
        // Edge enhancement, denoise
        config_regs[25] = 16'h7A20; // SLOP: Gamma curve highest segment slope
        config_regs[26] = 16'h7B10; // GAM1: Gamma curve 1
        config_regs[27] = 16'h7C1E; // GAM2: Gamma curve 2
        config_regs[28] = 16'h7D35; // GAM3: Gamma curve 3
        config_regs[29] = 16'h6900; // GFIX: Fix gain control
    end

    // Number of registers to configure
    localparam CONFIG_SIZE = 30;

    // Configuration state machine
    reg [4:0] config_index = 0;
    reg [2:0] sccb_state = 0;
    reg       sccb_start_transaction = 0;
    wire      sccb_ready;
    wire      sccb_done_tick;
    reg [7:0] sccb_reg_addr;
    reg [7:0] sccb_reg_data;
    reg       config_done = 0;
    
    // State machine for camera configuration
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sccb_state <= 0;
            config_index <= 0;
            sccb_start_transaction <= 0;
            config_done <= 0;
        end else begin
            case (sccb_state)
                0: begin // Wait for clock to stabilize
                    if (clk_locked) begin
                        sccb_state <= 1;
                    end
                end
                
                1: begin // Prepare register values
                    if (config_index < CONFIG_SIZE) begin
                        sccb_reg_addr <= config_regs[config_index][15:8];
                        sccb_reg_data <= config_regs[config_index][7:0];
                        if (sccb_ready) begin
                            sccb_start_transaction <= 1;
                            sccb_state <= 2;
                        end
                    end else begin
                        sccb_state <= 4;
                        config_done <= 1;
                    end
                end
                
                2: begin // Wait for transaction start
                    sccb_start_transaction <= 0; // Clear start signal
                    sccb_state <= 3;
                end
                
                3: begin // Wait for transaction completion
                    if (sccb_done_tick) begin
                        config_index <= config_index + 1;
                        sccb_state <= 1;
                    end
                end
                
                4: begin // Configuration complete
                    // Stay in this state
                end
                
                default: sccb_state <= 0;
            endcase
        end
    end

    // Instantiate the SCCB master
    sccb_master #(
        .CLK_FREQ(50_000_000),  // 50 MHz system clock
        .SCCB_FREQ(100_000)     // 100 kHz SCCB frequency for reliability
    ) sccb_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_transaction(sccb_start_transaction),
        .device_addr(8'h42),    // OV7670 write address (0x42)
        .register_addr(sccb_reg_addr),
        .register_data(sccb_reg_data),
        .ready(sccb_ready),
        .done_tick(sccb_done_tick),
        .scl(cmos_scl),
        .sda(cmos_sda)
    );

    // =========================================================================
    // Pixel Stream Capture
    // =========================================================================
    reg [15:0] pixel_buf;
    reg        byte_toggle;
    reg [9:0]  x_cnt, y_cnt;
    reg        href_d, vsync_d;
    reg [2:0]  frame_count = 0;
    
    // Frame sync logic
    always @(posedge cmos_pclk or negedge rst_n) begin
        if (!rst_n) begin
            frame_valid <= 0;
            vsync_d     <= 0;
            frame_count <= 0;
        end else begin
            vsync_d <= cmos_vsync;
            
            // Detect falling edge of vsync to start frame capture
            if (vsync_d && !cmos_vsync) begin
                frame_count <= frame_count + 1;
                // Skip first 3 frames to allow camera to stabilize
                frame_valid <= (frame_count >= 3) ? 1'b1 : 1'b0;
            end
            // Detect rising edge of vsync to end frame capture
            else if (!vsync_d && cmos_vsync) begin
                frame_valid <= 1'b0;
            end
        end
    end

    // Pixel capture state machine
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
            
            // Reset coordinates at frame start
            if (!frame_valid) begin
                x_cnt <= 0;
                y_cnt <= 0;
                byte_toggle <= 0;
                pixel_valid <= 0;
            end 
            // Reset x position at start of new line
            else if (href_d && !cmos_href) begin
                x_cnt <= 0;
                byte_toggle <= 0;
                pixel_valid <= 0;
                y_cnt <= y_cnt + 1;
            end 
            // Process pixels during active line
            else if (cmos_href) begin
                if (!byte_toggle) begin
                    // First byte of pixel (R & G components in RGB565)
                    pixel_buf[15:8] <= cmos_db;
                    byte_toggle     <= 1;
                    pixel_valid     <= 0;
                end else begin
                    // Second byte of pixel (G & B components in RGB565)
                    pixel_buf[7:0]  <= cmos_db;
                    byte_toggle     <= 0;
                    pixel_valid     <= 1;
                    pixel_data      <= {pixel_buf[15:8], cmos_db};
                    pixel_x         <= x_cnt;
                    pixel_y         <= y_cnt;
                    x_cnt           <= x_cnt + 1;
                end
            end
            else begin
                pixel_valid <= 0;
            end
        end
    end

    // Debug LED indicators
    assign led = {config_done, frame_valid, cmos_href, pixel_valid};

endmodule