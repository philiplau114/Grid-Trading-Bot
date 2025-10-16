//+------------------------------------------------------------------+
//|                                           ZigZag_RangeRectangle  |
//| Trading Range (Rectangle) from latest confirmed ZigZag pivots    |
//| - Top = most recent confirmed swing high (horizontal)            |
//| - Bottom = most recent confirmed swing low (horizontal)          |
//| - Center = (Top+Bottom)/2                                        |
//| - Lines drawn from the later (more recent) pivot to current bar  |
//| - Refreshes every tick                                           |
//|                                                                  |
//| Based on MetaQuotes ZigZag reference logic (MT4 sample).         |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 3
#property indicator_buffers 3

// Plot 1: Top line (range high)
#property indicator_label1  "Range Top"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 2: Bottom line (range low)
#property indicator_label2  "Range Bottom"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 3: Center line (midpoint)
#property indicator_label3  "Range Center"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGold
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

// ZigZag parameters (same semantics as built-in sample)
input int InpDepth     = 12; // Depth
input int InpDeviation = 5;  // Deviation (points)
input int InpBackstep  = 3;  // Backstep

// Whether to draw the rectangle from the later pivot to current bar
input bool ExtendToCurrentBar = true;

// Output buffers
double TopBuf[];
double BotBuf[];
double MidBuf[];

// Internal ZigZag working arrays
double ZZBuf[];
double HiBuf[];
double LoBuf[];

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

   SetIndexBuffer(0, TopBuf);
   SetIndexBuffer(1, BotBuf);
   SetIndexBuffer(2, MidBuf);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);

   ArraySetAsSeries(TopBuf, true);
   ArraySetAsSeries(BotBuf, true);
   ArraySetAsSeries(MidBuf, true);

   IndicatorShortName("ZigZag Range Rectangle ("+IntegerToString(InpDepth)+","+IntegerToString(InpDeviation)+","+IntegerToString(InpBackstep)+")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Initialize internal ZZ buffers                                   |
//+------------------------------------------------------------------+
void ZZInitAll(int bars_total)
{
   ArrayResize(ZZBuf, bars_total);
   ArrayResize(HiBuf, bars_total);
   ArrayResize(LoBuf, bars_total);

   ArraySetAsSeries(ZZBuf, true);
   ArraySetAsSeries(HiBuf, true);
   ArraySetAsSeries(LoBuf, true);

   ArrayInitialize(ZZBuf, 0.0);
   ArrayInitialize(HiBuf, 0.0);
   ArrayInitialize(LoBuf, 0.0);
}

//+------------------------------------------------------------------+
//| Compute ZigZag (adapted from MetaQuotes sample)                  |
//+------------------------------------------------------------------+
void ComputeZigZag(const int rates_total,
                   const double &high[],
                   const double &low[])
{
   ZZInitAll(rates_total);

   int limit = rates_total - InpDepth;
   if(limit < 0) limit = 0;

   int i, back, pos, whatlookfor=0, lasthighpos=0, lastlowpos=0;
   double extremum, curlow=0.0, curhigh=0.0, lasthigh=0.0, lastlow=0.0;

   // Pass 1: find candidate highs/lows in windows
   for(i = limit; i >= 0; i--)
   {
      // lowest low
      extremum = low[iLowest(NULL, 0, MODE_LOW, InpDepth, i)];
      if(extremum == lastlow) extremum = 0.0;
      else
      {
         lastlow = extremum;
         if(low[i] - extremum > InpDeviation * Point) extremum = 0.0;
         else
         {
            for(back=1; back<=InpBackstep; back++)
            {
               pos = i + back;
               if(LoBuf[pos]!=0 && LoBuf[pos] > extremum) LoBuf[pos]=0.0;
            }
         }
      }
      LoBuf[i] = (low[i]==extremum ? extremum : 0.0);

      // highest high
      extremum = high[iHighest(NULL, 0, MODE_HIGH, InpDepth, i)];
      if(extremum == lasthigh) extremum = 0.0;
      else
      {
         lasthigh = extremum;
         if(extremum - high[i] > InpDeviation * Point) extremum = 0.0;
         else
         {
            for(back=1; back<=InpBackstep; back++)
            {
               pos = i + back;
               if(HiBuf[pos]!=0 && HiBuf[pos] < extremum) HiBuf[pos]=0.0;
            }
         }
      }
      HiBuf[i] = (high[i]==extremum ? extremum : 0.0);
   }

   // Pass 2: finalize alternating ZZ points
   if(whatlookfor==0) { lastlow=0.0; lasthigh=0.0; } else { lastlow=curlow; lasthigh=curhigh; }

   ArrayInitialize(ZZBuf, 0.0);

   for(i = limit; i >= 0; i--)
   {
      switch(whatlookfor)
      {
         case 0:
            if(lastlow==0.0 && lasthigh==0.0)
            {
               if(HiBuf[i]!=0.0) { lasthigh=High[i]; lasthighpos=i; whatlookfor=-1; ZZBuf[i]=lasthigh; }
               if(LoBuf[i]!=0.0) { lastlow =Low[i];  lastlowpos =i; whatlookfor= 1; ZZBuf[i]=lastlow;  }
            }
            break;

         case 1: // look for peak
            if(LoBuf[i]!=0.0 && LoBuf[i]<lastlow && HiBuf[i]==0.0)
            { ZZBuf[lastlowpos]=0.0; lastlowpos=i; lastlow=LoBuf[i]; ZZBuf[i]=lastlow; }
            if(HiBuf[i]!=0.0 && LoBuf[i]==0.0)
            { lasthigh=HiBuf[i]; lasthighpos=i; ZZBuf[i]=lasthigh; whatlookfor=-1; }
            break;

         case -1: // look for valley
            if(HiBuf[i]!=0.0 && HiBuf[i]>lasthigh && LoBuf[i]==0.0)
            { ZZBuf[lasthighpos]=0.0; lasthighpos=i; lasthigh=HiBuf[i]; ZZBuf[i]=lasthigh; }
            if(LoBuf[i]!=0.0 && HiBuf[i]==0.0)
            { lastlow=LoBuf[i]; lastlowpos=i; ZZBuf[i]=lastlow; whatlookfor=1; }
            break;
      }
   }
}

//+------------------------------------------------------------------+
//| Build rectangle lines from last opposite-type pivots             |
//+------------------------------------------------------------------+
void BuildRectangle(const int rates_total)
{
   // Clear outputs
   ArrayInitialize(TopBuf, EMPTY_VALUE);
   ArrayInitialize(BotBuf, EMPTY_VALUE);
   ArrayInitialize(MidBuf, EMPTY_VALUE);

   // Find the most recent confirmed pivot (closest to current bar)
   int p1Idx = -1; double p1Val = 0.0; int p1Type = 0; // +1=High, -1=Low
   for(int i=0; i<rates_total; ++i)
   {
      if(HiBuf[i]!=0.0) { p1Idx=i; p1Val=HiBuf[i]; p1Type=+1; break; }
      if(LoBuf[i]!=0.0) { p1Idx=i; p1Val=LoBuf[i]; p1Type=-1; break; }
   }
   if(p1Idx < 0) return; // no pivots yet

   // Find the nearest opposite-type pivot (older than p1)
   int p2Idx = -1; double p2Val = 0.0; int p2Type = 0;
   for(int j=p1Idx+1; j<rates_total; ++j)
   {
      if(p1Type==+1 && LoBuf[j]!=0.0) { p2Idx=j; p2Val=LoBuf[j]; p2Type=-1; break; }
      if(p1Type==-1 && HiBuf[j]!=0.0) { p2Idx=j; p2Val=HiBuf[j]; p2Type=+1; break; }
   }
   if(p2Idx < 0) return; // need both sides to define a rectangle

   // Determine top/bottom prices
   double topPrice = (p1Type==+1) ? p1Val : p2Val;
   double botPrice = (p1Type==-1) ? p1Val : p2Val;
   if(topPrice <= botPrice) return; // invalid (shouldn't happen with proper pivots)

   // Draw from the later pivot (the more recent one: smaller index) to current bar
   int start = p1Idx; // later (more recent) pivot index
   int end   = 0;     // current bar

   if(!ExtendToCurrentBar)
   {
      // If not extending, draw only on the pivot bar itself
      end   = p1Idx;
   }

   for(int i=start; i>=end; --i)
   {
      TopBuf[i] = topPrice;
      BotBuf[i] = botPrice;
      MidBuf[i] = 0.5*(topPrice + botPrice);
   }
}

//+------------------------------------------------------------------+
//| Main                                                             |
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
   if(rates_total <= 0 || InpBackstep >= InpDepth) return 0;

   // Ensure arrays are series
   ArraySetAsSeries(TopBuf, true);
   ArraySetAsSeries(BotBuf, true);
   ArraySetAsSeries(MidBuf, true);
   ArraySetAsSeries(ZZBuf, true);
   ArraySetAsSeries(HiBuf, true);
   ArraySetAsSeries(LoBuf, true);

   // Recompute ZigZag each tick to ensure immediate updates
   ComputeZigZag(rates_total, high, low);

   // Build the rectangle from the most recent opposite-type pivot pair
   BuildRectangle(rates_total);

   return(rates_total);
}
//+------------------------------------------------------------------+