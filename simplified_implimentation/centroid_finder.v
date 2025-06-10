`timescale 1ns / 1ps

// ============================================================================
// CENTROID FINDER MODULE (for Real-Time Object Tracking)
// - Receives object_pixel stream and coordinates from object_extract
// - Accumulates (x, y) positions of all object pixels in a frame
// - At end of frame, outputs centroid (average x, y) and a valid pulse
// ============================================================================

module centroid_finder #(
    parameter X_WIDTH = 10, // e.g., 640 pixels max
    parameter Y_WIDTH = 10  // e.g., 480 pixels max
)(
    input  wire              clk,           // System clock
    input  wire              rst_n,         // Active-low reset
    input  wire              frame_valid,   // High during active frame
    input  wire              pixel_valid,   // High when pixel is valid
    input  wire [X_WIDTH-1:0] x,            // Current pixel x coordinate
    input  wire [Y_WIDTH-1:0] y,            // Current pixel y coordinate
    input  wire              object_pixel,  // 1 if pixel is part of object

    output reg  [X_WIDTH-1:0] centroid_x,   // Output centroid x coordinate
    output reg  [Y_WIDTH-1:0] centroid_y,   // Output centroid y coordinate
    output reg               centroid_valid // High for 1 clk when centroid is updated
);

    // =========================================================================
    // Internal Accumulators
    // =========================================================================
    reg [31:0] sum_x, sum_y, count;
    reg        frame_valid_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_x          <= 0;
            sum_y          <= 0;
            count          <= 0;
            centroid_x     <= 0;
            centroid_y     <= 0;
            centroid_valid <= 0;
            frame_valid_d  <= 0;
        end else begin
            frame_valid_d <= frame_valid;

            // Reset accumulators at start of frame
            if (!frame_valid) begin
                sum_x          <= 0;
                sum_y          <= 0;
                count          <= 0;
                centroid_valid <= 0;
            end else if (pixel_valid && object_pixel) begin
                // Accumulate object pixel positions
                sum_x <= sum_x + x;
                sum_y <= sum_y + y;
                count <= count + 1;
            end

            // On falling edge of frame_valid, output centroid
            if (frame_valid_d && !frame_valid) begin
                if (count != 0) begin
                    centroid_x     <= sum_x / count;
                    centroid_y     <= sum_y / count;
                    centroid_valid <= 1;
                end else begin
                    centroid_x     <= 0;
                    centroid_y     <= 0;
                    centroid_valid <= 1;
                end
            end else begin
                centroid_valid <= 0;
            end
        end
    end

endmodule