//+------------------------------------------------------------------+
//|                                       HybridGridEA_AllInOne.mq4  |
//| Grid EA (no iCustom dependencies)                                |
//|                                                                  |
//| Embedded logic:                                                  |
//|  - RangeHybrid Lite (Window + Envelope; no Structural)           |
//|  - Supertrend (TV-style) for direction                           |
//|  - Squeeze Index (PSI) for regime                                |
//|                                                                  |
//| StrategyProfile (simple):                                        |
//|  - Auto (default):                                               |
//|      Breakout while Squeeze PSI < 80  -> momentum with trend     |
//|      Pullback while Squeeze PSI >= 80 -> limit-in-trend          |
//|  - Pullback only                                                 |
//|  - Breakout only                                                 |
//|                                                                  |
//| Step sizing (simple):                                            |
//|  - StepMode: AutoByRangeDensity | FixedDollars | FixedPoints     |
//|    * AutoByRangeDensity (default): choose Tight/Normal/Wide      |
//|      and EA derives step from range height and levels            |
//|    * FixedDollars: e.g., $5 per step on XAUUSD                   |
//|    * FixedPoints: set broker points directly                     |
//|  - GridLevelsEachSide = L (target rung count per side)           |
//|    EA ensures L rungs fit inside the current range               |
//|                                                                  |
//| UX safeguards:                                                   |
//|  - Preview/Confirm panel on attach or parameter change           |
//|  - Pending cleanup prompt: Rebuild | Keep | Add Missing          |
//|  - No surprise order placement until you click Proceed           |
//|                                                                  |
//| Notes:                                                           |
//|  - Trading is tick-driven. Visuals can also refresh on a timer.  |
//+------------------------------------------------------------------+
#property strict

/******************** USER INPUTS **********************************/
input string   EA_Tag                 = "RHGridEA";
input int      MagicNumber            = 8642001;
input double   FixedLot               = 0.10;
input int      MaxOrdersPerSide       = 20;
input double   SlippagePoints         = 10;
input bool     AllowHedge             = false;      // one-sided trading aligned with Supertrend
input bool     AllowNewTrades         = true;

// Range source (Lite only)
enum eRangeSource { Range_Window=0, Range_Envelope=1 };
input eRangeSource RangeSource        = Range_Window;

/*** RangeHybrid Lite params ***/
input int   RH_WindowBars             = 120;
input bool  RH_UseCompletedBars       = true;

// Envelope options (Lite)
enum eEnvMode { Envelope_PriceExtremes=0, Envelope_ZigZagPivots=1 };
input eEnvMode EnvelopeMode           = Envelope_PriceExtremes;
input int   RH_EnvelopeLookbackBars   = 500;

// ZigZag parameters (used only when EnvelopeMode = Envelope_ZigZagPivots)
input int   ZZ_Depth                  = 12;
input int   ZZ_DeviationPoints        = 5;   // points
input int   ZZ_Backstep               = 3;

/*** Strategy profile (simple) ***/
enum eStrategyProfile { Strategy_AutoBySqueeze=0, Strategy_PullbackOnly=1, Strategy_BreakoutOnly=2 };
input eStrategyProfile StrategyProfile = Strategy_AutoBySqueeze;

/*** Step sizing (simple) ***/
enum eStepMode { Step_AutoByRangeDensity=0, Step_FixedDollars=1, Step_FixedPoints=2 };
input eStepMode StepMode              = Step_AutoByRangeDensity;

enum eGridDensity { Density_Tight=0, Density_Normal=1, Density_Wide=2 };
input eGridDensity GridDensity        = Density_Normal;   // used when Step_AutoByRangeDensity

input double DollarsPerStep           = 5.0;    // used when Step_FixedDollars (e.g., gold $ per step)
input int    FixedStepPoints          = 150;    // used when Step_FixedPoints (broker points)
input double StepSmoothingFactor      = 0.30;   // 0..1 EMA smoothing on step; set 0 to disable
input bool   RespectLevelsEachSide    = true;   // if true, cap step so L rungs fit inside range

/*** Grid ***/
enum eGridMode { Grid_Reversion_Limit=0, Grid_Breakout_Stop=1 }; // base mode (may be overridden by StrategyProfile)
input eGridMode GridMode              = Grid_Reversion_Limit;
input int       GridLevelsEachSide    = 6;
input int       EntryBufferPoints     = 5;      // for breakout stops
input bool      PlaceAllGridLevels    = false;  // false: place nearest eligible level per side; true: place all eligible levels

/*** Recenter ***/
input bool   RecenterWhenRangeShifts  = true;
input double RecenterThresholdPct     = 15.0;

/*** Trend (Supertrend TV clone) ***/
input bool            UseTrendFilter  = true;
input ENUM_TIMEFRAMES TrendTF         = PERIOD_H1;
input int             ST_ATR_Period   = 10;
input double          ST_Factor       = 3.0;

/*** Squeeze (PSI) ***/
input bool            UseSqueezeFilter= true;
input ENUM_TIMEFRAMES SqueezeTF       = PERIOD_H1;
input int             SQ_ConvFactor   = 50;
input int             SQ_Length       = 20;
input double          SQ_Threshold    = 80.0;     // Breakout if PSI < threshold; Pullback otherwise

/*** Basket / TP ***/
input bool   UseBasketBreakeven       = true;
input double BasketBE_ProfitMoney     = 10.0;
input double BasketBE_ProfitPercent   = 0.0;
input bool   UsePerOrderTP            = true;
input int    PerOrderTP_InPoints      = 300;
input bool   TP_ToNextGridLevel       = true;

/*** Risk safety ***/
input double MaxTotalDDPercent        = 25.0;
input bool   CloseAllOnMaxDD          = false;

/*** UX / Visuals ***/
input group "UX & Visual"
input bool   ConfirmOnAttach          = true;    // show preview on attach
input bool   ConfirmOnParamChange     = true;    // show preview on re-attach (inputs change)
input bool   ShowPreviewPanel         = true;    // draw panel text/buttons
input bool   PromptRebuildOnParamChange = true;  // ask about existing pendings
input bool   RebuildOnStepChange      = false;   // auto prompt on big step change
input double StepChangeTriggerPct     = 15.0;    // threshold for "big" change
input int    StepRebuildCooldownMin   = 5;       // min minutes between rebuild prompts
input bool   ShowOpenMarkers          = true;
input bool   ShowClosedMarkers        = true;

// Marker style (classic vs. enhanced)
enum eMarkerStyle { Markers_Classic=1, Markers_Enhanced=2 };
input eMarkerStyle TradeMarkerStyle   = Markers_Enhanced;

// Enhanced marker styling
input int   MarkerTextFontSize        = 10;          // PnL text size
input int   MarkerCloseLabelPtsOffset = 80;          // vertical offset in broker points for $ label
input color MarkerWinTextColor        = clrLime;
input color MarkerLoseTextColor       = clrTomato;
input color MarkerWinLineColor        = clrDodgerBlue;
input color MarkerLoseLineColor       = clrTomato;
input int   MarkerLineWidth           = 2;
input int   MarkerLineStyleWin        = STYLE_DOT;
input int   MarkerLineStyleLose       = STYLE_DASHDOTDOT;

// Panel readability controls
input bool              ForcePanelOnTop        = true;         // temporarily disable "Chart on foreground" while EA is attached
input bool              HideDashboardInPreview = true;         // temporarily hide dashboard while preview is visible
input ENUM_BASE_CORNER  PanelCorner            = CORNER_LEFT_UPPER;
input int               PanelX                 = 8;
input int               PanelY                 = 46;           // below chart title area
input int               PanelWidth             = 660;
// Auto height and spacing for clearer lines
input bool              PanelAutoHeight        = true;         // auto-calc height from font and spacing
input int               PanelHeight            = 140;          // used if PanelAutoHeight=false
input int               PanelButtonW           = 160;
input int               PanelButtonH           = 20;
input int               PanelFontSize          = 9;            // smaller font as requested
input int               PreviewLineSpacingPx   = 6;            // extra vertical space between lines
input int               PanelPaddingTop        = 6;            // top padding
input int               PanelPaddingSides      = 8;            // left/right padding
input int               ButtonsRowSpacing      = 6;            // space above buttons
input bool              RebuildRowAuto         = true;         // place rebuild row just below panel
input int               RebuildRowY            = 200;          // used if RebuildRowAuto=false
input color             PanelBgColor           = clrBlack;
input color             PanelBorderColor       = clrDimGray;
input color             PanelTextColor         = clrWhite;

input bool   ShowVisualDebug          = true;
input bool   DrawRangeLines           = true;
input bool   KeepHistoricalRangeMarks = true;
input bool   DrawGridLevels           = true;
input bool   ShowTradeMarkers         = true;
input bool   ShowEntryReasonLabels    = true;
input bool   ShowDashboard            = true;
input color  ColRangeTop              = clrMaroon;
input color  ColRangeBot              = clrDarkGreen;
input color  ColRangeCtr              = clrDimGray;
input color  ColRangeOld              = clrGray;
input color  ColGridBuy               = clrLime;
input color  ColGridSell              = clrRed;
input color  ColTradeBuyOpen          = clrLime;
input color  ColTradeSellOpen         = clrRed;
input color  ColTradeClose            = clrSilver;
input color  ColTradeLine             = clrDodgerBlue;
input bool   CleanOnDeinit            = true;

// Visual refresh timer (seconds). 0 = disabled (tick-only).
input int    VisualRefreshSeconds     = 1;

/******************** INTERNAL STATE ********************************/
string   OBJPFX = "RHGAI_";
int      DigitsAdjust = 0;

double   g_rangeTop=0, g_rangeBot=0, g_rangeCtr=0;   // selected RangeSource
double   g_prevTop=0, g_prevBot=0, g_prevCtr=0;      // for recenter compare
datetime g_lastBarTime = 0;

int      g_currentStepPoints = 0;      // broker points
int      g_prevStepPoints    = 0;
datetime g_lastStepPromptAt  = 0;

int      g_closedTickets[1024];
int      g_closedCount=0;

bool     g_tradingPaused   = false;    // set by preview/confirm
bool     g_waitingRebuild  = false;    // pending cleanup prompt open
bool     g_previewShown    = false;

double   g_cachedPsi       = EMPTY_VALUE; // last closed PSI cached for panel display

// Remember/restore chart "foreground" for readability
bool     g_savedForegroundFlag = false;
bool     g_changedForeground   = false;

// Last computed panel height (px) for auto rebuild-row placement
int      g_lastPanelHeightPx   = 0;

/*** Internal arrays for Envelope ZigZag (series orientation) ***/
double   ZZ_Hi[], ZZ_Lo[];

/******************** FORWARD DECLARATIONS **************************/
bool   IsNum(double x);
void   DeleteAllObjects();
void   DrawHLine(string name,double price,color clr,int style,int width);

int    LoadTFSeries(ENUM_TIMEFRAMES tf,int count,double &o[],double &h[],double &l[],double &c[],datetime &t[]);
int    SupertrendDirectionTF(ENUM_TIMEFRAMES tf,int atrPeriod,double factor,int maxBars,int &dirPrevRef);

double CorrSeq(double &a[],int start,int nW);
double SqueezePSI_TF(ENUM_TIMEFRAMES tf,int conv,int len,int maxBars,double &psiPrevRef);

void   ComputeZZForEnvelope(int rates_total);
void   ComputeWindowRange(int rates_total);
void   ComputeEnvelopeRange(int rates_total);

void   ComputeRange();                     // range only
void   ComputeStep();                      // step only (with chosen StepMode)
void   ComputeRangeAndStep();              // helper

void   BuildGridLevels(double &buyLvls[],int &nB,double &sellLvls[],int &nS);
bool   AllowSide(int side,int trendDir);
void   CountOrders(int &buyOpen,int &sellOpen,int &buyPend,int &sellPend);
bool   HasPendingAt(double price,int side);
bool   PlacePending(int side,int type,double price,string reason,int trendDir);
void   ManageEntries(int effMode,int trendDir,double &buyLvls[],int nB,double &sellLvls[],int nS);
void   TryBasketBreakeven();
void   CloseAllPositions();
void   CancelPendingOrders();

void   SnapshotOldRange();
void   DrawCurrentRangeLines();
void   DrawCurrentGridLevels();
void   DrawOpenTradeMarkers();
bool   ClosedTicketSeen(int tk);
void   MarkClosedTicket(int tk);
void   DrawClosedTradeMarkers();
void   DrawClosedTradeMarkersEnhanced();     // NEW: enhanced closed markers
void   DrawOpenTradeMarkersEnhanced();       // NEW: enhanced open markers
void   ClearTradeMarkers();                  // remove marker objects (classic + enhanced)
void   CreateTextLabel(string name,string text,datetime t,double price,color clr);
void   DrawDashboard();

void   ShowPreviewPanelNow(string reason, int effMode, int trendDir, double psiNow, double stepPrice, int stepPts);
void   HidePreviewPanel();
void   ShowRebuildPrompt(int buyPend,int sellPend, string reason);
void   HideRebuildPrompt();
void   SummarizePendings(int &buyPend,int &sellPend,double &minPrice,double &maxPrice);

int    EffectiveModeByStrategy(double psiNow); // 0=Reversion, 1=Breakout
void   RedrawVisuals();

/******************** UTILS ****************************************/
bool IsNum(double x){ return (x==x && x!=EMPTY_VALUE && x!=DBL_MAX && x!=DBL_MIN); }

void DeleteAllObjects()
{
   for(int i=ObjectsTotal()-1;i>=0;i--)
   {
      string name=ObjectName(i);
      if(StringFind(name,OBJPFX,0)==0)
         ObjectDelete(name);
   }
}

void DrawHLine(string name,double price,color clr,int style,int width)
{
   if(ObjectFind(name)<0)
      ObjectCreate(name,OBJ_HLINE,0,0,price);
   ObjectSet(name,OBJPROP_PRICE,price);
   ObjectSet(name,OBJPROP_COLOR,clr);
   ObjectSet(name,OBJPROP_STYLE,style);
   ObjectSet(name,OBJPROP_WIDTH,width);
}

/******************** TIMEFRAME SERIES ACCESS **********************/
int LoadTFSeries(ENUM_TIMEFRAMES tf,int count,double &o[],double &h[],double &l[],double &c[],datetime &t[])
{
   int avail = iBars(Symbol(), tf);
   if(avail<=0) return 0;
   int n = MathMin(count, avail);
   ArrayResize(o,n); ArrayResize(h,n); ArrayResize(l,n); ArrayResize(c,n); ArrayResize(t,n);
   // Fill oldest->newest as 0..n-1
   for(int i=0;i<n;i++)
   {
      int sh = n-1 - i;
      t[i] = iTime(Symbol(),tf,sh);
      o[i] = iOpen(Symbol(),tf,sh);
      h[i] = iHigh(Symbol(),tf,sh);
      l[i] = iLow(Symbol(),tf,sh);
      c[i] = iClose(Symbol(),tf,sh);
   }
   return n;
}

/******************** SUPERTREND (TV clone) ************************/
// Returns +1 for UP (long), -1 for DOWN (short), 0 neutral
int SupertrendDirectionTF(ENUM_TIMEFRAMES tf,int atrPeriod,double factor,int maxBars,int &dirPrevRef)
{
   double o[],h[],l[],c[]; datetime t[];
   int n = LoadTFSeries(tf, maxBars, o,h,l,c,t);
   if(n < atrPeriod+5){ dirPrevRef=0; return 0; }

   double TR[], ATR[];
   ArrayResize(TR,n); ArrayResize(ATR,n);
   for(int i=0;i<n;i++)
   {
      double pc = (i==0)? c[i] : c[i-1];
      double r1 = h[i]-l[i];
      double r2 = MathAbs(h[i]-pc);
      double r3 = MathAbs(l[i]-pc);
      TR[i] = MathMax(r1, MathMax(r2,r3));
   }
   int seed = atrPeriod-1;
   double sum=0;
   for(int i=0;i<=seed;i++) sum+=TR[i];
   ATR[seed] = sum/atrPeriod;
   for(int i=seed+1;i<n;i++)
      ATR[i] = (ATR[i-1]*(atrPeriod-1)+TR[i])/atrPeriod;

   double FU[],FL[]; int DIR[];
   ArrayResize(FU,n); ArrayResize(FL,n); ArrayResize(DIR,n);
   double hl2 = 0.5*(h[seed]+l[seed]);
   double UB  = hl2 + factor*ATR[seed];
   double LB  = hl2 - factor*ATR[seed];
   FU[seed]=UB; FL[seed]=LB; DIR[seed]=0;

   for(int i=seed+1;i<n;i++)
   {
      double hl2i = 0.5*(h[i]+l[i]);
      double UBi  = hl2i + factor*ATR[i];
      double LBi  = hl2i - factor*ATR[i];

      double FUprev=FU[i-1], FLprev=FL[i-1], cprev=c[i-1];

      FU[i] = (UBi < FUprev || cprev > FUprev) ? UBi : FUprev;
      FL[i] = (LBi > FLprev || cprev < FLprev) ? LBi : FLprev;

      int dir = DIR[i-1];
      if(c[i] > FUprev)      dir = +1;  // UP trend
      else if(c[i] < FLprev) dir = -1;  // DOWN trend
      DIR[i]=dir;
   }

   int idx = MathMax(seed+1, n-2);     // last closed
   int idxPrev = MathMax(seed+1, idx-1);
   dirPrevRef = DIR[idxPrev];
   return DIR[idx];
}

/******************** SQUEEZE INDEX (PSI) **************************/
double CorrSeq(double &a[],int start,int nW)
{
   if(nW<=1) return EMPTY_VALUE;
   double meanB = 0.5*(nW-1);
   double varB  = ((double)nW*(double)nW - 1.0)/12.0;
   if(varB<=0) return EMPTY_VALUE;
   double sdB   = MathSqrt(varB);

   double sumA=0,sumA2=0,sumAB=0;
   for(int k=0;k<nW;k++)
   {
      double ak=a[start+k];
      sumA  += ak;
      sumA2 += ak*ak;
      sumAB += ak*k;
   }
   double invN = 1.0/nW;
   double meanA = sumA*invN;
   double varA  = (sumA2*invN) - (meanA*meanA);
   if(varA<=0) return EMPTY_VALUE;
   double sdA   = MathSqrt(varA);
   double cov   = (sumAB*invN) - (meanA*meanB);
   if(sdA<=0||sdB<=0) return EMPTY_VALUE;
   return cov/(sdA*sdB);
}

double SqueezePSI_TF(ENUM_TIMEFRAMES tf,int conv,int len,int maxBars,double &psiPrevRef)
{
   double o[],h[],l[],c[]; datetime t[];
   int n = LoadTFSeries(tf, maxBars, o,h,l,c,t);
   if(n < len+5){ psiPrevRef=EMPTY_VALUE; return EMPTY_VALUE; }

   double diff[]; ArrayResize(diff,n);
   double maxPrev=c[0], minPrev=c[0];
   for(int i=0;i<n;i++)
   {
      double s=c[i];
      if(i==0){ maxPrev=s; minPrev=s; }
      else
      {
         double convF = MathMax(1.0,(double)conv);
         double maxCand = maxPrev - (maxPrev - s)/convF;
         maxPrev = (s>maxCand? s:maxCand);
         double minCand = minPrev + (s - minPrev)/convF;
         minPrev = (s<minCand? s:minCand);
      }
      double d=maxPrev-minPrev; if(d<=0) d=1e-12;
      diff[i]=MathLog(d);
   }

   int idxNow  = n-2; // last closed
   int idxPrev = n-3;
   if(idxPrev-(len-1) < 0){ psiPrevRef=EMPTY_VALUE; return EMPTY_VALUE; }

   double corrPrev = CorrSeq(diff, idxPrev-(len-1), len);
   double corrNow  = CorrSeq(diff, idxNow -(len-1), len);
   psiPrevRef = (corrPrev==EMPTY_VALUE? EMPTY_VALUE : (-50.0*corrPrev+50.0));
   double psiNow   = (corrNow ==EMPTY_VALUE? EMPTY_VALUE : (-50.0*corrNow +50.0));
   return psiNow;
}

/******************** RANGEHYBRID LITE (embedded) ******************/
void ComputeZZForEnvelope(int rates_total)
{
   ArrayResize(ZZ_Hi, rates_total);
   ArrayResize(ZZ_Lo, rates_total);
   ArraySetAsSeries(ZZ_Hi,true); ArraySetAsSeries(ZZ_Lo,true);
   ArrayInitialize(ZZ_Hi,0.0); ArrayInitialize(ZZ_Lo,0.0);

   if(rates_total < ZZ_Depth || ZZ_Backstep >= ZZ_Depth) return;

   int limit = rates_total - ZZ_Depth; if(limit<0) limit=0;

   double lastLow=0,lastHigh=0;
   for(int i=limit;i>=0;i--)
   {
      double extLow = Low[iLowest(NULL,0,MODE_LOW,ZZ_Depth,i)];
      if(extLow == lastLow) extLow=0.0;
      else
      {
         lastLow = extLow;
         if(Low[i] - extLow > ZZ_DeviationPoints*Point) extLow=0.0;
         else
         {
            for(int b=1;b<=ZZ_Backstep;b++)
            {
               int pos=i+b;
               if(ZZ_Lo[pos]!=0 && ZZ_Lo[pos]>extLow) ZZ_Lo[pos]=0.0;
            }
         }
      }
      ZZ_Lo[i] = (Low[i]==extLow? extLow:0.0);

      double extHigh = High[iHighest(NULL,0,MODE_HIGH,ZZ_Depth,i)];
      if(extHigh == lastHigh) extHigh=0.0;
      else
      {
         lastHigh = extHigh;
         if(extHigh - High[i] > ZZ_DeviationPoints*Point) extHigh=0.0;
         else
         {
            for(int b=1;b<=ZZ_Backstep;b++)
            {
               int pos=i+b;
               if(ZZ_Hi[pos]!=0 && ZZ_Hi[pos]<extHigh) ZZ_Hi[pos]=0.0;
            }
         }
      }
      ZZ_Hi[i] = (High[i]==extHigh? extHigh:0.0);
   }
}

double g_rTop_W=0,g_rBot_W=0,g_rCtr_W=0;
double g_rTop_E=0,g_rBot_E=0,g_rCtr_E=0;

void ComputeWindowRange(int rates_total)
{
   g_rTop_W=0; g_rBot_W=0; g_rCtr_W=0;
   int startOff = RH_UseCompletedBars? 1:0;
   int count = RH_WindowBars;
   if(startOff+count > rates_total) count = rates_total-startOff;
   if(count<=0) return;

   int hiIdx = iHighest(NULL,0,MODE_HIGH,count,startOff);
   int loIdx = iLowest(NULL,0,MODE_LOW, count,startOff);
   if(hiIdx<0 || loIdx<0) return;

   g_rTop_W = High[hiIdx];
   g_rBot_W = Low[loIdx];
   g_rCtr_W = 0.5*(g_rTop_W+g_rBot_W);
}

void ComputeEnvelopeRange(int rates_total)
{
   g_rTop_E=0; g_rBot_E=0; g_rCtr_E=0;

   int startOff = RH_UseCompletedBars? 1:0;
   int count    = RH_EnvelopeLookbackBars;
   if(count<=0) return;
   if(startOff+count > rates_total) count = rates_total-startOff;
   if(count<=0) return;

   double top=EMPTY_VALUE, bot=EMPTY_VALUE;

   if(EnvelopeMode == Envelope_PriceExtremes)
   {
      int pHi = iHighest(NULL,0,MODE_HIGH,count,startOff);
      int pLo = iLowest (NULL,0,MODE_LOW, count,startOff);
      if(pHi>=0 && pLo>=0){ top=High[pHi]; bot=Low[pLo]; }
   }
   else
   {
      ComputeZZForEnvelope(rates_total);
      double hiBest=-1e100, loBest=1e100;
      int start = startOff, endBar = startOff + count - 1;
      for(int i=start;i<=endBar;i++)
      {
         if(ZZ_Hi[i]!=0.0 && ZZ_Hi[i]>hiBest) hiBest=ZZ_Hi[i];
         if(ZZ_Lo[i]!=0.0 && ZZ_Lo[i]<loBest) loBest=ZZ_Lo[i];
      }
      if(hiBest>loBest){ top=hiBest; bot=loBest; }
      else
      {
         int pHi = iHighest(NULL,0,MODE_HIGH,count,startOff);
         int pLo = iLowest (NULL,0,MODE_LOW, count,startOff);
         if(pHi>=0 && pLo>=0){ top=High[pHi]; bot=Low[pLo]; }
      }
   }

   if(top==EMPTY_VALUE || bot==EMPTY_VALUE || top<=bot) return;
   g_rTop_E = top;
   g_rBot_E = bot;
   g_rCtr_E = 0.5*(top+bot);
}

/******************** RANGE + STEP *********************************/
void ComputeRange()
{
   int bars = Bars;
   ComputeWindowRange(bars);
   ComputeEnvelopeRange(bars);
   switch(RangeSource)
   {
      case Range_Window:   g_rangeTop=g_rTop_W; g_rangeBot=g_rBot_W; g_rangeCtr=g_rCtr_W; break;
      case Range_Envelope: g_rangeTop=g_rTop_E; g_rangeBot=g_rBot_E; g_rangeCtr=g_rCtr_E; break;
   }
}

void ComputeStep()
{
   if(!IsNum(g_rangeTop) || !IsNum(g_rangeBot) || !IsNum(g_rangeCtr)){ g_currentStepPoints = MathMax(1, FixedStepPoints); return; }

   double H = g_rangeTop - g_rangeBot;
   if(H <= Point){ g_currentStepPoints = MathMax(1, FixedStepPoints); return; }

   int L = MathMax(1, GridLevelsEachSide);

   // raw step in price
   double step_price = 0.0;
   if(StepMode==Step_AutoByRangeDensity)
   {
      int bias = 0;
      if(GridDensity==Density_Normal) bias=2;
      else if(GridDensity==Density_Wide) bias=4;
      int divisor = 2*L + bias;
      if(divisor<=0) divisor = 2*L;
      step_price = H / divisor;
   }
   else if(StepMode==Step_FixedDollars)
   {
      step_price = MathMax(0.0, DollarsPerStep);
   }
   else // Step_FixedPoints
   {
      step_price = FixedStepPoints * Point;
   }

   // Respect level fit (cap step so L rungs stay inside tighter half-range)
   double HalfUp   = MathMax(0.0, g_rangeTop - g_rangeCtr);
   double HalfDown = MathMax(0.0, g_rangeCtr - g_rangeBot);
   double HalfMin  = MathMin(HalfUp, HalfDown);
   double step_max_fit = (L>0 ? HalfMin / L : step_price);

   // min step by spread
   double spreadPts = (MarketInfo(Symbol(), MODE_SPREAD));
   double step_min = MathMax(1*Point, 4.0*spreadPts*Point);

   if(RespectLevelsEachSide)
      step_price = MathMin(step_price, step_max_fit);

   step_price = MathMax(step_min, step_price);

   int newStepPts = MathMax(1, (int)MathRound(step_price / Point));

   // Optional smoothing
   if(StepSmoothingFactor>0.0 && g_prevStepPoints>0)
   {
      double s = MathMin(1.0, MathMax(0.0, StepSmoothingFactor));
      double smoothed = (1.0 - s) * (double)g_prevStepPoints + s * (double)newStepPts;
      newStepPts = MathMax(1, (int)MathRound(smoothed));
   }

   g_currentStepPoints = newStepPts;
}

void ComputeRangeAndStep()
{
   ComputeRange();
   ComputeStep();
}

/******************** GRID BUILD ************************************/
void BuildGridLevels(double &buyLvls[],int &nB,double &sellLvls[],int &nS)
{
   nB=0; nS=0;
   int step=MathMax(1,g_currentStepPoints);

   for(int k=1;k<=GridLevelsEachSide;k++)
   {
      double bLvl=g_rangeCtr - k*step*Point;
      if(IsNum(g_rangeBot) && bLvl>=g_rangeBot && nB<ArraySize(buyLvls))
         buyLvls[nB++]=bLvl;

      double sLvl=g_rangeCtr + k*step*Point;
      if(IsNum(g_rangeTop) && sLvl<=g_rangeTop && nS<ArraySize(sellLvls))
         sellLvls[nS++]=sLvl;
   }
}

/******************** ORDER MGMT ************************************/
bool AllowSide(int side,int trendDir)
{
   if(!UseTrendFilter) return true;
   if(trendDir==0) return false;
   return (side==trendDir) || AllowHedge;
}

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

bool HasPendingAt(double price,int side)
{
   int t1=(side>0)?OP_BUYLIMIT:OP_SELLLIMIT;
   int t2=(side>0)?OP_BUYSTOP :OP_SELLSTOP;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==t1||type==t2)
         if(MathAbs(OrderOpenPrice()-price)<=MathMax(1,EntryBufferPoints)*Point) return true;
   }
   return false;
}

bool PlacePending(int side,int type,double price,string reason,int trendDir)
{
   double lot=FixedLot;
   int step=MathMax(1,g_currentStepPoints);
   double tp=0.0;
   if(TP_ToNextGridLevel) tp=(side>0)? price+step*Point : price-step*Point;
   else if(UsePerOrderTP && PerOrderTP_InPoints>0)
      tp=(side>0)? price+PerOrderTP_InPoints*Point : price-PerOrderTP_InPoints*Point;

   int tk=OrderSend(Symbol(),type,lot,NormalizeDouble(price,DigitsAdjust),(int)SlippagePoints,0,tp,EA_Tag,MagicNumber,0,(side>0)?clrLime:clrRed);
   if(tk<0){ Print("OrderSend failed ",GetLastError()); return false; }

   if(ShowVisualDebug && ShowEntryReasonLabels)
      CreateTextLabel(OBJPFX+"ORD_"+(string)tk," "+reason+" dir="+(string)trendDir+" stepPts="+(string)step,Time[0],price,(side>0)?clrLime:clrRed);
   return true;
}

void ManageEntries(int effMode,int trendDir,double &buyLvls[],int nB,double &sellLvls[],int nS)
{
   double bid=Bid, ask=Ask;
   int buyOpen=0,sellOpen=0,buyPend=0,sellPend=0;
   CountOrders(buyOpen,sellOpen,buyPend,sellPend);

   // BUY side
   if(AllowSide(+1,trendDir) && buyOpen+buyPend < MaxOrdersPerSide)
   {
      for(int i=0;i<nB;i++)
      {
         double lvl=buyLvls[i];
         int type; bool eligible=false;
         if(effMode==0){ type=OP_BUYLIMIT; eligible=(lvl < bid - Point); }
         else          { type=OP_BUYSTOP;  double trig=lvl + EntryBufferPoints*Point; eligible=(trig > ask + Point); lvl=trig; }

         if(eligible && !HasPendingAt(lvl,+1))
         {
            if(PlacePending(+1,type,lvl, effMode==0?("BUY L"+(string)(i+1)):("BUY STOP "+(string)(i+1)), trendDir))
            {
               if(!PlaceAllGridLevels) break;
            }
         }
      }
   }

   // SELL side
   if(AllowSide(-1,trendDir) && sellOpen+sellPend < MaxOrdersPerSide)
   {
      for(int j=0;j<nS;j++)
      {
         double lvl=sellLvls[j];
         int type; bool eligible=false;
         if(effMode==0){ type=OP_SELLLIMIT; eligible=(lvl > ask + Point); }
         else          { type=OP_SELLSTOP;  double trig=lvl - EntryBufferPoints*Point; eligible=(trig < bid - Point); lvl=trig; }

         if(eligible && !HasPendingAt(lvl,-1))
         {
            if(PlacePending(-1,type,lvl, effMode==0?("SELL L"+(string)(j+1)):("SELL STOP "+(string)(j+1)), trendDir))
            {
               if(!PlaceAllGridLevels) break;
            }
         }
      }
   }
}

void TryBasketBreakeven()
{
   double eq=AccountEquity(), net=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUY||t==OP_SELL)
         net += OrderProfit()+OrderSwap()+OrderCommission();
   }
   bool okMoney=(BasketBE_ProfitMoney>0 && net>=BasketBE_ProfitMoney);
   bool okPct=(BasketBE_ProfitPercent>0 && eq>0 && (100.0*net/eq)>=BasketBE_ProfitPercent);
   if(!(okMoney||okPct)) return;
   CloseAllPositions();
}

void CloseAllPositions()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUY)
      {
         if(!OrderClose(OrderTicket(),OrderLots(),Bid,(int)SlippagePoints,clrAqua))
            Print("OrderClose BUY failed ",GetLastError());
      }
      else if(t==OP_SELL)
      {
         if(!OrderClose(OrderTicket(),OrderLots(),Ask,(int)SlippagePoints,clrAqua))
            Print("OrderClose SELL failed ",GetLastError());
      }
      else
      {
         if(!OrderDelete(OrderTicket()))
            Print("OrderDelete failed ",GetLastError());
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
            Print("OrderDelete (cleanup) failed ",GetLastError());
      }
   }
}

/******************** VISUALS ***************************************/
void SnapshotOldRange()
{
   DrawHLine(OBJPFX+"OLD_TOP_"+(string)TimeCurrent(), g_prevTop, ColRangeOld, STYLE_DOT,1);
   DrawHLine(OBJPFX+"OLD_BOT_"+(string)TimeCurrent(), g_prevBot, ColRangeOld, STYLE_DOT,1);
   DrawHLine(OBJPFX+"OLD_CTR_"+(string)TimeCurrent(), g_prevCtr, ColRangeOld, STYLE_DOT,1);
}

void DrawCurrentRangeLines()
{
   ObjectDelete(OBJPFX+"RNG_TOP");
   ObjectDelete(OBJPFX+"RNG_BOT");
   ObjectDelete(OBJPFX+"RNG_CTR");
   if(IsNum(g_rangeTop)) DrawHLine(OBJPFX+"RNG_TOP", g_rangeTop, ColRangeTop, STYLE_SOLID,2);
   if(IsNum(g_rangeBot)) DrawHLine(OBJPFX+"RNG_BOT", g_rangeBot, ColRangeBot, STYLE_SOLID,2);
   if(IsNum(g_rangeCtr)) DrawHLine(OBJPFX+"RNG_CTR", g_rangeCtr, ColRangeCtr, STYLE_DOT,1);
}

void DrawCurrentGridLevels()
{
   for(int i=ObjectsTotal()-1;i>=0;i--)
   {
      string nm=ObjectName(i);
      if(StringFind(nm,OBJPFX+"GRID_",0)==0) ObjectDelete(nm);
   }
   int step=MathMax(1,g_currentStepPoints);
   for(int k=1;k<=GridLevelsEachSide;k++)
   {
      double bLvl=g_rangeCtr - k*step*Point;
      if(IsNum(g_rangeBot) && bLvl>=g_rangeBot)
         DrawHLine(OBJPFX+"GRID_BUY_"+(string)k, bLvl, ColGridBuy, STYLE_DASH,1);
      double sLvl=g_rangeCtr + k*step*Point;
      if(IsNum(g_rangeTop) && sLvl<=g_rangeTop)
         DrawHLine(OBJPFX+"GRID_SELL_"+(string)k, sLvl, ColGridSell, STYLE_DASH,1);
   }
}

void DrawOpenTradeMarkers()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==OP_BUY||type==OP_SELL)
      {
         string on=OBJPFX+"OPEN_"+(string)OrderTicket();
         if(ObjectFind(on)<0)
         {
            int arrow=(type==OP_BUY)?233:234;
            if(ObjectCreate(on,OBJ_ARROW,0,OrderOpenTime(),OrderOpenPrice()))
            {
               color c=(type==OP_BUY)?ColTradeBuyOpen:ColTradeSellOpen;
               ObjectSet(on,OBJPROP_ARROWCODE,arrow);
               ObjectSet(on,OBJPROP_COLOR,c);
               ObjectSetText(on,"O"+(string)OrderTicket(),8,"Arial",c);
            }
         }
      }
   }
}

bool ClosedTicketSeen(int tk){ for(int i=0;i<g_closedCount;i++) if(g_closedTickets[i]==tk) return true; return false; }
void MarkClosedTicket(int tk){ if(g_closedCount<ArraySize(g_closedTickets)) g_closedTickets[g_closedCount++]=tk; }

void DrawClosedTradeMarkers()
{
   int hist=OrdersHistoryTotal();
   for(int i=hist-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType(); if(!(type==OP_BUY||type==OP_SELL)) continue;
      int tk=OrderTicket(); if(ClosedTicketSeen(tk)) continue;

      string cn=OBJPFX+"CLOSE_"+(string)tk;
      if(ObjectFind(cn)<0)
      {
         if(ObjectCreate(cn,OBJ_ARROW,0,OrderCloseTime(),OrderClosePrice()))
         {
            ObjectSet(cn,OBJPROP_ARROWCODE,251);
            ObjectSet(cn,OBJPROP_COLOR,ColTradeClose);
            ObjectSetText(cn,"C"+(string)tk,8,"Arial",ColTradeClose);
         }
      }
      string ln=OBJPFX+"LINE_"+(string)tk;
      if(ObjectFind(ln)<0)
      {
         if(ObjectCreate(ln,OBJ_TREND,0,OrderOpenTime(),OrderOpenPrice(),OrderCloseTime(),OrderClosePrice()))
         {
            ObjectSet(ln,OBJPROP_COLOR,ColTradeLine);
            ObjectSet(ln,OBJPROP_STYLE,STYLE_DOT);
            ObjectSet(ln,OBJPROP_WIDTH,1);
         }
      }
      MarkClosedTicket(tk);
   }
}

// NEW: Enhanced closed markers with colored path and $PnL label
void DrawClosedTradeMarkersEnhanced()
{
   int hist = OrdersHistoryTotal();
   for(int i=hist-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;

      int  t = OrderType();
      if(!(t==OP_BUY || t==OP_SELL)) continue;

      int      tk    = OrderTicket();
      datetime tOpen = OrderOpenTime();
      double   pOpen = OrderOpenPrice();
      datetime tClose= OrderCloseTime();
      double   pClose= OrderClosePrice();

      double pnl = OrderProfit()+OrderSwap()+OrderCommission(); // account currency
      bool   win = (pnl >= 0.0);

      // Names (TM2_ prefix = enhanced markers)
      string nOpen  = OBJPFX+"TM2_O_"+(string)tk;
      string nClose = OBJPFX+"TM2_C_"+(string)tk;
      string nLine  = OBJPFX+"TM2_L_"+(string)tk;
      string nPL    = OBJPFX+"TM2_P_"+(string)tk;

      // Open marker (small filled circle)
      if(ObjectFind(nOpen)<0)
      {
         if(ObjectCreate(nOpen, OBJ_ARROW, 0, tOpen, pOpen))
         {
            ObjectSet(nOpen, OBJPROP_ARROWCODE, 159);
            ObjectSet(nOpen, OBJPROP_COLOR, (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
            ObjectSetText(nOpen, "", 8, "Arial", (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
         }
      }

      // Close marker (small filled circle)
      if(ObjectFind(nClose)<0)
      {
         if(ObjectCreate(nClose, OBJ_ARROW, 0, tClose, pClose))
         {
            ObjectSet(nClose, OBJPROP_ARROWCODE, 159);
            ObjectSet(nClose, OBJPROP_COLOR, (win ? MarkerWinLineColor : MarkerLoseLineColor));
            ObjectSetText(nClose, "", 8, "Arial", (win ? MarkerWinLineColor : MarkerLoseLineColor));
         }
      }

      // Path from open->close
      if(ObjectFind(nLine)<0)
      {
         if(ObjectCreate(nLine, OBJ_TREND, 0, tOpen, pOpen, tClose, pClose))
         {
            ObjectSet(nLine, OBJPROP_COLOR, (win ? MarkerWinLineColor : MarkerLoseLineColor));
            ObjectSet(nLine, OBJPROP_STYLE, (win ? MarkerLineStyleWin : MarkerLineStyleLose));
            ObjectSet(nLine, OBJPROP_WIDTH, MarkerLineWidth);
         }
      }

      // $PnL label near the close price, vertical offset in points
      double yOff     = MarkerCloseLabelPtsOffset * Point;
      double lblPrice = pClose + (win ? +yOff : -yOff);
      string txt      = (pnl>=0.0 ? "+" : "") + StringFormat("$%.2f", pnl);

      if(ObjectFind(nPL)<0)
      {
         if(ObjectCreate(nPL, OBJ_TEXT, 0, tClose, lblPrice))
            ObjectSetText(nPL, txt, MarkerTextFontSize, "Arial", (win ? MarkerWinTextColor : MarkerLoseTextColor));
      }
      else
      {
         ObjectMove(nPL, 0, tClose, lblPrice);
         ObjectSetText(nPL, txt, MarkerTextFontSize, "Arial", (win ? MarkerWinTextColor : MarkerLoseTextColor));
      }
   }
}

// NEW: Enhanced open markers for currently open positions
void DrawOpenTradeMarkersEnhanced()
{
   datetime nowT = Time[0]; // anchor at last bar time
   double   bid  = Bid, ask = Ask;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;

      int t = OrderType();
      if(!(t==OP_BUY || t==OP_SELL)) continue;

      int      tk    = OrderTicket();
      datetime tOpen = OrderOpenTime();
      double   pOpen = OrderOpenPrice();

      double curPrice = (t==OP_BUY ? bid : ask);
      double pnl      = OrderProfit()+OrderSwap()+OrderCommission(); // running PnL
      bool   win      = (pnl >= 0.0);

      string nOpen  = OBJPFX+"TM2_O2_"+(string)tk;
      string nLine  = OBJPFX+"TM2_L2_"+(string)tk;
      string nPL    = OBJPFX+"TM2_P2_"+(string)tk;

      // Open marker (circle)
      if(ObjectFind(nOpen)<0)
      {
         if(ObjectCreate(nOpen, OBJ_ARROW, 0, tOpen, pOpen))
         {
            ObjectSet(nOpen, OBJPROP_ARROWCODE, 159);
            ObjectSet(nOpen, OBJPROP_COLOR, (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
            ObjectSetText(nOpen, "", 8, "Arial", (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
         }
      }

      // Line from open to "now"
      if(ObjectFind(nLine)<0)
      {
         if(ObjectCreate(nLine, OBJ_TREND, 0, tOpen, pOpen, nowT, curPrice))
         {
            ObjectSet(nLine, OBJPROP_COLOR, (win ? MarkerWinLineColor : MarkerLoseLineColor));
            ObjectSet(nLine, OBJPROP_STYLE, (win ? MarkerLineStyleWin : MarkerLineStyleLose));
            ObjectSet(nLine, OBJPROP_WIDTH, MarkerLineWidth);
         }
      }
      else
      {
         // update moving end
         ObjectMove(nLine, 1, nowT, curPrice);
         ObjectSet(nLine, OBJPROP_COLOR, (win ? MarkerWinLineColor : MarkerLoseLineColor));
         ObjectSet(nLine, OBJPROP_STYLE, (win ? MarkerLineStyleWin : MarkerLineStyleLose));
      }

      // Running $PnL label near current end
      double yOff     = MarkerCloseLabelPtsOffset * Point;
      double lblPrice = curPrice + (win ? +yOff : -yOff);
      string txt      = (pnl>=0.0 ? "+" : "") + StringFormat("$%.2f", pnl);

      if(ObjectFind(nPL)<0)
      {
         if(ObjectCreate(nPL, OBJ_TEXT, 0, nowT, lblPrice))
            ObjectSetText(nPL, txt, MarkerTextFontSize, "Arial", (win ? MarkerWinTextColor : MarkerLoseTextColor));
      }
      else
      {
         ObjectMove(nPL, 0, nowT, lblPrice);
         ObjectSetText(nPL, txt, MarkerTextFontSize, "Arial", (win ? MarkerWinTextColor : MarkerLoseTextColor));
      }
   }
}

// Remove classic and enhanced markers
void ClearTradeMarkers()
{
   for(int i=ObjectsTotal()-1;i>=0;i--)
   {
      string nm = ObjectName(i);
      if(StringFind(nm, OBJPFX+"OPEN_",  0)==0 ||
         StringFind(nm, OBJPFX+"CLOSE_", 0)==0 ||
         StringFind(nm, OBJPFX+"LINE_",  0)==0 ||
         StringFind(nm, OBJPFX+"TM2_",   0)==0)
      {
         ObjectDelete(nm);
      }
   }
}

void CreateTextLabel(string name,string text,datetime t,double price,color clr)
{
   if(ObjectFind(name)>=0) return;
   if(ObjectCreate(name,OBJ_TEXT,0,t,price))
      ObjectSetText(name,text,8,"Arial",clr);
}

void DrawDashboard()
{
   if(HideDashboardInPreview && g_previewShown) return; // keep dashboard out during preview to avoid overlap
   string nm = OBJPFX+"DASH";
   double stepPrice = g_currentStepPoints*Point;
   string s  = "Range Top="+DoubleToString(g_rangeTop,Digits)+
               "  Ctr="+DoubleToString(g_rangeCtr,Digits)+
               "  Bot="+DoubleToString(g_rangeBot,Digits)+
               "  step="+(string)g_currentStepPoints+" pts (~"+DoubleToString(stepPrice,Digits)+" price)";
   if(ObjectFind(nm)<0) ObjectCreate(nm,OBJ_LABEL,0,0,0);
   ObjectSetText(nm,s,9,"Arial",clrWhite);
   ObjectSet(nm,OBJPROP_CORNER,0);
   ObjectSet(nm,OBJPROP_XDISTANCE,8);
   ObjectSet(nm,OBJPROP_YDISTANCE,18);
}

/******************** PREVIEW PANEL / REBUILD PROMPT ***************/
void ShowPreviewPanelNow(string reason, int effMode, int trendDir, double psiNow, double stepPrice, int stepPts)
{
   if(!ShowPreviewPanel) return;

   // Hide dashboard immediately to avoid overlap (restored when preview closes)
   if(HideDashboardInPreview) ObjectDelete(OBJPFX+"DASH");

   // Optional: keep objects on top of candles by disabling Foreground
   if(ForcePanelOnTop)
   {
      long fg=0;
      if(ChartGetInteger(0, CHART_FOREGROUND, 0, fg))
      {
         g_savedForegroundFlag = (fg!=0);
         if(g_savedForegroundFlag){ ChartSetInteger(0, CHART_FOREGROUND, false); g_changedForeground=true; }
      }
   }

   // Clear any previous preview objects
   string ids[] = { "PV_BG","PV_T1","PV_T2","PV_T3","PV_T4",
                    "BTN_GO","BTN_CANCEL" };
   for(int i=0;i<ArraySize(ids);i++) ObjectDelete(OBJPFX+ids[i]);

   // Compute line height and dynamic panel height if requested
   int lh = PanelFontSize + MathMax(0, PreviewLineSpacingPx);
   int yPad = MathMax(0, PanelPaddingTop);
   int sidePad = MathMax(0, PanelPaddingSides);
   int lines = 4;
   int textHeight = lines * lh;
   int baseHeight = yPad + textHeight + ButtonsRowSpacing + PanelButtonH + yPad;
   int bgHeight = PanelAutoHeight ? baseHeight : PanelHeight;
   if(!PanelAutoHeight) bgHeight = MathMax(PanelHeight, baseHeight); // ensure enough space even if user set too small
   g_lastPanelHeightPx = bgHeight;

   // Background rectangle
   ObjectCreate(OBJPFX+"PV_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_XDISTANCE,  PanelX);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_YDISTANCE,  PanelY);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_XSIZE,      PanelWidth);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_YSIZE,      bgHeight);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_COLOR,      PanelBorderColor);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_BGCOLOR,    PanelBgColor);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_BACK,       false);

   // Text split into multiple labels (no wrapping needed)
   string modeStr = (effMode==0? "Pullback (Limit-in-trend)" : "Breakout (Stop-with-trend)");
   string dirStr  = (trendDir>0? "UP (long-only)" : (trendDir<0? "DOWN (short-only)" : "Neutral"));
   string t1 = "Preview ("+reason+")";
   string t2 = "Strategy: "+modeStr+"  |  Direction: "+dirStr;
   string t3 = "Squeeze PSI (last closed): "+(IsNum(psiNow)? DoubleToString(psiNow,2):"n/a")+
               "   Threshold: "+DoubleToString(SQ_Threshold,2);
   string t4 = "Grid: LevelsEachSide="+(string)GridLevelsEachSide+
               "   Step="+(string)stepPts+" pts  (~"+DoubleToString(stepPrice,Digits)+")";

   int y0 = PanelY + yPad;
   int x0 = PanelX + sidePad;

   ObjectCreate(OBJPFX+"PV_T1", OBJ_LABEL, 0, 0, 0);
   ObjectSet(OBJPFX+"PV_T1", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"PV_T1", OBJPROP_XDISTANCE,  x0);
   ObjectSet(OBJPFX+"PV_T1", OBJPROP_YDISTANCE,  y0 + 0*lh);
   ObjectSetText(OBJPFX+"PV_T1", t1, PanelFontSize, "Arial", PanelTextColor);

   ObjectCreate(OBJPFX+"PV_T2", OBJ_LABEL, 0, 0, 0);
   ObjectSet(OBJPFX+"PV_T2", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"PV_T2", OBJPROP_XDISTANCE,  x0);
   ObjectSet(OBJPFX+"PV_T2", OBJPROP_YDISTANCE,  y0 + 1*lh);
   ObjectSetText(OBJPFX+"PV_T2", t2, PanelFontSize, "Arial", PanelTextColor);

   ObjectCreate(OBJPFX+"PV_T3", OBJ_LABEL, 0, 0, 0);
   ObjectSet(OBJPFX+"PV_T3", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"PV_T3", OBJPROP_XDISTANCE,  x0);
   ObjectSet(OBJPFX+"PV_T3", OBJPROP_YDISTANCE,  y0 + 2*lh);
   ObjectSetText(OBJPFX+"PV_T3", t3, PanelFontSize, "Arial", PanelTextColor);

   ObjectCreate(OBJPFX+"PV_T4", OBJ_LABEL, 0, 0, 0);
   ObjectSet(OBJPFX+"PV_T4", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"PV_T4", OBJPROP_XDISTANCE,  x0);
   ObjectSet(OBJPFX+"PV_T4", OBJPROP_YDISTANCE,  y0 + 3*lh);
   ObjectSetText(OBJPFX+"PV_T4", t4, PanelFontSize, "Arial", PanelTextColor);

   // Buttons
   int by = PanelY + bgHeight - PanelButtonH - ButtonsRowSpacing;
   ObjectCreate(OBJPFX+"BTN_GO", OBJ_BUTTON, 0, 0, 0);
   ObjectSet(OBJPFX+"BTN_GO", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"BTN_GO", OBJPROP_XDISTANCE,  PanelX+10);
   ObjectSet(OBJPFX+"BTN_GO", OBJPROP_YDISTANCE,  by);
   ObjectSet(OBJPFX+"BTN_GO", OBJPROP_XSIZE,      PanelButtonW);
   ObjectSet(OBJPFX+"BTN_GO", OBJPROP_YSIZE,      PanelButtonH);
   ObjectSetText(OBJPFX+"BTN_GO", "Proceed", PanelFontSize, "Arial", clrBlack);

   ObjectCreate(OBJPFX+"BTN_CANCEL", OBJ_BUTTON, 0, 0, 0);
   ObjectSet(OBJPFX+"BTN_CANCEL", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"BTN_CANCEL", OBJPROP_XDISTANCE,  PanelX+20+PanelButtonW);
   ObjectSet(OBJPFX+"BTN_CANCEL", OBJPROP_YDISTANCE,  by);
   ObjectSet(OBJPFX+"BTN_CANCEL", OBJPROP_XSIZE,      PanelButtonW+100);
   ObjectSet(OBJPFX+"BTN_CANCEL", OBJPROP_YSIZE,      PanelButtonH);
   ObjectSetText(OBJPFX+"BTN_CANCEL", "Cancel (stay paused)", PanelFontSize, "Arial", clrBlack);

   g_previewShown = true;
   ChartRedraw();
}

void HidePreviewPanel()
{
   string ids[] = { "PV_BG","PV_T1","PV_T2","PV_T3","PV_T4",
                    "BTN_GO","BTN_CANCEL" };
   for(int i=0;i<ArraySize(ids);i++) ObjectDelete(OBJPFX+ids[i]);
   g_previewShown = false;

   // Restore dashboard if desired
   if(ShowDashboard) DrawDashboard();
}

void SummarizePendings(int &buyPend,int &sellPend,double &minPrice,double &maxPrice)
{
   buyPend=sellPend=0;
   minPrice=1e100; maxPrice=-1e100;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUYLIMIT||t==OP_BUYSTOP){ buyPend++; minPrice=MathMin(minPrice,OrderOpenPrice()); maxPrice=MathMax(maxPrice,OrderOpenPrice()); }
      if(t==OP_SELLLIMIT||t==OP_SELLSTOP){ sellPend++; minPrice=MathMin(minPrice,OrderOpenPrice()); maxPrice=MathMax(maxPrice,OrderOpenPrice()); }
   }
   if(minPrice==1e100){ minPrice=0; maxPrice=0; }
}

void ShowRebuildPrompt(int buyPend,int sellPend, string reason)
{
   if(!ShowPreviewPanel) return;

   ObjectDelete(OBJPFX+"RB_TXT");
   ObjectDelete(OBJPFX+"BTN_RB");
   ObjectDelete(OBJPFX+"BTN_KEEP");
   ObjectDelete(OBJPFX+"BTN_ADD");

   int x = PanelX;
   int y = RebuildRowAuto ? (PanelY + g_lastPanelHeightPx + 10) : RebuildRowY;

   string s = "Pending orders detected ("+reason+"): buys="+(string)buyPend+" sells="+(string)sellPend+
              ". Rebuild to match current grid?";

   ObjectCreate(OBJPFX+"RB_TXT", OBJ_LABEL, 0, 0, 0);
   ObjectSet(OBJPFX+"RB_TXT", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"RB_TXT", OBJPROP_XDISTANCE,  x+6);
   ObjectSet(OBJPFX+"RB_TXT", OBJPROP_YDISTANCE,  y+6);
   ObjectSetText(OBJPFX+"RB_TXT", s, PanelFontSize, "Arial", clrYellow);

   ObjectCreate(OBJPFX+"BTN_RB", OBJ_BUTTON, 0, 0, 0);
   ObjectSet(OBJPFX+"BTN_RB", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"BTN_RB", OBJPROP_XDISTANCE,  x+10);
   ObjectSet(OBJPFX+"BTN_RB", OBJPROP_YDISTANCE,  y+26);
   ObjectSet(OBJPFX+"BTN_RB", OBJPROP_XSIZE,      PanelButtonW+120);
   ObjectSet(OBJPFX+"BTN_RB", OBJPROP_YSIZE,      PanelButtonH);
   ObjectSetText(OBJPFX+"BTN_RB", "Rebuild (delete & re-place)", PanelFontSize, "Arial", clrBlack);

   ObjectCreate(OBJPFX+"BTN_KEEP", OBJ_BUTTON, 0, 0, 0);
   ObjectSet(OBJPFX+"BTN_KEEP", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"BTN_KEEP", OBJPROP_XDISTANCE,  x+200+PanelButtonW);
   ObjectSet(OBJPFX+"BTN_KEEP", OBJPROP_YDISTANCE,  y+26);
   ObjectSet(OBJPFX+"BTN_KEEP", OBJPROP_XSIZE,      PanelButtonW);
   ObjectSet(OBJPFX+"BTN_KEEP", OBJPROP_YSIZE,      PanelButtonH);
   ObjectSetText(OBJPFX+"BTN_KEEP", "Keep", PanelFontSize, "Arial", clrBlack);

   ObjectCreate(OBJPFX+"BTN_ADD", OBJ_BUTTON, 0, 0, 0);
   ObjectSet(OBJPFX+"BTN_ADD", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"BTN_ADD", OBJPROP_XDISTANCE,  x+210+2*PanelButtonW);
   ObjectSet(OBJPFX+"BTN_ADD", OBJPROP_YDISTANCE,  y+26);
   ObjectSet(OBJPFX+"BTN_ADD", OBJPROP_XSIZE,      PanelButtonW+40);
   ObjectSet(OBJPFX+"BTN_ADD", OBJPROP_YSIZE,      PanelButtonH);
   ObjectSetText(OBJPFX+"BTN_ADD", "Add Missing", PanelFontSize, "Arial", clrBlack);

   g_waitingRebuild = true;
   ChartRedraw();
}

void HideRebuildPrompt()
{
   ObjectDelete(OBJPFX+"RB_TXT");
   ObjectDelete(OBJPFX+"BTN_RB");
   ObjectDelete(OBJPFX+"BTN_KEEP");
   ObjectDelete(OBJPFX+"BTN_ADD");
   g_waitingRebuild = false;
}

/******************** REGIME / EFFECTIVE MODE **********************/
int EffectiveModeByStrategy(double psiNow)
{
   if(StrategyProfile==Strategy_PullbackOnly) return 0;
   if(StrategyProfile==Strategy_BreakoutOnly) return 1;

   // Auto by Squeeze (strict threshold on last closed bar)
   if(!UseSqueezeFilter || !IsNum(psiNow)) return 0;
   return (psiNow < SQ_Threshold ? 1 : 0);
}

/******************** INIT / DEINIT / TICK / TIMER / EVENTS ********/
int OnInit()
{
   DigitsAdjust = (int)MarketInfo(Symbol(), MODE_DIGITS);
   ArrayInitialize(g_closedTickets,-1);
   DeleteAllObjects();

   if(VisualRefreshSeconds > 0) EventSetTimer(MathMax(1, VisualRefreshSeconds));

   // Initial compute
   ComputeRangeAndStep();
   RedrawVisuals();

   // Preview/Confirm flow
   g_tradingPaused = (ConfirmOnAttach || ConfirmOnParamChange);
   double psiPrev=EMPTY_VALUE;
   double psiNow = UseSqueezeFilter ? SqueezePSI_TF(SqueezeTF, SQ_ConvFactor, SQ_Length, 1200, psiPrev) : 0.0;
   g_cachedPsi = psiNow;

   int stPrev=0; int trendDir = UseTrendFilter ? SupertrendDirectionTF(TrendTF, ST_ATR_Period, ST_Factor, 1200, stPrev) : 0;
   int effMode = EffectiveModeByStrategy(psiNow);
   double stepPrice = g_currentStepPoints*Point;

   if(g_tradingPaused)
      ShowPreviewPanelNow("attach/params", effMode, trendDir, psiNow, stepPrice, g_currentStepPoints);

   // If there are existing pendings, ask about rebuild
   if(PromptRebuildOnParamChange)
   {
      int bp, sp; double mn, mx; SummarizePendings(bp,sp,mn,mx);
      if(bp+sp>0) ShowRebuildPrompt(bp,sp,"attach/params");
   }

   g_prevStepPoints = g_currentStepPoints;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // Restore chart foreground if we changed it
   if(ForcePanelOnTop && g_changedForeground)
      ChartSetInteger(0, CHART_FOREGROUND, g_savedForegroundFlag);

   if(VisualRefreshSeconds > 0) EventKillTimer();
   if(CleanOnDeinit) DeleteAllObjects();
}

void OnTick()
{
   // Safety: DD
   if(MaxTotalDDPercent>0)
   {
      double eq=AccountEquity(), bal=AccountBalance();
      if(bal>0)
      {
         double ddPct=100.0*(bal-eq)/bal;
         if(ddPct>=MaxTotalDDPercent){ if(CloseAllOnMaxDD) CloseAllPositions(); }
      }
   }

   // Range/Step
   int stepPrev = g_currentStepPoints;
   ComputeRangeAndStep();

   // Recenter detection
   bool recentered=false;
   if(RecenterWhenRangeShifts && IsNum(g_prevTop) && IsNum(g_prevBot) && IsNum(g_rangeCtr))
   {
      double prevH = g_prevTop - g_prevBot; if(prevH<=Point) prevH=Point;
      double shiftPct = 100.0*MathAbs(g_rangeCtr - g_prevCtr)/prevH;
      if(shiftPct >= RecenterThresholdPct)
      {
         if(KeepHistoricalRangeMarks && ShowVisualDebug && DrawRangeLines) SnapshotOldRange();
         CancelPendingOrders();
         recentered=true;
      }
   }

   g_prevTop=g_rangeTop; g_prevBot=g_rangeBot; g_prevCtr=g_rangeCtr;
   g_prevStepPoints = g_currentStepPoints;

   // Visuals (range/grid/dashboard)
   if(ShowVisualDebug)
   {
      bool newBar=(Time[0]!=g_lastBarTime);
      if(DrawRangeLines && (newBar||recentered)) DrawCurrentRangeLines();
      if(DrawGridLevels && (newBar||recentered)) DrawCurrentGridLevels();
      if(ShowDashboard && (newBar||recentered)) DrawDashboard();
      g_lastBarTime=Time[0];
   }

   // If paused (preview), do not trade or draw markers
   if(g_tradingPaused)
   {
      ClearTradeMarkers();
      return;
   }

   // Signals (MTF)
   int stPrev=0;
   int trendDir = UseTrendFilter ? SupertrendDirectionTF(TrendTF, ST_ATR_Period, ST_Factor, 1200, stPrev) : 0;

   double psiPrev=EMPTY_VALUE;
   double psiNow  = UseSqueezeFilter ? SqueezePSI_TF(SqueezeTF, SQ_ConvFactor, SQ_Length, 1200, psiPrev) : 0.0;
   g_cachedPsi = psiNow;

   // Effective mode by StrategyProfile+Squeeze
   int effMode = EffectiveModeByStrategy(psiNow);

   // Build grid arrays & manage entries
   double buyLvls[128], sellLvls[128]; int nB=0,nS=0;
   BuildGridLevels(buyLvls,nB,sellLvls,nS);

   if(AllowNewTrades)
   {
      if(!UseTrendFilter || trendDir!=0)
         ManageEntries(effMode,trendDir,buyLvls,nB,sellLvls,nS);
   }

   // Basket
   if(UseBasketBreakeven) TryBasketBreakeven();

   // Trade markers (respect toggles and style)
   if(ShowTradeMarkers)
   {
      if(TradeMarkerStyle==Markers_Enhanced)
      {
         if(ShowOpenMarkers)   DrawOpenTradeMarkersEnhanced();
         if(ShowClosedMarkers) DrawClosedTradeMarkersEnhanced();
         if(!ShowOpenMarkers && !ShowClosedMarkers) ClearTradeMarkers();
      }
      else // classic
      {
         if(ShowOpenMarkers)   DrawOpenTradeMarkers();
         if(ShowClosedMarkers) DrawClosedTradeMarkers();
         if(!ShowOpenMarkers && !ShowClosedMarkers) ClearTradeMarkers();
      }
   }
   else
   {
      ClearTradeMarkers();
   }
}

void OnTimer()
{
   // Visual-only refresh
   ComputeRangeAndStep();
   RedrawVisuals();

   // If preview is showing, update the text with current cached PSI / step
   if(g_previewShown)
   {
      int stPrev=0; int trendDir = UseTrendFilter ? SupertrendDirectionTF(TrendTF, ST_ATR_Period, ST_Factor, 200, stPrev) : 0;
      int effMode = EffectiveModeByStrategy(g_cachedPsi);
      double stepPrice = g_currentStepPoints*Point;
      ShowPreviewPanelNow("attach/params", effMode, trendDir, g_cachedPsi, stepPrice, g_currentStepPoints);
   }
}

void RedrawVisuals()
{
   if(!ShowVisualDebug) return;
   if(DrawRangeLines) DrawCurrentRangeLines();
   if(DrawGridLevels) DrawCurrentGridLevels();
   if(ShowDashboard)  DrawDashboard();

   // Respect preview and toggles on timer refresh as well
   if(ShowTradeMarkers && !g_tradingPaused)
   {
      if(TradeMarkerStyle==Markers_Enhanced)
      {
         if(ShowOpenMarkers)   DrawOpenTradeMarkersEnhanced();
         if(ShowClosedMarkers) DrawClosedTradeMarkersEnhanced();
         if(!ShowOpenMarkers && !ShowClosedMarkers) ClearTradeMarkers();
      }
      else
      {
         if(ShowOpenMarkers)   DrawOpenTradeMarkers();
         if(ShowClosedMarkers) DrawClosedTradeMarkers();
         if(!ShowOpenMarkers && !ShowClosedMarkers) ClearTradeMarkers();
      }
   }
   else
   {
      ClearTradeMarkers();
   }
}

// OnChartEvent must be void in MT4 EA
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam==OBJPFX+"BTN_GO")
      {
         g_tradingPaused=false;
         HidePreviewPanel();
         return;
      }
      if(sparam==OBJPFX+"BTN_CANCEL")
      {
         HidePreviewPanel();
         return;
      }
      if(sparam==OBJPFX+"BTN_RB")
      {
         CancelPendingOrders();
         HideRebuildPrompt();
         return;
      }
      if(sparam==OBJPFX+"BTN_KEEP")
      {
         HideRebuildPrompt();
         return;
      }
      if(sparam==OBJPFX+"BTN_ADD")
      {
         HideRebuildPrompt();
         return;
      }
   }
   return;
}
//+------------------------------------------------------------------+