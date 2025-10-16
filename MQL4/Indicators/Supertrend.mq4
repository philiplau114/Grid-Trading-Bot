//+------------------------------------------------------------------+
//|                                           Supertrend_tv_clone.mq4|
//| Exact MT4 clone of TradingView's ta.supertrend(factor, period)   |
//| - ATR = Wilder (RMA of True Range)                               |
//| - Basis = HL2 ( (high+low)/2 )                                   |
//| - Final bands filtering with close[1] conditions                  |
//| - Direction flips on close vs previous bands                      |
//| - Plots as line segments (EMPTY_VALUE to break lines)             |
//| - Refreshes every tick (full recompute)                           |
//|                                                                  |
//| This version supports MTF:                                       |
//| - Input Timeframe lets you compute on any TF (incl. current).    |
//| - It computes Supertrend on the selected TF and maps the value   |
//|   and its direction to the chart bars.                           |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1 clrGreen   // Uptrend segments
#property indicator_color2 clrRed     // Downtrend segments
#property indicator_width1 2
#property indicator_width2 2

input int    ATRPeriod = 10;     // TradingView default: 10
input double Factor    = 3.0;    // TradingView default: 3.0
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // NEW: compute on this TF

double UpTrend[];    // plotted on chart timeframe
double DownTrend[];

// Internal working (chart TF branch)
double TR[];         // True Range
double ATR[];        // Wilder ATR
double UB[];         // basic upper band = hl2 + factor*atr
double LB[];         // basic lower band = hl2 - factor*atr
double FU[];         // final upper band (filtered)
double FL[];         // final lower band (filtered)
int    DIR[];        // direction: -1 = uptrend, +1 = downtrend

// Internal working (MTF branch)
double tf_close[], tf_high[], tf_low[];
double tf_ATR[], tf_FU[], tf_FL[];
int    tf_DIR[];
double tf_ST[]; // supertrend value chosen per bar (TF space)

int OnInit()
{
   string tfName = (Timeframe==PERIOD_CURRENT ? "Chart" : IntegerToString(Timeframe));
   IndicatorShortName("Supertrend (TV clone) - TF: " + tfName);

   SetIndexBuffer(0, UpTrend);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2);
   SetIndexLabel(0, "Up Trend");

   SetIndexBuffer(1, DownTrend);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 2);
   SetIndexLabel(1, "Down Trend");

   ArraySetAsSeries(UpTrend, true);
   ArraySetAsSeries(DownTrend, true);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total <= 0 || ATRPeriod < 1) return 0;

   // Clear outputs (line breaks handled by EMPTY_VALUE)
   ArrayInitialize(UpTrend,   EMPTY_VALUE);
   ArrayInitialize(DownTrend, EMPTY_VALUE);

   if(Timeframe == PERIOD_CURRENT)
   {
      // Chart-TF computation (original logic)
      ArrayResize(TR,  rates_total);
      ArrayResize(ATR, rates_total);
      ArrayResize(UB,  rates_total);
      ArrayResize(LB,  rates_total);
      ArrayResize(FU,  rates_total);
      ArrayResize(FL,  rates_total);
      ArrayResize(DIR, rates_total);

      ArraySetAsSeries(TR,  true);
      ArraySetAsSeries(ATR, true);
      ArraySetAsSeries(UB,  true);
      ArraySetAsSeries(LB,  true);
      ArraySetAsSeries(FU,  true);
      ArraySetAsSeries(FL,  true);
      ArraySetAsSeries(DIR, true);

      // 1) True Range
      for(int i = rates_total - 1; i >= 0; --i)
      {
         double prevClose = (i == rates_total - 1) ? close[i] : close[i+1];
         double r1 = high[i] - low[i];
         double r2 = MathAbs(high[i] - prevClose);
         double r3 = MathAbs(low[i]  - prevClose);
         TR[i] = MathMax(r1, MathMax(r2, r3));
      }

      // 2) Wilder ATR (RMA)
      int firstSeed = rates_total - ATRPeriod;
      if(firstSeed < 0) firstSeed = rates_total - 1;

      double sumTR = 0.0;
      bool   seeded = false;
      double atrPrev = 0.0;

      for(int i = rates_total - 1; i >= 0; --i)
      {
         if(i >= firstSeed)
         {
            sumTR += TR[i];
            if(i == firstSeed)
            {
               ATR[i] = sumTR / ATRPeriod;
               atrPrev = ATR[i];
               seeded = true;
            }
            else
            {
               ATR[i] = 0.0;
            }
         }
         else
         {
            if(seeded)
            {
               ATR[i]  = (atrPrev * (ATRPeriod - 1) + TR[i]) / ATRPeriod;
               atrPrev = ATR[i];
            }
            else
               ATR[i] = 0.0;
         }
      }

      // 3) Bands and direction
      for(int i = rates_total - 1; i >= 0; --i)
      {
         if(ATR[i] <= 0.0)
         {
            DIR[i] = 1;
            continue;
         }

         double hl2 = 0.5 * (high[i] + low[i]);
         UB[i] = hl2 + Factor * ATR[i];
         LB[i] = hl2 - Factor * ATR[i];

         if(i == rates_total - 1)
         {
            FU[i]  = UB[i];
            FL[i]  = LB[i];
            DIR[i] = 1;
         }
         else
         {
            double FUprev  = FU[i+1];
            double FLprev  = FL[i+1];
            double cPrev   = close[i+1];

            FU[i] = (UB[i] < FUprev || cPrev > FUprev) ? UB[i] : FUprev;
            FL[i] = (LB[i] > FLprev || cPrev < FLprev) ? LB[i] : FLprev;

            int dirPrev = DIR[i+1];
            int dir = dirPrev;
            if(close[i] > FUprev)      dir = -1; // uptrend
            else if(close[i] < FLprev) dir = 1;  // downtrend
            DIR[i] = dir;
         }

         double st = (DIR[i] < 0) ? FL[i] : FU[i];

         if(DIR[i] < 0)
         {
            UpTrend[i]   = st;
            DownTrend[i] = EMPTY_VALUE;
         }
         else
         {
            UpTrend[i]   = EMPTY_VALUE;
            DownTrend[i] = st;
         }
      }

      return(rates_total);
   }

   // --------- MTF branch ----------
   int tfBars = iBars(NULL, Timeframe);
   if(tfBars <= 0) return rates_total;

   // Determine how many TF bars to fetch to cover the chart range
   datetime oldestChartTime = time[rates_total-1];
   int oldestShift = iBarShift(NULL, Timeframe, oldestChartTime, true);
   if(oldestShift < 0) oldestShift = tfBars - 1;
   int wantCount = oldestShift + 1;
   if(wantCount > tfBars) wantCount = tfBars;

   // Resize TF arrays (series orientation)
   ArrayResize(tf_close, wantCount);
   ArrayResize(tf_high,  wantCount);
   ArrayResize(tf_low,   wantCount);
   ArrayResize(tf_ATR,   wantCount);
   ArrayResize(tf_FU,    wantCount);
   ArrayResize(tf_FL,    wantCount);
   ArrayResize(tf_DIR,   wantCount);
   ArrayResize(tf_ST,    wantCount);

   ArraySetAsSeries(tf_close, true);
   ArraySetAsSeries(tf_high,  true);
   ArraySetAsSeries(tf_low,   true);
   ArraySetAsSeries(tf_ATR,   true);
   ArraySetAsSeries(tf_FU,    true);
   ArraySetAsSeries(tf_FL,    true);
   ArraySetAsSeries(tf_DIR,   true);
   ArraySetAsSeries(tf_ST,    true);

   // Load TF OHLC via i* (series: shift 0=current)
   for(int sh=0; sh<wantCount; ++sh)
   {
     tf_close[sh] = iClose(NULL, Timeframe, sh);
     tf_high[sh]  = iHigh (NULL, Timeframe, sh);
     tf_low[sh]   = iLow  (NULL, Timeframe, sh);
   }

   // True Range on TF and Wilder ATR
   int seedShift = wantCount - 1 - (ATRPeriod - 1);
   if(seedShift < 0) seedShift = wantCount - 1;

   double sumTR = 0.0;
   bool   seeded = false;
   double atrPrev = 0.0;

   for(int sh = wantCount - 1; sh >= 0; --sh)
   {
      double prevClose = (sh == wantCount - 1) ? tf_close[sh] : tf_close[sh+1];
      double r1 = tf_high[sh] - tf_low[sh];
      double r2 = MathAbs(tf_high[sh] - prevClose);
      double r3 = MathAbs(tf_low[sh]  - prevClose);
      double TRv = MathMax(r1, MathMax(r2, r3));

      if(sh >= seedShift)
      {
         sumTR += TRv;
         if(sh == seedShift)
         {
            tf_ATR[sh] = sumTR / ATRPeriod;
            atrPrev = tf_ATR[sh];
            seeded = true;
         }
         else
            tf_ATR[sh] = 0.0;
      }
      else
      {
         if(seeded)
         {
            tf_ATR[sh]  = (atrPrev * (ATRPeriod - 1) + TRv) / ATRPeriod;
            atrPrev = tf_ATR[sh];
         }
         else
            tf_ATR[sh] = 0.0;
      }
   }

   // Bands + direction on TF
   for(int sh = wantCount - 1; sh >= 0; --sh)
   {
      if(tf_ATR[sh] <= 0.0)
      {
         tf_DIR[sh] = 1;
         tf_FU[sh]  = tf_FL[sh] = 0.0;
         tf_ST[sh]  = 0.0;
         continue;
      }

      double hl2 = 0.5 * (tf_high[sh] + tf_low[sh]);
      double basicUB = hl2 + Factor * tf_ATR[sh]; // renamed to avoid hiding globals
      double basicLB = hl2 - Factor * tf_ATR[sh];

      if(sh == wantCount - 1)
      {
         tf_FU[sh]  = basicUB;
         tf_FL[sh]  = basicLB;
         tf_DIR[sh] = 1;
      }
      else
      {
         double FUprev = tf_FU[sh+1];
         double FLprev = tf_FL[sh+1];
         double cPrev  = tf_close[sh+1];

         tf_FU[sh] = (basicUB < FUprev || cPrev > FUprev) ? basicUB : FUprev;
         tf_FL[sh] = (basicLB > FLprev || cPrev < FLprev) ? basicLB : FLprev;

         int dirPrev = tf_DIR[sh+1];
         int dir = dirPrev;
         if(tf_close[sh] > FUprev)      dir = -1;
         else if(tf_close[sh] < FLprev) dir = 1;
         tf_DIR[sh] = dir;
      }

      tf_ST[sh] = (tf_DIR[sh] < 0 ? tf_FL[sh] : tf_FU[sh]);
   }

   // Map TF values to chart bars
   for(int i=rates_total-1; i>=0; --i)
   {
      int sh = iBarShift(NULL, Timeframe, time[i], false);
      if(sh<0 || sh>=wantCount) continue;

      int dir = tf_DIR[sh];
      double st = tf_ST[sh];

      if(dir < 0)
      {
         UpTrend[i]   = st;
         DownTrend[i] = EMPTY_VALUE;
      }
      else
      {
         UpTrend[i]   = EMPTY_VALUE;
         DownTrend[i] = st;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+