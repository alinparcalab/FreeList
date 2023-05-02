// -----------------------------------------------------------------------------
// Module name: FreeList
// HDL        : System Verilog
// Author     : Alin Parcalab (AP)
// Description: The main task of this module is to generate unique names 
//              this is a priority picker cascading based free list
// Date       : 01 May, 2023
// -----------------------------------------------------------------------------

module FreeList # 
(  parameter pEnScan  =  1, // Enable Scan Mode Generation
   parameter pEnFwd   =  1, // Enable Forwarding Dealocation to Name Generator
   parameter pHwPhy0  =  1, // Phy0 is Hardwired to 0 -> Never generate a Phy0 Name (Zero '0' Or One '1'!!!)
   parameter pBitVecW = 16, // Bit Vector Width
   parameter pAlcIO   =  4, // Number of Allocation Ports
   parameter pDeAlcIO =  8  // Number of Deallocation Ports
)( // ------------------------------------------
   input  logic Clk, // Clock 
   input  logic Rsn, // Asynchronous Reset Active Low '0'
   input  logic Clr, // Synchronous Reset Active High '1'
   // ------------------------------------------

   // ------------------------------------------
   input  logic ScanEn,  // Scan Enable Active High '1' -> If pEnScan == 0 - Scan Logic is not generated -> tiedValue to '0'             
   input  logic ScanIn,  // Scan Data Input             -> If pEnScan == 0 - Scan Logic is not generated -> tiedValue to '0' 
   output logic ScanOut, // Scan Data Output            -> If pEnScan == 0 - Scan Logic is not generated -> tiedValue to Open
   // ------------------------------------------

   // ------------------------------------------
   input  logic [pAlcIO-1:0] AllocReq, // Allocation Request Active High '1'
   output logic [pAlcIO-1:0] AllocVld, // Allocation Valid Active High '1'

   output logic [pAlcIO-1:0][$clog2(pBitVecW)-1:0] AllocPhy, // Allocated Phy Address 
   // ------------------------------------------

   // ------------------------------------------
   input  logic [pDeAlcIO-1:0] DeAllocReq, // Deallocation Request Active High '1'

   input  logic [pDeAlcIO-1:0][$clog2(pBitVecW)-1:0] DeAllocPhy, // Deallocate Phy Address 
   // ------------------------------------------

   // ------------------------------------------
   output logic FreeListEmpty, // Free List Is Empty Active High '1'
   // ------------------------------------------  

   // ------------------------------------------
   input  logic [pBitVecW-1:pHwPhy0] wBitVec, // Input Bit Vector (SS)

   input  logic weBitVec,                     // Write wBitVec enable Active High '1'

   output logic [pBitVecW-1:pHwPhy0] rBitVec, // Output Current Bit Vector  
   // ------------------------------------------

   // ------------------------------------------   
   output logic [pBitVecW-1:pHwPhy0] rBitVecFF // Read Flip Flop Bit Vector - Debug - If Forwarding is disabled, the rBitVec may replace this
   // ------------------------------------------
);

   // ------------------------------------------
   // ------------ Internal Signals ------------
   // ------------------------------------------
   logic [pAlcIO-1:0][$clog2(pBitVecW)-1:0] 
         genPhyAddr;

   logic [pAlcIO-1:0][pBitVecW-1:pHwPhy0] 
         _Pickers_;

   logic [pBitVecW-1:pHwPhy0][pAlcIO-1:0] 
         Transpose_Pickers;      

   logic [pBitVecW-1:pHwPhy0][pDeAlcIO-1:0] 
         Transpose_Dealloc;

   logic [pBitVecW-1:pHwPhy0] 
         BitVecFF, BitVecLo, BitVecFwdMux, 
         Transpose_Pickers_Or_Tree, Transpose_Dealloc_And_Tree;

   logic [pAlcIO-1:0][pBitVecW-1:pHwPhy0] 
         BitVecOR;
   // ------------------------------------------


   // ------------------------------------------
   // ------------ Free List Status ------------
   // ------------------------------------------
   assign FreeListEmpty = & BitVecFwdMux; // If the BitVecFwdMux is filled with '1' then the free list is Empty
   // ------------------------------------------


   // ------------------------------------------
   // ------------ Bit Vector Logic ------------
   // ------------------------------------------
   for (genvar i=pHwPhy0; i<pBitVecW; i++) // Iterate every position of the Bit Vector
      for (genvar y=0; y<pAlcIO; y++) // Iterate every Allocation port
         assign Transpose_Pickers[i][y] = (_Pickers_[y][i] == 1'b1) & AllocReq[y]; // if the AllocReq of port 'y' is set '1' and _Picker_[y] bit [i] is set '1' 
                                                                                   // than Transpose_Pickers is set '1' to Allocate Position i

   for (genvar i=pHwPhy0; i<pBitVecW; i++) // Iterate every position of the Bit Vector
      assign Transpose_Pickers_Or_Tree[i] = (| Transpose_Pickers[i]); // (Transpose_Pickers[i] != 0) --- Check for Allocation Request at Position 'i' 

   // -------

   for (genvar i=pHwPhy0; i<pBitVecW; i++) // Iterate every position of the Bit Vector
      for (genvar z=0; z<pDeAlcIO; z++) // Iterate every Deallocation port
         assign Transpose_Dealloc[i][z] = ~(DeAllocReq[z] & DeAllocPhy[z] == i); // If there is a Deallocation Request at Address 'i' set Transpose_Dealloc at Address 'i' to '0'

   for (genvar i=pHwPhy0; i<pBitVecW; i++) // Iterate every position of the Bit Vector
      assign Transpose_Dealloc_And_Tree[i] = (& Transpose_Dealloc[i]); // (Transpose_Dealloc[i] == ((2**pDeAlcIO)-1))
   
   // -------

   for (genvar i=pHwPhy0; i<pBitVecW; i++) // Iterate every position of the Bit Vector
      assign BitVecLo[i] = Transpose_Pickers_Or_Tree[i] | (Transpose_Dealloc_And_Tree[i] & BitVecFF[i]); // Allocate OR Deallocate BitVecFF at position 'i'
 
   // -------


   // -------
   if (pEnScan) assign ScanOut = BitVecFF[pBitVecW-1];
   else         assign ScanOut = 1'b0;
   // -------

   always_ff @(posedge Clk or negedge Rsn) // Generate Bit Vector Register
   if (!Rsn              ) BitVecFF <= 0                                     ; else // Asynchronous Reset
   if ( Clr              ) BitVecFF <= 0                                     ; else // Synchronous Reset
   if ( ScanEn & pEnScan ) BitVecFF <= {BitVecFF[pBitVecW-2:pHwPhy0], ScanIn}; else // Scan Mode - Shift Register
   if ( weBitVec         ) BitVecFF <= wBitVec                               ; else // Load New Bit Vector (Maybe Snapshot)  
                           BitVecFF <= BitVecLo                              ;      // Load Value from the Bit Vector Logic  
   
   assign rBitVecFF = BitVecFF;
   // -------
   
   for (genvar i=pHwPhy0; i<pBitVecW; i++)
      if(pEnFwd) assign BitVecFwdMux[i] = Transpose_Dealloc_And_Tree[i] & BitVecFF[i]; // Forward Dealocation to Pickers
      else       assign BitVecFwdMux[i] = BitVecFF[i];                                 // Fwd will add extra latency, if it is not needed just Set pEnFwd = 0
   // -------  

   assign rBitVec = BitVecFwdMux;                                    
   // ------------------------------------------


   // ------------------------------------------    
   // ------------ Or Vector Logic -------------
   // ------------------------------------------
   assign BitVecOR[0] = _Pickers_[0] | BitVecFwdMux;     // After Every Picking, the Picker will Return a 1-bit set
                                                         // In order to feed the next picker correctly the output of the current
   for (genvar i=1; i<pAlcIO; i++)                        // picker must be OR with the BitVec FF or with the output from the Previous
      assign BitVecOR[i] = _Pickers_[i] | BitVecOR[i-1]; // BitVecOR 
   // ------------------------------------------


   // ------------------------------------------
   // ----------- Picker Instance --------------
   // ------------------------------------------
   _picker_220220310_RenameFreeList_ #(.pW(pBitVecW)) i_picker0 (.iBitVec(BitVecFwdMux),.oBitVec(_Pickers_[0])); // Picker Instance

   for (genvar i=1; i<pAlcIO; i++)
      _picker_220220310_RenameFreeList_ #(.pW(pBitVecW)) i_picker1 (.iBitVec(BitVecOR[i-1]),.oBitVec(_Pickers_[i])); // Picker Instance
   // ------------------------------------------


   // ------------------------------------------
   // ----------- Picker Addr Gen --------------
   // ------------------------------------------
   always_comb begin
      for (integer k=0; k<pAlcIO; k++) genPhyAddr[k] = 0; // Set Default to '0'
       
      for (integer k=0; k<pAlcIO; k++)  // Iterate every Allocation Port 
         for (integer i=pHwPhy0; i<pBitVecW; i++) // Iterate every output bit of every Picker 
            if (_Pickers_[k][i] == 1'b1) genPhyAddr[k] = i; // If the 'i' of 'k' picker is set '1' the 'k' will get the 'i' value 
   end  
   // ------------------------------------------


   // ------------------------------------------
   // ------------- IO Ports Gen ---------------
   // ------------------------------------------
   for (genvar y=0; y<pAlcIO; y++) begin     
      assign AllocPhy[y] = genPhyAddr[y]; // Forward to the Ports the generated Address
      assign AllocVld[y] = (| _Pickers_[y]) & AllocReq[y]; // Ack the Allocation 
                                                           // By checking the Pickers output instead of the BitVecFwdMux
                                                           // The number of wires on the BitVecFwdMux will be reduce
                                                           // This shouldn't add latency, at least not much since 
                                                           // the pickers out are converted to addresses in parallel
   end
   // ------------------------------------------

endmodule : FreeList



module _picker_220220310_RenameFreeList_ #
(  parameter pW = 16
)( input  logic [pW-1:0] iBitVec,
   output logic [pW-1:0] oBitVec
);

   assign oBitVec[0] = ~iBitVec[0];

   for(genvar i=1; i<pW; i++) assign oBitVec[i] = (& iBitVec[i-1:0]) & ~iBitVec[i]; // Optimized on synthesis

endmodule : _picker_220220310_RenameFreeList_
