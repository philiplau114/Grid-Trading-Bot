//+------------------------------------------------------------------+
//| Dynamic CSV Import EA (deletes CSV after import)                 |
//+------------------------------------------------------------------+
#property strict

struct BarData
{
   datetime dt;
   double Open;
   double High;
   double Low;
   double Close;
   long Volume;
};

BarData importedBars[];
int importedBarCount = 0;

// Parse a CSV line to BarData
bool ParseBarLine(string line, BarData &bar)
{
   string fields[];
   int n = StringSplit(line, ',', fields);
   if(n < 7) return false;
   bar.dt = StrToTime(fields[0] + " " + fields[1]);
   bar.Open  = StrToDouble(fields[2]);
   bar.High  = StrToDouble(fields[3]);
   bar.Low   = StrToDouble(fields[4]);
   bar.Close = StrToDouble(fields[5]);
   bar.Volume = (long)StrToInteger(fields[6]);
   return true;
}

// Read CSV file into importedBars[]
int LoadCSV(string filename)
{
   importedBarCount = 0;
   int handle = FileOpen(filename, FILE_READ|FILE_CSV);
   if(handle < 0) { Print("File open failed: ", filename); return 0; }
   string header = FileReadString(handle); // Skip header
   int parseFails = 0;
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      // Remove leading/trailing whitespace
      line = StringTrimLeft(StringTrimRight(line));
      if(StringLen(line) == 0) continue; // skip blank lines
      BarData bar;
      if(ParseBarLine(line, bar))
      {
         ArrayResize(importedBars, importedBarCount+1);
         importedBars[importedBarCount++] = bar;
      }
      else
      {
         parseFails++;
         if(parseFails < 10) Print("Parse failed, line: ", line);
      }
   }
   FileClose(handle);
   Print("Loaded ", importedBarCount, " bars from ", filename, "; parse failures: ", parseFails);

   // Print first 3 and last 3 bars for diagnostics
   int showBars = MathMin(3, importedBarCount);
   for(int i=0; i<showBars; i++)
   {
      BarData b = importedBars[i];
      Print("First bar #", i+1, ": ", TimeToStr(b.dt), " O:", b.Open, " H:", b.High, " L:", b.Low, " C:", b.Close, " V:", b.Volume);
   }
   for(int i=importedBarCount-showBars; i<importedBarCount; i++)
   {
      if(i<0) continue;
      BarData b = importedBars[i];
      Print("Last bar #", i+1, ": ", TimeToStr(b.dt), " O:", b.Open, " H:", b.High, " L:", b.Low, " C:", b.Close, " V:", b.Volume);
   }
   return importedBarCount;
}

// Find the first matching CSV (for batch, you could collect all and process in a loop)
void FindFirstCSV(string &foundFile)
{
   foundFile = "";
   string returned_filename = "";
   long handle = FileFindFirst("*.csv", returned_filename);
   if(handle != INVALID_HANDLE)
   {
      do
      {
         if(StringFind(returned_filename, "-bardata_") > -1)
         {
            foundFile = returned_filename;
            break; // Only pick the first matching file for import
         }
      }
      while(FileFindNext(handle, returned_filename));
      FileFindClose(handle);
   }
}

// OnInit: import and delete any CSV found
int OnInit()
{
   string foundFile = "";
   FindFirstCSV(foundFile);
   if(foundFile != "")
   {
      Print("Auto-import: ", foundFile);
      LoadCSV(foundFile);
      if(FileDelete(foundFile))
         Print("CSV file deleted: ", foundFile);
      else
         Print("Failed to delete CSV file: ", foundFile);
   }
   else
   {
      Print("No suitable CSV file found in MQL4/Files.");
   }
   Print("initialized");
   return INIT_SUCCEEDED;
}

// Every N ticks, scan for new CSV and import/delete if found
int tickCount = 0;
void OnTick()
{
   tickCount++;
   if(tickCount % 10 == 0) // Check every 10 ticks
   {
      string foundFile = "";
      FindFirstCSV(foundFile);

      if(foundFile != "")
      {
         Print("Detected new CSV: ", foundFile);
         LoadCSV(foundFile);
         if(FileDelete(foundFile))
            Print("CSV file deleted: ", foundFile);
         else
            Print("Failed to delete CSV file: ", foundFile);
      }
      else
      {
         Print("No new CSV file detected.");
      }
   }
}