module adc_bfm(
    input  wire             clk          ,
    input  wire             rst_n        ,
    inout  wire             DQ           );


parameter string filename            = " ";
parameter CYC_NUM_1US                = 32'd50 ; //50MHz clk, 50 cycles is 1us

localparam RESET_TIME_SLOT                 = 32'd475 * CYC_NUM_1US;
localparam RESET_RSP_TIME_SLOT             = 32'd480 * CYC_NUM_1US;
localparam RESET_RSP_WAIT_TIME             = 32'd60  * CYC_NUM_1US;
localparam RESET_RSP_DRIVE_TIME            = 32'd240 * CYC_NUM_1US;
localparam RECV_BIT_MASTER_START_TIME      = 32'd1   * CYC_NUM_1US; 
localparam RECV_BIT_SLAVE_WAIT_TIME        = 32'd15  * CYC_NUM_1US; 
localparam RECV_BIT_SLAVE_SAMPLE_TIME      = 32'd58  * CYC_NUM_1US; 
localparam RECV_BIT_SLAVE_SAMPLE_TYP_TIME  = 32'd30  * CYC_NUM_1US; 
localparam TRAN_BIT_MASTER_START_TIME      = 32'd1   * CYC_NUM_1US;
localparam TRAN_BIT_SLAVE_DRIVE_TIME       = 32'd20  * CYC_NUM_1US;
localparam TRAN_BIT_SLAVE_WAIT_TIME        = 32'd58  * CYC_NUM_1US;

localparam CONFG_ADC_CMD                   = 8'h4E;  
localparam START_ADC_CMD                   = 8'h48;  
localparam ADC_CNVT_CMD                    = 8'h44;  
localparam ADC_TRAN_CMD                    = 8'hBE;  

wire            reset_rsp_done    ;
wire            one_byte_recv_done;
wire            recv_cfg_data_done;
wire            cvt_data_tran_done;
wire          recv_bit_sample_en;
reg    [7:0]  recv_byte_data;

//****************** read file begin *******************//
bit [8-1:0] data_bank[$];
bit [8-1:0] data_read;
int output_cnt;
int file_handle;
int fp;
int read_data_num;

function void init(input string fileaddr=" ");
    //init variable
    data_bank.delete();
    data_read        = 0   ;
    output_cnt       = 0   ;
    read_data_num    = 0   ;

    //read input testcase file
    file_handle = $fopen(fileaddr,"r");
    if(file_handle==0) begin
        $display("open file failed at testcase file %s",fileaddr);
        $finish;
    end
    while(!$feof(file_handle)) begin
        fp = $fscanf(file_handle,"%h",data_read);
        if(fp==1) begin
            data_bank.push_front(data_read);
            read_data_num++;
        end
    end
    $fclose(file_handle);
    $display("read file finished at testcase file %s",fileaddr);
endfunction

initial
begin
    forever @(posedge rst_n) init(filename);
end
//****************** read file end *******************//

//**************** dq_edge begin *******************//
wire       dq_in;
assign     dq_in= DQ;

reg        dq_in_pos_dly;      
reg        dq_in_neg_dly;      

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
    begin
        dq_in_pos_dly <= 1'b1;
        dq_in_neg_dly <= 1'b0;
    end
    else
    begin
        dq_in_pos_dly <= dq_in;
        dq_in_neg_dly <= dq_in;
    end
end

assign dq_posedge= dq_in && ~dq_in_pos_dly;
assign dq_negedge=~dq_in &&  dq_in_neg_dly;
//**************** dq_edge end *******************//

//**************** reset detection begin ************//
reg  [31:0]  reset_cnt;
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        reset_cnt <= 1'b0;
    else if(dq_in == 1'b0)
        reset_cnt <= reset_cnt + 32'd1;
    else if(dq_in)
        reset_cnt <= 1'b0;
end

assign reset_flag = (reset_cnt > RESET_TIME_SLOT) ? 1'b1 : 1'b0;
//**************** reset detection end ************//

//**************** main fsm begin ************//
reg    [3:0]    cur_main_state;
reg    [3:0]    nxt_main_state;
reg             all_data_trans_done;

localparam    IDLE                = 4'd0;
localparam    WAIT_RESET_RELEASE  = 4'd1;
localparam    RESET_RSP           = 4'd2;
localparam    RECV_CMD            = 4'd3;
localparam    RECV_CFG_DATA       = 4'd4;
localparam    TRANS_CVT_DATA      = 4'd5;

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        cur_main_state <= IDLE;
    else
        cur_main_state <= nxt_main_state;
end

always@(*)
begin
    if(all_data_trans_done)
        nxt_main_state = IDLE;
    else if(reset_flag)
        nxt_main_state = WAIT_RESET_RELEASE;
    else
        case(cur_main_state)
            IDLE              :  nxt_main_state = IDLE;
            WAIT_RESET_RELEASE:  nxt_main_state = reset_flag      ? WAIT_RESET_RELEASE : RESET_RSP;
            RESET_RSP         :  nxt_main_state = reset_rsp_done  ? RECV_CMD           : RESET_RSP;
            RECV_CMD          :  
            begin
                if(one_byte_recv_done && (recv_byte_data == CONFG_ADC_CMD))
                    nxt_main_state = RECV_CFG_DATA;
               else if(one_byte_recv_done && (recv_byte_data == START_ADC_CMD))
                    nxt_main_state = IDLE;
               else if(one_byte_recv_done && (recv_byte_data == ADC_CNVT_CMD))
                    nxt_main_state = IDLE;
               else if(one_byte_recv_done && (recv_byte_data == ADC_TRAN_CMD))
                    nxt_main_state = TRANS_CVT_DATA;
               else 
                    nxt_main_state = RECV_CMD;
            end
            RECV_CFG_DATA:   nxt_main_state = recv_cfg_data_done ? IDLE : RECV_CFG_DATA;
            TRANS_CVT_DATA:  nxt_main_state = cvt_data_tran_done ? IDLE : TRANS_CVT_DATA;
        default:    nxt_main_state = IDLE;
        endcase
end
//**************** main fsm end ************//

//**************** RESET RSP begin *****************//
reg    [31:0]    reset_rsp_cnt;

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        reset_rsp_cnt <= 32'b0;
    else if(cur_main_state == RESET_RSP)
        reset_rsp_cnt <= reset_rsp_cnt + 32'd1;
    else
        reset_rsp_cnt <= 32'b0;
end

assign reset_rsp_done   = (reset_rsp_cnt > RESET_RSP_TIME_SLOT) ? 1'b1 : 1'b0;
assign reset_rsp_wait   = (reset_rsp_cnt < RESET_RSP_WAIT_TIME) ? 1'b1 : 1'b0;
assign reset_rsp_drive  =((reset_rsp_cnt >=RESET_RSP_WAIT_TIME) && (reset_rsp_cnt < (RESET_RSP_WAIT_TIME + RESET_RSP_DRIVE_TIME))) ? 1'b1 : 1'b0;
assign reset_rsp_release= (reset_rsp_cnt >=(RESET_RSP_WAIT_TIME + RESET_RSP_DRIVE_TIME)) ? 1'b1 : 1'b0;
//**************** RESET RSP end *****************//

//**************** receive data begin *****************//
reg [31:0]  recv_timer;
reg [3:0]   cur_recv_bit_state;
reg [3:0]   nxt_recv_bit_state;

localparam  RECV_BIT_IDLE         = 4'd0;
localparam  RECV_BIT_MASTER_START = 4'd1;
localparam  RECV_BIT_SLAVE_WAIT   = 4'd2;
localparam  RECV_BIT_SLAVE_SAMPLE = 4'd3;

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        recv_timer <= 32'b0;
    else if(cur_recv_bit_state != RECV_BIT_IDLE)
        recv_timer <= recv_timer + 32'd1;
    else
        recv_timer <= 32'b0;
end

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        cur_recv_bit_state <= RECV_BIT_IDLE;
    else
        cur_recv_bit_state <= nxt_recv_bit_state;
end

always@(*)
begin
    case(cur_recv_bit_state)
        RECV_BIT_IDLE        : nxt_recv_bit_state = (((cur_main_state == RECV_CMD) || (cur_main_state == RECV_CFG_DATA)) && dq_negedge) ? RECV_BIT_MASTER_START : RECV_BIT_IDLE;
        RECV_BIT_MASTER_START: nxt_recv_bit_state = (recv_timer >= RECV_BIT_MASTER_START_TIME) ? RECV_BIT_SLAVE_WAIT   : RECV_BIT_MASTER_START;
        RECV_BIT_SLAVE_WAIT  : nxt_recv_bit_state = (recv_timer >= RECV_BIT_SLAVE_WAIT_TIME  ) ? RECV_BIT_SLAVE_SAMPLE : RECV_BIT_SLAVE_WAIT  ;
        RECV_BIT_SLAVE_SAMPLE: nxt_recv_bit_state = (recv_timer >= RECV_BIT_SLAVE_SAMPLE_TIME) ? RECV_BIT_IDLE         : RECV_BIT_SLAVE_SAMPLE;
        default:               nxt_recv_bit_state = RECV_BIT_IDLE;
    endcase
end

assign one_bit_recv_done = (cur_recv_bit_state == RECV_BIT_SLAVE_SAMPLE) && (nxt_recv_bit_state == RECV_BIT_IDLE);

assign        recv_bit_sample_en = (cur_recv_bit_state == RECV_BIT_SLAVE_SAMPLE) && (recv_timer == RECV_BIT_SLAVE_SAMPLE_TYP_TIME);

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        recv_byte_data <= 8'b0;
    else if(recv_bit_sample_en)
        recv_byte_data <= {dq_in,recv_byte_data[7:1]};
end

reg  [3:0]  recv_bit_idx;
reg  [3:0]  recv_byte_idx;
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        recv_bit_idx <= 4'd0;
    else if((cur_main_state != RECV_CMD) && (cur_main_state != RECV_CFG_DATA))
        recv_bit_idx <= 4'd0;
    else if(one_byte_recv_done)
        recv_bit_idx <= 4'd0;
    else if(one_bit_recv_done)
        recv_bit_idx <= recv_bit_idx + 4'd1;
end
        
assign one_byte_recv_done = (recv_bit_idx == 4'd7) && one_bit_recv_done;

always@(*)
begin
    if(one_byte_recv_done)
       $display("receive byte data %h @ %t !",recv_byte_data,$time);
end


always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        recv_byte_idx <= 4'd0;
    else if(cur_main_state != RECV_CFG_DATA)
        recv_byte_idx <= 4'd0;
    else if(one_byte_recv_done)
        recv_byte_idx <= recv_byte_idx + 4'd1;
end
        
assign recv_cfg_data_done = (recv_byte_idx == 4'd2) && (recv_bit_idx == 4'd7) && one_bit_recv_done;
//**************** receive data end *****************//

//**************** trans data begin *****************//
reg [31:0]  tran_timer;
reg [3:0]   cur_tran_bit_state;
reg [3:0]   nxt_tran_bit_state;
wire        one_byte_tran_done;

parameter  TRAN_BIT_IDLE         = 4'd0;
parameter  TRAN_BIT_MASTER_START = 4'd1;
parameter  TRAN_BIT_SLAVE_DRIVE  = 4'd2;
parameter  TRAN_BIT_SLAVE_WAIT   = 4'd3;

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        tran_timer <= 32'b0;
        else if(cur_tran_bit_state != TRAN_BIT_IDLE)
            tran_timer <= tran_timer + 32'd1;
        else
            tran_timer <= 32'b0;
end

always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        cur_tran_bit_state <= TRAN_BIT_IDLE;
    else
        cur_tran_bit_state <= nxt_tran_bit_state;
end

always@(*)
begin
    case(cur_tran_bit_state)
        TRAN_BIT_IDLE        : nxt_tran_bit_state = ((cur_main_state == TRANS_CVT_DATA) && dq_negedge) ? TRAN_BIT_MASTER_START: TRAN_BIT_IDLE;
        TRAN_BIT_MASTER_START: nxt_tran_bit_state = (tran_timer >= TRAN_BIT_MASTER_START_TIME) ? TRAN_BIT_SLAVE_DRIVE  : TRAN_BIT_MASTER_START;
        TRAN_BIT_SLAVE_DRIVE : nxt_tran_bit_state = (tran_timer >= TRAN_BIT_SLAVE_DRIVE_TIME ) ? TRAN_BIT_SLAVE_WAIT   : TRAN_BIT_SLAVE_DRIVE ;
        TRAN_BIT_SLAVE_WAIT  : nxt_tran_bit_state = (tran_timer >= TRAN_BIT_SLAVE_WAIT_TIME  ) ? TRAN_BIT_IDLE         : TRAN_BIT_SLAVE_WAIT  ;
        default:               nxt_tran_bit_state = TRAN_BIT_IDLE;
    endcase
end

assign one_bit_tran_done = (cur_tran_bit_state == TRAN_BIT_SLAVE_WAIT ) && (nxt_tran_bit_state == TRAN_BIT_IDLE);

reg  [3:0]  tran_bit_idx;
reg  [3:0]  tran_byte_idx;
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        tran_bit_idx <= 4'd0;
    else if(cur_main_state != TRANS_CVT_DATA)
        tran_bit_idx <= 4'd0;
    else if(one_byte_tran_done)
        tran_bit_idx <= 4'd0;
    else if(one_bit_tran_done)
        tran_bit_idx <= tran_bit_idx + 4'd1;
end
        
assign one_byte_tran_done = (tran_bit_idx == 4'd7) && one_bit_tran_done;
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        tran_byte_idx <= 4'd0;
    else if(cur_main_state != TRANS_CVT_DATA)
        tran_byte_idx <= 4'd0;
    else if(one_byte_tran_done)
        tran_byte_idx <= tran_byte_idx + 4'd1;
end
        
assign cvt_data_tran_done = (tran_byte_idx == 4'd2) && (tran_bit_idx == 4'd7) && one_bit_tran_done;

reg  [7:0]  trans_byte_data;
initial
begin
    all_data_trans_done <= 1'b0;
    @(posedge rst_n);
    #3;
    @(posedge clk  );
    trans_byte_data <= data_bank.pop_back;
    output_cnt += 1;
    forever begin
        @(posedge clk )
        if(one_byte_tran_done && (output_cnt < read_data_num))
        begin
            trans_byte_data <= data_bank.pop_back;
            output_cnt += 1;
        end
        else if(one_byte_tran_done && (output_cnt >= read_data_num))
        begin
            $display("All data trans done @%t !",$time);
            all_data_trans_done <= 1'b1;
        end
    end
end

reg  trans_bit_value;
always@(*)
begin
    case(tran_bit_idx)
    8'd0   : trans_bit_value = trans_byte_data[0];
    8'd1   : trans_bit_value = trans_byte_data[1];
    8'd2   : trans_bit_value = trans_byte_data[2];
    8'd3   : trans_bit_value = trans_byte_data[3];
    8'd4   : trans_bit_value = trans_byte_data[4];
    8'd5   : trans_bit_value = trans_byte_data[5];
    8'd6   : trans_bit_value = trans_byte_data[6];
    8'd7   : trans_bit_value = trans_byte_data[7];
    default: trans_bit_value = 1'b0;
    endcase
end
//**************** trans data end *****************//
wire dq_drive_en;
        
assign DQ = dq_drive_en ? 1'b0 : 1'bz;

assign dq_drive_en     = reset_rsp_drive || ((cur_tran_bit_state == TRAN_BIT_SLAVE_DRIVE)&& (trans_bit_value == 1'b0)) ;



endmodule                
