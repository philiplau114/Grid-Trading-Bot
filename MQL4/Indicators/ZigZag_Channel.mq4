//+------------------------------------------------------------------+
//|                                                ZigZag_Channel.mq4|
//|   Trading Range from ZigZag pivots                               |
//|   - Top: connects ALL consecutive swing highs (extends last seg) |
//|   - Bottom: connects ALL consecutive swing lows (extends last)   |
//|   - Center: midpoint where both top & bottom exist               |
//|   Refreshes every tick                                           |
//|                                                                  |
//|   Based on MetaQuotes ZigZag reference logic (MT4 sample).       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 3
#property indicator_buffers 3

// Top line (from swing highs)
#property indicator_label1  "ZZ Top"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Bottom line (from swing lows)
#property indicator_label2  "ZZ Bottom"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Center line (midpoint)
#property indicator_label3  "ZZ Center"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGold
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

// ZigZag parameters (matching standard ZigZag)
input int InpDepth     = 12; // Depth
input int InpDeviation = 5;  // Deviation (points)
input int InpBackstep  = 3;  // Backstep

// Extend last segments to the current bar
input bool ExtendToCurrentBar = true;

// Output buffers
double TopBuffer[];
double BottomBuffer[];
double CenterBuffer[];

// Internal ZigZag working arrays (not plotted)
double ZZBuffer[];
double HighBuf[];
double LowBuf[];

// Recount depth of extremums (same constant used in sample)
int ExtLevel = 3;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpBackstep >= InpDepth)
   {
      Print("Backstep cannot be greater or equal to Depth");
      return(INIT_FAILED);
   }

   // Bind plotted buffers
   SetIndexBuffer(0, TopBuffer);
   SetIndexBuffer(1, BottomBuffer);
   SetIndexBuffer(2, CenterBuffer);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);

   ArraySetAsSeries(TopBuffer,    true);
   ArraySetAsSeries(BottomBuffer, true);
   ArraySetAsSeries(CenterBuffer, true);

   IndicatorShortName("ZigZag Range (" + IntegerToString(InpDepth) + "," + IntegerToString(InpDeviation) + "," + IntegerToString(InpBackstep) + ")");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Helper to (re)initialize internal ZigZag buffers                 |
//+------------------------------------------------------------------+
int InitializeAll(int bars_total)
{
   ArrayResize(ZZBuffer,  bars_total);
   ArrayResize(HighBuf,   bars_total);
   ArrayResize(LowBuf,    bars_total);

   ArraySetAsSeries(ZZBuffer, true);
   ArraySetAsSeries(HighBuf,  true);
   ArraySetAsSeries(LowBuf,   true);

   ArrayInitialize(ZZBuffer,  0.0);
   ArrayInitialize(HighBuf,   0.0);
   ArrayInitialize(LowBuf,    0.0);

   // first counting position (align with reference but use passed size)
   return(bars_total - InpDepth);
}

//+------------------------------------------------------------------+
//| Core ZigZag computation (adapted from MetaQuotes sample)         |
//+------------------------------------------------------------------+
int ComputeZigZag(const int rates_total,
                  const int prev_calculated,
                  const double &high[],
                  const double &low[])
{
   int i, limit, whatlookfor = 0;
   int back, pos, lasthighpos = 0, lastlowpos = 0;
   double extremum;
   double curlow = 0.0, curhigh = 0.0, lasthigh = 0.0, lastlow = 0.0;

   if(rates_total < InpDepth || InpBackstep >= InpDepth)
      return(0);

   // Full recompute each tick for consistency
   limit = InitializeAll(rates_total);

   // Main loop (from reference implementation)
   for(i = limit; i >= 0; i--)
   {
      // Find lowest low in depth
      extremum = low[iLowest(NULL, 0, MODE_LOW, InpDepth, i)];
      if(extremum == lastlow)
         extremum = 0.0;
      else
      {
         lastlow = extremum;
         if(low[i] - extremum > InpDeviation * Point)
            extremum = 0.0;
         else
         {
            for(back = 1; back <= InpBackstep; back++)
            {
               pos = i + back;
               if(LowBuf[pos] != 0 && LowBuf[pos] > extremum)
                  LowBuf[pos] = 0.0;
            }
         }
      }
      if(low[i] == extremum) LowBuf[i] = extremum; else LowBuf[i] = 0.0;

      // Find highest high in depth
      extremum = high[iHighest(NULL, 0, MODE_HIGH, InpDepth, i)];
      if(extremum == lasthigh)
         extremum = 0.0;
      else
      {
         lasthigh = extremum;
         if(extremum - high[i] > InpDeviation * Point)
            extremum = 0.0;
         else
         {
            for(back = 1; back <= InpBackstep; back++)
            {
               pos = i + back;
               if(HighBuf[pos] != 0 && HighBuf[pos] < extremum)
                  HighBuf[pos] = 0.0;
            }
         }
      }
      if(high[i] == extremum) HighBuf[i] = extremum; else HighBuf[i] = 0.0;
   }

   // Final cutting (from reference)
   if(whatlookfor == 0) { lastlow = 0.0; lasthigh = 0.0; }
   else { lastlow = curlow; lasthigh = curhigh; }

   for(i = limit; i >= 0; i--)
   {
      switch(whatlookfor)
      {
         case 0: // look for first peak or valley
            if(lastlow == 0.0 && lasthigh == 0.0)
            {
               if(HighBuf[i] != 0.0)
               {
                  lasthigh = high[i];
                  lasthighpos = i;
                  whatlookfor = -1;
                  ZZBuffer[i] = lasthigh;
               }
               if(LowBuf[i] != 0.0)
               {
                  lastlow = low[i];
                  lastlowpos = i;
                  whatlookfor = 1;
                  ZZBuffer[i] = lastlow;
               }
            }
            break;

         case 1: // look for peak
            if(LowBuf[i] != 0.0 && LowBuf[i] < lastlow && HighBuf[i] == 0.0)
            {
               ZZBuffer[lastlowpos] = 0.0;
               lastlowpos = i;
               lastlow = LowBuf[i];
               ZZBuffer[i] = lastlow;
            }
            if(HighBuf[i] != 0.0 && LowBuf[i] == 0.0)
            {
               lasthigh = HighBuf[i];
               lasthighpos = i;
               ZZBuffer[i] = lasthigh;
               whatlookfor = -1;
            }
            break;

         case -1: // look for valley
            if(HighBuf[i] != 0.0 && HighBuf[i] > lasthigh && LowBuf[i] == 0.0)
            {
               ZZBuffer[lasthighpos] = 0.0;
               lasthighpos = i;
               lasthigh = HighBuf[i];
               ZZBuffer[i] = lasthigh;
            }
            if(LowBuf[i] != 0.0 && HighBuf[i] == 0.0)
            {
               lastlow = LowBuf[i];
               lastlowpos = i;
               ZZBuffer[i] = lastlow;
               whatlookfor = 1;
            }
            break;
      }
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw segments for all swing highs and lows (extend last segment) |
//+------------------------------------------------------------------+
void BuildRangeLines(const int rates_total)
{
   // Clear outputs
   ArrayInitialize(TopBuffer,    EMPTY_VALUE);
   ArrayInitialize(BottomBuffer, EMPTY_VALUE);
   ArrayInitialize(CenterBuffer, EMPTY_VALUE);

   // Collect swing highs and lows in chronological order (oldest -> newest)
   // Since arrays are series (0=current), iterate i = rates_total-1 .. 0
   int maxPivots = rates_total;
   int hiCount = 0, loCount = 0;

   // Pre-allocate simple arrays for indices/values
   static int    HiIdx[]; static double HiVal[];
   static int    LoIdx[]; static double LoVal[];
   ArrayResize(HiIdx, maxPivots); ArrayResize(HiVal, maxPivots);
   ArrayResize(LoIdx, maxPivots); ArrayResize(LoVal, maxPivots);

   for(int i = rates_total - 1; i >= 0; --i)
   {
      if(HighBuf[i] != 0.0) { HiIdx[hiCount] = i; HiVal[hiCount] = HighBuf[i]; hiCount++; }
      if(LowBuf[i]  != 0.0) { LoIdx[loCount] = i; LoVal[loCount] = LowBuf[i];  loCount++; }
   }

   // Draw all top segments (between consecutive swing highs)
   for(int k = 1; k < hiCount; ++k)
   {
      int i0 = HiIdx[k-1];   double y0 = HiVal[k-1];   // older
      int i1 = HiIdx[k];     double y1 = HiVal[k];     // newer (i1 < i0)
      if(i0 == i1) continue;

      double slope = (y1 - y0) / (double)(i1 - i0);
      // Fill from i0 down to i1 to create a contiguous segment
      for(int i = i0; i >= i1; --i)
      {
         double y = y0 + slope * (i - i0);
         TopBuffer[i] = y;
      }
   }

   // Extend the last top segment to current bar if requested and we have at least 2 highs
   if(ExtendToCurrentBar && hiCount >= 2)
   {
      int i0 = HiIdx[hiCount - 2]; double y0 = HiVal[hiCount - 2];
      int i1 = HiIdx[hiCount - 1]; double y1 = HiVal[hiCount - 1];
      double slope = (y1 - y0) / (double)(i1 - i0);
      for(int i = i1; i >= 0; --i)
      {
         double y = y1 + slope * (i - i1);
         TopBuffer[i] = y;
      }
   }

   // Draw all bottom segments (between consecutive swing lows)
   for(int k = 1; k < loCount; ++k)
   {
      int i0 = LoIdx[k-1];   double y0 = LoVal[k-1];   // older
      int i1 = LoIdx[k];     double y1 = LoVal[k];     // newer
      if(i0 == i1) continue;

      double slope = (y1 - y0) / (double)(i1 - i0);
      for(int i = i0; i >= i1; --i)
      {
         double y = y0 + slope * (i - i0);
         BottomBuffer[i] = y;
      }
   }

   // Extend the last bottom segment to current bar if requested and we have at least 2 lows
   if(ExtendToCurrentBar && loCount >= 2)
   {
      int i0 = LoIdx[loCount - 2]; double y0 = LoVal[loCount - 2];
      int i1 = LoIdx[loCount - 1]; double y1 = LoVal[loCount - 1];
      double slope = (y1 - y0) / (double)(i1 - i0);
      for(int i = i1; i >= 0; --i)
      {
         double y = y1 + slope * (i - i1);
         BottomBuffer[i] = y;
      }
   }

   // Center line where both exist
   for(int i = rates_total - 1; i >= 0; --i)
   {
      if(TopBuffer[i] != EMPTY_VALUE && BottomBuffer[i] != EMPTY_VALUE)
         CenterBuffer[i] = 0.5 * (TopBuffer[i] + BottomBuffer[i]);
   }
}

//+------------------------------------------------------------------+
//| Main calculation                                                 |
//+------------------------------------------------------------------+
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
   if(rates_total <= 0) return 0;

   // Ensure arrays are series-oriented
   ArraySetAsSeries(TopBuffer,    true);
   ArraySetAsSeries(BottomBuffer, true);
   ArraySetAsSeries(CenterBuffer, true);
   ArraySetAsSeries(ZZBuffer,     true);
   ArraySetAsSeries(HighBuf,      true);
   ArraySetAsSeries(LowBuf,       true);

   // Compute ZigZag anew each tick
   ComputeZigZag(rates_total, prev_calculated, high, low);

   // Build trading range lines from ALL pivots (extend last segments)
   BuildRangeLines(rates_total);

   return(rates_total);
}
//+------------------------------------------------------------------+