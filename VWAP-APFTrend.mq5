//+------------------------------------------------------------------+
//|                                                VWAP-APFTrend.mq5 |
//|              Copyright 2018, MetaQuotes Software Corp.- Humberto |
//|                                 http://aprendizfinanceiro.com.br |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, LFGuardian Software Corp.- Humberto"
#property link      "http://aprendizfinanceiro.com.br"
#property version   "1.03"
#property indicator_chart_window

#property indicator_buffers 1

#property indicator_plots 1                   //Number of graphic plots                 

#property indicator_label1   "Indicator"      //Buffer for calculated values
#property indicator_type1    DRAW_LINE
#property indicator_color1   clrDodgerBlue
#property indicator_style1   STYLE_SOLID
#property indicator_width2  2


// VWAP buffers
double buf_VWAP[];
double sumPrice,sumVol;
double auxsumPrice=0,auxsumVol=0;
datetime oldtime=0;

int dweek_now=0,dweek_last=0,wait=0;


//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping

    sumPrice=0;
    sumVol=0;

    // Assignment of array to indicator buffer
    SetIndexBuffer(0,buf_VWAP,INDICATOR_DATA);   

    // temp
    PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0.0);
    PlotIndexSetString(0,PLOT_LABEL,"Moving Average VWAP");
   
//---
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
//---

   //---  Redefine o valor do último erro
   ResetLastError();

   //--- First level for APFTrend indicator
   // - colors: white, 0: green (LTA), 1:, red:2 (LTB)
   int last=0;

   MqlDateTime date_candle;

   // Getting the candle records;
   last=0;
   if (prev_calculated>0) last = rates_total-1;

   for(int i=last; i<rates_total; i++) {
         
      // TimeToStruct(iTime(Symbol(), period, i),date_candle);
      TimeToStruct(time[i],date_candle);
      dweek_now = date_candle.day;
      if (oldtime==0) oldtime=time[i];      

      if (dweek_now != dweek_last) {
         wait=3;

         sumPrice=0;
         sumVol=0;
         
         dweek_last=dweek_now;
      }

      // Calc buf_VWAP
      double volume1=(double)volume[i];
      if (i>2 && volume[i]==0 && volume[i-1]==0) volume1=(double) tick_volume[i];
      if (wait==3) {
         sumPrice    = (double) (((high[i]+low[i]+close[i])/3) * volume1);
         sumVol      = volume1;
         if (sumVol>0) {
            buf_VWAP[i] = NormalizeDouble(sumPrice/sumVol,2);
            auxsumPrice = sumPrice;
            auxsumVol   = sumVol;
         }
      }
      else {
         if (prev_calculated>0) {
             if (time[i]!=oldtime) {
                auxsumPrice  = sumPrice;
                auxsumVol    = sumVol;
                //sumPrice    += (double) (((high[i-1]+low[i-1]+close[i-1])/3) * (double)volune[i-1]);
                //sumVol      += (double) volume2;
             }
             else {
                sumPrice   = auxsumPrice;
                sumVol     = auxsumVol;
             }
             sumPrice  += (double) (((high[i]+low[i]+close[i])/3) * volume1);
             sumVol    += volume1;
             oldtime=time[i];
         }
         else {
            sumPrice    += (double) (((high[i]+low[i]+close[i])/3) * volume1);
            sumVol      += volume1;
            auxsumPrice  = sumPrice;
            auxsumVol    = sumVol;
         }
         if (sumVol>0) buf_VWAP[i] = NormalizeDouble(sumPrice/sumVol,SYMBOL_DIGITS);
      }

      if (wait) wait--;
   } 
//--- return value of prev_calculated for next call
   return(rates_total);
  }


//+------------------------------------------------------------------+
//| Returns true if a new bar has appeared for a symbol/period pair  |
//+------------------------------------------------------------------+
bool isNewBar(const datetime lastbar_time)
  {
//--- memorize the time of opening of the last bar in the static variable
   static datetime last_time=0;
   
   //datetime lastbar_time=SeriesInfoInteger(Symbol(),Period(),SERIES_LASTBAR_DATE);
   MqlDateTime cur_time;
   TimeToStruct(TimeLocal(),cur_time);

//printf(lastbar_time);

//--- if it is the first call of the function
   if(last_time==0) {
      last_time=lastbar_time;
      return(false);
   }

//--- if the time differs
   if(last_time!=lastbar_time) {
      last_time=lastbar_time;
      return(true);
   }
   
//--- if we passed to this line, then the bar is not new; return false
   return(false);
  }
  
  
//+------------------------------------------------------------------+
//| Indicator deinitialization function                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- clear the chart after deleting the indicator
   Comment("");
  }
//+------------------------------------------------------------------+
