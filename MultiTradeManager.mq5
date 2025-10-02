//+------------------------------------------------------------------+
//|                                      MultiTradeManager_v1.2.mq5|
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.30"
#property description "Multi-Trade Manager v1.3 - Flexible Trade Count & Auto Breakeven"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Trade Parameters ==="
input ulong Magic_Number = 12345;          // Magic Number for order identification
input int Number_Of_Trades = 2;            // Number of identical trades to open (1 or more)
input double Fixed_Lot_Size = 0.02;        // Fixed lot size per trade
input bool Half_Risk = false;               // Half Risk mode (Yes/No)
input double Stop_Loss_Price = 0.0;         // Stop Loss price level (0 = no SL)
input double Take_Profit_Price_1 = 0.0;     // Take Profit 1 (primary TP, 0 = no TP)
input double Take_Profit_Price_2 = 0.0;     // Take Profit 2 (secondary TP, 0 = no TP)

input group "=== Display Settings ==="
input int Panel_X_Position = 5;          // Panel X position
input int Panel_Y_Position = 85;          // Panel Y position
input color Panel_Background = clrWhiteSmoke; // Panel background color
input color Panel_Border = clrDarkBlue;   // Panel border color

input group "=== Safety Settings ==="
input int Max_Total_Positions = 100;       // Maximum total positions allowed
input string Trade_Comment = "MultiTrade"; // Comment for trade identification
input datetime Order_Expiration = D'2025.12.31 23:59:59'; // Pending order expiration

//--- Global variables
CTrade trade;
string current_symbol;
double current_bid = 0, current_ask = 0;
int total_positions = 0;
int total_pending_orders = 0;

//--- Cache variables for performance optimization
double last_bid = 0, last_ask = 0;
uint last_price_update = 0;
uint last_count_update = 0;
uint last_gui_update = 0;

//--- Optimized price update threshold (milliseconds)
#define PRICE_UPDATE_THRESHOLD 50
#define COUNT_UPDATE_THRESHOLD 1000
#define GUI_UPDATE_THRESHOLD 500

//--- Pre-calculated symbol info
double symbol_point;
int symbol_digits;
double symbol_tick_value;
double symbol_min_lot;
double symbol_max_lot;
double symbol_lot_step;
int symbol_stops_level;

//--- GUI Objects
string panel_name = "MultiTradePanel";
string btn_buy_name = "btn_buy";
string btn_sell_name = "btn_sell";
string btn_market_name = "btn_market";
string btn_pending_name = "btn_pending";
string btn_execute_name = "btn_execute";
string btn_close_all_name = "btn_close_all";
string btn_cancel_pending_name = "btn_cancel_pending";
string btn_half_risk_name = "btn_half_risk";
string edit_lot_size_name = "edit_lot_size";
string edit_trades_name = "edit_trades";
string edit_open_price_name = "edit_open_price";
string edit_sl_name = "edit_sl";
string edit_tp_name = "edit_tp";
string label_status_name = "label_status";
string label_loss_amount_name = "label_loss_amount";
string label_profit_amounts_name = "label_profit_amounts";
string label_final_lot_name = "label_final_lot";
string label_open_price_name = "label_open_price";

//--- Base panel dimensions (reference for scaling)
#define BASE_PANEL_WIDTH 400
#define BASE_PANEL_HEIGHT 570
#define BASE_BUTTON_WIDTH 85
#define BASE_BUTTON_HEIGHT 25
#define BASE_EDIT_WIDTH 125
#define BASE_EDIT_HEIGHT 25
#define BASE_FONT_SIZE 11
#define BASE_TITLE_FONT_SIZE 12

//--- Responsive layout variables
int chart_width = 0;
int chart_height = 0;
double scale_factor = 1.0;
double dpi_compensation = 1.0;  // DPI scaling compensation factor
int panel_width = BASE_PANEL_WIDTH;
int panel_height = BASE_PANEL_HEIGHT;
int button_width = BASE_BUTTON_WIDTH;
int button_height = BASE_BUTTON_HEIGHT;
int edit_width = BASE_EDIT_WIDTH;
int edit_height = BASE_EDIT_HEIGHT;
int font_size = BASE_FONT_SIZE;
int title_font_size = BASE_TITLE_FONT_SIZE;

//--- Trade direction and execution type
enum TRADE_DIRECTION
{
   TRADE_BUY = 0,
   TRADE_SELL = 1
};

enum EXECUTION_TYPE
{
   EXEC_MARKET = 0,
   EXEC_PENDING = 1
};

TRADE_DIRECTION selected_direction = TRADE_BUY;
EXECUTION_TYPE selected_execution = EXEC_MARKET;
bool half_risk_enabled = false;

//+------------------------------------------------------------------+
//| Trade Group Structure for Breakeven Management                   |
//+------------------------------------------------------------------+
struct TradeGroup
{
   string group_id;              // Unique identifier (timestamp-based)
   datetime created_time;        // When group was created
   double entry_price;           // Average entry price for BE calculation
   bool breakeven_moved;         // Flag if BE already moved
   int total_trades;             // Total trades in this group
   ulong tp1_tickets[];          // Array of tickets with TP1
   ulong tp2_tickets[];          // Array of tickets with TP2
};

//--- Global array to track active trade groups
TradeGroup active_groups[];
int active_group_count = 0;

//--- Pending BE cache for positions without TP
struct PendingBETicket
{
   ulong ticket;
   double entry_price;
   TRADE_DIRECTION direction;
   datetime created_time;
   bool has_tp1;  // Which TP this ticket should use
};

//--- Pending BE cache timeout (24 hours)
#define PENDING_BE_TIMEOUT 86400

PendingBETicket pending_be_cache[];
int pending_be_count = 0;

//+------------------------------------------------------------------+
//| Calculate Responsive Layout Dimensions                           |
//+------------------------------------------------------------------+
void CalculateResponsiveLayout()
{
   chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   // Auto-detect DPI scaling by analyzing chart pixel dimensions
   // Windows DPI scaling affects how MT5 reports chart dimensions:
   // - 100% DPI: Full resolution reported (e.g., 1920x1080)
   // - 125% DPI: ~80% of resolution (e.g., 1536x864 for 1920x1080 screen)
   // - 150% DPI: ~67% of resolution (e.g., 1280x720 for 1920x1080 screen)
   
   double width_ratio = chart_width / 1920.0;
   double height_ratio = chart_height / 1080.0;
   double avg_ratio = (width_ratio + height_ratio) / 2.0;
   
   // Detect DPI compensation needed
   if(avg_ratio <= 0.70)        // 150% DPI or higher (ratio ~0.67)
   {
      dpi_compensation = 1.50;
   }
   else if(avg_ratio <= 0.85)   // 125% DPI (ratio ~0.80)
   {
      dpi_compensation = 1.25;
   }
   else                          // 100% DPI (ratio ~1.0)
   {
      dpi_compensation = 1.0;
   }
   
   // Calculate base scale factor from actual chart dimensions
   double width_scale = chart_width / 1920.0;
   double height_scale = chart_height / 1080.0;
   double base_scale = MathMin(width_scale, height_scale);
   
   // Apply DPI compensation to maintain consistent visual size
   // This ensures panel looks the same size regardless of Windows DPI setting
   scale_factor = base_scale * dpi_compensation;
   
   // Apply minimum and maximum scale limits
   if(scale_factor < 0.6) scale_factor = 0.6;  // Minimum 60% scale
   if(scale_factor > 1.5) scale_factor = 1.5;  // Maximum 150% scale

   // Calculate responsive dimensions
   panel_width = (int)(BASE_PANEL_WIDTH * scale_factor);
   panel_height = (int)(BASE_PANEL_HEIGHT * scale_factor);
   button_width = (int)(BASE_BUTTON_WIDTH * scale_factor);
   button_height = (int)(BASE_BUTTON_HEIGHT * scale_factor);
   edit_width = (int)(BASE_EDIT_WIDTH * scale_factor);
   edit_height = (int)(BASE_EDIT_HEIGHT * scale_factor);
   font_size = (int)(BASE_FONT_SIZE * scale_factor);
   title_font_size = (int)(BASE_TITLE_FONT_SIZE * scale_factor);

   // Ensure minimum readable font sizes
   if(font_size < 9) font_size = 9;
   if(title_font_size < 10) title_font_size = 10;
   
   // Debug info (akan muncul di Expert log)
   static bool first_run = true;
   if(first_run)
   {
      Print("=== DPI Auto-Detection ===");
      Print("Chart dimensions: ", chart_width, "x", chart_height);
      Print("Dimension ratio: ", DoubleToString(avg_ratio, 2));
      Print("DPI compensation: ", DoubleToString(dpi_compensation, 2), "x");
      Print("Final scale factor: ", DoubleToString(scale_factor, 2));
      Print("Panel size: ", panel_width, "x", panel_height);
      first_run = false;
   }
}

//+------------------------------------------------------------------+
//| Scale Position Helper                                            |
//+------------------------------------------------------------------+
int ScalePos(int base_position)
{
   return (int)(base_position * scale_factor);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Get Take Profit price for specific trade                         |
//+------------------------------------------------------------------+
double GetTakeProfitForTrade(int trade_index, int total_trades)
{
   // Handle edge cases first
   bool tp1_set = (Take_Profit_Price_1 > 0);
   bool tp2_set = (Take_Profit_Price_2 > 0);
   
   // If only one TP is set, use it for all trades
   if(tp1_set && !tp2_set)
      return Take_Profit_Price_1;
   if(!tp1_set && tp2_set)
      return Take_Profit_Price_2;
   
   // If neither TP is set, return 0
   if(!tp1_set && !tp2_set)
      return 0.0;
   
   // Both TPs are set - alternate between them
   // For single trade, prefer TP1
   if(total_trades == 1)
      return Take_Profit_Price_1;
   
   // For multiple trades, alternate: even indices use TP1, odd use TP2
   if(trade_index % 2 == 0)
      return Take_Profit_Price_1;  // Even indices (0, 2, 4...) use TP1
   else
      return Take_Profit_Price_2;  // Odd indices (1, 3, 5...) use TP2
}

//+------------------------------------------------------------------+
//| Expert initialization function (Optimized)                       |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Calculate responsive layout dimensions first
   CalculateResponsiveLayout();

   //--- Initialize Half Risk state
   half_risk_enabled = Half_Risk;

   //--- Initialize TP field names (commented as they're not used)
   for(int i = 0; i < 2; i++)
   {
      string edit_tp_field_name = "edit_tp_" + IntegerToString(i + 1);
      string label_tp_field_name = "label_tp_" + IntegerToString(i + 1);
   }

   //--- Get current symbol information and pre-calculate values
   current_symbol = Symbol();

   // Pre-calculate all symbol info for better performance
   symbol_point = SymbolInfoDouble(current_symbol, SYMBOL_POINT);
   symbol_digits = (int)SymbolInfoInteger(current_symbol, SYMBOL_DIGITS);
   symbol_tick_value = SymbolInfoDouble(current_symbol, SYMBOL_TRADE_TICK_VALUE);
   symbol_min_lot = SymbolInfoDouble(current_symbol, SYMBOL_VOLUME_MIN);
   symbol_max_lot = SymbolInfoDouble(current_symbol, SYMBOL_VOLUME_MAX);
   symbol_lot_step = SymbolInfoDouble(current_symbol, SYMBOL_VOLUME_STEP);
   symbol_stops_level = (int)SymbolInfoInteger(current_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   // Validate critical symbol properties
   if(symbol_point <= 0)
   {
      Print("[CRITICAL ERROR] Invalid SYMBOL_POINT: ", symbol_point);
      return INIT_FAILED;
   }
   if(symbol_min_lot <= 0 || symbol_max_lot <= 0 || symbol_min_lot > symbol_max_lot)
   {
      Print("[CRITICAL ERROR] Invalid lot range. Min: ", symbol_min_lot, " Max: ", symbol_max_lot);
      return INIT_FAILED;
   }
   if(symbol_lot_step <= 0)
   {
      Print("[WARNING] Invalid SYMBOL_VOLUME_STEP: ", symbol_lot_step, ". Using 0.01 as default.");
      symbol_lot_step = 0.01;
   }
   if(symbol_tick_value <= 0)
   {
      Print("[WARNING] Invalid SYMBOL_TRADE_TICK_VALUE: ", symbol_tick_value, ". Using 1.0 as fallback.");
      symbol_tick_value = 1.0;
   }

   //--- Initialize current prices with validation
   ResetLastError();
   current_bid = SymbolInfoDouble(current_symbol, SYMBOL_BID);
   current_ask = SymbolInfoDouble(current_symbol, SYMBOL_ASK);
   int error_code = GetLastError();

   // Validate prices
   if(current_bid <= 0 || current_ask <= 0)
   {
      Print("[CRITICAL ERROR] Invalid price data for symbol ", current_symbol);
      Print("Bid: ", current_bid, " | Ask: ", current_ask, " | Error code: ", error_code);
      return INIT_FAILED;
   }
   
   if(error_code != 0)
   {
      Print("[WARNING] SymbolInfo returned error: ", error_code, " but prices valid. Continuing...");
   }

   last_bid = current_bid;
   last_ask = current_ask;
   last_price_update = GetTickCount();
   last_count_update = GetTickCount();
   last_gui_update = GetTickCount();

   //--- Set up trade object with optimized settings
   ResetLastError();
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetMarginMode();
   
   if(!trade.SetTypeFillingBySymbol(current_symbol))
   {
      Print("[WARNING] Failed to set filling type for ", current_symbol, ". Using default.");
      // Try alternative: FILL_OR_KILL or FILL_RETURN
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   //--- Create GUI panel
   ResetLastError();
   if(!CreatePanel())
   {
      int error_code = GetLastError();
      Print("[CRITICAL ERROR] Failed to create GUI panel. Error code: ", error_code);
      Print("Panel position: X=", Panel_X_Position, " Y=", Panel_Y_Position);
      return INIT_FAILED;
   }

   // Initialize displays
   UpdateLossProfitDisplay();
   UpdateFinalLotDisplay();

   Print("MultiTradeManager EA v1.3 initialized successfully for ", current_symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Remove all GUI objects
   DeletePanel();
   Print("MultiTradeManager EA v1.3 deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function (Optimized)                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   uint current_time = GetTickCount();

   //--- Optimized price updates with caching
   if(current_time - last_price_update > PRICE_UPDATE_THRESHOLD)
   {
      double new_bid = SymbolInfoDouble(current_symbol, SYMBOL_BID);
      double new_ask = SymbolInfoDouble(current_symbol, SYMBOL_ASK);

      // Only update if prices changed significantly
      if(new_bid != last_bid || new_ask != last_ask)
      {
         current_bid = new_bid;
         current_ask = new_ask;
         last_bid = new_bid;
         last_ask = new_ask;
         last_price_update = current_time;
      }
   }

   //--- Optimized position/order counting (reduced frequency)
   if(current_time - last_count_update > COUNT_UPDATE_THRESHOLD)
   {
      total_positions = CountMyPositions();
      total_pending_orders = CountMyPendingOrders();
      last_count_update = current_time;
   }

   //--- Optimized GUI updates
   if(current_time - last_gui_update > GUI_UPDATE_THRESHOLD)
   {
      ChartRedraw();
      last_gui_update = current_time;
   }
   
   //--- Periodic cleanup of closed groups
   static uint last_cleanup = 0;
   if(current_time - last_cleanup > 60000) // Every 60 seconds
   {
      RemoveClosedGroups();
      CheckPendingBECache();
      last_cleanup = current_time;
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction Event Handler - Breakeven Trigger              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Handle multiple transaction types
   
   // TYPE 1: Position/Order modification (SL/TP changed)
   if(trans.type == TRADE_TRANSACTION_ORDER_UPDATE)
   {
      // Check if TP was added to a position in pending BE cache
      CheckTPAddedToCache(trans.order);
   }
   
   // TYPE 2: Deal added (position opened or closed)
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // Check if it's our symbol and magic number
      if(trans.symbol != current_symbol)
         return;
      
      // Get deal properties
      ResetLastError();
      if(!HistoryDealSelect(trans.deal))
      {
         int error_code = GetLastError();
         if(error_code != 0)
         {
            Print("[ERROR] Failed to select deal #", trans.deal, ". Error: ", error_code);
         }
         return;
      }
      
      ulong deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      if(deal_magic != Magic_Number)
         return;
      
      string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      if(StringFind(deal_comment, Trade_Comment) < 0)
         return;
      
      ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      ulong position_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      
      // Case A: Position ENTRY (from pending order activation)
      if(deal_entry == DEAL_ENTRY_IN)
      {
         // Check if this position has TP set
         ResetLastError();
         if(PositionSelectByTicket(position_id))
         {
            double tp = PositionGetDouble(POSITION_TP);
            if(tp == 0)
            {
               Print("[INFO] Position ", position_id, " opened without TP. Adding to pending BE cache.");
               // Will be handled by pending BE cache system
            }
         }
      }
      
      // Case B: Position CLOSE (TP or SL hit)
      if(deal_entry == DEAL_ENTRY_OUT)
      {
         // Check if this was a TP1 ticket in any group
         int group_index = FindGroupByTP1Ticket(position_id);
         
         if(group_index >= 0)
         {
            // TP1 hit! Move group to breakeven
            Print("[SUCCESS] TP1 hit detected! Ticket: ", position_id, " | Triggering breakeven for group");
            MoveGroupToBreakeven(group_index);
         }
      }
   }
   
   // Cleanup closed groups periodically
   RemoveClosedGroups();
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   //--- Handle chart resize for responsive layout
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int new_chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int new_chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

      // Only recreate panel if size changed significantly (avoid flicker)
      if(MathAbs(new_chart_width - chart_width) > 10 || MathAbs(new_chart_height - chart_height) > 10)
      {
         CalculateResponsiveLayout();
         DeletePanel();
         CreatePanel();
         UpdateLossProfitDisplay();
         UpdateFinalLotDisplay();
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      //--- Handle button clicks
      if(sparam == btn_buy_name)
      {
         selected_direction = TRADE_BUY;
         UpdateDirectionButtons();
         UpdateOpenPriceField();
         ObjectSetInteger(0, btn_buy_name, OBJPROP_STATE, false);
         UpdateLossProfitDisplay();
      }
      else if(sparam == btn_sell_name)
      {
         selected_direction = TRADE_SELL;
         UpdateDirectionButtons();
         UpdateOpenPriceField();
         ObjectSetInteger(0, btn_sell_name, OBJPROP_STATE, false);
         UpdateLossProfitDisplay();
      }
      else if(sparam == btn_market_name)
      {
         selected_execution = EXEC_MARKET;
         UpdateExecutionButtons();
         UpdateOpenPriceVisibility();
         ObjectSetInteger(0, btn_market_name, OBJPROP_STATE, false);
         UpdateLossProfitDisplay();
      }
      else if(sparam == btn_pending_name)
      {
         selected_execution = EXEC_PENDING;
         UpdateExecutionButtons();
         UpdateOpenPriceVisibility();
         UpdateOpenPriceField();
         ObjectSetInteger(0, btn_pending_name, OBJPROP_STATE, false);
         UpdateLossProfitDisplay();
      }
      else if(sparam == btn_execute_name)
      {
         ExecuteTrades();
         ObjectSetInteger(0, btn_execute_name, OBJPROP_STATE, false);
      }
      else if(sparam == btn_close_all_name)
      {
         CloseAllMyPositions();
         ObjectSetInteger(0, btn_close_all_name, OBJPROP_STATE, false);
      }
      else if(sparam == btn_cancel_pending_name)
      {
         CancelAllMyPendingOrders();
         ObjectSetInteger(0, btn_cancel_pending_name, OBJPROP_STATE, false);
      }
      else if(sparam == btn_half_risk_name)
      {
         half_risk_enabled = !half_risk_enabled;
         UpdateHalfRiskButton();
         ObjectSetInteger(0, btn_half_risk_name, OBJPROP_STATE, false);
         // Instant update for Final Lot display
         UpdateFinalLotDisplay();
         // Update loss/profit calculations (can be slightly delayed)
         UpdateLossProfitDisplay();
      }
   }
   else if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      //--- Handle edit field changes
      if(sparam == edit_trades_name)
      {
         ValidateTradeNumber();
         UpdateTPFieldVisibility();
      }
      else if(sparam == edit_lot_size_name || sparam == edit_sl_name)
      {
         // Instant update for Final Lot when lot size changes
         if(sparam == edit_lot_size_name)
            UpdateFinalLotDisplay();
         UpdateLossProfitDisplay();
      }
      else if(StringFind(sparam, "edit_tp_") >= 0)
      {
         UpdateLossProfitDisplay();
      }
   }
}

//+------------------------------------------------------------------+
//| Create GUI Panel                                                 |
//+------------------------------------------------------------------+
bool CreatePanel()
{
   //--- Main panel rectangle
   if(!ObjectCreate(0, panel_name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      Print("Failed to create main panel");
      return false;
   }
   
   ObjectSetInteger(0, panel_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panel_name, OBJPROP_XDISTANCE, Panel_X_Position);
   ObjectSetInteger(0, panel_name, OBJPROP_YDISTANCE, Panel_Y_Position);
   ObjectSetInteger(0, panel_name, OBJPROP_XSIZE, panel_width);
   ObjectSetInteger(0, panel_name, OBJPROP_YSIZE, panel_height);
   ObjectSetInteger(0, panel_name, OBJPROP_BGCOLOR, Panel_Background);
   ObjectSetInteger(0, panel_name, OBJPROP_BORDER_COLOR, Panel_Border);
   ObjectSetInteger(0, panel_name, OBJPROP_BORDER_TYPE, BORDER_RAISED);
   ObjectSetInteger(0, panel_name, OBJPROP_WIDTH, 2);
   
   //--- Title label
   CreateLabel("label_title", "Multi-Trade Manager v1.3", ScalePos(10), ScalePos(10), clrDarkBlue, title_font_size);

   //--- Current symbol label
   CreateLabel("label_symbol", "Symbol: " + current_symbol, ScalePos(10), ScalePos(35), clrBlack, font_size);

   //--- Current price label (removed for performance optimization)

   //--- Lot size
   CreateLabel("label_lot", "Lot Size:", ScalePos(10), ScalePos(85), clrBlack, font_size);
   CreateEdit(edit_lot_size_name, DoubleToString(Fixed_Lot_Size, 2), ScalePos(145), ScalePos(85), edit_width, edit_height);

   //--- Half Risk toggle
   CreateLabel("label_half_risk", "Half Risk:", ScalePos(10), ScalePos(118), clrBlack, font_size);
   CreateButton(btn_half_risk_name, "NO", ScalePos(145), ScalePos(118), button_width, button_height, clrRed);

   //--- Final Lot (display only)
   CreateLabel(label_final_lot_name, "Final Lot:", ScalePos(10), ScalePos(151), clrBlack, font_size);
   CreateLabel("label_final_lot_value", DoubleToString(Fixed_Lot_Size, 2), ScalePos(145), ScalePos(151), clrBlue, font_size);

   //--- Execution type section
   CreateLabel("label_exec_type", "Execution:", ScalePos(10), ScalePos(184), clrBlack, font_size);
   CreateButton(btn_market_name, "MARKET", ScalePos(145), ScalePos(184), button_width, button_height, clrWhite);
   CreateButton(btn_pending_name, "PENDING", ScalePos(145 + BASE_BUTTON_WIDTH + 5), ScalePos(184), button_width, button_height, clrWhite);

   //--- Direction section
   CreateLabel("label_direction", "Direction:", ScalePos(10), ScalePos(217), clrBlack, font_size);
   CreateButton(btn_buy_name, "BUY", ScalePos(145), ScalePos(217), button_width, button_height, clrWhite);
   CreateButton(btn_sell_name, "SELL", ScalePos(145 + BASE_BUTTON_WIDTH + 5), ScalePos(217), button_width, button_height, clrWhite);

   //--- Number of trades
   CreateLabel("label_trades", "Trades:", ScalePos(10), ScalePos(250), clrBlack, font_size);
   CreateEdit(edit_trades_name, IntegerToString(Number_Of_Trades), ScalePos(145), ScalePos(250), edit_width, edit_height);
   CreateLabel("label_trades_note", "(any number)", ScalePos(145 + BASE_EDIT_WIDTH + 10), ScalePos(250), clrBlue, font_size - 1);

   //--- Open price (for pending orders)
   CreateLabel(label_open_price_name, "Open Price:", ScalePos(10), ScalePos(283), clrBlack, font_size);
   CreateEdit(edit_open_price_name, "0.00000", ScalePos(145), ScalePos(283), (int)(edit_width * 1.18), edit_height);

   //--- Stop Loss
   CreateLabel("label_sl", "Stop Loss Price:", ScalePos(10), ScalePos(316), clrBlack, font_size);
   CreateEdit(edit_sl_name, DoubleToString(Stop_Loss_Price, 5), ScalePos(145), ScalePos(316), (int)(edit_width * 1.18), edit_height);
   CreateLabel("label_sl_amount", "($0.00)", ScalePos(145 + BASE_EDIT_WIDTH + 20), ScalePos(316), clrRed, font_size - 1);
   
   //--- Take Profit fields for TP1 and TP2 only
   CreateLabel("label_tp_header", "Take Profit Levels:", ScalePos(10), ScalePos(349), clrDarkBlue, font_size);
   int tp_y_offset = 372;
   int tp_spacing = 33;

   // Only create 2 TP fields (TP1 and TP2)
   for(int i = 0; i < 2; i++)
   {
      double tp_value = (i == 0) ? Take_Profit_Price_1 : Take_Profit_Price_2;
      string label_text = "TP " + IntegerToString(i + 1) + ":";
      string edit_tp_field_name = "edit_tp_" + IntegerToString(i + 1);
      string label_tp_field_name = "label_tp_" + IntegerToString(i + 1);

      int current_y = tp_y_offset + (i * tp_spacing);

      CreateLabel(label_tp_field_name, label_text, ScalePos(10), ScalePos(current_y), clrBlack, font_size);
      CreateEdit(edit_tp_field_name, DoubleToString(tp_value, 5), ScalePos(50), ScalePos(current_y), (int)(edit_width * 1.12), edit_height);
      CreateLabel("label_tp_amount_" + IntegerToString(i + 1), "($0.00)", ScalePos(50 + BASE_EDIT_WIDTH + 15), ScalePos(current_y), clrGreen, font_size - 1);
   }

   //--- Action buttons (adjusted positions for only 2 TP fields)
   int button_y_start = tp_y_offset + (2 * tp_spacing) + 15;
   int exec_button_width = (int)(BASE_BUTTON_WIDTH * 1.54);
   CreateButton(btn_execute_name, "EXECUTE", ScalePos(20), ScalePos(button_y_start), (int)(button_width * 1.54), button_height, clrBlue);
   CreateButton(btn_close_all_name, "CLOSE ALL", ScalePos(20 + exec_button_width + 10), ScalePos(button_y_start), (int)(button_width * 1.54), button_height, clrRed);
   CreateButton(btn_cancel_pending_name, "CANCEL PENDING ORDER", ScalePos(20), ScalePos(button_y_start + 35), (int)(button_width * 3.23), button_height, clrOrange);

   //--- Status label
   CreateLabel(label_status_name, "Ready", ScalePos(10), ScalePos(button_y_start + 70), clrGreen, font_size);

   //--- Update TP field visibility based on number of trades
   UpdateTPFieldVisibility();
   
   //--- Set initial states
   UpdateExecutionButtons();
   UpdateDirectionButtons();
   UpdateOpenPriceVisibility();
   UpdateHalfRiskButton();
   
   return true;
}

//+------------------------------------------------------------------+
//| Delete GUI Panel                                                 |
//+------------------------------------------------------------------+
void DeletePanel()
{
   ObjectsDeleteAll(0, 0, OBJ_RECTANGLE_LABEL);
   ObjectsDeleteAll(0, 0, OBJ_BUTTON);
   ObjectsDeleteAll(0, 0, OBJ_EDIT);
   ObjectsDeleteAll(0, 0, OBJ_LABEL);
}

//+------------------------------------------------------------------+
//| Create Label with Error Handling                                |
//+------------------------------------------------------------------+
bool CreateLabel(string name, string text, int x, int y, color clr, int label_font_size)
{
   ResetLastError();
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
   {
      int error_code = GetLastError();
      if(error_code != 4200)  // Object already exists
      {
         Print("[ERROR] Failed to create label '", name, "'. Error: ", error_code);
      }
      return false;
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Panel_X_Position + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Panel_Y_Position + y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, label_font_size);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");

   return true;
}

//+------------------------------------------------------------------+
//| Normalize Price to Symbol Tick Size and Digits                   |
//+------------------------------------------------------------------+
double NormalizePrice(double price, string symbol = "")
{
   // Use current symbol if not specified
   if(symbol == "")
      symbol = current_symbol;
   
   // Early validation
   if(price <= 0)
      return 0.0;
   
   // Get symbol properties
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   // Round to nearest tick size if available
   if(tick_size > 0)
   {
      price = MathRound(price / tick_size) * tick_size;
   }
   
   // Normalize to symbol digits
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Normalize Lot Size to Symbol Requirements                         |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lot_size)
{
   if(lot_size <= 0)
      return 0.0;
   
   // Round to lot step
   if(symbol_lot_step > 0)
   {
      lot_size = MathRound(lot_size / symbol_lot_step) * symbol_lot_step;
   }
   
   // Clamp to min/max
   if(lot_size < symbol_min_lot)
      lot_size = symbol_min_lot;
   if(lot_size > symbol_max_lot)
      lot_size = symbol_max_lot;
   
   return lot_size;
}

//+------------------------------------------------------------------+
//| Calculate Adjusted Lot Size with Half Risk (Optimized)           |
//+------------------------------------------------------------------+
double CalculateAdjustedLotSize(double base_lot_size)
{
   // Early validation
   if(base_lot_size <= 0)
      return 0.0;

   double adjusted = half_risk_enabled ? base_lot_size / 2.0 : base_lot_size;
   
   // Normalize to symbol requirements
   return NormalizeLotSize(adjusted);
}

//+------------------------------------------------------------------+
//| Calculate Loss Amount in Currency (Improved)                      |
//+------------------------------------------------------------------+
double CalculateLossAmount(double lot_size, double sl_price, double open_price)
{
   if(sl_price <= 0 || open_price <= 0 || lot_size <= 0)
      return 0.0;

   // Get contract size for accurate calculation
   double contract_size = SymbolInfoDouble(current_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   
   // Calculate price difference in points
   double price_diff_points = MathAbs(open_price - sl_price) / symbol_point;
   
   // Get proper tick value for loss calculation
   double tick_value_loss = SymbolInfoDouble(current_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value_loss == 0)
      tick_value_loss = symbol_tick_value; // Fallback
   
   // Calculate loss amount
   return lot_size * price_diff_points * tick_value_loss;
}

//+------------------------------------------------------------------+
//| Calculate Profit Amount in Currency (Improved)                    |
//+------------------------------------------------------------------+
double CalculateProfitAmount(double lot_size, double tp_price, double open_price)
{
   if(tp_price <= 0 || open_price <= 0 || lot_size <= 0)
      return 0.0;

   // Get contract size for accurate calculation
   double contract_size = SymbolInfoDouble(current_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   
   // Calculate price difference in points
   double price_diff_points = MathAbs(tp_price - open_price) / symbol_point;
   
   // Get proper tick value for profit calculation
   double tick_value_profit = SymbolInfoDouble(current_symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if(tick_value_profit == 0)
      tick_value_profit = symbol_tick_value; // Fallback
   
   // Calculate profit amount
   return lot_size * price_diff_points * tick_value_profit;
}

//+------------------------------------------------------------------+
//| Update Loss and Profit Display (Optimized)                       |
//+------------------------------------------------------------------+
void UpdateLossProfitDisplay()
{
   // Early return if prices not available
   if(current_bid <= 0 || current_ask <= 0)
      return;

   // Get values once for better performance
   string lot_text = ObjectGetString(0, edit_lot_size_name, OBJPROP_TEXT);
   string sl_text = ObjectGetString(0, edit_sl_name, OBJPROP_TEXT);
   string trades_text = ObjectGetString(0, edit_trades_name, OBJPROP_TEXT);

   double base_lot_size = StringToDouble(lot_text);
   double adjusted_lot_size = CalculateAdjustedLotSize(base_lot_size);
   double sl_price = StringToDouble(sl_text);

   // Update final lot display
   ObjectSetString(0, "label_final_lot_value", OBJPROP_TEXT, DoubleToString(adjusted_lot_size, 2));

   // Calculate and update SL amount
   // Use same reference price logic as TP (Open Price for pending, current for market)
   string sl_amount_text = "($0.00)";
   if(sl_price > 0 && (selected_direction == TRADE_BUY || selected_direction == TRADE_SELL))
   {
      double sl_reference_price;
      
      if(selected_execution == EXEC_PENDING)
      {
         // For pending orders, use the Open Price field
         string open_price_text = ObjectGetString(0, edit_open_price_name, OBJPROP_TEXT);
         sl_reference_price = StringToDouble(open_price_text);
         
         // Fallback to current price if open price is invalid
         if(sl_reference_price <= 0)
         {
            sl_reference_price = (selected_direction == TRADE_BUY) ? current_ask : current_bid;
         }
      }
      else
      {
         // For market orders, use current market price
         sl_reference_price = (selected_direction == TRADE_BUY) ? current_ask : current_bid;
      }
      
      double loss_amount = CalculateLossAmount(adjusted_lot_size, sl_price, sl_reference_price);
      sl_amount_text = "($" + DoubleToString(loss_amount, 2) + ")";
   }
   ObjectSetString(0, "label_sl_amount", OBJPROP_TEXT, sl_amount_text);

   // Calculate and update TP amounts for TP1 and TP2 only
   // Use Open Price field if in PENDING mode, otherwise use current market price
   double reference_price;
   
   if(selected_execution == EXEC_PENDING)
   {
      // For pending orders, use the Open Price field
      string open_price_text = ObjectGetString(0, edit_open_price_name, OBJPROP_TEXT);
      reference_price = StringToDouble(open_price_text);
      
      // Fallback to current price if open price is invalid
      if(reference_price <= 0)
      {
         reference_price = (selected_direction == TRADE_BUY) ? current_ask : current_bid;
      }
   }
   else
   {
      // For market orders, use current market price
      reference_price = (selected_direction == TRADE_BUY) ? current_ask : current_bid;
   }

   // Update both TP1 and TP2 amount displays
   for(int i = 0; i < 2; i++)
   {
      string tp_amount_label = "label_tp_amount_" + IntegerToString(i + 1);
      string tp_amount_text = "($0.00)";

      string edit_tp_field_name = "edit_tp_" + IntegerToString(i + 1);
      string tp_text = ObjectGetString(0, edit_tp_field_name, OBJPROP_TEXT);
      // FIXED: Normalize TP price for consistency with execution
      double tp_price = NormalizePrice(StringToDouble(tp_text));

      if(tp_price > 0)
      {
         double profit_amount = CalculateProfitAmount(adjusted_lot_size, tp_price, reference_price);
         tp_amount_text = "($" + DoubleToString(profit_amount, 2) + ")";
      }

      ObjectSetString(0, tp_amount_label, OBJPROP_TEXT, tp_amount_text);
   }
}

//+------------------------------------------------------------------+
//| Update Final Lot Display (Instant) (Optimized)                   |
//+------------------------------------------------------------------+
void UpdateFinalLotDisplay()
{
   string lot_text = ObjectGetString(0, edit_lot_size_name, OBJPROP_TEXT);
   double base_lot_size = StringToDouble(lot_text);
   double adjusted_lot_size = CalculateAdjustedLotSize(base_lot_size);

   // Only update if lot size is valid
   if(adjusted_lot_size > 0)
   {
      ObjectSetString(0, "label_final_lot_value", OBJPROP_TEXT, DoubleToString(adjusted_lot_size, 2));
   }
   else
   {
      ObjectSetString(0, "label_final_lot_value", OBJPROP_TEXT, "0.00");
   }
}

//+------------------------------------------------------------------+
//| Update Half Risk Button State (Optimized)                        |
//+------------------------------------------------------------------+
void UpdateHalfRiskButton()
{
   if(half_risk_enabled)
   {
      ObjectSetInteger(0, btn_half_risk_name, OBJPROP_BGCOLOR, clrLimeGreen);
      ObjectSetInteger(0, btn_half_risk_name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, btn_half_risk_name, OBJPROP_BORDER_COLOR, clrGreen);
      ObjectSetString(0, btn_half_risk_name, OBJPROP_TEXT, "YES");
   }
   else
   {
      ObjectSetInteger(0, btn_half_risk_name, OBJPROP_BGCOLOR, clrCrimson);
      ObjectSetInteger(0, btn_half_risk_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btn_half_risk_name, OBJPROP_BORDER_COLOR, clrRed);
      ObjectSetString(0, btn_half_risk_name, OBJPROP_TEXT, "NO");
   }

   // Trigger immediate lot display update
   UpdateFinalLotDisplay();
}

//+------------------------------------------------------------------+
//| Update TP Field Visibility (Optimized)                          |
//+------------------------------------------------------------------+
void UpdateTPFieldVisibility()
{
   // Always show both TP1 and TP2 fields since they're used for all trades
   // This function is no longer needed but kept for compatibility
   for(int i = 0; i < 2; i++)
   {
      string edit_tp_field_name = "edit_tp_" + IntegerToString(i + 1);
      string label_tp_field_name = "label_tp_" + IntegerToString(i + 1);

      // Always show both TP fields
      ObjectSetInteger(0, label_tp_field_name, OBJPROP_TIMEFRAMES, -1);
      ObjectSetInteger(0, edit_tp_field_name, OBJPROP_TIMEFRAMES, -1);
   }
}

//+------------------------------------------------------------------+
//| Create Button with Error Handling                               |
//+------------------------------------------------------------------+
bool CreateButton(string name, string text, int x, int y, int width, int height, color clr)
{
   ResetLastError();
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
   {
      int error_code = GetLastError();
      if(error_code != 4200)  // Object already exists
      {
         Print("[ERROR] Failed to create button '", name, "'. Error: ", error_code);
      }
      return false;
   }
      
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Panel_X_Position + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Panel_Y_Position + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   
   return true;
}

//+------------------------------------------------------------------+
//| Create Edit Box with Error Handling                             |
//+------------------------------------------------------------------+
bool CreateEdit(string name, string text, int x, int y, int width, int height)
{
   ResetLastError();
   if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0))
   {
      int error_code = GetLastError();
      if(error_code != 4200)  // Object already exists
      {
         Print("[ERROR] Failed to create edit '", name, "'. Error: ", error_code);
      }
      return false;
   }
      
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Panel_X_Position + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Panel_Y_Position + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
   
   return true;
}

//+------------------------------------------------------------------+
//| Update Execution Type Buttons                                   |
//+------------------------------------------------------------------+
void UpdateExecutionButtons()
{
   if(selected_execution == EXEC_MARKET)
   {
      ObjectSetInteger(0, btn_market_name, OBJPROP_BGCOLOR, clrDodgerBlue);
      ObjectSetInteger(0, btn_market_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btn_market_name, OBJPROP_BORDER_COLOR, clrBlue);

      ObjectSetInteger(0, btn_pending_name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, btn_pending_name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, btn_pending_name, OBJPROP_BORDER_COLOR, clrGray);
   }
   else
   {
      ObjectSetInteger(0, btn_market_name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, btn_market_name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, btn_market_name, OBJPROP_BORDER_COLOR, clrGray);

      ObjectSetInteger(0, btn_pending_name, OBJPROP_BGCOLOR, clrOrange);
      ObjectSetInteger(0, btn_pending_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btn_pending_name, OBJPROP_BORDER_COLOR, clrDarkOrange);
   }
}

//+------------------------------------------------------------------+
//| Update Direction Buttons                                         |
//+------------------------------------------------------------------+
void UpdateDirectionButtons()
{
   if(selected_direction == TRADE_BUY)
   {
      ObjectSetInteger(0, btn_buy_name, OBJPROP_BGCOLOR, clrLimeGreen);
      ObjectSetInteger(0, btn_buy_name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, btn_buy_name, OBJPROP_BORDER_COLOR, clrGreen);

      ObjectSetInteger(0, btn_sell_name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, btn_sell_name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, btn_sell_name, OBJPROP_BORDER_COLOR, clrGray);
   }
   else
   {
      ObjectSetInteger(0, btn_buy_name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, btn_buy_name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, btn_buy_name, OBJPROP_BORDER_COLOR, clrGray);

      ObjectSetInteger(0, btn_sell_name, OBJPROP_BGCOLOR, clrCrimson);
      ObjectSetInteger(0, btn_sell_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btn_sell_name, OBJPROP_BORDER_COLOR, clrRed);
   }
}

//+------------------------------------------------------------------+
//| Update Open Price Field Visibility                              |
//+------------------------------------------------------------------+
void UpdateOpenPriceVisibility()
{
   if(selected_execution == EXEC_MARKET)
   {
      //--- Hide open price field for market execution
      ObjectSetInteger(0, label_open_price_name, OBJPROP_COLOR, clrLightGray);
      ObjectSetInteger(0, edit_open_price_name, OBJPROP_BGCOLOR, clrLightGray);
      ObjectSetInteger(0, edit_open_price_name, OBJPROP_READONLY, true);
      ObjectSetString(0, edit_open_price_name, OBJPROP_TEXT, "N/A (Market)");
   }
   else
   {
      //--- Show open price field for pending orders
      ObjectSetInteger(0, label_open_price_name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, edit_open_price_name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, edit_open_price_name, OBJPROP_READONLY, false);
      UpdateOpenPriceField();
   }
}

//+------------------------------------------------------------------+
//| Update Open Price Field with suggested price (Optimized)        |
//+------------------------------------------------------------------+
void UpdateOpenPriceField()
{
   if(selected_execution == EXEC_PENDING)
   {
      // Use pre-calculated symbol_point for better performance
      double suggested_price = 0;

      if(selected_direction == TRADE_BUY)
      {
         //--- For BUY pending: suggest price below current Ask (Buy Limit) or above (Buy Stop)
         suggested_price = current_ask - (50 * symbol_point);
      }
      else
      {
         //--- For SELL pending: suggest price above current Bid (Sell Limit) or below (Sell Stop)
         suggested_price = current_bid + (50 * symbol_point);
      }

      ObjectSetString(0, edit_open_price_name, OBJPROP_TEXT, DoubleToString(suggested_price, symbol_digits));
   }
}


//+------------------------------------------------------------------+
//| Execute Multiple Trades (Optimized)                              |
//+------------------------------------------------------------------+
void ExecuteTrades()
{
   //--- Get parameters from GUI (cached for better performance)
   string lot_text = ObjectGetString(0, edit_lot_size_name, OBJPROP_TEXT);
   string trades_text = ObjectGetString(0, edit_trades_name, OBJPROP_TEXT);
   string open_price_text = ObjectGetString(0, edit_open_price_name, OBJPROP_TEXT);
   string sl_text = ObjectGetString(0, edit_sl_name, OBJPROP_TEXT);

   double base_lot_size = StringToDouble(lot_text);
   double adjusted_lot_size = CalculateAdjustedLotSize(base_lot_size);
   int num_trades = (int)StringToInteger(trades_text);
   
   // Normalize all prices to symbol tick size and digits
   double open_price = NormalizePrice(StringToDouble(open_price_text));
   double sl_price = NormalizePrice(StringToDouble(sl_text));

   //--- Early validation for basic parameters
   if(base_lot_size <= 0)
   {
      UpdateStatus("Invalid lot size", clrRed);
      return;
   }

   //--- Use pre-calculated min/max lot sizes
   if(adjusted_lot_size < symbol_min_lot || adjusted_lot_size > symbol_max_lot)
   {
      UpdateStatus("Lot size out of range", clrRed);
      return;
   }

   //--- Validate number of trades
   if(num_trades <= 0 || num_trades > Max_Total_Positions)
   {
      UpdateStatus("Invalid trade count", clrRed);
      return;
   }

   //--- Check position limits
   int current_total = total_positions + total_pending_orders;
   if(current_total + num_trades > Max_Total_Positions)
   {
      UpdateStatus("Max positions exceeded", clrRed);
      return;
   }
   
   //--- Check broker limits
   int account_limit = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   if(account_limit > 0 && current_total + num_trades > account_limit)
   {
      UpdateStatus("Broker order limit exceeded", clrRed);
      Print("[ERROR] Broker limit: ", account_limit, " | Requested: ", current_total + num_trades);
      return;
   }
   
   //--- Check margin requirements for market orders
   if(selected_execution == EXEC_MARKET)
   {
      double total_margin_required = 0;
      ENUM_ORDER_TYPE check_type = (selected_direction == TRADE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double check_price = (selected_direction == TRADE_BUY) ? current_ask : current_bid;
      
      ResetLastError();
      if(!OrderCalcMargin(check_type, current_symbol, adjusted_lot_size * num_trades, check_price, total_margin_required))
      {
         int error_code = GetLastError();
         UpdateStatus("Margin calculation failed", clrRed);
         Print("[ERROR] OrderCalcMargin failed. Error: ", error_code);
         return;
      }
      
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(total_margin_required > free_margin)
      {
         UpdateStatus("Insufficient margin", clrRed);
         Print("[ERROR] Required: $", total_margin_required, " | Available: $", free_margin);
         return;
      }
      
      // FIXED: Validate stops level for market orders
      double min_distance = symbol_stops_level * symbol_point;
      if(min_distance > 0)
      {
         if(sl_price > 0)
         {
            double sl_distance = MathAbs(check_price - sl_price);
            if(sl_distance < min_distance)
            {
               UpdateStatus("SL too close to market", clrRed);
               Print("[ERROR] SL distance: ", sl_distance, " | Min required: ", min_distance);
               return;
            }
         }
      }
   }

   //--- Get dynamic TP values from GUI (only TP1 and TP2) with normalization
   double tp_prices[2];
   tp_prices[0] = NormalizePrice(StringToDouble(ObjectGetString(0, "edit_tp_1", OBJPROP_TEXT)));
   tp_prices[1] = NormalizePrice(StringToDouble(ObjectGetString(0, "edit_tp_2", OBJPROP_TEXT)));

   //--- Validate price levels for all trades (using only TP1 and TP2)
   for(int i = 0; i < num_trades; i++)
   {
      // Alternate between TP1 and TP2
      int tp_index = (i % 2 == 0) ? 0 : 1;  // 0 for TP1, 1 for TP2
      double tp_for_trade = tp_prices[tp_index];

      // Fallback to other TP if one is not set
      if(tp_for_trade == 0)
      {
         tp_index = (tp_index == 0) ? 1 : 0;  // Try the other TP
         tp_for_trade = tp_prices[tp_index];
      }

      if(!ValidatePriceLevels(open_price, sl_price, tp_for_trade, selected_direction, selected_execution))
      {
         UpdateStatus("Invalid price levels", clrRed);
         return;
      }
   }

   //--- Execute trades based on execution type
   if(selected_execution == EXEC_MARKET)
   {
      ExecuteMarketTrades(num_trades, adjusted_lot_size, sl_price, tp_prices);
   }
   else
   {
      ExecutePendingTrades(num_trades, adjusted_lot_size, open_price, sl_price, tp_prices);
   }
}

//+------------------------------------------------------------------+
//| Execute Market Trades (Optimized)                                |
//+------------------------------------------------------------------+
void ExecuteMarketTrades(int num_trades, double lot_size, double sl_price, double &tp_prices[])
{
   UpdateStatus("Executing market trades...", clrBlue);

   int successful_trades = 0;
   string risk_type = half_risk_enabled ? " (Half Risk)" : " (Normal Risk)";
   string direction_str = selected_direction == TRADE_BUY ? "BUY" : "SELL";

   // Pre-build comment prefix for better performance
   string comment_prefix = Trade_Comment + " Market #";
   
   // Arrays to track tickets for group creation
   ulong tp1_tickets[];
   ulong tp2_tickets[];
   ArrayResize(tp1_tickets, num_trades);
   ArrayResize(tp2_tickets, num_trades);
   int tp1_count = 0;
   int tp2_count = 0;
   double total_entry = 0;
   int no_tp_count = 0;  // Track positions without TP

   for(int i = 0; i < num_trades; i++)
   {
      // Get TP for this trade using improved logic
      double tp_for_trade = GetTakeProfitForTrade(i, num_trades);
      
      // Determine which TP index this corresponds to for tracking
      int tp_index = 0;  // Default to TP1
      if(tp_for_trade > 0)
      {
         if(tp_for_trade == Take_Profit_Price_2)
            tp_index = 1;
         else
            tp_index = 0;
      }

      bool result = false;
      string comment = comment_prefix + IntegerToString(i + 1);
      string tp_used = (tp_index == 0) ? "TP1" : "TP2";

      if(selected_direction == TRADE_BUY)
      {
         result = trade.Buy(lot_size, current_symbol, 0, sl_price, tp_for_trade, comment);
      }
      else
      {
         result = trade.Sell(lot_size, current_symbol, 0, sl_price, tp_for_trade, comment);
      }

      if(result)
      {
         successful_trades++;
         
         // Retrieve position ticket in a way that works for hedging and netting accounts
         ulong ticket = 0;

         ulong deal_id = trade.ResultDeal();
         if(deal_id > 0 && HistoryDealSelect(deal_id))
            ticket = (ulong)HistoryDealGetInteger(deal_id, DEAL_POSITION_ID);

         if(ticket == 0)
            ticket = trade.ResultOrder();

         if(ticket == 0)
         {
            Print("[WARNING] Unable to determine position ticket for trade ", i + 1,
                  ". Order: ", trade.ResultOrder(), " Deal: ", trade.ResultDeal());
            continue;
         }

         // Verify position was opened and get actual entry price
         ResetLastError();
         if(PositionSelectByTicket(ticket))
         {
            double actual_entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double actual_tp = PositionGetDouble(POSITION_TP);
            int pos_error = GetLastError();
            
            // FIXED: Validate position data
            if(actual_entry <= 0 || pos_error != 0)
            {
               Print("[ERROR] Invalid position data for ticket ", ticket, ". Entry=", actual_entry, " Error=", pos_error);
               continue;
            }
            
            total_entry += actual_entry;
            
            // Check if TP was actually set
            if(actual_tp > 0)
            {
               // Store ticket in appropriate array based on TP
               if(tp_index == 0)
               {
                  tp1_tickets[tp1_count] = ticket;
                  tp1_count++;
               }
               else
               {
                  tp2_tickets[tp2_count] = ticket;
                  tp2_count++;
               }
            }
            else
            {
               // No TP set - add to pending BE cache
               AddToPendingBECache(ticket, actual_entry, selected_direction, (tp_index == 0));
               no_tp_count++;
               Print("[INFO] Trade ", i + 1, " opened without TP. Ticket: ", ticket, " added to pending BE cache.");
            }
         }
         else
         {
            int error_code = GetLastError();
            Print("[WARNING] Could not select position for ticket: ", ticket, " | Error: ", error_code);
         }
         
         Print("Market trade ", i + 1, " executed successfully. Ticket: ", ticket,
               " TP: ", tp_for_trade, " Lots: ", lot_size, risk_type);
      }
      else
      {
         // Optimized error reporting
         Print("Market trade ", i + 1, " failed. Error: ", trade.ResultRetcodeDescription(),
               " Code: ", trade.ResultRetcode(), " Direction: ", direction_str,
               " Lots: ", lot_size, risk_type, " Ask: ", current_ask, " Bid: ", current_bid,
               " SL: ", sl_price, " TP: ", tp_for_trade);
      }

      //--- No delay between trades for instant response
   }

   //--- Create trade group if any trades successful with TP (even partial)
   // FIXED: Create group even if only TP1 or TP2 exists (partial execution support)
   if(successful_trades > 0 && (tp1_count > 0 || tp2_count > 0))
   {
      // Use average entry price for BE calculation
      double avg_entry = total_entry / successful_trades;
      
      // Resize arrays to actual counts
      ArrayResize(tp1_tickets, tp1_count);
      ArrayResize(tp2_tickets, tp2_count);
      
      CreateTradeGroup(avg_entry, tp1_count, tp2_count, tp1_tickets, tp2_tickets);
      
      if(tp1_count > 0 && tp2_count > 0)
      {
         Print("[SUCCESS] Trade group created with ", tp1_count, " TP1 and ", tp2_count, " TP2 positions.");
      }
      else if(tp1_count > 0)
      {
         if(tp1_count == 1 && num_trades == 1)
            Print("[INFO] Single trade opened with TP. Breakeven will activate when TP hits.");
         else
            Print("[WARNING] Partial group created with only ", tp1_count, " TP1 position(s). BE will activate when TP1 hits.");
      }
      else
      {
         if(tp2_count == 1 && num_trades == 1)
            Print("[INFO] Single trade opened with TP. Breakeven will activate when TP hits.");
         else
            Print("[WARNING] Partial group created with only ", tp2_count, " TP2 position(s). No TP1 to trigger BE.");
      }
   }
   else if(successful_trades > 0 && tp1_count == 0 && tp2_count == 0 && no_tp_count == 0)
   {
      Print("[WARNING] No positions with TP. BE tracking disabled.");
   }
   
   // Inform user about pending BE positions
   if(no_tp_count > 0)
   {
      Print("[INFO] ", no_tp_count, " position(s) without TP. Breakeven will activate when TP is added.");
   }
   
   //--- Update status
   string status_msg;
   color status_color;

   if(successful_trades == num_trades)
   {
      status_msg = IntegerToString(successful_trades) + " trades opened";
      status_color = clrGreen;
   }
   else if(successful_trades > 0)
   {
      status_msg = IntegerToString(successful_trades) + "/" + IntegerToString(num_trades) + " trades opened";
      status_color = clrOrange;
   }
   else
   {
      status_msg = "All trades failed";
      status_color = clrRed;
   }

   UpdateStatus(status_msg, status_color);
}

//+------------------------------------------------------------------+
//| Execute Pending Trades (Optimized)                               |
//+------------------------------------------------------------------+
void ExecutePendingTrades(int num_trades, double lot_size, double open_price, double sl_price, double &tp_prices[])
{
   UpdateStatus("Placing orders...", clrBlue);

   int successful_orders = 0;
   ENUM_ORDER_TYPE order_type = GetPendingOrderType(open_price, selected_direction);
   string order_type_str = EnumToString(order_type);
   string risk_type = half_risk_enabled ? " (Half Risk)" : " (Normal Risk)";

   // Pre-build comment prefix for better performance
   string comment_prefix = Trade_Comment + " Pending #";
   
   // Note: Pending orders will be tracked when they convert to positions
   // via OnTradeTransaction event handler

   for(int i = 0; i < num_trades; i++)
   {
      // Get TP for this trade using improved logic
      double tp_for_trade = GetTakeProfitForTrade(i, num_trades);
      
      // Determine which TP index this corresponds to for tracking
      int tp_index = 0;  // Default to TP1
      if(tp_for_trade > 0)
      {
         if(tp_for_trade == Take_Profit_Price_2)
            tp_index = 1;
         else
            tp_index = 0;
      }

      //--- Place pending order based on type
      string comment = comment_prefix + IntegerToString(i + 1);
      string tp_used = (tp_index == 0) ? "TP1" : "TP2";
      bool result = trade.OrderOpen(current_symbol, order_type, lot_size, 0, open_price, sl_price, tp_for_trade,
                                   ORDER_TIME_SPECIFIED, Order_Expiration, comment);

      if(result)
      {
         successful_orders++;
         Print("Pending order ", i + 1, " placed successfully. Ticket: ", trade.ResultOrder(),
               " Type: ", order_type_str, " TP: ", tp_for_trade, " Lots: ", lot_size, risk_type, " Using: ", tp_used);
      }
      else
      {
         Print("Pending order ", i + 1, " failed. Type: ", order_type_str, " Error: ",
               trade.ResultRetcodeDescription(), " Code: ", trade.ResultRetcode());
      }

      //--- No delay between orders for instant response
   }

   //--- Update status with improved feedback
   string status_msg;
   color status_color;

   if(successful_orders == num_trades)
   {
      status_msg = IntegerToString(successful_orders) + " orders placed";
      status_color = clrGreen;
   }
   else if(successful_orders > 0)
   {
      status_msg = IntegerToString(successful_orders) + "/" + IntegerToString(num_trades) + " orders placed";
      status_color = clrOrange;
   }
   else
   {
      status_msg = "All orders failed";
      status_color = clrRed;
   }

   UpdateStatus(status_msg, status_color);
}

//+------------------------------------------------------------------+
//| Get Pending Order Type (Optimized)                               |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE GetPendingOrderType(double open_price, TRADE_DIRECTION direction)
{
   // Early validation for safety
   if(open_price <= 0)
      return WRONG_VALUE;

   if(direction == TRADE_BUY)
   {
      return (open_price > current_ask) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT;
   }
   else // TRADE_SELL
   {
      return (open_price < current_bid) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT;
   }
}

//+------------------------------------------------------------------+
//| Validate Trade Number                                             |
//+------------------------------------------------------------------+
void ValidateTradeNumber()
{
   string trades_text = ObjectGetString(0, edit_trades_name, OBJPROP_TEXT);
   int num_trades = (int)StringToInteger(trades_text);
   if(num_trades <= 0) num_trades = Number_Of_Trades;

   // Validate trade count is positive
   if(num_trades <= 0)
   {
      UpdateStatus("Trade count must be positive", clrRed);
   }
   else
   {
      UpdateStatus("Ready", clrGreen);
   }
}

//+------------------------------------------------------------------+
//| Validate Price Levels (Optimized)                               |
//+------------------------------------------------------------------+
bool ValidatePriceLevels(double open_price, double sl, double tp, TRADE_DIRECTION direction, EXECUTION_TYPE exec_type)
{
   // Early validation for invalid prices
   if(exec_type == EXEC_PENDING && open_price <= 0)
   {
      Print("Invalid open price for pending order: ", open_price);
      return false;
   }

   double reference_price;

   if(exec_type == EXEC_MARKET)
   {
      reference_price = (direction == TRADE_BUY) ? current_ask : current_bid;
   }
   else
   {
      reference_price = open_price;
   }

   // Early return if reference price is invalid
   if(reference_price <= 0)
      return false;

   //--- Validate Stop Loss
   if(sl > 0)
   {
      if(direction == TRADE_BUY && sl >= reference_price)
      {
         Print("Invalid SL for BUY: SL (", sl, ") must be below reference price (", reference_price, ")");
         return false;
      }
      if(direction == TRADE_SELL && sl <= reference_price)
      {
         Print("Invalid SL for SELL: SL (", sl, ") must be above reference price (", reference_price, ")");
         return false;
      }
   }

   //--- Validate Take Profit
   if(tp > 0)
   {
      if(direction == TRADE_BUY && tp <= reference_price)
      {
         Print("Invalid TP for BUY: TP (", tp, ") must be above reference price (", reference_price, ")");
         return false;
      }
      if(direction == TRADE_SELL && tp >= reference_price)
      {
         Print("Invalid TP for SELL: TP (", tp, ") must be below reference price (", reference_price, ")");
         return false;
      }
   }

   //--- Additional validation for pending orders (optimized)
   if(exec_type == EXEC_PENDING)
   {
      // Use pre-calculated stops level
      double min_distance = symbol_stops_level * symbol_point;

      // Only validate if stops level is set
      if(min_distance > 0)
      {
         if(direction == TRADE_BUY)
         {
            if(open_price > current_ask && (open_price - current_ask) < min_distance)
            {
               Print("Buy Stop too close to current price. Minimum distance: ", min_distance);
               return false;
            }
            if(open_price < current_ask && (current_ask - open_price) < min_distance)
            {
               Print("Buy Limit too close to current price. Minimum distance: ", min_distance);
               return false;
            }
         }
         else
         {
            if(open_price < current_bid && (current_bid - open_price) < min_distance)
            {
               Print("Sell Stop too close to current price. Minimum distance: ", min_distance);
               return false;
            }
            if(open_price > current_bid && (open_price - current_bid) < min_distance)
            {
               Print("Sell Limit too close to current price. Minimum distance: ", min_distance);
               return false;
            }
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Count My Positions (Optimized)                                  |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   int total = PositionsTotal();

   // Early return if no positions
   if(total == 0)
      return 0;

   // Optimized loop with early exit
   for(int i = 0; i < total; i++)
   {
      // Fast symbol check first
      if(PositionGetSymbol(i) == current_symbol)
      {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         // Fast magic number check before string operations
         if(magic == Magic_Number)
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, Trade_Comment) >= 0)
            {
               count++;
            }
         }
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Count My Pending Orders (Optimized)                             |
//+------------------------------------------------------------------+
int CountMyPendingOrders()
{
   int count = 0;
   int total = OrdersTotal();

   // Early return if no orders
   if(total == 0)
      return 0;

   // Optimized loop with early exit
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         // Fast symbol check first
         if(OrderGetString(ORDER_SYMBOL) == current_symbol)
         {
            ulong magic = OrderGetInteger(ORDER_MAGIC);
            // Fast magic number check before string operations
            if(magic == Magic_Number)
            {
               string comment = OrderGetString(ORDER_COMMENT);
               if(StringFind(comment, Trade_Comment) >= 0)
               {
                  count++;
               }
            }
         }
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Close All My Positions                                           |
//+------------------------------------------------------------------+
void CloseAllMyPositions()
{
   UpdateStatus("Closing positions...", clrBlue);

   int closed_count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == current_symbol)
      {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         string comment = PositionGetString(POSITION_COMMENT);
         if(magic == Magic_Number && StringFind(comment, Trade_Comment) >= 0)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            if(trade.PositionClose(ticket))
            {
               closed_count++;
               Print("Position closed successfully. Ticket: ", ticket);
            }
            else
            {
               uint retcode = trade.ResultRetcode();
               Print("[ERROR] Failed to close position. Ticket: ", ticket);
               Print("  Retcode: ", retcode, " - ", trade.ResultRetcodeDescription());
               Print("  Last error: ", GetLastError());
            }
         }
      }
   }

   if(closed_count > 0)
   {
      UpdateStatus("Closed " + IntegerToString(closed_count) + " positions", clrGreen);
   }
   else
   {
      UpdateStatus("No positions found", clrOrange);
   }
}

//+------------------------------------------------------------------+
//| Cancel All My Pending Orders                                     |
//+------------------------------------------------------------------+
void CancelAllMyPendingOrders()
{
   UpdateStatus("Canceling orders...", clrBlue);

   int canceled_count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderGetTicket(i))
      {
         if(OrderGetString(ORDER_SYMBOL) == current_symbol)
         {
            ulong magic = OrderGetInteger(ORDER_MAGIC);
            string comment = OrderGetString(ORDER_COMMENT);
            if(magic == Magic_Number && StringFind(comment, Trade_Comment) >= 0)
            {
               ulong ticket = OrderGetInteger(ORDER_TICKET);
               if(trade.OrderDelete(ticket))
               {
                  canceled_count++;
                  Print("Pending order canceled successfully. Ticket: ", ticket);
               }
               else
               {
                  uint retcode = trade.ResultRetcode();
                  Print("[ERROR] Failed to cancel pending order. Ticket: ", ticket);
                  Print("  Retcode: ", retcode, " - ", trade.ResultRetcodeDescription());
                  Print("  Last error: ", GetLastError());
               }
            }
         }
      }
   }

   if(canceled_count > 0)
   {
      UpdateStatus("Canceled " + IntegerToString(canceled_count) + " orders", clrGreen);
   }
   else
   {
      UpdateStatus("No orders found", clrOrange);
   }
}

//+------------------------------------------------------------------+
//| Update Status Label (Optimized)                                  |
//+------------------------------------------------------------------+
void UpdateStatus(string status, color clr)
{
   //--- Optimized status update with minimal object calls
   ObjectSetString(0, label_status_name, OBJPROP_TEXT, status);
   ObjectSetInteger(0, label_status_name, OBJPROP_COLOR, clr);

   //--- Force immediate GUI update for important status changes
   static uint last_status_update = 0;
   uint now = GetTickCount();

   if(now - last_status_update > 100) // Update every ~100ms
   {
      ChartRedraw();
      last_status_update = now;
   }
}

//+------------------------------------------------------------------+
//| Create New Trade Group                                           |
//+------------------------------------------------------------------+
string CreateTradeGroup(double entry, int num_tp1, int num_tp2, ulong &tp1_tickets[], ulong &tp2_tickets[])
{
   // Generate unique group ID based on timestamp
   string group_id = "MTM_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   group_id = StringFormat("%s_%d", group_id, GetTickCount());
   
   // Resize array to accommodate new group
   ResetLastError();
   int resize_result = ArrayResize(active_groups, active_group_count + 1);
   
   if(resize_result < 0)
   {
      int error_code = GetLastError();
      Print("[ERROR] Failed to resize active_groups array. Error: ", error_code);
      return "ERROR";
   }
   
   // Initialize new group
   active_groups[active_group_count].group_id = group_id;
   active_groups[active_group_count].created_time = TimeCurrent();
   active_groups[active_group_count].entry_price = entry;
   active_groups[active_group_count].breakeven_moved = false;
   active_groups[active_group_count].total_trades = num_tp1 + num_tp2;
   
   // Copy ticket arrays (FIXED: Only resize if count > 0)
   if(num_tp1 > 0)
   {
      ArrayResize(active_groups[active_group_count].tp1_tickets, num_tp1);
      for(int i = 0; i < num_tp1; i++)
         active_groups[active_group_count].tp1_tickets[i] = tp1_tickets[i];
   }
   else
   {
      ArrayResize(active_groups[active_group_count].tp1_tickets, 0);
   }
   
   if(num_tp2 > 0)
   {
      ArrayResize(active_groups[active_group_count].tp2_tickets, num_tp2);
      for(int i = 0; i < num_tp2; i++)
         active_groups[active_group_count].tp2_tickets[i] = tp2_tickets[i];
   }
   else
   {
      ArrayResize(active_groups[active_group_count].tp2_tickets, 0);
   }
   
   active_group_count++;
   
   Print("Trade group created: ", group_id, " | Entry: ", entry, " | TP1 count: ", num_tp1, " | TP2 count: ", num_tp2);
   
   return group_id;
}

//+------------------------------------------------------------------+
//| Move Group to Breakeven                                          |
//+------------------------------------------------------------------+
void MoveGroupToBreakeven(int group_index)
{
   if(group_index < 0 || group_index >= active_group_count)
      return;
   
   // Check if already moved
   if(active_groups[group_index].breakeven_moved)
   {
      Print("Group ", active_groups[group_index].group_id, " already moved to breakeven");
      return;
   }
   
   double be_price = NormalizePrice(active_groups[group_index].entry_price);
   int moved_count = 0;
   
   // Get minimum stop level for safety check
   int stops_level = (int)SymbolInfoInteger(current_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_distance = stops_level * symbol_point;
   
   // Move all TP2 tickets to breakeven
   int tp2_count = ArraySize(active_groups[group_index].tp2_tickets);
   for(int i = 0; i < tp2_count; i++)
   {
      ulong ticket = active_groups[group_index].tp2_tickets[i];
      
      // Check if position still exists
      ResetLastError();
      if(PositionSelectByTicket(ticket))
      {
         double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
         double current_tp = PositionGetDouble(POSITION_TP);
         double current_sl = PositionGetDouble(POSITION_SL);
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // FIXED: Validate position data with error code check
         int error_code = GetLastError();
         if(current_price <= 0 || error_code != 0)
         {
            Print("[ERROR] Invalid position data for ticket #", ticket, ": Price=", current_price, " Error=", error_code);
            continue;
         }
         
         // Safety check: Verify BE price distance from current price
         double distance_from_current = MathAbs(be_price - current_price);
         
         if(distance_from_current < min_distance && min_distance > 0)
         {
            Print("WARNING: BE price too close to current. Distance: ", distance_from_current, 
                  " | Min required: ", min_distance, " | Ticket: ", ticket);
            continue;  // Skip this ticket
         }
         
         // Validate BE price vs position type
         // FIXED: Improved validation logic for both BUY and SELL
         bool valid_be = false;
         if(pos_type == POSITION_TYPE_BUY)
         {
            // For BUY: BE must be below current price (profit zone) and above current SL (improvement)
            valid_be = (be_price < current_price) && (current_sl == 0 || be_price > current_sl);
         }
         else  // POSITION_TYPE_SELL
         {
            // For SELL: BE must be above current price (profit zone) and below current SL (improvement)
            // When in profit, current price < entry, so BE (entry) > current price
            valid_be = (be_price > current_price) && (current_sl == 0 || be_price < current_sl);
         }
         
         if(!valid_be)
         {
            Print("WARNING: Invalid BE placement. Type: ", EnumToString(pos_type),
                  " | Current: ", current_price, " | BE: ", be_price, " | Current SL: ", current_sl);
            continue;
         }
         
         // Modify SL to breakeven, keep TP unchanged
         ResetLastError();
         if(trade.PositionModify(ticket, be_price, current_tp))
         {
            moved_count++;
            Print("[OK] Ticket #", ticket, " SL moved to breakeven: ", be_price);
         }
         else
         {
            int error_code = GetLastError();
            uint retcode = trade.ResultRetcode();
            Print("[ERROR] Failed to move ticket #", ticket, " to BE.");
            Print("  Error code: ", error_code);
            Print("  Retcode: ", retcode, " - ", trade.ResultRetcodeDescription());
            Print("  Request: SL=", be_price, " TP=", current_tp);
            Print("  Current: Price=", current_price, " SL=", current_sl);
         }
      }
   }
   
   // Mark as moved
   active_groups[group_index].breakeven_moved = true;
   
   Print("=== BREAKEVEN ACTIVATED ===");
   Print("Group: ", active_groups[group_index].group_id);
   Print("Moved ", moved_count, " position(s) to BE: ", be_price);
   Print("===========================");
}

//+------------------------------------------------------------------+
//| Check if ticket is TP1 in any group                             |
//+------------------------------------------------------------------+
int FindGroupByTP1Ticket(ulong ticket)
{
   for(int i = 0; i < active_group_count; i++)
   {
      int tp1_count = ArraySize(active_groups[i].tp1_tickets);
      for(int j = 0; j < tp1_count; j++)
      {
         if(active_groups[i].tp1_tickets[j] == ticket)
            return i;
      }
   }
   return -1; // Not found
}

//+------------------------------------------------------------------+
//| Remove closed group from tracking                                |
//+------------------------------------------------------------------+
void RemoveClosedGroups()
{
   for(int i = active_group_count - 1; i >= 0; i--)
   {
      bool all_closed = true;
      
      // Check TP1 tickets
      int tp1_count = ArraySize(active_groups[i].tp1_tickets);
      for(int j = 0; j < tp1_count; j++)
      {
         if(PositionSelectByTicket(active_groups[i].tp1_tickets[j]))
         {
            all_closed = false;
            break;
         }
      }
      
      // Check TP2 tickets
      if(all_closed)
      {
         int tp2_count = ArraySize(active_groups[i].tp2_tickets);
         for(int j = 0; j < tp2_count; j++)
         {
            if(PositionSelectByTicket(active_groups[i].tp2_tickets[j]))
            {
               all_closed = false;
               break;
            }
         }
      }
      
      // Remove group if all trades closed
      if(all_closed)
      {
         Print("Removing closed group: ", active_groups[i].group_id);
         
         // Shift array elements
         for(int k = i; k < active_group_count - 1; k++)
         {
            active_groups[k] = active_groups[k + 1];
         }
         
         active_group_count--;
         ArrayResize(active_groups, active_group_count);
      }
   }
}

//+------------------------------------------------------------------+
//| Add Ticket to Pending BE Cache                                   |
//+------------------------------------------------------------------+
void AddToPendingBECache(ulong ticket, double entry, TRADE_DIRECTION dir, bool is_tp1)
{
   // Check if ticket already exists
   for(int i = 0; i < pending_be_count; i++)
   {
      if(pending_be_cache[i].ticket == ticket)
      {
         Print("[WARNING] Ticket ", ticket, " already in pending BE cache.");
         return;
      }
   }
   
   // Resize array
   ResetLastError();
   int resize_result = ArrayResize(pending_be_cache, pending_be_count + 1);
   if(resize_result < 0)
   {
      int error_code = GetLastError();
      Print("[ERROR] Failed to resize pending_be_cache. Error: ", error_code);
      return;
   }
   
   // Add new entry
   pending_be_cache[pending_be_count].ticket = ticket;
   pending_be_cache[pending_be_count].entry_price = entry;
   pending_be_cache[pending_be_count].direction = dir;
   pending_be_cache[pending_be_count].created_time = TimeCurrent();
   pending_be_cache[pending_be_count].has_tp1 = is_tp1;
   
   pending_be_count++;
   
   Print("[INFO] Added ticket ", ticket, " to pending BE cache. Total cached: ", pending_be_count);
}

//+------------------------------------------------------------------+
//| Check if TP Added to Cached Position                            |
//+------------------------------------------------------------------+
void CheckTPAddedToCache(ulong ticket)
{
   // Find ticket in cache
   int cache_index = -1;
   for(int i = 0; i < pending_be_count; i++)
   {
      if(pending_be_cache[i].ticket == ticket)
      {
         cache_index = i;
         break;
      }
   }
   
   if(cache_index < 0)
      return;  // Not in cache
   
   // Check if position now has TP
   ResetLastError();
   if(!PositionSelectByTicket(ticket))
   {
      // FIXED: Check error code for better diagnostics
      int error_code = GetLastError();
      if(error_code != 0)
      {
         Print("[INFO] Position ", ticket, " not found (likely closed). Error: ", error_code);
      }
      // Position closed - remove from cache
      RemoveFromPendingBECache(cache_index);
      return;
   }
   
   double tp = PositionGetDouble(POSITION_TP);
   if(tp > 0)
   {
      // TP added! Activate BE tracking
      Print("[SUCCESS] TP detected for ticket ", ticket, ". Activating breakeven tracking.");
      
      // Try to find or create appropriate group
      ActivateBEForCachedTicket(cache_index);
      
      // Remove from cache
      RemoveFromPendingBECache(cache_index);
   }
}

//+------------------------------------------------------------------+
//| Activate BE for Cached Ticket                                    |
//+------------------------------------------------------------------+
void ActivateBEForCachedTicket(int cache_index)
{
   if(cache_index < 0 || cache_index >= pending_be_count)
      return;
   
   ulong ticket = pending_be_cache[cache_index].ticket;
   double entry = pending_be_cache[cache_index].entry_price;
   bool is_tp1 = pending_be_cache[cache_index].has_tp1;
   
   // Look for existing group with matching entry price (within tolerance)
   double tolerance = 10 * symbol_point;
   int matching_group = -1;
   
   for(int i = 0; i < active_group_count; i++)
   {
      if(MathAbs(active_groups[i].entry_price - entry) < tolerance)
      {
         matching_group = i;
         break;
      }
   }
   
   if(matching_group >= 0)
   {
      // Add to existing group
      if(is_tp1)
      {
         int tp1_size = ArraySize(active_groups[matching_group].tp1_tickets);
         ArrayResize(active_groups[matching_group].tp1_tickets, tp1_size + 1);
         active_groups[matching_group].tp1_tickets[tp1_size] = ticket;
      }
      else
      {
         int tp2_size = ArraySize(active_groups[matching_group].tp2_tickets);
         ArrayResize(active_groups[matching_group].tp2_tickets, tp2_size + 1);
         active_groups[matching_group].tp2_tickets[tp2_size] = ticket;
      }
      
      active_groups[matching_group].total_trades++;
      Print("[INFO] Added ticket ", ticket, " to existing group: ", active_groups[matching_group].group_id);
   }
   else
   {
      // Create new group with single ticket
      ulong tp1_array[1];
      ulong tp2_array[1];
      
      if(is_tp1)
      {
         tp1_array[0] = ticket;
         CreateTradeGroup(entry, 1, 0, tp1_array, tp2_array);
         Print("[INFO] Created new group for TP1 ticket: ", ticket);
      }
      else
      {
         tp2_array[0] = ticket;
         CreateTradeGroup(entry, 0, 1, tp1_array, tp2_array);
         Print("[INFO] Created new group for TP2 ticket: ", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Remove from Pending BE Cache                                     |
//+------------------------------------------------------------------+
void RemoveFromPendingBECache(int index)
{
   if(index < 0 || index >= pending_be_count)
      return;
   
   Print("[INFO] Removing ticket ", pending_be_cache[index].ticket, " from pending BE cache.");
   
   // Shift array elements
   for(int i = index; i < pending_be_count - 1; i++)
   {
      pending_be_cache[i] = pending_be_cache[i + 1];
   }
   
   pending_be_count--;
   ArrayResize(pending_be_cache, pending_be_count);
}

//+------------------------------------------------------------------+
//| Check Pending BE Cache for TP Updates                           |
//+------------------------------------------------------------------+
void CheckPendingBECache()
{
   datetime current_time = TimeCurrent();
   
   for(int i = pending_be_count - 1; i >= 0; i--)
   {
      ulong ticket = pending_be_cache[i].ticket;
      
      // FIXED: Check for timeout (24 hours)
      if(current_time - pending_be_cache[i].created_time > PENDING_BE_TIMEOUT)
      {
         Print("[WARNING] Pending BE cache timeout for ticket ", ticket, ". Removing from cache.");
         RemoveFromPendingBECache(i);
         continue;
      }
      
      // Check if position still exists
      ResetLastError();
      if(!PositionSelectByTicket(ticket))
      {
         // Position closed - remove from cache
         RemoveFromPendingBECache(i);
         continue;
      }
      
      // Check if TP was added
      double tp = PositionGetDouble(POSITION_TP);
      if(tp > 0)
      {
         Print("[SUCCESS] TP detected for cached ticket ", ticket, " during periodic check.");
         ActivateBEForCachedTicket(i);
         RemoveFromPendingBECache(i);
      }
   }
}

//+------------------------------------------------------------------+
