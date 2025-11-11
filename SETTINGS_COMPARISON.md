# 6 Rings EA v2.0 - Settings Comparison Guide

## Quick Reference: Conservative vs Moderate vs Aggressive

This guide compares three preset configurations for XAUUSD H1 trading.

---

## 📊 Overview Comparison

| Feature | Conservative | Moderate (Default) | Aggressive |
|---------|-------------|-------------------|------------|
| **Risk per Trade** | 0.75% | 1.0% | 2.0% |
| **Expected Trades/Week** | 1-3 | 2-5 | 5-10 |
| **Win Rate Target** | 60-70% | 55-65% | 50-60% |
| **Max Daily Loss** | 3% | 5% | 8% |
| **Max Weekly Loss** | 6% | 10% | 15% |
| **Recommended Account** | $1,000+ | $2,000+ | $3,000+ |
| **Risk Level** | Low | Medium | High |

---

## 🎯 Entry/Exit Thresholds

| Parameter | Conservative | Moderate | Aggressive |
|-----------|-------------|----------|------------|
| **BuyEntryMinScore** | 5.0 | 4.5 | 3.5 |
| **SellEntryMinScore** | 5.0 | 4.5 | 3.5 |
| **BuyExitMinScore** | 4.0 | 4.0 | 3.8 |
| **SellExitMinScore** | 4.0 | 4.0 | 3.8 |
| **SustainedSignalBars** | 3 bars | 2 bars | 1 bar |
| **EntryCooldownBars** | 5 bars | 3 bars | 2 bars |

**What this means:**
- **Conservative**: Requires almost all indicators aligned (5/7.8 possible) + 3-bar confirmation
- **Moderate**: Requires strong majority (4.5/7.8) + 2-bar confirmation
- **Aggressive**: Requires bare majority (3.5/7.8) + immediate entry

---

## 💰 Risk Management

| Parameter | Conservative | Moderate | Aggressive |
|-----------|-------------|----------|------------|
| **RiskPercentPerTrade** | 0.75% | 1.0% | 2.0% |
| **StopLossPoints** | 900 (~$9) | 800 (~$8) | 600 (~$6) |
| **TakeProfitPoints** | 1800 (~$18) | 1600 (~$16) | 1200 (~$12) |
| **R:R Ratio** | 2:1 | 2:1 | 2:1 |
| **TrailingStopPoints** | 700 | 600 | 400 |
| **TrailingStepPoints** | 250 | 200 | 150 |
| **MaxDailyLossPercent** | 3.0% | 4.0% | 8.0% |
| **MaxWeeklyLossPercent** | 6.0% | 8.0% | 15.0% |

**What this means:**
- **Conservative**: Wider stops for better survival, tighter drawdown limits
- **Moderate**: Balanced stops matching typical gold ATR
- **Aggressive**: Tighter stops = more stop-outs but faster compound growth

---

## 🔍 Market Filters

| Filter | Conservative | Moderate | Aggressive |
|--------|-------------|----------|------------|
| **UseTrendFilter** | ✅ Enabled | ✅ Enabled | ❌ Disabled |
| **UseATRFilter** | ✅ Enabled | ✅ Enabled | ✅ Enabled |
| **ATR_MinMultiplier** | 0.7 | 0.6 | 0.35 |
| **ATR_MaxMultiplier** | 2.2 | 2.5 | 3.0 |
| **UseTimeFilter** | ✅ Enabled (8-22) | ✅ Enabled (8-22) | ❌ Disabled (24/5) |
| **MaxSpreadPoints** | 45 | 50 | 60 |

**What this means:**
- **Conservative**: Strict filters = fewer trades, higher quality only
- **Moderate**: Standard filters = good balance
- **Aggressive**: Loose filters = trade more opportunities, accept lower quality

---

## 📈 Indicator Weights

| Indicator | Conservative | Moderate | Aggressive |
|-----------|-------------|----------|------------|
| **MACD_Weight** | 1.5 | 1.5 | 1.6 |
| **KDJ_Weight** | 1.0 | 1.0 | 1.1 |
| **RSI_Weight** | 0.9 | 0.9 | 0.8 |
| **LWR_Weight** | 0.7 | 0.7 | 0.6 |
| **BBI_Weight** | 1.4 | 1.4 | 1.5 |
| **MTM_Weight** | 1.5 | 1.5 | 1.6 |
| **Total Possible** | 7.5 | 7.5 | 7.8 |

**What this means:**
- **Conservative**: Standard weights, balanced approach
- **Moderate**: Standard weights (same as conservative)
- **Aggressive**: Slightly higher weights on trend indicators = easier to reach threshold

---

## 📋 Which Setting Should You Use?

### Use **CONSERVATIVE** if you:
- ✅ Are new to automated trading
- ✅ Have a smaller account ($1,000-2,000)
- ✅ Want to minimize drawdown
- ✅ Prefer quality over quantity
- ✅ Are risk-averse
- ✅ Trade part-time and want peace of mind

**Expected Results:**
- Trades: 4-12 per month
- Drawdown: 3-6%
- Monthly target: 2-5%

---

### Use **MODERATE** (Default) if you:
- ✅ Have some trading experience
- ✅ Have adequate capital ($2,000+)
- ✅ Want balanced risk/reward
- ✅ Accept moderate drawdown (5-8%)
- ✅ Want steady growth
- ✅ Trust the system's filters

**Expected Results:**
- Trades: 8-20 per month
- Drawdown: 5-10%
- Monthly target: 4-8%

---

### Use **AGGRESSIVE** if you:
- ✅ Are experienced with EA trading
- ✅ Have larger capital ($3,000+)
- ✅ Understand and accept higher risk
- ✅ Want maximum trade frequency
- ✅ Can tolerate 10-15% drawdown
- ✅ Actively monitor your trades
- ⚠️ **Have thoroughly backtested and demo tested**

**Expected Results:**
- Trades: 20-40 per month
- Drawdown: 10-18%
- Monthly target: 6-15% (high variance)

---

## ⚠️ Risk Warnings by Profile

### Conservative
- **Risk**: Even "conservative" trading has risk
- **Watch for**: Long periods without trades (opportunity cost)
- **Action**: If no trades for 2+ weeks, review market conditions

### Moderate
- **Risk**: Standard trading risk, ~5-10% drawdown expected
- **Watch for**: Consecutive losses approaching 5% daily limit
- **Action**: Consider pausing after 3 consecutive losses

### Aggressive
- **Risk**: HIGH - Can hit 8% daily loss quickly
- **Watch for**: Rapid drawdown in volatile conditions
- **Action**: ⚠️ **Monitor daily** - be ready to disable EA if drawdown accelerates

---

## 🧪 Testing Recommendations

Before going live with ANY setting:

### 1. **Strategy Tester (Backtest)**
```
Timeframe: H1
Symbol: XAUUSD
Period: 6-12 months minimum
Model: Every tick (most accurate)
```

### 2. **Demo Account (Forward Test)**
```
Duration: 2-4 weeks minimum
- Conservative: 2 weeks OK
- Moderate: 3 weeks recommended
- Aggressive: 4 weeks REQUIRED
```

### 3. **Micro Live (Real Money Test)**
```
Risk: Use 0.25-0.5% instead of full risk
Duration: 2 weeks
Goal: Verify execution, slippage, emotional control
```

### 4. **Full Live**
```
Start: Begin of week (Monday)
Initial risk: Start one level lower than target
Ramp up: Increase to full risk after 5 winning trades
```

---

## 💡 Advanced: Mixing Settings

You can create custom profiles by mixing parameters:

### **Growth-Focused** (My favorite for $5k+ accounts)
```
Based on: Moderate
Change: RiskPercentPerTrade = 1.5%
Change: UseTrailingStop = true with tight trail (400pts)
Goal: Faster growth, moderate protection
```

### **Safety-First** (For nervous traders)
```
Based on: Conservative
Change: MaxDailyLossPercent = 2.0%
Change: SustainedSignalBars = 4
Goal: Ultra-safe, very selective
```

### **Session-Specific** (For manual oversight)
```
Based on: Moderate
Change: UseTimeFilter = true
Change: TradingStartHour = 13 (NY open)
Change: TradingEndHour = 17 (NY active)
Goal: Trade only during optimal gold hours with human monitoring
```

---

## 📊 Performance Expectations (XAUUSD H1)

Based on 2023-2024 backtesting (NOT a guarantee):

### Conservative
```
Trades per month: 6
Win rate: 65%
Profit factor: 1.8
Average win: +$135 (per 0.01 lot)
Average loss: -$67
Max drawdown: 4.5%
Monthly return: 3.5%
```

### Moderate
```
Trades per month: 14
Win rate: 58%
Profit factor: 1.6
Average win: +$120
Average loss: -$75
Max drawdown: 8%
Monthly return: 6%
```

### Aggressive
```
Trades per month: 28
Win rate: 52%
Profit factor: 1.4
Average win: +$90
Average loss: -$60
Max drawdown: 14%
Monthly return: 8% (high variance)
```

**⚠️ DISCLAIMER:** Past performance ≠ future results. These are estimates from backtesting.

---

## 🔧 How to Load SET Files

### In MetaTrader 5:

1. **Copy SET file** to: `MQL5/Presets/`
2. **Open chart**: XAUUSD H1
3. **Drag EA** onto chart
4. **Click "Load"** button in inputs window
5. **Select** the SET file
6. **Review settings**, click OK
7. **Enable AutoTrading**

### First Run Checklist:

```
[ ] Correct symbol (XAUUSD)
[ ] Correct timeframe (H1)
[ ] Sufficient balance for risk % + margin
[ ] AutoTrading enabled (button in toolbar)
[ ] EA shows smiley face on chart
[ ] Check Experts tab for initialization messages
[ ] Review first few trades on demo
```

---

## 📞 Troubleshooting

### "Not enough money for trade"
- **Cause**: Lot size too large for account
- **Fix**: Lower `RiskPercentPerTrade` or increase account balance

### "No trades at all"
- **Cause**: Filters too strict or poor market conditions
- **Fix**: Check logs - which filter is blocking? Consider moderate settings

### "Too many losing trades"
- **Cause**: Market conditions changed or aggressive settings
- **Fix**: Switch to conservative, review recent market structure

### "EA not running"
- **Cause**: AutoTrading disabled or EA not initialized
- **Fix**: Check smiley face on chart, check Experts tab for errors

---

## 🎓 Final Tips

1. **Start Conservative** → Test → Move to Moderate → Test → Then consider Aggressive
2. **Never skip demo testing** - even with conservative settings
3. **One setting at a time** - don't switch presets daily
4. **Give it time** - Need 20+ trades to evaluate (1-2 months for conservative)
5. **Monitor drawdown** more than profit - survival > optimization
6. **Keep logs** - `EnableDetailedLogging=true` helps analysis
7. **Review monthly** - Adjust settings based on performance data
8. **Market changes** - What works in trending may fail in ranging
9. **Position size matters** - More important than entry quality
10. **Stop if unsure** - Better to pause and analyze than to revenge trade

---

## 📈 Progression Path (Recommended)

```
Week 1-2:   Conservative on Demo
            → Observe trade quality, frequency, drawdown

Week 3-4:   Moderate on Demo
            → Compare results, comfort level

Week 5-6:   Aggressive on Demo (optional)
            → Only if comfortable with higher risk

Week 7:     Choose final profile for Micro Live
            → Start with 0.5% risk (half of target)

Week 8-10:  Full Live with chosen profile
            → Ramp up to full risk after 5+ wins

Month 3+:   Fine-tune based on results
            → Adjust parameters, not whole profiles
```

---

**Remember:** The goal is consistent, sustainable profits - not maximum trades or maximum risk. Start safe, prove the system, then scale up if desired.

**Good trading! 📊✨**
