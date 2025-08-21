#property strict
#include <Trade/Trade.mqh>

// ---------------- Display / Logic Modes ----------------
input bool   UseNeutralColors         = false;     // true: 3-color (strong/neutral)  | false: classic 2-color

// ---------------- Indicator Parameters -----------------
// MACD
input int    MACD_Fast                = 12;
input int    MACD_Slow                = 26;
input int    MACD_Signal              = 9;
input double MACD_NeutralThreshold    = 0.001;     // |MACD - Signal|

// KDJ (Stochastic smoothed)
input int    KDJ_Length               = 9;
input int    KDJ_Smooth               = 3;         // used for slowing and D period

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

// MTM
input int    MTM_Length               = 12;        // close - close[n]
input double MTM_PctThreshold         = 0.5;       // 0.5% of price

// --------------- Count-based Entry / Exit ---------------
input int    BuyEntryMinGreen         = 6;         // X: greens >= X => consider BUY entry
input int    BuyExitMinRed            = 6;         // Y: reds   >= Y => close ALL (any side)
input int    SellEntryMinRed          = 6;         // X: reds   >= X => consider SELL entry
input int    SellExitMinGreen         = 6;         // Y: greens >= Y => close ALL (any side)
input bool   UseEdgeTrigger           = true;      // only act when count crosses the threshold vs previous bar

// ------------------- Trading Settings -------------------
input double Lots                     = 0.10;
input int    StopLossPoints           = 0;         // 0 = no SL
input int    TakeProfitPoints         = 0;         // 0 = no TP
input ulong  MagicNumber              = 6600066;
input bool   OneTradePerSide          = true;      // avoid multiple same-direction positions
input int    MaxSpreadPoints          = 150;       // 0 = ignore
input bool   TradeOnlyOnNewBar        = true;

// ----------------------- Globals ------------------------
CTrade Trade;
int hMACD=INVALID_HANDLE, hRSI=INVALID_HANDLE, hWPR=INVALID_HANDLE, hStoch=INVALID_HANDLE;
int hMA1=INVALID_HANDLE, hMA2=INVALID_HANDLE, hMA3=INVALID_HANDLE, hMA4=INVALID_HANDLE;
datetime lastBarTime=0;

struct SixState {
   bool macd_bull, macd_bear;
   bool kdj_bull,  kdj_bear;
   bool rsi_bull,  rsi_bear;
   bool lwr_bull,  lwr_bear;
   bool bbi_bull,  bbi_bear;
   bool mtm_bull,  mtm_bear;
};

// ------------------- Small helpers ----------------------
bool GetOne(const int handle,const int buffer,const int shift,double &val){
   double a[]; if(CopyBuffer(handle, buffer, shift, 1, a)!=1) return false; val=a[0]; return true;
}
bool NewBar(){
   datetime t=iTime(_Symbol,_Period,0);
   if(t==lastBarTime) return false;
   lastBarTime=t; return true;
}
bool SpreadOK(){
   int spr=(int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return MaxSpreadPoints<=0 || spr<=MaxSpreadPoints;
}
bool GetKDJ(int shift,double &K,double &D,double &J){
   if(!GetOne(hStoch,0,shift,K)) return false;
   if(!GetOne(hStoch,1,shift,D)) return false;
   J=3.0*K-2.0*D; return true;
}
bool GetBBI(int shift,double &bbi){
   double m1,m2,m3,m4;
   if(!GetOne(hMA1,0,shift,m1)) return false;
   if(!GetOne(hMA2,0,shift,m2)) return false;
   if(!GetOne(hMA3,0,shift,m3)) return false;
   if(!GetOne(hMA4,0,shift,m4)) return false;
   bbi=(m1+m2+m3+m4)/4.0; return true;
}

// core computation
bool ComputeSix(int shift,SixState &S){
   double c0=iClose(_Symbol,_Period,shift);
   double cN=iClose(_Symbol,_Period,shift+MTM_Length);
   if(c0==0.0 || cN==0.0) return false;

   // MACD
   double macd_main,macd_sig;
   if(!GetOne(hMACD,0,shift,macd_main)) return false;
   if(!GetOne(hMACD,1,shift,macd_sig )) return false;
   double macd_diff=MathAbs(macd_main-macd_sig);
   bool macd_neu=(macd_diff<=MACD_NeutralThreshold);
   if(UseNeutralColors){ S.macd_bull=(macd_main>macd_sig)&&!macd_neu; S.macd_bear=(macd_main<macd_sig)&&!macd_neu; }
   else{ S.macd_bull=(macd_main>macd_sig); S.macd_bear=(macd_main<macd_sig); }

   // KDJ
   double K,D,J; if(!GetKDJ(shift,K,D,J)) return false;
   double kd=MathAbs(K-D); bool kdj_neu=(kd<=2.0);
   if(UseNeutralColors){ S.kdj_bull=(K>D)&&!kdj_neu; S.kdj_bear=(K<D)&&!kdj_neu; }
   else{ S.kdj_bull=(K>D); S.kdj_bear=(K<D); }

   // RSI
   double rsi; if(!GetOne(hRSI,0,shift,rsi)) return false;
   if(UseNeutralColors){ S.rsi_bull=(rsi>(50.0+RSI_NeutralZone)); S.rsi_bear=(rsi<(50.0-RSI_NeutralZone)); }
   else{ S.rsi_bull=(rsi>50.0); S.rsi_bear=(rsi<50.0); }

   // LWR
   double wpr; if(!GetOne(hWPR,0,shift,wpr)) return false; // -100..0
   if(UseNeutralColors){ S.lwr_bull=(wpr>(-50.0+LWR_NeutralZone)); S.lwr_bear=(wpr<(-50.0-LWR_NeutralZone)); }
   else{ S.lwr_bull=(wpr>-50.0); S.lwr_bear=(wpr<-50.0); }

   // BBI
   double bbi; if(!GetBBI(shift,bbi)) return false;
   double pb=MathAbs(c0-bbi); double bbi_th=bbi*0.002; bool bbi_neu=(pb<=bbi_th);
   if(UseNeutralColors){ S.bbi_bull=(c0>bbi)&&!bbi_neu; S.bbi_bear=(c0<bbi)&&!bbi_neu; }
   else{ S.bbi_bull=(c0>bbi); S.bbi_bear=(c0<bbi); }

   // MTM
   double mtm=c0-cN; double mtm_th=c0*(MTM_PctThreshold/100.0);
   if(UseNeutralColors){ S.mtm_bull=(mtm> mtm_th); S.mtm_bear=(mtm<-mtm_th); }
   else{ S.mtm_bull=(mtm>0.0); S.mtm_bear=(mtm<0.0); }

   return true;
}

void CountBullBear(const SixState &S,int &greens,int &reds){
   greens= (int)S.macd_bull + (int)S.kdj_bull + (int)S.rsi_bull + (int)S.lwr_bull + (int)S.bbi_bull + (int)S.mtm_bull;
   reds  = (int)S.macd_bear + (int)S.kdj_bear + (int)S.rsi_bear + (int)S.lwr_bear + (int)S.bbi_bear + (int)S.mtm_bear;
}

// -------- position helpers (netting by default; hedging behind switch) ----
bool HasBuyPosition(ulong &ticket){
   ticket=0;
#ifdef USE_HEDGING_INDEX_LOOP
   for(int i=PositionsTotal()-1;i>=0;i--){
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if((int)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY){
         ticket=(ulong)PositionGetInteger(POSITION_TICKET); return true;
      }
   }
   return false;
#else
   if(!PositionSelect(_Symbol)) return false; // netting: one position per symbol
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return false;
   if((int)PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) return false;
   ticket=(ulong)PositionGetInteger(POSITION_TICKET); return true;
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
         ticket=(ulong)PositionGetInteger(POSITION_TICKET); return true;
      }
   }
   return false;
#else
   if(!PositionSelect(_Symbol)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return false;
   if((int)PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL) return false;
   ticket=(ulong)PositionGetInteger(POSITION_TICKET); return true;
#endif
}

void CloseAllForSymbolMagic(){
#ifdef USE_HEDGING_INDEX_LOOP
   for(int i=PositionsTotal()-1;i>=0;i--){
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      ulong tk=(ulong)PositionGetInteger(POSITION_TICKET);
      Trade.PositionClose(tk);
   }
#else
   if(PositionSelect(_Symbol) && (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber){
      ulong tk=(ulong)PositionGetInteger(POSITION_TICKET);
      Trade.PositionClose(tk);
   }
#endif
}

// --------------------------- Trading core ---------------------------
void TryTrade(){
   if(!SpreadOK()) return;

   SixState cur, prev;
   if(!ComputeSix(1,cur))  return;  // just-closed bar
   if(!ComputeSix(2,prev)) return;

   int gCur,rCur,gPrev,rPrev;
   CountBullBear(cur, gCur, rCur);
   CountBullBear(prev, gPrev, rPrev);

   // -------------------- Exit priority --------------------
   bool exitOnRedForBuy    = (rCur >= BuyExitMinRed);
   bool exitOnGreenForSell = (gCur >= SellExitMinGreen);
   if(exitOnRedForBuy || exitOnGreenForSell) {
      CloseAllForSymbolMagic();
   }

   // -------------------- Entry conditions -----------------
   bool buyEdge  = UseEdgeTrigger ? (gCur >= BuyEntryMinGreen  && gPrev < BuyEntryMinGreen) : (gCur >= BuyEntryMinGreen);
   bool sellEdge = UseEdgeTrigger ? (rCur >= SellEntryMinRed   && rPrev < SellEntryMinRed)  : (rCur >= SellEntryMinRed);

   ulong tkB, tkS;
   bool hasBuy  = HasBuyPosition(tkB);
   bool hasSell = HasSellPosition(tkS);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buyEdge && (!OneTradePerSide || !hasBuy)){
      double sl=0,tp=0;
      if(StopLossPoints>0) sl=NormalizeDouble(ask-StopLossPoints*_Point,_Digits);
      if(TakeProfitPoints>0) tp=NormalizeDouble(ask+TakeProfitPoints*_Point,_Digits);
      Trade.SetExpertMagicNumber(MagicNumber);
      Trade.Buy(Lots, _Symbol, ask, sl, tp, "Hamster6Rings BUY g="+(string)gCur+"/r="+(string)rCur);
   }
   if(sellEdge && (!OneTradePerSide || !hasSell)){
      double sl=0,tp=0;
      if(StopLossPoints>0) sl=NormalizeDouble(bid+StopLossPoints*_Point,_Digits);
      if(TakeProfitPoints>0) tp=NormalizeDouble(bid-TakeProfitPoints*_Point,_Digits);
      Trade.SetExpertMagicNumber(MagicNumber);
      Trade.Sell(Lots, _Symbol, bid, sl, tp, "Hamster6Rings SELL g="+(string)gCur+"/r="+(string)rCur);
   }

   // -------------------- Comment Panel --------------------
   string sMac = cur.macd_bull?"G":(cur.macd_bear?"R":"-");
   string sKdj = cur.kdj_bull?"G":(cur.kdj_bear?"R":"-");
   string sRsi = cur.rsi_bull?"G":(cur.rsi_bear?"R":"-");
   string sLwr = cur.lwr_bull?"G":(cur.lwr_bear?"R":"-");
   string sBbi = cur.bbi_bull?"G":(cur.bbi_bear?"R":"-");
   string sMtm = cur.mtm_bull?"G":(cur.mtm_bear?"R":"-");

   bool armBuy  = (gCur >= BuyEntryMinGreen);
   bool armSell = (rCur >= SellEntryMinRed);
   bool armExitByRed   = (rCur >= BuyExitMinRed);
   bool armExitByGreen = (gCur >= SellExitMinGreen);

   string panel;
   panel  = "Hamster 6 Rings  —  " + _Symbol + "  " + EnumToString(_Period) + "\n";
   panel += "Greens: " + (string)gCur + "   Reds: " + (string)rCur + "\n";
   panel += "Modules: [MACD " + sMac + "] [KDJ " + sKdj + "] [RSI " + sRsi + "] [LWR " + sLwr + "] [BBI " + sBbi + "] [MTM " + sMtm + "]\n";
   panel += "Entry X: Buy≥" + (string)BuyEntryMinGreen + " | Sell≥" + (string)SellEntryMinRed +
            "    Exit Y: CloseIf Red≥" + (string)BuyExitMinRed + " or Green≥" + (string)SellExitMinGreen + "\n";
   panel += "Armed:  Buy=" + (armBuy?"YES":"no") + "  Sell=" + (armSell?"YES":"no") +
            "  ExitByRed=" + (armExitByRed?"YES":"no") + "  ExitByGreen=" + (armExitByGreen?"YES":"no");
   Comment(panel);
}

// --------------------- EA lifecycle ---------------------
int OnInit(){
   hMACD = iMACD(_Symbol,_Period,MACD_Fast,MACD_Slow,MACD_Signal,PRICE_CLOSE);
   hRSI  = iRSI (_Symbol,_Period,RSI_Length,PRICE_CLOSE);
   hWPR  = iWPR (_Symbol,_Period,LWR_Length);
   hStoch= iStochastic(_Symbol,_Period,KDJ_Length,KDJ_Smooth,KDJ_Smooth,MODE_SMA,STO_LOWHIGH);
   hMA1  = iMA(_Symbol,_Period,BBI_Len1,0,MODE_SMA,PRICE_CLOSE);
   hMA2  = iMA(_Symbol,_Period,BBI_Len2,0,MODE_SMA,PRICE_CLOSE);
   hMA3  = iMA(_Symbol,_Period,BBI_Len3,0,MODE_SMA,PRICE_CLOSE);
   hMA4  = iMA(_Symbol,_Period,BBI_Len4,0,MODE_SMA,PRICE_CLOSE);

   if(hMACD==INVALID_HANDLE || hRSI==INVALID_HANDLE || hWPR==INVALID_HANDLE ||
      hStoch==INVALID_HANDLE || hMA1==INVALID_HANDLE || hMA2==INVALID_HANDLE ||
      hMA3==INVALID_HANDLE || hMA4==INVALID_HANDLE) return INIT_FAILED;

   lastBarTime=iTime(_Symbol,_Period,0);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int){
   Comment(""); // clear panel
   if(hMACD!=INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hRSI !=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hWPR !=INVALID_HANDLE) IndicatorRelease(hWPR);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hMA1 !=INVALID_HANDLE) IndicatorRelease(hMA1);
   if(hMA2 !=INVALID_HANDLE) IndicatorRelease(hMA2);
   if(hMA3 !=INVALID_HANDLE) IndicatorRelease(hMA3);
   if(hMA4 !=INVALID_HANDLE) IndicatorRelease(hMA4);
}
void OnTick(){
   if(TradeOnlyOnNewBar && !NewBar()) return;
   if(Bars(_Symbol,_Period) < MathMax(MTM_Length+10, 200)) return;
   TryTrade();
}
