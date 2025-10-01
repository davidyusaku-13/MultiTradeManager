# MultiTradeManager v1.2.1 - Bug Fixes & Improvements

**Release Date:** 2025-10-01

## 🔧 Critical Fixes

### 1. Partial Execution Support (Issue #2)
**Problem:** Trade groups were only created if BOTH TP1 and TP2 positions existed. In partial execution scenarios (e.g., only 2 out of 4 trades successful), if all successful trades had the same TP, no group was created and breakeven tracking was disabled.

**Solution:**
- Modified group creation logic to accept partial executions
- Groups now created with only TP1 OR only TP2 positions
- Added informative warning messages for different scenarios
- **Location:** `ExecuteMarketTrades()` line 1459

**Code Change:**
```mql5
// BEFORE:
if(successful_trades > 0 && tp1_count > 0 && tp2_count > 0)

// AFTER:
if(successful_trades > 0 && (tp1_count > 0 || tp2_count > 0))
```

---

### 2. Pending BE Cache Timeout (Issue #7)
**Problem:** Positions without TP remained in pending BE cache indefinitely, causing potential memory buildup if users forgot to add TP.

**Solution:**
- Added 24-hour timeout constant (`PENDING_BE_TIMEOUT = 86400`)
- Automatic cleanup of expired cache entries during periodic checks
- Warning message when timeout occurs
- **Location:** `CheckPendingBECache()` line 2324-2330

**Impact:** Prevents memory leaks and improves long-term stability.

---

### 3. Market Order Stops Level Validation (Issue #6)
**Problem:** Market orders could be rejected by broker if SL was too close to current market price. EA only validated stops level for pending orders.

**Solution:**
- Added stops level validation for market orders
- Checks minimum distance between entry price and SL
- Displays clear error message with actual vs required distance
- **Location:** `ExecuteTrades()` line 1271-1285

**Code Addition:**
```mql5
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
```

---

### 4. TP Price Normalization in Display (Issue #4)
**Problem:** TP prices in profit/loss display calculations were not normalized, causing slight inconsistencies between displayed profit and actual execution.

**Solution:**
- Added `NormalizePrice()` call when reading TP values for display
- Ensures consistency with execution logic
- **Location:** `UpdateLossProfitDisplay()` line 946

**Code Change:**
```mql5
// BEFORE:
double tp_price = StringToDouble(tp_text);

// AFTER:
double tp_price = NormalizePrice(StringToDouble(tp_text));
```

---

## 🛡️ Enhanced Error Handling

### 5. Position Data Validation
**Improvement:** Added comprehensive error code checks when selecting positions.

**Locations:**
- `MoveGroupToBreakeven()` line 2006-2012
- `CheckTPAddedToCache()` line 2203-2208  
- `ExecuteMarketTrades()` line 1404-1409

**Benefits:**
- Better diagnostics for debugging
- Prevents crashes from invalid position data
- Clearer error messages in logs

---

### 6. Optimized Array Management
**Improvement:** Fixed array resize logic in `CreateTradeGroup()`.

**Changes:**
- Only resize arrays when count > 0
- Explicit handling of empty arrays
- Cleaner memory management
- **Location:** `CreateTradeGroup()` line 1939-1960

**Code Structure:**
```mql5
// FIXED: Only resize if count > 0
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
```

---

### 7. Improved Code Documentation
**Improvement:** Added detailed comments explaining breakeven logic.

**Location:** `MoveGroupToBreakeven()` line 2025-2036

**Clarifications:**
- BUY position: BE must be below current price (profit zone) and above current SL
- SELL position: BE must be above current price (profit zone) and below current SL
- Explains why logic is correct for both directions

---

## 📊 Summary

| Issue | Severity | Status | Impact |
|-------|----------|--------|--------|
| Partial Execution Support | **Critical** | ✅ Fixed | BE tracking now works with partial executions |
| Pending BE Cache Timeout | **High** | ✅ Fixed | Prevents memory leaks |
| Market Order Validation | **High** | ✅ Fixed | Prevents broker rejections |
| TP Normalization | **Medium** | ✅ Fixed | Display accuracy improved |
| Error Handling | **Medium** | ✅ Improved | Better diagnostics |
| Array Management | **Low** | ✅ Optimized | Cleaner code |
| Documentation | **Low** | ✅ Enhanced | Better maintainability |

---

## 🧪 Testing Recommendations

1. **Partial Execution Test:**
   - Set number of trades to 4
   - Manually close 2 positions immediately after opening
   - Verify group is still created with remaining positions

2. **Stops Level Test:**
   - Set SL very close to current market price
   - Attempt market order execution
   - Verify error message appears

3. **BE Cache Timeout Test:**
   - Open positions without TP
   - Wait 24+ hours (or modify timeout constant for testing)
   - Verify automatic cleanup

4. **Display Accuracy Test:**
   - Enter TP prices with many decimals
   - Verify displayed profit matches actual execution

---

## 📝 Notes

- All changes are backward compatible
- No changes to input parameters or GUI
- Existing trade groups continue to work normally
- Log messages enhanced for better monitoring

---

## 🔄 Upgrade Instructions

1. Close all positions managed by old version
2. Remove EA from chart
3. Compile new version (v1.2.1)
4. Attach to chart
5. Verify settings are correct

**No data migration required.**

---

## 👨‍💻 Developer Notes

### Code Quality Improvements:
- Consistent error handling patterns
- Better separation of concerns
- Improved code readability
- Enhanced logging for debugging

### Performance:
- No performance degradation
- Slightly improved memory management
- More efficient array operations

### Future Considerations:
- Consider adding configurable timeout for pending BE cache
- Potential for dynamic stops level adjustment
- Enhanced partial execution strategies

---

**Version:** 1.2.1  
**Previous Version:** 1.2  
**Compatibility:** MT5 Build 3802+  
**Language:** MQL5
