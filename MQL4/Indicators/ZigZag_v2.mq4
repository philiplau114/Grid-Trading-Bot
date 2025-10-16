//+------------------------------------------------------------------+
//|                                                   ZigZag_v2.mq4  |
//|         Updated: Export pivots AND waves to CSV for comparison   |
//|         Now: Only export within input date range                 |
//+------------------------------------------------------------------+
#property copyright "2006-2014, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property strict

#property indicator_chart_window
#property indicator_buffers 1
#property indicator_color1  Red

//---- indicator parameters
input int InpDepth=12;     // Depth
input int InpDeviation=5;  // Deviation
input int InpBackstep=3;   // Backstep

//---- NEW: Export date range inputs
input datetime ExportStart = D'2025.05.01 00:00'; // Start date for export
input datetime ExportEnd   = D'2025.09.05 23:59'; // End date for export

//---- indicator buffers
double ExtZigzagBuffer[];
double ExtHighBuffer[];
double ExtLowBuffer[];

//--- globals
int    ExtLevel=3; // recounting's depth of extremums

int OnInit()
  {
   if(InpBackstep>=InpDepth)
     {
      Print("Backstep cannot be greater or equal to Depth");
      return(INIT_FAILED);
     }
   IndicatorBuffers(3);
   SetIndexStyle(0,DRAW_SECTION);
   SetIndexBuffer(0,ExtZigzagBuffer);
   SetIndexBuffer(1,ExtHighBuffer);
   SetIndexBuffer(2,ExtLowBuffer);
   SetIndexEmptyValue(0,0.0);
   IndicatorShortName("ZigZag("+string(InpDepth)+","+string(InpDeviation)+","+string(InpBackstep)+")");
   return(INIT_SUCCEEDED);
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
   int    i,limit,counterZ,whatlookfor=0;
   int    back,pos,lasthighpos=0,lastlowpos=0;
   double extremum;
   double curlow=0.0,curhigh=0.0,lasthigh=0.0,lastlow=0.0;
   if(rates_total<InpDepth || InpBackstep>=InpDepth)
      return(0);
   if(prev_calculated==0)
      limit=InitializeAll();
   else
     {
      i=counterZ=0;
      while(counterZ<ExtLevel && i<100)
        {
         if(ExtZigzagBuffer[i]!=0.0)
            counterZ++;
         i++;
        }
      if(counterZ==0)
         limit=InitializeAll();
      else
        {
         limit=i-1;
         if(ExtLowBuffer[i]!=0.0)
           {
            curlow=ExtLowBuffer[i];
            whatlookfor=1;
           }
         else
           {
            curhigh=ExtHighBuffer[i];
            whatlookfor=-1;
           }
         for(i=limit-1; i>=0; i--)
           {
            ExtZigzagBuffer[i]=0.0;
            ExtLowBuffer[i]=0.0;
            ExtHighBuffer[i]=0.0;
           }
        }
     }
   for(i=limit; i>=0; i--)
     {
      extremum=low[iLowest(NULL,0,MODE_LOW,InpDepth,i)];
      if(extremum==lastlow)
         extremum=0.0;
      else
        {
         lastlow=extremum;
         if(low[i]-extremum>InpDeviation*Point)
            extremum=0.0;
         else
           {
            for(back=1; back<=InpBackstep; back++)
              {
               pos=i+back;
               if(ExtLowBuffer[pos]!=0 && ExtLowBuffer[pos]>extremum)
                  ExtLowBuffer[pos]=0.0;
              }
           }
        }
      if(low[i]==extremum)
         ExtLowBuffer[i]=extremum;
      else
         ExtLowBuffer[i]=0.0;
      extremum=high[iHighest(NULL,0,MODE_HIGH,InpDepth,i)];
      if(extremum==lasthigh)
         extremum=0.0;
      else
        {
         lasthigh=extremum;
         if(extremum-high[i]>InpDeviation*Point)
            extremum=0.0;
         else
           {
            for(back=1; back<=InpBackstep; back++)
              {
               pos=i+back;
               if(ExtHighBuffer[pos]!=0 && ExtHighBuffer[pos]<extremum)
                  ExtHighBuffer[pos]=0.0;
              }
           }
        }
      if(high[i]==extremum)
         ExtHighBuffer[i]=extremum;
      else
         ExtHighBuffer[i]=0.0;
     }
   if(whatlookfor==0)
     {
      lastlow=0.0;
      lasthigh=0.0;
     }
   else
     {
      lastlow=curlow;
      lasthigh=curhigh;
     }
   for(i=limit; i>=0; i--)
     {
      switch(whatlookfor)
        {
         case 0:
            if(lastlow==0.0 && lasthigh==0.0)
              {
               if(ExtHighBuffer[i]!=0.0)
                 {
                  lasthigh=high[i];
                  lasthighpos=i;
                  whatlookfor=-1;
                  ExtZigzagBuffer[i]=lasthigh;
                 }
               if(ExtLowBuffer[i]!=0.0)
                 {
                  lastlow=low[i];
                  lastlowpos=i;
                  whatlookfor=1;
                  ExtZigzagBuffer[i]=lastlow;
                 }
              }
            break;
         case 1:
            if(ExtLowBuffer[i]!=0.0 && ExtLowBuffer[i]<lastlow && ExtHighBuffer[i]==0.0)
              {
               ExtZigzagBuffer[lastlowpos]=0.0;
               lastlowpos=i;
               lastlow=ExtLowBuffer[i];
               ExtZigzagBuffer[i]=lastlow;
              }
            if(ExtHighBuffer[i]!=0.0 && ExtLowBuffer[i]==0.0)
              {
               lasthigh=ExtHighBuffer[i];
               lasthighpos=i;
               ExtZigzagBuffer[i]=lasthigh;
               whatlookfor=-1;
              }
            break;
         case -1:
            if(ExtHighBuffer[i]!=0.0 && ExtHighBuffer[i]>lasthigh && ExtLowBuffer[i]==0.0)
              {
               ExtZigzagBuffer[lasthighpos]=0.0;
               lasthighpos=i;
               lasthigh=ExtHighBuffer[i];
               ExtZigzagBuffer[i]=lasthigh;
              }
            if(ExtLowBuffer[i]!=0.0 && ExtHighBuffer[i]==0.0)
              {
               lastlow=ExtLowBuffer[i];
               lastlowpos=i;
               ExtZigzagBuffer[i]=lastlow;
               whatlookfor=1;
              }
            break;
        }
     }
   ExportZigZagPivotsAndWavesToCSV(rates_total, time);
   return(rates_total);
  }

int InitializeAll()
  {
   ArrayInitialize(ExtZigzagBuffer,0.0);
   ArrayInitialize(ExtHighBuffer,0.0);
   ArrayInitialize(ExtLowBuffer,0.0);
   return(Bars-InpDepth);
  }

//+------------------------------------------------------------------+
//| Export ZigZag pivots AND waves to CSV with date filter           |
//+------------------------------------------------------------------+
void ExportZigZagPivotsAndWavesToCSV(int rates_total, const datetime &time[])
  {
   int fileHandle = FileOpen("ZigZagExport_Pivots.csv", FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(fileHandle < 0)
     {
      Print("Cannot open ZigZagExport_Pivots.csv for writing");
      return;
     }
   FileWrite(fileHandle, "DateTime,Price,Type");

   for(int i=0; i<rates_total; i++)
     {
      double zz = ExtZigzagBuffer[i];
      if(zz != 0.0)
        {
         // Only export within date range
         if(time[i] < ExportStart || time[i] > ExportEnd) continue;
         string type = "";
         if(ExtHighBuffer[i] != 0.0) type = "High";
         else if(ExtLowBuffer[i] != 0.0) type = "Low";
         else type = "Unknown";
         string dt = TimeToStr(time[i], TIME_DATE|TIME_MINUTES);
         FileWrite(fileHandle, dt, DoubleToString(zz, Digits), type);
        }
     }
   FileClose(fileHandle);

   // Export waves (pivot-to-pivot intervals)
   int waveHandle = FileOpen("ZigZagExport_Waves.csv", FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(waveHandle < 0)
     {
      Print("Cannot open ZigZagExport_Waves.csv for writing");
      return;
     }
   FileWrite(waveHandle, "start,end,bars,pips,type");

   // Gather pivots
   datetime pivotsTime[];
   double pivotsPrice[];
   string pivotsType[];
   ArrayResize(pivotsTime, rates_total);
   ArrayResize(pivotsPrice, rates_total);
   ArrayResize(pivotsType, rates_total);
   int count=0;
   for(int i=0; i<rates_total; i++)
     {
      double zz = ExtZigzagBuffer[i];
      if(zz != 0.0)
        {
         if(time[i] < ExportStart || time[i] > ExportEnd) continue;
         pivotsTime[count] = time[i];
         pivotsPrice[count] = zz;
         if(ExtHighBuffer[i] != 0.0) pivotsType[count] = "High";
         else if(ExtLowBuffer[i] != 0.0) pivotsType[count] = "Low";
         else pivotsType[count] = "Unknown";
         count++;
        }
     }
   ArrayResize(pivotsTime, count);
   ArrayResize(pivotsPrice, count);
   ArrayResize(pivotsType, count);

   // Write waves (use only pivots within range)
   for(int i=1; i<count; i++)
     {
      string startdt = TimeToStr(pivotsTime[i-1], TIME_DATE|TIME_MINUTES);
      string enddt = TimeToStr(pivotsTime[i], TIME_DATE|TIME_MINUTES);
      int bars = (pivotsTime[i] - pivotsTime[i-1]) / PeriodSeconds();
      double pips = MathAbs(pivotsPrice[i] - pivotsPrice[i-1]) * MathPow(10, Digits);
      string type = pivotsType[i];
      FileWrite(waveHandle, startdt, enddt, bars, DoubleToString(pips, 1), type);
     }
   FileClose(waveHandle);
  }
//+------------------------------------------------------------------+