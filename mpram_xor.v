////////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2014, University of British Columbia (UBC); All rights reserved. //
//                                                                                //
// Redistribution  and  use  in  source   and  binary  forms,   with  or  without //
// modification,  are permitted  provided that  the following conditions are met: //
//   * Redistributions   of  source   code  must  retain   the   above  copyright //
//     notice,  this   list   of   conditions   and   the  following  disclaimer. //
//   * Redistributions  in  binary  form  must  reproduce  the  above   copyright //
//     notice, this  list  of  conditions  and the  following  disclaimer in  the //
//     documentation and/or  other  materials  provided  with  the  distribution. //
//   * Neither the name of the University of British Columbia (UBC) nor the names //
//     of   its   contributors  may  be  used  to  endorse  or   promote products //
//     derived from  this  software without  specific  prior  written permission. //
//                                                                                //
// THIS  SOFTWARE IS  PROVIDED  BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" //
// AND  ANY EXPRESS  OR IMPLIED WARRANTIES,  INCLUDING,  BUT NOT LIMITED TO,  THE //
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE //
// DISCLAIMED.  IN NO  EVENT SHALL University of British Columbia (UBC) BE LIABLE //
// FOR ANY DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY, OR CONSEQUENTIAL //
// DAMAGES  (INCLUDING,  BUT NOT LIMITED TO,  PROCUREMENT OF  SUBSTITUTE GOODS OR //
// SERVICES;  LOSS OF USE,  DATA,  OR PROFITS;  OR BUSINESS INTERRUPTION) HOWEVER //
// CAUSED AND ON ANY THEORY OF LIABILITY,  WHETHER IN CONTRACT, STRICT LIABILITY, //
// OR TORT  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE //
// OF  THIS SOFTWARE,  EVEN  IF  ADVISED  OF  THE  POSSIBILITY  OF  SUCH  DAMAGE. //
////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////
//            mpram_xor.v: Multiported-RAM based on XOR implementation            //
//                                                                                //
//   Author: Ameer M.S. Abdelhadi (ameer@ece.ubc.ca, ameer.abdelhadi@gmail.com)   //
//   Switched SRAM-based Multi-ported RAM; University of British Columbia, 2014   //
////////////////////////////////////////////////////////////////////////////////////

`include "utils.vh"

module mpram_xor
#( parameter MD  = 16, // memory depth
   parameter DW  = 32, // data width
   parameter nR  = 2 , // number of reading ports
   parameter nW  = 2 , // number of writing ports
   parameter WAW = 1 , // allow Write-After-Write (need to bypass feedback ram)
   parameter RAW = 1 , // new data for Read-after-Write (need to bypass output ram)
   parameter RDW = 0 , // new data for Read-During-Write
   parameter INI = ""  // initialization: CLR for zeros, or hex/bin file name (file extension .hex/.bin)
)( input                    clk  , // clock
   input [          nW-1:0] wEn  , // write enable for each writing port
   input [`log2(MD)*nW-1:0] wAddr, // write addresses - packed from nW write ports
   input [      DW *nW-1:0] wData, // write data      - packed from nW read ports
   input [`log2(MD)*nR-1:0] rAddr, // read  addresses - packed from nR read  ports
   output reg [ DW *nR-1:0] rData  // read  data      - packed from nR read ports
);

  // local parameters
  localparam AW = `log2(MD); // address width
  localparam INIEXT = INI[23:0]; // extension of initializing file (if exists)
  localparam isINI  = (INI   =="CLR" ) || // RAM is initialized if cleared,
                      (INIEXT=="hex") || // or initialized from .hex file,
                      (INIEXT=="bin")  ; // or initialized from .bin file

  // Register write addresses, data and enables
  reg [AW*nW-1:0] wAddr_r; // registered write addresses - packed from nW write ports
  reg [DW*nW-1:0] wData_r; // registered write data - packed from nW read ports
  reg [   nW-1:0] wEn_r  ; // registered write enable for each writing port
  always @(posedge clk) begin
    wAddr_r <= wAddr;
    wData_r <= wData;
    wEn_r   <= wEn  ;
  end

  // unpacked/pack addresses/data
  reg  [AW       -1:0] wAddr2D    [nW-1:0]        ; // write addresses            / 2D
  reg  [AW       -1:0] wAddr2D_r  [nW-1:0]        ; // registered write addresses / 2D
  reg  [DW       -1:0] wData2D    [nW-1:0]        ; // write data                 / 2D 
  reg  [DW       -1:0] wData2D_r  [nW-1:0]        ; // registered write data      / 2D
  wire [DW* nR   -1:0] rDataOut2D [nW-1:0]        ; // read data out              / 2D
  reg  [DW       -1:0] rDataOut3D [nW-1:0][nR-1:0]; // read data out              / 3D
  reg  [AW*(nW-1)-1:0] rAddrFB2D  [nW-1:0]        ; // read address fb            / 2D
  reg  [AW       -1:0] rAddrFB3D  [nW-1:0][nW-2:0]; // read address fb            / 3D
  wire [DW*(nW-1)-1:0] rDataFB2D  [nW-1:0]        ; // read data fb               / 2D
  reg  [DW       -1:0] rDataFB3D  [nW-1:0][nW-2:0]; // read data fb               / 3D
  reg  [DW       -1:0] wDataFB2D  [nW-1:0]        ; // write data                 / 2D
  reg  [DW       -1:0] rData2D    [nR-1:0]        ; // read data                  / 2D 
  `ARRINIT;
  always  @* begin
    `ARR1D2D(nW,     AW,wAddr     ,wAddr2D   );
    `ARR1D2D(nW,     AW,wAddr_r   ,wAddr2D_r );
    `ARR1D2D(nW,     DW,wData     ,wData2D   );
    `ARR1D2D(nW,     DW,wData_r   ,wData2D_r );
    `ARR2D1D(nR,     DW,rData2D   ,rData     );
    `ARR2D3D(nW,nR  ,DW,rDataOut2D,rDataOut3D);
    `ARR3D2D(nW,nW-1,AW,rAddrFB3D ,rAddrFB2D );
    `ARR2D3D(nW,nW-1,DW,rDataFB2D ,rDataFB3D );
  end

  // generate and instantiate mulriread RAM blocks
  genvar wpi;
  generate
    for (wpi=0 ; wpi<nW ; wpi=wpi+1) begin: RPORTwpi
      // feedback multiread ram instantiation
      mrdpramSS   #( .MD   (MD                    ),  // memory depth
                     .DW   (DW                    ),  // data width
                     .nR   (nW-1                  ),  // number of reading ports
                     .BYP  (WAW || RDW || RAW     ),  // bypass? 0:none; 1:single-stage; 2:two-stages
                     .INI  ((wpi&&isINI)?"CLR":INI)) // initialization: CLR for zeros, or hex/bin file name (file extension .hex/.bin)
      mrdpramSSfdb ( .clk  (clk                   ),  // clock                                       - in
                     .wEn  (wEn_r[wpi]            ),  // write enable  (1 port)                      - in
                     .wAddr(wAddr2D_r[wpi]        ),  // write address (1 port)                      - in : [`log2(MD)   -1:0]
                     .wData(wDataFB2D[wpi]        ),  // write data    (1 port)                      - in : [      DW    -1:0]
                     .rAddr(rAddrFB2D[wpi]        ),  // read  addresses - packed from nR read ports - in : [`log2(MD)*nR-1:0]
                     .rData(rDataFB2D[wpi]        )); // read  data      - packed from nR read ports - out: [      DW *nR-1:0]
      // output multiread ram instantiation
      mrdpramSS   #( .MD   (MD                    ),  // memory depth
                     .DW   (DW                    ),  // data width
                     .nR   (nR                    ),  // number of reading ports
                     .BYP  (RDW ? 2 : RAW         ),  // bypass? 0:none; 1:single-stage; 2:two-stages
                     .INI  ((wpi&&isINI)?"CLR":INI)) // initialization: CLR for zeros, or hex/bin file name (file extension .hex/.bin)
      mrdpramSSout ( .clk  (clk                   ),  // clock                                       - in
                     .wEn  (wEn_r[wpi]            ),  // write enable  (1 port)                      - in
                     .wAddr(wAddr2D_r[wpi]        ),  // write address (1 port)                      - in : [`log2(MD)   -1:0]
                     .wData(wDataFB2D[wpi]        ),  // write data    (1 port)                      - in : [      DW    -1:0]
                     .rAddr(rAddr                 ),  // read  addresses - packed from nR read ports - in : [`log2(MD)*nR-1:0]
                     .rData(rDataOut2D[wpi]       )); // read  data      - packed from nR read ports - out: [      DW *nR-1:0]
    end
  endgenerate

  // combinatorial logic for output and feedback functions
  integer i,j,k;
  always @* begin
    // generate output read functions
    for(i=0;i<nR;i=i+1) begin
      rData2D[i] = rDataOut3D[0][i];
      for(j=1;j<nW;j=j+1) rData2D[i] = rData2D[i] ^ rDataOut3D[j][i];
    end
    // generate feedback functions
    for(i=0;i<nW;i=i+1) wDataFB2D[i] = wData2D_r[i];
    for(i=0;i<nW;i=i+1) begin
      k = 0;
      for(j=0;j<nW-1;j=j+1) begin
        k=k+(j==i);
        rAddrFB3D[i][j] = wAddr2D[k];
        wDataFB2D[k] = wDataFB2D[k] ^ rDataFB3D[i][j];
        k=k+1;
      end
    end
  end

endmodule
