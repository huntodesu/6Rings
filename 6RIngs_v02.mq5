#property strict
#property version   "2.00"
#property description "6 Rings Enhanced - Multi-indicator consensus strategy with improved risk management"
#include <Trade/Trade.mqh>

// ======================== DISPLAY / LOGIC MODES ========================
input bool   UseNeutralColors         = false;     // true: 3-color (strong/neutral) | false: classic 2-color

// ======================== INDICATOR PARAMETERS =========================
// MACD
input int    MACD_Fast                = 12;
input int    MACD_Slow                = 26;
input int    MACD_Signal              = 9;
input double MACD_NeutralThreshold    = 0.001;     // |MACD - Signal|

// KDJ (Stochastic smoothed)
input int    KDJ_Length               = 9;
input int    KDJ_Smooth               = 3;         // used for slowing and D period
input double KDJ_NeutralZone          = 2.0;       // K-D threshold for neutral (was hardcoded)

// RSI
input int    RSI_Length               = 14;
input double RSI_NeutralZone          = 5.0;       // +/- around 50

// LWR (Williams %R)
input int    LWR_Length               = 14;
input double LWR_NeutralZone          = 10.0;      // +/- around -50

// BBI (avg of 4 SMAs)
input int    BBI_Len1                 = 3;
input int    BBI_Len2                 = 6;
input int    BBI_Len3                 = 12;
input int    BBI_Len4                 = 24;
input double BBI_NeutralPct           = 0.2;       // 0.2% threshold (was hardcoded)

// MTM
input int    MTM_Length               = 12;        // close - close[n]
input double MTM_PctThreshold         = 0.5;       // 0.5% of price

// ===================== WEIGHTED SCORING SYSTEM =========================
input bool   UseWeightedScoring       = true;      // Use weighted vs simple count
input double MACD_Weight              = 1.5;       // MACD signal weight
input double KDJ_Weight               = 1.0;       // KDJ signal weight
input double RSI_Weight               = 1.0;       // RSI signal weight
input double LWR_Weight               = 0.8;       // Williams %R weight (similar to RSI)
input double BBI_Weight               = 1.2;       // BBI trend weight
input double MTM_Weight               = 1.3;       // Momentum weight

// ==================== COUNT/SCORE-BASED ENTRY/EXIT =====================
input double BuyEntryMinScore         = 4.0;       // Buy entry threshold (was 6)
input double BuyExitMinScore          = 4.0;       // Exit on opposite signal (was 6)
input double SellEntryMinScore        = 4.0;       // Sell entry threshold (was 6)
input double SellExitMinScore         = 4.0;       // Exit on opposite signal (was 6)
input bool   UseEdgeTrigger           = true;      // only act when count crosses threshold
input int    SustainedSignalBars      = 1;         // Bars signal must be sustained (1=immediate)
input int    EntryCooldownBars        = 3;         // Bars to wait after exit before re-entry

// ====================== MARKET CONDITION FILTERS =======================
input bool   UseATRFilter             = true;      // Filter by volatility
input int    ATR_Period               = 14;
input double ATR_MinMultiplier        = 0.5;       // Min ATR (multiple of median)
input double ATR_MaxMultiplier        = 3.0;       // Max ATR (multiple of median) - avoid extreme volatility

input bool   UseTrendFilter           = true;      // Trade only with higher TF trend
input ENUM_TIMEFRAMES TrendTimeframe  = PERIOD_H4; // Higher timeframe for trend
input int    TrendMA_Period           = 50;        // MA period for trend

input bool   UseTimeFilter            = false;     // Trade only during certain hours
input int    TradingStartHour         = 2;         // Start hour (broker time)
input int    TradingEndHour           = 22;        // End hour (broker time)

// ======================= RISK MANAGEMENT ===============================
input bool   UseDynamicLots           = true;      // Calculate lot size from risk %
input double RiskPercentPerTrade      = 1.0;       // Risk % of account per trade
input double FixedLots                = 0.10;      // Used if UseDynamicLots=false
input int    StopLossPoints           = 300;       // SL in points (0 = no SL) - REQUIRED for dynamic sizing
input int    TakeProfitPoints         = 600;       // TP in points (0 = no TP)

input bool   UseTrailingStop          = true;      // Enable trailing stop
input int    TrailingStopPoints       = 200;       // Distance to trail (in points)
input int    TrailingStepPoints       = 50;        // Minimum price movement to update trail

input bool   UseMaxDrawdown           = true;      // Enable drawdown protection
input double MaxDailyLossPercent      = 5.0;       // Max daily loss % before halt
input double MaxWeeklyLossPercent     = 10.0;      // Max weekly loss % before halt

// ======================= TRADING SETTINGS ==============================
input ulong  MagicNumber              = 6600066;
input bool   OneTradePerSide          = true;      // avoid multiple same-direction positions
input int    MaxSpreadPoints          = 150;       // 0 = ignore
input bool   TradeOnlyOnNewBar        = true;

input bool   EnableDetailedLogging    = true;      // Log trade decisions

// ========================== GLOBALS ====================================
CTrade Trade;
int hMACD=INVALID_HANDLE, hRSI=INVALID_HANDLE, hWPR=INVALID_HANDLE, hStoch=INVALID_HANDLE;
int hMA1=INVALID_HANDLE, hMA2=INVALID_HANDLE, hMA3=INVALID_HANDLE, hMA4=INVALID_HANDLE;
int hATR=INVALID_HANDLE, hTrendMA=INVALID_HANDLE;

datetime lastBarTime=0;
datetime lastExitTime=0;        // Track when last exit occurred
double dailyStartBalance=0;     // Balance at start of day
double weeklyStartBalance=0;    // Balance at start of week
datetime lastDailyReset=0;
datetime lastWeeklyReset=0;
bool tradingHalted=false;

// Signal history for sustained signals
double prevBullScore[10];
double prevBearScore[10];
int signalHistoryIndex=0;

struct SixState {
   bool macd_bull, macd_bear;
   bool kdj_bull,  kdj_bear;
   bool rsi_bull,  rsi_bear;
   bool lwr_bull,  lwr_bear;
   bool bbi_bull,  bbi_bear;
   bool mtm_bull,  mtm_bear;
};

// ======================== HELPER FUNCTIONS =============================

// Get single buffer value
bool GetOne(const int handle,const int buffer,const int shift,double &val){
   if(handle==INVALID_HANDLE) return false;
   double a[];
   if(CopyBuffer(handle, buffer, shift, 1, a)!=1) return false;
   val=a[0];
   return true;
}

// Check for new bar
bool NewBar(){
   datetime t=iTime(_Symbol,_Period,0);
   if(t==lastBarTime) return false;
   lastBarTime=t;
   return true;
}

// Check spread
bool SpreadOK(){
   int spr=(int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadPoints>0 && spr>MaxSpreadPoints) {
      if(EnableDetailedLogging) Print("❌ Spread too high: ", spr, " points");
      return false;
   }
   return true;
}

// Get KDJ values
bool GetKDJ(int shift,double &K,double &D,double &J){
   if(!GetOne(hStoch,0,shift,K)) return false;
   if(!GetOne(hStoch,1,shift,D)) return false;
   J=3.0*K-2.0*D;
   return true;
}

// Get BBI value
bool GetBBI(int shift,double &bbi){
   double m1,m2,m3,m4;
   if(!GetOne(hMA1,0,shift,m1)) return false;
   if(!GetOne(hMA2,0,shift,m2)) return false;
   if(!GetOne(hMA3,0,shift,m3)) return false;
   if(!GetOne(hMA4,0,shift,m4)) return false;
   bbi=(m1+m2+m3+m4)/4.0;
   return true;
}

// Check if sufficient bars available
bool SufficientBars(){
   int minBars = MathMax(MTM_Length + SustainedSignalBars + 10, 200);
   int bars = Bars(_Symbol,_Period);
   if(bars < minBars) {
      if(EnableDetailedLogging) Print("❌ Insufficient bars: ", bars, " < ", minBars);
      return false;
   }
   return true;
}

// ====================== MARKET FILTERS =================================

// Check ATR filter
bool ATRFilterOK(){
   if(!UseATRFilter) return true;

   double atr_current;
   if(!GetOne(hATR, 0, 1, atr_current)) return false;

   // Get median ATR over 50 bars
   double atr_sum=0;
   int lookback=50;
   for(int i=1; i<=lookback; i++){
      double atr_val;
      if(GetOne(hATR, 0, i, atr_val)) atr_sum+=atr_val;
   }
   double atr_median = atr_sum/lookback;

   if(atr_current < atr_median * ATR_MinMultiplier){
      if(EnableDetailedLogging) Print("❌ ATR too low: ", atr_current, " < ", atr_median * ATR_MinMultiplier);
      return false;
   }
   if(atr_current > atr_median * ATR_MaxMultiplier){
      if(EnableDetailedLogging) Print("❌ ATR too high: ", atr_current, " > ", atr_median * ATR_MaxMultiplier);
      return false;
   }
   return true;
}

// Check trend filter
int GetTrendDirection(){
   if(!UseTrendFilter) return 0; // 0=any, 1=up, -1=down

   double trendMA, currentPrice;
   if(!GetOne(hTrendMA, 0, 1, trendMA)) return 0;
   currentPrice = iClose(_Symbol, TrendTimeframe, 1);

   if(currentPrice > trendMA) return 1;  // Uptrend
   if(currentPrice < trendMA) return -1; // Downtrend
   return 0;
}

// Check time filter
bool TimeFilterOK(){
   if(!UseTimeFilter) return true;

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);

   if(TradingStartHour <= TradingEndHour){
      // Normal range (e.g., 8-18)
      if(tm.hour >= TradingStartHour && tm.hour < TradingEndHour) return true;
   } else {
      // Overnight range (e.g., 22-2)
      if(tm.hour >= TradingStartHour || tm.hour < TradingEndHour) return true;
   }

   if(EnableDetailedLogging) Print("❌ Outside trading hours: ", tm.hour);
   return false;
}

// ==================== DRAWDOWN PROTECTION ==============================

void ResetDrawdownTracking(){
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);

   // Daily reset
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(lastDailyReset != todayStart){
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDailyReset = todayStart;
      tradingHalted = false; // Reset halt on new day
      if(EnableDetailedLogging) Print("✅ Daily reset: Balance = ", dailyStartBalance);
   }

   // Weekly reset (Monday)
   if(tm.day_of_week == 1 && lastWeeklyReset != todayStart){
      weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastWeeklyReset = todayStart;
      if(EnableDetailedLogging) Print("✅ Weekly reset: Balance = ", weeklyStartBalance);
   }
}

bool DrawdownOK(){
   if(!UseMaxDrawdown) return true;
   if(tradingHalted) return false;

   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Check daily drawdown
   if(dailyStartBalance > 0){
      double dailyLossPct = (dailyStartBalance - currentBalance) / dailyStartBalance * 100.0;
      if(dailyLossPct > MaxDailyLossPercent){
         tradingHalted = true;
         Print("🛑 TRADING HALTED: Daily loss ", dailyLossPct, "% exceeds limit ", MaxDailyLossPercent, "%");
         return false;
      }
   }

   // Check weekly drawdown
   if(weeklyStartBalance > 0){
      double weeklyLossPct = (weeklyStartBalance - currentBalance) / weeklyStartBalance * 100.0;
      if(weeklyLossPct > MaxWeeklyLossPercent){
         tradingHalted = true;
         Print("🛑 TRADING HALTED: Weekly loss ", weeklyLossPct, "% exceeds limit ", MaxWeeklyLossPercent, "%");
         return false;
      }
   }

   return true;
}

// ==================== DYNAMIC POSITION SIZING ==========================

double CalculateLotSize(int slPoints){
   if(!UseDynamicLots) return FixedLots;

   if(slPoints <= 0){
      Print("⚠️ Warning: Dynamic lots requires StopLossPoints > 0. Using fixed lots.");
      return FixedLots;
   }

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = accountBalance * RiskPercentPerTrade / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Calculate money risk per point
   double moneyPerPoint = tickValue * (point / tickSize);

   // Calculate lot size
   double lotSize = riskMoney / (slPoints * moneyPerPoint);

   // Apply broker limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(lotSize, minLot);
   lotSize = MathMin(lotSize, maxLot);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   if(EnableDetailedLogging)
      Print("📊 Dynamic lot size: ", lotSize, " (Risk: $", riskMoney, " / SL: ", slPoints, " pts)");

   return lotSize;
}

// ===================== CORE INDICATOR COMPUTATION ======================

bool ComputeSix(int shift, SixState &S){
   double c0=iClose(_Symbol,_Period,shift);
   int mtmShift = shift + MTM_Length;

   // Validate sufficient bars for MTM
   if(Bars(_Symbol, _Period) <= mtmShift){
      if(EnableDetailedLogging) Print("❌ Insufficient bars for MTM calculation at shift ", shift);
      return false;
   }

   double cN=iClose(_Symbol,_Period,mtmShift);
   if(c0==0.0 || cN==0.0) return false;

   // MACD
   double macd_main,macd_sig;
   if(!GetOne(hMACD,0,shift,macd_main)) return false;
   if(!GetOne(hMACD,1,shift,macd_sig )) return false;
   double macd_diff=MathAbs(macd_main-macd_sig);
   bool macd_neu=(macd_diff<=MACD_NeutralThreshold);
   if(UseNeutralColors){
      S.macd_bull=(macd_main>macd_sig)&&!macd_neu;
      S.macd_bear=(macd_main<macd_sig)&&!macd_neu;
   } else {
      S.macd_bull=(macd_main>macd_sig);
      S.macd_bear=(macd_main<macd_sig);
   }

   // KDJ
   double K,D,J;
   if(!GetKDJ(shift,K,D,J)) return false;
   double kd=MathAbs(K-D);
   bool kdj_neu=(kd<=KDJ_NeutralZone);
   if(UseNeutralColors){
      S.kdj_bull=(K>D)&&!kdj_neu;
      S.kdj_bear=(K<D)&&!kdj_neu;
   } else {
      S.kdj_bull=(K>D);
      S.kdj_bear=(K<D);
   }

   // RSI
   double rsi;
   if(!GetOne(hRSI,0,shift,rsi)) return false;
   if(UseNeutralColors){
      S.rsi_bull=(rsi>(50.0+RSI_NeutralZone));
      S.rsi_bear=(rsi<(50.0-RSI_NeutralZone));
   } else {
      S.rsi_bull=(rsi>50.0);
      S.rsi_bear=(rsi<50.0);
   }

   // LWR
   double wpr;
   if(!GetOne(hWPR,0,shift,wpr)) return false; // -100..0
   if(UseNeutralColors){
      S.lwr_bull=(wpr>(-50.0+LWR_NeutralZone));
      S.lwr_bear=(wpr<(-50.0-LWR_NeutralZone));
   } else {
      S.lwr_bull=(wpr>-50.0);
      S.lwr_bear=(wpr<-50.0);
   }

   // BBI
   double bbi;
   if(!GetBBI(shift,bbi)) return false;
   double pb=MathAbs(c0-bbi);
   double bbi_th=bbi*(BBI_NeutralPct/100.0);
   bool bbi_neu=(pb<=bbi_th);
   if(UseNeutralColors){
      S.bbi_bull=(c0>bbi)&&!bbi_neu;
      S.bbi_bear=(c0<bbi)&&!bbi_neu;
   } else {
      S.bbi_bull=(c0>bbi);
      S.bbi_bear=(c0<bbi);
   }

   // MTM
   double mtm=c0-cN;
   double mtm_th=c0*(MTM_PctThreshold/100.0);
   if(UseNeutralColors){
      S.mtm_bull=(mtm> mtm_th);
      S.mtm_bear=(mtm<-mtm_th);
   } else {
      S.mtm_bull=(mtm>0.0);
      S.mtm_bear=(mtm<0.0);
   }

   return true;
}

// Calculate score (weighted or simple count)
void CalculateScores(const SixState &S, double &bullScore, double &bearScore){
   if(UseWeightedScoring){
      bullScore = (S.macd_bull ? MACD_Weight : 0) +
                  (S.kdj_bull  ? KDJ_Weight  : 0) +
                  (S.rsi_bull  ? RSI_Weight  : 0) +
                  (S.lwr_bull  ? LWR_Weight  : 0) +
                  (S.bbi_bull  ? BBI_Weight  : 0) +
                  (S.mtm_bull  ? MTM_Weight  : 0);

      bearScore = (S.macd_bear ? MACD_Weight : 0) +
                  (S.kdj_bear  ? KDJ_Weight  : 0) +
                  (S.rsi_bear  ? RSI_Weight  : 0) +
                  (S.lwr_bear  ? LWR_Weight  : 0) +
                  (S.bbi_bear  ? BBI_Weight  : 0) +
                  (S.mtm_bear  ? MTM_Weight  : 0);
   } else {
      // Simple count
      bullScore = (int)S.macd_bull + (int)S.kdj_bull + (int)S.rsi_bull +
                  (int)S.lwr_bull + (int)S.bbi_bull + (int)S.mtm_bull;
      bearScore = (int)S.macd_bear + (int)S.kdj_bear + (int)S.rsi_bear +
                  (int)S.lwr_bear + (int)S.bbi_bear + (int)S.mtm_bear;
   }
}

// Check if signal sustained for required bars
bool IsSignalSustained(double currentScore, double threshold, bool isBull){
   if(SustainedSignalBars <= 1) return currentScore >= threshold;

   // Check history
   int sustainedCount = (currentScore >= threshold) ? 1 : 0;

   for(int i=0; i<MathMin(SustainedSignalBars-1, 10); i++){
      double histScore = isBull ? prevBullScore[i] : prevBearScore[i];
      if(histScore >= threshold) sustainedCount++;
   }

   return sustainedCount >= SustainedSignalBars;
}

// Update signal history
void UpdateSignalHistory(double bullScore, double bearScore){
   // Shift history
   for(int i=9; i>0; i--){
      prevBullScore[i] = prevBullScore[i-1];
      prevBearScore[i] = prevBearScore[i-1];
   }
   prevBullScore[0] = bullScore;
   prevBearScore[0] = bearScore;
}

// ==================== POSITION MANAGEMENT ==============================

bool HasBuyPosition(ulong &ticket){
   ticket=0;
#ifdef USE_HEDGING_INDEX_LOOP
   for(int i=PositionsTotal()-1;i>=0;i--){
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if((int)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY){
         ticket=(ulong)PositionGetInteger(POSITION_TICKET);
         return true;
      }
   }
   return false;
#else
   if(!PositionSelect(_Symbol)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return false;
   if((int)PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) return false;
   ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   return true;
#endif
}

bool HasSellPosition(ulong &ticket){
   ticket=0;
#ifdef USE_HEDGING_INDEX_LOOP
   for(int i=PositionsTotal()-1;i>=0;i--){
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if((int)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL){
         ticket=(ulong)PositionGetInteger(POSITION_TICKET);
         return true;
      }
   }
   return false;
#else
   if(!PositionSelect(_Symbol)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return false;
   if((int)PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL) return false;
   ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   return true;
#endif
}

void CloseAllForSymbolMagic(){
#ifdef USE_HEDGING_INDEX_LOOP
   for(int i=PositionsTotal()-1;i>=0;i--){
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      ulong tk=(ulong)PositionGetInteger(POSITION_TICKET);
      if(Trade.PositionClose(tk)){
         if(EnableDetailedLogging) Print("✅ Closed position #", tk);
      } else {
         Print("❌ Failed to close position #", tk, " Error: ", GetLastError());
      }
   }
#else
   if(PositionSelect(_Symbol) && (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber){
      ulong tk=(ulong)PositionGetInteger(POSITION_TICKET);
      if(Trade.PositionClose(tk)){
         if(EnableDetailedLogging) Print("✅ Closed position #", tk);
      } else {
         Print("❌ Failed to close position #", tk, " Error: ", GetLastError());
      }
   }
#endif
   lastExitTime = TimeCurrent();
}

// ===================== TRAILING STOP ===================================

void ManageTrailingStop(){
   if(!UseTrailingStop) return;
   if(TrailingStopPoints <= 0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   ulong ticket;

   // Check buy positions
   if(HasBuyPosition(ticket)){
      if(PositionSelectByTicket(ticket)){
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         double newSL = bid - TrailingStopPoints * point;

         // Only move SL up
         if(newSL > currentSL + TrailingStepPoints * point && newSL < bid){
            newSL = NormalizeDouble(newSL, digits);
            double currentTP = PositionGetDouble(POSITION_TP);

            if(Trade.PositionModify(ticket, newSL, currentTP)){
               if(EnableDetailedLogging)
                  Print("✅ Trailed BUY #", ticket, " SL to ", newSL);
            }
         }
      }
   }

   // Check sell positions
   if(HasSellPosition(ticket)){
      if(PositionSelectByTicket(ticket)){
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         double newSL = ask + TrailingStopPoints * point;

         // Only move SL down (for sell, lower is better)
         if((currentSL == 0 || newSL < currentSL - TrailingStepPoints * point) && newSL > ask){
            newSL = NormalizeDouble(newSL, digits);
            double currentTP = PositionGetDouble(POSITION_TP);

            if(Trade.PositionModify(ticket, newSL, currentTP)){
               if(EnableDetailedLogging)
                  Print("✅ Trailed SELL #", ticket, " SL to ", newSL);
            }
         }
      }
   }
}

// ===================== TRADING CORE ====================================

void TryTrade(){
   // Pre-flight checks
   if(!SpreadOK()) return;
   if(!SufficientBars()) return;
   if(!TimeFilterOK()) return;
   if(!ATRFilterOK()) return;
   if(!DrawdownOK()) return;

   // Get trend direction
   int trendDir = GetTrendDirection();

   // Compute indicators
   SixState cur, prev;
   if(!ComputeSix(1, cur)) return;   // just-closed bar
   if(!ComputeSix(2, prev)) return;  // previous bar

   double bullScoreCur, bearScoreCur, bullScorePrev, bearScorePrev;
   CalculateScores(cur, bullScoreCur, bearScoreCur);
   CalculateScores(prev, bullScorePrev, bearScorePrev);

   // Check for sustained signals
   bool bullSustained = IsSignalSustained(bullScoreCur, BuyEntryMinScore, true);
   bool bearSustained = IsSignalSustained(bearScoreCur, SellEntryMinScore, false);

   // Update history for next bar
   UpdateSignalHistory(bullScoreCur, bearScoreCur);

   // Current positions
   ulong tkB, tkS;
   bool hasBuy  = HasBuyPosition(tkB);
   bool hasSell = HasSellPosition(tkS);

   // Check cooldown period after exit
   bool cooldownActive = false;
   if(lastExitTime > 0){
      int barsSinceExit = Bars(_Symbol, _Period, lastExitTime, TimeCurrent()) - 1;
      if(barsSinceExit < EntryCooldownBars){
         cooldownActive = true;
         if(EnableDetailedLogging)
            Print("⏳ Cooldown active: ", barsSinceExit, "/", EntryCooldownBars, " bars");
      }
   }

   // ==================== EXIT LOGIC ====================
   bool shouldExitBuy  = hasBuy  && bearScoreCur >= BuyExitMinScore;
   bool shouldExitSell = hasSell && bullScoreCur >= SellExitMinScore;

   if(shouldExitBuy){
      if(EnableDetailedLogging)
         Print("🔻 EXIT BUY signal: bearScore=", bearScoreCur, " >= ", BuyExitMinScore);
      CloseAllForSymbolMagic();
      return; // Exit and wait for cooldown
   }

   if(shouldExitSell){
      if(EnableDetailedLogging)
         Print("🔺 EXIT SELL signal: bullScore=", bullScoreCur, " >= ", SellExitMinScore);
      CloseAllForSymbolMagic();
      return; // Exit and wait for cooldown
   }

   // Don't enter during cooldown
   if(cooldownActive) return;

   // ==================== ENTRY LOGIC ====================

   // Entry edge triggers
   bool buyEdge = UseEdgeTrigger ?
      (bullScoreCur >= BuyEntryMinScore && bullScorePrev < BuyEntryMinScore && bullSustained) :
      (bullScoreCur >= BuyEntryMinScore && bullSustained);

   bool sellEdge = UseEdgeTrigger ?
      (bearScoreCur >= SellEntryMinScore && bearScorePrev < SellEntryMinScore && bearSustained) :
      (bearScoreCur >= SellEntryMinScore && bearSustained);

   // Mutual exclusion: if both signals, use trend filter or skip
   if(buyEdge && sellEdge){
      if(trendDir > 0) {
         sellEdge = false; // Prefer buy in uptrend
         if(EnableDetailedLogging) Print("⚠️ Both signals active, choosing BUY (uptrend)");
      } else if(trendDir < 0) {
         buyEdge = false; // Prefer sell in downtrend
         if(EnableDetailedLogging) Print("⚠️ Both signals active, choosing SELL (downtrend)");
      } else {
         // No clear trend, skip both
         if(EnableDetailedLogging) Print("⚠️ Both signals active, no clear trend - skipping");
         return;
      }
   }

   // Apply trend filter
   if(UseTrendFilter){
      if(trendDir > 0 && sellEdge) {
         if(EnableDetailedLogging) Print("❌ SELL signal blocked by uptrend filter");
         sellEdge = false;
      }
      if(trendDir < 0 && buyEdge) {
         if(EnableDetailedLogging) Print("❌ BUY signal blocked by downtrend filter");
         buyEdge = false;
      }
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Execute BUY
   if(buyEdge && (!OneTradePerSide || !hasBuy)){
      double lots = CalculateLotSize(StopLossPoints);
      double sl=0, tp=0;

      if(StopLossPoints > 0)
         sl = NormalizeDouble(ask - StopLossPoints * point, digits);
      if(TakeProfitPoints > 0)
         tp = NormalizeDouble(ask + TakeProfitPoints * point, digits);

      Trade.SetExpertMagicNumber(MagicNumber);

      string comment = StringFormat("6Rings_BUY bull=%.1f bear=%.1f", bullScoreCur, bearScoreCur);

      if(Trade.Buy(lots, _Symbol, ask, sl, tp, comment)){
         Print("✅ BUY opened: Lots=", lots, " Score=", bullScoreCur, " SL=", sl, " TP=", tp);
      } else {
         Print("❌ BUY failed: Error=", GetLastError(), " RetCode=", Trade.ResultRetcode());
      }
   }

   // Execute SELL
   if(sellEdge && (!OneTradePerSide || !hasSell)){
      double lots = CalculateLotSize(StopLossPoints);
      double sl=0, tp=0;

      if(StopLossPoints > 0)
         sl = NormalizeDouble(bid + StopLossPoints * point, digits);
      if(TakeProfitPoints > 0)
         tp = NormalizeDouble(bid - TakeProfitPoints * point, digits);

      Trade.SetExpertMagicNumber(MagicNumber);

      string comment = StringFormat("6Rings_SELL bull=%.1f bear=%.1f", bullScoreCur, bearScoreCur);

      if(Trade.Sell(lots, _Symbol, bid, sl, tp, comment)){
         Print("✅ SELL opened: Lots=", lots, " Score=", bearScoreCur, " SL=", sl, " TP=", tp);
      } else {
         Print("❌ SELL failed: Error=", GetLastError(), " RetCode=", Trade.ResultRetcode());
      }
   }

   // ==================== STATUS PANEL ====================
   string sMac = cur.macd_bull ? "G" : (cur.macd_bear ? "R" : "-");
   string sKdj = cur.kdj_bull  ? "G" : (cur.kdj_bear  ? "R" : "-");
   string sRsi = cur.rsi_bull  ? "G" : (cur.rsi_bear  ? "R" : "-");
   string sLwr = cur.lwr_bull  ? "G" : (cur.lwr_bear  ? "R" : "-");
   string sBbi = cur.bbi_bull  ? "G" : (cur.bbi_bear  ? "R" : "-");
   string sMtm = cur.mtm_bull  ? "G" : (cur.mtm_bear  ? "R" : "-");

   string trendStr = trendDir > 0 ? "UP" : (trendDir < 0 ? "DOWN" : "NEUTRAL");

   string panel;
   panel  = "═══════════════════════════════════════════════════════════\n";
   panel += "  6 RINGS v2.0  —  " + _Symbol + "  " + EnumToString(_Period) + "\n";
   panel += "═══════════════════════════════════════════════════════════\n";
   panel += StringFormat("Bull Score: %.1f / %.1f   |   Bear Score: %.1f / %.1f\n",
                         bullScoreCur, BuyEntryMinScore, bearScoreCur, SellEntryMinScore);
   panel += "Indicators: [MACD:" + sMac + "] [KDJ:" + sKdj + "] [RSI:" + sRsi +
            "] [LWR:" + sLwr + "] [BBI:" + sBbi + "] [MTM:" + sMtm + "]\n";
   panel += "Trend Filter: " + trendStr + " (" + EnumToString(TrendTimeframe) + ")\n";
   panel += "───────────────────────────────────────────────────────────\n";
   panel += "Signals:  BUY=" + (buyEdge ? "✓" : "✗") +
            "  SELL=" + (sellEdge ? "✓" : "✗") +
            "  Cooldown=" + (cooldownActive ? "ACTIVE" : "Ready") + "\n";
   panel += "Positions: BUY=" + (hasBuy ? "OPEN" : "none") +
            "  SELL=" + (hasSell ? "OPEN" : "none") + "\n";
   panel += "───────────────────────────────────────────────────────────\n";
   panel += "Risk: " + (UseDynamicLots ? DoubleToString(RiskPercentPerTrade,1)+"%" : "Fixed") +
            "  |  Trailing: " + (UseTrailingStop ? "ON" : "OFF") +
            "  |  Halted: " + (tradingHalted ? "YES" : "NO") + "\n";
   panel += "═══════════════════════════════════════════════════════════";

   Comment(panel);
}

// ===================== EA LIFECYCLE ====================================

int OnInit(){
   // Initialize indicators
   hMACD = iMACD(_Symbol, _Period, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   hRSI  = iRSI(_Symbol, _Period, RSI_Length, PRICE_CLOSE);
   hWPR  = iWPR(_Symbol, _Period, LWR_Length);
   hStoch= iStochastic(_Symbol, _Period, KDJ_Length, KDJ_Smooth, KDJ_Smooth, MODE_SMA, STO_LOWHIGH);
   hMA1  = iMA(_Symbol, _Period, BBI_Len1, 0, MODE_SMA, PRICE_CLOSE);
   hMA2  = iMA(_Symbol, _Period, BBI_Len2, 0, MODE_SMA, PRICE_CLOSE);
   hMA3  = iMA(_Symbol, _Period, BBI_Len3, 0, MODE_SMA, PRICE_CLOSE);
   hMA4  = iMA(_Symbol, _Period, BBI_Len4, 0, MODE_SMA, PRICE_CLOSE);
   hATR  = iATR(_Symbol, _Period, ATR_Period);
   hTrendMA = iMA(_Symbol, TrendTimeframe, TrendMA_Period, 0, MODE_SMA, PRICE_CLOSE);

   // Validate handles
   if(hMACD==INVALID_HANDLE || hRSI==INVALID_HANDLE || hWPR==INVALID_HANDLE ||
      hStoch==INVALID_HANDLE || hMA1==INVALID_HANDLE || hMA2==INVALID_HANDLE ||
      hMA3==INVALID_HANDLE || hMA4==INVALID_HANDLE || hATR==INVALID_HANDLE ||
      hTrendMA==INVALID_HANDLE) {
      Print("❌ Failed to initialize indicators");
      return INIT_FAILED;
   }

   // Initialize tracking
   lastBarTime = iTime(_Symbol, _Period, 0);
   ResetDrawdownTracking();

   // Initialize signal history
   ArrayInitialize(prevBullScore, 0);
   ArrayInitialize(prevBearScore, 0);

   // Validate settings
   if(UseDynamicLots && StopLossPoints <= 0){
      Print("⚠️ Warning: Dynamic lots requires StopLossPoints > 0. Will use fixed lots.");
   }

   Print("✅ 6 Rings v2.0 initialized successfully");
   Print("   Weighted Scoring: ", UseWeightedScoring ? "ON" : "OFF");
   Print("   Dynamic Lots: ", UseDynamicLots ? "ON" : "OFF");
   Print("   Trailing Stop: ", UseTrailingStop ? "ON" : "OFF");
   Print("   Drawdown Protection: ", UseMaxDrawdown ? "ON" : "OFF");
   Print("   Trend Filter: ", UseTrendFilter ? "ON ("+EnumToString(TrendTimeframe)+")" : "OFF");
   Print("   ATR Filter: ", UseATRFilter ? "ON" : "OFF");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){
   Comment(""); // clear panel

   // Release indicators
   if(hMACD!=INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hWPR!=INVALID_HANDLE) IndicatorRelease(hWPR);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hMA1!=INVALID_HANDLE) IndicatorRelease(hMA1);
   if(hMA2!=INVALID_HANDLE) IndicatorRelease(hMA2);
   if(hMA3!=INVALID_HANDLE) IndicatorRelease(hMA3);
   if(hMA4!=INVALID_HANDLE) IndicatorRelease(hMA4);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hTrendMA!=INVALID_HANDLE) IndicatorRelease(hTrendMA);

   Print("✅ 6 Rings v2.0 deinitialized. Reason: ", reason);
}

void OnTick(){
   // Check for new bar
   if(TradeOnlyOnNewBar && !NewBar()) {
      ManageTrailingStop(); // Still manage trailing even between bars
      return;
   }

   // Reset daily/weekly tracking if needed
   ResetDrawdownTracking();

   // Execute trading logic
   TryTrade();

   // Manage trailing stops
   ManageTrailingStop();
}
