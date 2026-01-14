module smart_gate_controller (
    input clk_i,
    input reset_ni,
    input car_i,
    input pay_ok_i,
    input clear_i,
    input cnt_reset_i,
    output reg gate_open_o,
    output reg gate_close_o,
    output reg red_o,
    output reg yellow_o,
    output reg green_o,
    output reg [7:0] car_count_o
);

    localparam S0   = 3'd0;
    localparam S1   = 3'd1;
    localparam S2   = 3'd2;
    localparam S3   = 3'd3;
    localparam S4   = 3'd4;
    localparam S5   = 3'd5;
    localparam S6   = 3'd6;

    reg [2:0] state, next_state;
    reg [1:0] timer, next_timer;

    always @(posedge clk_i or negedge reset_ni) begin
        if (!reset_ni) begin
            state <= S0;
            timer <= 0;
            car_count_o <= 0;
        end else if (cnt_reset_i) begin
            car_count_o <= 0;
            state <= next_state;
            timer <= next_timer;
        end else begin
            state <= next_state;
            timer <= next_timer;
            if (state == S2 && car_count_o != 8'hFF) begin
                car_count_o <= car_count_o + 1;
            end
        end
    end

    always @(*) begin
        next_state = state;
        next_timer = 0;
        red_o = 0; yellow_o = 0; green_o = 0;
        gate_open_o = 0; gate_close_o = 0;

        case (state)
            S0: begin
                red_o = 1;
                if (car_i && pay_ok_i) next_state = S1;
            end

            S1: begin
                yellow_o = 1;
                if (timer < 1) begin
                    next_timer = timer + 1;
                    next_state = S1;
                end else begin
                    next_state = S2;
                end
            end

            S2: begin
                yellow_o = 1;
                if (clear_i) next_state = S3;
            end

            S3: begin
                green_o = 1;
                gate_open_o = 1;
                next_state = S4;
            end

            S4: begin
                green_o = 1;
                if (timer < 2) begin
                    next_timer = timer + 1;
                    next_state = S4;
                end else begin
                    next_state = S5;
                end
            end

            S5: begin
                yellow_o = 1;
                next_state = S6;
            end

            S6: begin
                red_o = 1;
                gate_close_o = 1;
                next_state = S0;
            end

            default: next_state = S0;
        endcase
    end
endmodule
