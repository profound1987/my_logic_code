/*
//1.启动AXI_DMA，置bit位为高
//2.查询DMASR寄存器的halted比特位DMASR.Halted，如果为0则说明AXI_DMA已启动
//3.当AXI_DMA启动后，使能中断，写入MM2S_DMACR.IOC_IrqEn和MM2S_DMACR.Err_IrqEn.
//4.写入有效地址到MM2S_SA寄存器中
//5.写入传输字节长度到MM2S_LENGTH寄存器中，该寄存器必须最后写入。
*/
`timescale 1 ns / 1 ps
`define SIMU_ON
//bit zone
`define Reg_Cr_EN                   0
`define Reg_Sr_Halted               0       
`define Reg_Cr_IOCIrqEn             12
`define Reg_Cr_ErrIrqEn             14

    module U_AxiDma_Ctrl_v1_0_M00_AXI #
    (
        // Users to add parameters here

        // User parameters ends
        // Do not modify the parameters beyond this line

        // The master will start generating data from the C_M_START_DATA_VALUE value
        parameter  C_M_START_DATA_VALUE = 32'hAA000000,
        // The master requires a target slave base address.
    // The master will initiate read and write transactions on the slave with base address specified here as a parameter.
        parameter  C_M_TARGET_SLAVE_BASE_ADDR   = 32'h40000000,
        // Width of M_AXI address bus. 
    // The master generates the read and write addresses of width specified as C_M_AXI_ADDR_WIDTH.
        parameter integer C_M_AXI_ADDR_WIDTH    = 32,
        // Width of M_AXI data bus. 
    // The master issues write data and accept read data where the width of the data bus is C_M_AXI_DATA_WIDTH
        parameter integer C_M_AXI_DATA_WIDTH    = 32,
        // Transaction number is the number of write 
    // and read transactions the master will perform as a part of this example memory test.
        //parameter integer C_M_TRANSACTIONS_NUM    = 4
    //
        parameter integer C_M_TRANSACTIONS_NUM  = 1024
    )
    (
        // Users to add ports here
        input     wire                AXIDMA_REQ_VALID,
        input     wire  [127:0]       AXIDMA_REQ_DATA,
        output    reg                 AXIDMA_REQ_READY,

        input     wire                AXI_DMA_MM2S_IRQ,
        input     wire                AXI_DMA_S2MM_IRQ,
        // User ports ends
        // Do not modify the ports beyond this line

        // Initiate AXI transactions
        input wire  INIT_AXI_TXN,
        // Asserts when ERROR is detected
        output reg  ERROR,
        // Asserts when AXI transactions is complete
        output wire  TXN_DONE,
        // AXI clock signal
        input wire  M_AXI_ACLK,
        // AXI active low reset signal
        input wire  M_AXI_ARESETN,
        // Master Interface Write Address Channel ports. Write address (issued by master)
        
        output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_AWADDR,
        // Write channel Protection type.
    // This signal indicates the privilege and security level of the transaction,
    // and whether the transaction is a data access or an instruction access.
        output wire [2 : 0] M_AXI_AWPROT,
        // Write address valid. 
    // This signal indicates that the master signaling valid write address and control information.
        
        output wire  M_AXI_AWVALID,
        // Write address ready. 
    // This signal indicates that the slave is ready to accept an address and associated control signals.
        (* mark_debug = "true" *)
        input wire  M_AXI_AWREADY,
        // Master Interface Write Data Channel ports. Write data (issued by master)
        (* mark_debug = "true" *)
        output wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_WDATA,
        // Write strobes. 
    // This signal indicates which byte lanes hold valid data.
    // There is one write strobe bit for each eight bits of the write data bus.
        output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
        // Write valid. This signal indicates that valid write data and strobes are available.
        
        output wire  M_AXI_WVALID,
        // Write ready. This signal indicates that the slave can accept the write data.
        (* mark_debug = "true" *)
        input wire  M_AXI_WREADY,
        // Master Interface Write Response Channel ports. 
    // This signal indicates the status of the write transaction.
        (* mark_debug = "true" *)
        input wire [1 : 0] M_AXI_BRESP,
        // Write response valid. 
    // This signal indicates that the channel is signaling a valid write response
        (* mark_debug = "true" *)
        input wire  M_AXI_BVALID,
        // Response ready. This signal indicates that the master can accept a write response.
        
        output wire  M_AXI_BREADY,
        // Master Interface Read Address Channel ports. Read address (issued by master)
        
        output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,
        // Protection type. 
    // This signal indicates the privilege and security level of the transaction, 
    // and whether the transaction is a data access or an instruction access.
        output wire [2 : 0] M_AXI_ARPROT,
        // Read address valid. 
    // This signal indicates that the channel is signaling valid read address and control information.
        output wire  M_AXI_ARVALID,
        // Read address ready. 
    // This signal indicates that the slave is ready to accept an address and associated control signals.
        input wire  M_AXI_ARREADY,
        // Master Interface Read Data Channel ports. Read data (issued by slave)
        input wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,
        // Read response. This signal indicates the status of the read transfer.
        input wire [1 : 0] M_AXI_RRESP,
        // Read valid. This signal indicates that the channel is signaling the required read data.
        input wire  M_AXI_RVALID,
        // Read ready. This signal indicates that the master can accept the read data and response information.
        output wire  M_AXI_RREADY
    );

    // function called clogb2 that returns an integer which has the
    // value of the ceiling of the log base 2

     function integer clogb2 (input integer bit_depth);
         begin
         for(clogb2=0; bit_depth>0; clogb2=clogb2+1)
             bit_depth = bit_depth >> 1;
         end
     endfunction

    // TRANS_NUM_BITS is the width of the index counter for 
    // number of write or read transaction.
     localparam integer TRANS_NUM_BITS = clogb2(C_M_TRANSACTIONS_NUM-1);

    // Example State machine to initialize counter, initialize write transactions, 
    // initialize read transactions and comparison of read data with the 
    // written data words.
    localparam [1:0] IDLE = 2'b00, // This state initiates AXI4Lite transaction 
            // after the state machine changes state to INIT_WRITE   
            // when there is 0 to 1 transition on INIT_AXI_TXN
        INIT_WRITE   = 2'b01, // This state initializes write transaction,
            // once writes are done, the state machine 
            // changes state to INIT_READ 
        INIT_READ = 2'b10, // This state initializes read transaction
            // once reads are done, the state machine 
            // changes state to INIT_COMPARE 
        INIT_COMPARE = 2'b11; // This state issues the status of comparison 
            // of the written data with the read data   
      //
      //
      //

  /***********************************************************
  * 地址的偏移依赖于C_BASEADDR 
  ***********************************************************/
  localparam  MM2S_DMACR_ADDR   =   8'h00,            //DMA控制寄存器
              MM2S_DMASR_ADDR   =   8'h04,            //DMA状态寄存器

              MM2S_SA           =   8'h18,            //MM2S源地址寄存器低32bit
              MM2S_SA_MSB       =   8'h1c,            //MM2S源地址寄存器高32bit

              MM2S_LENGTH       =   8'h28;            //传输长度
              
  localparam  S2MM_DMACR_ADDR   =   8'h30,            //DMA控制寄存器      
              S2MM_DMASR_ADDR   =   8'h34,            //DMA状态寄存器
              S2MM_DA           =   8'h48,            //DMA目的地址低32bit
              S2MM_DA_MSB       =   8'h4C,            //DMA目的地址高32bit
              S2MM_LENGTH       =   8'h58;            //S2MM缓冲长度       


/*   localparam  S_IDLE            =   8'd0,
              S_RST_AXIDMA      =   8'd1,
              S_WRITE_DMACR     =   8'd2,
              S_WRITE_SA        =   8'd3,
              S_WRITE_SA_MSB    =   8'd4,
              S_WRITE_LENGTH    =   8'd5,
              S_START_DMA       =   8'd6,
              S_WAIT_DONE       =   8'd7;
 */
  localparam  S_IDLE            =   8'd0,
              S_START_DMA       =   8'd1,
              S_WAIT_DMA_RUN    =   8'd2,
              S_EN_INTERRUPT    =   8'd3,
              S_WRITE_SA        =   8'd4,
              S_WRITE_SA_MSB    =   8'd5,
              S_WRITE_LENGTH    =   8'd6,              
              S_WAIT_DONE       =   8'd7;

  
    (* mark_debug = "true" *)
     reg [1:0] mst_exec_state;

    // AXI4LITE signals
    //write address valid
    (* mark_debug = "true" *)
    reg     axi_awvalid;
    //write data valid
    (* mark_debug = "true" *)
    reg     axi_wvalid;
    //read address valid
    (* mark_debug = "true" *)
    reg     axi_arvalid;
    //read data acceptance
    reg     axi_rready;
    //write response acceptance
    (* mark_debug = "true" *)
    reg     axi_bready;
    //write address
    (* mark_debug = "true" *)
    reg [C_M_AXI_ADDR_WIDTH-1 : 0]  axi_awaddr;
    //write data
    
    reg [C_M_AXI_DATA_WIDTH-1 : 0]  axi_wdata;
    //read addresss
    (* mark_debug = "true" *)
    reg [C_M_AXI_ADDR_WIDTH-1 : 0]  axi_araddr;
    //Asserts when there is a write response error
    wire    write_resp_error;
    //Asserts when there is a read response error
    wire    read_resp_error;
    //A pulse to initiate a write transaction
    (* mark_debug = "true" *)
    reg     start_single_write;
    //A pulse to initiate a read transaction
    (* mark_debug = "true" *)
    reg     start_single_read;
    //Asserts when a single beat write transaction is issued and remains asserted till the completion of write trasaction.
    (* mark_debug = "true" *)
    reg     write_issued;
    //Asserts when a single beat read transaction is issued and remains asserted till the completion of read trasaction.
    reg     read_issued;
    //flag that marks the completion of write trasactions. The number of write transaction is user selected by the parameter C_M_TRANSACTIONS_NUM.
    (* mark_debug = "true" *)
    reg     writes_done;
    //flag that marks the completion of read trasactions. The number of read transaction is user selected by the parameter C_M_TRANSACTIONS_NUM
    reg     reads_done;
    //The error register is asserted when any of the write response error, read response error or the data mismatch flags are asserted.
    reg     error_reg;
    //index counter to track the number of write transaction issued
    (* mark_debug = "true" *)
    reg [TRANS_NUM_BITS : 0]    write_index;
    //index counter to track the number of read transaction issued
    (* mark_debug = "true" *)
    reg [TRANS_NUM_BITS : 0]    read_index;
    //Expected read data used to compare with the read data.
    (* mark_debug = "true" *)
    reg [C_M_AXI_DATA_WIDTH-1 : 0]  expected_rdata;
    //Flag marks the completion of comparison of the read data with the expected read data
    reg     compare_done;
    //This flag is asserted when there is a mismatch of the read data with the expected read data.
    reg     read_mismatch;
    //Flag is asserted when the write index reaches the last write transction number
    (* mark_debug = "true" *)
    reg     last_write;
    //Flag is asserted when the read index reaches the last read transction number
    (* mark_debug = "true" *)
    reg     last_read;
    reg     init_txn_ff;
    reg     init_txn_ff2;
    reg     init_txn_edge;
    (* mark_debug = "true" *)
    wire    init_txn_pulse;


    // I/O Connections assignments

    //Adding the offset address to the base addr of the slave
    assign M_AXI_AWADDR = C_M_TARGET_SLAVE_BASE_ADDR + axi_awaddr;
    //AXI 4 write data
    assign M_AXI_WDATA  = axi_wdata;
    assign M_AXI_AWPROT = 3'b000;
    assign M_AXI_AWVALID    = axi_awvalid;
    //Write Data(W)
    assign M_AXI_WVALID = axi_wvalid;
    //Set all byte strobes in this example
    assign M_AXI_WSTRB  = 4'b1111;
    //Write Response (B)
    assign M_AXI_BREADY = axi_bready;
    //Read Address (AR)
    assign M_AXI_ARADDR = C_M_TARGET_SLAVE_BASE_ADDR + axi_araddr;
    assign M_AXI_ARVALID    = axi_arvalid;
    assign M_AXI_ARPROT = 3'b001;
    //Read and Read Response (R)
    assign M_AXI_RREADY = axi_rready;
    //Example design I/O
    assign TXN_DONE = compare_done;
    assign init_txn_pulse   = (!init_txn_ff2) && init_txn_ff;


    //Generate a pulse to initiate AXI transaction.
    always @(posedge M_AXI_ACLK)                                              
      begin                                                                        
        // Initiates AXI transaction delay    
        if (M_AXI_ARESETN == 0 )                                                   
          begin                                                                    
            init_txn_ff <= 1'b0;                                                   
            init_txn_ff2 <= 1'b0;                                                   
          end                                                                               
        else                                                                       
          begin  
            //init_txn_ff <= INIT_AXI_TXN;
            //当DiniDMA发起DMA请求时，产生初始化脉冲信号
            init_txn_ff   <= AXIDMA_REQ_VALID;
            init_txn_ff2 <= init_txn_ff;                                                                 
          end                                                                      
      end     


    //--------------------
    //Write Address Channel
    //--------------------

    // The purpose of the write address channel is to request the address and 
    // command information for the entire transaction.  It is a single beat
    // of information.

    // Note for this example the axi_awvalid/axi_wvalid are asserted at the same
    // time, and then each is deasserted independent from each other.
    // This is a lower-performance, but simplier control scheme.

    // AXI VALID signals must be held active until accepted by the partner.

    // A data transfer is accepted by the slave when a master has
    // VALID data and the slave acknoledges it is also READY. While the master
    // is allowed to generated multiple, back-to-back requests by not 
    // deasserting VALID, this design will add rest cycle for
    // simplicity.

    // Since only one outstanding transaction is issued by the user design,
    // there will not be a collision between a new request and an accepted
    // request on the same clock cycle. 

      always @(posedge M_AXI_ACLK)                                            
      begin                                                                        
        //Only VALID signals must be deasserted during reset per AXI spec          
        //Consider inverting then registering active-low reset for higher fmax     
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                   
          begin                                                                    
            axi_awvalid <= 1'b0;                                                   
          end                                                                      
          //Signal a new address/data command is available by user logic           
        else                                                                       
          begin                                                                    
            if (start_single_write)                                                
              begin                                                                
                axi_awvalid <= 1'b1;                                               
              end                                                                  
         //Address accepted by interconnect/slave (issue of M_AXI_AWREADY by slave)
            else if (M_AXI_AWREADY && axi_awvalid)                                 
              begin                                                                
                axi_awvalid <= 1'b0;                                               
              end                                                                  
          end                                                                      
      end                                                                          
                                                                                   
                                                                                   
      // start_single_write triggers a new write                                   
      // transaction. write_index is a counter to                                  
      // keep track with number of write transaction                               
      // issued/initiated                                                          
      always @(posedge M_AXI_ACLK)                                                 
      begin                                                                        
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                   
          begin                                                                    
            write_index <= 0;                                                      
          end                                                                      
          // Signals a new write address/ write data is                            
          // available by user logic                                               
        else if (start_single_write)                                               
          begin                                                                    
            write_index <= write_index + 1;                                        
          end                                                                      
      end                                                                          


    //--------------------
    //Write Data Channel
    //--------------------

    //The write data channel is for transfering the actual data.
    //The data generation is speific to the example design, and 
    //so only the WVALID/WREADY handshake is shown here

       always @(posedge M_AXI_ACLK)                                        
       begin                                                                         
         if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1)                                                    
           begin                                                                     
             axi_wvalid <= 1'b0;                                                     
           end                                                                       
         //Signal a new address/data command is available by user logic              
         else if (start_single_write)                                                
           begin                                                                     
             axi_wvalid <= 1'b1;                                                     
           end                                                                       
         //Data accepted by interconnect/slave (issue of M_AXI_WREADY by slave)      
         else if (M_AXI_WREADY && axi_wvalid)                                        
           begin                                                                     
            axi_wvalid <= 1'b0;                                                      
           end                                                                       
       end                                                                           


    //----------------------------
    //Write Response (B) Channel
    //----------------------------

    //The write response channel provides feedback that the write has committed
    //to memory. BREADY will occur after both the data and the write address
    //has arrived and been accepted by the slave, and can guarantee that no
    //other accesses launched afterwards will be able to be reordered before it.

    //The BRESP bit [1] is used indicate any errors from the interconnect or
    //slave for the entire write burst. This example will capture the error.

    //While not necessary per spec, it is advisable to reset READY signals in
    //case of differing reset latencies between master/slave.

      always @(posedge M_AXI_ACLK)                                    
      begin                                                                
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                           
          begin                                                            
            axi_bready <= 1'b0;                                            
          end                                                              
        // accept/acknowledge bresp with axi_bready by the master          
        // when M_AXI_BVALID is asserted by slave                          
        else if (M_AXI_BVALID && ~axi_bready)                              
          begin                                                            
            axi_bready <= 1'b1;                                            
          end                                                              
        // deassert after one clock cycle                                  
        else if (axi_bready)                                               
          begin                                                            
            axi_bready <= 1'b0;                                            
          end                                                              
        // retain the previous value                                       
        else                                                               
          axi_bready <= axi_bready;                                        
      end                                                                  
                                                                           
    //Flag write errors                                                    
    assign write_resp_error = (axi_bready & M_AXI_BVALID & M_AXI_BRESP[1]);


    //----------------------------
    //Read Address Channel
    //----------------------------

    //start_single_read triggers a new read transaction. read_index is a counter to
    //keep track with number of read transaction issued/initiated

      always @(posedge M_AXI_ACLK)                                                     
      begin                                                                            
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                       
          begin                                                                        
            read_index <= 0;                                                           
          end                                                                          
        // Signals a new read address is                                               
        // available by user logic                                                     
        else if (start_single_read)                                                    
          begin                                                                        
            read_index <= read_index + 1;                                              
          end                                                                          
      end                                                                              
                                                                                       
      // A new axi_arvalid is asserted when there is a valid read address              
      // available by the master. start_single_read triggers a new read                
      // transaction                                                                   
      always @(posedge M_AXI_ACLK)                                                     
      begin                                                                            
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                       
          begin                                                                        
            axi_arvalid <= 1'b0;                                                       
          end                                                                          
        //Signal a new read address command is available by user logic                 
        else if (start_single_read)                                                    
          begin                                                                        
            axi_arvalid <= 1'b1;                                                       
          end                                                                          
        //RAddress accepted by interconnect/slave (issue of M_AXI_ARREADY by slave)    
        else if (M_AXI_ARREADY && axi_arvalid)                                         
          begin                                                                        
            axi_arvalid <= 1'b0;                                                       
          end                                                                          
        // retain the previous value                                                   
      end                                                                              


    //--------------------------------
    //Read Data (and Response) Channel
    //--------------------------------

    //The Read Data channel returns the results of the read request 
    //The master will accept the read data by asserting axi_rready
    //when there is a valid read data available.  always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
    AXIDMA_REQ_READY    <= 1'b1;
    end
    else begin
      if(current_state == S_IDLE)
        AXIDMA_REQ_READY    <= 1'b1;
      else
        AXIDMA_REQ_READY    <= 1'b0;        
    end
  end

    //While not necessary per spec, it is advisable to reset READY signals in
    //case of differing reset latencies between master/slave.

      always @(posedge M_AXI_ACLK)                                    
      begin                                                                 
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                            
          begin                                                             
            axi_rready <= 1'b0;                                             
          end                                                               
        // accept/acknowledge rdata/rresp with axi_rready by the master     
        // when M_AXI_RVALID is asserted by slave                           
        else if (M_AXI_RVALID && ~axi_rready)                               
          begin                                                             
            axi_rready <= 1'b1;                                             
          end                                                               
        // deassert after one clock cycle                                   
        else if (axi_rready)                                                
          begin                                                             
            axi_rready <= 1'b0;                                             
          end                                                               
        // retain the previous value                                        
      end                                                                   
                                                                            
    //Flag write errors                                                     
    assign read_resp_error = (axi_rready & M_AXI_RVALID & M_AXI_RRESP[1]);  


    //--------------------------------
    //User Logic
    //--------------------------------
    (* mark_debug = "true" *)
    reg [7:0]   current_state;
    reg [7:0]   next_state;
    reg         transfer_finish;
    (* mark_debug = "true" *)
    reg [7:0]   cnt_wr_all;

    reg [127:0] dma_req;
    
    wire dma_run;
    assign dma_run = ~expected_rdata[`Reg_Sr_Halted];

  /***********************************************************
  * 当DiniDMA发起DMA请求并且目前状态为空闲时，接收请求字段 
  ***********************************************************/
  always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
      dma_req <= 128'b0;          
    end
    else begin
      if(AXIDMA_REQ_VALID & current_state == S_IDLE)
        dma_req <= AXIDMA_REQ_DATA;
      else
        dma_req <= 128'b0;                
    end
  end

  
  /***********************************************************
  * 只有当状态机处于空闲状态，才能接收AXIDMA的请求   
  ***********************************************************/
  always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
    AXIDMA_REQ_READY    <= 1'b1;
    end
    else begin
      if(current_state == S_IDLE)
        AXIDMA_REQ_READY    <= 1'b1;
      else
        AXIDMA_REQ_READY    <= 1'b0;        
    end
  end
    
  /***********************************************************
  * 如果AXI_DMA传输完成，给出中断信号，判断传输完成 
  ***********************************************************/
  always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
      transfer_finish    <= 1'b0;
    end
    else begin
      if(AXI_DMA_MM2S_IRQ)
        transfer_finish <= 1'b1;
      else
        transfer_finish <= 1'b0;        
    end
  end
    `ifdef SIMU_ON
    reg [15*8:0] write_state_str;
    
    always @(*)
    begin
        case(current_state)
        S_IDLE:
            write_state_str = "IDLE";
        S_START_DMA:
            write_state_str = "START_DMA";
        S_WAIT_DMA_RUN:
            write_state_str = "WAIT_DMA_RUN";
        S_EN_INTERRUPT:
            write_state_str = "EN_INTERRUPT";
        S_WRITE_SA:
            write_state_str = "WRITE_SA";
        S_WRITE_SA_MSB:
            write_state_str = "WRITE_SA_MSB";    
        S_WRITE_LENGTH:
            write_state_str = "WRITE_LENGTH";
        S_WAIT_DONE:
            write_state_str = "WAIT_DONE";
        default:
            write_state_str = "IDLE";
        endcase
     end
     `endif       
        
  
  always @(posedge M_AXI_ACLK or negedge M_AXI_ARESETN)
  begin
    if(!M_AXI_ARESETN)
      current_state <= S_IDLE;
    else
      current_state <= next_state;
  end
  (* mark_debug = "true" *)
  wire write_ack;
  assign write_ack = axi_awvalid && axi_wvalid && M_AXI_AWREADY && M_AXI_WREADY;
  always @(*)begin
  case(current_state)

      S_IDLE:
      if(start_single_write)
      begin
        next_state = S_START_DMA;
      end
      else begin
        next_state = S_IDLE;
      end
      //write the bit 0 of DMACR to start the DMA
      S_START_DMA:
        if(last_write)
          next_state  = S_WAIT_DMA_RUN;
        else
          next_state  = S_START_DMA;
      
      //
      S_WAIT_DMA_RUN:    
        if(dma_run)
          next_state  = S_EN_INTERRUPT;
        else
          next_state  = S_WAIT_DMA_RUN;
                           
      //write the bit 12 and 14 of DMACR to En the interrupt  
      S_EN_INTERRUPT:
        if(M_AXI_BVALID && M_AXI_BREADY)
          next_state  = S_WRITE_SA;
        else
          next_state  = S_EN_INTERRUPT;
      //write the length register
      S_WRITE_SA:
        if(M_AXI_BVALID && M_AXI_BREADY)
          next_state  = S_WRITE_SA_MSB;
        else
          next_state  = S_WRITE_SA;
      //write the length register MSB
      S_WRITE_SA_MSB:
        if(M_AXI_BVALID && M_AXI_BREADY)
          next_state  = S_WRITE_LENGTH;
        else
          next_state  = S_WRITE_SA_MSB;
      //write the length register to transfer
      S_WRITE_LENGTH:
        if(M_AXI_BVALID && M_AXI_BREADY)
          next_state  = S_WAIT_DONE;
        else
          next_state  = S_WRITE_LENGTH;        
      //wait the transfer by Irq finish
      S_WAIT_DONE:
        if(transfer_finish)
          next_state  = S_IDLE;
        else
          next_state  = S_WAIT_DONE;

      default : next_state  = S_IDLE;
    endcase
  end
  
  always@(*)
  begin
    case(current_state)
    S_IDLE:
    begin
      axi_wdata     = 32'd0;
      axi_awaddr    = 32'h0000_0000;
    end
    //step 1 set the run/stop bit of DMACR to start the DMA
    S_START_DMA:
    begin
      axi_awaddr              = MM2S_DMACR_ADDR;    
      axi_wdata[`Reg_Cr_EN]   = 1'b1;
      cnt_wr_all              = 8'd2;
    end
    S_WAIT_DMA_RUN:
    begin
      axi_araddr              = MM2S_DMASR_ADDR;
      expected_rdata          = M_AXI_RDATA; 
      cnt_wr_all              = 8'd100;        
    end
    //step 2 en the bit zone of interrupt
    S_EN_INTERRUPT:
    begin      
      axi_awaddr                    = MM2S_DMACR_ADDR;                
      axi_wdata[`Reg_Cr_ErrIrqEn]   = 1'b1;
      axi_wdata[`Reg_Cr_IOCIrqEn]   = 1'b1;
      cnt_wr_all                    = 8'd8;
    end
    //step 3
    S_WRITE_SA:
    begin
      axi_awaddr    = MM2S_SA;
      axi_wdata     = dma_req[95:64];       
    end
    //step 4    
    S_WRITE_SA_MSB:
    begin      
      axi_wdata     = dma_req[127:96];
      axi_awaddr    = MM2S_SA_MSB;
    end
    //step 5 write the length bytes to transfer ,this step is the last step
    S_WRITE_LENGTH:
    begin
      axi_wdata[22:0] = 23'd1024;         
      axi_awaddr      = MM2S_LENGTH;
    end
    //step 6,wait the Irq finish
    S_WAIT_DONE:                          
      ;
    default:
      axi_wdata     = 32'd0;
    endcase
  end
    //Address/Data Stimulus
     
  //Write Addresses
    /*                                        
      always @(posedge M_AXI_ACLK)                                  
          begin                                                     
            if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1)                                
              begin                                                 
                axi_awaddr <= 0;                                    
              end                                                   
              // Signals a new write address/ write data is         
              // available by user logic                            
            else if (M_AXI_AWREADY && axi_awvalid)                  
              begin                                                 
                //axi_awaddr <= axi_awaddr + 32'h00000004;            
              end                                                   
          end                                                       
                                                                    
      // Write data generation                                      
      always @(posedge M_AXI_ACLK)                                  
          begin                                                     
            if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 )                                
              begin                                                 
                axi_wdata <= C_M_START_DATA_VALUE;                  
              end                                                   
            // Signals a new write address/ write data is           
            // available by user logic                              
            else if (M_AXI_WREADY && axi_wvalid)                    
              begin                                                 
                axi_wdata <= C_M_START_DATA_VALUE + write_index;    
              end                                                   
            end                                                    
      */                                                              
      //Read Addresses                                              
/*       always @(posedge M_AXI_ACLK)                                  
          begin                                                     
            if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1)                                
              begin                                                 
                axi_araddr <= 0;                                    
              end                                                   
              // Signals a new write address/ write data is         
              // available by user logic                            
            else if (M_AXI_ARREADY && axi_arvalid)                  
              begin                                                 
                axi_araddr <= axi_araddr + 32'h00000004;            
              end                                                   
          end                                                       
                                                                    
                                                                    
                                                                    
      always @(posedge M_AXI_ACLK)                                  
          begin                                                     
            if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1)                                
              begin                                                 
                expected_rdata <= C_M_START_DATA_VALUE;             
              end                                                   
              // Signals a new write address/ write data is         
              // available by user logic                            
            else if (M_AXI_RVALID && axi_rready)                    
              begin                                                 
                expected_rdata <= C_M_START_DATA_VALUE + read_index;
              end                                                   
          end */                                                       
      //implement master command interface state machine                         
      always @ ( posedge M_AXI_ACLK)                                                    
      begin                                                                             
        if (M_AXI_ARESETN == 1'b0)                                                     
          begin                                                                         
          // reset condition                                                            
          // All the signals are assigned default values under reset condition          
            mst_exec_state  <= IDLE;                                            
            start_single_write <= 1'b0;                                                 
            write_issued  <= 1'b0;                                                      
            start_single_read  <= 1'b0;                                                 
            read_issued   <= 1'b0;                                                      
            compare_done  <= 1'b0;                                                      
            ERROR <= 1'b0;
          end                                                                           
        else                                                                            
          begin                                                                         
           // state transition                                                          
            case (mst_exec_state)                                                       
                                                                                        
              IDLE:                                                             
              // This state is responsible to initiate 
              // AXI transaction when init_txn_pulse is asserted 
                if ( init_txn_pulse == 1'b1 )                                     
                  begin                                                                 
                    mst_exec_state  <= INIT_WRITE;                                      
                    ERROR <= 1'b0;
                    compare_done <= 1'b0;
                  end                                                                   
                else                                                                    
                  begin                                                                 
                    mst_exec_state  <= IDLE;                                    
                  end                                                                   
                                                                                        
              INIT_WRITE:                                                               
                // This state is responsible to issue start_single_write pulse to       
                // initiate a write transaction. Write transactions will be             
                // issued until last_write signal is asserted.                          
                // write controller                                                     
                if (writes_done)                                                        
                  begin                                                                 
                    mst_exec_state <= INIT_READ;//                                      
                  end                                                                   
                else                                                                    
                  begin 
                    if(current_state != S_WAIT_DONE)
                        mst_exec_state  <= INIT_WRITE;                                      
                    else
                        mst_exec_state  <= IDLE;
                                                                                        
                      if (~axi_awvalid && ~axi_wvalid && ~M_AXI_BVALID && ~last_write && ~start_single_write && ~write_issued && (current_state != S_WAIT_DONE ))
                        begin                                                           
                          start_single_write <= 1'b1;                                   
                          write_issued  <= 1'b1;                                        
                        end                                                             
                      else if (axi_bready)                                              
                        begin                                                           
                          write_issued  <= 1'b0;                                        
                        end                                                             
                      else                                                              
                        begin                                                           
                          start_single_write <= 1'b0; //Negate to generate a pulse      
                        end                                                             
                  end                                                                   
                                                                                        
              INIT_READ:                                                                
                // This state is responsible to issue start_single_read pulse to        
                // initiate a read transaction. Read transactions will be               
                // issued until last_read signal is asserted.                           
                 // read controller                                                     
                 if (reads_done || dma_run)                                                        
                   begin                                                                
                     mst_exec_state <= INIT_WRITE;                                    
                   end                                                                  
                 else                                                                   
                   begin                                                                
                     mst_exec_state  <= INIT_READ;                                      
                                                                                        
                     if (~axi_arvalid && ~M_AXI_RVALID && ~last_read && ~start_single_read && ~read_issued)
                       begin                                                            
                         start_single_read <= 1'b1;                                     
                         read_issued  <= 1'b1;                                          
                       end                                                              
                     else if (axi_rready)                                               
                       begin                                                            
                         read_issued  <= 1'b0;                                          
                       end                                                              
                     else                                                               
                       begin                                                            
                         start_single_read <= 1'b0; //Negate to generate a pulse        
                       end                                                              
                   end                                                                  
                                                                                        
               INIT_COMPARE:                                                            
                 begin
                     // This state is responsible to issue the state of comparison          
                     // of written data with the read data. If no error flags are set,      
                     // compare_done signal will be asseted to indicate success.            
                     ERROR <= error_reg; 
                     mst_exec_state <= IDLE;                                    
                     compare_done <= 1'b1;                                              
                 end                                                                  
               default :                                                                
                 begin                                                                  
                   mst_exec_state  <= IDLE;                                     
                 end                                                                    
            endcase                                                                     
        end                                                                             
      end //MASTER_EXECUTION_PROC                                                       
                                                                                        
      //Terminal write count                                                            
                                                                                        
      always @(posedge M_AXI_ACLK)                                                      
      begin                                                                             
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 || mst_exec_state == INIT_READ)                                                         
          last_write <= 1'b0;                                                           
                                                                                        
        //The last write should be associated with a write address ready response       
        else if ((write_index == cnt_wr_all) && M_AXI_AWREADY)                
          last_write <= 1'b1;                                                           
        else                                                                            
          last_write <= last_write;                                                     
      end                                                                               
                                                                                        
      //Check for last write completion.                                                
                                                                                        
      //This logic is to qualify the last write count with the final write              
      //response. This demonstrates how to confirm that a write has been                
      //committed.                                                                      
                                                                                        
      always @(posedge M_AXI_ACLK)                                                      
      begin                                                                             
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 || mst_exec_state == INIT_READ)                                                         
          writes_done <= 1'b0;                                                          
                                                                                        
          //The writes_done should be associated with a bready response                 
        else if (last_write && M_AXI_BVALID && axi_bready)                              
          writes_done <= 1'b1;                                                          
        else                                                                            
          writes_done <= writes_done;                                                   
      end                                                                               
                                                                                        
    //------------------                                                                
    //Read example                                                                      
    //------------------                                                                
                                                                                        
    //Terminal Read Count                                                               
                                                                                        
      always @(posedge M_AXI_ACLK)                                                      
      begin                                                                             
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 || mst_exec_state == INIT_WRITE)                                                         
          last_read <= 1'b0;                                                            
                                                                                        
        //The last read should be associated with a read address ready response         
        else if ((read_index == cnt_wr_all) && (M_AXI_ARREADY) )              
          last_read <= 1'b1;                                                            
        else                                                                            
          last_read <= last_read;                                                       
      end                                                                               
                                                                                        
    /*                                                                                  
     Check for last read completion.                                                    
                                                                                        
     This logic is to qualify the last read count with the final read                   
     response/data.                                                                     
     */                                                                                 
      always @(posedge M_AXI_ACLK)                                                      
      begin                                                                             
        if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                         
          reads_done <= 1'b0;                                                           
                                                                                        
        //The reads_done should be associated with a read ready response                
        else if (last_read && M_AXI_RVALID && axi_rready)                               
          reads_done <= 1'b1;                                                           
        else                                                                            
          reads_done <= reads_done;                                                     
        end                                                                             
                                                                                        
    //-----------------------------                                                     
    //Example design error register                                                     
    //-----------------------------                                                     
                                                                                        
    //Data Comparison                                                                   
      always @(posedge M_AXI_ACLK)                                                      
      begin                                                                             
        if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1)                                                         
        read_mismatch <= 1'b0;                                                          
                                                                                        
        //The read data when available (on axi_rready) is compared with the expected data
        else if ((M_AXI_RVALID && axi_rready) && (M_AXI_RDATA != expected_rdata))         
          read_mismatch <= 1'b1;                                                        
        else                                                                            
          read_mismatch <= read_mismatch;                                               
      end                                                                               
                                                                                        
    // Register and hold any data mismatches, or read/write interface errors            
      always @(posedge M_AXI_ACLK)                                                      
      begin                                                                             
        if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1)                                                         
          error_reg <= 1'b0;                                                            
                                                                                        
        //Capture any error types                                                       
        else if (read_mismatch || write_resp_error || read_resp_error)                  
          error_reg <= 1'b1;                                                            
        else                                                                            
          error_reg <= error_reg;                                                       
      end                                                                               
    // Add user logic here

    // User logic ends

    endmodule
