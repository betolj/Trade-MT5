//+------------------------------------------------------------------+
//|                                                   APF-Color.mq5 |
//|                              Copyright 2019, Aprendiz Financeiro |
//|                                 http://aprendizfinanceiro.com.br |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019, Aprendiz Financeiro"
#property link      "http://aprendizfinanceiro.com.br"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   1
//--- plot Label1
#property indicator_label1  "Label1"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrBisque,clrGreen,clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

input int fail_trades=5;                        // Limite de trades falhos
input int max_daytrades=8;                // Número máximo de trades
input int max_tradeloss=-30;               // Prejuízo máximo em pts

input bool Trade_Sum=false;
input bool Trade_Total=false;

//--- indicator buffers
double        HighBuf[];
double        CloseBuf[];
double        OpenBuf[];
double        LowBuf[];
double        buf_color_line[];

//--- Indicador de referência
int              handle=0,hSAR=0,hstdDev=0;
double        buf_MA[],buf_SAR[],buf_stdDev[];


//--- Trade control
static int trade_dir=0,trade_ct=0;
static double trade_open=0,bars_trade=0;

static int wait=0,dweek_now=0,dweek_last=0,last_index=0;


//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   last_index=0;
   
   SetIndexBuffer(0,OpenBuf,INDICATOR_DATA);
   SetIndexBuffer(1,HighBuf,INDICATOR_DATA);
   SetIndexBuffer(2,LowBuf,INDICATOR_DATA);
   SetIndexBuffer(3,CloseBuf,INDICATOR_DATA);   
   SetIndexBuffer(4,buf_color_line,INDICATOR_COLOR_INDEX);
   
   SetIndexBuffer(5,buf_MA,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,buf_SAR,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,buf_stdDev,INDICATOR_CALCULATIONS);   
   
   ArrayInitialize(buf_MA, EMPTY_VALUE);
   ArrayInitialize(buf_SAR, EMPTY_VALUE);
   ArrayInitialize(buf_stdDev, EMPTY_VALUE);
   
   
   handle=iMA(Symbol(),PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   hSAR = iSAR(NULL,PERIOD_CURRENT,0.02,0.2);
   hstdDev=iStdDev(NULL,PERIOD_CURRENT,15,0,MODE_EMA,PRICE_CLOSE);
   
      
   if (handle==INVALID_HANDLE)
   {
        PrintFormat("Falha ao criar o manipulador do indicador iMA para o símbolo %s/%s, código de erro %d",
                  Symbol(), EnumToString(PERIOD_CURRENT), GetLastError());
        return(INIT_FAILED);
   }
   
   if (hSAR == INVALID_HANDLE) {
      PrintFormat("Failed to create handle of the iSAR indicator for the symbol %s, error code %d",
                  "APFTrend",
                  GetLastError());
      return(INIT_FAILED);   
   }
   
   if(hstdDev==INVALID_HANDLE) {
      //--- tell about the failure and output the error code
      PrintFormat("Failed to create handle of the iStdDev indicator for the symbol %s, error code %d",
                  "APFTrend",
                  GetLastError());
      //--- the indicator is stopped early
      return(INIT_FAILED);
   }


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

    //--- Primeiro nível  do indicador
    // - cores: bisque: 0 (neutro); verde:1 (T. Alta); vermelho:2 (T. Baixa)
    int close_trades=0;                                                                 // Se close_trades 1, não permite abertura de novas operações
    int start=0,values_to_copy=rates_total;
    int force_trade=0;

    // Variáveis para controle dos trades
    static int bars_calculated=0;                                                   // nro de barras calculadas
    static int gain_ct=0;                                                                // nro de trades com ganho no dia
    static double trade_gain=0,trade_maxgain=0,stop_gain=0;         // pontos obtidos no trade, ganho máximo até o momento e valor de saída do trade (stopgain)
    static double trade_sum=0,gain_total=0;                                   // somatório de pontos no dia (diário) e somatório de pontos desde o início da apuração (total)
    static int first_bar=0;

    MqlDateTime date_candle;

    // Getting the candle records;    
    int calculated=BarsCalculated(hSAR);
    if(calculated<=0) {
       PrintFormat("BarsCalculated() retornando %d, código de erro %d",calculated,GetLastError());
       return(0);
    }
   
    //--- Obtendo o número de valores necessários para o indicador 
    if (prev_calculated==0 || calculated!=bars_calculated || rates_total>prev_calculated+1) {
        if(calculated>rates_total) values_to_copy=rates_total;
        else                       values_to_copy=calculated;
    }
    else values_to_copy=(rates_total-prev_calculated)+1;

    //--- Variáveis de inicialização (start identifica a primeira barra que será processada)
    if (prev_calculated>0) start=rates_total-1;
    else {
       // primeira chamada (quando prev_calculated for zero)
       start=0;             // calcular a partir de 0
       wait=3;              // colocar os três primeiros candles em espera
       gain_total=0;      // estima o ganho total no dia
    }


    // Copiar o valor dos indicadores MA e SAR para buf_MA e buf_SAR
    // - buf_MA: preços da média móvel
    // - buf_SAR: preços do parabólico SAR
    // - buf_stdDev: desvio padrão
    if(!FillArrayFromBuffer(buf_MA,0,handle,values_to_copy)) return(0);
    if(!FillArrayFromBuffer(buf_SAR,0,hSAR,values_to_copy)) return(0);
    if(!FillArrayFromBuffer(buf_stdDev,0,hstdDev,values_to_copy)) return(0);

    for (int i=start; i<rates_total; i++) {
        HighBuf[i]=high[i];
        CloseBuf[i]=close[i];
        OpenBuf[i]=open[i];
        LowBuf[i]=low[i];

        // Compara o dia da semana (aguarda 3 candles a cada novo dia)
        // - O dia da semana atual é armazenado em dweek_now
        TimeToStruct(time[i],date_candle);
        dweek_now = date_candle.day;

        // Reinicia valores padrão no início do dia
        if (dweek_now != dweek_last) {
             wait=3;
             first_bar=i;
             last_index=i;

             gain_ct=0;
             bars_trade=0;
             trade_ct=0;
             trade_sum=0;         
             trade_open=0;
             trade_gain=0;
             trade_maxgain=0;

             close_trades=0;
             dweek_last=dweek_now;
          }
          else if ((date_candle.hour>=17 && date_candle.min>30)) close_trades=1; // Não operar após 17:30h

         // Controle de risco para novas aberturas de posição - por isto !trade_open ou trade_open==0
         if (!trade_open){
            // Critérios principais e globais
            if (trade_sum>20) close_trades=1;                                 // Encerra ao atingir 20 pts
            else if (trade_ct>max_daytrades-1) close_trades=1;        // Encerra ao atingir o limite diário de trades
            else if (trade_sum<=max_tradeloss) close_trades=1;      // Encerra ao atingir o prejuízo diário máximo
            // Critérios a partir de 3 pts
            else if (trade_ct>=3) {
               if (trade_ct>fail_trades-1 && gain_ct<1) close_trades=1;
               else if (trade_ct>gain_ct && trade_sum>=5) close_trades=1;
               else if (trade_ct==3 && gain_ct==3) close_trades=1;
            }
         }


         if (wait) {
            // Ignore operações
            if (wait>0 && (i!=last_index || (wait==3 && !prev_calculated))) wait--;
            buf_color_line[i]=0;
         }
         else {
             // Processa operações possíveis

             int k=i;
             if (!trade_open) k=i-1;

             // Preços para obtenção do pavio
             double aux_low=MathMin(open[k],close[k]);
             double aux_high=MathMax(open[k],close[k]);


             // Identificação da barra
             bool CANDLE_0          = (open[k]-close[k] == 0);
             bool CANDLE_UP       = (close[k]>open[k] && close[k]-open[k]>=1);
             bool CANDLE_DOWN  = (close[k]<open[k] && open[k]-close[k]>=1);

             // Deslocamento dos preços pela média dos preços das últimas três barras
             // - Para saber se está crescente ou decrescente
             bool MED_UP             = ((open[k]+close[k])/2 >= (open[k-1]+close[k-1])/2 && (open[k-1]+close[k-1])/2 > (open[k-2]+close[k-2])/2);
             bool MED_DOWN       = ((open[k]+close[k])/2 <= (open[k-1]+close[k-1])/2 && (open[k-1]+close[k-1])/2 < (open[k-2]+close[k-2])/2);             

             // Valida se o volume real é crescente
             bool VOLUME_UP   = (volume[k]>volume[k-1]+(volume[k-1]/3));

       
             //--- Verifica se existe um trade em aberto (trade_open):
             // 1. Caso não exista operação em aberto, verifica se a próxima barra está prestes a ser desenha e libera o processamento (isNewBar)
             // 2. Caso exista, verifica a possibilidade de fechar a posição (desviará para o bloco "else")
             if (!trade_open && !close_trades) { 
                 // Código para abertura de posição
                 if (isNewBar(time[i], 1, prev_calculated)==true) {
                    trade_dir=0;
                    bars_trade=0;
                    force_trade=0;
                    buf_color_line[i]=0;

                    //--- Defina aqui os critérios para abertura de posição
                    // 1. Opera em relação a posição do preço
                    // 2. Buscamos a tendência comparando buf_MA atual com anterior
                    if (buf_MA[k]>buf_MA[k-1]  && low[k]>buf_MA[k]) trade_dir=1;
                    else if (buf_MA[k]<buf_MA[k-1] && high[k]<buf_MA[k]) trade_dir=2;
                    
                    // 2. Opera em rompimentos expressivos da média móvel
                    if (VOLUME_UP) {
                       if (low[k]>buf_SAR[k] && open[k]<buf_MA[k]) {
                          if (close[k]-buf_MA[k]>2) trade_dir=1;
                          else if (buf_SAR[k-1]>high[k-1] && buf_MA[k]>buf_MA[k-1] && buf_MA[k-1]>buf_MA[k-2]) trade_dir=1;
                          force_trade=1;
                       }
                       else if (high[k]<buf_SAR[k] && open[k]>buf_MA[k]) {
                          if (buf_MA[k]-close[k]>2) trade_dir=2;
                          else if (low[k-1]>buf_SAR[k-1] && buf_MA[k]<buf_MA[k-1] && buf_MA[k-1]<buf_MA[k-2])  trade_dir=2;
                          force_trade=1;
                       }
                    }
                    //---

                    //--- Revisão para abertura de posição (confirmação)
                    // 1. Confirmar se operação de Long (trade_dir 1) é segura
                    if (trade_dir==1) {
                       // - Retorne para zero condições não desejadas
                       if (CANDLE_DOWN) trade_dir=0;  // Se o candle for de baixa, abandone a operação (volte trade_dir para 0)
                       else if (MED_DOWN && (high[k]<=buf_SAR[k] || trade_ct>1)) trade_dir=0;   // Operação comprada com média decrescente
                       else if (open[i]-buf_MA[i]>5) trade_dir=0;  // Se a distância do preço de abertura e a média móvel for maior que 5 pts, ignore
                       else if (i-first_bar<5 && high[i-1]-open[i]>2) trade_dir=0;
                       else if (high[i-1]-open[i]>4 && volume[i-1]>volume[i-2]) trade_dir=0;
                       else if (!force_trade && open[i]-buf_MA[i]>2 && high[k]-aux_high>=3) trade_dir=0;
                    }
                    // 2. Confirmar operação de Short (trade_dir 2) é segura
                    else if (trade_dir==2) {
                       // - Retorne para zero condições não desejadas
                       if (CANDLE_UP) trade_dir=0;  // Se o candle for de alta, abandone a operação (volte trade_dir para 0)
                       else if (MED_UP && (low[k]>=buf_SAR[k] || trade_ct>1)) trade_dir=0;  // Operação vendida com média crescente
                       else if (buf_MA[i]-open[i]>5 && buf_stdDev[i]<5) trade_dir=0;  // Se a distância do preço de abertura e a média móvel for maior que 5 pts, ignore
                       else if (i-first_bar<5 && open[i]-low[i-1]>2) trade_dir=0;
                       else if (open[i]-low[i-1]>=4 && volume[i-1]>volume[i-2]) trade_dir=0;
                       else if (!force_trade && buf_MA[i]-open[i]>2 && aux_low-low[k]>=3) trade_dir=0;
                    }
                    //---

                    //--- Testes globais (tanto para operações de Long como Short)
                    // 1. Se fechamento for igual a abertura e com volume inferior, abandone a operação
                    // 2. Ignora quando o desvio padrão foi baixo
                    // 3. Ignora a operação caso o corpo do candle tenha mais de 14 pts
                    if (CANDLE_0 && volume[k]<volume[k-1]) trade_dir=0;
                    else if (buf_stdDev[k]<=4 && buf_stdDev[k-1]-buf_stdDev[k]>0.5) trade_dir=0;
                    else if (MathAbs(open[k]-close[k])>14) trade_dir=0;

                    // Ignore operações com corpo superior a 10pts antes de 9:20h
                    else if (MathAbs(open[k]-close[k])>10 && date_candle.hour <= 9 && date_candle.min <= 20) trade_dir=0;

                    // Ignore quando a barra anterior apresentar abertura igual ao fechamento com baixo volume
                    if (open[k]==close[k] && volume[k]<=volume[k-1]) trade_dir=0;
                    else if (buf_color_line[k-1]>0 && buf_stdDev[k]<3) trade_dir=0;

                    // Se trade_dir for maior que 0, abre a posição e define as condições da operação
                    if (trade_dir>0) {
                       buf_color_line[i]=trade_dir;  // Abre posição setando o valor de trade_dir
                       trade_gain=0;                     // Inicializa trade_gain com 0
                       trade_maxgain=0;
                       trade_open=close[i];
                       trade_ct++;
                       bars_trade=1;

                       if (k==i-1) {
                          trade_open=open[i];
                          if (trade_dir>1) stop_gain=open[i]+5;
                          else stop_gain=open[i]-5;
                       }
                       else {
                          trade_open=close[i];
                          if (trade_dir>1) stop_gain=close[i]+5;
                          else stop_gain=close[i]-5;
                       }               
                    }
                }
             }
             else {
                 // Código para fechamento de posição
                 
                 // atualiza buf_color_line pelo último valor de trade_dir
                 buf_color_line[i]=trade_dir;
                    
                 double tgain=0;                       // armazenará o ganho no instante atual (inicializa em 0)

                 if (trade_dir==1) {                     // valida ganho no Long - trade_dir representa a direção do trade (1=long e 2=short)
                    tgain=high[i]-trade_open;       // ganho atual no long (compra)
                    if (tgain>trade_maxgain) {      // atualiza o valor de trade_maxgain (ganho máximo no trade)
                       if (tgain>5) stop_gain=trade_open+(trade_maxgain/2);
                       trade_maxgain=tgain;         // ganho máximo no long (compra) do trade aberto
                    }
                    
                 }
                 else if (trade_dir==2) {              // valida o ganho no Short - trade_dir representa a direção do trade (1=long e 2=short)
                    tgain=trade_open-low[i];        // ganho atual no short (venda)
                    if (tgain>trade_maxgain) {      // atualiza o valor de trade_maxgain (ganho máximo no trade)
                       if (tgain>5) stop_gain=trade_open-(trade_maxgain/2);
                       trade_maxgain=tgain;         // ganho máximo no short (venda) do trade aberto
                    }

                 }

                 if ((isNewBar(time[i], 2, prev_calculated)==true || close_trades) && buf_color_line[i]>0) {
                    // - verifica condições de fechamento de posição comprada (trade_dir=1, representa Long)
                    if (trade_dir==1 && buf_color_line[i-1]==1) {
                       if (high[i]>buf_MA[i] && low[i]<buf_MA[i] && tgain<2) trade_dir=0;
                       else if (buf_MA[i]-close[i]>1 && (open[i-1]>buf_MA[i] || MED_DOWN)) trade_dir=0;
                       else if (close[i]<stop_gain && trade_maxgain>5 && (bars_trade>6 || (bars_trade>4 && tgain<=1.5))) trade_dir=0;
                      
                       else if (trade_maxgain>15) {
                           if (trade_maxgain>40 || (trade_maxgain>30 && tgain<=20)) {
                              if (open[i]-close[i]>10) trade_dir=0;
                              else if ((tgain*100)/trade_maxgain<62) trade_dir=0;
                           }
                           else if (tgain<=5) trade_dir=0;
                       }

                    }

                    // - verifica condições de fechamento de posições vendidas (trade_dir=2, representa Short)
                    else if (trade_dir==2 && buf_color_line[i-1]==2) {
                       if (high[i]>buf_MA[i] && low[i]<buf_MA[i] && tgain<2) trade_dir=0;
                       else if (close[i]-buf_MA[i]>1 && (buf_MA[i]>open[i-1] || MED_UP)) trade_dir=0;
                       else if (close[i]>stop_gain && trade_maxgain>5 && (bars_trade>6 || (bars_trade>4 && tgain<=1.5))) trade_dir=0;
                       else if (trade_maxgain>15) {
                          if (trade_maxgain>40 || (trade_maxgain>30 && tgain<=20)) {
                             if (close[i]-open[i]>10) trade_dir=0;
                             else if ((tgain*100)/trade_maxgain<62) trade_dir=0;
                          }
                          else if (tgain<=5) trade_dir=0;
                       }
                       
                    }

                   // 1. Fecha posição depois de 5 barras sem ganho superior a 2 pts
                   // 2. Atualiza buf_color_line pelo valor de trade_dir
                   if (close_trades) trade_dir=0;
                   else if (bars_trade>5 && trade_maxgain<2) trade_dir=0;
                   buf_color_line[i]=trade_dir;


                   //--- Calcula o ganho e encerra a operação
                   if (trade_dir==0 && buf_color_line[i-1]>0) {
                      double last_tradesum = trade_sum;
               
                      if (buf_color_line[i-1]==1) trade_gain=close[i]-trade_open;
                      else trade_gain=trade_open-close[i];

                      //  Calcula trades vencedores por dia
                      if (trade_gain>0) gain_ct++;

                      // Soma e exibe os resultados (se autorizado)
                      trade_sum+=trade_gain;
                      gain_total+=trade_gain;
                      if (Trade_Total) printf("%s Trade %u sum (%u): %f (Total %f)", Symbol(), trade_ct, dweek_now, trade_sum, gain_total);
                      else if (Trade_Sum) printf("%s Trade %u sum (%u): %f", Symbol(), trade_ct, dweek_now, trade_sum);

                      // Encerra os trades no dia caso o resultado seja negativo em 5 tentativas
                      if (last_tradesum < 0 && trade_sum >= 5) close_trades=1;

                      // Encerra os trades no dia caso a primeira operação supere 15 pts
                      if (trade_ct==1 && trade_gain>=15) close_trades=1;

                      // Reseta os contadores
                      bars_trade=0;
                      trade_open=0;
                      trade_gain=0;
                      trade_dir=0;
                   }

                 } // encerramento isNewBar
             } // encerramento do bloco else (tenta fechar o trade)

         } // encerramento da verificação de operações possíveis (depois de wait 3)
 
         last_index=i;
    } // fim loop (for)
     
    bars_calculated = calculated;
//--- return value of prev_calculated for next call
   return(rates_total);
  }
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Returns true if a new bar has appeared for a symbol/period pair  |
//+------------------------------------------------------------------+
bool isNewBar(const datetime lastbar_time, const int op_type, const int prev_calc)
  {
//--- memorize the time of opening of the last bar in the static variable
   static datetime last_time=0;
   static datetime init_time=0;
   
   datetime init_auxtime=TimeCurrent();

   int limit_time=0;
   long time_match=0;
//   MqlDateTime ldate_candle;
//   TimeToStruct(lastbar_time,ldate_candle);
   
   limit_time=300;
   time_match=(limit_time-(init_auxtime-init_time));
   if (time_match<0) time_match=0;
   
   string label_name1="Seconds", label_text="Seconds... "+(string) (long)time_match;
   ObjectDelete(0, label_name1);
   ObjectCreate(0, label_name1, OBJ_LABEL, 0, 0, 0);
   //ObjectSetInteger(0,label_name1,OBJPROP_XDISTANCE,960);
   ObjectSetInteger(0,label_name1,OBJPROP_XDISTANCE,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0)-100);
   ObjectSetInteger(0,label_name1,OBJPROP_YDISTANCE,30);
   ObjectSetInteger(0,label_name1,OBJPROP_COLOR,YellowGreen);
   ObjectSetString(0,label_name1,OBJPROP_TEXT,label_text);
   
//--- if it is the first call of the function or new bar
   if (last_time==0 || init_time==0 || last_time!=lastbar_time) {
      last_time=lastbar_time;
      init_time=init_auxtime;
      if (last_time==0) return(false);
      if (prev_calc==0 || op_type==1) return(true);
      return(false);
   }

   if (op_type==2 && time_match<=2) return(true);
   
//--- if we passed to this line, then the bar is not new; return false
   return(false);
  }


//+------------------------------------------------------------------+
//| Filling indicator buffers from the MA indicator                  |
//+------------------------------------------------------------------+
bool FillArrayFromBuffer(double &values[],   // indicator buffer
                         int shift,          // shift
                         int ind_handle,     // handle of the indicator
                         int amount          // number of copied values
                         )
  {
   //--- reset error code
   ResetLastError();
   //--- fill a part of the Buffer array with values from the indicator buffer that has 0 index
   if(CopyBuffer(ind_handle,0,-shift,amount,values)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iMA indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(false);
     }
   //--- everything is fine
   return(true);
  }
  
//+------------------------------------------------------------------+
//| Indicator deinitialization function                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- clear the chart after deleting the indicator
   IndicatorRelease(handle);
   IndicatorRelease(hSAR);
  }
//+------------------------------------------------------------------+
