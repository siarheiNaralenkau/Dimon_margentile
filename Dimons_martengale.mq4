#define LOTS_LIST_SIZE 15

extern double stopLossDelta = 10;
extern double takeProfitDelta = 20;
extern double initialLot = 0.1;
extern double maxLot = 100.0;

extern bool lotsGeom = true;
extern bool lotsFibo = false;

int lotsInList;

// ���������� ��� �����.
int log_handle = -1;

// ���������� ��� ������������ ������� �� ������� ��� �������, � ����������� �� ���������� ���� ������.
int completedOrders = 0;
// ����� ��������� � ������ ������ ������.
int curOrderTicket;

// ��� ������� � �������� �������� � ������� �����(�������/�������).
int orderType;

// ���� ���������� ���������.
bool tradeStarted = false;

// ���������� �������� ������� �� ���������� ����.
int preOrdersTotal = 0;

int slippage = 2;
int errorCode = 0;

double price;
double stopLoss;
double takeProfit;
double volume;   
string message;

bool advisorAvailable = true;

// ������ �����.
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
   
   //---- ���������� �������� ��������� � ����� �����
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
    
   //---- ���������� ���������� ���� �� ����
   FileFlush( log_handle );
}

/*
   ������� �������� ����� ���������� �������� ������� �� �������� ����.
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
   ������� ����������, �� ������� ��� �� ������� ��������� �����.
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

// ������� �������� ��� �������� ���������� ������(1 - stopLoss, 2 - takeProfit).
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

// ������� �������� ��������� ������������� ���� ������.
string orderTypeToString(int orderType) {
   string orderTypeString;
   if(orderType == OP_SELL) {
      orderTypeString = "�� �������";
   } else {
      orderTypeString = "�� �������";
   }
   return (orderTypeString);
}

// �������������� ������ �����.
int initLotsList() {   
   double nextLotSize;          
   if(lotsGeom) {      
      lotsList[0] = initialLot;
      lotsList[1] = initialLot*2;
      lotsList[2] = initialLot*3;
      lotsList[3] = initialLot*4;      
      Alert("������������ ����� ����: " + maxLot + " ������� ����� ����: " + lotsList[3]);
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
   ������� ��������� ��������� �����(� ����� 0.01)
*/
int openInitialOrder() {        
   // ����������, �� ������� ��� ������� ��������� �����.
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
      message = "����� " + orderTypeToString(orderType) + " " + Symbol() + " �� ���� " + price + " ���� ����: " + stopLoss + " ���� ������: " + takeProfit + " �����: " + volume + " ������ " + errorCode;
      log(message);
      Alert(message);   
   } else {
      tradeStarted = true;
      preOrdersTotal = 1;
      message = "������� ������ " + orderTypeToString(orderType) + " " + Symbol() + " �� ���� " + price + " ���� ����: " + stopLoss + " ���� ������: " + takeProfit + " �����: " + volume;   
      log(message);  
      Alert(message);            
   }           
      
   return(0);
}

// ������� ��� �������� ������ ������.
void openNewOrder() {                     
   // �������� ���������� � �������� ������ �� ��� ������.   
   int closeType = getCloseType();   
         
   // ���� ������ ��������� �� StopLoss - ��������� ����� ���������� �� ������ ������ � ��� �� �����������
   if(closeType == 1) {
      completedOrders++;
      
      // ���� ����� � ������������ ����� ��� ���������� - �������� � ������.
      if(completedOrders == lotsInList) {
         completedOrders = 0;
         orderType = getInitialOrderType();
         Alert("������� ������ � ������������ �������!");
         log("������� ������ � ������������ �������!");
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
         message = "����� " + orderTypeToString(orderType) + " " + Symbol() + " �� ���� " + price + " ���� ����: " + stopLoss + " ���� ������: " + takeProfit + " �����: " + volume + " ������ " + errorCode;
         log(message);   
         Alert(message);
         while(curOrderTicket == -1) {
            openNewOrder();
         }
      } else {
         tradeStarted = true;
         preOrdersTotal = 1;
         message = "������� ������ " + orderTypeToString(orderType) + " " + Symbol() + " �� ���� " + price + " ���� ����: " + stopLoss + " ���� ������: " + takeProfit + " �����: " + volume;   
         log(message);  
         Alert(message);            
      }                  
   }
   // ���� �� �� TakeProfit - �������� ���� � ������, � ����������� ������. 
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
   log("���-���� ������ �������, ������� ����� ������..."); 
   Alert("����� �������������� ������ �����");
   initLotsList();   
   Alert("����� ������������� ������ �����");
   
   int curCurrencyOrders = getPairOrdersCount();              
   if(curCurrencyOrders > 0) {
      Alert("�������� ������� �� ����: " + curCurrencyOrders + ". �������� ��� ������ �� �������� ���� ����� ������������ ���������!");
      advisorAvailable = false;
      return (-1);
   } else {
      Alert("�������� ���������!");      
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
         
      if(!tradeStarted) { // ���� ��� �������� �������(��� ��������� �������� �� TakeProfit) - ��������� ����� ����� ����������� �������.            
         openInitialOrder();            
      } else if(preOrdersTotal > opennedOrders) { // ����� - ��������� ��������� �����(��� ����� �� ���������� ����� ���������).     
         openNewOrder();            
      }
   }
   return(0);
}