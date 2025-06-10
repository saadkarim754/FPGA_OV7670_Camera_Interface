module object_extract(
    input wire clk,
    input wire rst_n,
    input wire [15:0] pixel_data,
    input wire pixel_valid,
    input wire frame_valid,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    output reg object_pixel,
    output reg [9:0] x,
    output reg [9:0] y,
    output reg pixel_valid_out,
    output reg frame_valid_out
);

    // Simple threshold on red channel (bits 15:11)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            object_pixel <= 0;
            x <= 0;
            y <= 0;
            pixel_valid_out <= 0;
            frame_valid_out <= 0;
        end else begin
            pixel_valid_out <= pixel_valid;
            frame_valid_out <= frame_valid;
            x <= pixel_x;
            y <= pixel_y;
            // Example: object if red > threshold
            object_pixel <= (pixel_data[15:11] > 5'd16) ? 1'b1 : 1'b0;
        end
    end

endmodule