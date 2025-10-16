//+------------------------------------------------------------------+
//|                                                     RangeWindow  |
//| Moving-window trading range (Top/Bottom/Center)                  |
//| - Top = Highest high in the window                               |
//| - Bottom = Lowest low in the window                              |
//| - Center = (Top + Bottom)/2                                      |
//| - Supports current-window-only (flat box) or full history mode   |
//| - Refreshes every tick                                           |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

// Plot 1: Top line
#property indicator_label1  "Range Top"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 2: Bottom line
#property indicator_label2  "Range Bottom"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 3: Center line
#property indicator_label3  "Range Center"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGold
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

// Inputs
input int  WindowBars          = 100; // Lookback length (bars)
input bool UseCompletedBars    = true; // Exclude the forming bar from the window
input bool ShowHistoricalRange = false; // If true, draw rolling range for every bar; else draw only the current window

// Buffers
double TopBuf[];
double BotBuf[];
double MidBuf[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("RangeWindow (" + IntegerToString(WindowBars) + ")");
   SetIndexBuffer(0, TopBuf);
   SetIndexBuffer(1, BotBuf);
   SetIndexBuffer(2, MidBuf);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);

   ArraySetAsSeries(TopBuf, true);
   ArraySetAsSeries(BotBuf, true);
   ArraySetAsSeries(MidBuf, true);

   return(INIT_SUCCEEDED);
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

   // Clear outputs each tick for correctness
   ArrayInitialize(TopBuf, EMPTY_VALUE);
   ArrayInitialize(BotBuf, EMPTY_VALUE);
   ArrayInitialize(MidBuf, EMPTY_VALUE);

   // Decide which bar to start from (exclude forming bar if requested)
   int startOffset = (UseCompletedBars ? 1 : 0);

   if(ShowHistoricalRange)
   {
      // Draw rolling range for every bar where a full window fits
      // Iterate oldest -> newest in series indexing: i = rates_total-WindowBars-startOffset down to 0
      int firstIndex = rates_total - (WindowBars + startOffset);
      if(firstIndex < 0) firstIndex = 0;

      for(int i = firstIndex; i >= 0; --i)
      {
         int count = WindowBars;
         int start = i + startOffset; // series index start of the window
         if(start + count > rates_total) continue;

         int hiIdx = iHighest(NULL, 0, MODE_HIGH, count, start);
         int loIdx = iLowest(NULL, 0, MODE_LOW,  count, start);
         if(hiIdx < 0 || loIdx < 0) continue;

         double top = High[hiIdx];
         double bot = Low[loIdx];
         double mid = 0.5 * (top + bot);

         TopBuf[i] = top;
         BotBuf[i] = bot;
         MidBuf[i] = mid;
      }
   }
   else
   {
      // Draw a flat rectangle only for the current window (last N bars)
      int count = WindowBars;
      int start = startOffset;

      if(start + count > rates_total)
         count = rates_total - start;

      if(count > 0)
      {
         int hiIdx = iHighest(NULL, 0, MODE_HIGH, count, start);
         int loIdx = iLowest(NULL, 0, MODE_LOW,  count, start);

         if(hiIdx >= 0 && loIdx >= 0)
         {
            double top = High[hiIdx];
            double bot = Low[loIdx];
            double mid = 0.5 * (top + bot);

            // Fill the last 'count' bars (from start to start+count-1) with flat lines
            int endBar = start + count - 1;
            for(int i = start; i <= endBar; ++i)
            {
               TopBuf[i] = top;
               BotBuf[i] = bot;
               MidBuf[i] = mid;
            }
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+