`define right 1

module CHECKER#(
    parameter string filename = " ",
    parameter int d_width = 16
)
(
    input bit clk,
    input bit rst_n,
    input bit input_en,
    input [d_width-1:0] data_i,
    output bit data_check_done
);

bit [d_width-1:0] data_bank[$];
bit [d_width-1:0] data;
int file_handle;
int fp;
int read_data_num;
int check_data_idx;
int err_cnt;

function void init(input string fileaddr=" ");
    //init variable
    data_bank.delete();
    data = 0;
    err_cnt = 0;
    read_data_num = 0;
    check_data_idx = 0;
    //init output signal
    data_check_done = 1'b0;
    //read input verification data from file
    file_handle = $fopen(fileaddr,"r");
    if(file_handle==0) begin
        $display("open file failed at verification file: %s",fileaddr);
        $finish;
    end
    while(!$feof(file_handle)) begin
        fp = $fscanf(file_handle,"%h",data);
        if(fp==1) begin
            data_bank.push_front(data);
            read_data_num++;
        end
    end
    $fclose(file_handle);
    $display("read file finished at verification file: %s", fileaddr);
    if(read_data_num == 0)
    begin
        $display("read no data from %s, check done at time: %t", fileaddr,$time);
        data_check_done <= 1'b1;
    end
endfunction

always@ (posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        init(filename);
	data = data_bank.pop_back;
    end
    else begin
        if(input_en) begin
            if(data_i!==data) begin
                $display("verification error: current time:%t, verification file:%s, data idx:%0d, DUT data:%h, reference data: %h",$time,filename,check_data_idx,data_i,data);
                err_cnt = err_cnt + 1;
            end
            `ifdef right
                if(check_data_idx%4==0) begin
                    $display("verification current time:%t,verification file:%s,data idx:%0d, checked",$time,filename,check_data_idx);
                end
            `endif
            
            if(check_data_idx==(read_data_num-1)) begin
                data_check_done <= 1'b1;
                if(data_check_done==0) begin
                    $display("data from verification file: %s has all been checked at time: %t, total data num is %d",filename,$time,read_data_num);
                end
                #5000;
                $finish;
            end
            else if(check_data_idx >= read_data_num) begin
                $display("verification error: current time:%t, verification file:%s, data idx:%0d,DUT generate more data than expected!",$time,filename,check_data_idx,data_i);
                #100;
                $finish;
            end

	    data = data_bank.pop_back;
            check_data_idx++;
        end
    end
end

always@(*)
begin
    if(err_cnt > 10)
    begin
        $display("Too much error, finish the simulation @time:%t, verification file:%s, ",$time,filename);
        $finish;
    end
end

endmodule
