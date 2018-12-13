// Control unit of neural network.

`timescale 1ps / 1ps

`include "fixed_point.vh"

module control_unit(clk, rst, batch, x_dout, nd_dout, x_addr, y_addr, t_addr, nd_addr, state, e_x, e_y, e_nd, we, x_we, y_we,
                    nd_we, t_we, bp_we, dtb);
  
  parameter ltot = 99;
  parameter [32*ltot-1:0] lr = 99;
  localparam sx = lr[0*32 +: 32];  // Size of inputs
  localparam sl = lr[2*32 +: 32];  // Total node of last layer
  
  parameter a = 99;   // Address width
  
  parameter nd = 99;  // Total node all layers
  parameter wt = 99;  // Total all weights
  
  // Below are params that will be set to signals later
  localparam max_it = 10000;
  localparam mode = 3;  // 2 feedforward, 3 backprop
  
  localparam n = `n; // Bit
  localparam f = `f; // Fraction
  localparam i = `i; // Integer
  
  localparam t0 = {{n-4{1'b0}}, 4'd10}; // The initial address for supervisor, in the output memory

  input clk, rst;
  input signed [n-1:0] batch;
  input [n*sx-1:0] x_dout;
  input [n-1:0] nd_dout;
  output reg [a-1:0] x_addr;
  output reg [a-1:0] y_addr;
  output reg [a-1:0] t_addr;
  output reg [a-1:0] nd_addr;
  
  // Control signals (wires)
  output reg [2:0] state;
  output reg e_x, e_y, e_nd;  // Control signals for memory-to-bus buffers
  output reg [nd-1:0] we;     // Layer nodes coeffs
  
  output reg [7:0] x_we, y_we, t_we;
  output reg [7:0] nd_we;
  
  output reg [wt+nd-1:0] bp_we; // One for each constant
  output reg dtb;               // 0: bp_we enable writing to dff, 1: bp_we enable bus buffer
  
  // Counters
  integer data;   // Counting the data for an iteration
  integer iterate;
  integer l, d, c;   // Layer, node, and coef counter
  integer ld, ldp;     // Total node in this layer, and prev
  
  // Control unit
  always @(posedge clk or posedge rst) begin
    if (rst) begin
    
      // Reset
      state = 3'd0;
      we = {nd{1'b0}};
      e_x = 1'b0;
      e_y = 1'b0;
      e_nd = 1'b0;
      
      x_addr = {n{1'b0}};
      y_addr = {n{1'b0}};
      t_addr = t0;
      nd_addr = {n{1'b0}};
      
      bp_we = {(wt+nd){1'b0}};
      dtb = 1'b0;
      
      data = 0;
//      delay = 0;
      iterate = 0;
      l = 0; d = 0; c = 0;
      ld = 0; ldp = 0;
      
    end else begin
    
//      delay = data; // Will assign the clock after
      
      if (state == 3'd0) begin
        $display("[[[Start Loading]]]");
        state = 3'd1;
        
        // Initialize for next state
        l = 1; d = 0; c = -1; // Start on first hidden layer for loading
        nd_addr = {n{1'b0}}; 
      end
        
      // Load data    
      else if (state == 3'd1) begin
        
        // Moved to be combinational
//        ld = lr[l*32 +: 32];  // Get total node in a layer
        
//        if (l > 0) ldp = lr[(l-1)*32 +: 32]; 
//        else ldp = 0;
        
        e_nd = 1'b1; // Weights and biases to bus
        
        if (l == ltot) begin
          // End loading
          state = mode;
          we = {nd{1'b0}};
          e_nd = 1'b0;
          data = -1;
          x_addr = x_addr + 1'd1;
          y_addr = y_addr + 1'd1;
          t_addr = t_addr + 1'd1;
          
          l = 0;
          $display("[[[State-%1d]]]", state);
        end else if ((d == ld-1) && (c == ldp+1-1)) begin
          // Until all layers
          nd_addr = nd_addr + 1'd1;
          we = we >> 1; // Load for next node
          
          d = 0;
          c = 0;
          l = l + 1;
        end else if (c == ldp+1-1) begin
          // Until all nodes in a layer
          nd_addr = nd_addr + 1'd1;
          we = we >> 1; // Load for next node
          
          c = 0;
          d = d + 1;
        end else if (we != {nd{1'b0}}) begin
          // Until all coefs in a node
          // Increment node address
          nd_addr = nd_addr + 1'd1;
          
          c = c + 1;
        end else begin
          // Initalize writing here, compensating memory latency
          we = 1'b1 << (nd-1);
          nd_addr = nd_addr + 1'd1;
        end
      
      // Feedforward
      end else if (state == 3'd2) begin
              
        y_we = {8{1'b1}};  // Write last output
        
        // Increment in out address
        if (x_dout != {{sx*n-12{1'b0}}, 12'h888}) begin   // Continue if not reading 888 (non-frac)
          x_addr = x_addr + 1'd1;
          y_addr = y_addr + 1'd1;
        end
        
      // Backpropagation  
      end else if (state == 3'd3) begin
        
        // Address is separated because 1 clock latency in BRAM
        if (iterate < max_it) begin
          if (data < batch) begin
            $display("[Data-%02d]", x_addr);
            // Increment in out address
            x_addr = x_addr + 1'd1;
            y_addr = y_addr + 1'd1;
            t_addr = t_addr + 1'd1;
            
            // Write calculation to dff
            dtb = 1'b0;               // 0: bp_we enable writing to dff, 1: bp_we enable bus buffer
            bp_we = {(wt+nd){1'b1}};  // Enable simultateously, cause one dff is placed for each node
            
            data = data + 1;
          end else begin
            // Reset
            // Should've been next batch addr, because it's end of iteration; not end of epoch.
            x_addr = 0;
            y_addr = 0;
            t_addr = t0;
            
            iterate = iterate + 1;
            $display("[[Iteration=%02d]]", iterate);
            
            // Save learning results
            state = 3'd4;
            bp_we = 1'b1  << (wt+nd-1);
            dtb = 1'b1;           // to memory (through bus) instead of registers
            l = 1; d = 0; c = -1; // Start on first hidden layer for loading
            nd_addr = {n{1'b0}}; 
            data = 0; 
            
            $display("[[[State-%1d]]]", state);  
          end
        end
        
      // Save new values
      end else if (state == 3'd4) begin
        
        // Moved to be combinational
//        ld = lr[l*32 +: 32];  // Get total node in a layer
        
//        if (l > 0) ldp = lr[(l-1)*32 +: 32]; 
//        else ldp = 0;
        
        dtb = 1'b1;           // to memory (through bus) instead of registers
        nd_we = {8{1'b1}};    // Write new coefs to memory
        
        if (l == ltot) begin
          // End saving
          state = 3'd0; // Re-loading coefs
          bp_we = {(wt+nd){1'b0}};
          nd_we = {8{1'b0}};    // Write new coefs to memory
          data = 0;
          dtb = 1'b0;   // to memory (through bus) instead of registers
          nd_addr = {n{1'b0}};
          
          l = 0;
          $display("[[[State-%1d]]]", state);
        end else if ((d == ld-1) && (c == ldp+1-1)) begin
          // Until all layers
          bp_we = bp_we >> 1; // Save for next coef
          nd_addr = nd_addr + 1'd1;
          
          d = 0;
          c = 0;
          l = l + 1;
        end else if (c == ldp+1-1) begin
          // Until all nodes in a layer
          bp_we = bp_we >> 1; // Save for next coef
          nd_addr = nd_addr + 1'd1;
          
          c = 0;
          d = d + 1;
        end else if (bp_we != {(wt+nd){1'b0}}) begin
          // Until all coefs in a node
          bp_we = bp_we >> 1; // Save for next coef
          nd_addr = nd_addr + 1'd1; // Increment node address
          
          c = c + 1;
        end else begin
          // Initalize writing here, compensating memory latency
          bp_we = 1'b1 << ((wt+nd)-1);
          nd_addr = nd_addr + 1'd1;
        end
        
      end
      
    end
  end
  
  always @(*) begin
    if (l < ltot) ld = lr[l*32 +: 32];  // Get total node in a layer
    else ld = 0;
    
    if (l > 0) ldp = lr[(l-1)*32 +: 32]; 
    else ldp = 0;
  end
  
endmodule
