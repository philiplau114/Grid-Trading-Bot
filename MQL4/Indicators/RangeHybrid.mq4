//+------------------------------------------------------------------+
//|                                                 RangeHybrid_Lite |
//| Two-layer range indicator (no Structural layer):                 |
//|  - Window rectangle: highest/lowest in the last N bars           |
//|  - Envelope rectangle: macro bounds (either Price or ZigZag piv) |
//|                                                                  |
//| Buffers (series, 0 = current bar):                               |
//|  0 Window Top, 1 Window Bottom, 2 Window Center                  |
//|  3 Envelope Top, 4 Envelope Bottom, 5 Envelope Center            |
//|                                                                  |
//| Notes:                                                           |
//| - No Structural layer.                                           |
//| - Envelope can use ZigZag pivots or plain price extremes.        |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots   6
#property indicator_buffers 6

// Window
#property indicator_label1  "Window Top"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Window Bottom"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "Window Center"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGold
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

// Envelope
#property indicator_label4  "Envelope Top"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrPurple
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

#property indicator_label5  "Envelope Bottom"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDodgerBlue
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#property indicator_label6  "Envelope Center"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrSilver
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

//---------------- Inputs ----------------
input group "Window Range"
input int  WindowBars            = 100;   // Lookback length
input bool UseCompletedBars      = true;  // Exclude the forming bar
input bool ShowWindowHistorical  = false; // Plot rolling history or flat last window
input bool ShowWindowLines       = true;
input bool ShowWindowCenter      = true;

input group "Envelope Range"
enum eEnvMode { Envelope_PriceExtremes=0, Envelope_ZigZagPivots=1 };
input eEnvMode EnvelopeMode      = Envelope_PriceExtremes;
input int  EnvelopeLookbackBars  = 500;   // Window for envelope calculation
input bool ShowEnvelopeLines     = true;
input bool ShowEnvelopeCenter    = true;

// ZigZag parameters used only if EnvelopeMode=Envelope_ZigZagPivots
input int  ZZ_Depth              = 12;
input int  ZZ_DeviationPoints    = 5;     // points
input int  ZZ_Backstep           = 3;

//---------------- Buffers ----------------
double WinTop[], WinBot[], WinMid[];
double EnvTop[], EnvBot[], EnvMid[];

// Internal (ZigZag) for envelope pivots
double HiBuf[], LoBuf[];

int OnInit()
{
  IndicatorShortName("RangeHybrid_Lite (Window + Envelope)");
  // Binds
  SetIndexBuffer(0, WinTop); ArraySetAsSeries(WinTop, true); SetIndexEmptyValue(0, EMPTY_VALUE);
  SetIndexBuffer(1, WinBot); ArraySetAsSeries(WinBot, true); SetIndexEmptyValue(1, EMPTY_VALUE);
  SetIndexBuffer(2, WinMid); ArraySetAsSeries(WinMid, true); SetIndexEmptyValue(2, EMPTY_VALUE);

  SetIndexBuffer(3, EnvTop); ArraySetAsSeries(EnvTop, true); SetIndexEmptyValue(3, EMPTY_VALUE);
  SetIndexBuffer(4, EnvBot); ArraySetAsSeries(EnvBot, true); SetIndexEmptyValue(4, EMPTY_VALUE);
  SetIndexBuffer(5, EnvMid); ArraySetAsSeries(EnvMid, true); SetIndexEmptyValue(5, EMPTY_VALUE);

  return(INIT_SUCCEEDED);
}

void Clear(double &buf[]){ ArrayInitialize(buf, EMPTY_VALUE); }

// Window rectangle
void ComputeWindow(const int total)
{
  Clear(WinTop); Clear(WinBot); Clear(WinMid);
  if(!ShowWindowLines && !ShowWindowCenter) return;
  if(WindowBars<=0 || total<=0) return;

  int startOff = (UseCompletedBars ? 1 : 0);

  if(ShowWindowHistorical)
  {
    int firstIndex = total - (WindowBars + startOff);
    if(firstIndex < 0) firstIndex = 0;

    for(int i = firstIndex; i >= 0; --i)
    {
      int count = WindowBars;
      int start = i + startOff;
      if(start + count > total) continue;

      int pHi = iHighest(NULL, 0, MODE_HIGH, count, start);
      int pLo = iLowest (NULL, 0, MODE_LOW,  count, start);
      if(pHi<0 || pLo<0) continue;

      double top = High[pHi];
      double bot = Low [pLo];
      double mid = 0.5*(top+bot);

      if(ShowWindowLines){ WinTop[i]=top; WinBot[i]=bot; }
      if(ShowWindowCenter){ WinMid[i]=mid; }
    }
  }
  else
  {
    int count = WindowBars;
    int start = startOff;
    if(start + count > total) count = total - start;
    if(count <= 0) return;

    int pHi = iHighest(NULL, 0, MODE_HIGH, count, start);
    int pLo = iLowest (NULL, 0, MODE_LOW,  count, start);
    if(pHi<0 || pLo<0) return;

    double top = High[pHi];
    double bot = Low [pLo];
    double mid = 0.5*(top+bot);

    int endBar = start + count - 1;
    for(int i = start; i <= endBar; ++i)
    {
      if(ShowWindowLines){ WinTop[i]=top; WinBot[i]=bot; }
      if(ShowWindowCenter){ WinMid[i]=mid; }
    }
  }
}

// Simple ZigZag detection for envelope (pivots only)
void ZigZag_Pivots(const int total)
{
  ArrayResize(HiBuf,total); ArrayResize(LoBuf,total);
  ArraySetAsSeries(HiBuf,true); ArraySetAsSeries(LoBuf,true);
  ArrayInitialize(HiBuf,0.0); ArrayInitialize(LoBuf,0.0);

  if(total < ZZ_Depth || ZZ_Backstep >= ZZ_Depth) return;

  int limit = total - ZZ_Depth; if(limit<0) limit=0;

  double lastLow=0,lastHigh=0;
  for(int i=limit;i>=0;i--)
  {
    // Low
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
          if(LoBuf[pos]!=0 && LoBuf[pos]>extLow) LoBuf[pos]=0.0;
        }
      }
    }
    LoBuf[i] = (Low[i]==extLow? extLow:0.0);

    // High
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
          if(HiBuf[pos]!=0 && HiBuf[pos]<extHigh) HiBuf[pos]=0.0;
        }
      }
    }
    HiBuf[i] = (High[i]==extHigh? extHigh:0.0);
  }
}

// Envelope rectangle (Price or ZigZag)
void ComputeEnvelope(const int total)
{
  Clear(EnvTop); Clear(EnvBot); Clear(EnvMid);
  if(!ShowEnvelopeLines && !ShowEnvelopeCenter) return;
  if(EnvelopeLookbackBars <= 0) return;

  int startOff = (UseCompletedBars ? 1 : 0);
  int count    = EnvelopeLookbackBars;
  if(startOff + count > total) count = total - startOff;
  if(count <= 0) return;

  double top=EMPTY_VALUE, bot=EMPTY_VALUE;

  if(EnvelopeMode == Envelope_PriceExtremes)
  {
    int pHi = iHighest(NULL,0,MODE_HIGH,count,startOff);
    int pLo = iLowest (NULL,0,MODE_LOW, count,startOff);
    if(pHi>=0 && pLo>=0)
    { top = High[pHi]; bot = Low[pLo]; }
  }
  else // Envelope_ZigZagPivots
  {
    ZigZag_Pivots(total);

    double hiBest=-1e100, loBest=1.0e100;
    int start = startOff, endBar = startOff + count - 1;
    for(int i=start;i<=endBar;i++)
    {
      if(HiBuf[i]!=0.0 && HiBuf[i]>hiBest) hiBest=HiBuf[i];
      if(LoBuf[i]!=0.0 && LoBuf[i]<loBest) loBest=LoBuf[i];
    }
    if(hiBest > loBest){ top=hiBest; bot=loBest; }
    else
    {
      // fallback to price extremes if pivots not found in window
      int pHi = iHighest(NULL,0,MODE_HIGH,count,startOff);
      int pLo = iLowest (NULL,0,MODE_LOW, count,startOff);
      if(pHi>=0 && pLo>=0)
      { top = High[pHi]; bot = Low[pLo]; }
    }
  }

  if(top==EMPTY_VALUE || bot==EMPTY_VALUE || top<=bot) return;
  double mid = 0.5*(top+bot);

  int s = startOff, e = startOff + count - 1;
  for(int i=s;i<=e;i++)
  {
    if(ShowEnvelopeLines){ EnvTop[i]=top; EnvBot[i]=bot; }
    if(ShowEnvelopeCenter){ EnvMid[i]=mid; }
  }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
  if(rates_total<=0) return 0;

  ArraySetAsSeries(WinTop,true); ArraySetAsSeries(WinBot,true); ArraySetAsSeries(WinMid,true);
  ArraySetAsSeries(EnvTop,true); ArraySetAsSeries(EnvBot,true); ArraySetAsSeries(EnvMid,true);
  ArraySetAsSeries(HiBuf,true);  ArraySetAsSeries(LoBuf,true);

  ComputeWindow(rates_total);
  ComputeEnvelope(rates_total);

  return(rates_total);
}
//+------------------------------------------------------------------+