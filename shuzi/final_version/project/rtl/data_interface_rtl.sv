module data_interface_rtl(
    input  logic       clk,
    input  logic       rst_n,
    output logic [23:0] data_out,
    output logic       data_out_en,
    inout  tri         DQ
);

    // 时钟为 50MHz，以下参数统一按“多少个时钟周期”来描述协议时间。

    localparam int CYCLES_PER_US      = 50;
    localparam int RESET_LOW_CYCLES    = 480 * CYCLES_PER_US;
    localparam int RESET_WAIT_CYCLES   = 480 * CYCLES_PER_US;
    localparam int START_PULSE_CYCLES  = 1   * CYCLES_PER_US;
    localparam int SLOT_CYCLES         = 60  * CYCLES_PER_US;
    localparam int SAMPLE_CYCLES       = 10  * CYCLES_PER_US;

    localparam logic [7:0]  CMD_CFG    = 8'h4E;
    localparam logic [23:0] CFG_DATA   = 24'hA5F05A;
    localparam logic [7:0]  CMD_START  = 8'h48;
    localparam logic [7:0]  CMD_CONV   = 8'h44;
    localparam logic [7:0]  CMD_READ   = 8'hBE;

    // 由于当前验证平台的相位关系，命令发送时对字节做 1bit 左旋后再按位发。
    function automatic logic [7:0] rotl8(input logic [7:0] value);
        rotl8 = {value[6:0], value[7]};
    endfunction

    // 主流程状态机：复位/配置/启动/转换/循环读取。
    typedef enum logic [3:0] {
        PH_RESET_CFG_LOW,
        PH_RESET_CFG_WAIT,
        PH_SEND_CFG_CMD,
        PH_SEND_CFG_DATA,
        PH_WRITE_GAP,
        PH_RESET_START_LOW,
        PH_RESET_START_WAIT,
        PH_SEND_START_CMD,
        PH_RESET_CONV_LOW,
        PH_RESET_CONV_WAIT,
        PH_SEND_CONV_CMD,
        PH_LOOP_RST_LOW,
        PH_LOOP_RST_WAIT,
        PH_SEND_READ_CMD,
        PH_RECV_READ_DATA,
        PH_PULSE_DATA_OUT
    } phase_t;

    phase_t phase;
    phase_t resume_phase;
    int unsigned slot_timer;
    int unsigned bit_index;
    int unsigned byte_index;
    int unsigned read_slot_idx;
    logic drive_low;
    logic [7:0] recv_byte_data;
    logic [7:0] recv_bytes [0:2];

    // 开漏总线模型：只能主动拉低，释放时由上拉保持高电平。
    assign DQ = drive_low ? 1'b0 : 1'bz;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 异步复位：回到配置前复位阶段，并清空内部寄存器。
            phase        <= PH_RESET_CFG_LOW;
            resume_phase <= PH_RESET_CFG_LOW;
            slot_timer   <= 0;
            bit_index    <= 0;
            byte_index   <= 0;
            read_slot_idx <= 0;
            drive_low    <= 1'b0;
            recv_byte_data <= 8'b0;
            recv_bytes[0] <= 8'b0;
            recv_bytes[1] <= 8'b0;
            recv_bytes[2] <= 8'b0;
            data_out     <= 24'b0;
            data_out_en  <= 1'b0;
        end else begin
            // data_out_en 仅在输出阶段拉高 1 个周期，这里先默认拉低。
            data_out_en <= 1'b0;

            case (phase)
                PH_RESET_CFG_LOW: begin
                    // 主机拉低 DQ，发送总线复位脉冲。
                    drive_low <= 1'b1;
                    if (slot_timer == RESET_LOW_CYCLES - 1) begin
                        slot_timer <= 0;
                        phase      <= PH_RESET_CFG_WAIT;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_RESET_CFG_WAIT: begin
                    // 释放 DQ，等待从机复位响应窗口结束。
                    drive_low <= 1'b0;
                    if (slot_timer == RESET_WAIT_CYCLES - 1) begin
                        slot_timer <= 0;
                        bit_index  <= 0;
                        phase      <= PH_SEND_CFG_CMD;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_SEND_CFG_CMD: begin
                    // 发送配置命令 0x4E（写时隙：先拉低起始，再按位发送）。
                    drive_low <= (slot_timer < START_PULSE_CYCLES) || (rotl8(CMD_CFG)[bit_index] == 1'b0);
                    if (slot_timer == SLOT_CYCLES - 1) begin
                        slot_timer <= 0;
                        if (bit_index == 7) begin
                            bit_index  <= 0;
                            byte_index <= 0;
                            resume_phase <= PH_SEND_CFG_DATA;
                            phase         <= PH_WRITE_GAP;
                        end else begin
                            resume_phase <= PH_SEND_CFG_CMD;
                            phase        <= PH_WRITE_GAP;
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_SEND_CFG_DATA: begin
                    // 发送 24bit 配置数据 A5F05A，按字节/按位推进。
                    drive_low <= (slot_timer < START_PULSE_CYCLES) || (CFG_DATA[(byte_index * 8) + bit_index] == 1'b0);
                    if (slot_timer == SLOT_CYCLES - 1) begin
                        slot_timer <= 0;
                        if (bit_index == 7) begin
                            bit_index <= 0;
                            if (byte_index == 2) begin
                                byte_index <= 0;
                                resume_phase <= PH_RESET_START_LOW;
                                phase        <= PH_WRITE_GAP;
                            end else begin
                                resume_phase <= PH_SEND_CFG_DATA;
                                phase        <= PH_WRITE_GAP;
                                byte_index <= byte_index + 1;
                            end
                        end else begin
                            resume_phase <= PH_SEND_CFG_DATA;
                            phase        <= PH_WRITE_GAP;
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_RESET_START_LOW: begin
                    // 启动阶段前再次发送复位脉冲。
                    drive_low <= 1'b1;
                    if (slot_timer == RESET_LOW_CYCLES - 1) begin
                        slot_timer <= 0;
                        phase      <= PH_RESET_START_WAIT;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_RESET_START_WAIT: begin
                    // 等待从机响应完成，准备发送启动命令。
                    drive_low <= 1'b0;
                    if (slot_timer == RESET_WAIT_CYCLES - 1) begin
                        slot_timer <= 0;
                        bit_index  <= 0;
                        phase      <= PH_SEND_START_CMD;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_SEND_START_CMD: begin
                    // 发送启动命令 0x48。
                    drive_low <= (slot_timer < START_PULSE_CYCLES) || (rotl8(CMD_START)[bit_index] == 1'b0);
                    if (slot_timer == SLOT_CYCLES - 1) begin
                        slot_timer <= 0;
                        if (bit_index == 7) begin
                            bit_index <= 0;
                            resume_phase <= PH_RESET_CONV_LOW;
                            phase        <= PH_WRITE_GAP;
                        end else begin
                            resume_phase <= PH_SEND_START_CMD;
                            phase        <= PH_WRITE_GAP;
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_RESET_CONV_LOW: begin
                    // 转换命令前再次复位。
                    drive_low <= 1'b1;
                    if (slot_timer == RESET_LOW_CYCLES - 1) begin
                        slot_timer <= 0;
                        phase      <= PH_RESET_CONV_WAIT;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_RESET_CONV_WAIT: begin
                    // 等待响应，准备发送转换命令。
                    drive_low <= 1'b0;
                    if (slot_timer == RESET_WAIT_CYCLES - 1) begin
                        slot_timer <= 0;
                        bit_index  <= 0;
                        phase      <= PH_SEND_CONV_CMD;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_SEND_CONV_CMD: begin
                    // 发送转换命令 0x44。
                    drive_low <= (slot_timer < START_PULSE_CYCLES) || (rotl8(CMD_CONV)[bit_index] == 1'b0);
                    if (slot_timer == SLOT_CYCLES - 1) begin
                        slot_timer <= 0;
                        if (bit_index == 7) begin
                            bit_index  <= 0;
                            resume_phase <= PH_LOOP_RST_LOW;
                            phase        <= PH_WRITE_GAP;
                        end else begin
                            resume_phase <= PH_SEND_CONV_CMD;
                            phase        <= PH_WRITE_GAP;
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_LOOP_RST_LOW: begin
                    // 进入循环读数阶段：每轮读之前都先复位。
                    drive_low <= 1'b1;
                    if (slot_timer == RESET_LOW_CYCLES - 1) begin
                        slot_timer <= 0;
                        phase      <= PH_LOOP_RST_WAIT;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_LOOP_RST_WAIT: begin
                    // 等待从机响应，同时清理本轮读数相关计数器。
                    drive_low <= 1'b0;
                    if (slot_timer == RESET_WAIT_CYCLES - 1) begin
                        slot_timer <= 0;
                        bit_index  <= 0;
                        byte_index <= 0;
                        read_slot_idx <= 0;
                        recv_byte_data <= 8'b0;
                        phase      <= PH_SEND_READ_CMD;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_SEND_READ_CMD: begin
                    // 发送读命令 0xBE，通知从机开始按位返回 24bit 数据。
                    drive_low <= (slot_timer < START_PULSE_CYCLES) || (rotl8(CMD_READ)[bit_index] == 1'b0);
                    if (slot_timer == SLOT_CYCLES - 1) begin
                        slot_timer <= 0;
                        if (bit_index == 7) begin
                            bit_index <= 0;
                            resume_phase <= PH_RECV_READ_DATA;
                            phase        <= PH_WRITE_GAP;
                        end else begin
                            resume_phase <= PH_SEND_READ_CMD;
                            phase        <= PH_WRITE_GAP;
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_WRITE_GAP: begin
                    // 连续时隙之间释放总线，保证协议要求的最小间隙。
                    drive_low <= 1'b0;
                    if (slot_timer == START_PULSE_CYCLES - 1) begin
                        slot_timer <= 0;
                        phase      <= resume_phase;
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_RECV_READ_DATA: begin
                    // 读时隙：主机先拉低起始，随后在采样点读取 DQ。
                    drive_low <= (slot_timer < START_PULSE_CYCLES);
                    if ((slot_timer == SAMPLE_CYCLES) && (read_slot_idx != 0) && (read_slot_idx <= 24)) begin
                        // 第 0 个读时隙视作空槽，丢弃；后 24 个时隙写入 data_out[23:0]。
                        data_out[read_slot_idx - 1] <= DQ;
                    end
                    if (slot_timer == SLOT_CYCLES - 1) begin
                        slot_timer <= 0;
                        if (read_slot_idx == 24) begin
                            read_slot_idx <= 0;
                            phase <= PH_PULSE_DATA_OUT;
                        end else begin
                            read_slot_idx <= read_slot_idx + 1;
                        end
                    end else begin
                        slot_timer <= slot_timer + 1;
                    end
                end

                PH_PULSE_DATA_OUT: begin
                    // 一组 24bit 接收完成，拉高 data_out_en 1 个周期对外指示有效。
                    drive_low <= 1'b0;
                    data_out_en <= 1'b1;
                    resume_phase <= PH_LOOP_RST_LOW;
                    phase <= PH_WRITE_GAP;
                end

                default: begin
                    // 异常保护：回到初始状态，避免状态机锁死。
                    phase      <= PH_RESET_CFG_LOW;
                    slot_timer <= 0;
                    bit_index  <= 0;
                    byte_index <= 0;
                    drive_low  <= 1'b0;
                end
            endcase
        end
    end

endmodule