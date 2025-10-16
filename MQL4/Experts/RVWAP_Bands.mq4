#property strict
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_color1 Orange
#property indicator_color2 Lime
#property indicator_color3 Lime
#property indicator_color4 Yellow
#property indicator_color5 Yellow
#property indicator_color6 Red
#property indicator_color7 Red
#property indicator_width  1

// Rolling VWAP with optional StdDev bands (buffer-based plotting for MT4)

// Inputs
enum VwapWeight { TickVolume=0, EqualWeight=1 };
input VwapWeight VWAP_WeightMode = TickVolume;

enum VwapWindowMode { Rolling=0, Daily=1, Session=2 };
input VwapWindowMode VwapMode     = Rolling;

input bool  UseFixedTimeWindow    = false;
input int   WindowDays            = 1;
input int   WindowHours           = 0;
input int   WindowMinutes         = 0;
input int   MinBarsInWindow       = 10;

input double StdevMult1           = 0.0;
input double StdevMult2           = 0.0;
input double StdevMult3           = 0.0;

input int    LineWidth            = 2;
input color  ColVWAP              = clrOrange;
input color  ColBand1             = clrLime;
input color  ColBand2             = clrYellow;
input color  ColBand3             = clrRed;

// Buffers
double bVWAP[];
double bU1[], bL1[];
double bU2[], bL2[];
double bU3[], bL3[];

// Helpers
int TFSeconds() { return Period()*60; }

int AutoWindowMsForTF() {
   int MS_IN_MIN=60*1000, MS_IN_HOUR=60*60*1000, MS_IN_DAY=24*MS_IN_HOUR;
   int tfMs = TFSeconds()*1000;
   int ONE_MONTH_MS = 30*MS_IN_DAY + 10*MS_IN_HOUR + 30*MS_IN_MIN; // ~30.4375d
   if (tfMs <= MS_IN_MIN)      return MS_IN_HOUR;
   if (tfMs <= 5*MS_IN_MIN)    return 4*MS_IN_HOUR;
   if (tfMs <= MS_IN_HOUR)     return MS_IN_DAY;
   if (tfMs <= 4*MS_IN_HOUR)   return 3*MS_IN_DAY;
   if (tfMs <= 12*MS_IN_HOUR)  return 7*MS_IN_DAY;
   if (tfMs <= MS_IN_DAY)      return ONE_MONTH_MS;
   if (tfMs <= 7*MS_IN_DAY)    return 90*MS_IN_DAY;
   return 365*MS_IN_DAY;
}

int WindowMs() {
   if (VwapMode != Rolling) return AutoWindowMsForTF(); // keep Rolling focus for Step 1
   if (UseFixedTimeWindow) {
      int MS_IN_MIN=60*1000, MS_IN_HOUR=60*60*1000, MS_IN_DAY=24*MS_IN_HOUR;
      return WindowMinutes*MS_IN_MIN + WindowHours*MS_IN_HOUR + WindowDays*MS_IN_DAY;
   }
   return AutoWindowMsForTF();
}

int OnInit() {
   IndicatorDigits(Digits);

   IndicatorBuffers(7);
   // vwap
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, LineWidth, ColVWAP);
   SetIndexBuffer(0, bVWAP);
   SetIndexLabel(0, "RVWAP");

   // bands
   SetIndexStyle(1, (StdevMult1>0? DRAW_LINE: DRAW_NONE), STYLE_SOLID, 1, ColBand1);
   SetIndexBuffer(1, bU1); SetIndexLabel(1, "U1");

   SetIndexStyle(2, (StdevMult1>0? DRAW_LINE: DRAW_NONE), STYLE_SOLID, 1, ColBand1);
   SetIndexBuffer(2, bL1); SetIndexLabel(2, "L1");

   SetIndexStyle(3, (StdevMult2>0? DRAW_LINE: DRAW_NONE), STYLE_SOLID, 1, ColBand2);
   SetIndexBuffer(3, bU2); SetIndexLabel(3, "U2");

   SetIndexStyle(4, (StdevMult2>0? DRAW_LINE: DRAW_NONE), STYLE_SOLID, 1, ColBand2);
   SetIndexBuffer(4, bL2); SetIndexLabel(4, "L2");

   SetIndexStyle(5, (StdevMult3>0? DRAW_LINE: DRAW_NONE), STYLE_SOLID, 1, ColBand3);
   SetIndexBuffer(5, bU3); SetIndexLabel(5, "U3");

   SetIndexStyle(6, (StdevMult3>0? DRAW_LINE: DRAW_NONE), STYLE_SOLID, 1, ColBand3);
   SetIndexBuffer(6, bL3); SetIndexLabel(6, "L3");

   return(INIT_SUCCEEDED);
}

// Compute rolling VWAP anchored at bar i using a time window in seconds.
// Arrays in OnCalculate are time-ascending when we call ArraySetAsSeries(..., false),
double ComputeVWAP_At(const int i,
                      const datetime time[],
                      const double high[], const double low[], const double close[],
                      const long tick_volume[],
                      const int windowSec, const int minBars,
                      double &stdevOut)
{
   double sumVol=0.0, sumSrcVol=0.0, sumSrc2Vol=0.0;
   int cnt=0;
   datetime anchor = time[i];

   for (int j=i; j>=0; j--) { // walk backwards in time
      int dt = (int)(anchor - time[j]);
      if (dt > windowSec && cnt >= minBars) break;

      double tp = (high[j] + low[j] + close[j]) / 3.0;
      double vol = 1.0;
      if (VWAP_WeightMode == TickVolume) {
         vol = (double)tick_volume[j];
         if (vol <= 0.0) vol = 1.0;
      }
      sumVol     += vol;
      sumSrcVol  += tp * vol;
      sumSrc2Vol += (tp * tp) * vol;
      cnt++;
   }

   if (sumVol <= 0.0) { stdevOut = 0.0; return EMPTY_VALUE; }
   double vwap = sumSrcVol / sumVol;
   double variance = MathMax((sumSrc2Vol / sumVol) - vwap*vwap, 0.0);
   stdevOut = MathSqrt(variance);
   return vwap;
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
   if (rates_total < 5) return 0;

   // Work in ascending index order (0..rates_total-1)
   ArraySetAsSeries(bVWAP, false);
   ArraySetAsSeries(bU1,   false); ArraySetAsSeries(bL1, false);
   ArraySetAsSeries(bU2,   false); ArraySetAsSeries(bL2, false);
   ArraySetAsSeries(bU3,   false); ArraySetAsSeries(bL3, false);

   ArraySetAsSeries(time,        false);
   ArraySetAsSeries(high,        false);
   ArraySetAsSeries(low,         false);
   ArraySetAsSeries(close,       false);
   ArraySetAsSeries(tick_volume, false);

   int start = 0;
   if (prev_calculated > 0) start = prev_calculated - 1;

   int wMs  = WindowMs();
   int wSec = wMs / 1000;

   for (int i=start; i<rates_total; i++) {
      double sd;
      double v = ComputeVWAP_At(i, time, high, low, close, tick_volume, wSec, MinBarsInWindow, sd);
      bVWAP[i] = v;

      if (v != EMPTY_VALUE) {
         bU1[i] = (StdevMult1>0 ? v + StdevMult1*sd : EMPTY_VALUE);
         bL1[i] = (StdevMult1>0 ? v - StdevMult1*sd : EMPTY_VALUE);
         bU2[i] = (StdevMult2>0 ? v + StdevMult2*sd : EMPTY_VALUE);
         bL2[i] = (StdevMult2>0 ? v - StdevMult2*sd : EMPTY_VALUE);
         bU3[i] = (StdevMult3>0 ? v + StdevMult3*sd : EMPTY_VALUE);
         bL3[i] = (StdevMult3>0 ? v - StdevMult3*sd : EMPTY_VALUE);
      } else {
         bU1[i]=bL1[i]=bU2[i]=bL2[i]=bU3[i]=bL3[i]=EMPTY_VALUE;
      }
   }

   return(rates_total);
}