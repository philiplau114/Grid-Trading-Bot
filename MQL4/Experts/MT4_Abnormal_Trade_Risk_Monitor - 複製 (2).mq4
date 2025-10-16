//+------------------------------------------------------------------+
//|   MT4 EA: Abnormal Trade & Risk Monitor with Notification & UI   |
//|   Smart [BE] button: Close All or Partial Close in profit        |
//|   Enhanced message box logic, dashboard shows current price      |
//+------------------------------------------------------------------+
#property strict

//========= Inputs =========//
input double MaxLotSizePerSymbolBuy = 1.5;
input double MaxLotSizePerSymbolSell = 1.5;
input int    MaxTradeCountPerSymbolBuy = 3;
input int    MaxTradeCountPerSymbolSell = 3;
input double MarginLevelThreshold = 150.0;
input double MaxEquityDrawdownPercent = 20.0;
input double MaxTradeDurationHours = 24.0;
input double MaxSwap = 10.0;
input double BreakevenProfitAmount = 1.0;
input bool   EnableEmailAlert = false;
input bool   EnablePopupAlert = true;
input string LogFileName = "AbnormalTradeRiskMonitorLog.csv";
input int    AlertCooldownMins = 60;

//========= UI Inputs =========//
input int    FontSizeLabel    = 9;
input int    FontSizeHeader   = 12;
input int    RowHeight        = 18;
input int    HeaderHeight     = 22;
input color  PanelBGColor     = clrBlack;
input color  PanelBorderColor = clrGray;
input color  HeaderBGColor    = clrGold;
input color  HeaderTextColor  = clrBlue;
input color  ColHeaderBG      = clrAqua;
input color  ColHeaderText    = clrBlue;
input color  TotalsBG         = clrAqua;
input color  TotalsText       = clrBlue;
input color  PositiveCell     = clrLime;
input color  NegativeCell     = clrRed;
input color  NeutralCell      = clrWhite;
input color  BEBtnColor       = clrYellow;
input color  BEBtnActive      = clrLime;
input color  BEBtnText        = clrBlack;

//========= Constants =========//
#define MAX_GROUPS 100
#define MAX_TICKETS_PER_GROUP 100
#define MAX_ALERTS 200
#define TABLE_COLS 14
int colWidths[TABLE_COLS] = {70, 40, 42, 50, 60, 60, 50, 65, 48, 40, 70, 75, 75, 40};

//========= Structs =========//
struct SymTypeRow {
   string symbol;
   int    type; // OP_BUY or OP_SELL
   string typeStr;
   int    trades;
   double lots;
   double profit;
   double loss;
   double swap;
   double totalUSD;
   int    tickets[MAX_TICKETS_PER_GROUP];
   int    ticketCount;
   bool   beActive;
   double ddPct;
   double pips;
   double profitPct;
   double bePrice;
   double curPrice;
};
struct PartialCloseSuggest {
   int    ticketList[MAX_TICKETS_PER_GROUP];
   int    count;
   string symbol;
   int    type;
   bool   valid;
   double closeTotal;
   double closeLots;
   double remainTotal;
   double remainLots;
   string closeMsg;
   string remainMsg;
};

//========= BE State =========//
SymTypeRow beGroups[MAX_GROUPS];
int beGroupCount = 0;
PartialCloseSuggest lastSuggest;

//========= Alerts =========//
int      alertTickets[MAX_ALERTS];
int      alertTypes[MAX_ALERTS];
string   alertSymbols[MAX_ALERTS];
datetime alertTimes[MAX_ALERTS];

//========= Helper Functions =========//
int FindGroupRow(SymTypeRow &rows[], int n, string symbol, int type) {
   for(int i=0;i<n;i++)
      if(rows[i].symbol==symbol && rows[i].type==type)
         return i;
   return -1;
}
void LogEvent(string msg) {
   string ts = TimeToStr(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   Print(ts, " | ", msg);
   int handle = FileOpen(LogFileName, FILE_CSV|FILE_WRITE|FILE_READ, ',');
   if(handle != INVALID_HANDLE) {
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, ts, msg);
      FileClose(handle);
   }
}
bool IsGroupBE(string symbol, int type) {
   int idx = FindGroupRow(beGroups, beGroupCount, symbol, type);
   return (idx >= 0 && beGroups[idx].beActive);
}
void SendAlert(string msg) {
   if(EnablePopupAlert) Alert(msg);
   if(EnableEmailAlert) SendMail("Abnormal Trade & Risk Alert", msg);
   LogEvent(msg);
}
void ResetPartialSuggest() {
   lastSuggest.count = 0;
   lastSuggest.valid = false;
   lastSuggest.symbol = "";
   lastSuggest.type = -1;
   lastSuggest.closeTotal = 0;
   lastSuggest.closeLots = 0;
   lastSuggest.remainTotal = 0;
   lastSuggest.remainLots = 0;
   lastSuggest.closeMsg = "";
   lastSuggest.remainMsg = "";
}

//========= Partial Close Suggestion ========//
PartialCloseSuggest FindBestPartialClose(string symbol, int type) {
   int tlist[MAX_TICKETS_PER_GROUP] = {0}, n=0;
   double lots[MAX_TICKETS_PER_GROUP] = {0}, open[MAX_TICKETS_PER_GROUP] = {0}, profit[MAX_TICKETS_PER_GROUP] = {0}, swap[MAX_TICKETS_PER_GROUP] = {0}, comm[MAX_TICKETS_PER_GROUP] = {0};
   for(int i=0; i<OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol()==symbol && OrderType()==type) {
            tlist[n] = OrderTicket();
            lots[n] = OrderLots();
            open[n] = OrderOpenPrice();
            profit[n] = OrderProfit();
            swap[n] = OrderSwap();
            comm[n] = OrderCommission();
            n++;
         }
      }
   }
   double bestClosedNet = -1e10; // maximize closed group net profit
   int bestMask = 0;
   int bestCount = 0;
   double bestCloseTotal = 0, bestCloseLots = 0, bestRemainTotal = 0, bestRemainLots = 0;
   string bestCloseMsg = "", bestRemainMsg = "";

   for(int mask=1; mask < (1<<n)-1; mask++) { // all non-empty, non-all combos
      double cl_lots=0, cl_profit=0, cl_swap=0, cl_comm=0, cl_open=0;
      double rm_lots=0, rm_open=0, rm_profit=0, rm_swap=0, rm_comm=0;
      string closeMsg="", remainMsg="";
      for(int i=0;i<n;i++) {
         if((mask & (1 << i)) != 0) {
            cl_lots += lots[i];
            cl_profit += profit[i];
            cl_swap += swap[i];
            cl_comm += comm[i];
            closeMsg += IntegerToString(tlist[i]) + " (" + ((profit[i]>=0)?"+":"") + DoubleToString(profit[i],2) + ", lot " + DoubleToString(lots[i],2) + ")";
            if(i<n-1) closeMsg += ", ";
         } else {
            rm_lots += lots[i];
            rm_open += open[i]*lots[i];
            rm_profit += profit[i];
            rm_swap += swap[i];
            rm_comm += comm[i];
            remainMsg += IntegerToString(tlist[i]) + " (" + ((profit[i]>=0)?"+":"") + DoubleToString(profit[i],2) + ", lot " + DoubleToString(lots[i],2) + ")";
            if(i<n-1) remainMsg += ", ";
         }
      }
      double closedNet = cl_profit + cl_swap + cl_comm;
      if(closedNet < BreakevenProfitAmount) continue; // must cover BE profit
      // prefer (1) minimal close count, (2) max closed profit
      if(closedNet > bestClosedNet || bestCount==0 || cl_lots < bestCloseLots) {
         bestClosedNet = closedNet;
         bestMask = mask;
         bestCount = 0;
         bestCloseTotal = cl_profit;
         bestCloseLots = cl_lots;
         bestRemainTotal = rm_profit;
         bestRemainLots = rm_lots;
         bestCloseMsg = closeMsg;
         bestRemainMsg = remainMsg;
         for(int i=0;i<n;i++) if((mask & (1<<i)) != 0) bestCount++;
      }
   }
   PartialCloseSuggest ret; ret.count=0; ret.valid=false; ret.symbol=symbol; ret.type=type;
   ret.closeTotal = bestCloseTotal; ret.closeLots = bestCloseLots;
   ret.remainTotal = bestRemainTotal; ret.remainLots = bestRemainLots;
   ret.closeMsg = bestCloseMsg; ret.remainMsg = bestRemainMsg;
   if(bestCount > 0) {
      for(int i=0;i<n;i++) if((bestMask & (1<<i)) != 0) ret.ticketList[ret.count++] = tlist[i];
      ret.valid=true;
   }
   return ret;
}
void DoPartialClose(PartialCloseSuggest &sugg) {
   if(!sugg.valid || sugg.count==0) return;
   int closed=0;
   double price = (sugg.type==OP_BUY) ? MarketInfo(sugg.symbol, MODE_BID) : MarketInfo(sugg.symbol, MODE_ASK);
   for(int i=0;i<sugg.count;i++) {
      int t = sugg.ticketList[i];
      if(OrderSelect(t, SELECT_BY_TICKET, MODE_TRADES)) {
         if(OrderSymbol()==sugg.symbol && OrderType()==sugg.type) {
            if(OrderClose(t, OrderLots(), price, 5, clrYellow)) closed++;
         }
      }
   }
   string msg = "Partial Close: Closed " + IntegerToString(closed) + " trade(s) for "+sugg.symbol+" "+(sugg.type==OP_BUY ? "Buy":"Sell") + " group.";
   SendAlert(msg);
   ResetPartialSuggest();
}

//========= Margin Calculation for Profit% =========//
bool OrderCalcMargin(int trade_type, string symbol, double trade_volume, double open_price, double &margin_required)
{
   double remaining_margin = AccountFreeMarginCheck(symbol, trade_type, trade_volume);
   if (remaining_margin > 0)
      margin_required = AccountFreeMargin() - remaining_margin;
   else
      margin_required = AccountFreeMargin() + MathAbs(remaining_margin);
   return true;
}

//=== Sort groupRows by symbol, then type (Buy first, then Sell) ===//
void SortGroupRows(SymTypeRow &rows[], int n) {
   for(int i=0;i<n-1;i++)
      for(int j=i+1;j<n;j++)
         if(StringCompare(rows[i].symbol,rows[j].symbol)>0
            || (rows[i].symbol==rows[j].symbol && rows[i].type>rows[j].type))
         {
            SymTypeRow tmp = rows[i]; rows[i]=rows[j]; rows[j]=tmp;
         }
}

//========= Alerts (Cooldown, Tracking) =========//
void ResetAlerts() {
   for(int i=0; i<MAX_ALERTS; i++) {
      alertTickets[i] = -1;
      alertTypes[i] = -1;
      alertSymbols[i] = "";
      alertTimes[i] = 0;
   }
}
int FindAlert(int ticket, int type, string symbol) {
   for(int i=0; i<MAX_ALERTS; i++)
      if(alertTickets[i]==ticket && alertTypes[i]==type && alertSymbols[i]==symbol) return i;
   return -1;
}
void UpdateAlert(int ticket, int type, string symbol) {
   int i = FindAlert(ticket, type, symbol);
   if(i != -1) {
      alertTimes[i]=TimeCurrent();
   } else {
      for(int j=0;j<MAX_ALERTS;j++) {
         if(alertTickets[j]==-1 && alertTypes[j]==-1 && alertSymbols[j]=="") {
            alertTickets[j]=ticket;
            alertTypes[j]=type;
            alertSymbols[j]=symbol;
            alertTimes[j]=TimeCurrent();
            break;
         }
      }
   }
}
bool ShouldAlert(int ticket, int type, string symbol, int intervalSeconds) {
   int i = FindAlert(ticket, type, symbol);
   if(i==-1) return true;
   if(TimeCurrent() - alertTimes[i] >= intervalSeconds) return true;
   return false;
}
int FindSymbolAlert(int type, string symbol) {
   for(int i=0; i<MAX_ALERTS; i++)
      if(alertTypes[i]==type && alertSymbols[i]==symbol && alertTickets[i]==-1) return i;
   return -1;
}
void UpdateSymbolAlert(int type, string symbol) {
   int i = FindSymbolAlert(type, symbol);
   if(i!=-1) alertTimes[i]=TimeCurrent();
   else {
      for(int j=0;j<MAX_ALERTS;j++) {
         if(alertTickets[j]==-1 && alertTypes[j]==-1 && alertSymbols[j]=="") {
            alertTickets[j]=-1;
            alertTypes[j]=type;
            alertSymbols[j]=symbol;
            alertTimes[j]=TimeCurrent();
            break;
         }
      }
   }
}
bool ShouldSymbolAlert(int type, string symbol, int intervalSeconds) {
   int i = FindSymbolAlert(type, symbol);
   if(i==-1) return true;
   if(TimeCurrent() - alertTimes[i] >= intervalSeconds) return true;
   return false;
}

//========= Abnormal Risk/Trade Checks =========//
void CheckAbnormalStates() {
   double startEquity = AccountBalance();
   double curEquity = AccountEquity();
   double dd = (startEquity - curEquity) / startEquity * 100.0;

   double marginLevel = 0.0;
   int openTrades = OrdersTotal();
   if(openTrades > 0 && AccountMargin() > 0)
      marginLevel = (AccountEquity() / AccountMargin()) * 100.0;
   else
      marginLevel = 99999.0;

   if(openTrades > 0 && marginLevel < MarginLevelThreshold) {
      if(ShouldSymbolAlert(6, "MARGIN", AlertCooldownMins*60)) {
         SendAlert("Margin level below threshold: " + DoubleToStr(marginLevel, 2) + "%");
         UpdateSymbolAlert(6, "MARGIN");
      }
   }
   if(dd > MaxEquityDrawdownPercent) {
      if(ShouldSymbolAlert(7, "DRAWDOWN", AlertCooldownMins*60)) {
         SendAlert("Equity drawdown exceeds limit: " + DoubleToStr(dd,2) + "%");
         UpdateSymbolAlert(7, "DRAWDOWN");
      }
   }
   int types[100]; ArrayInitialize(types, 0);
   string symbols[100];
   double lots[100]; ArrayInitialize(lots, 0.0);
   int count[100]; ArrayInitialize(count, 0);
   int groupCount=0;
   for(int i=0; i<OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         string sym = OrderSymbol();
         int type = OrderType();
         if(type!=OP_BUY && type!=OP_SELL) continue;
         int idx = -1;
         for(int j=0;j<groupCount;j++) if(symbols[j]==sym && types[j]==type) { idx=j; break; }
         if(idx==-1) { idx=groupCount; symbols[groupCount]=sym; types[groupCount]=type; groupCount++; }
         lots[idx]+=OrderLots();
         count[idx]++;
      }
   }
   for(int i=0;i<groupCount;i++) {
      if(types[i]==OP_BUY && lots[i]>MaxLotSizePerSymbolBuy)
         if(ShouldSymbolAlert(2,symbols[i]+"_BUY",AlertCooldownMins*60)) {
            SendAlert("BUY lots on "+symbols[i]+" exceed threshold: "+DoubleToStr(lots[i],2));
            UpdateSymbolAlert(2,symbols[i]+"_BUY");
         }
      if(types[i]==OP_SELL && lots[i]>MaxLotSizePerSymbolSell)
         if(ShouldSymbolAlert(3,symbols[i]+"_SELL",AlertCooldownMins*60)) {
            SendAlert("SELL lots on "+symbols[i]+" exceed threshold: "+DoubleToStr(lots[i],2));
            UpdateSymbolAlert(3,symbols[i]+"_SELL");
         }
      if(types[i]==OP_BUY && count[i]>MaxTradeCountPerSymbolBuy)
         if(ShouldSymbolAlert(4,symbols[i]+"_BUY",AlertCooldownMins*60)) {
            SendAlert("BUY count on "+symbols[i]+" exceed threshold: "+IntegerToString(count[i]));
            UpdateSymbolAlert(4,symbols[i]+"_BUY");
         }
      if(types[i]==OP_SELL && count[i]>MaxTradeCountPerSymbolSell)
         if(ShouldSymbolAlert(5,symbols[i]+"_SELL",AlertCooldownMins*60)) {
            SendAlert("SELL count on "+symbols[i]+" exceed threshold: "+IntegerToString(count[i]));
            UpdateSymbolAlert(5,symbols[i]+"_SELL");
         }
   }
}

//========= Alerts for other risk conditions =========//
void CheckTrades() {
   int intervalSec = AlertCooldownMins * 60;
   struct BETradeGroup {
      string symbol;
      int    type;
      double groupNetProfit;
      double groupLots;
      int    groupCount;
      double groupSwap;
      double groupComm;
   };
   BETradeGroup beTradeGroups[MAX_GROUPS]; int beCount=0;
   for(int i=0; i<OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         string sym = OrderSymbol();
         int type = OrderType();
         if(type!=OP_BUY && type!=OP_SELL) continue;
         int idx = -1;
         for(int j=0;j<beCount;j++) if(beTradeGroups[j].symbol==sym && beTradeGroups[j].type==type) { idx=j; break; }
         if(idx==-1) {
            idx = beCount++;
            beTradeGroups[idx].symbol = sym;
            beTradeGroups[idx].type = type;
            beTradeGroups[idx].groupNetProfit = 0;
            beTradeGroups[idx].groupLots = 0;
            beTradeGroups[idx].groupCount = 0;
            beTradeGroups[idx].groupSwap = 0;
            beTradeGroups[idx].groupComm = 0;
         }
         beTradeGroups[idx].groupNetProfit += OrderProfit() + OrderSwap() + OrderCommission();
         beTradeGroups[idx].groupSwap += OrderSwap();
         beTradeGroups[idx].groupComm += OrderCommission();
         beTradeGroups[idx].groupLots += OrderLots();
         beTradeGroups[idx].groupCount++;
      }
   }
   for(int i=0; i<beCount; i++) {
      string typeStr = (beTradeGroups[i].type == OP_BUY) ? "Buy" : "Sell";
      string key = beTradeGroups[i].symbol + "_" + typeStr;
      if(beTradeGroups[i].groupNetProfit >= BreakevenProfitAmount) {
         if(ShouldSymbolAlert(1, key, intervalSec)) {
            SendAlert("Breakeven reached for " + beTradeGroups[i].symbol + " " + typeStr + " group");
            UpdateSymbolAlert(1, key);
         }
      }
   }
   for(int i=0; i<OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         string sym = OrderSymbol();
         int type = OrderType();
         double openPrice = OrderOpenPrice();
         double sl = OrderStopLoss();
         double profit = OrderProfit();
         double swap = OrderSwap();
         double commission = OrderCommission();
         double durationH = (TimeCurrent() - OrderOpenTime())/3600.0;
         int ticket = OrderTicket();

         if(durationH > MaxTradeDurationHours) {
            if(ShouldAlert(ticket, 8, sym, intervalSec)) {
               SendAlert("Trade " + IntegerToString(ticket) + " open > " + DoubleToStr(MaxTradeDurationHours,1) + "h");
               UpdateAlert(ticket, 8, sym);
            }
         }
         if(MathAbs(swap) > MaxSwap) {
            if(ShouldAlert(ticket, 9, sym, intervalSec)) {
               SendAlert("Trade " + IntegerToString(ticket) + " swap exceeds threshold: " + DoubleToStr(swap,2));
               UpdateAlert(ticket, 9, sym);
            }
         }
      }
   }
}

//========= Cell Drawing (unchanged) =========//
void DrawCell(string objPrefix, int x, int y, int w, int h, string text, color bg, color fg, int fontSize, string font) {
   string rectName = objPrefix+"_rect";
   string labelName = objPrefix+"_lbl";
   if(ObjectFind(rectName)<0)
      ObjectCreate(rectName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(rectName, OBJPROP_CORNER, 0);
   ObjectSet(rectName, OBJPROP_XDISTANCE, x);
   ObjectSet(rectName, OBJPROP_YDISTANCE, y);
   ObjectSet(rectName, OBJPROP_XSIZE, w);
   ObjectSet(rectName, OBJPROP_YSIZE, h);
   ObjectSet(rectName, OBJPROP_COLOR, bg);
   ObjectSetInteger(0, rectName, OBJPROP_BGCOLOR, bg);
   ObjectSet(rectName, OBJPROP_BACK, false);

   if(ObjectFind(labelName)<0)
      ObjectCreate(labelName, OBJ_LABEL, 0, 0, 0);
   ObjectSet(labelName, OBJPROP_CORNER, 0);
   ObjectSet(labelName, OBJPROP_XDISTANCE, x+2);
   ObjectSet(labelName, OBJPROP_YDISTANCE, y+1);
   ObjectSetText(labelName, text, fontSize, font, fg);
}

//========= Main Dashboard Drawing Function with Cur.Price =========//
void DrawDashboard() {
   string prefix = "ATRMSymTypeDash_";
   int x0=10, y0=10;
   int tableW=0; for(int c=0;c<TABLE_COLS;c++) tableW+=colWidths[c];

   // Group symbol+type rows
   SymTypeRow groupRows[MAX_GROUPS];
   int groupN=0;
   double totLots=0, totProfit=0, totLoss=0, totSwap=0, totUSD=0, totDD=0, totPips=0, totProfitP=0;
   int totTrades=0;
   for(int i=0;i<OrdersTotal();i++) {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) {
         string sym = OrderSymbol();
         int type = OrderType();
         if(type!=OP_BUY && type!=OP_SELL) continue;
         int idx = FindGroupRow(groupRows, groupN, sym, type);
         if(idx < 0) {
            idx = groupN++;
            groupRows[idx].symbol = sym;
            groupRows[idx].type = type;
            groupRows[idx].typeStr = (type==OP_BUY)?"Buy":"Sell";
            groupRows[idx].trades=0;
            groupRows[idx].lots=0;
            groupRows[idx].profit=0;
            groupRows[idx].loss=0;
            groupRows[idx].swap=0;
            groupRows[idx].totalUSD=0;
            groupRows[idx].tickets[0]=0;
            groupRows[idx].ticketCount=0;
            groupRows[idx].beActive = IsGroupBE(sym, type);
            groupRows[idx].ddPct=0; groupRows[idx].pips=0; groupRows[idx].profitPct=0; groupRows[idx].bePrice=0;
            groupRows[idx].curPrice=0;
         }
         double lots = OrderLots();
         double profit = OrderProfit();
         double swap = OrderSwap();
         groupRows[idx].trades++;
         groupRows[idx].lots += lots;
         if(profit >= 0) groupRows[idx].profit += profit;
         else groupRows[idx].loss += profit;
         groupRows[idx].swap += swap;
         groupRows[idx].totalUSD += profit + swap;
         groupRows[idx].tickets[groupRows[idx].ticketCount++] = OrderTicket();
      }
   }
   for(int r=0;r<groupN;r++) {
      double avgOpen=0, pip=0, ddpct=0, profit=0, baseEquity=AccountBalance(), com=0, swap=0;
      double lots=0, sumOpen=0, sumProfit=0, sumSwap=0, sumComm=0;
      for(int t=0; t<groupRows[r].ticketCount; t++) {
         if(OrderSelect(groupRows[r].tickets[t], SELECT_BY_TICKET, MODE_TRADES)) {
            lots += OrderLots();
            sumOpen += OrderOpenPrice()*OrderLots();
            sumProfit += OrderProfit();
            sumSwap += OrderSwap();
            sumComm += OrderCommission();
         }
      }
      if(groupRows[r].trades > 0 && lots > 0) {
          avgOpen = sumOpen / lots;
          int digits = (int)MarketInfo(groupRows[r].symbol, MODE_DIGITS);
          int pipDiv = (digits == 3 || digits == 5) ? 10 : 1;
          double pipValue = MarketInfo(groupRows[r].symbol, MODE_TICKVALUE) * (lots / 0.01);
          double remainProfit = BreakevenProfitAmount - (sumProfit + sumSwap + sumComm);
          double priceDelta = 0.0;
          if(pipValue > 0)
              priceDelta = (remainProfit / pipValue) * MarketInfo(groupRows[r].symbol, MODE_POINT);
          if(groupRows[r].type == OP_BUY) {
              groupRows[r].bePrice = avgOpen + priceDelta;
              groupRows[r].curPrice = MarketInfo(groupRows[r].symbol, MODE_BID);
          } else {
              groupRows[r].bePrice = avgOpen - priceDelta;
              groupRows[r].curPrice = MarketInfo(groupRows[r].symbol, MODE_ASK);
          }
          profit = sumProfit;
          double groupMargin = 0.0;
          for(int t = 0; t < groupRows[r].ticketCount; t++) {
              if(OrderSelect(groupRows[r].tickets[t], SELECT_BY_TICKET, MODE_TRADES)) {
                  double om = 0;
                  if(OrderCalcMargin(OrderType(), OrderSymbol(), OrderLots(), OrderOpenPrice(), om))
                      groupMargin += om;
              }
          }
          groupRows[r].profitPct = (groupMargin > 0) ? profit / groupMargin * 100 : 0;
      }
      groupRows[r].ddPct = ddpct;
      groupRows[r].pips = pip;
   }
   SortGroupRows(groupRows, groupN);

   int rowCount = groupN+1;
   int panelWidth = tableW+16;
   int panelHeight = HeaderHeight+RowHeight*(rowCount+1)+8;

   string panelName = prefix+"Panel";
   if(ObjectFind(panelName)<0)
      ObjectCreate(panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(panelName, OBJPROP_CORNER, 0);
   ObjectSet(panelName, OBJPROP_XDISTANCE, x0);
   ObjectSet(panelName, OBJPROP_YDISTANCE, y0);
   ObjectSet(panelName, OBJPROP_XSIZE, panelWidth);
   ObjectSet(panelName, OBJPROP_YSIZE, panelHeight);
   ObjectSet(panelName, OBJPROP_COLOR, PanelBorderColor);
   ObjectSetInteger(0, panelName, OBJPROP_BGCOLOR, PanelBGColor);
   ObjectSet(panelName, OBJPROP_SELECTABLE, true);

   DrawCell(prefix+"Banner", x0, y0, tableW, HeaderHeight, "Open Trades    MT4 Abnormal Trade & Risk Monitor (Real-time)", HeaderBGColor, HeaderTextColor, FontSizeHeader, "Arial Bold");

   string colNames[TABLE_COLS] = {"Symb","Type","Trade","Lots","Profit","Loss","Swap","Tot.US","DD %","Pips","Profit%","Cur.Price","BE Price","[BE]"};
   int cx=x0, cy=y0+HeaderHeight;
   for(int c=0;c<TABLE_COLS;c++) {
      DrawCell(prefix+"ColHead"+IntegerToString(c), cx, cy, colWidths[c], RowHeight, colNames[c], ColHeaderBG, ColHeaderText, FontSizeLabel, "Arial Bold");
      cx+=colWidths[c];
   }

   cy += RowHeight;
   for(int r=0;r<groupN;r++) {
      cx = x0;
      color cProfit = groupRows[r].profit >= 0 ? PositiveCell : NegativeCell;
      color cLoss   = groupRows[r].loss < 0   ? NegativeCell : NeutralCell;
      color cSwap   = groupRows[r].swap >= 0  ? PositiveCell : NegativeCell;
      color cUSD    = groupRows[r].totalUSD >= 0 ? PositiveCell : NegativeCell;
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c0", cx, cy, colWidths[0], RowHeight, groupRows[r].symbol, NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[0];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c1", cx, cy, colWidths[1], RowHeight, groupRows[r].typeStr, NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[1];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c2", cx, cy, colWidths[2], RowHeight, IntegerToString(groupRows[r].trades), NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[2];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c3", cx, cy, colWidths[3], RowHeight, DoubleToString(groupRows[r].lots, 2), NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[3];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c4", cx, cy, colWidths[4], RowHeight, DoubleToString(groupRows[r].profit, 2), cProfit, clrBlack, FontSizeLabel, "Arial");
      cx+=colWidths[4];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c5", cx, cy, colWidths[5], RowHeight, DoubleToString(groupRows[r].loss, 2), cLoss, clrWhite, FontSizeLabel, "Arial");
      cx+=colWidths[5];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c6", cx, cy, colWidths[6], RowHeight, DoubleToString(groupRows[r].swap, 2), cSwap, clrBlack, FontSizeLabel, "Arial");
      cx+=colWidths[6];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c7", cx, cy, colWidths[7], RowHeight, DoubleToString(groupRows[r].totalUSD, 2), cUSD, clrBlack, FontSizeLabel, "Arial");
      cx+=colWidths[7];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c8", cx, cy, colWidths[8], RowHeight, DoubleToString(groupRows[r].ddPct, 2), NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[8];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c9", cx, cy, colWidths[9], RowHeight, IntegerToString((int)groupRows[r].pips), NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[9];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c10", cx, cy, colWidths[10], RowHeight, DoubleToString(groupRows[r].profitPct, 2), NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[10];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c11", cx, cy, colWidths[11], RowHeight, DoubleToString(groupRows[r].curPrice, 5), NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[11];
      DrawCell(prefix+"sym"+IntegerToString(r)+"_c12", cx, cy, colWidths[12], RowHeight, DoubleToString(groupRows[r].bePrice, 5), NeutralCell, clrBlue, FontSizeLabel, "Arial");
      cx+=colWidths[12];
      string btnBEName = prefix+"BtnBE_"+groupRows[r].symbol+"|"+groupRows[r].typeStr;
      string btnLabel = groupRows[r].beActive ? "[BE:ON]" : "[BE]";
      color btnColor = groupRows[r].beActive ? BEBtnActive : BEBtnColor;
      if(ObjectFind(btnBEName)<0)
         ObjectCreate(btnBEName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSet(btnBEName, OBJPROP_CORNER, 0);
      ObjectSet(btnBEName, OBJPROP_XDISTANCE, cx);
      ObjectSet(btnBEName, OBJPROP_YDISTANCE, cy);
      ObjectSet(btnBEName, OBJPROP_XSIZE, colWidths[13]);
      ObjectSet(btnBEName, OBJPROP_YSIZE, RowHeight);
      ObjectSet(btnBEName, OBJPROP_COLOR, btnColor);
      ObjectSetInteger(0, btnBEName, OBJPROP_BGCOLOR, btnColor);
      ObjectSet(btnBEName, OBJPROP_SELECTABLE, true);

      string btnLblName = btnBEName+"_lbl";
      if(ObjectFind(btnLblName)<0)
         ObjectCreate(btnLblName, OBJ_LABEL, 0, 0, 0);
      ObjectSet(btnLblName, OBJPROP_CORNER, 0);
      ObjectSet(btnLblName, OBJPROP_XDISTANCE, cx+4);
      ObjectSet(btnLblName, OBJPROP_YDISTANCE, cy+2);
      ObjectSetText(btnLblName, btnLabel, FontSizeLabel, "Arial Bold", BEBtnText);

      totTrades += groupRows[r].trades;
      totLots += groupRows[r].lots;
      totProfit += groupRows[r].profit;
      totLoss += groupRows[r].loss;
      totSwap += groupRows[r].swap;
      totUSD += groupRows[r].totalUSD;
      totDD += groupRows[r].ddPct;
      totPips += groupRows[r].pips;
      totProfitP += groupRows[r].profitPct;
      cy += RowHeight;
   }
   cx = x0;
   DrawCell(prefix+"total_c0", cx, cy, colWidths[0], RowHeight, "Total", TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[0];
   DrawCell(prefix+"total_c1", cx, cy, colWidths[1], RowHeight, "", TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[1];
   DrawCell(prefix+"total_c2", cx, cy, colWidths[2], RowHeight, IntegerToString(totTrades), TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[2];
   DrawCell(prefix+"total_c3", cx, cy, colWidths[3], RowHeight, DoubleToString(totLots,2), TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[3];
   DrawCell(prefix+"total_c4", cx, cy, colWidths[4], RowHeight, DoubleToString(totProfit,2), TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[4];
   DrawCell(prefix+"total_c5", cx, cy, colWidths[5], RowHeight, DoubleToString(totLoss,2), TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[5];
   DrawCell(prefix+"total_c6", cx, cy, colWidths[6], RowHeight, DoubleToString(totSwap,2), TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[6];
   DrawCell(prefix+"total_c7", cx, cy, colWidths[7], RowHeight, DoubleToString(totUSD,2), TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[7];
   DrawCell(prefix+"total_c8", cx, cy, colWidths[8], RowHeight, "-", TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[8];
   DrawCell(prefix+"total_c9", cx, cy, colWidths[9], RowHeight, "-", TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[9];
   DrawCell(prefix+"total_c10", cx, cy, colWidths[10], RowHeight, "-", TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[10];
   DrawCell(prefix+"total_c11", cx, cy, colWidths[11], RowHeight, "-", TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[11];
   DrawCell(prefix+"total_c12", cx, cy, colWidths[12], RowHeight, "-", TotalsBG, TotalsText, FontSizeLabel, "Arial");
   cx+=colWidths[12];
   DrawCell(prefix+"total_c13", cx, cy, colWidths[13], RowHeight, "-", TotalsBG, TotalsText, FontSizeLabel, "Arial");
}

//========= BE/Partial Close Button Handler with MessageBox ==========//
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    string prefix = "ATRMSymTypeDash_";
    string baseSparam = sparam;
    // If the object is a label (ends with _lbl), strip it to get the base button name
    if(StringFind(sparam, "_lbl") == StringLen(sparam) - 4)
        baseSparam = StringSubstr(sparam, 0, StringLen(sparam) - 4);

    if(id == CHARTEVENT_OBJECT_CLICK) {
        if(StringFind(baseSparam, prefix + "BtnBE_") == 0) {
            string remain = StringSubstr(baseSparam, StringLen(prefix+"BtnBE_"));
            int sep = StringFind(remain, "|");
            string symbol = StringSubstr(remain, 0, sep);
            string typeStr = StringSubstr(remain, sep+1);

         int type = (typeStr=="Buy") ? OP_BUY : OP_SELL;
         int idx = FindGroupRow(beGroups, beGroupCount, symbol, type);
         if(idx<0) {
            idx = beGroupCount++;
            beGroups[idx].symbol = symbol;
            beGroups[idx].type = type;
            beGroups[idx].typeStr = typeStr;
            beGroups[idx].beActive = false;
         }
         // Calculate group profit
         double totalUSD=0;
         for(int i=0; i<OrdersTotal(); i++)
            if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
               if(OrderSymbol()==symbol && OrderType()==type) totalUSD+=OrderProfit()+OrderSwap();

         // -------- Two-step MessageBox logic if in profit --------
         if(totalUSD > 0) {
            PartialCloseSuggest sugg = FindBestPartialClose(symbol, type);
            bool partialAvailable = sugg.valid && sugg.count>0;
            string msg = "Partial Close is available for these tickets:\n";
            msg += (partialAvailable ? sugg.closeMsg : "None. (No safe combination found)\n");
            msg += "Subtotal to close: " + ((sugg.closeTotal>=0)?"+":"") + DoubleToString(sugg.closeTotal,2) + ", lot " + DoubleToString(sugg.closeLots,2) + "\n\n";
            msg += "Remaining tickets:\n" + (partialAvailable?sugg.remainMsg:"(All will be closed)\n");
            msg += "Subtotal remaining: " + ((sugg.remainTotal>=0)?"+":"") + DoubleToString(sugg.remainTotal,2) + ", lot " + DoubleToString(sugg.remainLots,2) + "\n\n";
            msg += "YES: Partial Close\nNO: Close All\nCANCEL: Cancel";
            int res = MessageBox(msg, "BE Action for "+symbol+" "+typeStr, partialAvailable?MB_YESNOCANCEL:MB_OKCANCEL);

            if(res == IDYES && partialAvailable) {
                DoPartialClose(sugg);
                return;
            } else if((res == IDNO && partialAvailable) || (res == IDOK && !partialAvailable)) {
                int res2 = MessageBox("Are you sure you want to CLOSE ALL trades in this group?\nOK: Close All\nCANCEL: Cancel.",
                   "Close All for "+symbol+" "+typeStr, MB_OKCANCEL);
                if(res2 == IDOK) {
                   int closed=0;
                   double price = (type==OP_BUY) ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);
                   for(int i=0;i<OrdersTotal();i++) {
                      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) {
                         if(OrderSymbol()==symbol && OrderType()==type) {
                            if(OrderClose(OrderTicket(), OrderLots(), price, 5, clrAqua)) closed++;
                         }
                      }
                   }
                   string msg2 = "Closed ALL "+IntegerToString(closed)+" trades for "+symbol+" "+typeStr+" group.";
                   SendAlert(msg2);
                }
                return;
            }
            return;
         }
         // -------- Default: Toggle BE monitoring (drawdown recovery) --------
         beGroups[idx].beActive = !beGroups[idx].beActive;
         string msg = symbol + " " + typeStr + " group BE monitoring " + (beGroups[idx].beActive ? "enabled" : "disabled");
         Alert(msg);
         LogEvent(msg);
      }
   }
}

//========= BE Auto-Close Logic =========//
void CheckBEAutoClose() {
   for(int idx=0; idx<beGroupCount; idx++) {
      if(!beGroups[idx].beActive) continue;
      string symbol = beGroups[idx].symbol;
      int type = beGroups[idx].type;
      double lots=0, sumOpen=0, sumProfit=0, sumSwap=0, sumComm=0;
      int ticketList[MAX_TICKETS_PER_GROUP]; int tCount=0;
      ArrayInitialize(ticketList, 0);
      for(int i=0; i<OrdersTotal(); i++) {
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) {
            if(OrderSymbol()==symbol && OrderType()==type) {
               lots += OrderLots();
               sumOpen += OrderOpenPrice()*OrderLots();
               sumProfit += OrderProfit();
               sumSwap += OrderSwap();
               sumComm += OrderCommission();
               ticketList[tCount++] = OrderTicket();
            }
         }
      }
      if(lots==0) { beGroups[idx].beActive=false; continue; }
      double avgOpen = sumOpen/lots;
      double pipValue = MarketInfo(symbol, MODE_TICKVALUE)*(lots/0.01);
      double remainProfit = BreakevenProfitAmount - (sumProfit + sumSwap + sumComm);
      double priceDelta = (pipValue>0) ? (remainProfit/pipValue)*MarketInfo(symbol, MODE_POINT) : 0.0;
      double bePrice = (type==OP_BUY) ? avgOpen+priceDelta : avgOpen-priceDelta;

      if(type==OP_BUY) {
         double bid = MarketInfo(symbol, MODE_BID);
         if(bid >= bePrice) {
            for(int t=0; t<tCount; t++) {
               if(OrderSelect(ticketList[t], SELECT_BY_TICKET, MODE_TRADES)) {
                  bool closed = OrderClose(OrderTicket(), OrderLots(), bid, 5, clrLime);
                  if(closed) LogEvent("BE auto-closed: " + symbol + " Buy ticket " + IntegerToString(OrderTicket()));
               }
            }
            beGroups[idx].beActive = false;
            Alert("All " + symbol + " Buy trades closed at group BE price ("+DoubleToString(bePrice,5)+")");
         }
      } else {
         double ask = MarketInfo(symbol, MODE_ASK);
         if(ask <= bePrice) {
            for(int t=0; t<tCount; t++) {
               if(OrderSelect(ticketList[t], SELECT_BY_TICKET, MODE_TRADES)) {
                  bool closed = OrderClose(OrderTicket(), OrderLots(), ask, 5, clrRed);
                  if(closed) LogEvent("BE auto-closed: " + symbol + " Sell ticket " + IntegerToString(OrderTicket()));
               }
            }
            beGroups[idx].beActive = false;
            Alert("All " + symbol + " Sell trades closed at group BE price ("+DoubleToString(bePrice,5)+")");
         }
      }
   }
}

//========= EA Entry Points =========//
int OnInit() {
   ResetPartialSuggest();
   ResetAlerts();
   LogEvent("EA initialized");
   DrawDashboard();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {
   string prefix = "ATRMSymTypeDash_";
   string panelName = prefix+"Panel";
   if(ObjectFind(panelName) >= 0) ObjectDelete(panelName);
   for(int i=0;i<MAX_GROUPS*TABLE_COLS+100;i++) {
      string objName = prefix+"sym"+IntegerToString(i/TABLE_COLS)+"_c"+IntegerToString(i%TABLE_COLS);
      if(ObjectFind(objName)>=0) ObjectDelete(objName);
      string btnName = prefix+"BtnBE_"+IntegerToString(i);
      if(ObjectFind(btnName)>=0) ObjectDelete(btnName);
      string btnLbl = btnName+"_lbl";
      if(ObjectFind(btnLbl)>=0) ObjectDelete(btnLbl);
   }
   for(int i=0;i<TABLE_COLS;i++) {
      string head = prefix+"ColHead"+IntegerToString(i);
      if(ObjectFind(head)>=0) ObjectDelete(head);
      string tot = prefix+"total_c"+IntegerToString(i);
      if(ObjectFind(tot)>=0) ObjectDelete(tot);
   }
   if(ObjectFind(prefix+"Banner")>=0) ObjectDelete(prefix+"Banner");
   LogEvent("EA deinitialized");
}
int start() {
   CheckAbnormalStates();
   CheckTrades();
   DrawDashboard();
   CheckBEAutoClose();
   return(0);
}