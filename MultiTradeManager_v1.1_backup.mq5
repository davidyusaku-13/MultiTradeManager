//+------------------------------------------------------------------+
//|                                      MultiTradeManager_v1.1.mq5|
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"
#property description "Multi-Trade Manager v1.1 - Market Execution & Pending Orders"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Trade Parameters ==="
input ulong Magic_Number = 12345;          // Magic Number for order identification
input int Number_Of_Trades = 2;            // Number of identical trades to open (must be even: 2, 4, 6, 8, 10)
input double Fixed_Lot_Size = 0.02;        // Fixed lot size per trade
input bool Half_Risk = false;               // Half Risk mode (Yes/No)
input double Stop_Loss_Price = 0.0;         // Stop Loss price level (0 = no SL)
input double Take_Profit_Price_1 = 0.0;     // Take Profit for trade 1 (0 = no TP)
input double Take_Profit_Price_2 = 0.0;     // Take Profit for trade 2 (0 = no TP)

input group "=== Display Settings ==="
input int Panel_X_Position = 5;          // Panel X position
input int Panel_Y_Position = 85;          // Panel Y position
input color Panel_Background = clrWhiteSmoke; // Panel background color
input color Panel_Border = clrDarkBlue;   // Panel border color

input group "=== Safety Settings ==="
input int Max_Total_Positions = 100;       // Maximum total positions allowed (recommended even number)
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
datetime last_price_update = 0;
datetime last_count_update = 0;
datetime last_gui_update = 0;

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
double GetTakeProfitForTrade(int trade_index)
{
   // Alternate between TP1 and TP2 for all trades
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
   symbol_stops_level = (int)SymbolInfoInteger(current_symbol, SYMBOL_TRADE_STOPS_LEVEL);

   //--- Initialize current prices with validation
   current_bid = SymbolInfoDouble(current_symbol, SYMBOL_BID);
   current_ask = SymbolInfoDouble(current_symbol, SYMBOL_ASK);

   // Validate prices
   if(current_bid <= 0 || current_ask <= 0)
   {
      Print("Error: Invalid price data for symbol ", current_symbol);
      return INIT_FAILED;
   }

   last_bid = current_bid;
   last_ask = current_ask;

   //--- Set up trade object with optimized settings
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(current_symbol);

   //--- Create GUI panel
   if(!CreatePanel())
   {
      Print("Failed to create GUI panel");
      return INIT_FAILED;
   }

   // Initialize displays
   UpdateLossProfitDisplay();
   UpdateFinalLotDisplay();

   Print("MultiTradeManager EA v1.1 initialized successfully for ", current_symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Remove all GUI objects
   DeletePanel();
   Print("MultiTradeManager EA v1.1 deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function (Optimized)                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_time = TimeCurrent();

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
   CreateLabel("label_title", "Multi-Trade Manager v1.1", ScalePos(10), ScalePos(10), clrDarkBlue, title_font_size);

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
   CreateLabel("label_trades_note", "(must be even)", ScalePos(145 + BASE_EDIT_WIDTH + 10), ScalePos(250), clrBlue, font_size - 1);

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
//| Create Label                                                     |
//+------------------------------------------------------------------+
bool CreateLabel(string name, string text, int x, int y, color clr, int label_font_size)
{
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      return false;

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
//| Calculate Adjusted Lot Size with Half Risk (Optimized)           |
//+------------------------------------------------------------------+
double CalculateAdjustedLotSize(double base_lot_size)
{
   // Early validation
   if(base_lot_size <= 0)
      return 0.0;

   return half_risk_enabled ? base_lot_size / 2.0 : base_lot_size;
}

//+------------------------------------------------------------------+
//| Calculate Loss Amount in Currency (Optimized)                     |
//+------------------------------------------------------------------+
double CalculateLossAmount(double lot_size, double sl_price, double open_price)
{
   if(sl_price <= 0 || open_price <= 0 || lot_size <= 0)
      return 0.0;

   // Use pre-calculated values for better performance
   return lot_size * (MathAbs(open_price - sl_price) / symbol_point) * symbol_tick_value;
}

//+------------------------------------------------------------------+
//| Calculate Profit Amount in Currency (Optimized)                   |
//+------------------------------------------------------------------+
double CalculateProfitAmount(double lot_size, double tp_price, double open_price)
{
   if(tp_price <= 0 || open_price <= 0 || lot_size <= 0)
      return 0.0;

   // Use pre-calculated values for better performance
   return lot_size * (MathAbs(tp_price - open_price) / symbol_point) * symbol_tick_value;
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
   string sl_amount_text = "($0.00)";
   if(sl_price > 0 && (selected_direction == TRADE_BUY || selected_direction == TRADE_SELL))
   {
      double reference_price = (selected_direction == TRADE_BUY) ? current_ask : current_bid;
      double loss_amount = CalculateLossAmount(adjusted_lot_size, sl_price, reference_price);
      sl_amount_text = "($" + DoubleToString(loss_amount, 2) + ")";
   }
   ObjectSetString(0, "label_sl_amount", OBJPROP_TEXT, sl_amount_text);

   // Calculate and update TP amounts for TP1 and TP2 only
   double reference_price = (selected_direction == TRADE_BUY) ? current_ask : current_bid;

   // Update both TP1 and TP2 amount displays
   for(int i = 0; i < 2; i++)
   {
      string tp_amount_label = "label_tp_amount_" + IntegerToString(i + 1);
      string tp_amount_text = "($0.00)";

      string edit_tp_field_name = "edit_tp_" + IntegerToString(i + 1);
      string tp_text = ObjectGetString(0, edit_tp_field_name, OBJPROP_TEXT);
      double tp_price = StringToDouble(tp_text);

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
//| Create Button                                                    |
//+------------------------------------------------------------------+
bool CreateButton(string name, string text, int x, int y, int width, int height, color clr)
{
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return false;
      
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
//| Create Edit Box                                                  |
//+------------------------------------------------------------------+
bool CreateEdit(string name, string text, int x, int y, int width, int height)
{
   if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0))
      return false;
      
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
   double open_price = StringToDouble(open_price_text);
   double sl_price = StringToDouble(sl_text);

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

   //--- Validate number of trades (must be even for TP1/TP2 distribution)
   if(num_trades <= 0 || num_trades > Max_Total_Positions)
   {
      UpdateStatus("Invalid trade count", clrRed);
      return;
   }

   //--- Validate that number of trades is even
   if(num_trades % 2 != 0)
   {
      UpdateStatus("Trade count must be even", clrRed);
      return;
   }

   //--- Check position limits
   int current_total = total_positions + total_pending_orders;
   if(current_total + num_trades > Max_Total_Positions)
   {
      UpdateStatus("Max positions exceeded", clrRed);
      return;
   }

   //--- Get dynamic TP values from GUI (only TP1 and TP2)
   double tp_prices[2];
   tp_prices[0] = StringToDouble(ObjectGetString(0, "edit_tp_1", OBJPROP_TEXT));
   tp_prices[1] = StringToDouble(ObjectGetString(0, "edit_tp_2", OBJPROP_TEXT));

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
         Print("Market trade ", i + 1, " executed successfully. Ticket: ", trade.ResultOrder(),
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
//| Validate Trade Number (must be even)                              |
//+------------------------------------------------------------------+
void ValidateTradeNumber()
{
   string trades_text = ObjectGetString(0, edit_trades_name, OBJPROP_TEXT);
   int num_trades = (int)StringToInteger(trades_text);
   if(num_trades <= 0) num_trades = Number_Of_Trades;

   // Check if number is even
   if(num_trades % 2 != 0)
   {
      UpdateStatus("Trade count must be even", clrRed);
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
               Print("Failed to close position. Ticket: ", ticket, " Error: ", trade.ResultRetcodeDescription());
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
                  Print("Failed to cancel pending order. Ticket: ", ticket, " Error: ", trade.ResultRetcodeDescription());
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
   static datetime last_status_update = 0;
   datetime current_time = TimeCurrent();

   if(current_time - last_status_update > 100) // Update every 100ms
   {
      ChartRedraw();
      last_status_update = current_time;
   }
}

//+------------------------------------------------------------------+