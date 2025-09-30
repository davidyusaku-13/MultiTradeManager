# MultiTradeManager Changelog

## Version 1.2 (2025-09-30)

### ✨ New Features

#### 1. **Auto Breakeven System**
- **Independent Trade Groups**: Each execution creates a separate trade group
- **Automatic BE Trigger**: When any TP1 trade hits target, remaining TP2 trades in the same group automatically move SL to breakeven (exact entry price)
- **Smart Tracking**: Uses `OnTradeTransaction()` event handler for real-time monitoring
- **Group Management**: Automatic cleanup of closed trade groups

**How It Works:**
```
EXECUTE: 2 trades ETHUSD @ 2500
  ├─ Trade #1: Entry 2500, TP=2520 (TP1)
  └─ Trade #2: Entry 2500, TP=2540 (TP2)

When Trade #1 hits TP1 (2520):
  → Trade #2 SL automatically moved to 2500 (breakeven)
  → No risk remaining on Trade #2!
```

**Benefits:**
- ✅ Protects profits automatically
- ✅ Independent groups don't interfere with each other
- ✅ Zero manual intervention needed
- ✅ Works with both market and pending orders

#### 2. **Price Normalization System**
- **Tick Size Validation**: All prices normalized to broker's tick size
- **Digit Precision**: Proper rounding based on symbol digits
- **Fix for Price Rounding Issues**: No more "1680 becomes 1679.66" problems

**Technical Implementation:**
```mql5
NormalizePrice() function:
- Rounds to nearest tick size
- Normalizes to symbol digits
- Applied to: Entry, SL, TP1, TP2
```

**Fixes Issues With:**
- ✅ XAUUSD (Gold)
- ✅ ETHUSD (Ethereum)
- ✅ Forex majors
- ✅ Indices
- ✅ Any symbol with specific tick requirements

### 🔧 Technical Improvements

**New Functions Added:**
- `NormalizePrice()` - Price normalization helper
- `CreateTradeGroup()` - Trade group creation and tracking
- `MoveGroupToBreakeven()` - BE execution logic
- `FindGroupByTP1Ticket()` - Group lookup by ticket
- `RemoveClosedGroups()` - Cleanup closed groups
- `OnTradeTransaction()` - Event handler for TP monitoring

**New Structures:**
```mql5
struct TradeGroup {
   string group_id;
   datetime created_time;
   double entry_price;
   bool breakeven_moved;
   int total_trades;
   ulong tp1_tickets[];
   ulong tp2_tickets[];
}
```

### 📊 Log Output Examples

**Group Creation:**
```
Trade group created: MTM_2025.09.30_16:15:30_123456 | Entry: 2500.00 | TP1 count: 1 | TP2 count: 1
```

**Breakeven Activation:**
```
TP1 hit detected! Ticket: 123456789 | Triggering breakeven for group
=== BREAKEVEN ACTIVATED ===
Group: MTM_2025.09.30_16:15:30_123456
Moved 1 position(s) to BE: 2500.00
===========================
Ticket #987654321 SL moved to breakeven: 2500.00
```

### 🐛 Bug Fixes
- Fixed price rounding issues (ETHUSD, XAUUSD, etc.)
- Fixed floating point precision errors in price input
- Improved price display consistency

### 🎨 Version Updates
- Version number: 1.10 → 1.20
- Description updated to reflect new features
- Print statements updated for v1.2

---

## Version 1.1 (Previous)

### Features
- Multi-trade execution (market & pending)
- Dual TP system (TP1 & TP2 alternating)
- Half Risk mode
- Responsive GUI with DPI scaling
- Basic risk calculation display

---

## Migration Notes (1.1 → 1.2)

### No Breaking Changes
- All v1.1 functionality preserved
- New features work automatically
- No input parameter changes required
- Existing settings remain compatible

### What to Expect
1. **First Run**: EA will detect DPI and log settings
2. **Price Inputs**: Prices now automatically normalized
3. **Trade Execution**: Groups created automatically
4. **Breakeven**: Activates when TP1 hits (fully automatic)

### Testing Recommendations
1. Test with small lot sizes first
2. Monitor Expert log for breakeven triggers
3. Verify price normalization on your symbols
4. Test with 2, 4, 6 trades to verify grouping

---

## Support & Troubleshooting

### Price Normalization Issues?
- Check Expert log for "normalized" messages
- Verify symbol tick size: `SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE)`
- Try different price inputs to test rounding

### Breakeven Not Triggering?
- Verify TP1 is being hit (check Expert log)
- Confirm trade comment contains "MultiTrade"
- Check magic number matches
- Look for "TP1 hit detected" message in log

### Group Tracking Issues?
- Check "Trade group created" messages
- Verify ticket numbers in logs
- Ensure trades executed successfully

---

## Known Limitations
- Breakeven only for TP2 trades (TP1 trades close at target)
- Requires even number of trades (enforced by EA)
- Only works with trades managed by this EA
- Pending orders tracked when converted to positions

---

## Future Considerations
- Optional BE buffer (entry + X pips)
- Configurable BE trigger (multiple TP1 hits)
- Trailing stop after BE activated
- Visual panel indicators for BE status
- Multi-TP level support (TP3, TP4, etc.)

---

**Developed by:** MultiTradeManager Team  
**License:** MetaQuotes Ltd. Copyright 2025  
**Platform:** MetaTrader 5