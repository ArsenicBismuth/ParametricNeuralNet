// Top level and datapath of neural network.

`timescale 1ps / 1ps

`include "fixed_point.vh"

module neural(clk, rst, batch);
  
  parameter a = 32; // Address width
  localparam n = `n; // Bit
  localparam f = `f; // Fraction
  localparam i = `i; // Integer
  
  // Layer params
  parameter ltot = 4;
  parameter sx = 5;     
  parameter sl1 = 7;
  parameter sl2 = 7;
  parameter sl = 1;     // Total node of last layer
  parameter [32*ltot-1:0] lr = {sl, sl2, sl1, sx}; // Nodes in a layer, LSB are the input
  
  localparam nd = sl1+sl2+sl;       // Total all nodes
  localparam wt = sx*sl1 + sl1*sl2 + sl2*sl;  // Total all weights
  
  input clk, rst;
  input [n-1:0] batch;  // Number of data each iteration
  
  wire [n-1:0] bus;  // Bus max width is sx*n, but some (like node) only use n.
  
  // Memory wires, see diagram or updated wrapper
  wire [a-1:0] x_addr;
  wire [a-1:0] y_addr;
  wire [a-1:0] t_addr;
  wire [n-1:0] x_din, x_dout;
  wire [n*sl-1:0] y_din, y_dout;
  wire [n*sl-1:0] t_din, t_dout;
  
  wire [a-1:0] nd_addr;
  wire [n-1:0] nd_din, nd_dout;
  
  // Layer & backprop wires
  wire [n*sx-1:0] nx;  // Concatenation of sx amount of x    
  wire [n*sl-1:0] ly;  // Concatenation of sl amount of y
  wire [n*sl-1:0] lt;  // Concatenation of sl amount of t
  
  wire [n*nd-1:0] yall;
  wire [n*wt-1:0] wall;
  wire [n*nd-1:0] ball;
  
  wire [n-1:0] cost;
  
  // Control signals (wires)
  wire [2:0] state;
  wire e_x, e_y, e_nd;  // Control signals for memory-to-bus buffers 
  wire [nd-1:0] c_we;   // Layer nodes coeffs, also another one for backprop mode
  wire [sx-1:0] in_we;  // Control signals for bus-to-shiftregs
  
  wire [7:0] x_we, y_we, t_we;
  wire [7:0] nd_we;
  
  wire [wt+nd-1:0] bp_we; // One for each constant
  wire dtb;               // 0: bp_we enable writing to dff, 1: bp_we enable bus buffer
  
  // Buffers for bus inputs
//  assign bus = (e_x) ? x_dout : {n*sx{1'bz}}; // Directly to ai_top
  assign bus = (e_x) ? x_dout : {n{1'bz}};      // Sequential loading
  assign bus = (e_y) ? y_dout : {n{1'bz}};
  assign bus = (e_nd) ? nd_dout : {n{1'bz}};
  
  assign x_din = bus;
//  assign y_din = bus; // Directly from ai_top
  assign nd_din = bus;
  
//  assign nx = x_dout; // Not directly anymore
  assign y_din = ly;
  assign lt = t_dout;
  
  // Modules
  control_unit #(ltot, lr, a, nd, wt) cu(clk, rst, batch, x_addr, y_addr, t_addr, nd_addr, state,
                                        e_x, e_y, e_nd, c_we, in_we, x_we, y_we,
                                        nd_we, t_we, bp_we, dtb);
  ai_top #(sx, sl1, sl2, sl, nd, wt) ai(clk, rst, batch, c_we, bus, nx, ly, yall, wall, ball);
  backprop #(ltot, lr, sx, sl1, sl2, sl, nd, wt) bp(clk, rst, batch, bp_we, dtb, bus, nx, yall, wall, ball, lt, cost);
  
  // Input loading
  // One register for each input forming one shift reg. Data start from LSB.
  shift_register #(sx) sr(clk, rst, in_we, bus, nx);  // Total sx amount of input data
  
  // RAMs
  ram_wrapper ram_node
    (.BRAM_PORTA_addr(nd_addr),
    .BRAM_PORTA_clk(clk),
    .BRAM_PORTA_din(nd_din),
    .BRAM_PORTA_dout(nd_dout),
    .BRAM_PORTA_en(1'b1),
//    .BRAM_PORTA_en(nd_en),
    .BRAM_PORTA_rst(rst),
    .BRAM_PORTA_we(nd_we)//,
//    .BRAM_PORTB_addr(BRAM_PORTB_addr),
//    .BRAM_PORTB_clk(BRAM_PORTB_clk),
//    .BRAM_PORTB_din(BRAM_PORTB_din),
//    .BRAM_PORTB_dout(BRAM_PORTB_dout),
//    .BRAM_PORTB_en(BRAM_PORTB_en),
//    .BRAM_PORTB_rst(BRAM_PORTB_rst),
//    .BRAM_PORTB_we(BRAM_PORTB_we)
  );
  
  sbc_wrapper sbc_w
    (.BRAM_PORTA_addr(x_addr),
    .BRAM_PORTA_clk(clk),
    .BRAM_PORTA_din(x_din),
    .BRAM_PORTA_dout(x_dout),
    .BRAM_PORTA_en(1'b1),
    .BRAM_PORTA_rst(rst),
    .BRAM_PORTA_we(x_we),
    .BRAM_PORTA_1_addr(y_addr),
    .BRAM_PORTA_1_clk(clk),
    .BRAM_PORTA_1_din(y_din),
    .BRAM_PORTA_1_dout(y_dout),
    .BRAM_PORTA_1_en(1'b1),
    .BRAM_PORTA_1_rst(rst),
    .BRAM_PORTA_1_we(y_we),
//    .BRAM_PORTB_addr(BRAM_PORTB_addr),
//    .BRAM_PORTB_clk(BRAM_PORTB_clk),
//    .BRAM_PORTB_din(BRAM_PORTB_din),
//    .BRAM_PORTB_dout(BRAM_PORTB_dout),
//    .BRAM_PORTB_en(BRAM_PORTB_en),
//    .BRAM_PORTB_rst(BRAM_PORTB_rst),
//    .BRAM_PORTB_we(BRAM_PORTB_we),
    .BRAM_PORTB_1_addr(t_addr),
    .BRAM_PORTB_1_clk(clk),
    .BRAM_PORTB_1_din(t_din),
    .BRAM_PORTB_1_dout(t_dout),
    .BRAM_PORTB_1_en(1'b1),
    .BRAM_PORTB_1_rst(rst),
    .BRAM_PORTB_1_we(t_we)
  );
  
endmodule
