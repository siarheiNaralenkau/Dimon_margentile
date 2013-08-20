#define LOTS_LIST_SIZE 15

extern double stopLossDelta = 10;
extern double takeProfitDelta = 20;
extern double initialLot = 0.1;
extern double maxLot = 100.0;

extern bool lotsGeom = true;
extern bool lotsFibo = false;

int lotsInList;

// Дескриптор лог файла.
int log_handle = -1;

// Количество уже отработавших ордеров по покупке или продаже, в зависимости от начального типа сделки.
int completedOrders = 0;
// Номер открытого в данный момент ордера.
int curOrderTicket;

// Тип ордеров с которыми работаем в текущем цикле(покупка/продажа).
int orderType;

// Флаг активности советника.
bool tradeStarted = false;

// Количество открытых позиций на предыдущем тике.
int preOrdersTotal = 0;

int slippage = 2;
int errorCode = 0;

double price;
double stopLoss;
double takeProfit;
double volume;   
string message;

bool advisorAvailable = true;

// Список лотов.
double lotsList[LOTS_LIST_SIZE];

void log_open(string ExpertName = "Expert") {   
   string log_name = "logs_" + ExpertName + "_" + Symbol() + "_" + TimeToStr(LocalTime(),TIME_DATE) + ".txt";
   // Alert(log_name);
   log_handle = FileOpen(log_name, FILE_READ|FILE_WRITE, " ");
   if( log_handle < 0 )
   {      
      Alert("Error: " + GetLastError() );
      return(-1);
   }
}

void log_close()
{
   if( log_handle > 0 ) 
      FileClose( log_handle );
}

void log(string text) {
   int _GetLastError = 0;
   if(log_handle < 0) {
      Alert("Log write error! Text: " + text);
      return (-1);
   }
   
   //---- Перемещаем файловый указатель в конец файла
   if( !FileSeek ( log_handle, 0, SEEK_END ) )
   {
      _GetLastError = GetLastError();
      Alert( "FileSeek - Error #" + _GetLastError);            
      return(-1);
   }
   
   if(text != "\n" && text != "\r\n") {
         text = StringConcatenate(TimeToStr( LocalTime(), TIME_SECONDS), " - - - ", text );
   }
   
   if(FileWrite(log_handle, text) < 0)
   {
      _GetLastError = GetLastError();
      Alert("FileWrite - Error #" + _GetLastError );
      return(-1);
   }
    
   //---- Сбрасываем записанный тест на диск
   FileFlush( log_handle );
}

/*
   Функция получает общее количество открытых ордеров по валютной паре.
*/
int getPairOrdersCount() {
   int ordersCount = OrdersTotal();
   int curCurrencyOrders = 0;
   for(int i = ordersCount-1; i >= 0; i--) {
      bool orderSelectable = OrderSelect(i, SELECT_BY_POS);
      if(!orderSelectable) {
         continue;
      }
      
      if(OrderSymbol() == Symbol()) {
         curCurrencyOrders = curCurrencyOrders+1;
      }
   }
   return (curCurrencyOrders);   
}

/*
   Функция определяет, на покупку или на продажу открывать ордер.
*/
int getInitialOrderType() {
   int orderType;
   MathSrand(TimeLocal());
   int rNum = MathRand();
   if(rNum > 16384) {
      orderType = OP_BUY;
   } else {
      orderType = OP_SELL;
   }
   return (orderType);   
}

// Функция получает код закрытия предыдущей сделки(1 - stopLoss, 2 - takeProfit).
int getCloseType() {
   int closeType = 0;
   OrderSelect(curOrderTicket, SELECT_BY_TICKET);
   if ( StringFind( OrderComment(), "[sl]" ) >= 0 ) { 
      closeType = 1;
   } else if ( StringFind( OrderComment(), "[tp]" ) >= 0 ) {
      closeType = 2;
   }
   return (closeType);
}

// Функция получает строковое представление типа ордера.
string orderTypeToString(int orderType) {
   string orderTypeString;
   if(orderType == OP_SELL) {
      orderTypeString = "на продажу";
   } else {
      orderTypeString = "на покупку";
   }
   return (orderTypeString);
}

// Инициализируем массив лотов.
int initLotsList() {   
   double nextLotSize;          
   if(lotsGeom) {      
      lotsList[0] = initialLot;
      lotsList[1] = initialLot*2;
      lotsList[2] = initialLot*3;
      lotsList[3] = initialLot*4;      
      Alert("Максимальный объем лота: " + maxLot + " Текущий объем лота: " + lotsList[3]);
      for(int i = 4; i < LOTS_LIST_SIZE; i++) {
         nextLotSize = lotsList[i-1]*2;
         if(nextLotSize > maxLot) {
            lotsList[i] = maxLot;
            lotsInList = i+1;        
            break;
         } else {
            lotsList[i] = nextLotSize;
         }
      }      
   } else if(lotsFibo) {      
      lotsList[0] = initialLot;
      lotsList[1] = initialLot*2;      
      for(int k = 2; k < LOTS_LIST_SIZE; k++) {
         nextLotSize = lotsList[k-1] + lotsList[k-2];  
         if(nextLotSize > maxLot) {
            lotsList[k] = maxLot;
            lotsInList = k+1;        
            break;              
         } else {                       
            lotsList[k] = nextLotSize;
         }
      }      
   }
   
   string lotsListString = "";
   for(int j = 0; j < lotsInList; j++) {
      lotsListString = lotsListString + lotsList[j] + ",";
   }
   log(lotsListString);
   Alert(lotsListString);
   
   return(lotsInList);
}

/*
   Функция открывает начальный ордер(с лотом 0.01)
*/
int openInitialOrder() {        
   // Определяем, на покупку или продажу открывать ордер.
   volume = lotsList[completedOrders];
   orderType = getInitialOrderType();
   if(orderType == OP_SELL) {
      price = Bid;
      stopLoss = Bid + stopLossDelta*Point;
      takeProfit = Bid - takeProfitDelta*Point;         
   } else {
      price = Ask;
      stopLoss = Ask - stopLossDelta*Point;
      takeProfit = Ask + takeProfitDelta*Point;         
   }      
      
   curOrderTicket = OrderSend(Symbol(), orderType, volume, price, slippage, stopLoss, takeProfit);
   if(curOrderTicket == -1) {
      errorCode = GetLastError();
      message = "Ордер " + orderTypeToString(orderType) + " " + Symbol() + " по цене " + price + " стоп лосс: " + stopLoss + " тэйк профит: " + takeProfit + " объем: " + volume + " ОШИБКА " + errorCode;
      log(message);
      Alert(message);   
   } else {
      tradeStarted = true;
      preOrdersTotal = 1;
      message = "Открыта сделка " + orderTypeToString(orderType) + " " + Symbol() + " по цене " + price + " стоп лосс: " + stopLoss + " тэйк профит: " + takeProfit + " объем: " + volume;   
      log(message);  
      Alert(message);            
   }           
      
   return(0);
}

// Функция для открытия нового ордера.
void openNewOrder() {                     
   // Получаем информацию о закрытом ордере по его тикету.   
   int closeType = getCloseType();   
         
   // Если сделка закрылась по StopLoss - открываем ордер следующего по списку объема в том же направлении
   if(closeType == 1) {
      completedOrders++;
      
      // Если ордер с максимальным лотом уже открывался - начинаем с начала.
      if(completedOrders == lotsInList) {
         completedOrders = 0;
         orderType = getInitialOrderType();
         Alert("Закрыта сделка с максимальным объемом!");
         log("Закрыта сделка с максимальным объемом!");
      }
      
      volume = lotsList[completedOrders];
      if(orderType == OP_SELL) {
         price = Bid;
         stopLoss = Bid + stopLossDelta*Point;
         takeProfit = Bid - takeProfitDelta*Point;                              
      } else {
         price = Ask;
         stopLoss = Ask - stopLossDelta*Point;
         takeProfit = Ask + takeProfitDelta*Point;         
      }                        
      
      curOrderTicket = OrderSend(Symbol(), orderType, volume, price, slippage,stopLoss, takeProfit);       
      
      if(curOrderTicket == -1) {
         errorCode = GetLastError();
         message = "Ордер " + orderTypeToString(orderType) + " " + Symbol() + " по цене " + price + " стоп лосс: " + stopLoss + " тэйк профит: " + takeProfit + " объем: " + volume + " ОШИБКА " + errorCode;
         log(message);   
         Alert(message);
         while(curOrderTicket == -1) {
            openNewOrder();
         }
      } else {
         tradeStarted = true;
         preOrdersTotal = 1;
         message = "Открыта сделка " + orderTypeToString(orderType) + " " + Symbol() + " по цене " + price + " стоп лосс: " + stopLoss + " тэйк профит: " + takeProfit + " объем: " + volume;   
         log(message);  
         Alert(message);            
      }                  
   }
   // Если же по TakeProfit - начинаем цикл с начала, с наименьшего ордера. 
   else if(closeType == 2) {
      tradeStarted = false;
      completedOrders = 0;
      preOrdersTotal = 0;
      openInitialOrder();      
   }
}

int init()
{   
   log_open("log_test");
   log("Лог-файл открыт успешно, эксперт начал работу..."); 
   Alert("Перед инициализацией списка лотов");
   initLotsList();   
   Alert("После инициализации списка лотов");
   
   int curCurrencyOrders = getPairOrdersCount();              
   if(curCurrencyOrders > 0) {
      Alert("Открытых ордеров по паре: " + curCurrencyOrders + ". Закройте все ордеры по валютной паре перед подключением советника!");
      advisorAvailable = false;
      return (-1);
   } else {
      Alert("Советник подключен!");      
      return(0);
   }   
}

int deinit()
{
   log_close();   
   return(0);
}

int start()
{        
   if(advisorAvailable) {        
      int opennedOrders = getPairOrdersCount();       
         
      if(!tradeStarted) { // Если нет открытых ордеров(Или произошло закрытие по TakeProfit) - Открываем новый ордер минимальным объемом.            
         openInitialOrder();            
      } else if(preOrdersTotal > opennedOrders) { // Иначе - открываем удвоенный ордер(Или ордер по следующему числу фибоначчи).     
         openNewOrder();            
      }
   }
   return(0);
}