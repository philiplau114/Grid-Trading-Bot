#property strict

// Step 1 — Regime Detector (No trading)
// - Multi-line, every-tick panel refresh (uses \r\n)
// - Rolling VWAP curve (segment-based, rays OFF) + optional H-line
// - Squeeze (BB vs KC), ZigZag range/mid
// - Optional EMA/ADX filters
// - Coherence: Strict/Score
// - CSV logging retained (on new bars only)

// ---------------- Inputs ----------------
input int      MagicNumber              = 8642137;
input string   TradeComment             = "GridZZVWAP_Step1_NoTrade";

// Refresh
enum UpdateMode { EveryTick=0, OnNewBar=1 };
input UpdateMode PanelUpdateMode        = EveryTick; // panel refresh mode only (curve always updates each tick)
input bool     LogOnlyOnNewBar          = true;      // keep CSV small

// Visualization
input bool     ShowPanel                = true;
input int      PanelFontSize            = 10;        // NEW: easier to read panel
input bool     ShowIndicatorStatus      = true;
input bool     UseAsciiPanelSymbols     = true;

input bool     ShowVWAP_HLine           = true;
input bool     ShowVWAPCurve            = true;      // draw curve as segments (rays OFF)
input int      VwapCurveBars            = 200;       // how many bars back to draw the curve
input int      VwapCurveWidth           = 2;
input color    ColVWAP                  = clrOrange;

input bool     ShowZigZag               = true;
input color    ColZZMid                 = clrMagenta;
input color    ColZZHi                  = clrTomato;
input color    ColZZLo                  = clrLimeGreen;

input bool     ShowSqueezeBadges        = true;
input color    ColSqueezeOn             = clrGold;
input color    ColSqueezeRelUp          = clrDeepSkyBlue;
input color    ColSqueezeRelDn          = clrMagenta;

input color    ColPanelBG               = clrDimGray;
input color    ColPanelText             = clrWhite;

// Panel position
enum Corner { TL=0, TR=1, BL=2, BR=3 };
input Corner   PanelCorner              = TR;
input int      PanelXOffset             = 10;
input int      PanelYOffset             = 15;

// Logging
enum LogPathMode { FilesDir=0, CommonDir=1, AbsolutePath=2 };
input LogPathMode CsvPathMode           = FilesDir;
input string   LogDirectory             = "";
input string   LogBaseName              = "regime";
input bool     WriteCSV                 = true;

// Coherence
enum CoherenceMode { Strict=0, Score=1 };
input CoherenceMode SignalsCoherence    = Strict;
input int      SignalWindowBars         = 5;
input int      SignalScoreThreshold     = 60;

// Rolling VWAP
enum VwapWindowMode { Rolling=0, Daily=1, Session=2 };
input VwapWindowMode VwapMode           = Rolling;
input bool     UseFixedTimeWindow       = false;
input int      WindowDays               = 1;
input int      WindowHours              = 0;
input int      WindowMinutes            = 0;
input int      MinBarsInWindow          = 10;
input int      VwapSlopePeriodBars      = 14;
input double   VwapSlopeThreshold       = 0.0;

enum VwapWeight { TickVolume=0, EqualWeight=1 };
input VwapWeight VWAP_WeightMode        = TickVolume;

// VWAP bands
input double   VWAP_StdevMult1          = 0.0;
input double   VWAP_StdevMult2          = 0.0;
input double   VWAP_StdevMult3          = 0.0;
input color    VWAP_StdevColor1         = clrLime;
input color    VWAP_StdevColor2         = clrYellow;
input color    VWAP_StdevColor3         = clrRed;

// ZigZag
input int      ZZ_Depth                 = 12;
input int      ZZ_Deviation             = 5;
input int      ZZ_Backstep              = 3;

// Squeeze (BB vs KC)
input int      BB_Period                = 20;
input double   BB_Dev                   = 2.0;
input int      KC_Period                = 20;
input double   KC_MultATR               = 1.5;

// Trend indicators
input bool     UseEMAStack              = false;
input int      EMA_Fast                 = 20;
input int      EMA_Mid                  = 50;
input int      EMA_Slow                 = 100;
input double   EMA_MinSlope             = 0.0;

input bool     UseADX                   = false;
input int      ADX_Period               = 14;
input double   ADX_Threshold            = 20.0;

// Range indicators
input bool     UseBBBandwidth           = true;
input double   BBW_Threshold            = 0.015;
input bool     UseDonchWidth            = false;
input int      Donch_Period             = 20;
input double   DonchWidthMin            = 0.001;
input double   DonchWidthMax            = 0.010;
input bool     UseATRBandwidth          = false;
input int      ATR_Period               = 14;
input double   ATRBandwidthMax          = 0.005;

// Safety: no trading
input bool     NoTrading_Enforced       = true;

// ---------------- Globals ----------------
datetime g_lastBarTime = 0;
int      g_csvHandle   = INVALID_HANDLE;
bool     g_csvHeaderWrote=false;

bool     g_prevSqueezeOn=false;
int      g_lastSqueezeReleaseBarIndex=999999;

string   OBJ_PANEL     = "RD_PANEL";
string   OBJ_VWAP_HL   = "RD_VWAP_HL";
string   OBJ_VB1U      = "RD_VB1U";
string   OBJ_VB1L      = "RD_VB1L";
string   OBJ_VB2U      = "RD_VB2U";
string   OBJ_VB2L      = "RD_VB2L";
string   OBJ_VB3U      = "RD_VB3U";
string   OBJ_VB3L      = "RD_VB3L";
string   OBJ_ZZ_HI     = "RD_ZZ_HI";
string   OBJ_ZZ_LO     = "RD_ZZ_LO";
string   OBJ_ZZ_MID    = "RD_ZZ_MID";

int      g_prevCurveSegments = 0;

// ---------------- Utils ----------------
double Pip(){ if(Digits==5 || Digits==3) return 10*Point; return Point; }
bool IsNewBar(){ datetime t0=iTime(Symbol(),Period(),0); if(t0!=g_lastBarTime){ g_lastBarTime=t0; return true;} return false;}
int TFSeconds(){ return Period()*60; }

string TFStr(int tf){
   if(tf==PERIOD_M1) return "M1"; if(tf==PERIOD_M5) return "M5"; if(tf==PERIOD_M15) return "M15";
   if(tf==PERIOD_M30) return "M30"; if(tf==PERIOD_H1) return "H1"; if(tf==PERIOD_H4) return "H4";
   if(tf==PERIOD_D1) return "D1"; if(tf==PERIOD_W1) return "W1"; if(tf==PERIOD_MN1) return "MN1";
   return IntegerToString(tf);
}

bool StartsWith(const string s, const string prefix){ return (StringFind(s, prefix, 0) == 0); }

void DrawHLine(string name,double price,color col,int width,int style){
   if(ObjectFind(name)==-1) ObjectCreate(name,OBJ_HLINE,0,0,price);
   ObjectSet(name,OBJPROP_PRICE,price);
   ObjectSet(name,OBJPROP_COLOR,col);
   ObjectSet(name,OBJPROP_WIDTH,width);
   ObjectSet(name,OBJPROP_STYLE,style);
}

void DrawTrendSeg(string name, datetime t1,double p1, datetime t2,double p2, color col, int width,int style){
   if(ObjectFind(name)==-1){
      ObjectCreate(name,OBJ_TREND,0,t1,p1,t2,p2);
      ObjectSet(name, OBJPROP_RAY, false);        // prevent infinite rays
      ObjectSet(name, OBJPROP_BACK, false);
      ObjectSet(name, OBJPROP_SELECTABLE, false);
   } else {
      ObjectMove(name,0,t1,p1);
      ObjectMove(name,1,t2,p2);
   }
   ObjectSet(name,OBJPROP_COLOR,col);
   ObjectSet(name,OBJPROP_WIDTH,width);
   ObjectSet(name,OBJPROP_STYLE,style);
}

void DrawLabel(string name,string text,int corner,int xoff,int yoff,color colText,color colBG){
   if(ObjectFind(name)==-1) ObjectCreate(name,OBJ_LABEL,0,0,0);
   // Convert LF -> CRLF to force multi-line in MT4
   string t=text;
   StringReplace(t, "\r\n", "\n"); // normalize first
   StringReplace(t, "\n", "\r\n");
   ObjectSet(name,OBJPROP_CORNER,corner);
   ObjectSet(name,OBJPROP_XDISTANCE,xoff);
   ObjectSet(name,OBJPROP_YDISTANCE,yoff);
   ObjectSet(name,OBJPROP_BACK,true);
   ObjectSetText(name,t,PanelFontSize,"Arial",colText);
}

// ---------------- CSV ----------------
int OpenCSV(){
   if(!WriteCSV) return INVALID_HANDLE;
   string tf=TFStr(Period());
   string fname=StringFormat("%s_%s_%d_%s.csv",Symbol(),tf,MagicNumber,LogBaseName);
   int flags=FILE_CSV|FILE_WRITE|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE;
   int h=INVALID_HANDLE;
   if(CsvPathMode==FilesDir) h=FileOpen(fname,flags,';');
   else if(CsvPathMode==CommonDir) h=FileOpen(fname,flags|FILE_COMMON,';');
   else {
      string full=LogDirectory; if(StringLen(full)>0 && full[StringLen(full)-1]!='\\' && full[StringLen(full)-1]!='/') full+="\\";
      full+=fname; h=FileOpen(full,flags,';');
   }
   if(h==INVALID_HANDLE) Print("CSV open failed. Error=",GetLastError());
   g_csvHeaderWrote=false; return h;
}
void WriteCSVHeader(){
   if(!WriteCSV || g_csvHandle==INVALID_HANDLE || g_csvHeaderWrote) return;
   FileWrite(g_csvHandle,"timestamp","bar_time","bar_index","symbol","timeframe",
      "price","vwap","vwap_slope","vwap_mode","window_sec","min_bars","weight_mode",
      "zz_high","zz_low","zz_mid","zz_range_pips",
      "sq_on","sq_rel_up","sq_rel_dn",
      "ema_ok","adx_ok","range_bw_ok","range_donch_ok","range_atr_ok",
      "trend_up","trend_dn","regime","direction","score");
   g_csvHeaderWrote=true;
}
void WriteCSVRow(int barIndex,double price,double vwap,double vwapSlope,string vwapModeStr,int windowSec,int minBars,string weightMode,
                 double zzH,double zzL,double zzM,double zzRngPips,
                 bool sqOn,bool sqUp,bool sqDn,
                 bool emaOk,bool adxOk,bool rngBWOk,bool rngDonchOk,bool rngATROk,
                 bool trUp,bool trDn,string regime,int dir,int score){
   if(!WriteCSV || g_csvHandle==INVALID_HANDLE) return;
   datetime bt=iTime(Symbol(),Period(),barIndex); string tf=TFStr(Period());
   FileWrite(g_csvHandle,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      TimeToString(bt,TIME_DATE|TIME_SECONDS),
      barIndex,Symbol(),tf,
      DoubleToString(price,Digits), DoubleToString(vwap,Digits), DoubleToString(vwapSlope,6), vwapModeStr, windowSec, minBars, weightMode,
      (zzH>0?DoubleToString(zzH,Digits):""),(zzL>0?DoubleToString(zzL,Digits):""),(zzM>0?DoubleToString(zzM,Digits):""), DoubleToString(zzRngPips,1),
      (sqOn?"1":"0"),(sqUp?"1":"0"),(sqDn?"1":"0"),
      (emaOk?"1":"0"),(adxOk?"1":"0"),(rngBWOk?"1":"0"),(rngDonchOk?"1":"0"),(rngATROk?"1":"0"),
      (trUp?"1":"0"),(trDn?"1":"0"),regime,dir,score);
}

// ---------------- Indicators ----------------
int AutoWindowMsForTF(){
   int MS_IN_MIN=60*1000, MS_IN_HOUR=60*60*1000, MS_IN_DAY=24*MS_IN_HOUR;
   int tfMs=TFSeconds()*1000;
   int ONE_MONTH_MS = 30*MS_IN_DAY + 10*MS_IN_HOUR + 30*MS_IN_MIN; // ~30.4375d
   if(tfMs<=MS_IN_MIN) return MS_IN_HOUR;
   if(tfMs<=5*MS_IN_MIN) return 4*MS_IN_HOUR;
   if(tfMs<=MS_IN_HOUR) return MS_IN_DAY;
   if(tfMs<=4*MS_IN_HOUR) return 3*MS_IN_DAY;
   if(tfMs<=12*MS_IN_HOUR) return 7*MS_IN_DAY;
   if(tfMs<=MS_IN_DAY) return ONE_MONTH_MS;
   if(tfMs<=7*MS_IN_DAY) return 90*MS_IN_DAY;
   return 365*MS_IN_DAY;
}
int WindowMs(){
   if(VwapMode!=Rolling) return AutoWindowMsForTF(); // Step-1 focuses on Rolling display
   if(UseFixedTimeWindow){
      int MS_IN_MIN=60*1000, MS_IN_HOUR=60*60*1000, MS_IN_DAY=24*MS_IN_HOUR;
      return WindowMinutes*MS_IN_MIN + WindowHours*MS_IN_HOUR + WindowDays*MS_IN_DAY;
   }
   return AutoWindowMsForTF();
}

bool RollingVWAP_At(int shift,int windowMs,int minBars,double &vwap,double &stdev){
   vwap=0; stdev=0; if(Bars<=shift) return false;
   datetime anchor=iTime(Symbol(),Period(),shift);
   int windowSec=windowMs/1000;
   double sumVol=0.0, sumSrcVol=0.0, sumSrc2Vol=0.0;
   int count=0;
   for(int i=shift; i<Bars; i++){
      datetime t=iTime(Symbol(),Period(),i);
      int dt=(int)(anchor - t);
      if(dt>windowSec && count>=minBars) break;
      double tp=(iHigh(Symbol(),Period(),i)+iLow(Symbol(),Period(),i)+iClose(Symbol(),Period(),i))/3.0;
      double vol=1.0;
      if(VWAP_WeightMode==TickVolume){ long vr=iVolume(Symbol(),Period(),i); vol = (double)vr; if(vol<=0.0) vol=1.0; }
      sumVol+=vol; sumSrcVol+=tp*vol; sumSrc2Vol+=(tp*tp)*vol;
      count++;
   }
   if(sumVol<=0) return false;
   vwap = sumSrcVol/sumVol;
   double variance=MathMax((sumSrc2Vol/sumVol) - vwap*vwap, 0.0);
   stdev = MathSqrt(variance);
   return true;
}
double VwapSlopeOverBars(int lookback,int windowMs,int minBars){
   if(lookback<1) lookback=1;
   double v0,s0,vN,sN;
   if(!RollingVWAP_At(0,windowMs,minBars,v0,s0)) return 0.0;
   int sh=MathMin(lookback,Bars-1);
   if(!RollingVWAP_At(sh,windowMs,minBars,vN,sN)) return 0.0;
   return (v0 - vN)/lookback;
}

// Squeeze
void ComputeSqueeze(bool &squeezeOn, bool &releaseUp, bool &releaseDn){
   int s=0;
   double bbU=iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,s);
   double bbL=iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,s);
   double bbW=bbU-bbL;

   double ma=iMA(Symbol(),Period(),KC_Period,0,MODE_EMA,PRICE_TYPICAL,s);
   double atr=iATR(Symbol(),Period(),KC_Period,s);
   double kcU=ma+KC_MultATR*atr, kcL=ma-KC_MultATR*atr;

   squeezeOn = (bbW < (kcU-kcL));
   releaseUp=false; releaseDn=false;
   static bool prevSq=false;
   if(prevSq && !squeezeOn){
      int wMs=WindowMs(); double v,sd; RollingVWAP_At(0,wMs,MinBarsInWindow,v,sd);
      double slope=VwapSlopeOverBars(VwapSlopePeriodBars,wMs,MinBarsInWindow);
      double price=iClose(Symbol(),Period(),0);
      if(price>v && slope>=VwapSlopeThreshold) releaseUp=true;
      if(price<v && slope<=-VwapSlopeThreshold) releaseDn=true;
   }
   prevSq = squeezeOn;

   if(releaseUp || releaseDn) g_lastSqueezeReleaseBarIndex=0;
   else if(g_lastSqueezeReleaseBarIndex<1000000) g_lastSqueezeReleaseBarIndex++;
}

// ZigZag last range
bool GetZigZagLastRange(double &zzHigh,double &zzLow,int &barHigh,int &barLow){
   zzHigh=-1; zzLow=-1; barHigh=-1; barLow=-1;
   for(int i=5; i<300 && i<Bars; i++){
      double val=iCustom(Symbol(),Period(),"ZigZag",ZZ_Depth,ZZ_Deviation,ZZ_Backstep,0,i);
      if(val==0 || val==EMPTY_VALUE) continue;
      if(val>=High[i]-2*Point){ if(barHigh==-1){ barHigh=i; zzHigh=val; } }
      if(val<=Low[i]+2*Point ){ if(barLow==-1 ){ barLow=i;  zzLow=val; } }
      if(barHigh!=-1 && barLow!=-1) break;
   }
   return (barHigh!=-1 && barLow!=-1);
}

// EMA/ADX helpers
bool EMAStackUp(double &sf,double &sm,double &ss){
   double eF0=iMA(Symbol(),Period(),EMA_Fast,0,MODE_EMA,PRICE_CLOSE,0);
   double eF1=iMA(Symbol(),Period(),EMA_Fast,0,MODE_EMA,PRICE_CLOSE,EMA_Fast);
   double eM0=iMA(Symbol(),Period(),EMA_Mid,0,MODE_EMA,PRICE_CLOSE,0);
   double eM1=iMA(Symbol(),Period(),EMA_Mid,0,MODE_EMA,PRICE_CLOSE,EMA_Mid);
   double eS0=iMA(Symbol(),Period(),EMA_Slow,0,MODE_EMA,PRICE_CLOSE,0);
   double eS1=iMA(Symbol(),Period(),EMA_Slow,0,MODE_EMA,PRICE_CLOSE,EMA_Slow);
   sf=eF0-eF1; sm=eM0-eM1; ss=eS0-eS1;
   return (eF0>eM0 && eM0>eS0 && sf>=EMA_MinSlope && sm>=0 && ss>=0);
}
bool EMAStackDn(double &sf,double &sm,double &ss){
   double eF0=iMA(Symbol(),Period(),EMA_Fast,0,MODE_EMA,PRICE_CLOSE,0);
   double eF1=iMA(Symbol(),Period(),EMA_Fast,0,MODE_EMA,PRICE_CLOSE,EMA_Fast);
   double eM0=iMA(Symbol(),Period(),EMA_Mid,0,MODE_EMA,PRICE_CLOSE,0);
   double eM1=iMA(Symbol(),Period(),EMA_Mid,0,MODE_EMA,PRICE_CLOSE,EMA_Mid);
   double eS0=iMA(Symbol(),Period(),EMA_Slow,0,MODE_EMA,PRICE_CLOSE,0);
   double eS1=iMA(Symbol(),Period(),EMA_Slow,0,MODE_EMA,PRICE_CLOSE,EMA_Slow);
   sf=eF0-eF1; sm=eM0-eM1; ss=eS0-eS1;
   return (eF0<eM0 && eM0<eS0 && sf<=-EMA_MinSlope && sm<=0 && ss<=0);
}
bool ADXUp(){ double adx=iADX(Symbol(),Period(),ADX_Period,PRICE_CLOSE,MODE_MAIN,0);
   double p=iADX(Symbol(),Period(),ADX_Period,PRICE_CLOSE,MODE_PLUSDI,0);
   double m=iADX(Symbol(),Period(),ADX_Period,PRICE_CLOSE,MODE_MINUSDI,0);
   return (adx>=ADX_Threshold && p>m);
}
bool ADXDn(){ double adx=iADX(Symbol(),Period(),ADX_Period,PRICE_CLOSE,MODE_MAIN,0);
   double p=iADX(Symbol(),Period(),ADX_Period,PRICE_CLOSE,MODE_PLUSDI,0);
   double m=iADX(Symbol(),Period(),ADX_Period,PRICE_CLOSE,MODE_MINUSDI,0);
   return (adx>=ADX_Threshold && m>p);
}

// Regime resolve
int Clamp(int v,int lo,int hi){ if(v<lo) return lo; if(v>hi) return hi; return v; }
void ResolveRegime(double vwap,double vSlope,bool squeezeOn,
                   bool &trendUp,bool &trendDn,bool &rangeOk,
                   int &dirOut,string &regime,int &scoreOut){
   double price=iClose(Symbol(),Period(),0);
   bool baseUp = (price>vwap && vSlope>=VwapSlopeThreshold);
   bool baseDn = (price<vwap && vSlope<=-VwapSlopeThreshold);
   bool emaOKup=true,emaOKdn=true,adxOKup=true,adxOKdn=true;

   if(UseEMAStack){ double sf,sm,ss; emaOKup=EMAStackUp(sf,sm,ss); emaOKdn=EMAStackDn(sf,sm,ss); }
   if(UseADX){ adxOKup=ADXUp(); adxOKdn=ADXDn(); }

   trendUp = baseUp && (!UseEMAStack || emaOKup) && (!UseADX || adxOKup);
   trendDn = baseDn && (!UseEMAStack || emaOKdn) && (!UseADX || adxOKdn);

   bool rngBBW = UseBBBandwidth ? ( (iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,0) - iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,0))
                                  / MathMax(iClose(Symbol(),Period(),0),1e-9) <= BBW_Threshold ) : false;
   bool rngDon = UseDonchWidth ? (
      (iHigh(Symbol(),Period(),iHighest(Symbol(),Period(),MODE_HIGH,Donch_Period,0)) - iLow(Symbol(),Period(),iLowest(Symbol(),Period(),MODE_LOW,Donch_Period,0)))
      / MathMax(iClose(Symbol(),Period(),0),1e-9) >= DonchWidthMin &&
      (iHigh(Symbol(),Period(),iHighest(Symbol(),Period(),MODE_HIGH,Donch_Period,0)) - iLow(Symbol(),Period(),iLowest(Symbol(),Period(),MODE_LOW,Donch_Period,0)))
      / MathMax(iClose(Symbol(),Period(),0),1e-9) <= DonchWidthMax
   ) : false;
   bool rngATR = UseATRBandwidth ? ( iATR(Symbol(),Period(),ATR_Period,0) / MathMax(iClose(Symbol(),Period(),0),1e-9) <= ATRBandwidthMax ) : false;

   rangeOk = (rngBBW || rngDon || rngATR || squeezeOn || (!trendUp && !trendDn));

   int score=0;
   if(SignalsCoherence==Strict){
      bool releaseRecent=(g_lastSqueezeReleaseBarIndex<=SignalWindowBars);
      if(trendUp && (releaseRecent || SignalWindowBars<=0)){ dirOut=+1; regime="TrendUp"; scoreOut=80; return; }
      if(trendDn && (releaseRecent || SignalWindowBars<=0)){ dirOut=-1; regime="TrendDn"; scoreOut=80; return; }
      dirOut=0; regime="Range"; scoreOut=50; return;
   } else {
      if(trendUp) score+=50; if(trendDn) score+=50;
      if(squeezeOn) score+=10; if(rngBBW) score+=10; if(rngDon) score+=10; if(rngATR) score+=10;
      scoreOut=Clamp(score,0,100);
      if(scoreOut>=SignalScoreThreshold){
         if(trendUp && !trendDn){ dirOut=+1; regime="TrendUp"; return; }
         if(trendDn && !trendUp){ dirOut=-1; regime="TrendDn"; return; }
      }
      dirOut=0; regime="Range"; return;
   }
}

// ---------------- Panel ----------------
void UpdatePanel(double vwap,double vSlope,double zzH,double zzL,double zzM,
                 bool sqOn,bool relUp,bool relDn,string regime,int dir,int score,
                 bool emaEnabled,bool emaPass,bool adxEnabled,bool adxPass,
                 bool rngBBW_Enabled,bool rngBBW_Pass,bool rngDonch_Enabled,bool rngDonch_Pass,bool rngATR_Enabled,bool rngATR_Pass){
   if(!ShowPanel) return;
   string dirStr = UseAsciiPanelSymbols ? (dir>0?"UP":dir<0?"DN":"RNG") : (dir>0?"↑":dir<0?"↓":"↔");

   string header = Symbol()+" ("+TFStr(Period())+")  "+dirStr;
   string line2  = "VWAP: "+DoubleToString(vwap,Digits)+"   slope: "+DoubleToString(vSlope,6);
   string line3  = "ZZ mid: "+ (zzH>0 && zzL>0 ? DoubleToString(zzM,Digits):"n/a") +"  (H: "+ (zzH>0?DoubleToString(zzH,Digits):"n/a") +"  L: "+ (zzL>0?DoubleToString(zzL,Digits):"n/a") +")";
   string line4  = sqOn? "Squeeze: ON" : (relUp? "Squeeze: Release UP" : (relDn?"Squeeze: Release DN":"Squeeze: OFF"));
   string line5  = (SignalsCoherence==Strict ? "Coherence: Strict" : ("Coherence: Score ("+IntegerToString(score)+"/"+IntegerToString(SignalScoreThreshold)+")"));
   string line6  = "Regime: "+regime;
   string ind    = "";
   if(ShowIndicatorStatus){
      ind = StringFormat("EMA:%s %s | ADX:%s %s | BBW:%s %s | DonchW:%s %s | ATRband:%s %s",
         (emaEnabled?"ON":"OFF"), (emaEnabled?(emaPass?"PASS":"FAIL"):""),
         (adxEnabled?"ON":"OFF"), (adxEnabled?(adxPass?"PASS":"FAIL"):""),
         (rngBBW_Enabled?"ON":"OFF"), (rngBBW_Enabled?(rngBBW_Pass?"PASS":"FAIL"):""),
         (rngDonch_Enabled?"ON":"OFF"), (rngDonch_Enabled?(rngDonch_Pass?"PASS":"FAIL"):""),
         (rngATR_Enabled?"ON":"OFF"), (rngATR_Enabled?(rngATR_Pass?"PASS":"FAIL"):"")
      );
   }
   string text = header+"\n"+line2+"\n"+line3+"\n"+line4+"\n"+line5+"\n"+line6+(ShowIndicatorStatus?("\n"+ind):"");
   DrawLabel(OBJ_PANEL,text,(int)PanelCorner,PanelXOffset,PanelYOffset,ColPanelText,ColPanelBG);
}

// ---------------- Lifecycle ----------------
int OnInit(){
   if(WriteCSV) g_csvHandle=OpenCSV();
   g_lastBarTime=0;
   return(INIT_SUCCEEDED);
}

void DeleteObjectIfExists(const string name) { if (ObjectFind(name) != -1) ObjectDelete(name); }

void ClearVwapCurveSegments(){
   for (int i = ObjectsTotal() - 1; i >= 0; i--){
      string objName = ObjectName(i);
      if (StartsWith(objName, "RD_VWSEG_")) ObjectDelete(objName);
   }
}

void OnDeinit(const int reason) {
   if (g_csvHandle != INVALID_HANDLE) { FileClose(g_csvHandle); g_csvHandle = INVALID_HANDLE; }

   DeleteObjectIfExists(OBJ_PANEL);
   DeleteObjectIfExists(OBJ_VWAP_HL);
   DeleteObjectIfExists(OBJ_VB1U);
   DeleteObjectIfExists(OBJ_VB1L);
   DeleteObjectIfExists(OBJ_VB2U);
   DeleteObjectIfExists(OBJ_VB2L);
   DeleteObjectIfExists(OBJ_VB3U);
   DeleteObjectIfExists(OBJ_VB3L);
   DeleteObjectIfExists(OBJ_ZZ_HI);
   DeleteObjectIfExists(OBJ_ZZ_LO);
   DeleteObjectIfExists(OBJ_ZZ_MID);
   DeleteObjectIfExists("RD_SQ_BADGE");

   ClearVwapCurveSegments();
   g_prevCurveSegments = 0;
}

void OnTick(){
   bool newBar = IsNewBar();

   // Compute VWAP current + stdev every tick so curve can update each tick
   int wMs=WindowMs();
   double vwap,sd; if(!RollingVWAP_At(0,wMs,MinBarsInWindow,vwap,sd)) return;
   double slope = VwapSlopeOverBars(VwapSlopePeriodBars,wMs,MinBarsInWindow);

   // Squeeze
   bool sqOn,relUp,relDn; ComputeSqueeze(sqOn,relUp,relDn);

   // ZigZag info
   double zzH=-1,zzL=-1,zzM=0,zzR=0; int bh=-1,bl=-1;
   if(ShowZigZag && GetZigZagLastRange(zzH,zzL,bh,bl)){ zzM=(zzH+zzL)*0.5; zzR=MathAbs(zzH-zzL)/Pip(); }

   // Regime
   bool trUp=false,trDn=false,rng=false; int dir=0,score=0; string regime="Range";
   ResolveRegime(vwap,slope,sqOn,trUp,trDn,rng,dir,regime,score);

   // Draw H-line + bands (optional)
   if(ShowVWAP_HLine){ DrawHLine(OBJ_VWAP_HL,vwap,ColVWAP,2,STYLE_SOLID); }
   if(VWAP_StdevMult1>0){ DrawHLine(OBJ_VB1U,vwap+VWAP_StdevMult1*sd,VWAP_StdevColor1,1,STYLE_DOT); DrawHLine(OBJ_VB1L,vwap-VWAP_StdevMult1*sd,VWAP_StdevColor1,1,STYLE_DOT); }
   if(VWAP_StdevMult2>0){ DrawHLine(OBJ_VB2U,vwap+VWAP_StdevMult2*sd,VWAP_StdevColor2,1,STYLE_DOT); DrawHLine(OBJ_VB2L,vwap-VWAP_StdevMult2*sd,VWAP_StdevColor2,1,STYLE_DOT); }
   if(VWAP_StdevMult3>0){ DrawHLine(OBJ_VB3U,vwap+VWAP_StdevMult3*sd,VWAP_StdevColor3,1,STYLE_DOT); DrawHLine(OBJ_VB3L,vwap-VWAP_StdevMult3*sd,VWAP_StdevColor3,1,STYLE_DOT); }

   // Draw VWAP curve: always update each tick; rebuild count only when changed
   if(ShowVWAPCurve){
      int bars = MathMin(MathMax(VwapCurveBars,2), Bars-1);
      int segsWanted = bars - 1;

      if (segsWanted != g_prevCurveSegments || newBar){
         ClearVwapCurveSegments();
         g_prevCurveSegments = 0;
      }

      for(int k=0; k<segsWanted; k++){
         double v1,s1,v2,s2;
         if(!RollingVWAP_At(k,  wMs,MinBarsInWindow,v1,s1)) break;
         if(!RollingVWAP_At(k+1,wMs,MinBarsInWindow,v2,s2)) break;
         datetime t1=iTime(Symbol(),Period(),k);
         datetime t2=iTime(Symbol(),Period(),k+1);
         string nm=StringFormat("RD_VWSEG_%d",k);
         DrawTrendSeg(nm, t2, v2, t1, v1, ColVWAP, VwapCurveWidth, STYLE_SOLID);
      }
      g_prevCurveSegments = segsWanted;
   }

   // ZigZag lines
   if(ShowZigZag && zzH>0 && zzL>0){
      DrawHLine(OBJ_ZZ_HI, zzH, ColZZHi,1,STYLE_DASH);
      DrawHLine(OBJ_ZZ_LO, zzL, ColZZLo,1,STYLE_DASH);
      DrawHLine(OBJ_ZZ_MID,zzM, ColZZMid,2,STYLE_DASHDOT);
   }

   // Panel refresh: every tick or only on new bar (per setting)
   if (PanelUpdateMode==EveryTick || newBar){
      bool emaPass=false, adxPass=false;
      if(UseEMAStack){ double sf,sm,ss; emaPass = EMAStackUp(sf,sm,ss) || EMAStackDn(sf,sm,ss); }
      if(UseADX){ adxPass = ADXUp() || ADXDn(); }
      bool rngBBWpass = UseBBBandwidth ? ( (iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,0) - iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,0)) / MathMax(iClose(Symbol(),Period(),0),1e-9) <= BBW_Threshold ) : false;
      bool rngDonchPass = UseDonchWidth ? true : false; // summarized
      bool rngATRpass = UseATRBandwidth ? ( iATR(Symbol(),Period(),ATR_Period,0) / MathMax(iClose(Symbol(),Period(),0),1e-9) <= ATRBandwidthMax ) : false;

      UpdatePanel(vwap,slope,zzH,zzL,zzM,sqOn,relUp,relDn,regime,dir,score,
                  UseEMAStack,emaPass,UseADX,adxPass,
                  UseBBBandwidth,rngBBWpass,UseDonchWidth,rngDonchPass,UseATRBandwidth,rngATRpass);
   }

   // Logging (default: only on new bars)
   if(WriteCSV && (!LogOnlyOnNewBar || newBar)){
      if(g_csvHandle==INVALID_HANDLE) g_csvHandle=OpenCSV();
      WriteCSVHeader();
      double price = iClose(Symbol(),Period(),0);
      WriteCSVRow(0,price,vwap,slope,(VwapMode==Rolling?"Rolling":(VwapMode==Daily?"Daily":"Session")), WindowMs()/1000, MinBarsInWindow,
                  (VWAP_WeightMode==TickVolume?"TickVol":"EqualW"),
                  zzH,zzL,zzM,zzR,
                  sqOn,relUp,relDn,
                  false,false, // ema/ADX detailed pass already in panel; keep CSV concise
                  UseBBBandwidth ? ( (iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,0) - iBands(Symbol(),Period(),BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,0)) / MathMax(iClose(Symbol(),Period(),0),1e-9) <= BBW_Threshold ) : false,
                  false,
                  UseATRBandwidth ? ( iATR(Symbol(),Period(),ATR_Period,0) / MathMax(iClose(Symbol(),Period(),0),1e-9) <= ATRBandwidthMax ) : false,
                  trUp,trDn,regime,dir,score);
      FileFlush(g_csvHandle);
   }
}