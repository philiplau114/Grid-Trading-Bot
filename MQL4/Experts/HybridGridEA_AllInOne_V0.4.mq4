//+------------------------------------------------------------------+
//|                          HybridGridEA_AllInOne_V0.4.mq4          |
//| Grid EA with PSI gate, hybrid entry (relative-to-price),         |
//| k-nearest staging, Cluster BE (subset close), Basket BE,         |
//| and selectable TP modes (next rung, fixed points, fixed money).  |
//|                                                                  |
//| Principle: "Protect first, then let run."                        |
//+------------------------------------------------------------------+
#property strict

/******************** USER INPUTS **********************************/
// Core / lots
input bool   AutoProceedInTester = true;
input string EA_Tag              = "RHGridEA";
input int    MagicNumber         = 8642001;
input double FixedLot            = 0.10;
input int    MaxOrdersPerSide    = 6;
input double SlippagePoints      = 10;
input bool   AllowHedge          = false;
input bool   AllowNewTrades      = true;

// Preset (advisory)
enum eRiskPreset { Preset_RiskAware=0, Preset_Natural=1, Preset_Aggressive=2 };
input bool        UseRiskPreset   = true;
input eRiskPreset RiskPreset      = Preset_Natural;

// Range source
enum eRangeSource { Range_Window=0, Range_Envelope=1 };
input eRangeSource RangeSource    = Range_Window;

// RangeHybrid params
input int   RH_WindowBars         = 120;
input bool  RH_UseCompletedBars   = true;

// Envelope options
enum eEnvMode { Envelope_PriceExtremes=0, Envelope_ZigZagPivots=1 };
input eEnvMode EnvelopeMode       = Envelope_PriceExtremes;
input int   RH_EnvelopeLookbackBars = 500;

// ZigZag params (for Envelope_ZigZagPivots)
input int   ZZ_Depth              = 12;
input int   ZZ_DeviationPoints    = 5;
input int   ZZ_Backstep           = 3;

/*** Signals & PSI gate ***/
input bool            UseTrendFilter   = true;
input ENUM_TIMEFRAMES TrendTF          = PERIOD_H1;
input int             ST_ATR_Period    = 10;
input double          ST_Factor        = 3.0;
input int             ST_StableBars    = 6;

input bool            UseSqueezeFilter = true;
input ENUM_TIMEFRAMES SqueezeTF        = PERIOD_H1;
input int             SQ_ConvFactor    = 50;
input int             SQ_Length        = 20;

// PSI high pause gate
input bool   UsePSIHighPause = true;
input double PSIPauseAbove   = 80.0;   // if PSI > this and UsePSIHighPause=1 -> Pause

// Original hysteresis (kept for compatibility; not used to force entry type)
enum eSqueezeMode { SQ_Auto=0, SQ_Pullback=1, SQ_Breakout=2, SQ_Pause=3 };
input eSqueezeMode SqueezeMode = SQ_Auto;
input double       PSI_Low     = 70.0;
input double       PSI_High    = 85.0;

/*** Strategy profile (legacy) ***/
enum eStrategyProfile { Strategy_AutoBySqueeze=0, Strategy_PullbackOnly=1, Strategy_BreakoutOnly=2 };
input eStrategyProfile StrategyProfile = Strategy_AutoBySqueeze;

/*** Step sizing ***/
enum eStepMode { Step_AutoByRangeDensity=0, Step_FixedDollars=1, Step_FixedPoints=2 };
input eStepMode StepMode              = Step_AutoByRangeDensity;

enum eGridDensity { Density_Tight=0, Density_Normal=1, Density_Wide=2 };
input eGridDensity GridDensity        = Density_Normal;

input double DollarsPerStep           = 5.0;
input int    FixedStepPoints          = 150;
input double StepSmoothingFactor      = 0.30;
input bool   RespectLevelsEachSide    = true;

/*** Grid / staging ***/
enum eGridMode { Grid_Reversion_Limit=0, Grid_Breakout_Stop=1 }; // legacy base, no longer forces type
input eGridMode GridMode              = Grid_Reversion_Limit;
input int       GridLevelsEachSide    = 6;

// Nearest placement policy
enum eLevelsMode { Levels_Off=0, Levels_NearestOnly=1, Levels_All=2, Levels_RangeOnly=3 };
input eLevelsMode PlaceLevelsMode     = Levels_NearestOnly;
input int        NearestK             = 1; // when NearestOnly, place nearest K rungs per allowed side

// Hybrid entry (relative-to-price) controls
input int       EntryBufferPoints     = 5;
input bool      UseATRScaledBuffer    = true;
input ENUM_TIMEFRAMES BufferATR_TF    = PERIOD_H1;
input int       BufferATR_Period      = 14;
input double    BufferATR_Mult        = 0.25;
input int       BreakoutCloseConfirmBars = 1;

input double    HybridMinGapMultSpread   = 2.0;  // minGap = this * spread
input double    HybridDeadbandFracOfStep = 0.20; // deadband ~ frac * step

/*** Edge guard ***/
input double EdgeGuardPercentToRange  = 10.0;

/*** Recenter / Regime rebuild ***/
input bool   RecenterWhenRangeShifts  = true;
input double RecenterThresholdPct     = 25.0;
input bool   RecenterCheckOnNewBarOnly = true;
input bool   AutoRebuildOnRegimeChange = true;
input int    RebuildThrottleSeconds    = 120;
input int    RegimeChangeConfirmBars   = 1;

/*** Per-order risk (SL) ***/
input bool   UsePerOrderSLMoney       = true;
input double PerOrderSLMoney          = 35.0;

input bool   UseATR_SL                = false;   // OFF in design
input ENUM_TIMEFRAMES ATRSL_TF        = PERIOD_H1;
input int    ATRSL_Period             = 14;
input double ATRSL_Mult               = 1.6;

input bool   UseADX_Scale             = false;
input ENUM_TIMEFRAMES ADX_TF          = PERIOD_H1;
input int    ADX_Period               = 14;
input double ADX0                     = 20.0;
input double ADX_Range                = 20.0;
input double ADX_ScaleAlpha           = 0.4;

input bool   UseGridAwareSL           = false;   // OFF in design
input int    GridAwareRungsBeyond     = 1;
input int    GridAwareBufferPoints    = 40;

/*** Per-order exits (TP modes) ***/
// Priority: money TP > fixed points TP > next rung TP
input bool   UsePerOrderTP            = true;
input int    PerOrderTP_InPoints      = 300;
input bool   TP_ToNextGridLevel       = true;
input bool   UsePerOrderTP_Money      = false;
input double PerOrderTP_ProfitMoney   = 3.0;

input bool   UsePerOrderTP_Percent    = false;   // retained legacy option
input double PerOrderTP_Percent       = 0.20;

/*** Per-order breakeven (available; default OFF in cluster-first design) ***/
input bool   UsePerOrderBE            = false;
input bool   BE_UseStepFrac           = true;
input double BE_TriggerStepFrac       = 0.25;
input int    BE_TriggerPoints         = 120;
input int    BE_LockPoints            = 40;
input bool   BE_OnlyWhenWithTrend     = false;
input bool   UsePerOrderBE_Money      = false;
input double PerOrderBE_ProfitMoney   = 2.00;

/*** Exit priority / Basket ***/
enum eExitPriority { Exit_PerOrderBEFirst=0, Exit_BasketBEFirst=1, Exit_MaxDDFirst=2 };
input eExitPriority ExitPriorityOrder  = Exit_PerOrderBEFirst;

enum eBasketNetting { Basket_Global=0, Basket_OppositePairing=1, Basket_SameSideGrouping=2 };
input eBasketNetting BasketNettingMode= Basket_Global;

enum eBasketClosePriority { Close_BreakevenFirst=0, Close_MaxDDFirst=1 };
input eBasketClosePriority BasketClosePriority = Close_BreakevenFirst;

input bool   UseBasketBreakeven       = true;
input bool   BasketBE_AtZero          = true;
input double BasketBE_ProfitMoney     = 10.0;
input double BasketBE_ProfitPercent   = 0.0;

input double MaxTotalDDPercent        = 25.0;
input bool   CloseAllOnMaxDD          = false;

/*** Cluster BE (subset close; protector) ***/
input bool   UseClusterBE             = true;
input double ClusterBE_LossAlarmMoney = 12.0;
input double ClusterBE_SumLossAlarmMoney = 24.0;
input double ClusterBE_TargetProfitMoney = 1.0;
input int    ClusterBE_CooldownBars   = 2;
input int    ClusterBE_MaxSubsetSize  = 6;

/*** Recovery sizing (optional) ***/
input bool   UseRecoverySizing        = false;
input double RecoveryTargetMoney      = 5.0;
input double RecoveryCostBufferMoney  = 3.0;
input double RecoveryMaxLot           = 0.30;
input double RecoveryMaxMultiplier    = 2.0;
input int    RecoveryMaxAttempts      = 2;
input int    RecoveryCooldownBars     = 10;

/*** ATR trailing for open positions ***/
input bool   UseATR_Trailing          = false;
input ENUM_TIMEFRAMES ATRTrail_TF     = PERIOD_H1;
input int    ATRTrail_Period          = 14;
input double ATRTrail_Mult            = 1.5;
input int    TrailStepMinPoints       = 20;

/*** UX / Visuals ***/
input group "UX & Visual"
input bool   ConfirmOnAttach          = true;
input bool   ConfirmOnParamChange     = true;
input bool   ShowPreviewPanel         = true;
input bool   PromptRebuildOnParamChange = true;
input bool   RebuildOnStepChange      = false;
input double StepChangeTriggerPct     = 15.0;
input int    StepRebuildCooldownMin   = 5;
input bool   ShowOpenMarkers          = true;
input bool   ShowClosedMarkers        = true;

enum eMarkerStyle { Markers_Classic=1, Markers_Enhanced=2 };
input eMarkerStyle TradeMarkerStyle   = Markers_Enhanced;

input int   MarkerTextFontSize        = 10;
input int   MarkerCloseLabelPtsOffset = 80;
input color MarkerWinTextColor        = clrLime;
input color MarkerLoseTextColor       = clrTomato;
input color MarkerWinLineColor        = clrDodgerBlue;
input color MarkerLoseLineColor       = clrTomato;
input int   MarkerLineWidth           = 2;
input int   MarkerLineStyleWin        = STYLE_DOT;
input int   MarkerLineStyleLose       = STYLE_DASHDOTDOT;

input bool              ForcePanelOnTop        = true;
input bool              HideDashboardInPreview = true;
input ENUM_BASE_CORNER  PanelCorner            = CORNER_LEFT_UPPER;
input int               PanelX                 = 8;
input int               PanelY                 = 46;
input int               PanelWidth             = 660;
input bool              PanelAutoHeight        = true;
input int               PanelHeight            = 140;
input int               PanelButtonW           = 160;
input int               PanelButtonH           = 20;
input int               PanelFontSize          = 9;
input int               PreviewLineSpacingPx   = 6;
input int               PanelPaddingTop        = 6;
input int               PanelPaddingSides      = 8;
input int               ButtonsRowSpacing      = 6;
input bool              RebuildRowAuto         = true;
input int               RebuildRowY            = 200;
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
input int    VisualRefreshSeconds     = 1;

/******************** INTERNAL STATE ********************************/
string   OBJPFX = "RHGAI_";
int      DigitsAdjust = 0;

double   g_rangeTop=0, g_rangeBot=0, g_rangeCtr=0;
double   g_prevTop=0, g_prevBot=0, g_prevCtr=0;
datetime g_lastBarTime = 0;

int      g_currentStepPoints = 0;
int      g_prevStepPoints    = 0;
datetime g_lastStepPromptAt  = 0;

int      g_closedTickets[2048];
int      g_closedCount=0;

bool     g_tradingPaused   = false;
bool     g_waitingRebuild  = false;
bool     g_previewShown    = false;
datetime g_lastMassDeleteAtSec = 0;

double   g_cachedPsi       = EMPTY_VALUE;
int      g_lastTrendDir    = 0;
datetime g_trendLastFlipAt = 0;

int      g_lastEffMode     = -999;
datetime g_lastRebuildAt   = 0;
int      g_modeStableBars  = 0;
int      g_prevEffModeForStable = -999;

// Recovery state
int      g_recAttemptsBuy  = 0;
int      g_recAttemptsSell = 0;
int      g_lastRecBarBuy   = -10000;
int      g_lastRecBarSell  = -10000;
datetime g_lastRecAttemptBuyTime  = 0;
datetime g_lastRecAttemptSellTime = 0;

// Chart fg tracking
bool     g_savedForegroundFlag = false;
bool     g_changedForeground   = false;

// Panel auto height
int      g_lastPanelHeightPx   = 0;

// Envelope arrays
double   ZZ_Hi[], ZZ_Lo[];

// Cluster BE cooldown
datetime g_lastClusterAttemptBarTime = 0;

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

void   ComputeRange();
void   ComputeStep();
void   ComputeRangeAndStep();

void   BuildGridLevels(double &buyLvls[],int &nB,double &sellLvls[],int &nS);
bool   AllowSide(int side,int trendDir);
void   CountOrders(int &buyOpen,int &sellOpen,int &buyPend,int &sellPend);
bool   HasPendingAt(double price,int side);
bool   HasPendingAtType(double price,int side,int type);
bool   PlacePending(int side,int type,double price,string reason,int trendDir);
bool   PlacePendingWithLot(int side,int type,double price,string reason,int trendDir,double lot);

int    BufferPointsEffective();
bool   ConfirmCloseBeyondRung(int side,double rung,int needBars);
bool   IsNearEdge(double price,double guardPct);
double ValuePerPointPerLot();
double PointsFromMoney(double money,double lots);
double ComputeSLPrice(int side,double entryPrice);
double ComputeSLPriceWithLot(int side,double entryPrice,double lots);
double ComputeTPPrice(int side,double entryPrice,int stepPts);
double ComputeTPPrice_WithLots(int side,double entryPrice,int stepPts,double lots);
int    DetermineTPDistancePoints(int stepPts);
bool   PendingPriceMeetsStopLevel(int type,double price);

void   ManageEntriesHybrid(int trendDir,double &buyLvls[],int nB,double &sellLvls[],int nS);
bool   DecideOrderForBuy(double rung,int &outType,double &outPrice);
bool   DecideOrderForSell(double rung,int &outType,double &outPrice);

void   TryBasketBreakeven_Global(double needMoney, double needPct,bool atZero);
void   TryBasketBreakeven_SameSide(double needMoney, double needPct,bool atZero);
void   TryBasketBreakeven_OppositePair(double needMoney, double needPct,bool atZero);
void   TryBasketBreakeven();

bool   TryClusterBE();

void   CloseAllPositions();
void   CancelPendingOrders();
void   CancelPendingOrdersGuarded(int effMode,int trendDir,bool isRegime);

void   SnapshotOldRange();
void   DrawCurrentRangeLines();
void   DrawCurrentGridLevels();
void   DrawOpenTradeMarkers();
bool   ClosedTicketSeen(int tk);
void   MarkClosedTicket(int tk);
void   DrawClosedTradeMarkers();
void   DrawClosedTradeMarkersEnhanced();
void   DrawOpenTradeMarkersEnhanced();
void   ClearTradeMarkers();
void   CreateTextLabel(string name,string text,datetime t,double price,color clr);
void   DrawDashboard();

void   ShowPreviewPanelNow(string reason, int effMode, int trendDir, double psiNow, double stepPrice, int stepPts);
void   HidePreviewPanel();
void   ShowRebuildPrompt(int buyPend,int sellPend, string reason);
void   HideRebuildPrompt();
void   SummarizePendings(int &buyPend,int &sellPend,double &minPrice,double &maxPrice);

int    EffectiveModeByStrategy(double psiNow);
void   RedrawVisuals();
void   ApplyRiskPresetIfEnabled();

double GetATR(ENUM_TIMEFRAMES tf,int period,int shift);
double GetADX(ENUM_TIMEFRAMES tf,int period,int shift);
int    StableTrendBars(int curDir);

bool   NormalizeStopsForBroker(int type, double &sl, double &tp, int digitsAdj);
bool   ModifyOrderSLTPWithRetry(int ticket, double newSL, double newTP, color col, int digitsAdj);

void   HandlePerOrderBreakeven(int trendDir,int stepPts);

void   OnTimer();

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

/******************** SUPERTREND (TV-like) *************************/
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
      if(c[i] > FUprev)      dir = +1;
      else if(c[i] < FLprev) dir = -1;
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

double ValuePerPointPerLot()
{
   double tv = MarketInfo(Symbol(), MODE_TICKVALUE);
   double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(ts<=0 || tv<=0) return 0.0;
   double valuePerPointPerLot = tv * (Point/ts);
   return valuePerPointPerLot;
}

double PointsFromMoney(double money,double lots)
{
   if(money<=0 || lots<=0) return 0.0;
   double vpp = ValuePerPointPerLot();
   if(vpp<=0) return 0.0;
   double pts = money / (lots * vpp);
   return pts;
}

void ComputeStep()
{
   if(!IsNum(g_rangeTop) || !IsNum(g_rangeBot) || !IsNum(g_rangeCtr)){ g_currentStepPoints = MathMax(1, FixedStepPoints); return; }

   double H = g_rangeTop - g_rangeBot;
   if(H <= Point){ g_currentStepPoints = MathMax(1, FixedStepPoints); return; }

   int L = MathMax(1, GridLevelsEachSide);

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
      double vpp = ValuePerPointPerLot();
      if(vpp>0.0 && FixedLot>0.0)
      {
         double pts = DollarsPerStep / (vpp * FixedLot);
         step_price = MathMax(Point, pts * Point);
      }
      else
      {
         step_price = FixedStepPoints * Point;
      }
   }
   else
   {
      step_price = FixedStepPoints * Point;
   }

   double HalfUp   = MathMax(0.0, g_rangeTop - g_rangeCtr);
   double HalfDown = MathMax(0.0, g_rangeCtr - g_rangeBot);
   double HalfMin  = MathMin(HalfUp, HalfDown);
   double step_max_fit = (L>0 ? HalfMin / L : step_price);

   double spreadPts = (MarketInfo(Symbol(), MODE_SPREAD));
   double step_min = MathMax(1*Point, 4.0*spreadPts*Point);

   if(RespectLevelsEachSide)
      step_price = MathMin(step_price, step_max_fit);

   step_price = MathMax(step_min, step_price);

   int newStepPts = MathMax(1, (int)MathRound(step_price / Point));

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

/******************** HELPERS (ATR/ADX/ETC.) ************************/
double GetATR(ENUM_TIMEFRAMES tf,int period,int shift)
{
   double v = iATR(Symbol(), tf, period, shift);
   if(!IsNum(v) || v<=0) return 0.0;
   return v;
}
double GetADX(ENUM_TIMEFRAMES tf,int period,int shift)
{
   double v = iADX(Symbol(), tf, period, PRICE_CLOSE, MODE_MAIN, shift);
   if(!IsNum(v) || v<0) return 0.0;
   return v;
}
int StableTrendBars(int curDir)
{
   if(curDir!=g_lastTrendDir)
   {
      g_lastTrendDir = curDir;
      g_trendLastFlipAt = Time[0];
      return 0;
   }
   int bars = 0;
   for(int i=1;i<MathMin(1000,Bars);i++)
   {
      if(Time[i] <= g_trendLastFlipAt){ bars = i-1; break; }
   }
   return bars;
}

int BufferPointsEffective()
{
   int base = MathMax(0, EntryBufferPoints);
   if(!UseATRScaledBuffer) return base;
   double atr = GetATR(BufferATR_TF, BufferATR_Period, 1);
   if(atr<=0) return base;
   int atrPts = (int)MathRound((atr/Point) * MathMax(0.0, BufferATR_Mult));
   return MathMax(base, atrPts);
}

bool ConfirmCloseBeyondRung(int side,double rung,int needBars)
{
   if(needBars<=0) return true;
   for(int k=1;k<=needBars;k++)
   {
      double c = iClose(Symbol(), PERIOD_CURRENT, k);
      if(side>0) { if(!(c > rung)) return false; }
      else       { if(!(c < rung)) return false; }
   }
   return true;
}

bool IsNearEdge(double price,double guardPct)
{
   if(guardPct<=0.0) return false;
   if(!IsNum(g_rangeTop) || !IsNum(g_rangeBot)) return false;
   double H = g_rangeTop - g_rangeBot; if(H<=Point) return false;
   double band = (guardPct/100.0)*H;
   if((g_rangeTop - price) <= band) return true;
   if((price - g_rangeBot) <= band) return true;
   return false;
}

/******************** TP COMPUTATION ********************************/
double ComputeTPPrice(int side,double entryPrice,int stepPts)
{
   if(UsePerOrderTP_Percent && PerOrderTP_Percent>0.0)
   {
      double dist = (PerOrderTP_Percent/100.0) * entryPrice;
      double tp = (side>0)? (entryPrice + dist) : (entryPrice - dist);
      return NormalizeDouble(tp, DigitsAdjust);
   }
   if(UsePerOrderTP && PerOrderTP_InPoints>0)
   {
      double tp = (side>0)? (entryPrice + PerOrderTP_InPoints*Point) : (entryPrice - PerOrderTP_InPoints*Point);
      return NormalizeDouble(tp, DigitsAdjust);
   }
   if(TP_ToNextGridLevel && stepPts>0)
   {
      double tp = (side>0)? (entryPrice + stepPts*Point) : (entryPrice - stepPts*Point);
      return NormalizeDouble(tp, DigitsAdjust);
   }
   return 0.0;
}

double ComputeTPPrice_WithLots(int side,double entryPrice,int stepPts,double lots)
{
   if(UsePerOrderTP_Money && PerOrderTP_ProfitMoney>0.0 && lots>0.0)
   {
      double pts = PointsFromMoney(PerOrderTP_ProfitMoney, lots);
      if(pts>0.0)
      {
         double tp=(side>0)? (entryPrice + pts*Point) : (entryPrice - pts*Point);
         return NormalizeDouble(tp, DigitsAdjust);
      }
   }
   return ComputeTPPrice(side, entryPrice, stepPts);
}

int DetermineTPDistancePoints(int stepPts)
{
   if(UsePerOrderTP_Percent && PerOrderTP_Percent>0.0)
   {
      double px = (Bid+Ask)*0.5;
      double distPrice = (PerOrderTP_Percent/100.0) * px;
      return (int)MathMax(1, MathRound(distPrice/Point));
   }
   if(UsePerOrderTP && PerOrderTP_InPoints>0) return PerOrderTP_InPoints;
   if(TP_ToNextGridLevel && stepPts>0) return stepPts;
   return stepPts>0? stepPts : 100;
}

/******************** SL/TP MODIFY HELPERS *************************/
bool PendingPriceMeetsStopLevel(int type,double price)
{
   RefreshRates();
   double stopDist  = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double bid = Bid, ask = Ask;

   if(type==OP_BUYLIMIT)  return ( (ask - price) >= stopDist );
   if(type==OP_SELLLIMIT) return ( (price - bid) >= stopDist );
   if(type==OP_BUYSTOP)   return ( (price - ask) >= stopDist );
   if(type==OP_SELLSTOP)  return ( (bid - price) >= stopDist );
   return true;
}

bool NormalizeStopsForBroker(int type, double &sl, double &tp, int digitsAdj)
{
   double stopPts   = MarketInfo(Symbol(), MODE_STOPLEVEL);
   double stopDist  = stopPts   * Point;

   RefreshRates();
   double curBid = Bid, curAsk = Ask;

   if(type==OP_BUY)
   {
      if(sl>0 && (curBid - sl) < stopDist) sl = curBid - stopDist;
      if(tp>0 && (tp - curAsk) < stopDist) tp = curAsk + stopDist;
   }
   else if(type==OP_SELL)
   {
      if(sl>0 && (sl - curAsk) < stopDist) sl = curAsk + stopDist;
      if(tp>0 && (curBid - tp) < stopDist) tp = curBid - stopDist;
   }

   if(sl>0) sl = NormalizeDouble(sl, digitsAdj);
   if(tp>0) tp = NormalizeDouble(tp, digitsAdj);
   return true;
}

bool ModifyOrderSLTPWithRetry(int ticket, double newSL, double newTP, color col, int digitsAdj)
{
   for(int attempt=0; attempt<5; attempt++)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) { Print("Modify: select fail tk=",ticket," err=",GetLastError()); return false; }

      int    type = OrderType();
      double open = OrderOpenPrice();
      double sl   = newSL;
      double tp   = newTP;

      NormalizeStopsForBroker(type, sl, tp, digitsAdj);
      RefreshRates();

      bool ok = OrderModify(ticket, open, sl, tp, 0, col);
      if(ok) return true;

      int err = GetLastError();
      if(err==ERR_OFF_QUOTES || err==ERR_SERVER_BUSY || err==ERR_TRADE_CONTEXT_BUSY || err==ERR_PRICE_CHANGED)
      { Sleep(250); RefreshRates(); continue; }

      if(err==ERR_INVALID_STOPS || err==ERR_INVALID_PRICE) { Sleep(200); continue; }

      Print("Modify: failed tk=",ticket," err=",err," SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits));
      Sleep(200);
   }
   return false;
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
   int tolPts = MathMax(MathMax(1, EntryBufferPoints), BufferPointsEffective());
   double tol = MathMax(Point, tolPts * Point);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type==t1||type==t2)
      {
         if(MathAbs(OrderOpenPrice()-price) <= tol) return true;
      }
   }
   return false;
}

bool HasPendingAtType(double price,int side,int typeMask)
{
   int t1=(side>0)?OP_BUYLIMIT:OP_SELLLIMIT;
   int t2=(side>0)?OP_BUYSTOP :OP_SELLSTOP;
   int tolPts = MathMax(MathMax(1, EntryBufferPoints), BufferPointsEffective());
   double tol  = MathMax(Point, tolPts * Point);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(!(t==t1 || t==t2)) continue;
      if(typeMask!=-1 && t!=typeMask) continue;
      if(MathAbs(OrderOpenPrice()-price) <= tol) return true;
   }
   return false;
}

double ComputeSLPrice(int side,double entryPrice)
{
   return ComputeSLPriceWithLot(side,entryPrice,FixedLot);
}

double ComputeSLPriceWithLot(int side,double entryPrice,double lots)
{
   double bestDistPts = 1e12; int step=MathMax(1,g_currentStepPoints);

   if(UsePerOrderSLMoney && PerOrderSLMoney>0 && lots>0)
   {
      double pts = PointsFromMoney(PerOrderSLMoney, lots);
      if(pts>0 && pts<bestDistPts) bestDistPts=pts;
   }
   if(UseATR_SL)
   {
      double atr = GetATR(ATRSL_TF, ATRSL_Period, 1);
      if(atr>0)
      {
         double scale = 1.0;
         if(UseADX_Scale)
         {
            double adx = GetADX(ADX_TF, ADX_Period, 1);
            double u = MathMax(0.0, MathMin(1.0, (adx - ADX0)/MathMax(1.0, ADX_Range)));
            scale = 1.0 + ADX_ScaleAlpha * u;
         }
         double pts = (atr/Point) * MathMax(0.1, ATRSL_Mult) * scale;
         if(pts>0 && pts<bestDistPts) bestDistPts=pts;
      }
   }
   if(UseGridAwareSL && step>0)
   {
      int r = MathMax(1, GridAwareRungsBeyond);
      double pts = r*step + MathMax(0, GridAwareBufferPoints);
      if(pts>0 && pts<bestDistPts) bestDistPts=pts;
   }

   if(bestDistPts>=1e12) return 0.0;
   double sl = (side>0)? (entryPrice - bestDistPts*Point) : (entryPrice + bestDistPts*Point);
   return NormalizeDouble(sl, DigitsAdjust);
}

bool PlacePending(int side,int type,double price,string reason,int trendDir)
{
   return PlacePendingWithLot(side,type,price,reason,trendDir,FixedLot);
}

bool PlacePendingWithLot(int side,int type,double price,string reason,int trendDir,double lot)
{
   if(IsNearEdge(price, EdgeGuardPercentToRange)) return false;
   if(!PendingPriceMeetsStopLevel(type, price)) return false;

   int step=MathMax(1,g_currentStepPoints);

   // SL and TP
   double sl = ComputeSLPriceWithLot(side, price, lot);
   double tp = ComputeTPPrice_WithLots(side, price, step, lot);

   int tk=OrderSend(Symbol(),type,lot,NormalizeDouble(price,DigitsAdjust),(int)SlippagePoints,sl,tp,EA_Tag,MagicNumber,0,(side>0)?clrLime:clrRed);
   if(tk<0){ Print("OrderSend failed ",GetLastError()," type=",type," px=",DoubleToString(price,Digits)); return false; }

   if(ShowVisualDebug && ShowEntryReasonLabels)
      CreateTextLabel(OBJPFX+"ORD_"+(string)tk," "+reason+" dir="+(string)trendDir+" stepPts="+(string)step+" lot="+DoubleToString(lot,2),Time[0],price,(side>0)?clrLime:clrRed);
   return true;
}

/******************** HYBRID ENTRY LOGIC ****************************/
bool DecideOrderForBuy(double rung,int &outType,double &outPrice)
{
   RefreshRates(); double bid=Bid, ask=Ask; double mid=(bid+ask)*0.5;
   int spreadPts=(int)MarketInfo(Symbol(),MODE_SPREAD);
   int minGapPts=(int)MathMax(1.0, HybridMinGapMultSpread*spreadPts);
   int deadbandPts=(int)MathMax(1.0, HybridDeadbandFracOfStep*MathMax(1,g_currentStepPoints));
   int bufPts=BufferPointsEffective();

   if(mid >= rung + minGapPts*Point){          // price above rung → pullback buy
      outType=OP_BUYLIMIT; outPrice=rung;
      return true;
   }
   if(mid <= rung - minGapPts*Point){          // price below rung → reclaim breakout
      if(!ConfirmCloseBeyondRung(+1,rung,BreakoutCloseConfirmBars)) return false;
      outType=OP_BUYSTOP; outPrice=rung + bufPts*Point;
      return true;
   }
   if(MathAbs(mid - rung) <= deadbandPts*Point) return false;
   return false;
}

bool DecideOrderForSell(double rung,int &outType,double &outPrice)
{
   RefreshRates(); double bid=Bid, ask=Ask; double mid=(bid+ask)*0.5;
   int spreadPts=(int)MarketInfo(Symbol(),MODE_SPREAD);
   int minGapPts=(int)MathMax(1.0, HybridMinGapMultSpread*spreadPts);
   int deadbandPts=(int)MathMax(1.0, HybridDeadbandFracOfStep*MathMax(1,g_currentStepPoints));
   int bufPts=BufferPointsEffective();

   if(mid <= rung - minGapPts*Point){          // price below rung → pullback sell
      outType=OP_SELLLIMIT; outPrice=rung;
      return true;
   }
   if(mid >= rung + minGapPts*Point){          // price above rung → reclaim breakout down
      if(!ConfirmCloseBeyondRung(-1,rung,BreakoutCloseConfirmBars)) return false;
      outType=OP_SELLSTOP; outPrice=rung - bufPts*Point;
      return true;
   }
   if(MathAbs(mid - rung) <= deadbandPts*Point) return false;
   return false;
}

void ManageEntriesHybrid(int trendDir,double &buyLvls[],int nB,double &sellLvls[],int nS)
{
   if(!AllowNewTrades) return;

   int placedBuy=0, placedSell=0;
   int kTarget=MathMax(1, NearestK);

   if(PlaceLevelsMode==Levels_All){ kTarget=9999; }
   else if(PlaceLevelsMode==Levels_RangeOnly)
   {
      // Allow "all" only when PSI not paused; and require some trend stability
      int stableBars = StableTrendBars(trendDir);
      bool allowAll = (stableBars>=ST_StableBars) && !(UseSqueezeFilter && IsNum(g_cachedPsi) && UsePSIHighPause && g_cachedPsi>PSIPauseAbove);
      kTarget = allowAll? 9999 : MathMax(1, NearestK);
   }
   else if(PlaceLevelsMode==Levels_Off) { return; }

   // BUY side (trend up)
   if(AllowSide(+1,trendDir))
   {
      for(int i=0;i<nB;i++)
      {
         int type=0; double price=0.0;
         if(!DecideOrderForBuy(buyLvls[i],type,price)) continue;
         if(HasPendingAtType(price,+1,type)) continue;
         if(PlacePendingWithLot(+1,type,price,"HYBRID BUY",trendDir,FixedLot))
         {
            placedBuy++;
            if(PlaceLevelsMode==Levels_NearestOnly && placedBuy>=kTarget) break;
         }
      }
   }

   // SELL side (trend down)
   if(AllowSide(-1,trendDir))
   {
      for(int j=0;j<nS;j++)
      {
         int type=0; double price=0.0;
         if(!DecideOrderForSell(sellLvls[j],type,price)) continue;
         if(HasPendingAtType(price,-1,type)) continue;
         if(PlacePendingWithLot(-1,type,price,"HYBRID SELL",trendDir,FixedLot))
         {
            placedSell++;
            if(PlaceLevelsMode==Levels_NearestOnly && placedSell>=kTarget) break;
         }
      }
   }
}

/******************** BASKET ****************************************/
void BasketNetPositionsLots(double &outNet,int &outPosCount,double &outTotalLots)
{
   outNet=0.0; outPosCount=0; outTotalLots=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUY || t==OP_SELL)
      {
         outNet += (OrderProfit()+OrderSwap()+OrderCommission());
         outPosCount++;
         outTotalLots += OrderLots();
      }
   }
}

void TryBasketBreakeven_Global(double needMoney, double needPct, bool atZero)
{
   if(!UseBasketBreakeven) return;

   double net=0.0, totalLots=0.0; int posCount=0;
   BasketNetPositionsLots(net,posCount,totalLots);
   if(posCount <= 0) return;

   double eq = AccountEquity();
   bool trigger = false;

   if(needMoney > 0.0 && net >= needMoney) trigger = true;
   if(!trigger && needPct > 0.0 && eq > 0.0)
   {
      double pct = 100.0 * net / eq;
      if(pct >= needPct) trigger = true;
   }
   if(!trigger && atZero)
   {
      double effZeroMoney = (needMoney > 0.0 ? needMoney : 0.0);
      if(effZeroMoney <= 0.0)
      {
         double vpp = ValuePerPointPerLot();
         if(vpp > 0.0 && totalLots > 0.0) effZeroMoney = MathMax(0.01, vpp * totalLots);
         else                              effZeroMoney = 0.01;
      }
      if(net >= effZeroMoney) trigger = true;
   }

   if(!trigger) return;

   bool anyClosed = false;
   RefreshRates();
   for(int j=OrdersTotal()-1; j>=0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int t = OrderType();
      if(t==OP_BUY)
      {
         if(OrderClose(OrderTicket(), OrderLots(), Bid, (int)SlippagePoints, clrAqua))
            anyClosed = true;
      }
      else if(t==OP_SELL)
      {
         if(OrderClose(OrderTicket(), OrderLots(), Ask, (int)SlippagePoints, clrAqua))
            anyClosed = true;
      }
   }

   if(anyClosed)
   {
      datetime now = TimeCurrent();
      g_lastRebuildAt       = now;
      g_lastMassDeleteAtSec = now;
   }
}

void TryBasketBreakeven_SameSide(double needMoney, double needPct,bool atZero)
{
   TryBasketBreakeven_Global(needMoney,needPct,atZero);
}
void TryBasketBreakeven_OppositePair(double needMoney, double needPct,bool atZero)
{
   TryBasketBreakeven_Global(needMoney,needPct,atZero);
}
void TryBasketBreakeven()
{
   if(!UseBasketBreakeven) return;
   switch(BasketNettingMode)
   {
     case Basket_Global:           TryBasketBreakeven_Global(BasketBE_ProfitMoney, BasketBE_ProfitPercent, BasketBE_AtZero); break;
     case Basket_SameSideGrouping: TryBasketBreakeven_SameSide(BasketBE_ProfitMoney, BasketBE_ProfitPercent, BasketBE_AtZero); break;
     case Basket_OppositePairing:  TryBasketBreakeven_OppositePair(BasketBE_ProfitMoney, BasketBE_ProfitPercent, BasketBE_AtZero); break;
   }
}

/******************** CLUSTER BE (subset close) *********************/
struct TicketPnL { int tk; double pnl; int type; };

void SortLosersAsc(TicketPnL &arr[], int n)  // most negative first
{
   for(int i=1;i<n;i++){ TicketPnL key=arr[i]; int j=i-1; while(j>=0 && arr[j].pnl>key.pnl){ arr[j+1]=arr[j]; j--; } arr[j+1]=key; }
}

void SortWinnersDesc(TicketPnL &arr[], int n) // largest pnl first
{
   for(int i=0;i<n-1;i++)
      for(int j=0;j<n-1-i;j++)
         if(arr[j].pnl < arr[j+1].pnl){ TicketPnL tmp=arr[j]; arr[j]=arr[j+1]; arr[j+1]=tmp; }
}

bool TryClusterBE()
{
   if(!UseClusterBE) return false;

   // Cooldown in bars
   if(ClusterBE_CooldownBars>0 && g_lastClusterAttemptBarTime>0)
   {
      int barsSince = iBarShift(Symbol(), PERIOD_CURRENT, g_lastClusterAttemptBarTime, false);
      if(barsSince>=0 && barsSince < ClusterBE_CooldownBars) return false;
   }

   // Collect open tickets
   TicketPnL losers[256]; int nL=0;
   TicketPnL winners[256]; int nW=0;
   double maxLoss=0.0, sumLoss=0.0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType(); if(!(t==OP_BUY||t==OP_SELL)) continue;
      double pnl=OrderProfit()+OrderSwap()+OrderCommission();
      TicketPnL rec; rec.tk=OrderTicket(); rec.pnl=pnl; rec.type=t;
      if(pnl<0){ if(nL<256) losers[nL++]=rec; double loss=-pnl; sumLoss+=loss; if(loss>maxLoss) maxLoss=loss; }
      else      { if(nW<256) winners[nW++]=rec; }
   }
   if(nL==0) return false;

   if(!(maxLoss>=ClusterBE_LossAlarmMoney || sumLoss>=ClusterBE_SumLossAlarmMoney)) return false;

   SortLosersAsc(losers,nL);
   SortWinnersDesc(winners,nW);

   // Build subset: worst loser + best winners until cushion reached
   double subsetSum = losers[0].pnl; // negative
   int subsetTk[512]; int subsetCount=0;
   subsetTk[subsetCount++]=losers[0].tk;

   for(int w=0; w<nW && subsetSum < ClusterBE_TargetProfitMoney; w++)
   {
      subsetSum += winners[w].pnl;
      subsetTk[subsetCount++]=winners[w].tk;
      if(ClusterBE_MaxSubsetSize>0 && subsetCount>=ClusterBE_MaxSubsetSize) break;
   }
   if(subsetSum < ClusterBE_TargetProfitMoney) return false;

   // Close subset
   bool anyClosed=false;
   RefreshRates();
   for(int s=0; s<subsetCount; s++)
   {
      int tk = subsetTk[s];
      if(!OrderSelect(tk, SELECT_BY_TICKET)) continue;
      int t=OrderType(); double lots=OrderLots();
      if(t==OP_BUY)
      {
         if(OrderClose(tk,lots,Bid,(int)SlippagePoints,clrAqua)) anyClosed=true;
      }
      else if(t==OP_SELL)
      {
         if(OrderClose(tk,lots,Ask,(int)SlippagePoints,clrAqua)) anyClosed=true;
      }
   }
   if(anyClosed)
   {
      g_lastClusterAttemptBarTime = Time[0];
      datetime now=TimeCurrent();
      g_lastMassDeleteAtSec = now;
      return true;
   }
   return false;
}

/******************** CLOSE / CANCEL ********************************/
void CancelPendingOrders()
{
   bool anyDeleted = false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUYLIMIT||t==OP_BUYSTOP||t==OP_SELLLIMIT||t==OP_SELLSTOP)
      {
         if(!OrderDelete(OrderTicket()))
            Print("OrderDelete (cleanup) failed ",GetLastError());
         else
            anyDeleted = true;
      }
   }
   if(anyDeleted)
   {
      datetime now = TimeCurrent();
      g_lastRebuildAt       = now;
      g_lastMassDeleteAtSec = now;
   }
}

// Guarded cancellation for rebuilds
bool TypeCompatibleWithMode(int type,int effMode)
{
   if(effMode==0) return (type==OP_BUYLIMIT || type==OP_SELLLIMIT);
   if(effMode==1) return (type==OP_BUYSTOP  || type==OP_SELLSTOP);
   return false;
}
int PendingSideFromType(int type){ return (type==OP_BUYLIMIT||type==OP_BUYSTOP)? +1 : -1; }
double PendingDistancePtsToMarket(int type,double price)
{
   RefreshRates(); double bid=Bid, ask=Ask;
   if(type==OP_BUYLIMIT)  return MathMax(0.0,(ask - price)/Point);
   if(type==OP_BUYSTOP)   return MathMax(0.0,(price - ask)/Point);
   if(type==OP_SELLLIMIT) return MathMax(0.0,(price - bid)/Point);
   if(type==OP_SELLSTOP)  return MathMax(0.0,(bid - price)/Point);
   return 0.0;
}
bool FreezeLevelBlocksDelete(int type,double price)
{
   RefreshRates();
   double freezeDist = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double d = PendingDistancePtsToMarket(type, price) * Point;
   return (freezeDist>0 && d < freezeDist);
}

void CancelPendingOrdersGuarded(int effMode,int trendDir,bool isRegime)
{
   int stepPts = MathMax(1, g_currentStepPoints);
   int spreadPts = (int)MarketInfo(Symbol(), MODE_SPREAD);

   int gracePts = MathMax(2*spreadPts, (int)MathRound(0.10 * stepPts));
   int farPts = MathMax((int)MathRound(1.5 * stepPts), stepPts + BufferPointsEffective());
   int MIN_PENDING_AGE_SEC = 90;

   bool anyDeleted=false;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;

      int t=OrderType();
      if(!(t==OP_BUYLIMIT || t==OP_BUYSTOP || t==OP_SELLLIMIT || t==OP_SELLSTOP)) continue;

      double px = OrderOpenPrice();
      int side  = PendingSideFromType(t);

      if(FreezeLevelBlocksDelete(t, px)) continue;

      double distPts = PendingDistancePtsToMarket(t, px);
      bool nearFill = (distPts <= gracePts);
      if(nearFill) continue;

      int ageSec = (int)(TimeCurrent() - OrderOpenTime());

      bool typeOk  = TypeCompatibleWithMode(t, effMode);
      bool sideOk  = AllowSide(side, trendDir);
      bool outOfRange = (IsNum(g_rangeTop) && IsNum(g_rangeBot))? (px>g_rangeTop || px<g_rangeBot) : false;
      bool edgeBand  = IsNearEdge(px, EdgeGuardPercentToRange);

      bool clearlyIncompatible = (!typeOk) || (!sideOk);
      bool tooFresh = (ageSec < MIN_PENDING_AGE_SEC);

      if(tooFresh && !clearlyIncompatible) continue;

      bool shouldDelete = outOfRange || clearlyIncompatible || edgeBand || (distPts >= farPts);

      if(shouldDelete)
      {
         if(!OrderDelete(OrderTicket()))
            Print("OrderDelete (guarded) failed tk=",OrderTicket()," err=",GetLastError());
         else
            anyDeleted = true;
      }
   }

   if(anyDeleted)
   {
      datetime now=TimeCurrent();
      g_lastRebuildAt = now;
      g_lastMassDeleteAtSec = now;
      if(isRegime){ g_recAttemptsBuy=0; g_recAttemptsSell=0; }
   }
}

void CloseAllPositions()
{
   bool anyAction = false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType();
      if(t==OP_BUY)
      {
         if(OrderClose(OrderTicket(),OrderLots(),Bid,(int)SlippagePoints,clrAqua))
            anyAction = true;
         else
            Print("OrderClose BUY failed ",GetLastError());
      }
      else if(t==OP_SELL)
      {
         if(OrderClose(OrderTicket(),OrderLots(),Ask,(int)SlippagePoints,clrAqua))
            anyAction = true;
         else
            Print("OrderClose SELL failed ",GetLastError());
      }
      else
      {
         if(OrderDelete(OrderTicket()))
            anyAction = true;
         else
            Print("OrderDelete failed ",GetLastError());
      }
   }
   if(anyAction)
   {
      datetime now = TimeCurrent();
      g_lastRebuildAt       = now;
      g_lastMassDeleteAtSec = now;
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

void DrawClosedTradeMarkersEnhanced()
{
   int hist = OrdersHistoryTotal();
   for(int i=hist-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int  t = OrderType(); if(!(t==OP_BUY || t==OP_SELL)) continue;

      int      tk    = OrderTicket();
      datetime tOpen = OrderOpenTime();
      double   pOpen = OrderOpenPrice();
      datetime tClose= OrderCloseTime();
      double   pClose= OrderClosePrice();

      double pnl = OrderProfit()+OrderSwap()+OrderCommission();
      bool   win = (pnl >= 0.0);

      string nOpen  = OBJPFX+"TM2_O_"+(string)tk;
      string nClose = OBJPFX+"TM2_C_"+(string)tk;
      string nLine  = OBJPFX+"TM2_L_"+(string)tk;
      string nPL    = OBJPFX+"TM2_P_"+(string)tk;

      if(ObjectFind(nOpen)<0)
      {
         if(ObjectCreate(nOpen, OBJ_ARROW, 0, tOpen, pOpen))
         {
            ObjectSet(nOpen, OBJPROP_ARROWCODE, 159);
            ObjectSet(nOpen, OBJPROP_COLOR, (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
            ObjectSetText(nOpen, "", 8, "Arial", (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
         }
      }

      if(ObjectFind(nClose)<0)
      {
         if(ObjectCreate(nClose, OBJ_ARROW, 0, tClose, pClose))
         {
            ObjectSet(nClose, OBJPROP_ARROWCODE, 159);
            ObjectSet(nClose, OBJPROP_COLOR, (win ? MarkerWinLineColor : MarkerLoseLineColor));
            ObjectSetText(nClose, "", 8, "Arial", (win ? MarkerWinLineColor : MarkerLoseLineColor));
         }
      }

      if(ObjectFind(nLine)<0)
      {
         if(ObjectCreate(nLine, OBJ_TREND, 0, tOpen, pOpen, tClose, pClose))
         {
            ObjectSet(nLine, OBJPROP_COLOR, (win ? MarkerWinLineColor : MarkerLoseLineColor));
            ObjectSet(nLine, OBJPROP_STYLE, (win ? MarkerLineStyleWin : MarkerLineStyleLose));
            ObjectSet(nLine, OBJPROP_WIDTH, MarkerLineWidth);
         }
      }

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

void DrawOpenTradeMarkersEnhanced()
{
   datetime nowT = Time[0];
   double   bid  = Bid, ask = Ask;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;

      int t = OrderType(); if(!(t==OP_BUY || t==OP_SELL)) continue;

      int      tk    = OrderTicket();
      datetime tOpen = OrderOpenTime();
      double   pOpen = OrderOpenPrice();
      double   curPrice = (t==OP_BUY ? bid : ask);
      double   pnl      = OrderProfit()+OrderSwap()+OrderCommission();
      bool     win      = (pnl >= 0.0);

      string nOpen  = OBJPFX+"TM2_O2_"+(string)tk;
      string nLine  = OBJPFX+"TM2_L2_"+(string)tk;
      string nPL    = OBJPFX+"TM2_P2_"+(string)tk;

      if(ObjectFind(nOpen)<0)
      {
         if(ObjectCreate(nOpen, OBJ_ARROW, 0, tOpen, pOpen))
         {
            ObjectSet(nOpen, OBJPROP_ARROWCODE, 159);
            ObjectSet(nOpen, OBJPROP_COLOR, (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
            ObjectSetText(nOpen, "", 8, "Arial", (t==OP_BUY ? ColTradeBuyOpen : ColTradeSellOpen));
         }
      }

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
         ObjectMove(nLine, 1, nowT, curPrice);
         ObjectSet(nLine, OBJPROP_COLOR, (win ? MarkerWinLineColor : MarkerLoseLineColor));
         ObjectSet(nLine, OBJPROP_STYLE, (win ? MarkerLineStyleWin : MarkerLineStyleLose));
      }

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
   if(HideDashboardInPreview && g_previewShown) return;
   string nm = OBJPFX+"DASH";
   double stepPrice = g_currentStepPoints*Point;
   string s  = "Range Top="+DoubleToString(g_rangeTop,Digits)+
               "  Ctr="+DoubleToString(g_rangeCtr,Digits)+
               "  Bot="+DoubleToString(g_rangeBot,Digits)+
               "  step="+(string)g_currentStepPoints+" pts (~"+DoubleToString(stepPrice,Digits)+" price)"+
               "  PSI="+(IsNum(g_cachedPsi)?DoubleToString(g_cachedPsi,2):"n/a");
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
   if(HideDashboardInPreview) ObjectDelete(OBJPFX+"DASH");

   if(ForcePanelOnTop)
   {
      long fg=0;
      if(ChartGetInteger(0, CHART_FOREGROUND, 0, fg))
      {
         g_savedForegroundFlag = (fg!=0);
         if(g_savedForegroundFlag){ ChartSetInteger(0, CHART_FOREGROUND, false); g_changedForeground=true; }
      }
   }

   string ids[] = { "PV_BG","PV_T1","PV_T2","PV_T3","PV_T4","BTN_GO","BTN_CANCEL" };
   for(int i=0;i<ArraySize(ids);i++) ObjectDelete(OBJPFX+ids[i]);

   int lh = PanelFontSize + MathMax(0, PreviewLineSpacingPx);
   int yPad = MathMax(0, PanelPaddingTop);
   int sidePad = MathMax(0, PanelPaddingSides);
   int lines = 4;
   int textHeight = lines * lh;
   int baseHeight = yPad + textHeight + ButtonsRowSpacing + PanelButtonH + yPad;
   int bgHeight = PanelAutoHeight ? baseHeight : PanelHeight;
   if(!PanelAutoHeight) bgHeight = MathMax(PanelHeight, baseHeight);
   g_lastPanelHeightPx = bgHeight;

   ObjectCreate(OBJPFX+"PV_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_CORNER,     PanelCorner);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_XDISTANCE,  PanelX);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_YDISTANCE,  PanelY);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_XSIZE,      PanelWidth);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_YSIZE,      bgHeight);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_COLOR,      PanelBorderColor);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_BGCOLOR,    PanelBgColor);
   ObjectSet(OBJPFX+"PV_BG", OBJPROP_BACK,       false);

   string modeStr = (effMode==0? "Pullback (Limit-in-trend)" : (effMode==1? "Breakout (Stop-with-trend)" : "PAUSE"));
   string dirStr  = (trendDir>0? "UP (long-only)" : (trendDir<0? "DOWN (short-only)" : "Neutral"));
   string t1 = "Preview ("+reason+")";
   string t2 = "Strategy: "+modeStr+"  |  Direction: "+dirStr;
   string t3 = "Squeeze PSI (last closed): "+(IsNum(psiNow)? DoubleToString(psiNow,2):"n/a")+
               "   Gate(PauseAbove): "+DoubleToString(PSIPauseAbove,1);
   string t4 = "Grid: LevelsEachSide="+(string)GridLevelsEachSide+
               "   Step="+(string)stepPts+" pts  (~"+DoubleToString(stepPrice,Digits)+")"+
               "   NearestK="+(string)NearestK;

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
   string ids[] = { "PV_BG","PV_T1","PV_T2","PV_T3","PV_T4","BTN_GO","BTN_CANCEL" };
   for(int i=0;i<ArraySize(ids);i++) ObjectDelete(OBJPFX+ids[i]);
   g_previewShown = false;
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
   // Hard PSI pause takes priority
   if(UseSqueezeFilter && IsNum(psiNow) && UsePSIHighPause && psiNow>PSIPauseAbove) return -1; // Pause

   // Keep legacy mapping for compatibility (does not force entry type now)
   if(StrategyProfile==Strategy_PullbackOnly) return 0;
   if(StrategyProfile==Strategy_BreakoutOnly) return 1;

   if(SqueezeMode==SQ_Pullback) return 0;
   if(SqueezeMode==SQ_Breakout) return 1;
   if(SqueezeMode==SQ_Pause)    return -1;

   if(!UseSqueezeFilter || !IsNum(psiNow)) return 0;
   if(psiNow < PSI_Low)  return 1;
   if(psiNow > PSI_High) return 0;
   return 0;
}

/******************** PRESETS **************************************/
void ApplyRiskPresetIfEnabled()
{
   if(!UseRiskPreset) return;
   if(RiskPreset==Preset_RiskAware)
   {
      if(!UseATRScaledBuffer) Print("Preset(RiskAware): Consider enabling UseATRScaledBuffer.");
      if(BreakoutCloseConfirmBars<1) Print("Preset(RiskAware): Consider BreakoutCloseConfirmBars=1.");
   }
   else if(RiskPreset==Preset_Natural)
   {
      if(!UsePerOrderSLMoney || UseATR_SL || UseGridAwareSL) Print("Preset(Natural): MoneySL-only suggested for your current tests.");
      if(!UseATRScaledBuffer) Print("Preset(Natural): Consider ATR buffer ON (UseATRScaledBuffer=true).");
   }
}

/******************** INIT / DEINIT / TICK / EVENTS ***************/
int OnInit()
{
   DigitsAdjust = (int)MarketInfo(Symbol(), MODE_DIGITS);
   ArrayInitialize(g_closedTickets,-1);
   DeleteAllObjects();

   if(VisualRefreshSeconds > 0) EventSetTimer(MathMax(1, VisualRefreshSeconds));

   ApplyRiskPresetIfEnabled();

   ComputeRangeAndStep();
   RedrawVisuals();

   bool inTester = (IsTesting() || IsOptimization());
   if(inTester && AutoProceedInTester) g_tradingPaused = false;
   else                                g_tradingPaused = (ConfirmOnAttach || ConfirmOnParamChange);

   double psiPrev=EMPTY_VALUE;
   double psiNow = UseSqueezeFilter ? SqueezePSI_TF(SqueezeTF, SQ_ConvFactor, SQ_Length, 1200, psiPrev) : 0.0;
   g_cachedPsi = psiNow;

   int stPrev=0; int trendDir = UseTrendFilter ? SupertrendDirectionTF(TrendTF, ST_ATR_Period, ST_Factor, 1200, stPrev) : 0;
   g_lastTrendDir = trendDir; g_trendLastFlipAt = Time[0];
   int effMode = EffectiveModeByStrategy(psiNow);
   g_lastEffMode = effMode;

   g_prevEffModeForStable = effMode;
   g_modeStableBars = 0;

   double stepPrice = g_currentStepPoints*Point;

   if(g_tradingPaused && !inTester)
      ShowPreviewPanelNow("attach/params", effMode, trendDir, psiNow, stepPrice, g_currentStepPoints);

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
   if(ForcePanelOnTop && g_changedForeground)
      ChartSetInteger(0, CHART_FOREGROUND, g_savedForegroundFlag);

   if(VisualRefreshSeconds > 0) EventKillTimer();
   if(CleanOnDeinit) DeleteAllObjects();
}

void HandlePerOrderBreakeven(int trendDir,int stepPts)
{
   if(!UsePerOrderBE) return;

   int triggerPts_dist = BE_UseStepFrac ? (int)MathRound(MathMax(0.1,BE_TriggerStepFrac) * MathMax(1,stepPts))
                                        : MathMax(1,BE_TriggerPoints);
   int lockPts         = MathMax(0,BE_LockPoints);

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
      int t=OrderType(); if(!(t==OP_BUY||t==OP_SELL)) continue;

      if(BE_OnlyWhenWithTrend && UseTrendFilter)
      {
         if((t==OP_BUY && g_lastTrendDir<0) || (t==OP_SELL && g_lastTrendDir>0)) continue;
      }

      double open=OrderOpenPrice();
      double cur  = (t==OP_BUY? Bid: Ask);
      int inPts   = (int)MathFloor(( (t==OP_BUY? (cur-open):(open-cur)) )/Point);

      bool distanceTrigger = (inPts >= triggerPts_dist);

      double pnlMoney = OrderProfit()+OrderSwap()+OrderCommission();
      bool moneyTrigger = (UsePerOrderBE_Money && PerOrderBE_ProfitMoney>0.0 && pnlMoney >= PerOrderBE_ProfitMoney);

      if(!(distanceTrigger || moneyTrigger)) continue;

      double bePrice = (t==OP_BUY? (open + lockPts*Point) : (open - lockPts*Point));
      double curSL   = OrderStopLoss();
      bool needMod   = (curSL==0.0) || ( (t==OP_BUY && bePrice>curSL+Point) || (t==OP_SELL && bePrice<curSL-Point) );
      if(needMod)
      {
         double newSL=NormalizeDouble(bePrice,DigitsAdjust), keepTP=OrderTakeProfit();
         bool ok=ModifyOrderSLTPWithRetry(OrderTicket(),newSL,keepTP,clrYellow,DigitsAdjust);
         if(!ok) Print("BE: SL move failed tk=",OrderTicket()," err=",GetLastError()," PnL=$",DoubleToString(pnlMoney,2));
      }
   }
}

void OnTick()
{
   bool newBar = (Time[0] != g_lastBarTime);

   ComputeRangeAndStep();

   bool rebuiltNow = false;

   // Recenter on shift (guarded)
   bool recentered=false;
   if(RecenterWhenRangeShifts && IsNum(g_prevTop) && IsNum(g_prevBot) && IsNum(g_rangeCtr))
   {
      bool allowCheck = (!RecenterCheckOnNewBarOnly) || newBar;
      if(allowCheck && (TimeCurrent() - g_lastRebuildAt) >= RebuildThrottleSeconds)
      {
         double prevH = g_prevTop - g_prevBot; if(prevH < 5*Point) prevH = 5*Point;
         double shiftPct = 100.0*MathAbs(g_rangeCtr - g_prevCtr)/prevH;
         if(shiftPct >= RecenterThresholdPct)
         {
            if(KeepHistoricalRangeMarks && ShowVisualDebug && DrawRangeLines) SnapshotOldRange();
            CancelPendingOrdersGuarded(EffectiveModeByStrategy(g_cachedPsi), g_lastTrendDir, false);
            recentered = true;
            rebuiltNow = true;
         }
      }
   }

   g_prevTop=g_rangeTop; g_prevBot=g_rangeBot; g_prevCtr=g_rangeCtr;
   g_prevStepPoints = g_currentStepPoints;

   if(ShowVisualDebug)
   {
      if(DrawRangeLines && (newBar||recentered)) DrawCurrentRangeLines();
      if(DrawGridLevels && (newBar||recentered)) DrawCurrentGridLevels();
      if(ShowDashboard && (newBar||recentered)) DrawDashboard();
      g_lastBarTime=Time[0];
   }

   double eq=AccountEquity(), bal=AccountBalance();
   if(ExitPriorityOrder==Exit_MaxDDFirst && MaxTotalDDPercent>0 && bal>0)
   {
      double ddPct=100.0*(bal-eq)/bal;
      if(ddPct>=MaxTotalDDPercent){ if(CloseAllOnMaxDD) CloseAllPositions(); }
   }

   if(g_tradingPaused)
   {
      ClearTradeMarkers();
      return;
   }

   int stPrev=0;
   int trendDir = UseTrendFilter ? SupertrendDirectionTF(TrendTF, ST_ATR_Period, ST_Factor, 1200, stPrev) : 0;
   g_lastTrendDir = trendDir;
   int stableBars = StableTrendBars(trendDir);

   double psiPrev=EMPTY_VALUE;
   double psiNow  = UseSqueezeFilter ? SqueezePSI_TF(SqueezeTF, SQ_ConvFactor, SQ_Length, 1200, psiPrev) : 0.0;
   g_cachedPsi = psiNow;

   int effMode = EffectiveModeByStrategy(psiNow);

   if(newBar)
   {
      if(effMode == g_prevEffModeForStable) g_modeStableBars++;
      else { g_prevEffModeForStable = effMode; g_modeStableBars = 1; }
   }

   if(AutoRebuildOnRegimeChange && effMode!=g_lastEffMode)
   {
      if(newBar && g_modeStableBars >= MathMax(1, RegimeChangeConfirmBars) &&
         (TimeCurrent() - g_lastRebuildAt) >= RebuildThrottleSeconds)
      {
         CancelPendingOrdersGuarded(effMode, trendDir, true);
         g_lastEffMode = effMode;
         rebuiltNow = true;
      }
      else
      {
         g_lastEffMode = effMode;
      }
   }

   int stepPts=MathMax(1,g_currentStepPoints);

   // PROTECTION PRIORITY
   // 1) Cluster BE (subset)
   if(effMode!=-1) // only if not paused
   {
      if(TryClusterBE()) return; // after subset action, skip placements this tick
   }

   // 2) Basket BE
   TryBasketBreakeven();

   // 3) MaxDD already handled above if priority chosen

   // 4) Per-order BE (if enabled and prioritized)
   if(UsePerOrderBE && ExitPriorityOrder==Exit_PerOrderBEFirst) HandlePerOrderBreakeven(trendDir,stepPts);

   if(rebuiltNow) return;
   if(g_lastMassDeleteAtSec!=0 && TimeCurrent()==g_lastMassDeleteAtSec) return;

   // PSI gate pause
   if(effMode==-1) return;

   // ENTRIES (hybrid)
   double buyLvls[128], sellLvls[128]; int nB=0,nS=0;
   BuildGridLevels(buyLvls,nB,sellLvls,nS);

   if(AllowNewTrades)
   {
      if(!UseTrendFilter || trendDir!=0)
         ManageEntriesHybrid(trendDir,buyLvls,nB,sellLvls,nS);
   }

   // Optional ATR trailing
   if(UseATR_Trailing)
   {
      double atr = GetATR(ATRTrail_TF, ATRTrail_Period, 1);
      if(atr>0)
      {
         int minStep= MathMax(1, TrailStepMinPoints);
         for(int i=OrdersTotal()-1;i>=0;i--)
         {
            if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
            if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber) continue;
            int t=OrderType(); if(!(t==OP_BUY||t==OP_SELL)) continue;

            double trailDistPts = (atr/Point)*MathMax(0.1, ATRTrail_Mult);
            double newSL=0.0;

            if(t==OP_BUY)
            {
               double candidate = Bid - trailDistPts*Point;
               if(OrderStopLoss()==0 || candidate > OrderStopLoss()+minStep*Point)
                  newSL = NormalizeDouble(candidate, DigitsAdjust);
            }
            else
            {
               double candidate = Ask + trailDistPts*Point;
               if(OrderStopLoss()==0 || candidate < OrderStopLoss()-minStep*Point)
                  newSL = NormalizeDouble(candidate, DigitsAdjust);
            }

            if(newSL!=0.0)
            {
               double keepTP = OrderTakeProfit();
               bool ok = ModifyOrderSLTPWithRetry(OrderTicket(), newSL, keepTP, clrYellow, DigitsAdjust);
               if(!ok)
                  Print("ATR trail: OrderModify failed, ticket=", OrderTicket(), " err=", GetLastError());
            }
         }
      }
   }

   // Trade markers
   if(ShowTradeMarkers)
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

void OnTimer()
{
   ComputeRangeAndStep();
   RedrawVisuals();

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

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
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
         int stPrev=0; int trendDir = UseTrendFilter ? SupertrendDirectionTF(TrendTF, ST_ATR_Period, ST_Factor, 400, stPrev) : 0;
         double psiPrev=EMPTY_VALUE;
         double psiNow = UseSqueezeFilter ? SqueezePSI_TF(SqueezeTF, SQ_ConvFactor, SQ_Length, 1200, psiPrev) : 0.0;
         int effMode = EffectiveModeByStrategy(psiNow);
         CancelPendingOrdersGuarded(effMode, trendDir, true);
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
}
//+------------------------------------------------------------------+