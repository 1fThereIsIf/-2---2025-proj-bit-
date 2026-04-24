module tb;

logic   clk  ;
logic   rst_n;
logic [23:0] rx_data;
logic        rx_data_en;
logic        data_check_done;

initial begin
    clk    = 0;
    rst_n  = 0;
    #30
    rst_n  = 1;
end

integer seed;
initial begin
    if($value$plusargs("seed=%d",seed))
        $display("random seed is %d",seed);
    $display("first random data is %d",$random(seed));
end

initial begin
    clk    = 0;
    #5;
    $display("clk delay time is %t",$time);
    forever #10 clk = ~clk;
end

tri           DQ;
data_interface_rtl data_interface_u0(
    .clk          (clk          ),
    .rst_n        (rst_n        ),
    .data_out     (rx_data      ),
    .data_out_en  (rx_data_en   ),
    .DQ           (DQ           ));

pullup PUP(DQ);

//always@(posedge clk)
//begin
//    if(rx_data_en)
//        $display("output data: %h @%t",rx_data,$time);
//end

adc_bfm #(.filename("../data/AD_trans_data.txt")) bfm_u0 (
    .clk          (clk          ),
    .rst_n        (rst_n        ),
    .DQ           (DQ           ));

CHECKER #(.filename("../data/bfm_received_data.txt"),
          .d_width (24 ))
u_checker0(
    .clk            (clk              )  ,
    .rst_n          (rst_n            )  ,
    .input_en       (rx_data_en       )  ,
    .data_i         (rx_data          )  ,
    .data_check_done(data_check_done  )
);


endmodule

