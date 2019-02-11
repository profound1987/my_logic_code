// +FHDR***********************************************************************
// Copyright        :   CNG
// Confidential     :   I LEVEL
// ============================================================================
// FILE NAME        :
// CREATE DATE      :   2017-06-10
// DEPARTMENT       :   R&D
// AUTHOR           :   TingtingGan
// AUTHOR'S EMAIL   :   gantingting@cng.com
// AUTHOR'S TEL     :   18280151291
// ============================================================================
// RELEASE  HISTORY
// VERSION  DATE        AUTHOR          DESCRIPTION
// V100     2017-06-10  TingtingGan     Original
// ============================================================================
// KEYWORDS         :
// PURPOSE          : gray to bin convert
// ============================================================================
// REUSE ISSUES
// Reset Strategy   :   Async clear, active hign
// Clock Domains    :   clk_125m
// Critical Timing  :   N/A
// Instantiations   :   N/A
// Ynthesizable     :   N/A
// Others           :
// -FHDR***********************************************************************
`timescale 1 ns / 1 ns
`include "DEFINES.v"

module gtbc
    (
    gray_in                     ,   
    bin_out
    );

/**********************************************************************************\
***************************** declare parameter ************************************
\**********************************************************************************/
parameter   ADDRWIDTH  = 3 ;

/**********************************************************************************\
***************************** declare interface signal *****************************
\**********************************************************************************/
// declare input singal
input       [ADDRWIDTH:0]       gray_in                             ;   

// declare output signal
output      [ADDRWIDTH:0]       bin_out                             ;   

// declare inout signal

/**********************************************************************************\
**************************** declare singal attribute ******************************
\**********************************************************************************/
// wire signal

// reg signal
reg     [ADDRWIDTH:0]           bin_out                             ;   
integer                         i                                   ;   

/**********************************************************************************\
******************************** debug code ****************************************
\**********************************************************************************/

/**********************************************************************************\
********************************* main code ****************************************
\**********************************************************************************/

always @(*) begin
   bin_out[ADDRWIDTH]  = gray_in[ADDRWIDTH];      
   for ( i=ADDRWIDTH ; i>0 ; i = i-1 ) begin
      bin_out[i-1]     = (bin_out[i] ^ gray_in[i-1]);
   end

end

endmodule 
