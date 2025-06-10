`timescale 1ns / 1ps

// ============================================================================
// OBJECT EXTRACTION MODULE (for Real-Time Object Tracking)
// - Receives pixel stream from camera_interface
// - Applies thresholding to detect object pixels
// - Outputs object_pixel flag, coordinates, and valid signals
// ============================================================================

module object_extract(
    input  wire        clk,             // System clock (same as camera pipeline)
    input  wire        rst_n,           // Active-low reset
    input  wire [15:0] pixel_data,      // RGB565 pixel data from camera
    input  wire        pixel_valid,     // High when pixel_data is valid
    input  wire        frame_valid,     // High during active frame
    input  wire [9:0]  pixel_x,         // X coordinate from camera
    input  wire [9:0]  pixel_y,         // Y coordinate from camera

    output reg         object_pixel,    // 1 if pixel is part of object, else 0
    output reg [9:0]   x,               // X coordinate (passed through)
    output reg [9:0]   y,               // Y coordinate (passed through)
    output reg         pixel_valid_out, // Passed-through pixel_valid
    output reg         frame_valid_out  // Passed-through frame_valid
);

    // =========================================================================
    // Threshold Parameters (can be tuned for your object and lighting)
    // =========================================================================
    // Example: Detect "red" objects in RGB565
    parameter RED_THRESHOLD   = 5'd16; // 5 bits for red (bits 15:11)
    parameter GREEN_THRESHOLD = 6'd20; // 6 bits for green (bits 10:5)
    parameter BLUE_THRESHOLD  = 5'd10; // 5 bits for blue (bits 4:0)

    // =========================================================================
    // Object Detection Logic
    // =========================================================================
    // You can change this logic for grayscale, color, or more advanced detection

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            object_pixel    <= 0;
            x              <= 0;
            y              <= 0;
            pixel_valid_out <= 0;
            frame_valid_out <= 0;
        end else begin
            pixel_valid_out <= pixel_valid;
            frame_valid_out <= frame_valid;
            x              <= pixel_x;
            y              <= pixel_y;

            // --- RGB565 Extraction ---
            // Red   = pixel_data[15:11]
            // Green = pixel_data[10:5]
            // Blue  = pixel_data[4:0]

            // --- Example: Detect "red" object ---
            if (pixel_valid) begin
                if ((pixel_data[15:11] > RED_THRESHOLD) && 
                    (pixel_data[10:5]  < GREEN_THRESHOLD) && 
                    (pixel_data[4:0]   < BLUE_THRESHOLD)) begin
                    object_pixel <= 1'b1;
                end else begin
                    object_pixel <= 1'b0;
                end
            end else begin
                object_pixel <= 1'b0;
            end
        end
    end

    // =========================================================================
    // (Optional) For grayscale detection, use this logic instead:
    // parameter Y_THRESHOLD = 8'd100;
    // wire [7:0] gray = {pixel_data[15:13], pixel_data[10:8], pixel_data[4:3]};
    // if (gray > Y_THRESHOLD) object_pixel <= 1'b1; else object_pixel <= 1'b0;
    // =========================================================================

endmodule