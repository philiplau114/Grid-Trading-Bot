//+------------------------------------------------------------------+
//|                                         HybridGridEA_visual.mq4  |
//| RangeHybrid Grid EA with visual audit overlays:                  |
//|  - Dynamic grid (same logic as previous HybridGridEA)            |
//|  - Optional drawing: selected range lines, grid levels           |
//|  - Trade open/close markers and connecting lines                 |
//|  - Historical range snapshot pre-recenter (optional)             |
//|  - Reason labels for entries                                     |
//|                                                                  |
//| NOTE: To see indicator plots (RangeHybrid, Supertrend,           |
//|       SqueezeIndex) in Strategy Tester visual mode:              |
//|       Create a template 'tester.tpl' containing them.            |
//+------------------------------------------------------------------+
#property strict

/******************** ORIGINAL LOGIC INPUTS (unchanged) ********************/
input string   EA_Tag                 = "RHGridEA";
input int      MagicNumber            = 8642001;
input double   FixedLot               = 0.10;
input double   MaxLotsPerSide         = 5.0;
input int      MaxOrdersPerSide       = 20;
input double   SlippagePoints         = 10;
input bool     AllowHedge             = true;
input bool     AllowNewTrades         = true;

enum eRangeSource { Range_Window=0, Range_Structural=1, Range_Envelope=2 };
input eRangeSource RangeSource        = Range_Structural;

// RangeHybrid inputs (MUST match indicator signature order)
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

enum eGridMode { Grid_Reversion_Limit=0, Grid_Breakout_Stop=1 };
input eGridMode GridMode              = Grid_Reversion_Limit;
input int       GridLevelsEachSide    = 6;
input int       GridStepPoints        = 150;
input int       EntryBufferPoints     = 5;
input bool      AutoGridStepFromRange = false;
input double    AutoStepDivisor       = 10.0;

input bool   RecenterWhenRangeShifts  = true;
input double RecenterThresholdPct     = 15.0;

input bool            UseTrendFilter  = true;
input ENUM_TIMEFRAMES TrendTF         = PERIOD_H1;
input int             ST_ATR_Period   = 10;
input double          ST_Factor       = 3.0;

input bool            UseSqueezeFilter= true;
input ENUM_TIMEFRAMES SqueezeTF       = PERIOD_H1;
input int             SQ_ConvFactor   = 50;
input int             SQ_Length       = 20;
input double          SQ_AllowBelow   = 80.0;
input bool            SQ_RequireReleaseCross = false;

input bool   UseBasketBreakeven       = true;
input double BasketBE_ProfitMoney     = 10.0;
input double BasketBE_ProfitPercent   = 0.0;
input bool   BasketBE_SameDirection   = true;
input bool   BasketBE_CrossDirection  = true;

input bool   UsePerOrderTP            = true;
input int    PerOrderTP_InPoints      = 300;
input bool   TP_ToNextGridLevel       = true;

input double MaxTotalDDPercent        = 25.0;
input bool   CloseAllOnMaxDD          = false;

/******************** NEW VISUAL / DEBUG INPUTS ****************************/
input group "Visual Debug"
input bool ShowVisualDebug            = true;
input bool DrawRangeLines             = true;     // Selected RangeSource lines
input bool KeepHistoricalRangeMarks   = true;     // Snapshot old lines at recenter
input bool DrawGridLevels             = true;
input bool ShowTradeMarkers           = true;
input bool ShowOrderCommentsOnChart   = true;
input color ColRangeTop               = clrMaroon;
input color ColRangeBot               = clrDarkGreen;
input color ColRangeCenter            = clrDimGray;
input color ColRangeOld               = clrGray;
input color ColGridBuy                = clrLime;
input color ColGridSell               = clrRed;
input color ColTradeBuyOpen           = clrLime;
input color ColTradeSellOpen          = clrRed;
input color ColTradeClose             = clrSilver;
input color ColTradeLine              = clrDodgerBlue;
input bool  CleanOnDeinit             = true;

//---------------- Internal runtime vars ----------------
datetime     g_lastRecenterTime = 0;
double       g_prevCenter       = 0.0;
double       g_prevRangeHigh    = 0.0;
double       g_prevRangeLow     = 0.0;

double       g_rangeTop=0, g_rangeBot=0, g_rangeCenter=0;
int          g_currentStepPoints = 0;

int          DigitsAdjust = 0;

// Track processed closed trades to avoid duplicate drawing
int          g_closedTickets[512];
int          g_closedCount = 0;

// Last bar time to throttle some redraw operations
datetime     g_lastBarTime = 0;

// Prefix for all objects
string OBJPFX = "RHGV_";

//+------------------------------------------------------------------+
int OnInit()
{
   DigitsAdjust = (int)MarketInfo(Symbol(), MODE_DIGITS);
   ArrayInitialize(g_closedTickets, -1);
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(CleanOnDeinit && ShowVisualDebug)
      DeleteAllObjects();
}
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal();
   for(int i=total-1; i>=0; --i)
   {
      string name = ObjectName(i);
      if(StringFind(name, OBJPFX, 0)==0)
         ObjectDelete(name);
   }
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!AllowNewTrades && OrdersTotal()==0) return;

   // Drawdown guard
   if(MaxTotalDDPercent > 0)
   {
      double eq=AccountEquity(), bal=AccountBalance();
      if(bal>0)
      {
         double ddPct=100.0*(bal-eq)/bal;
         if(ddPct >= MaxTotalDDPercent)
         {
            if(CloseAllOnMaxDD) CloseAllPositions();
            // Still update visuals for analysis, but skip new orders
         }
      }
   }

   if(!UpdateRangeHybrid()) return;

   int trendDir = GetTrendDirection();
   bool squeezeOK = CheckSqueezeGate();

   g_currentStepPoints = CurrentGridStepPoints();

   // Recenter logic
   bool recentered = false;
   if(RecenterWhenRangeShifts)
      recentered = MaybeRecenter(); // returns true if recentered now

   // (A) Visual update per new bar or recenter
   if(ShowVisualDebug)
   {
      datetime barTime = Time[0];
      bool isNewBar = (barTime != g_lastBarTime);
      if(DrawRangeLines && (isNewBar || recentered))
         DrawCurrentRangeLines(recentered);

      if(DrawGridLevels && (isNewBar || recentered))
         DrawCurrentGridLevels();

      g_lastBarTime = barTime;
   }

   // Build grid arrays
   double levelsBuy[128], levelsSell[128]; int buyCount=0, sellCount=0;
   BuildGridLevels(g_rangeCenter, g_rangeTop, g_rangeBot, levelsBuy, buyCount, levelsSell, sellCount);

   // Entries
   if(AllowNewTrades && squeezeOK)
   {
      if(trendDir != 0 || !UseTrendFilter)
         ManageEntries(trendDir, levelsBuy, buyCount, levelsSell, sellCount);
   }

   // Basket logic
   if(UseBasketBreakeven) TryBasketBreakeven();

   // Draw trade markers (open & close) after trade events
   if(ShowVisualDebug && ShowTradeMarkers)
   {
      DrawOpenTradeMarkers();
      DrawClosedTradeMarkers();
   }
}

/******************** RANGE & GRID CORE (same as prior, trimmed) ********************/
bool UpdateRangeHybrid()
{
   int tf = Period();
   int StructModeInt = (int)RH_StructMode;
   int DrawFromInt   = (int)RH_DrawFrom;

   int bTop=0,bBot=1,bMid=2;
   if(RangeSource==Range_Structural){ bTop=3; bBot=4; bMid=5; }
   else if(RangeSource==Range_Envelope){ bTop=6; bBot=7; bMid=8; }

   double top = iCustom(Symbol(), tf, "RangeHybrid",
                        RH_WindowBars, RH_UseCompletedBars, RH_ShowWindowHistorical, RH_ShowWindowLines, RH_ShowWindowCenter,
                        RH_ZZ_Depth, RH_ZZ_DeviationPoints, RH_ZZ_Backstep, StructModeInt, DrawFromInt,
                        RH_ShowStructuralLines, RH_ShowStructuralCenter,
                        RH_ShowEnvelopeLines, RH_ShowEnvelopeCenter, RH_EnvelopeLookbackBars, RH_EnvelopeFallbackToPrice,
                        bTop, 0);
   double bot = iCustom(Symbol(), tf, "RangeHybrid",
                        RH_WindowBars, RH_UseCompletedBars, RH_ShowWindowHistorical, RH_ShowWindowLines, RH_ShowWindowCenter,
                        RH_ZZ_Depth, RH_ZZ_DeviationPoints, RH_ZZ_Backstep, StructModeInt, DrawFromInt,
                        RH_ShowStructuralLines, RH_ShowStructuralCenter,
                        RH_ShowEnvelopeLines, RH_ShowEnvelopeCenter, RH_EnvelopeLookbackBars, RH_EnvelopeFallbackToPrice,
                        bBot, 0);
   double mid = iCustom(Symbol(), tf, "RangeHybrid",
                        RH_WindowBars, RH_UseCompletedBars, RH_ShowWindowHistorical, RH_ShowWindowLines, RH_ShowWindowCenter,
                        RH_ZZ_Depth, RH_ZZ_DeviationPoints, RH_ZZ_Backstep, StructModeInt, DrawFromInt,
                        RH_ShowStructuralLines, RH_ShowStructuralCenter,
                        RH_ShowEnvelopeLines, RH_ShowEnvelopeCenter, RH_EnvelopeLookbackBars, RH_EnvelopeFallbackToPrice,
                        bMid, 0);

   if(!MathIsValidNumber(top)||!MathIsValidNumber(bot)||!MathIsValidNumber(mid)) return false;
   if(top <= bot) return false;
   g_rangeTop=top; g_rangeBot=bot; g_rangeCenter=mid;
   return true;
}

int GetTrendDirection()
{
   if(!UseTrendFilter) return 0;
   // Changed indicator name here:
   double up   = iCustom(Symbol(), TrendTF, "Supertrend", ST_ATR_Period, ST_Factor, 0, 0);
   double down = iCustom(Symbol(), TrendTF, "Supertrend", ST_ATR_Period, ST_Factor, 1, 0);
   bool upActive   = MathIsValidNumber(up)   && up   != EMPTY_VALUE;
   bool downActive = MathIsValidNumber(down) && down != EMPTY_VALUE;
   if(upActive && !downActive)  return +1;
   if(downActive && !upActive)  return -1;
   return 0;
}

bool CheckSqueezeGate()
{
   if(!UseSqueezeFilter) return true;
   double psi0 = GetSqueezePSI(0);
   if(!MathIsValidNumber(psi0)) return false;
   if(!SQ_RequireReleaseCross) return (psi0 < SQ_AllowBelow);
   double psi1 = GetSqueezePSI(1);
   return (psi1 > SQ_AllowBelow && psi0 < SQ_AllowBelow);
}
double GetSqueezePSI(int shift)
{
   double a = iCustom(Symbol(), SqueezeTF, "SqueezeIndex", SQ_ConvFactor, SQ_Length, PRICE_CLOSE, 0, shift);
   double b = iCustom(Symbol(), SqueezeTF, "SqueezeIndex", SQ_ConvFactor, SQ_Length, PRICE_CLOSE, 1, shift);
   double psi = EMPTY_VALUE;
   if(MathIsValidNumber(a)&&a!=EMPTY_VALUE) psi=a;
   if(MathIsValidNumber(b)&&b!=EMPTY_VALUE) psi=b;
   return psi;
}

int CurrentGridStepPoints()
{
   double h = g_rangeTop - g_rangeBot;
   if(AutoGridStepFromRange && h>0 && AutoStepDivisor>0)
      return MathMax(1,(int)MathRound((h/AutoStepDivisor)/Point));
   return GridStepPoints;
}

bool MaybeRecenter()
{
   if(g_prevRangeHigh==0.0 && g_prevRangeLow==0.0)
   {
      g_prevRangeHigh=g_rangeTop; g_prevRangeLow=g_rangeBot; g_prevCenter=g_rangeCenter;
      g_lastRecenterTime=TimeCurrent();
      return false;
   }
   double oldHeight = g_prevRangeHigh - g_prevRangeLow;
   if(oldHeight <= Point) oldHeight = Point;
   double shiftPct = 100.0 * MathAbs(g_rangeCenter - g_prevCenter)/oldHeight;
   if(shiftPct >= RecenterThresholdPct)
   {
      if(KeepHistoricalRangeMarks && ShowVisualDebug && DrawRangeLines)
         SnapshotOldRange();
      CancelPendingOrders();
      g_prevRangeHigh=g_rangeTop; g_prevRangeLow=g_rangeBot; g_prevCenter=g_rangeCenter;
      g_lastRecenterTime=TimeCurrent();
      return true;
   }
   return false;
}

void BuildGridLevels(double center, double top, double bot,
                     double &levelsBuy[], int &buyCount,
                     double &levelsSell[], int &sellCount)
{
   buyCount=0; sellCount=0;
   int step = g_currentStepPoints; if(step<1) step=1;
   for(int k=1;k<=GridLevelsEachSide && buyCount < ArraySize(levelsBuy) && sellCount < ArraySize(levelsSell);++k)
   {
      double bLvl = center - k*step*Point;
      double sLvl = center + k*step*Point;
      if(bLvl >= bot)  levelsBuy[buyCount++]=bLvl;
      if(sLvl <= top)  levelsSell[sellCount++]=sLvl;
   }
}

/******************** ENTRY / ORDER MANAGEMENT ********************/
void ManageEntries(int trendDir, double &levelsBuy[], int buyCount, double &levelsSell[], int sellCount)
{
   double bid=Bid, ask=Ask;
   int buyOpen=0,sellOpen=0,buyPend=0,sellPend=0;
   CountOrders(buyOpen,sellOpen,buyPend,sellPend);

   if(AllowSide(+1,trendDir) && CountSide(+1,buyOpen,buyPend) < MaxOrdersPerSide)
   {
      for(int i=0;i<buyCount;i++)
      {
         double lvl=levelsBuy[i];
         if(GridMode==Grid_Reversion_Limit)
         {
            if(bid > lvl && !HasPendingAtPrice(+1,lvl))
               if(PlacePending(+1,OP_BUYLIMIT,lvl,"BUY L"+(string)(i+1),trendDir)) {}
         }
         else
         {
            double trig = lvl + EntryBufferPoints*Point;
            if(ask < trig && !HasPendingAtPrice(+1,trig))
               PlacePending(+1,OP_BUYSTOP,trig,"BUY STOP L"+(string)(i+1),trendDir);
         }
      }
   }
   if(AllowSide(-1,trendDir) && CountSide(-1,sellOpen,sellPend) < MaxOrdersPerSide)
   {
      for(int j=0;j<sellCount;j++)
      {
         double lvl=levelsSell[j];
         if(GridMode==Grid_Reversion_Limit)
         {
            if(ask < lvl && !HasPendingAtPrice(-1,lvl))
               PlacePending(-1,OP_SELLLIMIT,lvl,"SELL L"+(string)(j+1),trendDir);
         }
         else
         {
            double trig=lvl - EntryBufferPoints*Point;
            if(bid > trig && !HasPendingAtPrice(-1,trig))
               PlacePending(-1,OP_SELLSTOP,trig,"SELL STOP L"+(string)(j+1),trendDir);
         }
      }
   }
}

bool AllowSide(int side, int trendDir)
{
   if(!UseTrendFilter) return true;
   if(trendDir==0) return false;
   return (side==trendDir) || AllowHedge;
}
int CountSide(int side,int openCnt,int pendCnt){ return openCnt+pendCnt; }

void CountOrders(int &buyOpen,int &sellOpen,int &buyPend,int &sellPend)
{
   buyOpen=sellOpen=buyPend=sellPend=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==OP_BUY) buyOpen++;
      if(type==OP_SELL) sellOpen++;
      if(type==OP_BUYLIMIT||type==OP_BUYSTOP) buyPend++;
      if(type==OP_SELLLIMIT||type==OP_SELLSTOP) sellPend++;
   }
}

bool HasPendingAtPrice(int side,double price)
{
   int t1=(side>0)?OP_BUYLIMIT:OP_SELLLIMIT;
   int t2=(side>0)?OP_BUYSTOP:OP_SELLSTOP;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==t1||type==t2)
         if(MathAbs(OrderOpenPrice()-price)<=EntryBufferPoints*Point) return true;
   }
   return false;
}

bool PlacePending(int side,int ordType,double price,string reason,int trendDir)
{
   double lot=FixedLot;
   int step=g_currentStepPoints; if(step<1) step=1;
   double tp=0.0;
   if(TP_ToNextGridLevel) tp=(side>0)? price+step*Point : price-step*Point;
   else if(UsePerOrderTP && PerOrderTP_InPoints>0)
      tp=(side>0)?price+PerOrderTP_InPoints*Point:price-PerOrderTP_InPoints*Point;

   int ticket=OrderSend(Symbol(),ordType,lot,NormalizeDouble(price,DigitsAdjust),
                        (int)SlippagePoints,0.0,tp,
                        EA_Tag,MagicNumber,0,(side>0)?clrLime:clrRed);
   if(ticket<0){ Print("OrderSend failed ",GetLastError()); return false; }

   if(ShowVisualDebug && DrawGridLevels && ShowOrderCommentsOnChart)
      CreateTextLabel(OBJPFX+"ORDR_"+(string)ticket,
                      " "+reason+" Trend="+(string)trendDir+
                      " Step="+(string)step,
                      Time[0], price, (side>0)?clrLime:clrRed);

   return true;
}

/******************** BASKET & CLOSE LOGIC ********************/
void TryBasketBreakeven()
{
   double eq=AccountEquity();
   double net=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUY||t==OP_SELL)
         net += OrderProfit()+OrderSwap()+OrderCommission();
   }
   bool moneyOK=(BasketBE_ProfitMoney>0 && net >= BasketBE_ProfitMoney);
   bool pctOK=(BasketBE_ProfitPercent>0 && eq>0 && (100.0*net/eq)>=BasketBE_ProfitPercent);
   if(!(moneyOK||pctOK)) return;
   CloseAllPositions();
}

void CloseAllPositions()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==OP_BUY)
      {
         if(!OrderClose(OrderTicket(),OrderLots(),Bid,(int)SlippagePoints,clrAqua))
            Print("OrderClose BUY failed ",GetLastError());
      }
      else if(type==OP_SELL)
      {
         if(!OrderClose(OrderTicket(),OrderLots(),Ask,(int)SlippagePoints,clrAqua))
            Print("OrderClose SELL failed ",GetLastError());
      }
      else
      {
         if(!OrderDelete(OrderTicket()))
            Print("OrderDelete pending failed ",GetLastError());
      }
   }
}

void CancelPendingOrders()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUYLIMIT||t==OP_BUYSTOP||t==OP_SELLLIMIT||t==OP_SELLSTOP)
      {
         if(!OrderDelete(OrderTicket()))
            Print("OrderDelete (recenter) failed ",GetLastError());
      }
   }
}

/******************** VISUAL OVERLAYS **************************/
void SnapshotOldRange()
{
   // Draw old top/bot/center with faded color
   DrawHLine(OBJPFX+"OLD_TOP_"+(string)TimeCurrent(), g_prevRangeHigh, ColRangeOld, STYLE_DOT,1);
   DrawHLine(OBJPFX+"OLD_BOT_"+(string)TimeCurrent(), g_prevRangeLow,  ColRangeOld, STYLE_DOT,1);
   DrawHLine(OBJPFX+"OLD_CTR_"+(string)TimeCurrent(), g_prevCenter,    ColRangeOld, STYLE_DOT,1);
}
void DrawCurrentRangeLines(bool recentered)
{
   // Remove existing current lines
   ObjectDelete(OBJPFX+"RNG_TOP");
   ObjectDelete(OBJPFX+"RNG_BOT");
   ObjectDelete(OBJPFX+"RNG_CTR");

   DrawHLine(OBJPFX+"RNG_TOP", g_rangeTop, ColRangeTop, STYLE_SOLID, 2);
   DrawHLine(OBJPFX+"RNG_BOT", g_rangeBot, ColRangeBot, STYLE_SOLID, 2);
   DrawHLine(OBJPFX+"RNG_CTR", g_rangeCenter, ColRangeCenter, STYLE_DOT, 1);
}

void DrawCurrentGridLevels()
{
   // Cleanup old grid objects
   int total=ObjectsTotal();
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(i);
      if(StringFind(name,OBJPFX+"GRID_",0)==0)
         ObjectDelete(name);
   }
   int step=g_currentStepPoints; if(step<1) step=1;

   // Build symmetrical labels around center until reaching top/bot
   for(int k=1;k<=GridLevelsEachSide;k++)
   {
      double buyLvl=g_rangeCenter - k*step*Point;
      if(buyLvl>=g_rangeBot)
         DrawHLine(OBJPFX+"GRID_BUY_"+(string)k, buyLvl, ColGridBuy, STYLE_DASH, 1);

      double sellLvl=g_rangeCenter + k*step*Point;
      if(sellLvl<=g_rangeTop)
         DrawHLine(OBJPFX+"GRID_SELL_"+(string)k, sellLvl, ColGridSell, STYLE_DASH, 1);
   }
}

void DrawHLine(string name,double price,color clr,int style,int width)
{
   if(!ObjectCreate(name,OBJ_HLINE,0,0,price))
      return;
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSet(name, OBJPROP_STYLE, style);
   ObjectSet(name, OBJPROP_WIDTH, width);
}

// Trade markers
void DrawOpenTradeMarkers()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==OP_BUY||type==OP_SELL)
      {
         string oname=OBJPFX+"TRADE_OPEN_"+(string)OrderTicket();
         if(ObjectFind(oname)<0)
         {
            int arrow=(type==OP_BUY)?233:234; // Wingdings codes (up/down)
            if(!ObjectCreate(oname,OBJ_ARROW,0,OrderOpenTime(),OrderOpenPrice()))
               continue;
            ObjectSet(oname,OBJPROP_ARROWCODE,arrow);
            ObjectSet(oname,OBJPROP_COLOR,(type==OP_BUY)?ColTradeBuyOpen:ColTradeSellOpen);
            ObjectSetText(oname,"O"+(string)OrderTicket(),8,"Arial",(type==OP_BUY)?ColTradeBuyOpen:ColTradeSellOpen);
         }
      }
   }
}

bool IsTicketClosedProcessed(int ticket)
{
   for(int i=0;i<g_closedCount;i++)
      if(g_closedTickets[i]==ticket) return true;
   return false;
}
void MarkTicketClosedProcessed(int ticket)
{
   if(g_closedCount < ArraySize(g_closedTickets))
      g_closedTickets[g_closedCount++]=ticket;
}

void DrawClosedTradeMarkers()
{
   int totalHist=OrdersHistoryTotal();
   for(int i=totalHist-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(!(type==OP_BUY||type==OP_SELL)) continue;
      int tk=OrderTicket();
      if(IsTicketClosedProcessed(tk)) continue;

      // Create close marker & line from open to close
      string cname=OBJPFX+"TRADE_CLOSE_"+(string)tk;
      if(ObjectFind(cname)<0)
      {
         if(!ObjectCreate(cname,OBJ_ARROW,0,OrderCloseTime(),OrderClosePrice()))
            continue;
         ObjectSet(cname,OBJPROP_ARROWCODE,251); // small dot
         ObjectSet(cname,OBJPROP_COLOR,ColTradeClose);
         ObjectSetText(cname,"C"+(string)tk,8,"Arial",ColTradeClose);
      }
      string lname=OBJPFX+"TRADE_LINE_"+(string)tk;
      if(ObjectFind(lname)<0)
      {
         if(ObjectCreate(lname,OBJ_TREND,0,OrderOpenTime(),OrderOpenPrice(),
                         OrderCloseTime(),OrderClosePrice()))
         {
            ObjectSet(lname,OBJPROP_COLOR,ColTradeLine);
            ObjectSet(lname,OBJPROP_STYLE,STYLE_DOT);
            ObjectSet(lname,OBJPROP_WIDTH,1);
         }
      }
      MarkTicketClosedProcessed(tk);
   }
}

// Text label for pending order reason
void CreateTextLabel(string name,string text,datetime t,double price,color clr)
{
   if(ObjectFind(name)>=0) return;
   if(ObjectCreate(name,OBJ_TEXT,0,t,price))
   {
      ObjectSetText(name,text,8,"Arial",clr);
   }
}

/******************** END VISUAL ********************************/

void DrawTradeMarkers() {} // (legacy placeholder)

/******************** CLOSED ****************************************/