//+------------------------------------------------------------------+
//|                                                    SqueezeIndex  |
//|                                                                  |
//| Original TradingView script by LuxAlgo                           |
//|                                                                  |
//| Notes:                                                           |
//| - Computes the same PSI formula:                                 |
//|     max/min convergence bands -> diff = log(max-min) ->          |
//|     psi = -50 * corr(diff, time, length) + 50                    |
//| - Draws a line for psi<=80 and 'X' markers for psi>80.           |
//| - Fills area above 80 when psi>=80.                              |
//| - Updates every tick.                                            |
//|                                                                  |
//| This version supports MTF:                                       |
//| - Input Timeframe lets you compute on any TF (incl. current).    |
//| - The indicator computes PSI on the selected TF and maps values  |
//|   to the chart bars using iBarShift(time[i]).                    |
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   3

// Plot 0: PSI line (psi <= 80)
#property indicator_label1  "PSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1: Dots (psi > 80) as 'X'
#property indicator_label2  "Dots"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

// Plot 2/3: Fill between PSI and level 80 when psi>=80
#property indicator_label3  "Above80Fill"
#property indicator_type3   DRAW_FILLING
#property indicator_color3  clrFireBrick

// Inputs
extern int  ConvergenceFactor = 50;   // "conv" in the TV script
extern int  Length            = 20;   // correlation window
extern ENUM_APPLIED_PRICE PriceType = PRICE_CLOSE;
extern ENUM_TIMEFRAMES     Timeframe = PERIOD_CURRENT; // NEW: compute on this TF

// Buffers (chart-timeframe aligned)
double gPsiLine[];     // psi values where psi<=80, else EMPTY_VALUE
double gPsiDots[];     // psi values where psi>80, else EMPTY_VALUE
double gFillUpper[];   // psi when psi>=80, else EMPTY_VALUE
double gFillLower[];   // 80 when psi>=80, else EMPTY_VALUE

// Internal working storage (for TF computation)
double tf_diffFwd[];   // diff = log(max - min) in forward order (TF space)
double tf_psiSeries[]; // PSI per TF bar (series orientation: shift 0 = current)

//+------------------------------------------------------------------+
//| Helper: get price by applied price (series arrays)               |
//+------------------------------------------------------------------+
double GetPriceSeries(const int i, const double &open[], const double &high[], const double &low[], const double &close[])
{
   switch(PriceType)
   {
      case PRICE_CLOSE:   return close[i];
      case PRICE_OPEN:    return open[i];
      case PRICE_HIGH:    return high[i];
      case PRICE_LOW:     return low[i];
      case PRICE_MEDIAN:  return 0.5*(high[i] + low[i]);
      case PRICE_TYPICAL: return (high[i] + low[i] + close[i]) / 3.0;
      case PRICE_WEIGHTED:return (high[i] + low[i] + close[i] + close[i]) / 4.0;
      default:            return close[i];
   }
}

//+------------------------------------------------------------------+
//| Helper: get price on an arbitrary TF by shift                    |
//+------------------------------------------------------------------+
double GetPriceTF(const int shift, ENUM_TIMEFRAMES tf)
{
   switch(PriceType)
   {
      case PRICE_CLOSE:    return iClose(NULL, tf, shift);
      case PRICE_OPEN:     return iOpen (NULL, tf, shift);
      case PRICE_HIGH:     return iHigh (NULL, tf, shift);
      case PRICE_LOW:      return iLow  (NULL, tf, shift);
      case PRICE_MEDIAN:   return 0.5*(iHigh(NULL,tf,shift)+iLow(NULL,tf,shift));
      case PRICE_TYPICAL:  return (iHigh(NULL,tf,shift)+iLow(NULL,tf,shift)+iClose(NULL,tf,shift))/3.0;
      case PRICE_WEIGHTED: { double c=iClose(NULL,tf,shift); return (iHigh(NULL,tf,shift)+iLow(NULL,tf,shift)+c+c)/4.0; }
      default:             return iClose(NULL, tf, shift);
   }
}

//+------------------------------------------------------------------+
//| Calculate correlation (population) between a[0..n-1] and         |
//| b = 0..n-1. Returns EMPTY_VALUE if invalid.                      |
//+------------------------------------------------------------------+
double CorrWithSequentialIndex(const double &a[], int startIndex, int n)
{
   if(n <= 1) return EMPTY_VALUE;

   const double meanB = 0.5 * (n - 1);
   const double varB  = ( (double)n * (double)n - 1.0 ) / 12.0;
   if(varB <= 0.0) return EMPTY_VALUE;
   const double sdB   = MathSqrt(varB);

   double sumA = 0.0, sumA2 = 0.0, sumAB = 0.0;

   for(int k = 0; k < n; ++k)
   {
      double ak = a[startIndex + k];
      sumA  += ak;
      sumA2 += ak * ak;
      sumAB += ak * k;
   }

   const double invN  = 1.0 / n;
   const double meanA = sumA * invN;
   const double varA  = (sumA2 * invN) - (meanA * meanA);
   if(varA <= 0.0) return EMPTY_VALUE;
   const double sdA   = MathSqrt(varA);

   const double cov   = (sumAB * invN) - (meanA * meanB);
   if(sdA <= 0.0 || sdB <= 0.0) return EMPTY_VALUE;

   return cov / (sdA * sdB);
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   string tfName = (Timeframe==PERIOD_CURRENT ? "Chart" : IntegerToString(Timeframe));
   IndicatorShortName("Squeeze Index [LuxAlgo] (MT4) - TF: " + tfName);
   IndicatorDigits(2);

   // Buffers
   SetIndexBuffer(0, gPsiLine,   INDICATOR_DATA);
   SetIndexBuffer(1, gPsiDots,   INDICATOR_DATA);
   SetIndexBuffer(2, gFillUpper, INDICATOR_DATA);
   SetIndexBuffer(3, gFillLower, INDICATOR_DATA);

   // Dots as 'X' (Wingdings)
   SetIndexArrow(1, 251);

   // Levels
   SetLevelValue(0, 80.0);
   SetLevelStyle(STYLE_DOT, 1, clrSilver);

   // Empty values
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Compute PSI on a selected TF, producing series array (shift=0 is |
//| current bar). Returns count of bars filled in tf_psiSeries.      |
//+------------------------------------------------------------------+
int ComputePSI_OnTF(const datetime &chart_time[], int rates_total)
{
   ENUM_TIMEFRAMES tf = Timeframe;
   if(tf == PERIOD_CURRENT)
   {
      // We'll compute directly in OnCalculate using the arrays passed in.
      return 0;
   }

   int tfBars = iBars(NULL, tf);
   if(tfBars <= 0) return 0;

   // We want coverage from the oldest visible chart bar time to now
   datetime oldestChartTime = chart_time[rates_total-1];
   int oldestShift = iBarShift(NULL, tf, oldestChartTime, true);
   if(oldestShift < 0) oldestShift = tfBars - 1;

   int wantCount = oldestShift + 1;             // from oldestShift down to 0
   if(wantCount > tfBars) wantCount = tfBars;

   // Forward arrays sized to wantCount
   ArrayResize(tf_diffFwd,  wantCount);
   ArrayResize(tf_psiSeries, wantCount); // we'll fill series orientation later

   // Convergence factor
   double conv = (ConvergenceFactor <= 0) ? 1.0 : (double)ConvergenceFactor;

   // Build forward order from oldest -> newest using shifts: start at oldestShift .. 0
   double maxPrev=0.0, minPrev=0.0; bool hasPrev=false;
   int k=0;
   for(int sh = oldestShift; sh >= 0; --sh, ++k)
   {
      double s = GetPriceTF(sh, tf);

      if(!hasPrev)
      {
         maxPrev = s; minPrev = s; hasPrev=true;
      }
      else
      {
         double maxCandidate = maxPrev - (maxPrev - s) / conv;
         maxPrev = (s > maxCandidate ? s : maxCandidate);

         double minCandidate = minPrev + (s - minPrev) / conv;
         minPrev = (s < minCandidate ? s : minCandidate);
      }

      double delta = maxPrev - minPrev;
      if(delta <= 0.0) delta = 1e-12;
      tf_diffFwd[k] = MathLog(delta);
   }

   // PSI on forward array, remap to series shifts (0=current)
   ArrayInitialize(tf_psiSeries, EMPTY_VALUE);

   int n = Length;
   if(n < 2) return wantCount;

   for(int f = 0; f < wantCount; ++f)
   {
      if(f + 1 < n) continue; // need n samples

      int startIndex = f - (n - 1);
      double corr = CorrWithSequentialIndex(tf_diffFwd, startIndex, n);
      double psi = (corr==EMPTY_VALUE || !MathIsValidNumber(corr)) ? EMPTY_VALUE : (-50.0*corr + 50.0);

      // map forward index f to series shift
      int shift = (wantCount-1) - f;
      tf_psiSeries[shift] = psi;
   }

   return wantCount;
}

//+------------------------------------------------------------------+
//| Main calculation                                                 |
//+------------------------------------------------------------------+
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
   if(rates_total <= 0) return 0;

   // Clear outputs
   ArrayInitialize(gPsiLine,    EMPTY_VALUE);
   ArrayInitialize(gPsiDots,    EMPTY_VALUE);
   ArrayInitialize(gFillUpper,  EMPTY_VALUE);
   ArrayInitialize(gFillLower,  EMPTY_VALUE);

   if(Timeframe == PERIOD_CURRENT)
   {
      // Compute directly on chart TF (use original logic)
      // Prepare forward chronological array for diff
      static double diffFwd[]; // reuse
      if(ArraySize(diffFwd) != rates_total)
         ArrayResize(diffFwd, rates_total);

      double conv = (ConvergenceFactor <= 0) ? 1.0 : (double)ConvergenceFactor;

      double maxPrev = 0.0, minPrev = 0.0; bool hasPrev = false;
      int k = 0; // forward index

      for(int i = rates_total - 1; i >= 0; --i, ++k)
      {
         double s = GetPriceSeries(i, open, high, low, close);

         if(!hasPrev){ maxPrev=s; minPrev=s; hasPrev=true; }
         else
         {
            double maxCandidate = maxPrev - (maxPrev - s) / conv;
            maxPrev = (s > maxCandidate ? s : maxCandidate);

            double minCandidate = minPrev + (s - minPrev) / conv;
            minPrev = (s < minCandidate ? s : minCandidate);
         }

         double delta = maxPrev - minPrev;
         if(delta <= 0.0) delta = 1e-12;
         diffFwd[k] = MathLog(delta);
      }

      int n = Length;
      if(n >= 2)
      {
         for(int kbar=0; kbar<rates_total; ++kbar)
         {
            int i = rates_total - 1 - kbar;
            if(kbar + 1 < n) continue;

            int startIndex = kbar - (n - 1);
            double corr = CorrWithSequentialIndex(diffFwd, startIndex, n);
            double psi  = (corr==EMPTY_VALUE || !MathIsValidNumber(corr)) ? EMPTY_VALUE : (-50.0*corr + 50.0);

            if(psi==EMPTY_VALUE) continue;

            if(psi <= 80.0)
            {
               gPsiLine[i] = psi;
            }
            else
            {
               gPsiDots[i]   = psi;
               gFillUpper[i] = psi;
               gFillLower[i] = 80.0;
            }
         }
      }

      return(rates_total);
   }

   // MTF branch: compute on selected TF and map to chart bars
   int tfCount = ComputePSI_OnTF(time, rates_total);
   if(tfCount <= 0) return(rates_total);

   for(int i=rates_total-1; i>=0; --i)
   {
      int sh = iBarShift(NULL, Timeframe, time[i], false);
      if(sh<0 || sh>=tfCount) continue;

      double psi = tf_psiSeries[sh];
      if(psi==EMPTY_VALUE) continue;

      if(psi <= 80.0)
      {
         gPsiLine[i] = psi;
      }
      else
      {
         gPsiDots[i]   = psi;
         gFillUpper[i] = psi;
         gFillLower[i] = 80.0;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+