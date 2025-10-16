//+------------------------------------------------------------------+
//|                                                HybridGridEA      |
//| Robust grid EA using RangeHybrid + Supertrend + Squeeze Index    |
//| (Adjusted: dynamic grid step fix & OrderDelete checks)           |
//+------------------------------------------------------------------+
#property strict

//---------------- General inputs ----------------
input string   EA_Tag                 = "RHGridEA";
input int      MagicNumber            = 8642001;
input double   FixedLot               = 0.10;
input double   MaxLotsPerSide         = 5.0;
input int      MaxOrdersPerSide       = 20;
input double   SlippagePoints         = 10;
input bool     AllowHedge             = true;
input bool     AllowNewTrades         = true;

//---------------- RangeHybrid selection ----------------
enum eRangeSource { Range_Window=0, Range_Structural=1, Range_Envelope=2 };
input eRangeSource RangeSource        = Range_Structural;

// RangeHybrid parameters (must match indicator inputs order)
input int   RH_WindowBars             = 100;
input bool  RH_UseCompletedBars       = true;
input bool  RH_ShowWindowHistorical   = false;
input bool  RH_ShowWindowLines        = true;
input bool  RH_ShowWindowCenter       = true;
input int   RH_ZZ_Depth               = 12;
input int   RH_ZZ_DeviationPoints     = 5;
input int   RH_ZZ_Backstep            = 3;
enum eStructMode { AlwaysUpdate=0, LockUntilBreakout=1 };
input eStructMode RH_StructMode       = LockUntilBreakout;
enum eDrawFrom { LaterPivotToNow=0, OlderPivotToNow=1 };
input eDrawFrom RH_DrawFrom           = LaterPivotToNow;
input bool  RH_ShowStructuralLines    = true;
input bool  RH_ShowStructuralCenter   = true;
input bool  RH_ShowEnvelopeLines      = true;
input bool  RH_ShowEnvelopeCenter     = true;
input int   RH_EnvelopeLookbackBars   = 500;
input bool  RH_EnvelopeFallbackToPrice= true;

//---------------- Grid building ----------------
enum eGridMode { Grid_Reversion_Limit=0, Grid_Breakout_Stop=1 };
input eGridMode GridMode              = Grid_Reversion_Limit;
input int       GridLevelsEachSide    = 6;
input int       GridStepPoints        = 150;   // Input constant (not modified at runtime)
input int       EntryBufferPoints     = 5;
input bool      AutoGridStepFromRange = false;
input double    AutoStepDivisor       = 10.0;

// Re-centering
input bool   RecenterWhenRangeShifts  = true;
input double RecenterThresholdPct     = 15.0;

//---------------- Trend Signal (Supertrend) ----------------
input bool            UseTrendFilter  = true;
input ENUM_TIMEFRAMES TrendTF         = PERIOD_H1;
input int             ST_ATR_Period   = 10;
input double          ST_Factor       = 3.0;

//---------------- Squeeze Signal ----------------
input bool            UseSqueezeFilter= true;
input ENUM_TIMEFRAMES SqueezeTF       = PERIOD_H1;
input int             SQ_ConvFactor   = 50;
input int             SQ_Length       = 20;
input double          SQ_AllowBelow   = 80.0;
input bool            SQ_RequireReleaseCross = false;

//---------------- Basket Breakeven & TP ----------------
input bool   UseBasketBreakeven       = true;
input double BasketBE_ProfitMoney     = 10.0;
input double BasketBE_ProfitPercent   = 0.0;
input bool   BasketBE_SameDirection   = true;
input bool   BasketBE_CrossDirection  = true;

input bool   UsePerOrderTP            = true;
input int    PerOrderTP_InPoints      = 300;
input bool   TP_ToNextGridLevel       = true;

//---------------- Global risk/safety ----------------
input double MaxTotalDDPercent        = 25.0;
input bool   CloseAllOnMaxDD          = false;

//---------------- Internal state ----------------
datetime     g_lastRecenterTime = 0;
double       g_prevCenter       = 0.0;
double       g_prevRangeHigh    = 0.0;
double       g_prevRangeLow     = 0.0;

double       g_rangeTop=0, g_rangeBot=0, g_rangeCenter=0;

// *** MOD start: runtime grid step variable
int          g_currentStepPoints = 0;
// *** MOD end

int DigitsAdjust = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   DigitsAdjust = (int)MarketInfo(Symbol(), MODE_DIGITS);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!AllowNewTrades && OrdersTotal()==0) return;

   // Safety: Max DD
   if(MaxTotalDDPercent > 0)
   {
      double eq  = AccountEquity();
      double bal = AccountBalance();
      if(bal > 0)
      {
         double ddPct = 100.0 * (bal - eq) / bal;
         if(ddPct >= MaxTotalDDPercent)
         {
            if(CloseAllOnMaxDD) CloseAllPositions();
            return;
         }
      }
   }

   // 1) Update signals
   if(!UpdateRangeHybrid()) return;
   int trendDir = GetTrendDirection();
   bool tradeAllowedBySqueeze = CheckSqueezeGate();

   // *** MOD start: compute dynamic step (once per tick)
   g_currentStepPoints = CurrentGridStepPoints();
   // *** MOD end

   // 2) Recenter logic
   if(RecenterWhenRangeShifts) MaybeRecenter();

   // 3) Build grid
   double levelsBuy[128], levelsSell[128];
   int buyCount = 0, sellCount = 0;
   BuildGridLevels(g_rangeCenter, g_rangeTop, g_rangeBot, levelsBuy, buyCount, levelsSell, sellCount);

   // 4) Manage new entries
   if(AllowNewTrades && tradeAllowedBySqueeze)
   {
      if(trendDir != 0 || !UseTrendFilter)
         ManageEntries(trendDir, levelsBuy, buyCount, levelsSell, sellCount);
   }

   // 5) Basket management
   if(UseBasketBreakeven) TryBasketBreakeven();
}

//+------------------------------------------------------------------+
//| Dynamic grid step helper (replaces assignment to input)          |
//+------------------------------------------------------------------+
int CurrentGridStepPoints()
{
   double height = g_rangeTop - g_rangeBot;
   if(AutoGridStepFromRange && height > 0.0 && AutoStepDivisor > 0.0)
      return MathMax(1, (int)MathRound((height / AutoStepDivisor) / Point));
   return GridStepPoints;
}

//+------------------------------------------------------------------+
//| Update RangeHybrid via iCustom                                   |
//+------------------------------------------------------------------+
bool UpdateRangeHybrid()
{
   int tf = Period();
   double top=0, bot=0, mid=0;
   int bTop=0, bBot=1, bMid=2;

   int StructModeInt = (int)RH_StructMode;
   int DrawFromInt   = (int)RH_DrawFrom;

   switch(RangeSource)
   {
      case Range_Window:     bTop=0; bBot=1; bMid=2; break;
      case Range_Structural: bTop=3; bBot=4; bMid=5; break;
      case Range_Envelope:   bTop=6; bBot=7; bMid=8; break;
   }

   top = iCustom(Symbol(), tf, "RangeHybrid",
                 RH_WindowBars, RH_UseCompletedBars, RH_ShowWindowHistorical, RH_ShowWindowLines, RH_ShowWindowCenter,
                 RH_ZZ_Depth, RH_ZZ_DeviationPoints, RH_ZZ_Backstep, StructModeInt, DrawFromInt,
                 RH_ShowStructuralLines, RH_ShowStructuralCenter,
                 RH_ShowEnvelopeLines, RH_ShowEnvelopeCenter, RH_EnvelopeLookbackBars, RH_EnvelopeFallbackToPrice,
                 bTop, 0);

   bot = iCustom(Symbol(), tf, "RangeHybrid",
                 RH_WindowBars, RH_UseCompletedBars, RH_ShowWindowHistorical, RH_ShowWindowLines, RH_ShowWindowCenter,
                 RH_ZZ_Depth, RH_ZZ_DeviationPoints, RH_ZZ_Backstep, StructModeInt, DrawFromInt,
                 RH_ShowStructuralLines, RH_ShowStructuralCenter,
                 RH_ShowEnvelopeLines, RH_ShowEnvelopeCenter, RH_EnvelopeLookbackBars, RH_EnvelopeFallbackToPrice,
                 bBot, 0);

   mid = iCustom(Symbol(), tf, "RangeHybrid",
                 RH_WindowBars, RH_UseCompletedBars, RH_ShowWindowHistorical, RH_ShowWindowLines, RH_ShowWindowCenter,
                 RH_ZZ_Depth, RH_ZZ_DeviationPoints, RH_ZZ_Backstep, StructModeInt, DrawFromInt,
                 RH_ShowStructuralLines, RH_ShowStructuralCenter,
                 RH_ShowEnvelopeLines, RH_ShowEnvelopeCenter, RH_EnvelopeLookbackBars, RH_EnvelopeFallbackToPrice,
                 bMid, 0);

   if(!MathIsValidNumber(top) || !MathIsValidNumber(bot) || !MathIsValidNumber(mid)) return false;
   if(top <= bot) return false;

   g_rangeTop    = top;
   g_rangeBot    = bot;
   g_rangeCenter = mid;
   return true;
}

//+------------------------------------------------------------------+
//| Trend direction from Supertrend                                  |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   if(!UseTrendFilter) return 0;
   double up  = iCustom(Symbol(), TrendTF, "Supertrend_tv_clone", ST_ATR_Period, ST_Factor, 0, 0);
   double down= iCustom(Symbol(), TrendTF, "Supertrend_tv_clone", ST_ATR_Period, ST_Factor, 1, 0);
   bool upActive   = MathIsValidNumber(up)   && up   != EMPTY_VALUE;
   bool downActive = MathIsValidNumber(down) && down != EMPTY_VALUE;

   if(upActive && !downActive)  return +1;
   if(downActive && !upActive)  return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Squeeze gating                                                   |
//+------------------------------------------------------------------+
bool CheckSqueezeGate()
{
   if(!UseSqueezeFilter) return true;
   double psi0 = GetSqueezePSI(0);
   if(!MathIsValidNumber(psi0)) return false;

   if(!SQ_RequireReleaseCross)
      return (psi0 < SQ_AllowBelow);
   double psi1 = GetSqueezePSI(1);
   return (psi1 > SQ_AllowBelow && psi0 < SQ_AllowBelow);
}

double GetSqueezePSI(int shift)
{
   double a = iCustom(Symbol(), SqueezeTF, "SqueezeIndex", SQ_ConvFactor, SQ_Length, PRICE_CLOSE, 0, shift);
   double b = iCustom(Symbol(), SqueezeTF, "SqueezeIndex", SQ_ConvFactor, SQ_Length, PRICE_CLOSE, 1, shift);
   double psi = EMPTY_VALUE;
   if(MathIsValidNumber(a) && a != EMPTY_VALUE) psi = a;
   if(MathIsValidNumber(b) && b != EMPTY_VALUE) psi = b;
   return psi;
}

//+------------------------------------------------------------------+
//| Recenter logic                                                   |
//+------------------------------------------------------------------+
void MaybeRecenter()
{
   if(g_prevRangeHigh == 0.0 && g_prevRangeLow == 0.0)
   {
      g_prevRangeHigh = g_rangeTop;
      g_prevRangeLow  = g_rangeBot;
      g_prevCenter    = g_rangeCenter;
      g_lastRecenterTime = TimeCurrent();
      return;
   }
   double oldHeight = g_prevRangeHigh - g_prevRangeLow;
   if(oldHeight <= Point) oldHeight = Point;
   double centerShiftPct = 100.0 * MathAbs(g_rangeCenter - g_prevCenter) / oldHeight;
   if(centerShiftPct >= RecenterThresholdPct)
   {
      CancelPendingOrders();
      g_prevRangeHigh = g_rangeTop;
      g_prevRangeLow  = g_rangeBot;
      g_prevCenter    = g_rangeCenter;
      g_lastRecenterTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Build grid levels (no modification of input variable)            |
//+------------------------------------------------------------------+
void BuildGridLevels(double center, double top, double bot,
                     double &levelsBuy[], int &buyCount,
                     double &levelsSell[], int &sellCount)
{
   buyCount = 0; sellCount = 0;

   // *** MOD start: use runtime step
   int step = g_currentStepPoints;
   if(step < 1) step = 1;
   // *** MOD end

   for(int k=1; k<=GridLevelsEachSide && (buyCount < ArraySize(levelsBuy)) && (sellCount < ArraySize(levelsSell)); ++k)
   {
      double buyLvl  = center - k * step * Point;
      double sellLvl = center + k * step * Point;
      if(buyLvl >= bot)   levelsBuy[buyCount++]   = buyLvl;
      if(sellLvl <= top)  levelsSell[sellCount++] = sellLvl;
   }
}

//+------------------------------------------------------------------+
//| Entry management                                                 |
//+------------------------------------------------------------------+
void ManageEntries(int trendDir, double &levelsBuy[], int buyCount, double &levelsSell[], int sellCount)
{
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   if(bid == 0 || ask == 0) { bid=Bid; ask=Ask; }

   int buyOpenCount=0, sellOpenCount=0, buyPendCount=0, sellPendCount=0;
   CountOrders(buyOpenCount, sellOpenCount, buyPendCount, sellPendCount);

   if(AllowSide(+1, trendDir) && CountSide(+1,buyOpenCount,buyPendCount) < MaxOrdersPerSide)
   {
      for(int i=0;i<buyCount;i++)
      {
         double lvl = levelsBuy[i];
         if(GridMode == Grid_Reversion_Limit)
         {
            if(bid > lvl && !HasPendingAtPrice(+1, lvl))
               PlacePending(+1, OP_BUYLIMIT, lvl);
         }
         else
         {
            double trig = lvl + EntryBufferPoints*Point;
            if(ask < trig && !HasPendingAtPrice(+1, trig))
               PlacePending(+1, OP_BUYSTOP, trig);
         }
      }
   }

   if(AllowSide(-1, trendDir) && CountSide(-1,sellOpenCount,sellPendCount) < MaxOrdersPerSide)
   {
      for(int j=0;j<sellCount;j++)
      {
         double lvl = levelsSell[j];
         if(GridMode == Grid_Reversion_Limit)
         {
            if(ask < lvl && !HasPendingAtPrice(-1, lvl))
               PlacePending(-1, OP_SELLLIMIT, lvl);
         }
         else
         {
            double trig = lvl - EntryBufferPoints*Point;
            if(bid > trig && !HasPendingAtPrice(-1, trig))
               PlacePending(-1, OP_SELLSTOP, trig);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool AllowSide(int side, int trendDir)
{
   if(!UseTrendFilter) return true;
   if(trendDir==0) return false;
   return (side == trendDir) || AllowHedge;
}

int CountSide(int side, int openCnt, int pendCnt)
{
   return openCnt + pendCnt;
}

void CountOrders(int &buyOpen, int &sellOpen, int &buyPend, int &sellPend)
{
   buyOpen=sellOpen=buyPend=sellPend=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int type = OrderType();
      if(type==OP_BUY)  buyOpen++;
      if(type==OP_SELL) sellOpen++;
      if(type==OP_BUYLIMIT || type==OP_BUYSTOP) buyPend++;
      if(type==OP_SELLLIMIT|| type==OP_SELLSTOP) sellPend++;
   }
}

bool HasPendingAtPrice(int side, double price)
{
   int t1 = (side>0)?OP_BUYLIMIT:OP_SELLLIMIT;
   int t2 = (side>0)?OP_BUYSTOP :OP_SELLSTOP;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==t1 || type==t2)
         if(MathAbs(OrderOpenPrice()-price) <= (EntryBufferPoints*Point)) return true;
   }
   return false;
}

bool PlacePending(int side, int ordType, double price)
{
   double lot = FixedLot;
   int step   = g_currentStepPoints;
   if(step < 1) step = 1;

   double tp  = 0.0;
   if(TP_ToNextGridLevel)
      tp = (side>0) ? price + step*Point : price - step*Point;
   else if(UsePerOrderTP && PerOrderTP_InPoints>0)
      tp = (side>0) ? price + PerOrderTP_InPoints*Point : price - PerOrderTP_InPoints*Point;

   double sl=0.0; // optional future enhancement

   int    cmd = ordType;
   double slippage = SlippagePoints;
   color  clr = (side>0)?clrLime:clrRed;

   int ticket = OrderSend(Symbol(), cmd, lot, NormalizeDouble(price, DigitsAdjust),
                          (int)slippage, sl, tp, EA_Tag, MagicNumber, 0, clr);
   if(ticket<0) { Print("OrderSend failed ", GetLastError()); return false; }
   return true;
}

void CancelPendingOrders()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==OP_BUYLIMIT || type==OP_BUYSTOP || type==OP_SELLLIMIT || type==OP_SELLSTOP)
      {
         if(!OrderDelete(OrderTicket()))
            Print("OrderDelete (cancel pending) failed. Ticket=",OrderTicket()," Err=",GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Basket breakeven logic                                           |
//+------------------------------------------------------------------+
void TryBasketBreakeven()
{
   double eq = AccountEquity();
   double netProfit = 0.0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==OP_BUY || type==OP_SELL)
         netProfit += OrderProfit()+OrderSwap()+OrderCommission();
   }

   bool moneyOK = (BasketBE_ProfitMoney>0 && netProfit >= BasketBE_ProfitMoney);
   bool pctOK   = (BasketBE_ProfitPercent>0 && eq>0 && (100.0*netProfit/eq)>=BasketBE_ProfitPercent);
   if(!(moneyOK || pctOK)) return;

   // Simplified: close all positions for this symbol/magic when threshold met
   CloseAllPositions();
}

void CloseAllPositions()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int type = OrderType();
      if(type==OP_BUY)
      {
         if(!OrderClose(OrderTicket(), OrderLots(), Bid, (int)SlippagePoints, clrAqua))
            Print("OrderClose BUY failed ", GetLastError());
      }
      else if(type==OP_SELL)
      {
         if(!OrderClose(OrderTicket(), OrderLots(), Ask, (int)SlippagePoints, clrAqua))
            Print("OrderClose SELL failed ", GetLastError());
      }
      else
      {
         if(!OrderDelete(OrderTicket()))
            Print("OrderDelete (close all) failed. Ticket=",OrderTicket()," Err=",GetLastError());
      }
   }
}
//+------------------------------------------------------------------+