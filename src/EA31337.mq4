//+------------------------------------------------------------------+
//|                 EA31337 - multi-strategy advanced trading robot. |
//|                       Copyright 2016-2018, 31337 Investments Ltd |
//|                                       https://github.com/EA31337 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| EA includes.
//+------------------------------------------------------------------+

#include "include\EA31337\ea-mode.mqh"
#include "include\EA31337\ea-code-conf.mqh"
#include "include\EA31337\ea-defaults.mqh"
#include "include\EA31337\ea-expire.mqh"
#include "include\EA31337\ea-properties.mqh"
#include "include\EA31337\ea-enums.mqh"

#ifdef __advanced__
  #ifdef __rider__
    #include "include\EA31337\rider\ea-conf.mqh"
  #else
    #include "include\EA31337\advanced\ea-conf.mqh"
  #endif
#else
  #include "include\EA31337\lite\ea-conf.mqh"
#endif

//+------------------------------------------------------------------+
//| EA properties.
//+------------------------------------------------------------------+
#property version     ea_version
#property description ea_name
#property description ea_desc
#property link        ea_link
#property copyright   ea_copy
#property icon        "resources\\favicon.ico"
#property strict
//#property stacksize
//#property tester_file "trade_patterns.csv"    // File with the data to be read by an Expert Advisor.
//#property tester_indicator "smoothed_ma.ex4"  // File with a custom indicator specified in iCustom() as a variable.
//#property tester_library "MT4EA2DLL.dll" // Library file name from <terminal_data_folder>\MQL4\Libraries\ to be sent to a virtual server.

//+------------------------------------------------------------------+
//| Include public classes.
//+------------------------------------------------------------------+
// #include "include\EA31337-classes\Account.mqh"
#include "include\EA31337-classes\Array.mqh"
// #include "include\EA31337-classes\Chart.mqh"
#include "include\EA31337-classes\Condition.mqh"
#include "include\EA31337-classes\Convert.mqh"
#include "include\EA31337-classes\DateTime.mqh"
// #include "include\EA31337-classes\Draw.mqh"
#include "include\EA31337-classes\File.mqh"
#include "include\EA31337-classes\Indicator.mqh"
#include "include\EA31337-classes\Order.mqh"
#include "include\EA31337-classes\Orders.mqh"
#include "include\EA31337-classes\Market.mqh"
#include "include\EA31337-classes\Math.mqh"
#include "include\EA31337-classes\MD5.mqh"
#include "include\EA31337-classes\Misc.mqh"
#include "include\EA31337-classes\Msg.mqh"
#include "include\EA31337-classes\Report.mqh"
#include "include\EA31337-classes\Stats.mqh"
#include "include\EA31337-classes\Strategy.mqh"
//#include "include\EA31337-classes\Strategies.mqh"
#include "include\EA31337-classes\String.mqh"
#include "include\EA31337-classes\SummaryReport.mqh"
#include "include\EA31337-classes\Terminal.mqh"
#include "include\EA31337-classes\Tester.mqh"
#include "include\EA31337-classes\Tests.mqh"
#include "include\EA31337-classes\Ticker.mqh"
#include "include\EA31337-classes\Trade.mqh"
#ifdef __profiler__
#include "include\EA31337-classes\Profiler.mqh"
#endif
//#property tester_file "trade_patterns.csv"    // file with the data to be read by an Expert Advisor

//+------------------------------------------------------------------+
//| User input variables.
//+------------------------------------------------------------------+
extern string __EA_Parameters__ = "-- Input EA parameters for " + ea_name + " v" + ea_version + " --"; // >>> EA31337 <<<

#ifdef __advanced__ // Include default input settings based on the mode.
  #ifdef __rider__
    #include "include\EA31337\rider\ea-input.mqh"
  #else
    #include "include\EA31337\advanced\ea-input.mqh"
  #endif
#else
  #include "include\EA31337\lite\ea-input.mqh"
#endif

/*
 * Predefined constants:
 *   Point - The current symbol point value in the quote currency.
 *   Digits - Number of digits after decimal point for the current symbol prices.
 *   Bars - Number of bars in the current chart.
 */

/*
 * Notes:
 *   - __MQL4__  macro is defined when compiling *.mq4 file, __MQL5__ macro is defined when compiling *.mq5 one.
 */
//+------------------------------------------------------------------+

// Class variables.
Account *account;
Chart *chart;
Log *logger;
Market *market;
Stats *total_stats, *hourly_stats;
SummaryReport *summary_report; // For summary report.
Ticker *ticker; // For parsing ticks.
Terminal *terminal;
Trade *trade[FINAL_ENUM_TIMEFRAMES_INDEX];

// Market/session variables.
double pip_size, ea_lot_size;
double last_ask, last_bid;
uint order_freezelevel; // Order freeze level in points.
double curr_spread; // Broker current spread in pips.
double curr_trend; // Current trend.
double ea_risk_margin_per_order, ea_risk_margin_total; // Risk marigin in percent.
uint pts_per_pip; // Number points per pip.
int gmt_offset = 0; // Current difference between GMT time and the local computer time in seconds, taking into account switch to winter or summer time. Depends on the time settings of your computer.
// double total_sl, total_tp; // Total SL/TP points.

// Account variables.
string account_type;
double init_balance; // Initial account balance.
long init_spread; // Initial spread.

// State variables.
bool session_initiated = false;
bool session_active = false;

// Time-based variables.
// Bar time: initial, current and last one to check if bar has been changed since the last time.
datetime curr_bar_time;
datetime time_current = (int) EMPTY_VALUE;
int hour_of_day, day_of_week, day_of_month, day_of_year, month, year;
datetime last_order_time = 0, last_action_time = 0;
int last_history_check = 0; // Last ticket position processed.
datetime last_traded;

// Strategy variables.
int info[FINAL_STRATEGY_TYPE_ENTRY][FINAL_STRATEGY_INFO_ENTRY];
double conf[FINAL_STRATEGY_TYPE_ENTRY][FINAL_STRATEGY_VALUE_ENTRY], stats[FINAL_STRATEGY_TYPE_ENTRY][FINAL_STRATEGY_STAT_ENTRY];
int open_orders[FINAL_STRATEGY_TYPE_ENTRY], closed_orders[FINAL_STRATEGY_TYPE_ENTRY];
int signals[FINAL_STAT_PERIOD_TYPE_ENTRY][FINAL_STRATEGY_TYPE_ENTRY][FINAL_ENUM_TIMEFRAMES_INDEX][2]; // Count signals to buy and sell per period and strategy.
int tickets[200]; // List of tickets to process.
string sname[FINAL_STRATEGY_TYPE_ENTRY];
int worse_strategy[FINAL_STAT_PERIOD_TYPE_ENTRY], best_strategy[FINAL_ENUM_TIMEFRAMES_INDEX];

// EA variables.
bool ea_active = false; bool ea_expired = false;
double ea_risk_ratio; string rr_text; // Vars for calculation risk ratio.
double ea_margin_risk_level[3]; // For margin risk (all/buy/sell);
uint max_orders = 10, daily_orders; // Maximum orders available to open.
uint max_order_slippage; // Maximum price slippage for buy or sell orders (in points)
int err_code; // Error code.
string last_err, last_msg, last_debug, last_trace;
string ea_last_order;
double last_pip_change; // Last tick change in pips.
double last_close_profit = EMPTY;
// int last_trail_update = 0, last_indicators_update = 0, last_stats_update = 0;
int todo_queue[100][8];
datetime last_queue_process = 0;
uint total_orders = 0; // Number of total orders currently open.
double daily[FINAL_VALUE_TYPE_ENTRY], weekly[FINAL_VALUE_TYPE_ENTRY], monthly[FINAL_VALUE_TYPE_ENTRY];
double hourly_profit[367][24]; // Keep track of hourly profit.

// Used for writing the report file.
string log[];

// Condition and actions.
int acc_conditions[30][3];
string last_cname;

// Order queue.
long order_queue[100][FINAL_ORDER_QUEUE_ENTRY];

// For debugging purposes.
string stacktrace = "";
#define DEBUG_CHECKPOINT_RESET stacktrace = __FUNCTION__;
#define DEBUG_CHECKPOINT_ADD  stacktrace += ">" + __FUNCTION__ + ":" + (string) __LINE__;
#define DEBUG_CHECKPOINT_POP  stacktrace += "<";
#define DEBUG_STACK_PRINT  Print(stacktrace);
#define DEBUG_STACK_GET    stacktrace

// Indicator variables.
double iac[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double ad[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double adx[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_ADX_LINE_ENTRY];
double alligator[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_ALLIGATOR_LINE_ENTRY];
//double atr[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][MA_SLOW+1];
double awesome[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double bands[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_BANDS_LINE_ENTRY];
double bwmfi[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double bpower[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][ORDER_TYPE_SELL+1];
double cci[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double demarker[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double envelopes[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_LO_UP_LINE_ENTRY];
double iforce[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double fractals[H4][FINAL_ENUM_INDICATOR_INDEX][FINAL_LO_UP_LINE_ENTRY];
double gator[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_ALLIGATOR_LINE_ENTRY];
double ichimoku[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_ICHIMOKU_LINE_ENTRY];
double ma_fast[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX], ma_medium[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX], ma_slow[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double macd[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_SIGNAL_LINE_ENTRY];
double mfi[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
//double momentum[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][MA_SLOW+1];
double obv[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double osma[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double rsi[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX], rsi_stats[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_LO_UP_LINE_ENTRY];
double rvi[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_SIGNAL_LINE_ENTRY];
double sar[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX]; int sar_week[FINAL_ENUM_TIMEFRAMES_INDEX][7][2];
double stddev[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double stochastic[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX][FINAL_SIGNAL_LINE_ENTRY];
double wpr[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];
double zigzag[FINAL_ENUM_TIMEFRAMES_INDEX][FINAL_ENUM_INDICATOR_INDEX];

/*
 * TODO:
 *   - add trailing stops/profit for support/resistence,
 *   - daily higher highs and lower lows,
 *   - check risky dates and times,
 *   - check for risky patterns,
 *   - implement condition to close all strategy orders: when to trade, skip the day or week, etc.
 *   - implement SendFTP,
 *   - implement SendNotification,
 *   - send daily, weekly reports (SendMail),
 *   - check TesterStatistics(),
 *   - check ResourceCreate/ResourceSave to store dynamic parameters
 *   - consider to use Donchian Channel (ihighest/ilowest) for detecting s/r levels
 *   - convert `ma_fast`, `ma_medium`, `ma_slow` into one `ma` variable.
 *   - add RSI threshold param
 *   - trend calculated based on RSI
 *   - calculate support and resistance levels
 *   - calculate pivot levels
 *   - action to close the order after X hours when all orders of strategy are profitable
 *   - strategy flags: PP, S1-S3, R1-R3, trend
 */

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
  //#ifdef __trace__ PrintFormat("%s: Ask=%g/Bid=%g", __FUNCTION__, Ask, Bid); #endif
  if (!session_initiated) return;
  //#ifdef __profiler__ PROFILER_START #endif

  MqlTick _tick = market.GetTick();
  bool _tick_procesed = false;
  for (ENUM_TIMEFRAMES_INDEX tfi = 0; tfi < FINAL_ENUM_TIMEFRAMES_INDEX; tfi++) {
    if (Object::IsDynamic(trade[tfi]) && trade[tfi].Chart().IsValidTf()) {
      if (trade[tfi].Chart().IsNewBar()) {
        trade[tfi].Market().SetTick(_tick);
        ProcessBar(trade[tfi]);
        _tick_procesed = true;
      }
    }
  }
  if (_tick_procesed) {
    if (PrintLogOnChart) {
      DisplayInfoOnChart();
    }
    if (!terminal.IsOptimization()) {
      terminal.Logger().Flush(false);
    }
  }
  UpdateTicks();
  //#ifdef __profiler__ PROFILER_STOP #endif
} // end: OnTick()

/**
 * Process a new bar.
 */
void ProcessBar(Trade *_trade) {

  // Parse a tick.
  /*
  if (!ticker.Process(_trade.Chart(), TickProcessMethod)) {
    // Ignore a tick according to the method.
    return;
  }
  */

  /* @fixme: Disabled.
  // Check if we should ignore the tick based on the price change.
  if (last_pip_change < MinPipChangeToTrade) {
    if (last_bar_time == trade.GetBarTime(PERIOD_M1)) {
      return;
    }
  }
  else {
    last_bar_time = trade.GetBarTime(PERIOD_M1);
  }
  */
  if (!Object::IsDynamic(_trade)) {
    PrintFormat("%s: Error: Trade object not valid!", __FUNCTION_LINE__);
  }
  else if (!Object::IsDynamic(_trade.Chart())) {
    PrintFormat("%s: Error: Chart object not valid!", __FUNCTION_LINE__);
  }

  if (TradeAllowed()) {
    last_ask = market.GetLastAsk();
    last_bid = market.GetLastBid();
    last_pip_change = market.GetLastPriceChangeInPips();
    if (hour_of_day != DateTime::Hour()) {
      StartNewHour(_trade);
    }
    UpdateVariables();
    EA_Trade(_trade);
    UpdateOrders(_trade);
    UpdateStats();
  }

}

/**
 * Update ticks.
 */
void UpdateTicks() {
  if (!terminal.IsOptimization()) {
    // Update stats.
    if (RecordTicksToCSV) {
      total_stats.OnTick();
      hourly_stats.OnTick();
      ticker.Add(market.GetLastTick());
    }
  }
}

/**
 * Update existing opened orders.
 */
void UpdateOrders(Trade *_trade) {
  #ifdef __profiler__ PROFILER_START #endif
  if (total_orders > 0) {
    CheckOrders();
    UpdateTrailingStops(_trade);
    CheckAccConditions(_trade.Chart());
    TaskProcessList();
  }
  #ifdef __profiler__ PROFILER_STOP #endif
}

/**
 * Process orders.
 *
 * This is invoked after order being placed or each hour.
 */
void ProcessOrders() {
  UpdateMarginRiskLevel();
}

/**
 * Update margin risk level.
 */
void UpdateMarginRiskLevel() {
  if (RiskMarginTotal >= 0) {
    ea_margin_risk_level[ORDER_TYPE_BUY] = account.GetRiskMarginLevel(ORDER_TYPE_BUY); // Get current risk margin level for buy orders.
    ea_margin_risk_level[ORDER_TYPE_SELL] = account.GetRiskMarginLevel(ORDER_TYPE_SELL); // Get current risk margin level for sell orders.
    ea_margin_risk_level[2] = account.GetRiskMarginLevel(); // Get current risk margin level for all orders.
  }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
  string err;
  if (VerboseInfo) PrintFormat("%s v%s (%s) initializing...", ea_name, ea_version, ea_link);
  if (!session_initiated) {
    #ifdef __expire__ CheckExpireDate(); #endif
    err_code = CheckSettings();
    if (err_code < 0) {
      // Incorrect set of input parameters occured.
      Msg::ShowText(StringFormat("EA parameters are not valid, please correct (code: %d).", err_code), "Error", __FUNCTION__, __LINE__, VerboseErrors, true, true);
      ea_active = false;
      session_active = false;
      session_initiated = false;
      return (INIT_PARAMETERS_INCORRECT);
    }
    #ifdef __release__
    if (Terminal::IsRealtime() && account.GetLogin() <= 1) {
      // @todo: Fails when debugging.
      Msg::ShowText("EA requires on-line Terminal.", "Error", __FUNCTION__, __LINE__, VerboseErrors, true);
      ea_active = false;
      session_active = false;
      session_initiated = false;
      return (INIT_FAILED);
     }
     #endif
     session_initiated = true;
  }

  #ifdef __profiler__ PROFILER_SET_MIN(10) #endif
  #ifdef __profiler__ PROFILER_START #endif

  session_initiated &= InitClasses();
  session_initiated &= InitVariables();
  session_initiated &= InitStrategies();
  session_initiated &= InitializeConditions();
  session_initiated &= CheckHistory();

  #ifdef __advanced__
  if (SmartToggleComponent) ToggleComponent(SmartToggleComponent);
  #endif

  if (!Terminal::IsRealtime()) {
    // When testing, we need to simulate real MODE_STOPLEVEL = 30 (as it's in real account), in demo it's 0.
    // if (market_stoplevel == 0) market_stoplevel = DemoMarketStopLevel;
  }

  if (session_initiated) {
    session_active = true;
    ea_active = true;
    if (VerboseInfo) {
      string output = InitInfo(true);
      String::PrintText(output);
      Comment(output);
      ReportAdd(InitInfo());
    }
  }

  ChartRedraw();
  #ifdef __profiler__ PROFILER_STOP_PRINT #endif
  return (session_initiated ? INIT_SUCCEEDED : INIT_FAILED);
} // end: OnInit()

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  time_current = TimeCurrent();
  if (VerboseDebug) terminal.Logger().Debug(StringFormat("reason = %d", reason), __FUNCTION_LINE__);
  // Also: _UninitReason.
  if (VerboseInfo) terminal.Logger().Info(StringFormat("EA deinitializing, reason: %s (code: %s)", Terminal::GetUninitReasonText(reason), IntegerToString(reason)), __FUNCTION_LINE__);

  if (session_initiated) {
    if (!terminal.IsOptimization()) {
      // Show final account details.
      terminal.Logger().Info(GetSummaryText(), __FUNCTION_LINE__);

      #ifdef __profiler__ PROFILER_PRINT #endif

      // Save ticks if recorded.
      if (RecordTicksToCSV) {
        ticker.SaveToCSV();
      }

      if (WriteReport) {
        // if (reason == REASON_CHARTCHANGE)
        string filename;
        Chart *_chart = trade[chart.TfToIndex()].Chart();
        OHLC first_bar = _chart.LoadOHLC();
        summary_report.CalculateSummary();
        // @todo: Calculate average spread from stats[sid][AVG_SPREAD].
        filename = StringFormat(
            "%s-%.f%s-%s-%s-%dspread-%s-report.txt",
            market.GetSymbol(), summary_report.GetInitDeposit(), account.GetCurrency(),
            DateTime::TimeToStr(first_bar.time, TIME_DATE), DateTime::TimeToStr(_chart.iTime(), TIME_DATE),
            init_spread, chart.TfToString());
            // ea_name, _Symbol, summary.init_deposit, account.AccountCurrency(), init_spread, TimeToStr(time_current, TIME_DATE), Period());
            // ea_name, _Symbol, init_balance, account.AccountCurrency(), init_spread, TimeToStr(time_current, TIME_DATE|TIME_MINUTES), Period());
        string data = summary_report.GetReport();
        data += GetStatReport();
        data += GetStrategyReport();
        data += Array::ArrToString(log, "\n", "Report log:\n");
        Report::WriteReport(filename, data, VerboseInfo); // Todo: Add: Errors::GetUninitReasonText(reason)
        terminal.Logger().Info("Saved report as: " + filename, __FUNCTION__);
      }

    }

  }
  terminal.Logger().Flush(false);
  DeinitVars();
  // #ifdef _DEBUG
  // DEBUG("n=" + n + " : " +  DoubleToStrMorePrecision(val,19) );
  // DEBUG("CLOSEDEBUGFILE");
  // #endif
} // end: OnDeinit()

/**
 * Deinitialize global variables.
 */
void DeinitVars() {
  Object::Delete(account);
  Object::Delete(hourly_stats);
  Object::Delete(logger);
  Object::Delete(total_stats);
  Object::Delete(summary_report);
  Object::Delete(ticker);
  Object::Delete(terminal);
  Object::Delete(market);
  for (int tfi = 0; tfi < FINAL_ENUM_TIMEFRAMES_INDEX; tfi++) {
    Object::Delete(trade[tfi]);
  }
  #ifdef __profiler__ PROFILER_DEINIT #endif
}

/**
 * Test completion event handler.
 *
 * Returns calculated value that is used as the Custom max criterion in the genetic optimization of input parameters.
 *
 * @see: https://www.mql5.com/en/docs/basis/function/events
 */
/*
double OnTester() {
  if (ProfilingMinTime > 0) {
  }
}
*/

/**
 * Implements handler of the TesterPass event (MQL5 only).
 *
 * Invoked when a frame is received during EA optimization in the strategy tester.
 *
 * @see: https://www.mql5.com/en/docs/basis/function/events
 */
void OnTesterPass() {
  Print("Calling ", __FUNCTION__, ".");
  /*
  if (ProfilingMinTime > 0) {
    // Print("PROFILER: ", timers.ToString(0));
  }
  */
}

/**
 * Implements handler of the TesterInit event (MQL5 only).
 *
 * Invoked with the start of optimization in the strategy tester.
 *
 * @see: https://www.mql5.com/en/docs/basis/function/events
 */
void OnTesterInit() {
  //if (VerboseDebug)
  Print("Calling ", __FUNCTION__, ".");
  #ifdef __MQL5__
    // Specifies the use of input variable when optimizing: value, change step, initial and final values.
    // @see: https://www.mql5.com/en/docs/optimization_frames/parametersetrange
    //ParameterSetRange(LotSize, 0, 0.0, 0.01, 0.01, 0.1);
  #endif
}

/**
 * Implements handler of the TesterDeinit event (MQL5 only).
 *
 * Invoked after the end of optimization of an Expert Advisor in the strategy tester.
 *
 * @see: https://www.mql5.com/en/docs/basis/function/events
 */
void OnTesterDeinit() {
  //if (VerboseDebug)
  Print("Calling ", __FUNCTION__, ".");
}

// @todo: OnTradeTransaction (https://www.mql5.com/en/docs/basis/function/events).

// The Start event handler, which is automatically generated only for running scripts.
// FIXME: Doesn't seems to be called, however MT4 doesn't want to execute EA without it.
/** Should not be here. Breaks Compile @stephenc01
void start() {
  if (VerboseTrace) Print("Calling " + __FUNCTION__ + ".");
  if (VerboseInfo) Print(__FUNCTION__ + ": " + GetMarketTextDetails());
}
**/

/**
 * Print init variables and constants.
 */
string InitInfo(bool startup = false, string sep = "\n") {
  string extra = "";
  #ifdef __expire__ CheckExpireDate(); extra += StringFormat(" [expires on %s]", TimeToStr(ea_expire_date, TIME_DATE)); #endif
  string output = StringFormat("%s v%s by %s (%s)%s%s", ea_name, ea_version, ea_author, ea_link, extra, sep);
  output += "TERMINAL: " + terminal.ToString() + sep;
  output += "ACCOUNT: " + account.ToString() + sep;
  output += "SYMBOL: " + ((SymbolInfo *)market).ToString() + sep;
  output += "MARKET: " + market.ToString() + sep;
  for (ENUM_TIMEFRAMES_INDEX _tfi = 0; _tfi < FINAL_ENUM_TIMEFRAMES_INDEX; _tfi++) {
    if (Object::IsValid(trade[_tfi]) && trade[_tfi].Chart().IsValidTf()) {
      output += StringFormat("CHART: %s%s", trade[_tfi].Chart().ToString(), sep);
    }
    else {
      output += StringFormat("CHART: %s not active.%s", Chart::IndexToString(_tfi), sep);
    }
  }
  /*
  output += StringFormat("Contract specification for %s: Profit mode: %d, Margin mode: %d, Spread: %d pts, Trade tick size: %f, Point value: %f, Digits: %d, Trade stops level: %dpts, Trade contract size: %g%s",
      _Symbol,
      MarketInfo(_Symbol, MODE_PROFITCALCMODE),
      MarketInfo(_Symbol, MODE_MARGINCALCMODE),
      (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
      SymbolInfoDouble(_Symbol, SYMBOL_POINT),
      (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
      market.GetTradeStopsLevel(),
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
      sep);
      */
  // @todo: Move to SymbolInfo.
  output += StringFormat("Swap specification for %s: Mode: %d, Long/buy order value: %g, Short/sell order value: %g%s",
      _Symbol,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_MODE),
      SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG),
      SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT),
      sep);
  output += StringFormat("Calculated variables: Pip size: %g, EA lot size: %g, Points per pip: %d, Pip digits: %d, Volume digits: %d, Spread in pips: %.1f (%d pts), Stop Out Level: %.1f, Market gap: %d pts (%g pips)%s",
      market.GetPipSize(),
      NormalizeDouble(ea_lot_size, market.GetVolumeDigits()),
      pts_per_pip,
      market.GetPipDigits(),
      market.GetVolumeDigits(),
      market.GetSpreadInPips(),
      market.GetSpreadInPts(),
      account.GetAccountStopoutLevel(VerboseErrors),
      market.GetTradeDistanceInPts(),
      market.GetTradeDistanceInPips(),
      sep);
  output += StringFormat("EA params: Risk ratio: %g, Risk margin per order: %g%%, Risk margin in total: %g%%%s",
      ea_risk_ratio, ea_risk_margin_per_order, ea_risk_margin_total,
      sep);
  output += StringFormat("Strategies: Active strategies: %d of %d, Max orders: %d (per type: %d)%s",
      GetNoOfStrategies(),
      FINAL_STRATEGY_TYPE_ENTRY,
      max_orders,
      GetMaxOrdersPerType(),
      sep);
  output += Msg::ShowText(Chart::GetModellingQuality(), "Info", __FUNCTION__, __LINE__, VerboseInfo) + sep;
  output += Chart::ListTimeframes() + sep;
  output += StringFormat("Datetime: Hour of day: %d, Day of week: %d, Day of month: %d, Day of year: %d, Month: %d, Year: %d%s",
      hour_of_day, day_of_week, day_of_month, day_of_year, month, year, sep);
  output += GetAccountTextDetails() + sep;
  if (startup) {
    if (session_initiated && terminal.IsTradeAllowed()) {
      if (TradeAllowed()) {
        output += sep + "Trading is allowed, waiting for ticks...";
      } else {
        output += sep + "Trading is allowed, but there is some issue...";
        output += sep + last_err;
      }
    } else {
      output += sep + StringFormat("Error %d: Trading is not allowed for this symbol, please enable automated trading or check the settings!", __LINE__);
    }
  }
  return output;
}

/**
 * Main function to trade.
 */
bool EA_Trade(Trade *_trade) {
  DEBUG_CHECKPOINT_RESET
  #ifdef __profiler__ PROFILER_START #endif
  bool order_placed = false;
  ENUM_ORDER_TYPE _cmd = EMPTY;
  ENUM_TIMEFRAMES tf = _trade.Chart().GetTf();
  if (VerboseTrace) _trade.Logger().Trace(StringFormat("%s:%d: %s", __FUNCTION__, __LINE__, DateTime::TimeToStr(_trade.Chart().GetBarTime())));
  for (ENUM_STRATEGY_TYPE id = 0; id < FINAL_STRATEGY_TYPE_ENTRY; id++) {
    if (
      (ENUM_TIMEFRAMES) info[id][TIMEFRAME] == tf &&
      info[id][ACTIVE] &&
      !info[id][SUSPENDED]
    ) {
      // Note: When TradeWithTrend is set and we're against the trend, do not trade.
      if (TradeCondition(_trade, id, ORDER_TYPE_BUY)) {
        _cmd = ORDER_TYPE_BUY;
      } else if (TradeCondition(_trade, id, ORDER_TYPE_SELL)) {
        _cmd = ORDER_TYPE_SELL;
      } else {
        _cmd = EMPTY;
      }

      if (!DisableCloseConditions) {
        if (CheckMarketEvent(_trade.Chart(), ORDER_TYPE_BUY,  info[id][CLOSE_CONDITION])) CloseOrdersByType(ORDER_TYPE_SELL, id, R_OPPOSITE_SIGNAL, CloseConditionOnlyProfitable);
        if (CheckMarketEvent(_trade.Chart(), ORDER_TYPE_SELL, info[id][CLOSE_CONDITION])) CloseOrdersByType(ORDER_TYPE_BUY,  id, R_OPPOSITE_SIGNAL, CloseConditionOnlyProfitable);
      }

      if (info[id][OPEN_CONDITION1] != 0) {
        if (_cmd == ORDER_TYPE_BUY  && !CheckMarketCondition1(_trade.Chart(), ORDER_TYPE_BUY,  info[id][OPEN_CONDITION1])) _cmd = EMPTY;
        if (_cmd == ORDER_TYPE_SELL && !CheckMarketCondition1(_trade.Chart(), ORDER_TYPE_SELL, info[id][OPEN_CONDITION1])) _cmd = EMPTY;
      }
      if (Object::IsDynamic(trade[Chart::TfToIndex(TrendPeriod)]) && info[id][OPEN_CONDITION2] != 0) {
        if (_cmd == ORDER_TYPE_BUY  && CheckMarketCondition1(trade[Chart::TfToIndex(TrendPeriod)].Chart(), ORDER_TYPE_SELL, info[id][OPEN_CONDITION2], false)) _cmd = EMPTY;
        if (_cmd == ORDER_TYPE_SELL && CheckMarketCondition1(trade[Chart::TfToIndex(TrendPeriod)].Chart(), ORDER_TYPE_BUY,  info[id][OPEN_CONDITION2], false)) _cmd = EMPTY;
      }

      if (_cmd != EMPTY) {
        order_placed &= ExecuteOrder(_cmd, id);
        if (VerboseDebug) {
          _trade.Logger().Info(StringFormat("%s:%d: %s %s on %s at %s: %s",
            __FUNCTION__, __LINE__, sname[id],
            Chart::TfToString((ENUM_TIMEFRAMES) info[id][TIMEFRAME]),
            Order::OrderTypeToString(_cmd),
            DateTime::TimeToStr(TimeCurrent()),
            order_placed ? "SUCCESS" : "IGNORE"
          ));
        }
      }

    } // end: if
  } // end: for

  if (SmartQueueActive && !order_placed && total_orders <= max_orders) {
    order_placed &= OrderQueueProcess();
  }

  if (order_placed) {
    ProcessOrders();
  }

  last_traded = TimeCurrent();
  #ifdef __profiler__ PROFILER_STOP #endif
  return order_placed;
}

/**
 * Check if strategy is on trade conditionl.
 */
bool TradeCondition(Trade *_trade, ENUM_STRATEGY_TYPE sid = 0, ENUM_ORDER_TYPE cmd = NULL) {
  DEBUG_CHECKPOINT_ADD
  bool _result = false;
  #ifdef __profiler__ PROFILER_START #endif
  Chart *_chart = _trade.Chart();
  ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES) info[sid][TIMEFRAME];
  if (VerboseTrace) PrintFormat("%s:%d: %s (%s), cmd=%d", __FUNCTION__, __LINE__, sname[sid], EnumToString(tf), Order::OrderTypeToString(cmd));
  switch (sid) {
    case AC1: case AC5: case AC15: case AC30:                                 _result = Trade_AC(_chart, cmd); break;
    case AD1: case AD5: case AD15: case AD30:                                 _result = Trade_AD(_chart, cmd); break;
    case ADX1: case ADX5: case ADX15: case ADX30:                             _result = Trade_ADX(_chart, cmd); break;
    case ALLIGATOR1: case ALLIGATOR5: case ALLIGATOR15: case ALLIGATOR30:     _result = Trade_Alligator(_chart, cmd); break;
    case ATR1: case ATR5: case ATR15: case ATR30:                             _result = Trade_ATR(_chart, cmd); break;
    case AWESOME1: case AWESOME5: case AWESOME15: case AWESOME30:             _result = Trade_Awesome(_chart, cmd); break;
    case BANDS1: case BANDS5: case BANDS15: case BANDS30:                     _result = Trade_Bands(_chart, cmd); break;
    case BPOWER1: case BPOWER5: case BPOWER15: case BPOWER30:                 _result = Trade_BPower(_chart, cmd); break;
    case BWMFI1: case BWMFI5: case BWMFI15: case BWMFI30:                     _result = Trade_BWMFI(_chart, cmd); break;
    case BREAKAGE1: case BREAKAGE5: case BREAKAGE15: case BREAKAGE30:         _result = Trade_Breakage(_chart, cmd); break;
    case CCI1: case CCI5: case CCI15: case CCI30:                             _result = Trade_CCI(_chart, cmd); break;
    case DEMARKER1: case DEMARKER5: case DEMARKER15: case DEMARKER30:         _result = Trade_DeMarker(_chart, cmd); break;
    case ENVELOPES1: case ENVELOPES5: case ENVELOPES15: case ENVELOPES30:     _result = Trade_Envelopes(_chart, cmd); break;
    case FORCE1: case FORCE5: case FORCE15: case FORCE30:                     _result = Trade_Force(_chart, cmd); break;
    case FRACTALS1: case FRACTALS5: case FRACTALS15: case FRACTALS30:         _result = Trade_Fractals(_chart, cmd); break;
    case GATOR1: case GATOR5: case GATOR15: case GATOR30:                     _result = Trade_Gator(_chart, cmd); break;
    case ICHIMOKU1: case ICHIMOKU5: case ICHIMOKU15: case ICHIMOKU30:         _result = Trade_Ichimoku(_chart, cmd); break;
    case MA1: case MA5: case MA15: case MA30:                                 _result = Trade_MA(_chart, cmd); break;
    case MACD1: case MACD5: case MACD15: case MACD30:                         _result = Trade_MACD(_chart, cmd); break;
    case MFI1: case MFI5: case MFI15: case MFI30:                             _result = Trade_MFI(_chart, cmd); break;
    case MOM1: case MOM5: case MOM15: case MOM30:                             _result = Trade_Momentum(_chart, cmd); break;
    case OBV1: case OBV5: case OBV15: case OBV30:                             _result = Trade_OBV(_chart, cmd); break;
    case OSMA1: case OSMA5: case OSMA15: case OSMA30:                         _result = Trade_OSMA(_chart, cmd); break;
    case RSI1: case RSI5: case RSI15: case RSI30:                             _result = Trade_RSI(_chart, cmd); break;
    case RVI1: case RVI5: case RVI15: case RVI30:                             _result = Trade_RVI(_chart, cmd); break;
    case SAR1: case SAR5: case SAR15: case SAR30:                             _result = Trade_SAR(_chart, cmd); break;
    case STDDEV1: case STDDEV5: case STDDEV15: case STDDEV30:                 _result = Trade_StdDev(_chart, cmd); break;
    case STOCHASTIC1: case STOCHASTIC5: case STOCHASTIC15: case STOCHASTIC30: _result = Trade_Stochastic(_chart, cmd); break;
    case WPR1: case WPR5: case WPR15: case WPR30:                             _result = Trade_WPR(_chart, cmd); break;
    case ZIGZAG1: case ZIGZAG5: case ZIGZAG15: case ZIGZAG30:                 _result = Trade_ZigZag(_chart, cmd); break;
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  DEBUG_CHECKPOINT_POP
  return _result;
}

/**
 * Update specific indicator.
 * Gukkuk im Versteck
 */
bool UpdateIndicator(Chart *_chart, ENUM_INDICATOR_TYPE type) {
  DEBUG_CHECKPOINT_ADD
  bool success = true;
  int i; string text = __FUNCTION__ + ": ";
  ENUM_TIMEFRAMES tf = _chart.GetTf();
  uint index = _chart.TfToIndex();
  string symbol = _chart.GetSymbol();
  double ratio = 1.0, ratio2 = 1.0;
  int shift;
  // double envelopes_deviation;

  #ifdef __profiler__ PROFILER_START #endif
  switch (type) {
#ifdef __advanced__
    case INDI_AC: // Calculates the Bill Williams' Accelerator/Decelerator oscillator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++)
        iac[index][i] = iAC(symbol, tf, i);
      break;
    case INDI_AD: // Calculates the Accumulation/Distribution indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++)
        ad[index][i] = iAD(symbol, tf, i);
      break;
    case INDI_ADX: // Calculates the Average Directional Movement Index indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        adx[index][i][MODE_MAIN]    = iADX(symbol, tf, ADX_Period, ADX_Applied_Price, MODE_MAIN, i);    // Base indicator line
        adx[index][i][MODE_PLUSDI]  = iADX(symbol, tf, ADX_Period, ADX_Applied_Price, MODE_PLUSDI, i);  // +DI indicator line
        adx[index][i][MODE_MINUSDI] = iADX(symbol, tf, ADX_Period, ADX_Applied_Price, MODE_MINUSDI, i); // -DI indicator line
      }
      break;
#endif
    case INDI_ALLIGATOR: // Calculates the Alligator indicator.
      // Colors: Alligator's Jaw - Blue, Alligator's Teeth - Red, Alligator's Lips - Green.
      ratio = tf == 30 ? 1.0 : pow(Alligator_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        shift = i + Alligator_Shift + (i == FINAL_ENUM_INDICATOR_INDEX - 1 ? Alligator_Shift_Far : 0);
        alligator[index][i][LINE_LIPS]  = iMA(symbol, tf, (int) (Alligator_Period_Lips * ratio),  Alligator_Shift_Lips,  Alligator_MA_Method, Alligator_Applied_Price, shift);
        alligator[index][i][LINE_TEETH] = iMA(symbol, tf, (int) (Alligator_Period_Teeth * ratio), Alligator_Shift_Teeth, Alligator_MA_Method, Alligator_Applied_Price, shift);
        alligator[index][i][LINE_JAW]   = iMA(symbol, tf, (int) (Alligator_Period_Jaw * ratio),   Alligator_Shift_Jaw,   Alligator_MA_Method, Alligator_Applied_Price, shift);
        /**
        if (VerboseDebug) PrintFormat("%d: iMA(%s, %d, %d (%g), %d, %d, %d, %d) = %g",
          i, symbol, tf, (int) (Alligator_Period_Jaw * ratio), ratio, Alligator_Shift_Jaw,   Alligator_MA_Method, Alligator_Applied_Price, shift, alligator[index][i][LINE_JAW]);
        */
      }
      success = (bool) alligator[index][CURR][LINE_JAW] + alligator[index][PREV][LINE_JAW] + alligator[index][FAR][LINE_JAW];
      /* Note: This is equivalent to:
        alligator[index][i][LINE_TEETH] = iAlligator(symbol, tf, Alligator_Period_Jaw, Alligator_Shift_Jaw, Alligator_Period_Teeth, Alligator_Shift_Teeth, Alligator_Period_Lips, Alligator_Shift_Lips, Alligator_MA_Method, Alligator_Applied_Price, MODE_GATORJAW,   Alligator_Shift);
        alligator[index][i][LINE_TEETH] = iAlligator(symbol, tf, Alligator_Period_Jaw, Alligator_Shift_Jaw, Alligator_Period_Teeth, Alligator_Shift_Teeth, Alligator_Period_Lips, Alligator_Shift_Lips, Alligator_MA_Method, Alligator_Applied_Price, MODE_GATORTEETH, Alligator_Shift);
        alligator[index][i][LINE_LIPS]  = iAlligator(symbol, tf, Alligator_Period_Jaw, Alligator_Shift_Jaw, Alligator_Period_Teeth, Alligator_Shift_Teeth, Alligator_Period_Lips, Alligator_Shift_Lips, Alligator_MA_Method, Alligator_Applied_Price, MODE_GATORLIPS,  Alligator_Shift);
       */
      if (VerboseDebug) PrintFormat("Alligator M%d: %s", tf, Array::ArrToString3D(alligator, ",", Digits));
      break;
#ifdef __advanced__
/*
    case INDI_ATR: // Calculates the Average True Range indicator.
      ratio = tf == 30 ? 1.0 : pow(ATR_Period_Ratio, fabs(chart.TfToIndex(PERIOD_M30) - chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        atr[index][i][FAST] = iATR(symbol, tf, (int) (ATR_Period_Fast * ratio), i);
        atr[index][i][SLOW] = iATR(symbol, tf, (int) (ATR_Period_Slow * ratio), i);
      }
      break;
    case AWESOME: // Calculates the Awesome oscillator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        awesome[index][i] = iAO(symbol, tf, i);
      }
      break;
*/
#endif // __advanced__
    case INDI_BANDS: // Calculates the Bollinger Bands indicator.
      // int sid, bands_period = Bands_Period; // Not used at the moment.
      // sid = GetStrategyViaIndicator(BANDS, tf); bands_period = info[sid][CUSTOM_PERIOD]; // Not used at the moment.
      ratio = tf == PERIOD_M30 ? 1.0 : pow(Bands_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf)));
      ratio2 = tf == PERIOD_M30 ? 1.0 : pow(Bands_Deviation_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf)));
      //PrintFormat("tf: %s, ratio1/ratio2: %g/%g; %g/%g; fabs(%d - %d)", _chart.TfToString(), ratio, ratio2, Bands_Period * ratio, Bands_Deviation * ratio2, _chart.TfToIndex(PERIOD_M30), _chart.TfToIndex(tf));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        shift = i + Bands_Shift + (i == FINAL_ENUM_INDICATOR_INDEX - 1 ? Bands_Shift_Far : 0);
        bands[index][i][BAND_BASE]  = iBands(symbol, tf, (int) (Bands_Period * ratio), Bands_Deviation * ratio2, 0, Bands_Applied_Price, BAND_BASE,  shift);
        bands[index][i][BAND_UPPER] = iBands(symbol, tf, (int) (Bands_Period * ratio), Bands_Deviation * ratio2, 0, Bands_Applied_Price, BAND_UPPER, shift);
        bands[index][i][BAND_LOWER] = iBands(symbol, tf, (int) (Bands_Period * ratio), Bands_Deviation * ratio2, 0, Bands_Applied_Price, BAND_LOWER, shift);
      }
      success = (bool)bands[index][CURR][BAND_BASE];
      if (VerboseDebug) PrintFormat("Bands M%d: %s", tf, Array::ArrToString3D(bands, ",", Digits));
      break;
#ifdef __advanced__
    case INDI_BEARS: // Calculates the Bears Power and Bulls Power indicators.
      ratio = tf == 30 ? 1.0 : pow(BPower_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        bpower[index][i][ORDER_TYPE_BUY]  = iBullsPower(symbol, tf, (int) (BPower_Period * ratio), BPower_Applied_Price, i);
        bpower[index][i][ORDER_TYPE_SELL] = iBearsPower(symbol, tf, (int) (BPower_Period * ratio), BPower_Applied_Price, i);
      }
      success = (bool)(bpower[index][CURR][ORDER_TYPE_BUY] || bpower[index][CURR][ORDER_TYPE_SELL]);
      // Message("Bulls: " + bpower[index][CURR][ORDER_TYPE_BUY] + ", Bears: " + bpower[index][CURR][ORDER_TYPE_SELL]);
      break;
    case INDI_BWMFI: // Calculates the Market Facilitation Index indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        bwmfi[index][i] = iBWMFI(symbol, tf, i);
      }
      success = (bool) bwmfi[index][CURR];
      break;
#endif
    case INDI_CCI: // Calculates the Commodity Channel Index indicator.
      ratio = tf == 30 ? 1.0 : pow(CCI_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        cci[index][i] = iCCI(symbol, tf, (int) (CCI_Period * ratio), CCI_Applied_Price, i + CCI_Shift);
      }
      success = (bool) cci[index][CURR];
      break;
    case INDI_DEMARKER: // Calculates the DeMarker indicator.
      ratio = tf == 30 ? 1.0 : pow(DeMarker_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        demarker[index][i] = iDeMarker(symbol, tf, (int) (DeMarker_Period * ratio), i + DeMarker_Shift);
      }
      // success = (bool) demarker[index][CURR] + demarker[index][PREV] + demarker[index][FAR];
      // PrintFormat("Period: %d, DeMarker: %g", period, demarker[index][CURR]);
      if (VerboseDebug) PrintFormat("%s: DeMarker M%d: %s", DateTime::TimeToStr(_chart.GetBarTime(tf)), tf, Array::ArrToString2D(demarker, ",", Digits));
      break;
    case INDI_ENVELOPES: // Calculates the Envelopes indicator.
      /*
      envelopes_deviation = Envelopes30_Deviation;
      switch (period) {
        case M1: envelopes_deviation = Envelopes1_Deviation; break;
        case M5: envelopes_deviation = Envelopes5_Deviation; break;
        case M15: envelopes_deviation = Envelopes15_Deviation; break;
        case M30: envelopes_deviation = Envelopes30_Deviation; break;
      }
      */
      ratio = tf == 30 ? 1.0 : pow(Envelopes_MA_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      ratio2 = tf == 30 ? 1.0 : pow(Envelopes_Deviation_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        envelopes[index][i][MODE_MAIN]  = iEnvelopes(symbol, tf, (int) (Envelopes_MA_Period * ratio), Envelopes_MA_Method, Envelopes_MA_Shift, Envelopes_Applied_Price, Envelopes_Deviation * ratio2, MODE_MAIN,  i + Envelopes_Shift);
        envelopes[index][i][LINE_UPPER] = iEnvelopes(symbol, tf, (int) (Envelopes_MA_Period * ratio), Envelopes_MA_Method, Envelopes_MA_Shift, Envelopes_Applied_Price, Envelopes_Deviation * ratio2, LINE_UPPER, i + Envelopes_Shift);
        envelopes[index][i][LINE_LOWER]  = iEnvelopes(symbol, tf, (int) (Envelopes_MA_Period * ratio), Envelopes_MA_Method, Envelopes_MA_Shift, Envelopes_Applied_Price, Envelopes_Deviation * ratio2, LINE_LOWER, i + Envelopes_Shift);
      }
      success = (bool) envelopes[index][CURR][MODE_MAIN];
      if (VerboseDebug) PrintFormat("Envelopes M%d: %s", tf, Array::ArrToString3D(envelopes, ",", Digits));
      break;
#ifdef __advanced__
    case INDI_FORCE: // Calculates the Force Index indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        iforce[index][i] = iForce(symbol, tf, Force_Period, Force_MA_Method, Force_Applied_price, i);
      }
      success = (bool) iforce[index][CURR];
      break;
#endif
    case INDI_FRACTALS: // Calculates the Fractals indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        fractals[index][i][LINE_LOWER] = iFractals(symbol, tf, LINE_LOWER, i + Fractals_Shift);
        fractals[index][i][LINE_UPPER] = iFractals(symbol, tf, LINE_UPPER, i + Fractals_Shift);
      }
      if (VerboseDebug) PrintFormat("Fractals M%d: %s", tf, Array::ArrToString3D(fractals, ",", Digits));
      break;
    case INDI_GATOR: // Calculates the Gator oscillator.
      // Colors: Alligator's Jaw - Blue, Alligator's Teeth - Red, Alligator's Lips - Green.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        gator[index][i][LINE_LIPS]  = iGator(symbol, tf, Alligator_Period_Jaw, Alligator_Shift_Jaw, Alligator_Period_Lips, Alligator_Shift_Lips, Alligator_Period_Lips, Alligator_Shift_Lips, Alligator_MA_Method, Alligator_Applied_Price, MODE_GATORLIPS,  Alligator_Shift);
        gator[index][i][LINE_TEETH] = iGator(symbol, tf, Alligator_Period_Jaw, Alligator_Shift_Jaw, Alligator_Period_Teeth, Alligator_Shift_Teeth, Alligator_Period_Lips, Alligator_Shift_Lips, Alligator_MA_Method, Alligator_Applied_Price, MODE_GATORTEETH, Alligator_Shift);
        gator[index][i][LINE_JAW] = iGator(symbol, tf, Alligator_Period_Jaw, Alligator_Shift_Jaw, Alligator_Period_Jaw, Alligator_Shift_Jaw, Alligator_Period_Lips, Alligator_Shift_Lips, Alligator_MA_Method, Alligator_Applied_Price, MODE_GATORJAW,   Alligator_Shift);
      }
      success = (bool)gator[index][CURR][LINE_JAW];
      break;
    case INDI_ICHIMOKU: // Calculates the Ichimoku Kinko Hyo indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        ichimoku[index][i][MODE_TENKANSEN]   = iIchimoku(symbol, tf, Ichimoku_Period_Tenkan_Sen, Ichimoku_Period_Kijun_Sen, Ichimoku_Period_Senkou_Span_B, MODE_TENKANSEN, i);
        ichimoku[index][i][MODE_KIJUNSEN]    = iIchimoku(symbol, tf, Ichimoku_Period_Tenkan_Sen, Ichimoku_Period_Kijun_Sen, Ichimoku_Period_Senkou_Span_B, MODE_KIJUNSEN, i);
        ichimoku[index][i][MODE_SENKOUSPANA] = iIchimoku(symbol, tf, Ichimoku_Period_Tenkan_Sen, Ichimoku_Period_Kijun_Sen, Ichimoku_Period_Senkou_Span_B, MODE_SENKOUSPANA, i);
        ichimoku[index][i][MODE_SENKOUSPANB] = iIchimoku(symbol, tf, Ichimoku_Period_Tenkan_Sen, Ichimoku_Period_Kijun_Sen, Ichimoku_Period_Senkou_Span_B, MODE_SENKOUSPANB, i);
        ichimoku[index][i][MODE_CHIKOUSPAN]  = iIchimoku(symbol, tf, Ichimoku_Period_Tenkan_Sen, Ichimoku_Period_Kijun_Sen, Ichimoku_Period_Senkou_Span_B, MODE_CHIKOUSPAN, i);
      }
      success = (bool)ichimoku[index][CURR][MODE_TENKANSEN];
      break;
    case INDI_MA: // Calculates the Moving Average indicator.
      // Calculate MA Fast.
      ratio = tf == 30 ? 1.0 : pow(MA_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        shift = i + MA_Shift + (i == FINAL_ENUM_INDICATOR_INDEX - 1 ? MA_Shift_Far : 0);
        ma_fast[index][i]   = iMA(symbol, tf, (int) (MA_Period_Fast * ratio),   MA_Shift_Fast,   MA_Method, MA_Applied_Price, shift);
        ma_medium[index][i] = iMA(symbol, tf, (int) (MA_Period_Medium * ratio), MA_Shift_Medium, MA_Method, MA_Applied_Price, shift);
        ma_slow[index][i]   = iMA(symbol, tf, (int) (MA_Period_Slow * ratio),   MA_Shift_Slow,   MA_Method, MA_Applied_Price, shift);
        /*
        if (tf == Period() && i < FINAL_ENUM_INDICATOR_INDEX - 1) {
          Draw::TLine(StringFormat("%s%s%d", symbol, "MA Fast", i),   ma_fast[index][i],   ma_fast[index][i+1],    iTime(NULL, 0, shift), iTime(NULL, 0, shift+1), clrBlue);
          Draw::TLine(StringFormat("%s%s%d", symbol, "MA Medium", i), ma_medium[index][i], ma_medium[index][i+1],  iTime(NULL, 0, shift), iTime(NULL, 0, shift+1), clrYellow);
          Draw::TLine(StringFormat("%s%s%d", symbol, "MA Slow", i),   ma_slow[index][i],   ma_slow[index][i+1],    iTime(NULL, 0, shift), iTime(NULL, 0, shift+1), clrGray);
        }
        */
      }
      success = (bool) ma_fast[index][CURR] || ma_medium[index][CURR] || ma_slow[index][CURR];
      if (VerboseDebug) PrintFormat("MA Fast M%d: %s", tf, Array::ArrToString2D(ma_fast, ",", Digits));
      if (VerboseDebug) PrintFormat("MA Medium M%d: %s", tf, Array::ArrToString2D(ma_medium, ",", Digits));
      if (VerboseDebug) PrintFormat("MA Slow M%d: %s", tf, Array::ArrToString2D(ma_slow, ",", Digits));
      // if (VerboseDebug && Check::IsVisualMode()) Draw::DrawMA(tf);
      break;
    case INDI_MACD: // Calculates the Moving Averages Convergence/Divergence indicator.
      ratio = tf == 30 ? 1.0 : pow(MACD_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        shift = i + MACD_Shift + (i == FINAL_ENUM_INDICATOR_INDEX - 1 ? MACD_Shift_Far : 0);
        macd[index][i][MODE_MAIN]   = iMACD(symbol, tf, (int) (MACD_Period_Fast * ratio), (int) (MACD_Period_Slow * ratio), (int) (MACD_Period_Signal * ratio), MACD_Applied_Price, MODE_MAIN,   shift);
        macd[index][i][MODE_SIGNAL] = iMACD(symbol, tf, (int) (MACD_Period_Fast * ratio), (int) (MACD_Period_Slow * ratio), (int) (MACD_Period_Signal * ratio), MACD_Applied_Price, MODE_SIGNAL, shift);
      }
      if (VerboseDebug) PrintFormat("MACD M%d: %s", tf, Array::ArrToString3D(macd, ",", Digits));
      success = (bool)macd[index][CURR][MODE_MAIN];
      break;
    case INDI_MFI: // Calculates the Money Flow Index indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        mfi[index][i] = iMFI(symbol, tf, MFI_Period, i);
      }
      success = (bool)mfi[index][CURR];
      break;
    /*
    case INDI_MOMENTUM: // Calculates the Momentum indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        momentum[index][i][FAST] = iMomentum(symbol, tf, Momentum_Period_Fast, Momentum_Applied_Price, i);
        momentum[index][i][SLOW] = iMomentum(symbol, tf, Momentum_Period_Slow, Momentum_Applied_Price, i);
      }
      success = (bool)momentum[index][CURR][SLOW];
      break;
    */
    case INDI_OBV: // Calculates the On Balance Volume indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        obv[index][i] = iOBV(symbol, tf, OBV_Applied_Price, i);
      }
      success = (bool) obv[index][CURR];
      break;
    case INDI_OSMA: // Calculates the Moving Average of Oscillator indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        osma[index][i] = iOsMA(symbol, tf, OSMA_Period_Fast, OSMA_Period_Slow, OSMA_Period_Signal, OSMA_Applied_Price, i);
      }
      success = (bool) osma[index][CURR];
      break;
    case INDI_RSI: // Calculates the Relative Strength Index indicator.
      // int rsi_period = RSI_Period; // Not used at the moment.
      // sid = GetStrategyViaIndicator(RSI, tf); rsi_period = info[sid][CUSTOM_PERIOD]; // Not used at the moment.
      ratio = tf == 30 ? 1.0 : pow(RSI_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex(tf) + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        rsi[index][i] = iRSI(symbol, tf, (int) (RSI_Period * ratio), RSI_Applied_Price, i + RSI_Shift);
        if (rsi[index][i] > rsi_stats[index][LINE_UPPER]) rsi_stats[index][LINE_UPPER] = rsi[index][i]; // Calculate maximum value.
        if (rsi[index][i] < rsi_stats[index][LINE_LOWER] || rsi_stats[index][LINE_LOWER] == 0) rsi_stats[index][LINE_LOWER] = rsi[index][i]; // Calculate minimum value.
      }
      // Calculate average value.
      rsi_stats[index][0] = (rsi_stats[index][0] > 0 ? (rsi_stats[index][0] + rsi[index][0] + rsi[index][1] + rsi[index][2]) / 4 : (rsi[index][0] + rsi[index][1] + rsi[index][2]) / 3);
      if (VerboseDebug) PrintFormat("%s: RSI %s: %s", DateTime::TimeToStr(_chart.GetBarTime()), _chart.TfToString(), Array::ArrToString2D(rsi, ",", Digits));
      success = (bool) rsi[index][CURR] + rsi[index][PREV] + rsi[index][FAR];
      break;
    case INDI_RVI: // Calculates the Relative Strength Index indicator.
      rvi[index][CURR][MODE_MAIN]   = iRVI(symbol, tf, 10, MODE_MAIN, CURR);
      rvi[index][PREV][MODE_MAIN]   = iRVI(symbol, tf, 10, MODE_MAIN, PREV + RVI_Shift);
      rvi[index][FAR][MODE_MAIN]    = iRVI(symbol, tf, 10, MODE_MAIN, FAR + RVI_Shift + RVI_Shift_Far);
      rvi[index][CURR][MODE_SIGNAL] = iRVI(symbol, tf, 10, MODE_SIGNAL, CURR);
      rvi[index][PREV][MODE_SIGNAL] = iRVI(symbol, tf, 10, MODE_SIGNAL, PREV + RVI_Shift);
      rvi[index][FAR][MODE_SIGNAL]  = iRVI(symbol, tf, 10, MODE_SIGNAL, FAR + RVI_Shift + RVI_Shift_Far);
      success = (bool) rvi[index][CURR][MODE_MAIN];
      break;
    case INDI_SAR: // Calculates the Parabolic Stop and Reverse system indicator.
      ratio = tf == 30 ? 1.0 : pow(SAR_Step_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex() + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        sar[index][i] = iSAR(symbol, tf, SAR_Step * ratio, SAR_Maximum_Stop, i + SAR_Shift);
      }
      if (VerboseDebug) PrintFormat("SAR M%d: %s", tf, Array::ArrToString2D(sar, ",", Digits));
      success = (bool) sar[index][CURR] + sar[index][PREV] + sar[index][FAR];
      break;
    case INDI_STDDEV: // Calculates the Standard Deviation indicator.
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        stddev[index][i] = iStdDev(symbol, tf, StdDev_MA_Period, StdDev_MA_Shift, StdDev_MA_Method, StdDev_Applied_Price, i);
      }
      if (VerboseDebug) PrintFormat("StdDev M%d: %s", tf, Array::ArrToString2D(stddev, ",", Digits));
      success = stddev[index][CURR];
      break;
    case INDI_STOCHASTIC: // Calculates the Stochastic Oscillator.
      // TODO
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        stochastic[index][i][MODE_MAIN]   = iStochastic(symbol, PERIOD_H1, 15, 9, 9, MODE_EMA, 0, MODE_MAIN, i);
        stochastic[index][i][MODE_SIGNAL] = iStochastic(symbol, PERIOD_H1, 15, 9, 9, MODE_EMA, 0, MODE_SIGNAL, i);
      }
      if (VerboseDebug) PrintFormat("Stochastic M%d: %s", tf, Array::ArrToString3D(stochastic, ",", Digits));
      success = stochastic[index][CURR][MODE_MAIN];
      break;
    case INDI_WPR: // Calculates the  Larry Williams' Percent Range.
      // Update the Larry Williams' Percent Range indicator values.
      ratio = tf == 30 ? 1.0 : pow(WPR_Period_Ratio, fabs(_chart.TfToIndex(PERIOD_M30) - _chart.TfToIndex() + 1));
      for (i = 0; i < FINAL_ENUM_INDICATOR_INDEX; i++) {
        wpr[index][i] = -iWPR(symbol, tf, (int) (WPR_Period * ratio), i + WPR_Shift);
      }
      if (VerboseDebug) PrintFormat("%s: WPR M%d: %s", DateTime::TimeToStr(_chart.GetBarTime()), tf, Array::ArrToString2D(wpr, ",", Digits));
      success = (bool) wpr[index][CURR] + wpr[index][PREV] + wpr[index][FAR];
      break;
    case INDI_ZIGZAG: // Calculates the custom ZigZag indicator.
      // TODO
      break;
  } // end: switch

  //processed[type][index] = chart.GetBarTime(tf);
  #ifdef __profiler__ PROFILER_STOP #endif
  DEBUG_CHECKPOINT_POP
  return (success);
}

/**
 * Execute trade order.
 *
 * @param
 *   cmd int
 *     Trade order command to execute.
 *   trade_volume int
 *     Volume of the trade to execute (size).
 *   sid int
 *     Strategy ID.
 *   order_comment string
 *     Order comment.
 *   retry bool
 *     if true, re-try to open again after error/failure.
 */
int ExecuteOrder(ENUM_ORDER_TYPE cmd, int sid, double trade_volume = 0, string order_comment = "", bool retry = true) {
  DEBUG_CHECKPOINT_ADD
  bool result = false;
  int order_ticket;
  double trade_volume_max = market.GetVolumeMax();
  Trade *_trade = trade[GetStrategyTimeframeIndex(sid)];

  #ifdef __profiler__ PROFILER_START #endif

  // if (VerboseTrace) Print(__FUNCTION__);
  if (trade_volume <= market.GetVolumeMin()) {
    trade_volume = GetStrategyLotSize(sid, cmd);
  } else {
    trade_volume = market.NormalizeLots(trade_volume);
  }

   // Check the limits.
   if (!OpenOrderIsAllowed(cmd, sid, trade_volume)) {
     return (false);
   }

   // Check the order comment.
   if (order_comment == "") {
     order_comment = GetStrategyComment(sid);
   }

    // Print current market information before placing the order.
    if (VerboseDebug) Print(__FUNCTION__ + ": " + GetMarketTextDetails());

    // Calculate take profit and stop loss.
    Chart::RefreshRates();
    double sl_trail = GetTrailingValue(_trade, cmd, ORDER_SL, sid);
    double tp_trail = GetTrailingValue(_trade, cmd, ORDER_TP, sid);
    double stoploss = _trade.CalcBestSLTP(sl_trail, StopLossMax, RiskMarginPerOrder, ORDER_SL, cmd, market.GetVolumeMin());
    double takeprofit = TakeProfitMax > 0 ? _trade.CalcBestSLTP(tp_trail, TakeProfitMax, 0, ORDER_TP, cmd, market.GetVolumeMin()) : tp_trail;
    if (sl_trail != stoploss) {
      // @todo: Raise the condition on reaching the max stop loss.
      // @todo: Implement different methods of action.
      Msg::ShowText(
        StringFormat("%s: Max stop loss has reached, Current SL: %g, Max SL: %g (%g)",
        __FUNCTION__, sl_trail, stoploss, Convert::MoneyToValue(account.AccountRealBalance() / 100 * GetRiskMarginPerOrder(), trade_volume)),
        "Debug", __FUNCTION__, __LINE__, VerboseDebug);
    }

    if (Boosting_Enabled && (ConWinsIncreaseFactor != 0 || ConLossesIncreaseFactor != 0)) {
      trade_volume = _trade.OptimizeLotSize(trade_volume, ConWinsIncreaseFactor, ConLossesIncreaseFactor, ConFactorOrdersLimit);
    }

    if (RiskMarginPerOrder >= 0) {
      trade_volume_max = _trade.GetMaxLotSize((uint) StopLossMax, GetRiskMarginPerOrder(), cmd);
      if (trade_volume > trade_volume_max) {
        trade_volume = trade_volume_max;
        Msg::ShowText(
          StringFormat("%s: Max volume has reached, Current lot size: %g, Max lot size: %g",
          __FUNCTION__, trade_volume, trade_volume_max),
          "Debug", __FUNCTION__, __LINE__, VerboseDebug);
        // @todo: Convert lot size into money worth.
      }
    }

  trade_volume = market.NormalizeLots(trade_volume);
  order_ticket = OrderSend(
      market.GetSymbol(),
      cmd,
      trade_volume,
      market.GetOpenOffer(cmd),
      max_order_slippage,
      NormalizeDouble(market.NormalizePrice(stoploss), market.GetDigits()),
      NormalizeDouble(market.NormalizePrice(takeprofit), market.GetDigits()),
      order_comment,
      MagicNumber + sid, 0, Order::GetOrderColor(cmd));
   if (order_ticket >= 0) {
      total_orders++;
      daily_orders++;
      if (!OrderSelect(order_ticket, SELECT_BY_TICKET) && VerboseErrors) {
        Msg::ShowText(StringFormat("%s (err_code=%d, sid=%d)", terminal.GetLastErrorText(), err_code, sid), "Error", __FUNCTION__, __LINE__, VerboseErrors);
        OrderPrint();
        if (retry) TaskAddOrderOpen(cmd, trade_volume, sid); // Will re-try again.
        info[sid][TOTAL_ERRORS]++;
        return (false);
      }
      Msg::ShowText(
         StringFormat("OrderSend(%s, %s, %g, %f, %d, %f, %f, '%s', %d, %d, %d)",
           market.GetSymbol(),
           Order::OrderTypeToString(cmd),
           trade_volume,
           market.GetOpenOffer(cmd),
           max_order_slippage,
           NormalizeDouble(market.NormalizePrice(stoploss), market.GetDigits()),
           NormalizeDouble(market.NormalizePrice(takeprofit), market.GetDigits()),
           order_comment,
           MagicNumber + sid, 0, Order::GetOrderColor(cmd)),
           "Trace", __FUNCTION__, __LINE__, VerboseTrace);
      result = true;
      // TicketAdd(order_ticket);
      last_order_time = TimeCurrent(); // Set last execution time.
      // last_trail_update = 0; // Set to 0, so trailing stops can be updated faster.
      stats[sid][AVG_SPREAD] = (stats[sid][AVG_SPREAD] + curr_spread) / 2;
      if (VerboseInfo) OrderPrint();
      Msg::ShowText(StringFormat("%s: %s", Order::OrderTypeToString(Order::OrderType()), GetAccountTextDetails()), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
      if (SoundAlert && Terminal::IsRealtime()) PlaySound(SoundFileAtOpen);
      if (SendEmailEachOrder) SendEmailExecuteOrder();

      if (SmartQueueActive && total_orders >= max_orders) OrderQueueClear(); // Clear queue if we're reached the limit again, so we can start fresh.
   } else {
     /* On ECN brokers you must open first and THEN set stops
     int ticket = OrderSend(..., 0,0,...)
     if (ticket < 0)
       Alert("OrderSend failed: ", GetLastError());
     else if (!OrderSelect(ticket, SELECT_BY_TICKET))
       Alert("OrderSelect failed: ", GetLastError());
     else if (!OrderModify(OrderTicket(), OrderOpenPrice(), SL, TP, 0))
       Alert("OrderModify failed: ", GetLastError());
     @see: https://www.mql5.com/en/forum/141509
     */
     result = false;
     info[sid][TOTAL_ERRORS]++;
     err_code = GetLastError();
     last_err = Msg::ShowText(StringFormat("%s (err_code=%d, sid=%d)", terminal.GetErrorText(err_code), err_code, sid), "Error", __FUNCTION__, __LINE__, VerboseErrors);
     last_debug = Msg::ShowText(
       StringFormat("OrderSend(%s, %s, %g, %f, %d, %f, %f, '%s', %d, %d, %d)",
         market.GetSymbol(),
         Order::OrderTypeToString(cmd),
         trade_volume,
         market.GetOpenOffer(cmd),
         max_order_slippage,
         NormalizeDouble(market.NormalizePrice(stoploss), market.GetDigits()),
         NormalizeDouble(market.NormalizePrice(takeprofit), market.GetDigits()),
         order_comment,
         MagicNumber + sid, 0, Order::GetOrderColor(cmd)),
         "Debug", __FUNCTION__, __LINE__, VerboseErrors | VerboseDebug | VerboseTrace);
     Msg::ShowText(GetAccountTextDetails(), "Debug", __FUNCTION__, __LINE__, VerboseErrors | VerboseDebug | VerboseTrace);
     Msg::ShowText(GetMarketTextDetails(),  "Debug", __FUNCTION__, __LINE__, VerboseErrors | VerboseDebug | VerboseTrace);
     if (VerboseErrors) {
       if (WriteReport) ReportAdd(last_err);
     }

     /* Post-process the errors. */
     if (err_code == ERR_INVALID_STOPS) {
       // Invalid stops can happen when the open price is too close to the market prices.
       // Therefore the minimal distance of the pending price from the current market is invalid.
       if (WriteReport) ReportAdd(last_debug);
       Msg::ShowText(StringFormat("sid = %d, stoploss(%d) = %g, takeprofit(%d) = %g, openprice = %g, stoplevel = %g pts",
         sid, GetTrailingMethod(sid, ORDER_SL), stoploss, GetTrailingMethod(sid, ORDER_TP), takeprofit,
         market.GetOpenOffer(cmd), SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)),
         "Debug", __FUNCTION__, __LINE__, VerboseErrors | VerboseDebug | VerboseTrace);
       Msg::ShowText(GetMarketTextDetails(),  "Debug", __FUNCTION__, __LINE__, VerboseErrors | VerboseDebug | VerboseTrace);
       retry = false;
     }
     if (err_code == ERR_TRADE_TOO_MANY_ORDERS) {
       // On some trade servers, the total amount of open and pending orders can be limited. If this limit has been exceeded, no new order will be opened.
       //MaxOrders = total_orders; // So we're setting new fixed limit for total orders which is allowed. // @fixme
       Msg::ShowText(StringFormat("Total orders: %d, Max orders: %d, Broker Limit: %d", OrdersTotal(), total_orders, AccountInfoInteger(ACCOUNT_LIMIT_ORDERS)), "Error", __FUNCTION__, __LINE__, VerboseErrors);
       retry = false;
     }
     if (err_code == ERR_INVALID_TRADE_VOLUME) { // OrderSend error 131
       // Invalid trade volume.
       // Usually happens when volume is not normalized, or on invalid volume value.
       if (WriteReport) ReportAdd(last_debug);
       Msg::ShowText(
         StringFormat("Volume: %g (Min: %g, Max: %g, Step: %g)",
           trade_volume, market.GetVolumeMin(), market.GetVolumeMax(), market.GetVolumeStep()),
           "Error", __FUNCTION__, __LINE__, VerboseErrors);
       retry = false;
     }
     if (err_code == ERR_TRADE_EXPIRATION_DENIED) {
       // Applying of pending order expiration time can be disabled in some trade servers.
       retry = false;
     }
     if (err_code == ERR_TOO_MANY_REQUESTS) {
       // It occurs when you send the same command OrderSend()/OrderModify() over and over again in a short period of time.
       retry = true;
       Sleep(200); // Wait 200ms.
     }
     if (err_code == ERR_OFF_QUOTES) { /* error code: 136 */
        // Price changed, so we should re-consider whether to execute order or not.
        retry = false;
     }
     if (err_code == ERR_REQUOTE) { /* error code: 138 */
       // Price re-quoted by broker.
       // If this happens too often, consider increasing slippage (MaxOrderPriceSlippage).
     }
     if (retry) TaskAddOrderOpen(cmd, trade_volume, sid); // Will re-try again. // warning 43: possible loss of data due to type conversion
     info[sid][TOTAL_ERRORS]++;
   } // end-if: order_ticket
  #ifdef __profiler__ PROFILER_STOP #endif
  return (result);
}

/**
 * Check if we can open new order.
 */
bool OpenOrderIsAllowed(ENUM_ORDER_TYPE cmd, int sid = EMPTY, double volume = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  bool result = true;
  string err;
  // if (VerboseTrace) Print(__FUNCTION__);
  // total_sl = Orders::TotalSL(); // Convert::ValueToMoney(Orders::TotalSL(ORDER_TYPE_BUY)), Convert::ValueToMoney(Orders::TotalSL(ORDER_TYPE_SELL)
  // total_tp = Orders::TotalTP(); // Convert::ValueToMoney(Orders::TotalSL(ORDER_TYPE_BUY)), Convert::ValueToMoney(Orders::TotalSL(ORDER_TYPE_SELL)
  if (volume < market.GetVolumeMin()) {
    last_trace = Msg::ShowText(StringFormat("%s: Lot size = %.2f", sname[sid], volume), "Trace", __FUNCTION__, __LINE__, VerboseTrace);
    result = false;
  } else if (!account.Trades().IsNewOrderAllowed()) {
    last_msg = Msg::ShowText("Maximum open and pending orders has reached the limit set by the broker.", "Info", __FUNCTION__, __LINE__, VerboseInfo);
    result = false;
  } else if (total_orders >= max_orders) {
    last_msg = Msg::ShowText(
      StringFormat("Maximum open and pending orders has reached the limit (MaxOrders) [%d>=%d].", total_orders, max_orders),
      "Info", __FUNCTION__, __LINE__, VerboseInfo
      );
    #ifdef __advanced__
    OrderQueueAdd(sid, cmd);
    #endif
    result = false;
  } else if (GetTotalOrdersByType(sid) >= GetMaxOrdersPerType()) {
    last_msg = Msg::ShowText(StringFormat("%s: Maximum open and pending orders per type has reached the limit (MaxOrdersPerType).", sname[sid]), "Info", __FUNCTION__, __LINE__, VerboseInfo);
    #ifdef __advanced__
    OrderQueueAdd(sid, cmd);
    #endif
    result = false;
  } else if (!account.CheckFreeMargin(cmd, volume)) {
    last_err = Msg::ShowText("No money to open more orders.", "Error", __FUNCTION__, __LINE__, VerboseInfo | VerboseErrors, PrintLogOnChart);
    if (VerboseDebug) PrintFormat("%s:%d: %s: Volume: %g", __FUNCTION__, __LINE__, sname[sid], volume);
    result = false;
  } else if (!CheckMinPipGap(sid)) {
    last_trace = Msg::ShowText(StringFormat("%s: Ignoring the executing order, because the distance between orders is too close [MinPipGap].", sname[sid]), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
    result = false;
  } else if (!CheckProfitFactorLimits(sid)) {
    result = false;
  } else if (RiskMarginTotal >= 0 && ea_margin_risk_level[Convert::OrderTypeBuyOrSell(cmd)] > GetRiskMarginInTotal() / 100) {
    last_msg = Msg::ShowText(
      StringFormat("Maximum margin risk for %s orders has reached the limit [%.2f>%.2f/100][RiskMarginTotal].",
      Order::OrderTypeToString(cmd, true), ea_margin_risk_level[Convert::OrderTypeBuyOrSell(cmd)], GetRiskMarginInTotal()),
      "Info", __FUNCTION__, __LINE__, VerboseInfo
    );
    result = false;
  }

  #ifdef __advanced__
  if (ApplySpreadLimits && !CheckSpreadLimit(sid)) {
    last_trace = Msg::ShowText(StringFormat("%s: Not executing order, because the spread is too high. (spread = %.1f pips).", sname[sid], curr_spread), "Trace", __FUNCTION__, __LINE__, VerboseTrace);
    result = false;
  } else if (MinIntervalSec > 0 && time_current - last_order_time < MinIntervalSec) {
    last_trace = Msg::ShowText(StringFormat("%s: There must be a %d sec minimum interval between subsequent trade signals.", sname[sid], MinIntervalSec), "Trace", __FUNCTION__, __LINE__, VerboseTrace);
    result = false;
  } else if (MaxOrdersPerDay > 0 && daily_orders >= GetMaxOrdersPerDay()) {
    last_err = Msg::ShowText("Maximum open and pending orders has reached the daily limit (MaxOrdersPerDay).", "Info", __FUNCTION__, __LINE__, VerboseInfo);
    OrderQueueAdd(sid, cmd);
    result = false;
  }
  #endif
  #ifdef __expire__
  CheckExpireDate();
  if (ea_expired) result = false;
  #endif
  if (err != last_err) last_err = err;
  return (result);
}

/**
 * Check if profit factor is not restricted for the specific strategy.
 *
 * @param
 *   sid (int) - strategy id
 * @return
 *   If true, the profit factor is fine, otherwise return false.
 */
bool CheckProfitFactorLimits(int sid = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  if (sid == EMPTY) {
    // If sid is empty, unsuspend all strategies.
    ActionExecute(A_UNSUSPEND_STRATEGIES);
    return (true);
  }
  conf[sid][PROFIT_FACTOR] = GetStrategyProfitFactor(sid);
  if (conf[sid][PROFIT_FACTOR] <= 0) {
    last_err = Msg::ShowText(
      StringFormat("%s: Profit factor is zero. (pf = %.1f)",
        sname[sid], conf[sid][PROFIT_FACTOR]),
      "Warning", __FUNCTION__, __LINE__, VerboseErrors);
    return (true);
  }
  if (ProfitFactorMinToTrade > 0 && conf[sid][PROFIT_FACTOR] < ProfitFactorMinToTrade) {
    last_err = Msg::ShowText(
      StringFormat("%s: Minimum profit factor has been reached, disabling strategy. (pf = %.1f)",
        sname[sid], conf[sid][PROFIT_FACTOR]),
      "Info", __FUNCTION__, __LINE__, VerboseInfo);
    info[sid][SUSPENDED] = true;
    return (false);
  }
  if (ProfitFactorMaxToTrade > 0 && conf[sid][PROFIT_FACTOR] > ProfitFactorMaxToTrade) {
    last_err = Msg::ShowText(
      StringFormat("%s: Maximum profit factor has been reached, disabling strategy. (pf = %.1f)",
        sname[sid], conf[sid][PROFIT_FACTOR]),
      "Info", __FUNCTION__, __LINE__, VerboseInfo);
    info[sid][SUSPENDED] = true;
    return (false);
  }
  if (VerboseDebug) PrintFormat("%s: Profit factor: %.1f", sname[sid], conf[sid][PROFIT_FACTOR]);
  return (true);
}

#ifdef __advanced__
/**
 * Check if spread is not too high for specific strategy.
 *
 * @param
 *   sid (int) - strategy id
 * @return
 *   If true, the spread is fine, otherwise return false.
 */
bool CheckSpreadLimit(int sid) {
  DEBUG_CHECKPOINT_ADD
  double spread_limit = Misc::If(conf[sid][SPREAD_LIMIT] > 0, fmin(conf[sid][SPREAD_LIMIT], MaxSpreadToTrade), MaxSpreadToTrade);
  #ifdef __backtest__
  if (curr_spread > 10) { PrintFormat("%s: Error %d: %s", __FUNCTION__, __LINE__, "Backtesting over 10 pips not supported, sorry."); ExpertRemove(); }
  #endif
  return curr_spread <= spread_limit;
}

#endif

/**
 * Close order.
 */
bool CloseOrder(int ticket_no = EMPTY, int reason_id = EMPTY, bool retry = true) {
  DEBUG_CHECKPOINT_ADD
  bool result = false;
  if (ticket_no == EMPTY) {
    ticket_no = OrderTicket();
  }
  if (!Order::OrderSelect(ticket_no, SELECT_BY_TICKET, MODE_TRADES)) {
    return (false);
  }
  #ifdef __profiler__ PROFILER_START #endif
  double close_price = NormalizeDouble(market.GetCloseOffer(), market.GetDigits());
  result = OrderClose(ticket_no, OrderLots(), close_price, max_order_slippage, Order::GetOrderColor(EMPTY, ColorBuy, ColorSell)); // @fixme: warning 43: possible loss of data due to type conversion
  // if (VerboseTrace) Print(__FUNCTION__ + ": CloseOrder request. Reason: " + reason + "; Result=" + result + " @ " + TimeCurrent() + "(" + TimeToStr(TimeCurrent()) + "), ticket# " + ticket_no);
  if (result) {
    total_orders--;
    last_close_profit = Order::GetOrderProfit();
    if (SoundAlert) PlaySound(SoundFileAtClose);
    // TaskAddCalcStats(ticket_no); // Already done on CheckHistory().
    last_msg = StringFormat("Closed order %d with profit %g pips (%s)", ticket_no, Order::GetOrderProfitInPips(), ReasonIdToText(reason_id));
    Message(last_msg);
    Msg::ShowText(last_msg, "Info", __FUNCTION__, __LINE__, VerboseInfo);
    last_debug = Msg::ShowText(Order::OrderTypeToString((ENUM_ORDER_TYPE) Order::OrderType()), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
    #ifdef __advanced__
      if (VerboseDebug) Print(__FUNCTION__, ": Closed order " + IntegerToString(ticket_no) + " with profit " + DoubleToStr(Order::GetOrderProfitInPips(), 0) + " pips, reason: " + ReasonIdToText(reason_id) + "; " + Order::OrderTypeToString((ENUM_ORDER_TYPE) Order::OrderType()));
    #else
      if (VerboseDebug) Print(__FUNCTION__, ": Closed order " + IntegerToString(ticket_no) + " with profit " + DoubleToStr(Order::GetOrderProfitInPips(), 0) + " pips; " + Order::OrderTypeToString((ENUM_ORDER_TYPE) Order::OrderType()));
    #endif
    if (SmartQueueActive) OrderQueueProcess();
  } else {
    err_code = GetLastError();
    if (VerboseErrors) Print(__FUNCTION__, ": Error: Ticket: ", ticket_no, "; Error: ", terminal.GetErrorText(err_code)); // @fixme: CloseOrder: Error: Ticket: 10958; Error: Invalid ticket. OrderClose error 4108.
    if (VerboseDebug) PrintFormat("Error: OrderClose(%d, %f, %f, %f, %d);", ticket_no, OrderLots(), close_price, max_order_slippage, Order::GetOrderColor(EMPTY, ColorBuy, ColorSell));
    if (VerboseDebug) Print(__FUNCTION__ + ": " + GetMarketTextDetails());
    OrderPrint();
    if (retry) TaskAddCloseOrder(ticket_no, reason_id); // Add task to re-try.
    int id = GetIdByMagic();
    if (id < 0) info[id][TOTAL_ERRORS]++;
  } // end-if: !result
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Re-calculate statistics based on the order and return the profit value.
 */
double OrderCalc(int ticket_no = 0) {
  // OrderClosePrice(), OrderCloseTime(), OrderComment(), OrderCommission(), OrderExpiration(), OrderLots(), OrderOpenPrice(), OrderOpenTime(), OrderPrint(), OrderProfit(), OrderStopLoss(), OrderSwap(), OrderSymbol(), OrderTakeProfit(), OrderTicket(), OrderType()
  if (ticket_no == 0) ticket_no = OrderTicket();
  int id = GetIdByMagic();
  if (id < 0) return false;
  datetime close_time = Order::OrderCloseTime();
  double profit = Order::GetOrderProfit();
  info[id][TOTAL_ORDERS]++;
  if (profit > 0) {
    info[id][TOTAL_ORDERS_WON]++;
    stats[id][TOTAL_GROSS_PROFIT] += profit;
    if (profit > daily[MAX_PROFIT])   daily[MAX_PROFIT] = profit;
    if (profit > weekly[MAX_PROFIT])  weekly[MAX_PROFIT] = profit;
    if (profit > monthly[MAX_PROFIT]) monthly[MAX_PROFIT] = profit;
  } else {
    info[id][TOTAL_ORDERS_LOSS]++;
    stats[id][TOTAL_GROSS_LOSS] += profit;
    if (profit < daily[MAX_LOSS])     daily[MAX_LOSS] = profit;
    if (profit < weekly[MAX_LOSS])    weekly[MAX_LOSS] = profit;
    if (profit < monthly[MAX_LOSS])   monthly[MAX_LOSS] = profit;
  }
  stats[id][TOTAL_NET_PROFIT] += profit;
  stats[id][TOTAL_PIP_PROFIT] += Convert::ValueToPips(Convert::MoneyToValue(profit, Order::OrderLots(), Order::OrderSymbol()), Order::OrderSymbol());

  if (DateTime::TimeDayOfYear(close_time) == DateTime::DayOfYear()) {
    stats[id][DAILY_PROFIT] += profit;
  }
  if (DateTime::TimeDayOfWeek(close_time) <= DateTime::DayOfWeek()) {
    stats[id][WEEKLY_PROFIT] += profit;
  }
  if (DateTime::TimeDay(close_time) <= DateTime::Day()) {
    stats[id][MONTHLY_PROFIT] += profit;
  }
  //TicketRemove(ticket_no);
  return profit;
}

/**
 * Close order by type of order and strategy used. See: ENUM_STRATEGY_TYPE.
 *
 * @param
 *   cmd (int) - trade operation command to close (ORDER_TYPE_SELL/ORDER_TYPE_BUY)
 *   strategy_type (int) - strategy type, see ENUM_STRATEGY_TYPE
 */
int CloseOrdersByType(ENUM_ORDER_TYPE cmd, int strategy_id, int reason_id, bool only_profitable = false) {
   int orders_total = 0;
   int order_failed = 0;
   double profit_total = 0.0;
   Market::RefreshRates();
   int order;
   for (order = 0; order < OrdersTotal(); order++) {
      if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES)) {
        if (strategy_id == GetIdByMagic() && OrderSymbol() == Symbol() && OrderType() == cmd) {
          if (only_profitable && Order::GetOrderProfit() < 0) continue;
          if (CloseOrder(NULL, reason_id)) {
             orders_total++;
             profit_total += Order::GetOrderProfit();
          } else {
            order_failed++;
          }
        }
      } else {
        if (VerboseDebug)
          Print(__FUNCTION__ + "(" + Order::OrderTypeToString(cmd) + ", " + IntegerToString(strategy_id) + "): Error: Order: " + IntegerToString(order) + "; Message: ", terminal.GetErrorText(err_code));
        // TaskAddCloseOrder(OrderTicket(), reason_id); // Add task to re-try.
      }
   }
   if (orders_total > 0 && VerboseInfo) {
     Print(__FUNCTION__ + "(): Closed ", orders_total, " orders (", cmd, ", ", strategy_id, ") on market change with total profit of : ", profit_total, " pips (", order_failed, " failed)");
   }
   return (orders_total);
}

// Update statistics.
bool UpdateStats() {
  // Check if bar time has been changed since last check.
  // int bar_time = iTime(NULL, PERIOD_M1, 0);
  // CheckStats(last_pip_change, MAX_TICK);
  #ifdef __profiler__ PROFILER_START #endif
  CheckStats(High[0], MAX_HIGH);
  CheckStats(account.AccountBalance(), MAX_BALANCE);
  CheckStats(account.AccountEquity(), MAX_EQUITY);
  CheckStats(total_orders, MAX_ORDERS);
  CheckStats(market.GetSpreadInPts(), MAX_SPREAD);
  if (last_pip_change > MarketBigDropSize) {
    Message(StringFormat("Market very big drop of %.1f pips detected!", last_pip_change));
    Print(__FUNCTION__ + ": " + GetLastMessage());
    if (WriteReport) ReportAdd(__FUNCTION__ + ": " + GetLastMessage());
  }
  else if (VerboseDebug && last_pip_change > MarketSuddenDropSize) {
    Message(StringFormat("Market sudden drop of %.1f pips detected!", last_pip_change));
    Print(__FUNCTION__ + ": " + GetLastMessage());
    if (WriteReport) ReportAdd(__FUNCTION__ + ": " + GetLastMessage());
  }
  /*
  PrintFormat("Orders: %d/%d (ORDER_TYPE_BUY:%d/ORDER_TYPE_SELL:%d), Balance: %g (Eq: %g), Total SL: %g (B:%g/S:%g), Total TP: %g (B:%g/S:%g), Calc Money: SL:%g/TP:%g",
    GetTotalOrders(), OrdersTotal(), Orders::GetOrdersByType(ORDER_TYPE_BUY), Orders::GetOrdersByType(ORDER_TYPE_SELL),
    AccountBalance(), AccountEquity(),
    total_sl, Convert::ValueToMoney(Orders::TotalSL(ORDER_TYPE_BUY)), Convert::ValueToMoney(Orders::TotalSL(ORDER_TYPE_SELL)),
    total_tp, Convert::ValueToMoney(Orders::TotalTP(ORDER_TYPE_BUY)), Convert::ValueToMoney(Orders::TotalTP(ORDER_TYPE_SELL)),
    Convert::ValueToMoney(total_sl), Convert::ValueToMoney(total_tp));
  */
  #ifdef __profiler__ PROFILER_STOP #endif
  return (true);
}

/* INDICATOR FUNCTIONS */

/**
 * Check if AC indicator is on buy or sell.
 *
 * @param
 *   _chart (Chart) - given chart to check
 *   cmd (int) - type of trade order command
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (float) - signal level to use
 */
bool Trade_AC(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false;
  uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_AC);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_AC, _chart.GetTf(), 0);
  if (signal_level == EMPTY)  signal_level  = GetStrategySignalLevel(INDI_AC, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //1. Acceleration/Deceleration — AC
      //Buy: if the indicator is above zero and 2 consecutive columns are green or if the indicator is below zero and 3 consecutive columns are green
      //Sell: if the indicator is below zero and 2 consecutive columns are red or if the indicator is above zero and 3 consecutive columns are red
      if ((iAC(NULL,piac,0)>=0&&iAC(NULL,piac,0)>iAC(NULL,piac,1)&&iAC(NULL,piac,1)>iAC(NULL,piac,2))||(iAC(NULL,piac,0)<=0
      && iAC(NULL,piac,0)>iAC(NULL,piac,1)&&iAC(NULL,piac,1)>iAC(NULL,piac,2)&&iAC(NULL,piac,2)>iAC(NULL,piac,3)))
      if ((iAC(NULL,piac,0)<=0&&iAC(NULL,piac,0)<iAC(NULL,piac,1)&&iAC(NULL,piac,1)<iAC(NULL,piac,2))||(iAC(NULL,piac,0)>=0
      && iAC(NULL,piac,0)<iAC(NULL,piac,1)&&iAC(NULL,piac,1)<iAC(NULL,piac,2)&&iAC(NULL,piac,2)<iAC(NULL,piac,3)))
    */
    case ORDER_TYPE_BUY:
      /*
        bool result = iac[period][CURR][LINE_LOWER] != 0.0 || iac[period][PREV][LINE_LOWER] != 0.0 || iac[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !AC_On_Sell(period);
        if (METHOD(signal_method, 2)) result &= AC_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= AC_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= iac[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !AC_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = iac[period][CURR][LINE_UPPER] != 0.0 || iac[period][PREV][LINE_UPPER] != 0.0 || iac[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !AC_On_Buy(period);
        if (METHOD(signal_method, 2)) result &= AC_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= AC_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= iac[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !AC_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if AD indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_AD(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_AD);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_AD, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_AD, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //2. Accumulation/Distribution - A/D
      //Main principle - convergence/divergence
      //Buy: indicator growth at downtrend
      //Sell: indicator fall at uptrend
      if (iAD(NULL,piad,0)>=iAD(NULL,piad,1)&&iClose(NULL,piad2,0)<=iClose(NULL,piad2,1))
      {f2=1;}
      if (iAD(NULL,piad,0)<=iAD(NULL,piad,1)&&iClose(NULL,piad2,0)>=iClose(NULL,piad2,1))
      {f2=-1;}
    */
    case ORDER_TYPE_BUY:
      /*
        bool result = AD[period][CURR][LINE_LOWER] != 0.0 || AD[period][PREV][LINE_LOWER] != 0.0 || AD[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !AD_On_Sell(period);
        if (METHOD(signal_method, 2)) result &= AD_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= AD_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= AD[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !AD_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = AD[period][CURR][LINE_UPPER] != 0.0 || AD[period][PREV][LINE_UPPER] != 0.0 || AD[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !AD_On_Buy(period);
        if (METHOD(signal_method, 2)) result &= AD_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= AD_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= AD[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !AD_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if ADX indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_ADX(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_ADX);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_ADX, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_ADX, _chart.GetTf(), 0.0);
  switch (cmd) {
      //   if(iADX(NULL,0,14,PRICE_HIGH,MODE_MAIN,0)>iADX(NULL,0,14,PRICE_HIGH,MODE_PLUSDI,0)) return(0);
    /*
      //5. Average Directional Movement Index - ADX
      //Buy: +DI line is above -DI line, ADX is more than a certain value and grows (i.e. trend strengthens)
      //Sell: -DI line is above +DI line, ADX is more than a certain value and grows (i.e. trend strengthens)
      if (iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MINUSDI,0)<iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_PLUSDI,0)&&iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MAIN,0)>=minadx&&iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MAIN,0)>iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MAIN,1))
      {f5=1;}
      if (iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MINUSDI,0)>iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_PLUSDI,0)&&iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MAIN,0)>=minadx&&iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MAIN,0)>iADX(NULL,piadx,piadu,PRICE_CLOSE,MODE_MAIN,1))
      {f5=-1;}
    */
    case ORDER_TYPE_BUY:
      /*
        bool result = ADX[period][CURR][LINE_LOWER] != 0.0 || ADX[period][PREV][LINE_LOWER] != 0.0 || ADX[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !ADX_On_Sell(period);
        if (METHOD(signal_method, 2)) result &= ADX_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= ADX_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= ADX[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !ADX_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = ADX[period][CURR][LINE_UPPER] != 0.0 || ADX[period][PREV][LINE_UPPER] != 0.0 || ADX[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !ADX_On_Buy(period);
        if (METHOD(signal_method, 2)) result &= ADX_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= ADX_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= ADX[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !ADX_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Alligator indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Alligator(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  // [x][0] - The Blue line (Alligator's Jaw), [x][1] - The Red Line (Alligator's Teeth), [x][2] - The Green Line (Alligator's Lips)
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_ALLIGATOR);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_ALLIGATOR, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_ALLIGATOR, _chart.GetTf(), 0.0);
  double gap = signal_level * pip_size;

  switch(cmd) {
    case ORDER_TYPE_BUY:
      result = (
        alligator[period][CURR][LINE_LIPS] > alligator[period][CURR][LINE_TEETH] + gap && // Check if Lips are above Teeth ...
        alligator[period][CURR][LINE_TEETH] > alligator[period][CURR][LINE_JAW] + gap // ... Teeth are above Jaw ...
        );
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= (
          alligator[period][CURR][LINE_LIPS] > alligator[period][PREV][LINE_LIPS] && // Check if Lips increased.
          alligator[period][CURR][LINE_TEETH] > alligator[period][PREV][LINE_TEETH] && // Check if Teeth increased.
          alligator[period][CURR][LINE_JAW] > alligator[period][PREV][LINE_JAW] // // Check if Jaw increased.
          );
        if (METHOD(signal_method, 1)) result &= (
          alligator[period][PREV][LINE_LIPS] > alligator[period][FAR][LINE_LIPS] && // Check if Lips increased.
          alligator[period][PREV][LINE_TEETH] > alligator[period][FAR][LINE_TEETH] && // Check if Teeth increased.
          alligator[period][PREV][LINE_JAW] > alligator[period][FAR][LINE_JAW] // // Check if Jaw increased.
          );
        if (METHOD(signal_method, 2)) result &= alligator[period][CURR][LINE_LIPS] > alligator[period][FAR][LINE_LIPS]; // Check if Lips increased.
        if (METHOD(signal_method, 3)) result &= alligator[period][CURR][LINE_LIPS] - alligator[period][CURR][LINE_TEETH] > alligator[period][CURR][LINE_TEETH] - alligator[period][CURR][LINE_JAW];
        if (METHOD(signal_method, 4)) result &= (
          alligator[period][FAR][LINE_LIPS] <= alligator[period][FAR][LINE_TEETH] || // Check if Lips are below Teeth and ...
          alligator[period][FAR][LINE_LIPS] <= alligator[period][FAR][LINE_JAW] || // ... Lips are below Jaw and ...
          alligator[period][FAR][LINE_TEETH] <= alligator[period][FAR][LINE_JAW] // ... Teeth are below Jaw ...
          );
      }
      break;
    case ORDER_TYPE_SELL:
      result = (
        alligator[period][CURR][LINE_LIPS] + gap < alligator[period][CURR][LINE_TEETH] && // Check if Lips are below Teeth and ...
        alligator[period][CURR][LINE_TEETH] + gap < alligator[period][CURR][LINE_JAW] // ... Teeth are below Jaw ...
        );
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= (
          alligator[period][CURR][LINE_LIPS] < alligator[period][PREV][LINE_LIPS] && // Check if Lips decreased.
          alligator[period][CURR][LINE_TEETH] < alligator[period][PREV][LINE_TEETH] && // Check if Teeth decreased.
          alligator[period][CURR][LINE_JAW] < alligator[period][PREV][LINE_JAW] // // Check if Jaw decreased.
          );
        if (METHOD(signal_method, 1)) result &= (
          alligator[period][PREV][LINE_LIPS] < alligator[period][FAR][LINE_LIPS] && // Check if Lips decreased.
          alligator[period][PREV][LINE_TEETH] < alligator[period][FAR][LINE_TEETH] && // Check if Teeth decreased.
          alligator[period][PREV][LINE_JAW] < alligator[period][FAR][LINE_JAW] // // Check if Jaw decreased.
          );
        if (METHOD(signal_method, 2)) result &= alligator[period][CURR][LINE_LIPS] < alligator[period][FAR][LINE_LIPS]; // Check if Lips decreased.
        if (METHOD(signal_method, 3)) result &= alligator[period][CURR][LINE_TEETH] - alligator[period][CURR][LINE_LIPS] > alligator[period][CURR][LINE_JAW] - alligator[period][CURR][LINE_TEETH];
        if (METHOD(signal_method, 4)) result &= (
          alligator[period][FAR][LINE_LIPS] >= alligator[period][FAR][LINE_TEETH] || // Check if Lips are above Teeth ...
          alligator[period][FAR][LINE_LIPS] >= alligator[period][FAR][LINE_JAW] || // ... Lips are above Jaw ...
          alligator[period][FAR][LINE_TEETH] >= alligator[period][FAR][LINE_JAW] // ... Teeth are above Jaw ...
          );
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g; Trend: %g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level, curr_trend);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if ATR indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_ATR(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_ATR);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_ATR, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_ATR, _chart.GetTf(), 0.0);
  switch (cmd) {
    //   if(iATR(NULL,0,12,0)>iATR(NULL,0,20,0)) return(0);
    /*
      //6. Average True Range - ATR
      //Doesn't give independent signals. Is used to define volatility (trend strength).
      //principle: trend must be strengthened. Together with that ATR grows.
      //Because of the chart form it is inconvenient to analyze rise/fall. Only exceeding of threshold value is checked.
      //Flag is 1 when ATR is above threshold value (i.e. there is a trend), 0 - when ATR is below threshold value, -1 - never.
      if (iATR(NULL,piatr,piatru,0)>=minatr)
      {f6=1;}
    */
    case ORDER_TYPE_BUY:
      /*
        bool result = ATR[period][CURR][LINE_LOWER] != 0.0 || ATR[period][PREV][LINE_LOWER] != 0.0 || ATR[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !ATR_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= ATR_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= ATR_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= ATR[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !ATR_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = ATR[period][CURR][LINE_UPPER] != 0.0 || ATR[period][PREV][LINE_UPPER] != 0.0 || ATR[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !ATR_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= ATR_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= ATR_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= ATR[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !ATR_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Awesome indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Awesome(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_AO);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_AO, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_AO, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //7. Awesome Oscillator
      //Buy: 1. Signal "saucer" (3 positive columns, medium column is smaller than 2 others); 2. Changing from negative values to positive.
      //Sell: 1. Signal "saucer" (3 negative columns, medium column is larger than 2 others); 2. Changing from positive values to negative.
      if ((iAO(NULL,piao,2)>0&&iAO(NULL,piao,1)>0&&iAO(NULL,piao,0)>0&&iAO(NULL,piao,1)<iAO(NULL,piao,2)&&iAO(NULL,piao,1)<iAO(NULL,piao,0))||(iAO(NULL,piao,1)<0&&iAO(NULL,piao,0)>0))
      {f7=1;}
      if ((iAO(NULL,piao,2)<0&&iAO(NULL,piao,1)<0&&iAO(NULL,piao,0)<0&&iAO(NULL,piao,1)>iAO(NULL,piao,2)&&iAO(NULL,piao,1)>iAO(NULL,piao,0))||(iAO(NULL,piao,1)>0&&iAO(NULL,piao,0)<0))
      {f7=-1;}
    */
    case ORDER_TYPE_BUY:
      /*
        bool result = Awesome[period][CURR][LINE_LOWER] != 0.0 || Awesome[period][PREV][LINE_LOWER] != 0.0 || Awesome[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !Awesome_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= Awesome_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= Awesome_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= Awesome[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !Awesome_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = Awesome[period][CURR][LINE_UPPER] != 0.0 || Awesome[period][PREV][LINE_UPPER] != 0.0 || Awesome[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !Awesome_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= Awesome_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= Awesome_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= Awesome[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !Awesome_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Bands indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Bands(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_BANDS);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_BANDS, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_BANDS, _chart.GetTf(), 0);
  double lowest = fmin(Low[CURR], fmin(Low[PREV], Low[FAR]));
  double highest = fmax(High[CURR], fmax(High[PREV], High[FAR]));
  switch (cmd) {
    case ORDER_TYPE_BUY:
      // Price value was lower than the lower band.
      result = (
          lowest > 0 && lowest < fmax(fmax(bands[period][CURR][BAND_LOWER], bands[period][PREV][BAND_LOWER]), bands[period][FAR][BAND_LOWER])
          );
      // Buy: price crossed lower line upwards (returned to it from below).
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= fmin(Close[PREV], Close[FAR]) < bands[period][CURR][BAND_LOWER];
        if (METHOD(signal_method, 1)) result &= (bands[period][CURR][BAND_LOWER] > bands[period][FAR][BAND_LOWER]);
        if (METHOD(signal_method, 2)) result &= (bands[period][CURR][BAND_BASE] > bands[period][FAR][BAND_BASE]);
        if (METHOD(signal_method, 3)) result &= (bands[period][CURR][BAND_UPPER] > bands[period][FAR][BAND_UPPER]);
        if (METHOD(signal_method, 4)) result &= highest > bands[period][CURR][BAND_BASE];
        if (METHOD(signal_method, 5)) result &= Open[CURR] < bands[period][CURR][BAND_BASE];
        if (METHOD(signal_method, 6)) result &= fmin(Close[PREV], Close[FAR]) > bands[period][CURR][BAND_BASE];
        // if (METHOD(signal_method, 7)) result &= !Trade_Bands(Convert::NegateOrderType(cmd), (ENUM_TIMEFRAMES) Convert::IndexToTf(fmin(period + 1, M30)));
      }
      break;
    case ORDER_TYPE_SELL:
      // Price value was higher than the upper band.
      result = (
          lowest > 0 && highest > fmin(fmin(bands[period][CURR][BAND_UPPER], bands[period][PREV][BAND_UPPER]), bands[period][FAR][BAND_UPPER])
          );
      // Sell: price crossed upper line downwards (returned to it from above).
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= fmin(Close[PREV], Close[FAR]) > bands[period][CURR][BAND_UPPER];
        if (METHOD(signal_method, 1)) result &= (bands[period][CURR][BAND_LOWER] < bands[period][FAR][BAND_LOWER]);
        if (METHOD(signal_method, 2)) result &= (bands[period][CURR][BAND_BASE] < bands[period][FAR][BAND_BASE]);
        if (METHOD(signal_method, 3)) result &= (bands[period][CURR][BAND_UPPER] < bands[period][FAR][BAND_UPPER]);
        if (METHOD(signal_method, 4)) result &= lowest < bands[period][CURR][BAND_BASE];
        if (METHOD(signal_method, 5)) result &= Open[CURR] > bands[period][CURR][BAND_BASE];
        if (METHOD(signal_method, 6)) result &= fmin(Close[PREV], Close[FAR]) < bands[period][CURR][BAND_BASE];
        // if (METHOD(signal_method, 7)) result &= !Trade_Bands(Convert::NegateOrderType(cmd), (ENUM_TIMEFRAMES) Convert::IndexToTf(fmin(period + 1, M30)));
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    terminal.Logger().Trace(StringFormat("Signal: %s/%s/%d/%g", EnumToString(cmd), _chart.TfToString(), signal_method, signal_level), __FUNCTION_LINE__);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if BPower indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_BPower(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_BEARS);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_BEARS, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_BEARS, _chart.GetTf(), 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      /*
        bool result = BPower[period][CURR][LINE_LOWER] != 0.0 || BPower[period][PREV][LINE_LOWER] != 0.0 || BPower[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !BPower_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= BPower_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= BPower_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= BPower[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !BPower_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = BPower[period][CURR][LINE_UPPER] != 0.0 || BPower[period][PREV][LINE_UPPER] != 0.0 || BPower[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !BPower_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= BPower_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= BPower_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= BPower[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !BPower_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Breakage indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Breakage(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  // if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(BWMFI, tf, 0);
  // if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(BWMFI, tf, 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      /*
        bool result = Breakage[period][CURR][LINE_LOWER] != 0.0 || Breakage[period][PREV][LINE_LOWER] != 0.0 || Breakage[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !Breakage_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= Breakage_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= Breakage_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= Breakage[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !Breakage_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = Breakage[period][CURR][LINE_UPPER] != 0.0 || Breakage[period][PREV][LINE_UPPER] != 0.0 || Breakage[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !Breakage_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= Breakage_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= Breakage_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= Breakage[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !Breakage_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if BWMFI indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_BWMFI(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_BWMFI);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_BWMFI, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_BWMFI, _chart.GetTf(), 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      /*
        bool result = BWMFI[period][CURR][LINE_LOWER] != 0.0 || BWMFI[period][PREV][LINE_LOWER] != 0.0 || BWMFI[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !BWMFI_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= BWMFI_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= BWMFI_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= BWMFI[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !BWMFI_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = BWMFI[period][CURR][LINE_UPPER] != 0.0 || BWMFI[period][PREV][LINE_UPPER] != 0.0 || BWMFI[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !BWMFI_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= BWMFI_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= BWMFI_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= BWMFI[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !BWMFI_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if CCI indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_CCI(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_CCI);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_CCI, _chart.GetTf(), 0);
  if (signal_level == EMPTY)  signal_level  = GetStrategySignalLevel(INDI_CCI, _chart.GetTf(), 100);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      result = cci[period][CURR] > 0 && cci[period][CURR] < -signal_level;
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= cci[period][CURR] > cci[period][PREV];
        if (METHOD(signal_method, 1)) result &= cci[period][PREV] > cci[period][FAR];
        if (METHOD(signal_method, 2)) result &= cci[period][PREV] < -signal_level;
        if (METHOD(signal_method, 3)) result &= cci[period][FAR]  < -signal_level;
        if (METHOD(signal_method, 4)) result &= cci[period][CURR] - cci[period][PREV] > cci[period][PREV] - cci[period][FAR];
        if (METHOD(signal_method, 5)) result &= cci[period][FAR] > 0;
      }
      break;
    case ORDER_TYPE_SELL:
      result = cci[period][CURR] > 0 && cci[period][CURR] > signal_level;
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= cci[period][CURR] < cci[period][PREV];
        if (METHOD(signal_method, 1)) result &= cci[period][PREV] < cci[period][FAR];
        if (METHOD(signal_method, 2)) result &= cci[period][PREV] > signal_level;
        if (METHOD(signal_method, 3)) result &= cci[period][FAR]  > signal_level;
        if (METHOD(signal_method, 4)) result &= cci[period][PREV] - cci[period][CURR] > cci[period][FAR] - cci[period][PREV];
        if (METHOD(signal_method, 5)) result &= cci[period][FAR] < 0;
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if DeMarker indicator is on buy or sell.
 * Demarker Technical Indicator is based on the comparison of the period maximum with the previous period maximum.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_DeMarker(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_DEMARKER);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_DEMARKER, _chart.GetTf(), 0);
  if (signal_level == EMPTY)  signal_level  = GetStrategySignalLevel(INDI_DEMARKER, _chart.GetTf(), 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      result = demarker[period][CURR] < 0.5 - signal_level;
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= demarker[period][PREV] < 0.5 - signal_level;
        if (METHOD(signal_method, 1)) result &= demarker[period][FAR] < 0.5 - signal_level; // @to-remove?
        if (METHOD(signal_method, 2)) result &= demarker[period][CURR] < demarker[period][PREV]; // @to-remove?
        if (METHOD(signal_method, 3)) result &= demarker[period][PREV] < demarker[period][FAR]; // @to-remove?
        if (METHOD(signal_method, 4)) result &= demarker[period][PREV] < 0.5 - signal_level - signal_level/2;
      }
      // PrintFormat("DeMarker buy: %g <= %g", demarker[period][CURR], 0.5 - signal_level);
      break;
    case ORDER_TYPE_SELL:
      result = demarker[period][CURR] > 0.5 + signal_level;
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= demarker[period][PREV] > 0.5 + signal_level;
        if (METHOD(signal_method, 1)) result &= demarker[period][FAR] > 0.5 + signal_level;
        if (METHOD(signal_method, 2)) result &= demarker[period][CURR] > demarker[period][PREV];
        if (METHOD(signal_method, 3)) result &= demarker[period][PREV] > demarker[period][FAR];
        if (METHOD(signal_method, 4)) result &= demarker[period][PREV] > 0.5 + signal_level + signal_level/2;
      }
      // PrintFormat("DeMarker sell: %g >= %g", demarker[period][CURR], 0.5 + signal_level);
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Envelopes indicator is on sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Envelopes(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_ENVELOPES);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_ENVELOPES, _chart.GetTf(), 0);
  if (signal_level == EMPTY)  signal_level  = GetStrategySignalLevel(INDI_ENVELOPES, _chart.GetTf(), 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      result = Low[CURR] < envelopes[period][CURR][LINE_LOWER] || Low[PREV] < envelopes[period][CURR][LINE_LOWER]; // price low was below the lower band
      // result = result || (envelopes[period][CURR][MODE_MAIN] > envelopes[period][FAR][MODE_MAIN] && Open[CURR] > envelopes[period][CURR][LINE_UPPER]);
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= Open[CURR] > envelopes[period][CURR][LINE_LOWER]; // FIXME
        if (METHOD(signal_method, 1)) result &= envelopes[period][CURR][MODE_MAIN] < envelopes[period][PREV][MODE_MAIN];
        if (METHOD(signal_method, 2)) result &= envelopes[period][CURR][LINE_LOWER] < envelopes[period][PREV][LINE_LOWER];
        if (METHOD(signal_method, 3)) result &= envelopes[period][CURR][LINE_UPPER] < envelopes[period][PREV][LINE_UPPER];
        if (METHOD(signal_method, 4)) result &= envelopes[period][CURR][LINE_UPPER] - envelopes[period][CURR][LINE_LOWER] > envelopes[period][PREV][LINE_UPPER] - envelopes[period][PREV][LINE_LOWER];
        if (METHOD(signal_method, 5)) result &= _chart.GetAsk() < envelopes[period][CURR][MODE_MAIN];
        if (METHOD(signal_method, 6)) result &= Close[CURR] < envelopes[period][CURR][LINE_UPPER];
        //if (METHOD(signal_method, 7)) result &= _chart.GetAsk() > Close[PREV];
      }
      break;
    case ORDER_TYPE_SELL:
      result = High[CURR] > envelopes[period][CURR][LINE_UPPER] || High[PREV] > envelopes[period][CURR][LINE_UPPER]; // price high was above the upper band
      // result = result || (envelopes[period][CURR][MODE_MAIN] < envelopes[period][FAR][MODE_MAIN] && Open[CURR] < envelopes[period][CURR][LINE_LOWER]);
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= Open[CURR] < envelopes[period][CURR][LINE_UPPER]; // FIXME
        if (METHOD(signal_method, 1)) result &= envelopes[period][CURR][MODE_MAIN] > envelopes[period][PREV][MODE_MAIN];
        if (METHOD(signal_method, 2)) result &= envelopes[period][CURR][LINE_LOWER] > envelopes[period][PREV][LINE_LOWER];
        if (METHOD(signal_method, 3)) result &= envelopes[period][CURR][LINE_UPPER] > envelopes[period][PREV][LINE_UPPER];
        if (METHOD(signal_method, 4)) result &= envelopes[period][CURR][LINE_UPPER] - envelopes[period][CURR][LINE_LOWER] > envelopes[period][PREV][LINE_UPPER] - envelopes[period][PREV][LINE_LOWER];
        if (METHOD(signal_method, 5)) result &= _chart.GetAsk() > envelopes[period][CURR][MODE_MAIN];
        if (METHOD(signal_method, 6)) result &= Close[CURR] > envelopes[period][CURR][LINE_UPPER];
        //if (METHOD(signal_method, 7)) result &= _chart.GetAsk() < Close[PREV];
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Force indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Force(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_FORCE);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_FORCE, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_FORCE, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //14. Force Index
      //To use the indicator it should be correlated with another trend indicator
      //Flag 14 is 1, when FI recommends to buy (i.e. FI<0)
      //Flag 14 is -1, when FI recommends to sell (i.e. FI>0)
      if (iForce(NULL,piforce,piforceu,MODE_SMA,PRICE_CLOSE,0)<0)
      {f14=1;}
      if (iForce(NULL,piforce,piforceu,MODE_SMA,PRICE_CLOSE,0)>0)
      {f14=-1;}
    */
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Fractals indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Fractals(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint index = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_FRACTALS);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_FRACTALS, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_FRACTALS, _chart.GetTf(), 0.0);
  bool lower = (fractals[index][CURR][LINE_LOWER] != 0.0 || fractals[index][PREV][LINE_LOWER] != 0.0 || fractals[index][FAR][LINE_LOWER] != 0.0);
  bool upper = (fractals[index][CURR][LINE_UPPER] != 0.0 || fractals[index][PREV][LINE_UPPER] != 0.0 || fractals[index][FAR][LINE_UPPER] != 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      result = lower;
      if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[PREV];
      if (METHOD(signal_method, 1)) result &= _chart.GetBid() > Open[CURR];
      // if (METHOD(signal_method, 0)) result &= !Trade_Fractals(Convert::NegateOrderType(cmd), PERIOD_M30);
      // if (METHOD(signal_method, 1)) result &= !Trade_Fractals(Convert::NegateOrderType(cmd), Convert::IndexToTf(fmax(index + 1, M30)));
      // if (METHOD(signal_method, 2)) result &= !Trade_Fractals(Convert::NegateOrderType(cmd), Convert::IndexToTf(fmax(index + 2, M30)));
      // if (METHOD(signal_method, 1)) result &= !Fractals_On_Sell(tf);
      // if (METHOD(signal_method, 3)) result &= Fractals_On_Buy(M30);
      break;
    case ORDER_TYPE_SELL:
      result = upper;
      if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[PREV];
      if (METHOD(signal_method, 1)) result &= _chart.GetAsk() < Open[CURR];
      // if (METHOD(signal_method, 0)) result &= !Trade_Fractals(Convert::NegateOrderType(cmd), PERIOD_M30);
      // if (METHOD(signal_method, 1)) result &= !Trade_Fractals(Convert::NegateOrderType(cmd), Convert::IndexToTf(fmax(index + 1, M30)));
      // if (METHOD(signal_method, 2)) result &= !Trade_Fractals(Convert::NegateOrderType(cmd), Convert::IndexToTf(fmax(index + 2, M30)));
      // if (METHOD(signal_method, 1)) result &= !Fractals_On_Buy(tf);
      // if (METHOD(signal_method, 3)) result &= Fractals_On_Sell(M30);
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Gator indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Gator(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_GATOR);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_GATOR, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_GATOR, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //4. Gator Oscillator
      //Doesn't give independent signals. Is used for Alligator correction.
      //Principle: trend must be strengthened. Together with this Gator Oscillator goes up.
      //Lower part of diagram is taken for calculations. Growth is checked on 4 periods.
      //The flag is 1 of trend is strengthened, 0 - no strengthening, -1 - never.
      //Uses part of Alligator's variables
      if (iGator(NULL,piga,jaw_tf,jaw_shift,teeth_tf,teeth_shift,lips_tf,lips_shift,MODE_SMMA,PRICE_MEDIAN,LOWER,3)>iGator(NULL,piga,jaw_tf,jaw_shift,teeth_tf,teeth_shift,lips_tf,lips_shift,MODE_SMMA,PRICE_MEDIAN,LOWER,2)&&iGator(NULL,piga,jaw_tf,jaw_shift,teeth_tf,teeth_shift,lips_tf,lips_shift,MODE_SMMA,PRICE_MEDIAN,LOWER,2)>iGator(NULL,piga,jaw_tf,jaw_shift,teeth_tf,teeth_shift,lips_tf,lips_shift,MODE_SMMA,PRICE_MEDIAN,LOWER,1)&&iGator(NULL,piga,jaw_tf,jaw_shift,teeth_tf,teeth_shift,lips_tf,lips_shift,MODE_SMMA,PRICE_MEDIAN,LOWER,1)>iGator(NULL,piga,jaw_tf,jaw_shift,teeth_tf,teeth_shift,lips_tf,lips_shift,MODE_SMMA,PRICE_MEDIAN,LOWER,0))
      {f4=1;}
    */
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Ichimoku indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Ichimoku(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_ICHIMOKU);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_ICHIMOKU, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_ICHIMOKU, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //15. Ichimoku Kinko Hyo (1)
      //Buy: Price crosses Senkou Span-B upwards; price is outside Senkou Span cloud
      //Sell: Price crosses Senkou Span-B downwards; price is outside Senkou Span cloud
      if (iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,1)>iClose(NULL,pich2,1)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,0)<=iClose(NULL,pich2,0)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANA,0)<iClose(NULL,pich2,0))
      {f15=1;}
      if (iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,1)<iClose(NULL,pich2,1)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,0)>=iClose(NULL,pich2,0)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANA,0)>iClose(NULL,pich2,0))
      {f15=-1;}
    */
    /*
      //16. Ichimoku Kinko Hyo (2)
      //Buy: Tenkan-sen crosses Kijun-sen upwards
      //Sell: Tenkan-sen crosses Kijun-sen downwards
      //VERSION EXISTS, IN THIS CASE PRICE MUSTN'T BE IN THE CLOUD!
      if (iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_TENKANSEN,1)<iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_KIJUNSEN,1)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_TENKANSEN,0)>=iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_KIJUNSEN,0))
      {f16=1;}
      if (iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_TENKANSEN,1)>iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_KIJUNSEN,1)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_TENKANSEN,0)<=iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_KIJUNSEN,0))
      {f16=-1;}
    */

    /*
      //17. Ichimoku Kinko Hyo (3)
      //Buy: Chinkou Span crosses chart upwards; price is ib the cloud
      //Sell: Chinkou Span crosses chart downwards; price is ib the cloud
      if ((iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_CHINKOUSPAN,pkijun+1)<iClose(NULL,pich2,pkijun+1)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_CHINKOUSPAN,pkijun+0)>=iClose(NULL,pich2,pkijun+0))&&((iClose(NULL,pich2,0)>iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANA,0)&&iClose(NULL,pich2,0)<iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,0))||(iClose(NULL,pich2,0)<iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANA,0)&&iClose(NULL,pich2,0)>iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,0))))
      {f17=1;}
      if ((iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_CHINKOUSPAN,pkijun+1)>iClose(NULL,pich2,pkijun+1)&&iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_CHINKOUSPAN,pkijun+0)<=iClose(NULL,pich2,pkijun+0))&&((iClose(NULL,pich2,0)>iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANA,0)&&iClose(NULL,pich2,0)<iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,0))||(iClose(NULL,pich2,0)<iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANA,0)&&iClose(NULL,pich2,0)>iIchimoku(NULL,pich,ptenkan,pkijun,psenkou,MODE_SENKOUSPANB,0))))
      {f17=-1;}
    */
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if MA indicator is on buy.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_MA(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_MA);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_MA, _chart.GetTf(), 0);
  if (signal_level == EMPTY)  signal_level  = GetStrategySignalLevel(INDI_MA, _chart.GetTf(), 0);
  double gap = signal_level * pip_size;

  switch (cmd) {
    case ORDER_TYPE_BUY:
      result  = ma_fast[period][CURR]   > ma_medium[period][CURR] + gap;
      result &= ma_medium[period][CURR] > ma_slow[period][CURR];
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= ma_fast[period][CURR] > ma_slow[period][CURR] + gap;
        if (METHOD(signal_method, 1)) result &= ma_medium[period][CURR] > ma_slow[period][CURR];
        if (METHOD(signal_method, 2)) result &= ma_slow[period][CURR] > ma_slow[period][PREV];
        if (METHOD(signal_method, 3)) result &= ma_fast[period][CURR] > ma_fast[period][PREV];
        if (METHOD(signal_method, 4)) result &= ma_fast[period][CURR] - ma_medium[period][CURR] > ma_medium[period][CURR] - ma_slow[period][CURR];
        if (METHOD(signal_method, 5)) result &= (ma_medium[period][PREV] < ma_slow[period][PREV] || ma_medium[period][FAR] < ma_slow[period][FAR]);
        if (METHOD(signal_method, 6)) result &= (ma_fast[period][PREV] < ma_medium[period][PREV] || ma_fast[period][FAR] < ma_medium[period][FAR]);
      }
      break;
    case ORDER_TYPE_SELL:
      result  = ma_fast[period][CURR]   < ma_medium[period][CURR] - gap;
      result &= ma_medium[period][CURR] < ma_slow[period][CURR];
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= ma_fast[period][CURR] < ma_slow[period][CURR] - gap;
        if (METHOD(signal_method, 1)) result &= ma_medium[period][CURR] < ma_slow[period][CURR];
        if (METHOD(signal_method, 2)) result &= ma_slow[period][CURR] < ma_slow[period][PREV];
        if (METHOD(signal_method, 3)) result &= ma_fast[period][CURR] < ma_fast[period][PREV];
        if (METHOD(signal_method, 4)) result &= ma_medium[period][CURR] - ma_fast[period][CURR] > ma_slow[period][CURR] - ma_medium[period][CURR];
        if (METHOD(signal_method, 5)) result &= (ma_medium[period][PREV] > ma_slow[period][PREV] || ma_medium[period][FAR] > ma_slow[period][FAR]);
        if (METHOD(signal_method, 6)) result &= (ma_fast[period][PREV] > ma_medium[period][PREV] || ma_fast[period][FAR] > ma_medium[period][FAR]);
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if MACD indicator is on buy.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_MACD(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_MA);
  UpdateIndicator(_chart, INDI_MACD);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_MACD, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_MACD, _chart.GetTf(), 0);
  double gap = signal_level * pip_size;
  switch (cmd) {
    /* TODO:
          //20. MACD (1)
          //VERSION EXISTS, THAT THE SIGNAL TO BUY IS TRUE ONLY IF MACD<0, SIGNAL TO SELL - IF MACD>0
          //Buy: MACD rises above the signal line
          //Sell: MACD falls below the signal line
          if(iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,1)<iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_SIGNAL,1)
          && iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,0)>=iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_SIGNAL,0))
          {f20=1;}
          if(iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,1)>iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_SIGNAL,1)
          && iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,0)<=iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_SIGNAL,0))
          {f20=-1;}

          //21. MACD (2)
          //Buy: crossing 0 upwards
          //Sell: crossing 0 downwards
          if(iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,1)<0&&iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,0)>=0)
          {f21=1;}
          if(iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,1)>0&&iMACD(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,MODE_MAIN,0)<=0)
          {f21=-1;}
    */
    case ORDER_TYPE_BUY:
      result = macd[period][CURR][MODE_MAIN] > macd[period][CURR][MODE_SIGNAL] + gap; // MACD rises above the signal line.
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= macd[period][FAR][MODE_MAIN] < macd[period][FAR][MODE_SIGNAL];
        if (METHOD(signal_method, 1)) result &= macd[period][CURR][MODE_MAIN] >= 0;
        if (METHOD(signal_method, 2)) result &= macd[period][PREV][MODE_MAIN] < 0;
        if (METHOD(signal_method, 3)) result &= ma_fast[period][CURR] > ma_fast[period][PREV];
        if (METHOD(signal_method, 4)) result &= ma_fast[period][CURR] > ma_medium[period][CURR];
      }
      break;
    case ORDER_TYPE_SELL:
      result = macd[period][CURR][MODE_MAIN] < macd[period][CURR][MODE_SIGNAL] - gap; // MACD falls below the signal line.
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= macd[period][FAR][MODE_MAIN] > macd[period][FAR][MODE_SIGNAL];
        if (METHOD(signal_method, 1)) result &= macd[period][CURR][MODE_MAIN] <= 0;
        if (METHOD(signal_method, 2)) result &= macd[period][PREV][MODE_MAIN] > 0;
        if (METHOD(signal_method, 3)) result &= ma_fast[period][CURR] < ma_fast[period][PREV];
        if (METHOD(signal_method, 4)) result &= ma_fast[period][CURR] < ma_medium[period][CURR];
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if MFI indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_MFI(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_MFI);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_MFI, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_MFI, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //18. Money Flow Index - MFI
      //Buy: Crossing 20 upwards
      //Sell: Crossing 20 downwards
      if(iMFI(NULL,pimfi,barsimfi,1)<20&&iMFI(NULL,pimfi,barsimfi,0)>=20)
      {f18=1;}
      if(iMFI(NULL,pimfi,barsimfi,1)>80&&iMFI(NULL,pimfi,barsimfi,0)<=80)
      {f18=-1;}]
    */
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Momentum indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Momentum(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_MOMENTUM);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_MOMENTUM, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_MOMENTUM, _chart.GetTf(), 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if OBV indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_OBV(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_OBV);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_OBV, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_OBV, _chart.GetTf(), 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if OSMA indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_OSMA(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_OSMA);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_OSMA, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_OSMA, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //22. Moving Average of Oscillator (MACD histogram) (1)
      //Buy: histogram is below zero and changes falling direction into rising (5 columns are taken)
      //Sell: histogram is above zero and changes its rising direction into falling (5 columns are taken)
      if(iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,4)<0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,3)<0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)<0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)<0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,0)<0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,4)>=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,3)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,3)>=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)<=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)<=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,0))
      {f22=1;}
      if(iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,4)>0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,3)>0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)>0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)>0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,0)>0&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,4)<=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,3)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,3)<=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)>=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)>=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,0))
      {f22=-1;}
    */

    /*
      //23. Moving Average of Oscillator (MACD histogram) (2)
      //To use the indicator it should be correlated with another trend indicator
      //Flag 23 is 1, when MACD histogram recommends to buy (i.e. histogram is sloping upwards)
      //Flag 23 is -1, when MACD histogram recommends to sell (i.e. histogram is sloping downwards)
      //3 columns are taken for calculation
      if(iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)<=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)<=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,0))
      {f23=1;}
      if(iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,2)>=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)&&iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,1)>=iOsMA(NULL,pimacd,fastpimacd,slowpimacd,signalpimacd,PRICE_CLOSE,0))
      {f23=-1;}
    */
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if RSI indicator is on buy.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level - signal level to consider the signal
 */
bool Trade_RSI(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_RSI);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_RSI, _chart.GetTf(), 0);
  if (signal_level == EMPTY)  signal_level  = GetStrategySignalLevel(INDI_RSI, _chart.GetTf(), 20);
  bool is_valid = fmin(fmin(rsi[period][CURR], rsi[period][PREV]), rsi[period][FAR]) > 0;
  switch (cmd) {
    case ORDER_TYPE_BUY:
      result = rsi[period][CURR] > 0 && rsi[period][CURR] < (50 - signal_level);
      if (result && VerboseTrace) {
        PrintFormat("RSI %s: %g vs %g", _chart.TfToString(), rsi[period][CURR], 50 - signal_level);
      }
      if (signal_method != 0) {
        result &= is_valid;
        if (METHOD(signal_method, 0)) result &= rsi[period][CURR] < rsi[period][PREV];
        if (METHOD(signal_method, 1)) result &= rsi[period][PREV] < rsi[period][FAR];
        if (METHOD(signal_method, 2)) result &= rsi[period][PREV] < (50 - signal_level);
        if (METHOD(signal_method, 3)) result &= rsi[period][FAR]  < (50 - signal_level);
        if (METHOD(signal_method, 4)) result &= rsi[period][CURR] - rsi[period][PREV] > rsi[period][PREV] - rsi[period][FAR];
        if (METHOD(signal_method, 5)) result &= rsi[period][FAR] > 50;
        //if (METHOD(signal_method, 5)) result &= Open[CURR] > Close[PREV];
        //if (METHOD(signal_method, 7)) result &= !RSI_On_Sell(M30);
      }
      break;
    case ORDER_TYPE_SELL:
      result = rsi[period][CURR] > 0 && rsi[period][CURR] > (50 + signal_level);
      if (result && VerboseTrace) {
        PrintFormat("RSI %s: %g vs %g", _chart.TfToString(), rsi[period][CURR], 50 - signal_level);
      }
      if (signal_method != 0) {
        result &= is_valid;
        if (METHOD(signal_method, 0)) result &= rsi[period][CURR] > rsi[period][PREV];
        if (METHOD(signal_method, 1)) result &= rsi[period][PREV] > rsi[period][FAR];
        if (METHOD(signal_method, 2)) result &= rsi[period][PREV] > (50 + signal_level);
        if (METHOD(signal_method, 3)) result &= rsi[period][FAR]  > (50 + signal_level);
        if (METHOD(signal_method, 4)) result &= rsi[period][PREV] - rsi[period][CURR] > rsi[period][FAR] - rsi[period][PREV];
        if (METHOD(signal_method, 5)) result &= rsi[period][FAR] < 50;
        //if (METHOD(signal_method, 5)) result &= Open[CURR] < Close[PREV];
        //if (METHOD(signal_method, 7)) result &= !RSI_On_Buy(M30);
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s: Signal: %s/%s/%d/%g", __FUNCTION_LINE__, EnumToString(cmd), _chart.TfToString(), signal_method, signal_level);
    PrintFormat("RSI %s: %s", _chart.TfToString(), Array::ArrToString2D(rsi, ",", Digits));
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if RVI indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_RVI(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_RVI);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_RVI, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_RVI, _chart.GetTf(), 20);
  switch (cmd) {
    /*
      //26. RVI
      //RECOMMENDED TO USE WITH A TREND INDICATOR
      //Buy: main line (green) crosses signal (red) upwards
      //Sell: main line (green) crosses signal (red) downwards
      if(iRVI(NULL,pirvi,pirviu,MODE_MAIN,1)<iRVI(NULL,pirvi,pirviu,MODE_SIGNAL,1)
      && iRVI(NULL,pirvi,pirviu,MODE_MAIN,0)>=iRVI(NULL,pirvi,pirviu,MODE_SIGNAL,0))
      {f26=1;}
      if(iRVI(NULL,pirvi,pirviu,MODE_MAIN,1)>iRVI(NULL,pirvi,pirviu,MODE_SIGNAL,1)
      && iRVI(NULL,pirvi,pirviu,MODE_MAIN,0)<=iRVI(NULL,pirvi,pirviu,MODE_SIGNAL,0))
      {f26=-1;}
    */
    case ORDER_TYPE_BUY:
      break;
    case ORDER_TYPE_SELL:
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if SAR indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal (in pips)
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_SAR(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_SAR);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_SAR, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_SAR, _chart.GetTf(), 0);
  double gap = signal_level * pip_size;
  switch (cmd) {
    case ORDER_TYPE_BUY:
      result = sar[period][CURR] + gap < Open[CURR] || sar[period][PREV] + gap < Open[PREV];
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= sar[period][PREV] - gap > _chart.GetAsk();
        if (METHOD(signal_method, 1)) result &= sar[period][CURR] < sar[period][PREV];
        if (METHOD(signal_method, 2)) result &= sar[period][CURR] - sar[period][PREV] <= sar[period][PREV] - sar[period][FAR];
        if (METHOD(signal_method, 3)) result &= sar[period][FAR] > _chart.GetAsk();
        if (METHOD(signal_method, 4)) result &= sar[period][CURR] <= Close[CURR];
        if (METHOD(signal_method, 5)) result &= sar[period][PREV] > Close[PREV];
        if (METHOD(signal_method, 6)) result &= sar[period][PREV] > Open[PREV];
      }
      if (result) {
        // FIXME: Convert into more flexible way.
        signals[DAILY][SAR1][period][ORDER_TYPE_BUY]++; signals[WEEKLY][SAR1][period][ORDER_TYPE_BUY]++;
        signals[MONTHLY][SAR1][period][ORDER_TYPE_BUY]++; signals[YEARLY][SAR1][period][ORDER_TYPE_BUY]++;
      }
      break;
    case ORDER_TYPE_SELL:
      result = sar[period][CURR] - gap > Open[CURR] || sar[period][PREV] - gap > Open[PREV];
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= sar[period][PREV] + gap < _chart.GetAsk();
        if (METHOD(signal_method, 1)) result &= sar[period][CURR] > sar[period][PREV];
        if (METHOD(signal_method, 2)) result &= sar[period][PREV] - sar[period][CURR] <= sar[period][FAR] - sar[period][PREV];
        if (METHOD(signal_method, 3)) result &= sar[period][FAR] < _chart.GetAsk();
        if (METHOD(signal_method, 4)) result &= sar[period][CURR] >= Close[CURR];
        if (METHOD(signal_method, 5)) result &= sar[period][PREV] < Close[PREV];
        if (METHOD(signal_method, 6)) result &= sar[period][PREV] < Open[PREV];
      }
      if (result) {
        // FIXME: Convert into more flexible way.
        signals[DAILY][SAR1][period][ORDER_TYPE_SELL]++; signals[WEEKLY][SAR1][period][ORDER_TYPE_SELL]++;
        signals[MONTHLY][SAR1][period][ORDER_TYPE_SELL]++; signals[YEARLY][SAR1][period][ORDER_TYPE_SELL]++;
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if StdDev indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_StdDev(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_STDDEV);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_STDDEV, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_STDDEV, _chart.GetTf(), 0.0);
  switch (cmd) {
    /*
      //27. Standard Deviation
      //Doesn't give independent signals. Is used to define volatility (trend strength).
      //Principle: the trend must be strengthened. Together with this Standard Deviation goes up.
      //Growth on 3 consecutive bars is analyzed
      //Flag is 1 when Standard Deviation rises, 0 - when no growth, -1 - never.
      if (iStdDev(NULL,pistd,pistdu,0,MODE_SMA,PRICE_CLOSE,2)<=iStdDev(NULL,pistd,pistdu,0,MODE_SMA,PRICE_CLOSE,1)&&iStdDev(NULL,pistd,pistdu,0,MODE_SMA,PRICE_CLOSE,1)<=iStdDev(NULL,pistd,pistdu,0,MODE_SMA,PRICE_CLOSE,0))
      {f27=1;}
    */
    case ORDER_TYPE_BUY:
      /*
        bool result = StdDev[period][CURR][LINE_LOWER] != 0.0 || StdDev[period][PREV][LINE_LOWER] != 0.0 || StdDev[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !StdDev_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= StdDev_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= StdDev_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= StdDev[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !StdDev_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = StdDev[period][CURR][LINE_UPPER] != 0.0 || StdDev[period][PREV][LINE_UPPER] != 0.0 || StdDev[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !StdDev_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= StdDev_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= StdDev_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= StdDev[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !StdDev_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if Stochastic indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_Stochastic(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_STOCHASTIC);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_STOCHASTIC, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_STOCHASTIC, _chart.GetTf(), 0.0);
  switch (cmd) {
      /* TODO:
            //   if(iStochastic(NULL,0,5,3,3,MODE_SMA,0,MODE_MAIN,0)>iStochastic(NULL,0,5,3,3,MODE_SMA,0,MODE_SIGNAL,0)) return(0);
            // if(stoch4h<stoch4h2){ //Sell signal
            // if(stoch4h>stoch4h2){//Buy signal

            //28. Stochastic Oscillator (1)
            //Buy: main lline rises above 20 after it fell below this point
            //Sell: main line falls lower than 80 after it rose above this point
            if(iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,1)<20
            &&iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,0)>=20)
            {f28=1;}
            if(iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,1)>80
            &&iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,0)<=80)
            {f28=-1;}

            //29. Stochastic Oscillator (2)
            //Buy: main line goes above the signal line
            //Sell: signal line goes above the main line
            if(iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,1)<iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_SIGNAL,1)
            && iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,0)>=iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_SIGNAL,0))
            {f29=1;}
            if(iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,1)>iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_SIGNAL,1)
            && iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_MAIN,0)<=iStochastic(NULL,pisto,pistok,pistod,istslow,MODE_EMA,0,MODE_SIGNAL,0))
            {f29=-1;}
      */
    case ORDER_TYPE_BUY:
      /*
        bool result = Stochastic[period][CURR][LINE_LOWER] != 0.0 || Stochastic[period][PREV][LINE_LOWER] != 0.0 || Stochastic[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !Stochastic_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= Stochastic_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= Stochastic_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= Stochastic[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !Stochastic_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = Stochastic[period][CURR][LINE_UPPER] != 0.0 || Stochastic[period][PREV][LINE_UPPER] != 0.0 || Stochastic[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !Stochastic_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= Stochastic_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= Stochastic_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= Stochastic[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !Stochastic_On_Buy(M30);
        */
    break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if WPR indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_WPR(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_WPR);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_WPR, _chart.GetTf(), 0);
  if (signal_level == EMPTY)  signal_level  = GetStrategySignalLevel(INDI_WPR, _chart.GetTf(), 0);

  switch (cmd) {
    case ORDER_TYPE_BUY:
      result = wpr[period][CURR] > 50 + signal_level;
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= wpr[period][CURR] < wpr[period][PREV];
        if (METHOD(signal_method, 1)) result &= wpr[period][PREV] < wpr[period][FAR];
        if (METHOD(signal_method, 2)) result &= wpr[period][PREV] > 50 + signal_level;
        if (METHOD(signal_method, 3)) result &= wpr[period][FAR]  > 50 + signal_level;
        if (METHOD(signal_method, 4)) result &= wpr[period][PREV] - wpr[period][CURR] > wpr[period][FAR] - wpr[period][PREV];
        if (METHOD(signal_method, 5)) result &= wpr[period][PREV] > 50 + signal_level + signal_level / 2;
      }
      /* TODO:

            //30. Williams Percent Range
            //Buy: crossing -80 upwards
            //Sell: crossing -20 downwards
            if (iWPR(NULL,piwpr,piwprbar,1)<-80&&iWPR(NULL,piwpr,piwprbar,0)>=-80)
            {f30=1;}
            if (iWPR(NULL,piwpr,piwprbar,1)>-20&&iWPR(NULL,piwpr,piwprbar,0)<=-20)
            {f30=-1;}
      */
      break;
    case ORDER_TYPE_SELL:
      result = wpr[period][CURR] < 50 - signal_level;
      if (signal_method != 0) {
        if (METHOD(signal_method, 0)) result &= wpr[period][CURR] > wpr[period][PREV];
        if (METHOD(signal_method, 1)) result &= wpr[period][PREV] > wpr[period][FAR];
        if (METHOD(signal_method, 2)) result &= wpr[period][PREV] < 50 - signal_level;
        if (METHOD(signal_method, 3)) result &= wpr[period][FAR]  < 50 - signal_level;
        if (METHOD(signal_method, 4)) result &= wpr[period][CURR] - wpr[period][PREV] > wpr[period][PREV] - wpr[period][FAR];
        if (METHOD(signal_method, 5)) result &= wpr[period][PREV] > 50 - signal_level - signal_level / 2;
      }
      break;
  }
  result &= signal_method <= 0 || Convert::ValueToOp(curr_trend) == cmd;
  if (VerboseTrace && result) {
    PrintFormat("%s:%d: Signal: %d/%d/%d/%g", __FUNCTION__, __LINE__, cmd, _chart.GetTf(), signal_method, signal_level);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Check if ZigZag indicator is on buy or sell.
 *
 * @param
 *   cmd (int) - type of trade order command
 *   period (int) - period to check for
 *   signal_method (int) - signal method to use by using bitwise AND operation
 *   signal_level (double) - signal level to consider the signal
 */
bool Trade_ZigZag(Chart *_chart, ENUM_ORDER_TYPE cmd, int signal_method = EMPTY, double signal_level = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false; uint period = _chart.TfToIndex();
  UpdateIndicator(_chart, INDI_ZIGZAG);
  if (signal_method == EMPTY) signal_method = GetStrategySignalMethod(INDI_ZIGZAG, _chart.GetTf(), 0);
  if (signal_level  == EMPTY) signal_level  = GetStrategySignalLevel(INDI_ZIGZAG, _chart.GetTf(), 0.0);
  switch (cmd) {
    case ORDER_TYPE_BUY:
      /*
        bool result = ZigZag[period][CURR][LINE_LOWER] != 0.0 || ZigZag[period][PREV][LINE_LOWER] != 0.0 || ZigZag[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] > Close[CURR];
        if (METHOD(signal_method, 1)) result &= !ZigZag_On_Sell(tf);
        if (METHOD(signal_method, 2)) result &= ZigZag_On_Buy(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= ZigZag_On_Buy(M30);
        if (METHOD(signal_method, 4)) result &= ZigZag[period][FAR][LINE_LOWER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !ZigZag_On_Sell(M30);
        */
    break;
    case ORDER_TYPE_SELL:
      /*
        bool result = ZigZag[period][CURR][LINE_UPPER] != 0.0 || ZigZag[period][PREV][LINE_UPPER] != 0.0 || ZigZag[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 0)) result &= Open[CURR] < Close[CURR];
        if (METHOD(signal_method, 1)) result &= !ZigZag_On_Buy(tf);
        if (METHOD(signal_method, 2)) result &= ZigZag_On_Sell(fmin(period + 1, M30));
        if (METHOD(signal_method, 3)) result &= ZigZag_On_Sell(M30);
        if (METHOD(signal_method, 4)) result &= ZigZag[period][FAR][LINE_UPPER] != 0.0;
        if (METHOD(signal_method, 5)) result &= !ZigZag_On_Buy(M30);
        */
    break;
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/* END: INDICATOR FUNCTIONS */

/**
 * Check for market condition.
 *
 * @param
 *   _chart (Chart) - chart to use
 *   cmd (int) - trade command
 *   condition (int) - condition to check by using bitwise AND operation
 *   default_value (bool) - default value to set, if false - return the opposite
 */
bool CheckMarketCondition1(Chart *_chart, ENUM_ORDER_TYPE cmd, int condition = 0, bool default_value = true) {
  DEBUG_CHECKPOINT_ADD
  bool result = true;
  if (condition == 0) {
    return result;
  }
  uint period = _chart.TfToIndex();
  if (VerboseTrace) terminal.Logger().Trace(StringFormat("%s(%s, %d)", EnumToString(cmd), _chart.TfToString(), condition), __FUNCTION_LINE__);
  Market::RefreshRates(); // ?
  if (METHOD(condition,  0)) result &= ((cmd == ORDER_TYPE_BUY && Open[CURR] > Close[PREV]) || (cmd == ORDER_TYPE_SELL && Open[CURR] < Close[PREV]));
  if (METHOD(condition,  1)) result &= UpdateIndicator(_chart, INDI_SAR)       && ((cmd == ORDER_TYPE_BUY && sar[period][CURR] < Open[0]) || (cmd == ORDER_TYPE_SELL && sar[period][CURR] > Open[0]));
  if (METHOD(condition,  2)) result &= UpdateIndicator(_chart, INDI_RSI)       && ((cmd == ORDER_TYPE_BUY && rsi[period][CURR] < 50) || (cmd == ORDER_TYPE_SELL && rsi[period][CURR] > 50));
  if (METHOD(condition,  3)) result &= UpdateIndicator(_chart, INDI_MA)        && ((cmd == ORDER_TYPE_BUY && _chart.GetAsk() > ma_slow[period][CURR]) || (cmd == ORDER_TYPE_SELL && _chart.GetAsk() < ma_slow[period][CURR]));
  if (METHOD(condition,  4)) result &= UpdateIndicator(_chart, INDI_MA)        && ((cmd == ORDER_TYPE_BUY && ma_slow[period][CURR] > ma_slow[period][PREV]) || (cmd == ORDER_TYPE_SELL && ma_slow[period][CURR] < ma_slow[period][PREV]));
  if (METHOD(condition,  5)) result &= ((cmd == ORDER_TYPE_BUY && _chart.GetAsk() < Open[CURR]) || (cmd == ORDER_TYPE_SELL && _chart.GetAsk() > Open[CURR]));
  if (METHOD(condition,  6)) result &= UpdateIndicator(_chart, INDI_BANDS)     && ((cmd == ORDER_TYPE_BUY && Open[CURR] < bands[period][CURR][BAND_BASE]) || (cmd == ORDER_TYPE_SELL && Open[CURR] > bands[period][CURR][BAND_BASE]));
  if (METHOD(condition,  7)) result &= UpdateIndicator(_chart, INDI_ENVELOPES) && ((cmd == ORDER_TYPE_BUY && Open[CURR] < envelopes[period][CURR][MODE_MAIN]) || (cmd == ORDER_TYPE_SELL && Open[CURR] > envelopes[period][CURR][MODE_MAIN]));
  if (METHOD(condition,  8)) result &= UpdateIndicator(_chart, INDI_DEMARKER)  && ((cmd == ORDER_TYPE_BUY && demarker[period][CURR] < 0.5) || (cmd == ORDER_TYPE_SELL && demarker[period][CURR] > 0.5));
  if (METHOD(condition,  9)) result &= UpdateIndicator(_chart, INDI_WPR)       && ((cmd == ORDER_TYPE_BUY && wpr[period][CURR] > 50) || (cmd == ORDER_TYPE_SELL && wpr[period][CURR] < 50));
  if (METHOD(condition, 10)) result &= cmd == Convert::ValueToOp(curr_trend);
  if (!default_value) result = !result;
  return result;
}

/**
 * Check for market event.
 *
 * @param
 *   chart (Chart) - chart to use
 *   cmd (int) - trade command
 *   condition (int) - condition to check by using bitwise AND operation
 *   default_value (bool) - default value to set, if false - return the opposite
 */
bool CheckMarketEvent(Chart *_chart, ENUM_ORDER_TYPE cmd = EMPTY, int condition = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  bool result = false;
  uint period = _chart.TfToIndex();
  ENUM_TIMEFRAMES tf = _chart.GetTf();
  if (cmd == EMPTY || condition == EMPTY) return (false);
  if (VerboseTrace) terminal.Logger().Trace(StringFormat("%s(%s, %d)", EnumToString(cmd), _chart.TfToString(), condition), __FUNCTION_LINE__);
  switch (condition) {
    case C_AC_BUY_SELL:
      result = Trade_AC(_chart, cmd);
      break;
    case C_AD_BUY_SELL:
      result = Trade_AD(_chart, cmd);
      break;
    case C_ADX_BUY_SELL:
      result = Trade_ADX(_chart, cmd);
      break;
    case C_ALLIGATOR_BUY_SELL:
      result = Trade_Alligator(_chart, cmd);
      break;
    case C_ATR_BUY_SELL:
      result = Trade_ATR(_chart, cmd);
      break;
    case C_AWESOME_BUY_SELL:
      result = Trade_Awesome(_chart, cmd);
      break;
    case C_BANDS_BUY_SELL:
      result = Trade_Bands(_chart, cmd);
      break;
    case C_BPOWER_BUY_SELL:
      result = Trade_BPower(_chart, cmd);
      break;
    case C_BREAKAGE_BUY_SELL:
      result = Trade_Breakage(_chart, cmd);
      break;
    case C_CCI_BUY_SELL:
      result = Trade_CCI(_chart, cmd);
      break;
    case C_DEMARKER_BUY_SELL:
      result = Trade_DeMarker(_chart, cmd);
      break;
    case C_ENVELOPES_BUY_SELL:
      result = Trade_Envelopes(_chart, cmd);
      break;
    case C_FORCE_BUY_SELL:
      result = Trade_Force(_chart, cmd);
      break;
    case C_FRACTALS_BUY_SELL:
      result = Trade_Fractals(_chart, cmd);
      break;
    case C_GATOR_BUY_SELL:
      result = Trade_Gator(_chart, cmd);
      break;
    case C_ICHIMOKU_BUY_SELL:
      result = Trade_Ichimoku(_chart, cmd);
      break;
    case C_MA_BUY_SELL:
      result = Trade_MA(_chart, cmd);
      break;
    case C_MACD_BUY_SELL:
      result = Trade_MACD(_chart, cmd);
      break;
    case C_MFI_BUY_SELL:
      result = Trade_MFI(_chart, cmd);
      break;
    case C_OBV_BUY_SELL:
      result = Trade_OBV(_chart, cmd);
      break;
    case C_OSMA_BUY_SELL:
      result = Trade_OSMA(_chart, cmd);
      break;
    case C_RSI_BUY_SELL:
      result = Trade_RSI(_chart, cmd);
      break;
    case C_RVI_BUY_SELL:
      result = Trade_RVI(_chart, cmd);
      break;
    case C_SAR_BUY_SELL:
      result = Trade_SAR(_chart, cmd);
      break;
    case C_STDDEV_BUY_SELL:
      result = Trade_StdDev(_chart, cmd);
      break;
    case C_STOCHASTIC_BUY_SELL:
      result = Trade_Stochastic(_chart, cmd);
      break;
    case C_WPR_BUY_SELL:
      result = Trade_WPR(_chart, cmd);
      break;
    case C_ZIGZAG_BUY_SELL:
      result = Trade_ZigZag(_chart, cmd);
      break;
    case C_MA_FAST_SLOW_OPP: // MA Fast&Slow are in opposite directions.
      UpdateIndicator(_chart, INDI_MA);
      return
        (cmd == ORDER_TYPE_BUY && ma_fast[period][CURR] < ma_fast[period][PREV] && ma_slow[period][CURR] > ma_slow[period][PREV]) ||
        (cmd == ORDER_TYPE_SELL && ma_fast[period][CURR] > ma_fast[period][PREV] && ma_slow[period][CURR] < ma_slow[period][PREV]);
    case C_MA_FAST_MED_OPP: // MA Fast&Med are in opposite directions.
      UpdateIndicator(_chart, INDI_MA);
      return
        (cmd == ORDER_TYPE_BUY && ma_fast[period][CURR] < ma_fast[period][PREV] && ma_medium[period][CURR] > ma_medium[period][PREV]) ||
        (cmd == ORDER_TYPE_SELL && ma_fast[period][CURR] > ma_fast[period][PREV] && ma_medium[period][CURR] < ma_medium[period][PREV]);
    case C_MA_MED_SLOW_OPP: // MA Med&Slow are in opposite directions.
      UpdateIndicator(_chart, INDI_MA);
      return
        (cmd == ORDER_TYPE_BUY && ma_medium[period][CURR] < ma_medium[period][PREV] && ma_slow[period][CURR] > ma_slow[period][PREV]) ||
        (cmd == ORDER_TYPE_SELL && ma_medium[period][CURR] > ma_medium[period][PREV] && ma_slow[period][CURR] < ma_slow[period][PREV]);
#ifdef __advanced__
    case C_CUSTOM1_BUY_SELL:
    case C_CUSTOM2_BUY_SELL:
    case C_CUSTOM3_BUY_SELL:
      if (condition == C_CUSTOM1_BUY_SELL) condition = CloseConditionCustom1Method;
      if (condition == C_CUSTOM2_BUY_SELL) condition = CloseConditionCustom2Method;
      if (condition == C_CUSTOM3_BUY_SELL) condition = CloseConditionCustom3Method;
      result = false;
      if (condition != 0) {
        if (METHOD(condition, 0)) result |= CheckMarketEvent(_chart, cmd, C_MA_BUY_SELL);
        if (METHOD(condition, 1)) result |= CheckMarketEvent(_chart, cmd, C_MACD_BUY_SELL);
        if (METHOD(condition, 2)) result |= CheckMarketEvent(_chart, cmd, C_ALLIGATOR_BUY_SELL);
        if (METHOD(condition, 3)) result |= CheckMarketEvent(_chart, cmd, C_RSI_BUY_SELL);
        if (METHOD(condition, 4)) result |= CheckMarketEvent(_chart, cmd, C_SAR_BUY_SELL);
        if (METHOD(condition, 5)) result |= CheckMarketEvent(_chart, cmd, C_BANDS_BUY_SELL);
        if (METHOD(condition, 6)) result |= CheckMarketEvent(_chart, cmd, C_ENVELOPES_BUY_SELL);
        if (METHOD(condition, 7)) result |= CheckMarketEvent(_chart, cmd, C_DEMARKER_BUY_SELL);
        if (METHOD(condition, 8)) result |= CheckMarketEvent(_chart, cmd, C_WPR_BUY_SELL);
        if (METHOD(condition, 9)) result |= CheckMarketEvent(_chart, cmd, C_FRACTALS_BUY_SELL);
      }
      // Message("Condition: " + condition + ", result: " + result);
      break;
    case C_CUSTOM4_MARKET_COND:
    case C_CUSTOM5_MARKET_COND:
    case C_CUSTOM6_MARKET_COND:
      if (condition == C_CUSTOM4_MARKET_COND) condition = CloseConditionCustom4Method;
      if (condition == C_CUSTOM5_MARKET_COND) condition = CloseConditionCustom5Method;
      if (condition == C_CUSTOM6_MARKET_COND) condition = CloseConditionCustom6Method;
      if (cmd == ORDER_TYPE_BUY)  result = CheckMarketCondition1(_chart, ORDER_TYPE_SELL, condition);
      if (cmd == ORDER_TYPE_SELL) result = CheckMarketCondition1(_chart, ORDER_TYPE_BUY, condition);
    break;
#endif
    case C_EVENT_NONE:
    default:
      result = false;
  }
  DEBUG_CHECKPOINT_POP
  return result;
}

/**
 * Check if order match has minimum gap in pips configured by MinPipGap parameter.
 *
 * @param
 *   int sid - type of order strategy to check for (see: ENUM STRATEGY TYPE)
 */
bool CheckMinPipGap(int sid) {
  double diff;
  for (int order = 0; order < OrdersTotal(); order++) {
    if (Order::OrderSelect(order, SELECT_BY_POS, MODE_TRADES)) {
       if (Order::OrderMagicNumber() == MagicNumber + sid && Order::OrderSymbol() == market.GetSymbol()) {
         diff = Convert::GetValueDiffInPips(Order::OrderOpenPrice(), market.GetOpenOffer(Order::OrderType()), true);
         /*
         if (VerboseDebug) {
           PrintFormat("Ticket: #%d, %s, Gap: %g (%g-%g)",
              Order::OrderTicket(), Order::OrderTypeToString(Order::OrderType()), diff,
              Order::OrderOpenPrice(), market.GetOpenPrice()
            );
         }
         */
         if (diff < MinPipGap) {
           return (false);
         }
       }
    } else if (VerboseDebug) {
      Msg::ShowText(
          StringFormat("Cannot select order. Strategy type: %s, pos: %d, msg: %s.",
            sid, order, terminal.GetErrorText(err_code)),
          "Error", __FUNCTION__, __LINE__, VerboseErrors
      );
    }
  }
  return (true);
}

/**
 * Check orders for certain checks.
 */
void CheckOrders() {
  double elapsed_h;
  for (uint i = 0; i < Orders::OrdersTotal(); i++) {
    if (!Order::OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) { continue; }
    if (CheckOurMagicNumber() && Order::OrderOpenTime() > 0) {
      if (CloseOrderAfterXHours != 0) {
        elapsed_h = ((double) (TimeCurrent() - Order::OrderOpenTime()) / 60 / 60);
        if (elapsed_h > CloseOrderAfterXHours) {
          if (Order::GetOrderProfit() > 0) {
            TaskAddCloseOrder(OrderTicket(), R_ORDER_EXPIRED);
          }
        }
        else if (CloseOrderAfterXHours < 0 && elapsed_h > -CloseOrderAfterXHours) {
          TaskAddCloseOrder(OrderTicket(), R_ORDER_EXPIRED);
        }
      }
      /*
      if (Order::OrderTakeProfit()) {
      }
      */
    }
  } // end: for
}

/**
 * Update trailing stops for opened orders.
 */
bool UpdateTrailingStops(Trade *_trade) {
  // Check result of executed orders.
  bool result = true;
  // New StopLoss/TakeProfit.
  double prev_sl, prev_tp;
  double new_sl, new_tp;
  double trail_sl, trail_tp;
  int sid;

   // Check if bar time has been changed since last time.
   /*
   int bar_time = iTime(NULL, PERIOD_M1, 0);
   if (bar_time == last_trail_update) {
     return;
   } else {
     last_trail_update = bar_time;
   }*/

  #ifdef __profiler__ PROFILER_START #endif

   market.RefreshRates();
   for (int i = 0; i < OrdersTotal(); i++) {
     if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) { continue; }
      if (OrderSymbol() == Symbol() && CheckOurMagicNumber()) {
        sid = OrderMagicNumber() - MagicNumber;
        // order_stop_loss = NormalizeDouble(Misc::If(Order::OrderDirection(OrderType()) > 0 || OrderStopLoss() != 0.0, OrderStopLoss(), 999999), pip_digits);
        // FIXME
        // Make sure we get the minimum distance to StopLevel and freezing distance.
        // See: https://book.mql4.com/appendix/limits
        if (MinimalizeLosses) {
        // if (MinimalizeLosses && Order::GetOrderProfit() > GetMinStopLevel()) {
          if ((OrderType() == ORDER_TYPE_BUY && OrderStopLoss() < market.GetBid()) ||
             (OrderType() == ORDER_TYPE_SELL && OrderStopLoss() > market.GetAsk())) {
            result = OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() - OrderCommission() * Point, OrderTakeProfit(), 0, Order::GetOrderColor(EMPTY, ColorBuy, ColorSell));
            if (!result && err_code > 1) {
             if (VerboseErrors) Print(__FUNCTION__, ": Error: OrderModify(): [MinimalizeLosses] ", Terminal::GetErrorText(err_code));
               if (VerboseDebug)
                 Print(__FUNCTION__ + ": Error: OrderModify(", OrderTicket(), ", ", OrderOpenPrice(), ", ", OrderOpenPrice() - OrderCommission() * Point, ", ", OrderTakeProfit(), ", ", 0, ", ", Order::GetOrderColor(EMPTY, ColorBuy, ColorSell), "); ");
            } else {
              if (VerboseTrace) Print(__FUNCTION__ + ": MinimalizeLosses: ", Order::OrderTypeToString((ENUM_ORDER_TYPE) OrderType()));
            }
          }
        }

        // Get previous stops.
        prev_sl = Order::OrderStopLoss();
        prev_tp = Order::OrderTakeProfit();
        // @todo: Use RiskMarginPerOrder with equity?
        // Get dynamic stops.
        trail_sl = GetTrailingValue(_trade, Order::OrderType(), ORDER_SL, sid, Order::OrderStopLoss(), true);
        // Get new stops.
        if (
          (prev_sl == 0) ||
          (Order::OrderType() == ORDER_TYPE_BUY && trail_sl < prev_sl) ||
          (Order::OrderType() == ORDER_TYPE_SELL && trail_sl > prev_sl)
        ) {
          new_sl = _trade.CalcBestSLTP(trail_sl, StopLossMax, RiskMarginPerOrder, ORDER_SL);
        }
        else {
          new_sl = trail_sl;
        }
        if (new_sl != prev_sl) {
          // Re-calculate TP only when SL is changed.
          trail_tp = GetTrailingValue(_trade, Order::OrderType(), ORDER_TP, sid, Order::OrderTakeProfit(), true);
          new_tp = TakeProfitMax > 0 ? _trade.CalcBestSLTP(trail_tp, TakeProfitMax, 0, ORDER_TP) : trail_tp;
        }

        if (!market.TradeOpAllowed(Order::OrderType(), new_sl, new_tp)) {
          if (VerboseDebug) {
            PrintFormat("%s(): fabs(%f - %f) = %f > %f || fabs(%f - %f) = %f > %f",
                __FUNCTION__,
                Order::OrderStopLoss(), new_sl, fabs(Order::OrderStopLoss() - new_sl), MinPipChangeToTrade * pip_size,
                Order::OrderTakeProfit(), new_tp, fabs(Order::OrderTakeProfit() - new_tp), MinPipChangeToTrade * pip_size);
          }
          return (false);
        }
        else if (new_sl == Order::OrderStopLoss() && new_tp == Order::OrderTakeProfit()) {
          return (false);
        }
        // @todo
        // Perform update on pip change.
        // Perform update on change only.
        // MQL5: ORDER_TIME_GTC
        // datetime expiration=TimeTradeServer()+PeriodSeconds(PERIOD_D1);

        if (fabs(prev_sl - new_sl) > MinPipChangeToTrade * pip_size || fabs(prev_tp - new_tp) > MinPipChangeToTrade * pip_size) {
          result = OrderModify(OrderTicket(), OrderOpenPrice(), new_sl, new_tp, 0, Order::GetOrderColor(EMPTY, ColorBuy, ColorSell));
          if (!result) {
            err_code = GetLastError();
            if (err_code > 1) {
              Msg::ShowText(Terminal::GetErrorText(err_code), "Error", __FUNCTION__, __LINE__, VerboseErrors);
              Msg::ShowText(
                StringFormat("OrderModify(%d, %g, %g, %g, %d, %d); Ask:%g/Bid:%g; Gap:%g pips",
                OrderTicket(), OrderOpenPrice(), new_sl, new_tp, 0, Order::GetOrderColor(EMPTY, ColorBuy, ColorSell), market.GetAsk(), market.GetBid(), market.GetTradeDistanceInPips()),
                "Debug", __FUNCTION__, __LINE__, VerboseDebug
              );
              Msg::ShowText(
                StringFormat("%s(): fabs(%g - %g) = %g > %g || fabs(%g - %g) = %g > %g",
                __FUNCTION__,
                OrderStopLoss(), new_sl, fabs(OrderStopLoss() - new_sl), MinPipChangeToTrade * pip_size,
                OrderTakeProfit(), new_tp, fabs(OrderTakeProfit() - new_tp), MinPipChangeToTrade * pip_size),
                "Debug", __FUNCTION__, __LINE__, VerboseDebug);
            }
          } else {
            // if (VerboseTrace) Print("UpdateTrailingStops(): OrderModify(): ", Order::GetOrderToText());
          }
        }
      }
  } // end: for
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Calculate the new trailing stop. If calculation fails, use the previous one.
 *
 * @params:
 *   _chart (Chart)
 *    Chart to use.
 *   cmd (int)
 *    Command for trade operation.
 *   mode (ENUM_ORDER_PROPERTY_DOUBLE)
 *    Type of value (ORDER_SL or ORDER_TP).
 *   order_type (int)
 *    Value of strategy type. See: ENUM_STRATEGY_TYPE
 *   previous (double)
 *    Previous trailing value.
 *   existing (bool)
 *    Set to true if the calculation is for particular existing order, so additional local variables are available.
 */
double GetTrailingValue(Trade *_trade, ENUM_ORDER_TYPE cmd, ENUM_ORDER_PROPERTY_DOUBLE mode = ORDER_SL, int order_type = 0, double previous = 0, bool existing = false) {
  DEBUG_CHECKPOINT_ADD
  Chart *_chart = _trade.Chart();
  ENUM_TIMEFRAMES tf = _chart.GetTf();
  uint period = _chart.TfToIndex();
  string symbol = existing ? OrderSymbol() : _chart.GetSymbol();
  double diff;
  bool one_way; // Move trailing stop only in one mode.
  double new_value = 0;
  double extra_trail = 0;
  if (existing && TrailingStopAddPerMinute > 0 && OrderOpenTime() > 0) {
    double min_elapsed = (double) ((TimeCurrent() - OrderOpenTime()) / 60);
    extra_trail =+ min_elapsed * TrailingStopAddPerMinute;
    if (VerboseDebug) {
      PrintFormat("%s:%d: extra_trail += %g * %g => %g",
        __FUNCTION__, __LINE__, min_elapsed, TrailingStopAddPerMinute, extra_trail);
    }
  }
  int direction = Order::OrderDirection(cmd, mode);
  double trail = (TrailingStop + extra_trail) * pip_size;
  double default_trail = (cmd == ORDER_TYPE_BUY ? _chart.GetBid() : _chart.GetAsk()) + trail * direction;
  int method = GetTrailingMethod(order_type, mode);
  one_way = method > 0;

  if (VerboseDebug) {
    PrintFormat("%s:%d: %s, %s, %d, %g): method = %d, trail = (%d + %g) * %g = %g",
      __FUNCTION__, __LINE__, Order::OrderTypeToString(cmd), EnumToString(mode), order_type, previous,
      method,
      TrailingStop, extra_trail, pip_size, trail);
  }
  // TODO: Make starting point dynamic: Open[CURR], Open[PREV], Open[FAR], Close[PREV], Close[FAR], ma_fast[CURR], ma_medium[CURR], ma_slow[CURR]
   double highest_ma, lowest_ma;
   double ask = _chart.GetAsk();
   double bid = _chart.GetBid();
   switch (method) {
     case T_NONE: // 0: None.
       new_value = _trade.CalcOrderSLTP(mode == ORDER_TP ? TakeProfitMax : StopLossMax, cmd, mode);
       break;
     case T1_FIXED: // 1: Dynamic fixed.
     case T2_FIXED:
       new_value = default_trail;
       break;
     case T1_OPEN_PREV: // 2: Previous open price.
     case T2_OPEN_PREV:
       diff = fabs(Open[CURR] - iOpen(symbol, tf, PREV));
       new_value = Open[CURR] + diff * direction;
       if (VerboseDebug) {
          PrintFormat("%s: T_OPEN_PREV: open = %g, prev_open = %g, diff = %g, new_value = %g",
            __FUNCTION__, Open[CURR], iOpen(symbol, tf, PREV), diff, new_value);
       }
       break;
     case T1_2_BARS_PEAK: // 3: Two bars peak.
     case T2_2_BARS_PEAK:
       diff = fmax(_chart.GetPeakPrice(2, MODE_HIGH) - Open[CURR], Open[CURR] - _chart.GetPeakPrice(2, MODE_LOW));
       new_value = Open[CURR] + diff * direction;
       break;
     case T1_5_BARS_PEAK: // 4: Five bars peak.
     case T2_5_BARS_PEAK:
       diff = fmax(_chart.GetPeakPrice(5, MODE_HIGH) - Open[CURR], Open[CURR] - _chart.GetPeakPrice(5, MODE_LOW));
       new_value = Open[CURR] + diff * direction;
       break;
     case T1_10_BARS_PEAK: // 5: Ten bars peak.
     case T2_10_BARS_PEAK:
       diff = fmax(_chart.GetPeakPrice(10, MODE_HIGH) - Open[CURR], Open[CURR] - _chart.GetPeakPrice(10, MODE_LOW));
       new_value = Open[CURR] + diff * direction;
       break;
     case T1_50_BARS_PEAK: // 6: 50 bars peak.
     case T2_50_BARS_PEAK:
       diff = fmax(_chart.GetPeakPrice(50, MODE_HIGH) - Open[CURR], Open[CURR] - _chart.GetPeakPrice(50, MODE_LOW));
       new_value = Open[CURR] + diff * direction;
       // @todo: Text non-Open values.
       break;
     case T1_150_BARS_PEAK: // 7: 150 bars peak.
     case T2_150_BARS_PEAK:
       diff = fmax(_chart.GetPeakPrice(150, MODE_HIGH) - Open[CURR], Open[CURR] - _chart.GetPeakPrice(150, MODE_LOW));
       new_value = Open[CURR] + diff * direction;
       break;
     case T1_HALF_200_BARS: // 8: 200 bars peak.
     case T2_HALF_200_BARS:
       diff = fmax(_chart.GetPeakPrice(200, MODE_HIGH) - Open[CURR], Open[CURR] - _chart.GetPeakPrice(200, MODE_LOW));
       new_value = Open[CURR] + diff/2 * direction;
       break;
     case T1_HALF_PEAK_OPEN: // 9: Half price peak.
     case T2_HALF_PEAK_OPEN:
       if (existing) {
         // Get the number of bars for the tf since open. Zero means that the order was opened during the current bar.
         int BarShiftOfTradeOpen = iBarShift(symbol, tf, OrderOpenTime(), false);
         // Get the high price from the bar with the given tf index
         double highest_open = _chart.GetPeakPrice(BarShiftOfTradeOpen + 1, MODE_HIGH);
         double lowest_open = _chart.GetPeakPrice(BarShiftOfTradeOpen + 1, MODE_LOW);
         diff = fmax(highest_open - Open[CURR], Open[CURR] - lowest_open);
         new_value = Open[CURR] + diff/2 * direction;
       }
       break;
     case T1_MA_F_PREV: // 10: MA Small (Previous).
     case T2_MA_F_PREV:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(ask - ma_fast[period][PREV]);
       new_value = ask + diff * direction;
       break;
     case T1_MA_F_FAR: // 11: MA Small (Far) + trailing stop. Optimize together with: MA_Shift_Far.
     case T2_MA_F_FAR:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(ask - ma_fast[period][FAR]);
       new_value = ask + diff * direction;
       break;
     case T1_MA_F_TRAIL: // 12: MA Fast (Current) + trailing stop. Works fine.
     case T2_MA_F_TRAIL:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(ask - ma_fast[period][CURR]);
       new_value = ask + (diff + trail) * direction;
       break;
     case T1_MA_F_FAR_TRAIL: // 13: MA Fast (Far) + trailing stop. Works fine (SL pf: 1.26 for MA).
     case T2_MA_F_FAR_TRAIL:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(Open[CURR] - ma_fast[period][FAR]);
       new_value = Open[CURR] + (diff + trail) * direction;
       break;
     case T1_MA_M: // 14: MA Medium (Current).
     case T2_MA_M:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(ask - ma_medium[period][CURR]);
       new_value = ask + diff * direction;
       break;
     case T1_MA_M_FAR: // 15: MA Medium (Far)
     case T2_MA_M_FAR:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(ask - ma_medium[period][FAR]);
       new_value = ask + diff * direction;
       break;
     case T1_MA_M_LOW: // 16: Lowest/highest value of MA Medium. Optimized (SL pf: 1.39 for MA).
     case T2_MA_M_LOW:
       UpdateIndicator(_chart, INDI_MA);
       diff = fmax(Array::HighestArrValue2(ma_medium, period) - Open[CURR], Open[CURR] - Array::LowestArrValue2(ma_medium, period));
       new_value = Open[CURR] + diff * direction;
       break;
     case T1_MA_M_TRAIL: // 17: MA Small (Current) + trailing stop. Works fine (SL pf: 1.26 for MA).
     case T2_MA_M_TRAIL:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(Open[CURR] - ma_medium[period][CURR]);
       new_value = Open[CURR] + (diff + trail) * direction;
       break;
     case T1_MA_M_FAR_TRAIL: // 18: MA Small (Far) + trailing stop. Optimized (SL pf: 1.29 for MA).
     case T2_MA_M_FAR_TRAIL:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(Open[CURR] - ma_medium[period][FAR]);
       new_value = Open[CURR] + (diff + trail) * direction;
       if (VerboseDebug && new_value < 0) {
         PrintFormat("%s(): diff = fabs(%g - %g); new_value = %g + (%g + %g) * %g => %g",
             __FUNCTION__, Open[CURR], ma_medium[period][FAR], Open[CURR], diff, trail, direction, new_value);
       }
       break;
     case T1_MA_S: // 19: MA Slow (Current).
     case T2_MA_S:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(ask - ma_slow[period][CURR]);
       // new_value = ma_slow[period][CURR];
       new_value = ask + diff * direction;
       break;
     case T1_MA_S_FAR: // 20: MA Slow (Far).
     case T2_MA_S_FAR:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(ask - ma_slow[period][FAR]);
       // new_value = ma_slow[period][FAR];
       new_value = ask + diff * direction;
       break;
     case T1_MA_S_TRAIL: // 21: MA Slow (Current) + trailing stop. Optimized (SL pf: 1.29 for MA, PT pf: 1.23 for MA).
     case T2_MA_S_TRAIL:
       UpdateIndicator(_chart, INDI_MA);
       diff = fabs(Open[CURR] - ma_slow[period][CURR]);
       new_value = Open[CURR] + (diff + trail) * direction;
       break;
     case T1_MA_FMS_PEAK: // 22: Lowest/highest value of all MAs. Works fine (SL pf: 1.39 for MA, PT pf: 1.23 for MA).
     case T2_MA_FMS_PEAK:
       UpdateIndicator(_chart, INDI_MA);
       highest_ma = fabs(fmax(fmax(Array::HighestArrValue2(ma_fast, period), Array::HighestArrValue2(ma_medium, period)), Array::HighestArrValue2(ma_slow, period)));
       lowest_ma = fabs(fmin(fmin(Array::LowestArrValue2(ma_fast, period), Array::LowestArrValue2(ma_medium, period)), Array::LowestArrValue2(ma_slow, period)));
       diff = fmax(fabs(highest_ma - Open[CURR]), fabs(Open[CURR] - lowest_ma));
       new_value = Open[CURR] + diff * direction;
       break;
     case T1_SAR: // 23: Current SAR value. Optimized.
     case T2_SAR:
       UpdateIndicator(_chart, INDI_SAR);
       diff = fabs(Open[CURR] - sar[period][CURR]);
       new_value = Open[CURR] + (diff + trail) * direction;
       if (VerboseDebug) PrintFormat("SAR Trail: %g, %g, %g", sar[period][CURR], sar[period][PREV], sar[period][FAR]);
       break;
     case T1_SAR_PEAK: // 24: Lowest/highest SAR value.
     case T2_SAR_PEAK:
       UpdateIndicator(_chart, INDI_SAR);
       diff = fmax(fabs(Open[CURR] - Array::HighestArrValue2(sar, period)), fabs(Open[CURR] - Array::LowestArrValue2(sar, period)));
       new_value = Open[CURR] + (diff + trail) * direction;
       break;
     case T1_BANDS: // 25: Current Bands value.
     case T2_BANDS:
       UpdateIndicator(_chart, INDI_BANDS);
       new_value = direction > 0 ? bands[period][CURR][BAND_UPPER] : bands[period][CURR][BAND_LOWER];
       break;
     case T1_BANDS_PEAK: // 26: Lowest/highest Bands value.
     case T2_BANDS_PEAK:
       UpdateIndicator(_chart, INDI_BANDS);
       new_value = (Order::OrderDirection(cmd) == mode
         ? fmax(fmax(bands[period][CURR][BAND_UPPER], bands[period][PREV][BAND_UPPER]), bands[period][FAR][BAND_UPPER])
         : fmin(fmin(bands[period][CURR][BAND_LOWER], bands[period][PREV][BAND_LOWER]), bands[period][FAR][BAND_LOWER])
         );
       break;
     case T1_ENVELOPES: // 27: Current Envelopes value. // FIXME
     case T2_ENVELOPES:
       UpdateIndicator(_chart, INDI_ENVELOPES);
       new_value = direction > 0 ? envelopes[period][CURR][LINE_UPPER] : envelopes[period][CURR][LINE_LOWER];
       break;
     default:
       Msg::ShowText(StringFormat("Unknown trailing stop method: %d", method), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
   }

  if (new_value > 0) new_value += Convert::PointsToValue(market.GetTradeDistanceInPts()) * direction;
  // + Convert::PointsToValue(GetSpreadInPts()) ?

  if (!market.TradeOpAllowed(cmd, new_value)) {
    #ifndef __limited__
      if (existing && previous == 0 && mode == -1) previous = default_trail;
    #else // If limited, then force the trailing value.
      if (existing && previous == 0) previous = default_trail;
    #endif
    Msg::ShowText(
        StringFormat("#%d (%s;d:%d), method: %d, invalid value: %g, previous: %g, ask/bid/Gap: %f/%f/%f (%d pts); %s",
          existing ? OrderTicket() : 0, EnumToString(mode), direction,
          method, new_value, previous, ask, bid, Convert::PointsToValue(market.GetTradeDistanceInPts()), market.GetTradeDistanceInPts(), Order::OrderTypeToString(Order::OrderType())),
        "Debug", __FUNCTION__, __LINE__, VerboseDebug);
    // If value is invalid, fallback to the previous one.
    return previous;
  }

  if (one_way) {
    if (mode < 0) {
      // Move trailing stop only one mode.
      if (previous == 0) previous = default_trail;
      if (Order::OrderDirection(cmd) == mode) new_value = (new_value < previous || previous == 0) ? new_value : previous;
      else new_value = (new_value > previous || previous == 0) ? new_value : previous;
    }
    else if (mode > 0) {
      // Move profit take only one mode.
      if (Order::OrderDirection(cmd) == mode) new_value = (new_value > previous || previous == 0) ? new_value : previous;
      else new_value = (new_value < previous || previous == 0) ? new_value : previous;
    }
  }

  if (VerboseDebug) {
    Msg::ShowText(
      StringFormat("Strategy: %s (%d), Method: %d, Tf: %d, Period: %d, Value: %g, Prev: %g, Direction: %d, Trail: %g (%g), LMA/HMA: %g/%g (%g/%g/%g|%g/%g/%g)",
        sname[order_type], order_type, method, tf, period, new_value, previous, direction, trail, default_trail,
        fabs(fmin(fmin(Array::LowestArrValue2(ma_fast, period), Array::LowestArrValue2(ma_medium, period)), Array::LowestArrValue2(ma_slow, period))),
        fabs(fmax(fmax(Array::HighestArrValue2(ma_fast, period), Array::HighestArrValue2(ma_medium, period)), Array::HighestArrValue2(ma_slow, period))),
        Array::LowestArrValue2(ma_fast, period), Array::LowestArrValue2(ma_medium, period), Array::LowestArrValue2(ma_slow, period),
        Array::HighestArrValue2(ma_fast, period), Array::HighestArrValue2(ma_medium, period), Array::HighestArrValue2(ma_slow, period))
      , "Trace", __FUNCTION__, __LINE__, VerboseTrace);
  }
  // if (VerboseDebug && Terminal::IsVisualMode()) Draw::ShowLine("trail_stop_" + OrderTicket(), new_value, GetOrderColor(EMPTY, ColorBuy, ColorSell));

  return market.NormalizeSLTP(new_value, cmd, mode);
}

/**
 * Get trailing method based on the strategy type.
 */
int GetTrailingMethod(int order_type, ENUM_ORDER_PROPERTY_DOUBLE mode) {
  DEBUG_CHECKPOINT_ADD
  int stop_method = DefaultTrailingStopMethod, profit_method = DefaultTrailingProfitMethod;
  switch (order_type) {
    case MA1:
    case MA5:
    case MA15:
    case MA30:
      stop_method   = MA_TrailingStopMethod;
      profit_method = MA_TrailingProfitMethod;
      break;
    case MACD1:
    case MACD5:
    case MACD15:
    case MACD30:
      stop_method   = MACD_TrailingStopMethod;
      profit_method = MACD_TrailingProfitMethod;
      break;
    case ALLIGATOR1:
    case ALLIGATOR5:
    case ALLIGATOR15:
    case ALLIGATOR30:
      stop_method   = Alligator_TrailingStopMethod;
      profit_method = Alligator_TrailingProfitMethod;
      break;
    case RSI1:
    case RSI5:
    case RSI15:
    case RSI30:
      stop_method   = RSI_TrailingStopMethod;
      profit_method = RSI_TrailingProfitMethod;
      break;
    case SAR1:
    case SAR5:
    case SAR15:
    case SAR30:
      stop_method   = SAR_TrailingStopMethod;
      profit_method = SAR_TrailingProfitMethod;
      break;
    case BANDS1:
    case BANDS5:
    case BANDS15:
    case BANDS30:
      stop_method   = Bands_TrailingStopMethod;
      profit_method = Bands_TrailingProfitMethod;
      break;
    case ENVELOPES1:
    case ENVELOPES5:
    case ENVELOPES15:
    case ENVELOPES30:
      stop_method   = Envelopes_TrailingStopMethod;
      profit_method = Envelopes_TrailingProfitMethod;
      break;
    case DEMARKER1:
    case DEMARKER5:
    case DEMARKER15:
    case DEMARKER30:
      stop_method   = DeMarker_TrailingStopMethod;
      profit_method = DeMarker_TrailingProfitMethod;
      break;
    case CCI1:
    case CCI5:
    case CCI15:
    case CCI30:
      stop_method   = CCI_TrailingStopMethod;
      profit_method = CCI_TrailingProfitMethod;
      break;
    case WPR1:
    case WPR5:
    case WPR15:
    case WPR30:
      stop_method   = WPR_TrailingStopMethod;
      profit_method = WPR_TrailingProfitMethod;
      break;
    case FRACTALS1:
    case FRACTALS5:
    case FRACTALS15:
    case FRACTALS30:
      stop_method   = Fractals_TrailingStopMethod;
      profit_method = Fractals_TrailingProfitMethod;
      break;
    case STOCHASTIC1:
    case STOCHASTIC5:
    case STOCHASTIC15:
    case STOCHASTIC30:
      stop_method   = Stochastic_TrailingStopMethod;
      profit_method = Stochastic_TrailingProfitMethod;
      break;
    case BPOWER1:
    case BPOWER5:
    case BPOWER15:
    case BPOWER30:
      stop_method   = BPower_TrailingStopMethod;
      profit_method = BPower_TrailingProfitMethod;
      break;
    case ZIGZAG1:
    case ZIGZAG5:
    case ZIGZAG15:
    case ZIGZAG30:
      stop_method   = ZigZag_TrailingStopMethod;
      profit_method = ZigZag_TrailingProfitMethod;
      break;
    default:
      Msg::ShowText(StringFormat("Unknown order type: %s", order_type), "Trace", __FUNCTION__, __LINE__, VerboseTrace);
  }
  return mode == ORDER_TP ? profit_method : stop_method;
}

/**
 * Calculate open positions (in volume).
 */
int CalculateCurrentOrders(string _symbol) {
   int buys=0, sells=0;

   for (int i = 0; i < OrdersTotal(); i++) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) break;
      if (OrderSymbol() == _symbol && CheckOurMagicNumber()){
         if (OrderType() == ORDER_TYPE_BUY)  buys++;
         if (OrderType() == ORDER_TYPE_SELL) sells++;
        }
     }
   if (buys > 0) return(buys); else return(-sells); // Return orders volume
}

/**
 * Return total number of opened orders (based on the EA magic number)
 * @todo: Move to Orders.
 */
int GetTotalOrders(bool ours = true) {
  int total = 0;
  for (int order = 0; order < OrdersTotal(); order++) {
    if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol()) {
      if (CheckOurMagicNumber()) {
        if (ours) total++;
      } else {
        if (!ours) total++;
      }
    }
  }
  if (ours) total_orders = total; // Re-calculate global variables.
  return (total);
}

// Return total number of orders per strategy type. See: ENUM_STRATEGY_TYPE.
int GetTotalOrdersByType(int order_type) {
  static datetime last_access = time_current;
  if (Cache && open_orders[order_type] > 0 && last_access == time_current) { return open_orders[order_type]; } else { last_access = time_current; }; // Return cached if available.
  open_orders[order_type] = 0;
  // ArrayFill(open_orders[order_type], 0, ArraySize(open_orders), 0); // Reset open_orders array.
  for (int order = 0; order < OrdersTotal(); order++) {
   if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES)) {
     if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber + order_type) {
       open_orders[order_type]++;
     }
   }
  }
  return (open_orders[order_type]);
}

/**
 * Get total profit of opened orders by type.
 * @todo: Move to Orders.
 */
double GetTotalProfitByType(ENUM_ORDER_TYPE cmd = NULL, int order_type = NULL) {
  double total = 0;
  for (int i = 0; i < OrdersTotal(); i++) {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) break;
    if (OrderSymbol() == Symbol() && CheckOurMagicNumber()) {
       if (OrderType() == cmd) total += Order::GetOrderProfit();
       else if (OrderMagicNumber() == MagicNumber + order_type) total += Order::GetOrderProfit();
     }
  }
  return total;
}

/**
 * Get profitable side and return trade operation type (ORDER_TYPE_BUY/ORDER_TYPE_SELL).
 * @todo: Move to Orders.
 */
ENUM_ORDER_TYPE GetProfitableSide() {
  double buys = GetTotalProfitByType(ORDER_TYPE_BUY);
  double sells = GetTotalProfitByType(ORDER_TYPE_SELL);
  if (buys > sells) return ORDER_TYPE_BUY;
  if (sells > buys) return ORDER_TYPE_SELL;
  return (ENUM_ORDER_TYPE) NULL;
}

/**
 * Calculate trade order command based on the majority of opened orders.
 * @todo: Move to Orders.
 */
ENUM_ORDER_TYPE GetCmdByOrders() {
  uint buys = Orders::GetOrdersByType(ORDER_TYPE_BUY);
  uint sells = Orders::GetOrdersByType(ORDER_TYPE_SELL);
  if (buys > sells) return ORDER_TYPE_BUY;
  if (sells > buys) return ORDER_TYPE_SELL;
  return (ENUM_ORDER_TYPE) NULL;
}

/**
 * For given magic number, check if it is ours.
 */
bool CheckOurMagicNumber(int magic_number = NULL) {
  if (magic_number == NULL) magic_number = OrderMagicNumber();
  return (magic_number >= MagicNumber && magic_number < MagicNumber + FINAL_STRATEGY_TYPE_ENTRY);
}

#ifdef __expire__
/**
 * Check for the expiration date.
 */
void CheckExpireDate() {
  if (TimeCurrent() > ea_expire_date + (PERIOD_W1 * 60)) {
    Msg::ShowText("EA has expired!", "Error", __FUNCTION__, __LINE__, VerboseErrors | VerboseInfo, PrintLogOnChart, true);
    ExpertRemove();
  } else if (TimeCurrent() > ea_expire_date) {
    ea_expired = true;
  } else if (TimeCurrent() + (PERIOD_W1 * 60) > ea_expire_date) {
    last_err = Msg::ShowText(StringFormat("This version will expire on %s!", TimeToStr(ea_expire_date, TIME_DATE)), "Warning", __FUNCTION__, __LINE__, VerboseErrors | VerboseInfo, PrintLogOnChart);
  }
}
#endif

/**
 * Check if it is possible to trade.
 */
bool TradeAllowed() {
  bool _result = true;
  #ifdef __expire__
  if (TimeCurrent() > ea_expire_date) {
    last_err = Msg::ShowText("New trades are not allowed, because EA has expired!", "Error", __FUNCTION__, __LINE__, VerboseInfo | VerboseErrors);
    ea_active = false;
    ea_expired = true;
    if (PrintLogOnChart) DisplayInfoOnChart();
    CheckExpireDate();
    return (false);
  }
  #endif
  #ifdef __profiler__ PROFILER_START #endif
  if (Bars < 100) {
    last_err = Msg::ShowText("Bars less than 100, not trading yet.", "Error", __FUNCTION__, __LINE__, VerboseErrors);
    if (PrintLogOnChart) DisplayInfoOnChart();
    _result = false;
  }
  else if (Terminal::IsRealtime() && Volume[0] < MinVolumeToTrade) {
    last_err = Msg::ShowText("Volume too low to trade.", "Error", __FUNCTION__, __LINE__, VerboseErrors);
    if (PrintLogOnChart) DisplayInfoOnChart();
    _result = false;
  }
  else if (!METHOD(16, ((int) ea_last_order[6] - (int) ea_last_order[2]))) {
    _result = false;
  }
  else if (IsTradeContextBusy()) {
    last_err = Msg::ShowText("Trade context is temporary busy.", "Error", __FUNCTION__, __LINE__, VerboseErrors);
    if (PrintLogOnChart) DisplayInfoOnChart();
    _result = false;
  }
  // Check if the EA is allowed to trade and trading context is not busy, otherwise returns false.
  // OrderSend(), OrderClose(), OrderCloseBy(), OrderModify(), OrderDelete() trading functions
  //   changing the state of a trading account can be called only if trading by Expert Advisors
  //   is allowed (the "Allow live trading" checkbox is enabled in the Expert Advisor or script properties).
  else if (!IsTradeAllowed()) {
    last_err = Msg::ShowText("Trade is not allowed at the moment, check the settings!", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart);
    _result = false;
  }
  else if (!IsConnected()) {
    last_err = Msg::ShowText("Terminal is not connected!", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart);
    if (PrintLogOnChart) DisplayInfoOnChart();
    _result = false;
  }
  else if (IsStopped()) {
    last_err = Msg::ShowText("Terminal is stopping!", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart);
    _result = false;
  }
  else if (Terminal::IsRealtime() && !MarketInfo(Symbol(), MODE_TRADEALLOWED)) {
    last_err = Msg::ShowText("Trading is not allowed. Market may be closed or choose the right symbol. Otherwise contact your broker.", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart);
    if (PrintLogOnChart) DisplayInfoOnChart();
    _result = false;
  }
  else if (Terminal::IsRealtime() && !IsExpertEnabled()) {
    last_err = Msg::ShowText("You need to enable: 'Enable Expert Advisor'/'AutoTrading'.", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart);
    _result = false;
  }
  else if (!session_active || StringLen(ea_file) != 11) {
    last_err = Msg::ShowText(StringFormat("Session is not active (%d)!", StringLen(ea_file)), "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart);
    ea_active = false;
    _result = false;
  }

  ea_active = _result;
  #ifdef __profiler__ PROFILER_STOP #endif
  return (_result);
}

/**
 * Check if EA parameters are valid.
 */
int CheckSettings() {
  string err;
   // TODO: IsDllsAllowed(), IsLibrariesAllowed()
  /* @todo
  if (File::FileIsExist(Terminal::GetExpertPath() + "\\" + ea_file)) {
    Msg::ShowText("Meow!", "Error", __FUNCTION__, __LINE__, true, true, true);
    return (false);
  }
  #ifdef __release__
  #endif
  */
  /* // @todo
  if (ValidateSettings && !ValidateSettings()) {
    last_err = Msg::ShowText("Market values are invalid!", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
    ea_active = false;
    return (false);
  }
  */
  #ifdef __expire__
    if (VerboseDebug) PrintFormat("Expire date: %s (%d)", TimeToStr(ea_expire_date, TIME_DATE), ea_expire_date);
    if (TimeCurrent() > ea_expire_date) {
      Msg::ShowText("This version has expired! Upgrade is required!", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, true);
      #ifndef __debug__ return -__LINE__; #endif
    } else if (TimeCurrent() + (PERIOD_W1 * 60) >= ea_expire_date) {
      Msg::ShowText(StringFormat("This version will expire on %s!", TimeToStr(ea_expire_date, TIME_DATE)), "Warning", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, true);
    }
  #endif
  #ifdef __release__
  #ifdef __backtest__
  if (Terminal::IsRealtime()) {
    Msg::ShowText("This version is compiled for backtest mode only.", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, true);
    return -__LINE__;
  }
  #else
  if (Terminal::IsRealtime()) {
    if (AccountInfoDouble(ACCOUNT_BALANCE) > 100000) {
      Msg::ShowText("This version doesn't support balance above 100k for a real account.", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, true);
      return -__LINE__;
    }
  }
  #endif
  #endif
  if (LotSize < 0.0) {
    Msg::ShowText("LotSize is less than 0.", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, true);
    return -__LINE__;
  }
  if (!Terminal::IsRealtime() && ValidateSettings) {
    if (!Tester::ValidSpread() || !Tester::ValidLotstep()) {
      Msg::ShowText("Backtest market settings are invalid! Connect to broker to fix it!", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
      return -__LINE__;
    }
  }
  return StringLen(ea_file) == 11 ? __LINE__ : -__LINE__;
}

/**
 * Validate market values.
 */
bool ValidateSettings() {
  bool result = true;
  result &= Tests::TestAllMarket(VerboseDebug);
  return result;
}

void CheckStats(double value, int type, bool max = true) {
  if (max) {
    if (value > daily[type])   daily[type]   = value;
    if (value > weekly[type])  weekly[type]  = value;
    if (value > monthly[type]) monthly[type] = value;
  } else {
    if (value < daily[type])   daily[type]   = value;
    if (value < weekly[type])  weekly[type]  = value;
    if (value < monthly[type]) monthly[type] = value;
  }
}

/**
 * Get daily total available orders. It can dynamically change during the day.
 *
 * @return
 *   Returns daily order limit when positive. When zero, it means unlimited.
 */
#ifdef __advanced__
uint GetMaxOrdersPerDay() {
  if (MaxOrdersPerDay <= 0) return 0;
  int hours_left = (24 - hour_of_day);
  int curr_allowed_limit = (int) floor((MaxOrdersPerDay - daily_orders) / hours_left);
  // Message(StringFormat("Hours left: (%d - %d) / %d= %d", MaxOrdersPerDay, daily_orders, hours_left, curr_allowed_limit));
  return fmin(fmax((total_orders - daily_orders), 1) + curr_allowed_limit, MaxOrdersPerDay);
}
#endif

/**
 * Calculate number of maximum of orders allowed to open.
 */
uint GetMaxOrders(double volume_size) {
  uint _result = 0;
  uint _limit = account.GetLimitOrders();
  #ifdef __advanced__
    _result = MaxOrders > 0 ? (MaxOrdersPerDay > 0 ? fmin(MaxOrders, GetMaxOrdersPerDay()) : MaxOrders) : trade[chart.TfToIndex()].CalcMaxOrders(volume_size, ea_risk_ratio, max_orders, GetMaxOrdersPerDay());
  #else
    _result = MaxOrders > 0 ? MaxOrders : trade[chart.TfToIndex()].CalcMaxOrders(volume_size, ea_risk_ratio, max_orders);
  #endif
  return _limit > 0 ? fmin(_result, _limit) : _result;
}

/**
 * Calculate the limit of maximum orders to open per each strategy.
 */
int GetMaxOrdersPerType() {
  return MaxOrdersPerType > 0  ? (int)MaxOrdersPerType : (int) fmin(fmax(MathFloor(max_orders / fmax(GetNoOfStrategies(), 1) ), 1) * 2, max_orders);
}

/**
 * Get number of active strategies.
 */
int GetNoOfStrategies() {
  int result = 0;
  for (int i = 0; i < FINAL_STRATEGY_TYPE_ENTRY; i++) {
    result += info[i][ACTIVE];
  }
  return result;
}

/**
 * Calculate size of the lot based on the free margin and account leverage automatically.
 */
double GetLotSizeAuto(uint _method = 0, bool smooth = true) {
  double new_lot_size = trade[chart.TfToIndex()].CalcLotSize(ea_risk_margin_per_order, ea_risk_ratio, _method);

  // Lot size warm-up.
  static bool is_warm_up = InitNoOfDaysToWarmUp != 0;
  if (is_warm_up) {
    OHLC first_bar = trade[chart.TfToIndex()].Chart().LoadOHLC();
    long warmup_days = ((TimeCurrent() - first_bar.time) / 60 / 60 / 24);
    if (warmup_days < InitNoOfDaysToWarmUp) {
      /*
      PrintFormat("%s: %d of %d, lot: %g of %g",
        __FUNCTION__,
        warmup_days, InitNoOfDaysToWarmUp,
        market.NormalizeLots(new_lot_size * 1 / (double) InitNoOfDaysToWarmUp * warmup_days),
        new_lot_size
        );
      */
      new_lot_size *= market.NormalizeLots(new_lot_size * 1 / (double) InitNoOfDaysToWarmUp * warmup_days);
    }
    else {
      is_warm_up = false;
    }
  }

  #ifdef __advanced__
  if (Boosting_Enabled) {
    if (LotSizeIncreaseMethod != 0) {
      if (METHOD(LotSizeIncreaseMethod, 0)) if (AccCondition(C_ACC_IN_PROFIT))      new_lot_size *= 1.1;
      if (METHOD(LotSizeIncreaseMethod, 1)) if (AccCondition(C_EQUITY_10PC_HIGH))   new_lot_size *= 1.1;
      if (METHOD(LotSizeIncreaseMethod, 2)) if (AccCondition(C_EQUITY_20PC_HIGH))   new_lot_size *= 1.1;
      if (METHOD(LotSizeIncreaseMethod, 3)) if (AccCondition(C_DBAL_LT_WEEKLY))     new_lot_size *= 1.1;
      if (METHOD(LotSizeIncreaseMethod, 4)) if (AccCondition(C_WBAL_GT_MONTHLY))    new_lot_size *= 1.1;
      if (METHOD(LotSizeIncreaseMethod, 5)) if (AccCondition(C_ACC_IN_TREND))       new_lot_size *= 1.1;
      if (METHOD(LotSizeIncreaseMethod, 6)) if (AccCondition(C_ACC_CDAY_IN_PROFIT)) new_lot_size *= 1.1;
      if (METHOD(LotSizeIncreaseMethod, 7)) if (AccCondition(C_ACC_PDAY_IN_PROFIT)) new_lot_size *= 1.1;
    }
    // --
    if (LotSizeDecreaseMethod != 0) {
      if (METHOD(LotSizeDecreaseMethod, 0)) if (AccCondition(C_ACC_IN_LOSS))        new_lot_size *= 0.9;
      if (METHOD(LotSizeDecreaseMethod, 1)) if (AccCondition(C_EQUITY_10PC_LOW))    new_lot_size *= 0.9;
      if (METHOD(LotSizeDecreaseMethod, 2)) if (AccCondition(C_EQUITY_20PC_LOW))    new_lot_size *= 0.9;
      if (METHOD(LotSizeDecreaseMethod, 3)) if (AccCondition(C_DBAL_GT_WEEKLY))     new_lot_size *= 0.9;
      if (METHOD(LotSizeDecreaseMethod, 4)) if (AccCondition(C_WBAL_LT_MONTHLY))    new_lot_size *= 0.9;
      if (METHOD(LotSizeDecreaseMethod, 5)) if (AccCondition(C_ACC_IN_NON_TREND))   new_lot_size *= 0.9;
      if (METHOD(LotSizeDecreaseMethod, 6)) if (AccCondition(C_ACC_CDAY_IN_LOSS))   new_lot_size *= 0.9;
      if (METHOD(LotSizeDecreaseMethod, 7)) if (AccCondition(C_ACC_PDAY_IN_LOSS))   new_lot_size *= 0.9;
    }
  }
  #endif

  if (smooth && ea_lot_size > 0) {
    // Increase only by average of the previous and new (which should prevent sudden increases).
    return market.NormalizeLots((ea_lot_size + new_lot_size) / 2);
  } else {
    return market.NormalizeLots(new_lot_size);
  }
}

/**
 * Return current lot size to trade.
 */
double GetLotSize() {
  return market.NormalizeLots(LotSize <= 0 ? GetLotSizeAuto((uint) fabs(LotSize)) : LotSize);
}

/**
 * Calculate risk of margin per each order.
 *
 * Risk only certain % of total available margin for each order.
 */
double GetRiskMarginAutoPerOrder() {
  // @todo: Add different methods (e.g. violity level).
  return ea_risk_ratio;
}

/**
 * Calculate risk of margin for all orders.
 *
 * Risk only certain % of total available margin for all orders.
 */
double GetRiskMarginAutoInTotal() {
  // @todo: Add different methods (e.g. violity level).
  return fmin(20, 20 * ea_risk_ratio);
}

/**
 * Return risk margin per order.
 *
 * @return int
 *   Range: 1-100
 */
double GetRiskMarginPerOrder() {
  return RiskMarginPerOrder == 0 ? GetRiskMarginAutoPerOrder() : fabs(RiskMarginPerOrder);
}

/**
 * Return risk margin for total orders.
 *
 * @return int
 *   Range: 1-100
 */
double GetRiskMarginInTotal() {
  return RiskMarginTotal == 0 ? GetRiskMarginAutoInTotal() : RiskMarginTotal;
}

/**
 * Calculate auto risk ratio value.
 */
double GetAutoRiskRatio() {
  double equity  = account.AccountEquity();
  double balance = account.AccountBalance() + account.AccountCredit();
  // Used when you open/close new positions. It can increase decrease during the price movement
  // in favor and vice versa.
  double free    = account.AccountFreeMargin();
  // Taken from your depo as a guarantee to maintain your current positions opened.
  // It stays the same until you open or close positions.
  double margin  = account.AccountMargin();
  double new_ea_risk_ratio = 1 / fmax(NEAR_ZERO, fmin(equity, balance)) * fmin(fmin(free, balance), equity);
  // --
  int margin_pc = (int) (100 / fmax(NEAR_ZERO, equity * margin));
  rr_text = new_ea_risk_ratio < 1.0 ? StringFormat("-MarginUsed=%d%%|", margin_pc) : ""; string s = "|";
  // ea_margin_risk_level
  // @todo: Add account.GetRiskMarginLevel(), GetTrend(), ConWin/ConLoss, violity level.
  if (RiskRatioIncreaseMethod != 0) {
    if (METHOD(RiskRatioIncreaseMethod, 0)) if (AccCondition(C_ACC_IN_PROFIT))      { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
    if (METHOD(RiskRatioIncreaseMethod, 1)) if (AccCondition(C_EQUITY_20PC_HIGH))   { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
    if (METHOD(RiskRatioIncreaseMethod, 2)) if (AccCondition(C_EQUITY_20PC_LOW))    { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
    if (METHOD(RiskRatioIncreaseMethod, 3)) if (AccCondition(C_DBAL_LT_WEEKLY))     { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
    if (METHOD(RiskRatioIncreaseMethod, 4)) if (AccCondition(C_WBAL_GT_MONTHLY))    { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
    if (METHOD(RiskRatioIncreaseMethod, 5)) if (AccCondition(C_ACC_IN_TREND))       { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
    if (METHOD(RiskRatioIncreaseMethod, 6)) if (AccCondition(C_ACC_CDAY_IN_PROFIT)) { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
    if (METHOD(RiskRatioIncreaseMethod, 7)) if (AccCondition(C_ACC_PDAY_IN_PROFIT)) { new_ea_risk_ratio *= 1.1; rr_text += "+"+last_cname+s; }
  }
  // --
  if (RiskRatioDecreaseMethod != 0) {
    if (METHOD(RiskRatioDecreaseMethod, 0)) if (AccCondition(C_ACC_IN_LOSS))        { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
    if (METHOD(RiskRatioDecreaseMethod, 1)) if (AccCondition(C_EQUITY_20PC_LOW))    { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
    if (METHOD(RiskRatioDecreaseMethod, 2)) if (AccCondition(C_EQUITY_20PC_HIGH))   { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
    if (METHOD(RiskRatioDecreaseMethod, 3)) if (AccCondition(C_DBAL_GT_WEEKLY))     { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
    if (METHOD(RiskRatioDecreaseMethod, 4)) if (AccCondition(C_WBAL_LT_MONTHLY))    { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
    if (METHOD(RiskRatioDecreaseMethod, 5)) if (AccCondition(C_ACC_IN_NON_TREND))   { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
    if (METHOD(RiskRatioDecreaseMethod, 6)) if (AccCondition(C_ACC_CDAY_IN_LOSS))   { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
    if (METHOD(RiskRatioDecreaseMethod, 7)) if (AccCondition(C_ACC_PDAY_IN_LOSS))   { new_ea_risk_ratio *= 0.9; rr_text += "-"+last_cname+s; }
  }
  String::RemoveSepChar(rr_text, s);

  /*
  #ifdef __advanced__
  #else
    if (GetTotalProfit() < 0) new_ea_risk_ratio /= 2; // Half risk if we're in overall loss.
  #endif
  */

  return new_ea_risk_ratio;
}

/**
 * Return risk ratio value.
 */
double GetRiskRatio() {
  return RiskRatio == 0 ? GetAutoRiskRatio() : RiskRatio;
}

/* BEGIN: PERIODIC FUNCTIONS */

/**
 * Executed for every hour.
 */
void StartNewHour(Trade *_trade) {
  #ifdef __profiler__ PROFILER_START #endif

  CheckHistory(); // Process closed orders for the previous hour.

  // Process actions.
  CheckAccConditions(_trade.Chart());

  // Process orders.
  ProcessOrders();

  // Print stats.
  if (!terminal.IsOptimization()) {
    Msg::ShowText(
      StringFormat("Hourly stats: Ticks: %d/h (%.2f/min)",
        hourly_stats.GetTotalTicks(),
        hourly_stats.GetTotalTicks() / 60
      ), "Debug", __FUNCTION__, __LINE__, VerboseDebug);

    // Reset variables.
    hourly_stats.Reset();
  }

  // Start the new hour.
  // Note: This needs to be after action processing.
  hour_of_day = Hour();

  // Update variables.
  ea_risk_ratio = GetRiskRatio();
  max_orders = GetMaxOrders(ea_lot_size);

  if (VerboseDebug) {
    PrintFormat("== New hour at %s (risk ratio: %.2f, max orders: %d)",
      DateTime::TimeToStr(TimeCurrent()), ea_risk_ratio, max_orders);
  }

  // Check if new day has been started.
  if (day_of_week != DayOfWeek()) {
    StartNewDay(_trade);
  }

  // Update strategy factor and lot size.
  if (Boosting_Enabled) UpdateStrategyFactor(DAILY);

  #ifdef __advanced__
  // Check if RSI period needs re-calculation.
  // if (RSI_DynamicPeriod) RSI_CheckPeriod();
  // Check for dynamic spread configuration.
  if (DynamicSpreadConf) {
    // TODO: SpreadRatio, MinPipChangeToTrade, MinPipGap
  }
  #endif

  // Reset messages and errors.
  // Message(NULL);
  #ifdef __profiler__ PROFILER_STOP #endif
}

/**
 * Queue the message for display.
 */
void Message(string msg = NULL) {
  if (msg == NULL) { last_msg = ""; last_err = ""; }
  else last_msg = msg;
}

/**
 * Get last available message.
 */
string GetLastMessage() {
  return last_msg;
}

/**
 * Get last available error.
 */
string GetLastErrMsg() {
  return last_err;
}

/**
 * Executed for every new day.
 */
void StartNewDay(Trade *_trade) {
  if (VerboseInfo) PrintFormat("== New day at %s ==", DateTime::TimeToStr(TimeCurrent()));

  // Print daily report at end of each day.
  if (VerboseInfo) Print(GetDailyReport());

  // Process actions.
  CheckAccConditions(_trade.Chart());

  // Calculate lot size if required.
  if (InitNoOfDaysToWarmUp != 0) {
    OHLC first_bar = trade[chart.TfToIndex()].Chart().LoadOHLC(0);
    long warmup_days = ((TimeCurrent() - first_bar.time) / 60 / 60 / 24);
    if (warmup_days <= InitNoOfDaysToWarmUp) {
      ea_lot_size = GetLotSize();
    }
  }

  // Update boosting values.
  if (Boosting_Enabled) UpdateStrategyFactor(WEEKLY);

  // Check if day started another week.
  if (DayOfWeek() < day_of_week) {
    StartNewWeek(_trade);
  }
  if (Day() < day_of_month) {
    StartNewMonth(_trade);
  }
  if (DayOfYear() < day_of_year) {
    StartNewYear(_trade);
  }

  // Store new data.
  day_of_week = DayOfWeek(); // The zero-based day of week (0 means Sunday,1,2,3,4,5,6) of the specified date. At the testing, the last known server time is modelled.
  day_of_month = Day(); // The day of month (1 - 31) of the specified date. At the testing, the last known server time is modelled.
  day_of_year = DayOfYear(); // Day (1 means 1 January,..,365(6) does 31 December) of year. At the testing, the last known server time is modelled.
  // Print and reset variables.
  daily_orders = 0;
  /*
  string sar_stats = "Daily SAR stats: ";
  for (int i = 0; i < FINAL_PERIOD_TYPE_ENTRY; i++) {
    sar_stats += StringFormat("Period: %d, Buy/Sell: %d/%d; ", i, signals[DAILY][SAR1][i][ORDER_TYPE_BUY], signals[DAILY][SAR1][i][ORDER_TYPE_SELL]);
    // sar_stats += "Buy M5: " + signals[DAILY][SAR5][i][ORDER_TYPE_BUY] + " / " + "Sell M5: " + signals[DAILY][SAR5][i][ORDER_TYPE_SELL] + "; ";
    // sar_stats += "Buy M15: " + signals[DAILY][SAR15][i][ORDER_TYPE_BUY] + " / " + "Sell M15: " + signals[DAILY][SAR15][i][ORDER_TYPE_SELL] + "; ";
    // sar_stats += "Buy M30: " + signals[DAILY][SAR30][i][ORDER_TYPE_BUY] + " / " + "Sell M30: " + signals[DAILY][SAR30][i][ORDER_TYPE_SELL] + "; ";
    signals[DAILY][SAR1][i][ORDER_TYPE_BUY] = 0;  signals[DAILY][SAR1][i][ORDER_TYPE_SELL]  = 0;
    // signals[DAILY][SAR5][i][ORDER_TYPE_BUY] = 0;  signals[DAILY][SAR5][i][ORDER_TYPE_SELL]  = 0;
    // signals[DAILY][SAR15][i][ORDER_TYPE_BUY] = 0; signals[DAILY][SAR15][i][ORDER_TYPE_SELL] = 0;
    // signals[DAILY][SAR30][i][ORDER_TYPE_BUY] = 0; signals[DAILY][SAR30][i][ORDER_TYPE_SELL] = 0;
  }
  if (VerboseInfo) Print(sar_stats);
  */

  // Reset previous data.
  ArrayFill(daily, 0, ArraySize(daily), 0);
  // Print and reset strategy stats.
  string strategy_stats = "Daily strategy stats: ";
  for (int j = 0; j < FINAL_STRATEGY_TYPE_ENTRY; j++) {
    if (stats[j][DAILY_PROFIT] != 0) strategy_stats += StringFormat("%s: %.1f pips; ", sname[j], stats[j][DAILY_PROFIT]);
    stats[j][DAILY_PROFIT]  = 0;
  }
  if (VerboseInfo) Print(strategy_stats);

  // Reset ticks
  if (RecordTicksToCSV) {
    ticker.SaveToCSV();
    ticker.Reset();
  }
  terminal.Logger().Flush(false);
}

/**
 * Executed for every new week.
 */
void StartNewWeek(Trade *_trade) {
  if (StringLen(__FILE__) != 11) { ExpertRemove(); }
  if (VerboseInfo) PrintFormat("== New week at %s ==", DateTime::TimeToStr(TimeCurrent()));
  if (VerboseInfo) Print(GetWeeklyReport()); // Print weekly report at end of each week.

  // Process actions.
  CheckAccConditions(_trade.Chart());

  // Calculate lot size, orders and risk.
  ea_risk_margin_per_order = GetRiskMarginPerOrder(); // Re-calculate risk margin per order.
  ea_risk_margin_total = GetRiskMarginInTotal(); // Re-calculate risk margin in total.
  ea_lot_size = GetLotSize(); // Re-calculate lot size.
  UpdateStrategyLotSize(); // Update strategy lot size.

  // Update boosting values.
  if (Boosting_Enabled) UpdateStrategyFactor(MONTHLY);

  // Reset variables.
  string sar_stats = "Weekly SAR stats: ";
  for (int i = 0; i < FINAL_ENUM_TIMEFRAMES_INDEX; i++) {
    sar_stats += StringFormat("Period: %d, Buy/Sell: %d/%d; ", i, signals[WEEKLY][SAR1][i][ORDER_TYPE_BUY], signals[WEEKLY][SAR1][i][ORDER_TYPE_SELL]);
    //sar_stats += "Buy M1: " + signals[WEEKLY][SAR1][i][ORDER_TYPE_BUY] + " / " + "Sell M1: " + signals[WEEKLY][SAR1][i][ORDER_TYPE_SELL] + "; ";
    //sar_stats += "Buy M5: " + signals[WEEKLY][SAR5][i][ORDER_TYPE_BUY] + " / " + "Sell M5: " + signals[WEEKLY][SAR5][i][ORDER_TYPE_SELL] + "; ";
    //sar_stats += "Buy M15: " + signals[WEEKLY][SAR15][i][ORDER_TYPE_BUY] + " / " + "Sell M15: " + signals[WEEKLY][SAR15][i][ORDER_TYPE_SELL] + "; ";
    //sar_stats += "Buy M30: " + signals[WEEKLY][SAR30][i][ORDER_TYPE_BUY] + " / " + "Sell M30: " + signals[WEEKLY][SAR30][i][ORDER_TYPE_SELL] + "; ";
    signals[WEEKLY][SAR1][i][ORDER_TYPE_BUY]  = 0; signals[WEEKLY][SAR1][i][ORDER_TYPE_SELL]  = 0;
    // signals[WEEKLY][SAR5][i][ORDER_TYPE_BUY]  = 0; signals[WEEKLY][SAR5][i][ORDER_TYPE_SELL]  = 0;
    // signals[WEEKLY][SAR15][i][ORDER_TYPE_BUY] = 0; signals[WEEKLY][SAR15][i][ORDER_TYPE_SELL] = 0;
    // signals[WEEKLY][SAR30][i][ORDER_TYPE_BUY] = 0; signals[WEEKLY][SAR30][i][ORDER_TYPE_SELL] = 0;
  }
  if (VerboseInfo) Print(sar_stats);

  ArrayFill(weekly, 0, ArraySize(weekly), 0);
  // Reset strategy stats.
  string strategy_stats = "Weekly strategy stats: ";
  for (int j = 0; j < FINAL_STRATEGY_TYPE_ENTRY; j++) {
    if (stats[j][WEEKLY_PROFIT] != 0) strategy_stats += StringFormat("%s: %.1f pips; ", sname[j], stats[j][WEEKLY_PROFIT]);
    stats[j][WEEKLY_PROFIT] = 0;
  }
  if (VerboseInfo) Print(strategy_stats);
}

/**
 * Executed for every new month.
 */
void StartNewMonth(Trade *_trade) {
  if (VerboseInfo) PrintFormat("== New month at %s ==", DateTime::TimeToStr(TimeCurrent()));
  if (VerboseInfo) Print(GetMonthlyReport()); // Print monthly report at end of each month.

  // Process actions.
  CheckAccConditions(_trade.Chart());

  // Store new data.
  month = DateTime::Month(); // Returns the current month as number (1-January,2,3,4,5,6,7,8,9,10,11,12), i.e., the number of month of the last known server time.

  // Reset variables.
  string sar_stats = "Monthly SAR stats: ";
  for (int i = 0; i < FINAL_ENUM_TIMEFRAMES_INDEX; i++) {
    sar_stats += StringFormat("Period: %d, Buy/Sell: %d/%d; ", i, signals[MONTHLY][SAR1][i][ORDER_TYPE_BUY], signals[MONTHLY][SAR1][i][ORDER_TYPE_SELL]);
    // sar_stats += "Buy M1: " + signals[MONTHLY][SAR1][i][ORDER_TYPE_BUY] + " / " + "Sell M1: " + signals[MONTHLY][SAR1][i][ORDER_TYPE_SELL] + "; ";
    // sar_stats += "Buy M5: " + signals[MONTHLY][SAR5][i][ORDER_TYPE_BUY] + " / " + "Sell M5: " + signals[MONTHLY][SAR5][i][ORDER_TYPE_SELL] + "; ";
    // sar_stats += "Buy M15: " + signals[MONTHLY][SAR15][i][ORDER_TYPE_BUY] + " / " + "Sell M15: " + signals[MONTHLY][SAR15][i][ORDER_TYPE_SELL] + "; ";
    // sar_stats += "Buy M30: " + signals[MONTHLY][SAR30][i][ORDER_TYPE_BUY] + " / " + "Sell M30: " + signals[MONTHLY][SAR30][i][ORDER_TYPE_SELL] + "; ";
    signals[MONTHLY][SAR1][i][ORDER_TYPE_BUY]  = 0; signals[MONTHLY][SAR1][i][ORDER_TYPE_SELL]  = 0;
    // signals[MONTHLY][SAR5][i][ORDER_TYPE_BUY]  = 0; signals[MONTHLY][SAR5][i][ORDER_TYPE_SELL]  = 0;
    // signals[MONTHLY][SAR15][i][ORDER_TYPE_BUY] = 0; signals[MONTHLY][SAR15][i][ORDER_TYPE_SELL] = 0;
    // signals[MONTHLY][SAR30][i][ORDER_TYPE_BUY] = 0; signals[MONTHLY][SAR30][i][ORDER_TYPE_SELL] = 0;
  }
  if (VerboseInfo) Print(sar_stats);

  ArrayFill(monthly, 0, ArraySize(monthly), 0);
  // Reset strategy stats.
  string strategy_stats = "Monthly strategy stats: ";
  for (int j = 0; j < FINAL_STRATEGY_TYPE_ENTRY; j++) {
    if (stats[j][MONTHLY_PROFIT] != 0) strategy_stats += StringFormat("%s: %.1f pips; ", sname[j], stats[j][MONTHLY_PROFIT]);
    stats[j][MONTHLY_PROFIT] = fmin(0, stats[j][MONTHLY_PROFIT]);
  }
  if (VerboseInfo) Print(strategy_stats);
}

/**
 * Executed for every new year.
 */
void StartNewYear(Trade *_trade) {
  if (VerboseInfo) Print("== New year ==");
  // if (VerboseInfo) Print(GetYearlyReport()); // Print monthly report at end of each year.

  // Store new data.
  year = DateTime::Year(); // Returns the current year, i.e., the year of the last known server time.

  // Reset variables.
  for (int i = 0; i < FINAL_ENUM_TIMEFRAMES_INDEX; i++) {
    signals[YEARLY][SAR1][i][ORDER_TYPE_BUY] = 0;
    signals[YEARLY][SAR1][i][ORDER_TYPE_SELL] = 0;
  }
}

/* END: PERIODIC FUNCTIONS */

/* BEGIN: VARIABLE FUNCTIONS */

/**
 * Initialize startup variables.
 */
bool InitVariables() {

  bool init = true;

  // Get type of account.
  if (!Terminal::IsRealtime()) account_type = "Backtest on " + account.GetType();
  #ifdef __backtest__ init &= !Terminal::IsRealtime(); #endif

  // Check time of the week, month and year based on the trading bars.
  //init_bar_time = chart.GetBarTime();
  time_current = TimeCurrent();
  hour_of_day = DateTime::Hour(); // The hour (0,1,2,..23) of the last known server time by the moment of the program start.
  day_of_week = DateTime::DayOfWeek(); // The zero-based day of week (0 means Sunday,1,2,3,4,5,6) of the specified date. At the testing, the last known server time is modelled.
  day_of_month = DateTime::Day(); // The day of month (1 - 31) of the specified date. At the testing, the last known server time is modelled.
  day_of_year = DateTime::DayOfYear(); // Day (1 means 1 January,..,365(6) does 31 December) of year. At the testing, the last known server time is modelled.
  month = DateTime::Month(); // Returns the current month as number (1-January,2,3,4,5,6,7,8,9,10,11,12), i.e., the number of month of the last known server time.
  year = DateTime::Year(); // Returns the current year, i.e., the year of the last known server time.

  market = new Market(_Symbol);

  // @todo Move to method.
  if (market.GetTradeContractSize() <= 0.0) {
    init &= !ValidateSettings;
    Msg::ShowText(StringFormat("Invalid MODE_LOTSIZE: %g", market.GetTradeContractSize()), "Error", __FUNCTION__, __LINE__, VerboseErrors & ValidateSettings, PrintLogOnChart, ValidateSettings);
  }

  // @todo: Move to method.
  if (market.GetVolumeStep() <= 0.0) {
    init &= !ValidateSettings;
    Msg::ShowText(StringFormat("Invalid SYMBOL_VOLUME_STEP: %g", market.GetVolumeStep()), "Error", __FUNCTION__, __LINE__, VerboseErrors & ValidateSettings, PrintLogOnChart, ValidateSettings);
    // market.GetLotStepInPts() = 0.01;
  }

  // @todo: Move to method.
  // Check the minimum permitted amount of a lot.
  if (market.GetVolumeMin() <= 0.0) {
    init &= !ValidateSettings;
    Msg::ShowText(StringFormat("Invalid SYMBOL_VOLUME_MIN: %g", market.GetVolumeMin()), "Error", __FUNCTION__, __LINE__, VerboseErrors & ValidateSettings, PrintLogOnChart, ValidateSettings);
    // market.GetMinLot() = market.GetLotStepInPts();
  }

  // @todo: Move to method.
  // Check the maximum permitted amount of a lot.
  if (market.GetVolumeMax() <= 0.0) {
    init &= !ValidateSettings;
    Msg::ShowText(StringFormat("Invalid SYMBOL_VOLUME_MAX: %g", market.GetVolumeMax()), "Error", __FUNCTION__, __LINE__, VerboseErrors & ValidateSettings, PrintLogOnChart, ValidateSettings);
  }

  // @todo: Move to method.
  if (market.GetVolumeStep() > market.GetVolumeMin()) {
    init &= !ValidateSettings;
    Msg::ShowText(StringFormat("Step lot is higher than min lot (%g > %g)", market.GetVolumeStep(), market.GetVolumeMin()), "Error", __FUNCTION__, __LINE__, VerboseErrors & ValidateSettings, PrintLogOnChart, ValidateSettings);
  }

  if (market.GetMarginRequired() == 0) {
    init &= !ValidateSettings;
    Msg::ShowText(StringFormat("Invalid MODE_MARGINREQUIRED: %g", market.GetMarginRequired()), "Error", __FUNCTION__, __LINE__, VerboseErrors & ValidateSettings, PrintLogOnChart, ValidateSettings);
    // market.GetMarginRequired() = 10; // Fix for 'zero divide' bug when MODE_MARGINREQUIRED is zero.
  }

  order_freezelevel = market.GetFreezeLevel();

  curr_spread = market.GetSpreadInPips();
  init_balance = account.AccountBalance();
  if (init_balance <= 0) {
    Msg::ShowText(StringFormat("Account balance is %g!", init_balance), "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
    return (false);
  }
  if (account.AccountEquity() <= 0) {
    Msg::ShowText(StringFormat("Account equity is %g!", account.AccountEquity()), "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
    return (false);
  }
  if (account.AccountFreeMargin() <= 0) {
    Msg::ShowText(StringFormat("Account free margin is %g!", account.AccountFreeMargin()), "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
    return (false);
  }
  /* @fixme: https://travis-ci.org/EA31337-Tester/EA31337-Lite-Sets/builds/140302386
  if (account.AccountMargin() <= 0) {
    Msg::ShowText(StringFormat("Account margin is %g!", account.AccountMargin()), "Error", __FUNCTION__, __LINE__, VerboseErrors);
    return (false);
  }
  */

  init_spread = market.GetSpreadInPts(); // @todo

  // Calculate pip/volume/slippage size and precision.
  // Market *market = new Market(_Symbol);
  pip_size = market.GetPipSize();
  pts_per_pip = market.GetPointsPerPip();

  max_order_slippage = Convert::PipsToPoints(MaxOrderPriceSlippage); // Maximum price slippage for buy or sell orders (converted into points).

  // Calculate lot size, orders, risk ratio and margin risk.
  UpdateMarginRiskLevel();
  UpdateVariables();
  ea_risk_ratio = GetRiskRatio();   // Re-calculate risk ratio.
  ea_risk_margin_per_order = GetRiskMarginPerOrder(); // Calculate the risk margin per order.
  ea_risk_margin_total = GetRiskMarginInTotal(); // Calculate the risk margin for all orders.
  ea_lot_size = GetLotSize();       // Calculate lot size (dependent on ea_risk_ratio).
  ea_last_order = ea_name;          // Last order pointer.
  if (ea_lot_size <= 0) {
    Msg::ShowText(StringFormat("Lot size is %g!", ea_lot_size), "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
    if (ValidateSettings) {
      // @fixme: Fails on Gold H1.
      return (false);
    } else {
      ea_lot_size = market.GetVolumeMin();
    }
  }
  max_orders = GetMaxOrders(ea_lot_size);

  gmt_offset = TimeGMTOffset();
  ArrayInitialize(todo_queue, 0); // Reset queue list.
  ArrayInitialize(daily,   0); // Reset daily stats.
  ArrayInitialize(weekly,  0); // Reset weekly stats.
  ArrayInitialize(monthly, 0); // Reset monthly stats.
  ArrayInitialize(tickets, 0); // Reset ticket list.
  ArrayInitialize(worse_strategy, EMPTY); // Reset worse strategy pointer.
  ArrayInitialize(best_strategy, EMPTY); // Reset best strategy pointer.
  ArrayInitialize(order_queue, EMPTY); // Reset order queue.

  // Initialize stats.
  if (!terminal.IsOptimization()) {
    total_stats = new Stats();
    hourly_stats = new Stats();
  }
  return (init);
}

#ifdef __advanced__

/**
 * Disable specific component for diagnostic purposes.
 */
void ToggleComponent(int component) {
  switch (component) {
    // Conditional actions.
    case 1:
      Account_Conditions_Active = !Account_Conditions_Active;
      break;
    case 2:
      DisableCloseConditions = !DisableCloseConditions;
      break;
    // Boosting
    case 3:
      Boosting_Enabled = !Boosting_Enabled;
      break;
    case 4:
      StrategyBoostByPF = !StrategyBoostByPF;
      break;
    case 5:
      if (BestDailyStrategyMultiplierFactor != 1.0 || BestWeeklyStrategyMultiplierFactor != 1.0 || BestMonthlyStrategyMultiplierFactor != 1.0) {
        BestDailyStrategyMultiplierFactor = 1.0;
        BestWeeklyStrategyMultiplierFactor = 1.0;
        BestMonthlyStrategyMultiplierFactor = 1.0;
      } else {
        BestDailyStrategyMultiplierFactor = 1.2;
        BestWeeklyStrategyMultiplierFactor = 1.2;
        BestMonthlyStrategyMultiplierFactor = 1.5;
      }
      break;
    case 6:
      if (WorseDailyStrategyMultiplierFactor != 1.0 || WorseWeeklyStrategyMultiplierFactor != 1.0 || WorseMonthlyStrategyMultiplierFactor != 1.0) {
        WorseDailyStrategyMultiplierFactor = 1.0;
        WorseWeeklyStrategyMultiplierFactor = 1.0;
        WorseMonthlyStrategyMultiplierFactor = 1.0;
      } else {
        WorseDailyStrategyMultiplierFactor = 1.0;
        WorseWeeklyStrategyMultiplierFactor = 1.0;
        WorseMonthlyStrategyMultiplierFactor = 1.0;
      }
      break;
    case 7:
      if (BoostTrendFactor != 1.0) BoostTrendFactor = 1.0;
      else BoostTrendFactor = 1.2;
      break;
    case 8:
      StrategyHandicapByPF = !StrategyHandicapByPF;
      break;
    // Smart order queue
    case 9:
      SmartQueueActive = !SmartQueueActive;
      break;
    // Trend
    case 10:
      //TradeWithTrend = !TradeWithTrend;
      break;
    case 11:
      // if (TrendMethod > 0) TrendMethod = 0; else TrendMethod = 181;
      break;
    case 12:
      break;
    // Risk
    case 13:
      if (RiskRatio > 0) RiskRatio = 0.0;
      else RiskRatio = 1.0;
      break;
    case 14:
      if (RiskRatioIncreaseMethod > 0) RiskRatioIncreaseMethod = 0; else RiskRatioIncreaseMethod = 255;
      break;
    case 15:
      if (RiskRatioDecreaseMethod > 0) RiskRatioIncreaseMethod = 0; else RiskRatioIncreaseMethod = 255;
      break;
    case 16:
      MinimalizeLosses = !MinimalizeLosses;
      break;
    // Spreads
    case 17:
      ApplySpreadLimits = !ApplySpreadLimits;
      MaxSpreadToTrade = 100;
      break;
    case 18:
      DynamicSpreadConf = !DynamicSpreadConf;
      break;
    // Lot size
    case 19:
      if (LotSize > 0) LotSize = 0.0;
      else LotSize = market.GetVolumeMin();
      break;
    case 20:
      if (LotSizeIncreaseMethod > 0) LotSizeIncreaseMethod = 0; else LotSizeIncreaseMethod = 255;
      break;
    case 21:
      if (LotSizeDecreaseMethod > 0) LotSizeDecreaseMethod = 0; else LotSizeDecreaseMethod = 255;
      break;
    // Order limits
    case 22:
      if (MaxOrders > 0) MaxOrders = 0;
      else MaxOrders = 30;
      break;
    case 23:
      if (MaxOrdersPerType > 0) MaxOrdersPerType = 0;
      else MaxOrdersPerType = 3;
      break;
    case 24:
      if (MaxOrdersPerDay > 0) MaxOrdersPerDay = 0;
      else MaxOrdersPerDay = 30;
      break;
    case 25:
      if (MinIntervalSec > 0) MinIntervalSec = 0;
      else MinIntervalSec = 240;
      break;
    // Trade limits
    case 26:
      if (MinVolumeToTrade > 0) MinVolumeToTrade = 0;
      else MinVolumeToTrade = 2;
      break;
    case 27:
      if (MinPipChangeToTrade < 0.5) MinPipChangeToTrade = 1.0;
      else MinPipChangeToTrade = 0.5;
      break;
    case 28:
      if (MinPipGap < 5) MinPipGap = 10;
      else MinPipGap = 5;
      break;
    // Indicator specific
    case 29:
      // RSI_DynamicPeriod = !RSI_DynamicPeriod;
      break;
    // Profit and loss
    case 30:
      if (Account_Condition_MinProfitCloseOrder > 20) Account_Condition_MinProfitCloseOrder = 0;
      else Account_Condition_MinProfitCloseOrder = 20;
      break;
    case 31:
      if (TakeProfitMax > 0) TakeProfitMax = 0;
      else TakeProfitMax = 40;
      break;
    case 32:
      if (StopLossMax > 0) StopLossMax = 0;
      else StopLossMax = 40;
      break;
    // Trailing values
    case 33:
      if (TrailingStop > 0) TrailingStop = 0;
      else TrailingStop = 40;
      break;
    case 34:
      if (TrailingProfit > 0) TrailingProfit = 0;
      else TrailingProfit = 40;
      break;
    case 35:
      break;
    case 36:
      break;
    // Strategies
    case 37:
      Array::ArrSetValueI(info, OPEN_CONDITION1,  0);
      break;
    case 38:
      Array::ArrSetValueI(info, OPEN_CONDITION2,  0);
      break;
    case 39:
      Array::ArrSetValueI(info, CLOSE_CONDITION, C_MACD_BUY_SELL);
      break;
    case 40:
      Array::ArrSetValueD(conf, OPEN_LEVEL, 0.0);
      break;
    case 41:
      Array::ArrSetValueD(conf, SPREAD_LIMIT,  100.0);
      break;
    case 42:
      for (int m1 = 0; m1 < ArrayRange(info, 0); m1++)
        if (info[m1][TIMEFRAME] == PERIOD_M1) info[m1][ACTIVE] = false;
      break;
    case 43:
      for (int m5 = 0; m5 < ArrayRange(info, 0); m5++)
        if (info[m5][TIMEFRAME] == PERIOD_M5) info[m5][ACTIVE] = false;
      break;
    default:
      break;
  }
}

#endif

/**
 * Initialize strategies.
 */
bool InitStrategies() {
  bool init = true;
  #ifdef __profiler__ PROFILER_START #endif

  // Initialize/reset strategy arrays.
  ArrayInitialize(info, 0);  // Reset strategy info.
  ArrayInitialize(conf, 0);  // Reset strategy configuration.
  ArrayInitialize(stats, 0); // Reset strategy statistics.

  // Initialize strategy array variables.
  init &= !AC1_Active  | InitStrategy(AC1,  "AC M1",   AC1_Active,  INDI_AC, PERIOD_M1,  AC1_SignalMethod,  AC_SignalLevel, AC1_OpenCondition1,  AC1_OpenCondition2,  AC1_CloseCondition,  AC1_MaxSpread);
  init &= !AC5_Active  | InitStrategy(AC5,  "AC M5",   AC5_Active,  INDI_AC, PERIOD_M5,  AC5_SignalMethod,  AC_SignalLevel, AC5_OpenCondition1,  AC5_OpenCondition2,  AC5_CloseCondition,  AC5_MaxSpread);
  init &= !AC15_Active | InitStrategy(AC15, "AC M15", AC15_Active, INDI_AC, PERIOD_M15, AC15_SignalMethod, AC_SignalLevel, AC15_OpenCondition1, AC15_OpenCondition2, AC15_CloseCondition, AC15_MaxSpread);
  init &= !AC30_Active | InitStrategy(AC30, "AC M30", AC30_Active, INDI_AC, PERIOD_M30, AC30_SignalMethod, AC_SignalLevel, AC30_OpenCondition1, AC30_OpenCondition2, AC30_CloseCondition, AC30_MaxSpread);

  init &= !AD1_Active  | InitStrategy(AD1,  "AD M1",   AD1_Active,  INDI_AD, PERIOD_M1,  AD1_SignalMethod,  AD_SignalLevel, AD1_OpenCondition1,  AD1_OpenCondition2,  AD1_CloseCondition,  AD1_MaxSpread);
  init &= !AD5_Active  | InitStrategy(AD5,  "AD M5",   AD5_Active,  INDI_AD, PERIOD_M5,  AD5_SignalMethod,  AD_SignalLevel, AD5_OpenCondition1,  AD5_OpenCondition2,  AD5_CloseCondition,  AD5_MaxSpread);
  init &= !AD15_Active | InitStrategy(AD15, "AD M15", AD15_Active, INDI_AD, PERIOD_M15, AD15_SignalMethod, AD_SignalLevel, AD15_OpenCondition1, AD15_OpenCondition2, AD15_CloseCondition, AD15_MaxSpread);
  init &= !AD30_Active | InitStrategy(AD30, "AD M30", AD30_Active, INDI_AD, PERIOD_M30, AD30_SignalMethod, AD_SignalLevel, AD30_OpenCondition1, AD30_OpenCondition2, AD30_CloseCondition, AD30_MaxSpread);

  init &= !ADX1_Active  | InitStrategy(ADX1,  "ADX M1",   ADX1_Active,  INDI_ADX, PERIOD_M1,  ADX1_SignalMethod,  ADX_SignalLevel, ADX1_OpenCondition1,  ADX1_OpenCondition2,  ADX1_CloseCondition,  ADX1_MaxSpread);
  init &= !ADX5_Active  | InitStrategy(ADX5,  "ADX M5",   ADX5_Active,  INDI_ADX, PERIOD_M5,  ADX5_SignalMethod,  ADX_SignalLevel, ADX5_OpenCondition1,  ADX5_OpenCondition2,  ADX5_CloseCondition,  ADX5_MaxSpread);
  init &= !ADX15_Active | InitStrategy(ADX15, "ADX M15", ADX15_Active, INDI_ADX, PERIOD_M15, ADX15_SignalMethod, ADX_SignalLevel, ADX15_OpenCondition1, ADX15_OpenCondition2, ADX15_CloseCondition, ADX15_MaxSpread);
  init &= !ADX30_Active | InitStrategy(ADX30, "ADX M30", ADX30_Active, INDI_ADX, PERIOD_M30, ADX30_SignalMethod, ADX_SignalLevel, ADX30_OpenCondition1, ADX30_OpenCondition2, ADX30_CloseCondition, ADX30_MaxSpread);

  init &= !Alligator1_Active  | InitStrategy(ALLIGATOR1,  "Alligator M1",   Alligator1_Active,  INDI_ALLIGATOR, PERIOD_M1,  Alligator1_SignalMethod,  Alligator_SignalLevel, Alligator1_OpenCondition1,  Alligator1_OpenCondition2,  Alligator1_CloseCondition,  Alligator1_MaxSpread);
  init &= !Alligator5_Active  | InitStrategy(ALLIGATOR5,  "Alligator M5",   Alligator5_Active,  INDI_ALLIGATOR, PERIOD_M5,  Alligator5_SignalMethod,  Alligator_SignalLevel, Alligator5_OpenCondition1,  Alligator5_OpenCondition2,  Alligator5_CloseCondition,  Alligator5_MaxSpread);
  init &= !Alligator15_Active | InitStrategy(ALLIGATOR15, "Alligator M15", Alligator15_Active, INDI_ALLIGATOR, PERIOD_M15, Alligator15_SignalMethod, Alligator_SignalLevel, Alligator15_OpenCondition1, Alligator15_OpenCondition2, Alligator15_CloseCondition, Alligator15_MaxSpread);
  init &= !Alligator30_Active | InitStrategy(ALLIGATOR30, "Alligator M30", Alligator30_Active, INDI_ALLIGATOR, PERIOD_M30, Alligator30_SignalMethod, Alligator_SignalLevel, Alligator30_OpenCondition1, Alligator30_OpenCondition2, Alligator30_CloseCondition, Alligator30_MaxSpread);

  init &= !ATR1_Active  | InitStrategy(ATR1,  "ATR M1",   ATR1_Active,  INDI_ATR, PERIOD_M1,  ATR1_SignalMethod,  ATR_SignalLevel, ATR1_OpenCondition1,  ATR1_OpenCondition2,  ATR1_CloseCondition,  ATR1_MaxSpread);
  init &= !ATR5_Active  | InitStrategy(ATR5,  "ATR M5",   ATR5_Active,  INDI_ATR, PERIOD_M5,  ATR5_SignalMethod,  ATR_SignalLevel, ATR5_OpenCondition1,  ATR5_OpenCondition2,  ATR5_CloseCondition,  ATR5_MaxSpread);
  init &= !ATR15_Active | InitStrategy(ATR15, "ATR M15", ATR15_Active, INDI_ATR, PERIOD_M15, ATR15_SignalMethod, ATR_SignalLevel, ATR15_OpenCondition1, ATR15_OpenCondition2, ATR15_CloseCondition, ATR15_MaxSpread);
  init &= !ATR30_Active | InitStrategy(ATR30, "ATR M30", ATR30_Active, INDI_ATR, PERIOD_M30, ATR30_SignalMethod, ATR_SignalLevel, ATR30_OpenCondition1, ATR30_OpenCondition2, ATR30_CloseCondition, ATR30_MaxSpread);

  init &= !Awesome1_Active  | InitStrategy(AWESOME1,  "Awesome M1",   Awesome1_Active,  INDI_AO, PERIOD_M1,  Awesome1_SignalMethod,  Awesome_SignalLevel, Awesome1_OpenCondition1,  Awesome1_OpenCondition2,  Awesome1_CloseCondition,  Awesome1_MaxSpread);
  init &= !Awesome5_Active  | InitStrategy(AWESOME5,  "Awesome M5",   Awesome5_Active,  INDI_AO, PERIOD_M5,  Awesome5_SignalMethod,  Awesome_SignalLevel, Awesome5_OpenCondition1,  Awesome5_OpenCondition2,  Awesome5_CloseCondition,  Awesome5_MaxSpread);
  init &= !Awesome15_Active | InitStrategy(AWESOME15, "Awesome M15", Awesome15_Active, INDI_AO, PERIOD_M15, Awesome15_SignalMethod, Awesome_SignalLevel, Awesome15_OpenCondition1, Awesome15_OpenCondition2, Awesome15_CloseCondition, Awesome15_MaxSpread);
  init &= !Awesome30_Active | InitStrategy(AWESOME30, "Awesome M30", Awesome30_Active, INDI_AO, PERIOD_M30, Awesome30_SignalMethod, Awesome_SignalLevel, Awesome30_OpenCondition1, Awesome30_OpenCondition2, Awesome30_CloseCondition, Awesome30_MaxSpread);

  init &= !Bands1_Active  | InitStrategy(BANDS1,  "Bands M1",   Bands1_Active,  INDI_BANDS, PERIOD_M1,  Bands1_SignalMethod,  Bands_SignalLevel, Bands1_OpenCondition1,  Bands1_OpenCondition2,  Bands1_CloseCondition,  Bands1_MaxSpread);
  init &= !Bands5_Active  | InitStrategy(BANDS5,  "Bands M5",   Bands5_Active,  INDI_BANDS, PERIOD_M5,  Bands5_SignalMethod,  Bands_SignalLevel, Bands5_OpenCondition1,  Bands5_OpenCondition2,  Bands5_CloseCondition,  Bands5_MaxSpread);
  init &= !Bands15_Active | InitStrategy(BANDS15, "Bands M15", Bands15_Active, INDI_BANDS, PERIOD_M15, Bands15_SignalMethod, Bands_SignalLevel, Bands15_OpenCondition1, Bands15_OpenCondition2, Bands15_CloseCondition, Bands15_MaxSpread);
  init &= !Bands30_Active | InitStrategy(BANDS30, "Bands M30", Bands30_Active, INDI_BANDS, PERIOD_M30, Bands30_SignalMethod, Bands_SignalLevel, Bands30_OpenCondition1, Bands30_OpenCondition2, Bands30_CloseCondition, Bands30_MaxSpread);

  init &= !BPower1_Active  | InitStrategy(BPOWER1,  "BPower M1",   BPower1_Active,  INDI_BEARS, PERIOD_M1,  BPower1_SignalMethod,  BPower_SignalLevel, BPower1_OpenCondition1,  BPower1_OpenCondition2,  BPower1_CloseCondition,  BPower1_MaxSpread);
  init &= !BPower5_Active  | InitStrategy(BPOWER5,  "BPower M5",   BPower5_Active,  INDI_BEARS, PERIOD_M5,  BPower5_SignalMethod,  BPower_SignalLevel, BPower5_OpenCondition1,  BPower5_OpenCondition2,  BPower5_CloseCondition,  BPower5_MaxSpread);
  init &= !BPower15_Active | InitStrategy(BPOWER15, "BPower M15", BPower15_Active, INDI_BEARS, PERIOD_M15, BPower15_SignalMethod, BPower_SignalLevel, BPower15_OpenCondition1, BPower15_OpenCondition2, BPower15_CloseCondition, BPower15_MaxSpread);
  init &= !BPower30_Active | InitStrategy(BPOWER30, "BPower M30", BPower30_Active, INDI_BEARS, PERIOD_M30, BPower30_SignalMethod, BPower_SignalLevel, BPower30_OpenCondition1, BPower30_OpenCondition2, BPower30_CloseCondition, BPower30_MaxSpread);

  init &= !Breakage1_Active  | InitStrategy(BREAKAGE1,  "Breakage M1",   Breakage1_Active,  EMPTY, PERIOD_M1,  Breakage1_SignalMethod,  Breakage_SignalLevel, Breakage1_OpenCondition1,  Breakage1_OpenCondition2,  Breakage1_CloseCondition,  Breakage1_MaxSpread);
  init &= !Breakage5_Active  | InitStrategy(BREAKAGE5,  "Breakage M5",   Breakage5_Active,  EMPTY, PERIOD_M5,  Breakage5_SignalMethod,  Breakage_SignalLevel, Breakage5_OpenCondition1,  Breakage5_OpenCondition2,  Breakage5_CloseCondition,  Breakage5_MaxSpread);
  init &= !Breakage15_Active | InitStrategy(BREAKAGE15, "Breakage M15", Breakage15_Active, EMPTY, PERIOD_M15, Breakage15_SignalMethod, Breakage_SignalLevel, Breakage15_OpenCondition1, Breakage15_OpenCondition2, Breakage15_CloseCondition, Breakage15_MaxSpread);
  init &= !Breakage30_Active | InitStrategy(BREAKAGE30, "Breakage M30", Breakage30_Active, EMPTY, PERIOD_M30, Breakage30_SignalMethod, Breakage_SignalLevel, Breakage30_OpenCondition1, Breakage30_OpenCondition2, Breakage30_CloseCondition, Breakage30_MaxSpread);

  init &= !BWMFI1_Active  | InitStrategy(BWMFI1,  "BWMFI M1",   BWMFI1_Active,  EMPTY, PERIOD_M1,  BWMFI1_SignalMethod,  BWMFI_SignalLevel, BWMFI1_OpenCondition1,  BWMFI1_OpenCondition2,  BWMFI1_CloseCondition,  BWMFI1_MaxSpread);
  init &= !BWMFI5_Active  | InitStrategy(BWMFI5,  "BWMFI M5",   BWMFI5_Active,  EMPTY, PERIOD_M5,  BWMFI5_SignalMethod,  BWMFI_SignalLevel, BWMFI5_OpenCondition1,  BWMFI5_OpenCondition2,  BWMFI5_CloseCondition,  BWMFI5_MaxSpread);
  init &= !BWMFI15_Active | InitStrategy(BWMFI15, "BWMFI M15", BWMFI15_Active, EMPTY, PERIOD_M15, BWMFI15_SignalMethod, BWMFI_SignalLevel, BWMFI15_OpenCondition1, BWMFI15_OpenCondition2, BWMFI15_CloseCondition, BWMFI15_MaxSpread);
  init &= !BWMFI30_Active | InitStrategy(BWMFI30, "BWMFI M30", BWMFI30_Active, EMPTY, PERIOD_M30, BWMFI30_SignalMethod, BWMFI_SignalLevel, BWMFI30_OpenCondition1, BWMFI30_OpenCondition2, BWMFI30_CloseCondition, BWMFI30_MaxSpread);

  init &= !CCI1_Active  | InitStrategy(CCI1,  "CCI M1",   CCI1_Active,  INDI_CCI, PERIOD_M1,  CCI1_SignalMethod,  CCI_SignalLevel, CCI1_OpenCondition1,  CCI1_OpenCondition2,  CCI1_CloseCondition,  CCI1_MaxSpread);
  init &= !CCI5_Active  | InitStrategy(CCI5,  "CCI M5",   CCI5_Active,  INDI_CCI, PERIOD_M5,  CCI5_SignalMethod,  CCI_SignalLevel, CCI5_OpenCondition1,  CCI5_OpenCondition2,  CCI5_CloseCondition,  CCI5_MaxSpread);
  init &= !CCI15_Active | InitStrategy(CCI15, "CCI M15", CCI15_Active, INDI_CCI, PERIOD_M15, CCI15_SignalMethod, CCI_SignalLevel, CCI15_OpenCondition1, CCI15_OpenCondition2, CCI15_CloseCondition, CCI15_MaxSpread);
  init &= !CCI30_Active | InitStrategy(CCI30, "CCI M30", CCI30_Active, INDI_CCI, PERIOD_M30, CCI30_SignalMethod, CCI_SignalLevel, CCI30_OpenCondition1, CCI30_OpenCondition2, CCI30_CloseCondition, CCI30_MaxSpread);

  init &= !DeMarker1_Active  | InitStrategy(DEMARKER1,  "DeMarker M1",   DeMarker1_Active,  INDI_DEMARKER, PERIOD_M1,  DeMarker1_SignalMethod,  DeMarker_SignalLevel, DeMarker1_OpenCondition1,  DeMarker1_OpenCondition2,  DeMarker1_CloseCondition,  DeMarker1_MaxSpread);
  init &= !DeMarker5_Active  | InitStrategy(DEMARKER5,  "DeMarker M5",   DeMarker5_Active,  INDI_DEMARKER, PERIOD_M5,  DeMarker5_SignalMethod,  DeMarker_SignalLevel, DeMarker5_OpenCondition1,  DeMarker5_OpenCondition2,  DeMarker5_CloseCondition,  DeMarker5_MaxSpread);
  init &= !DeMarker15_Active | InitStrategy(DEMARKER15, "DeMarker M15", DeMarker15_Active, INDI_DEMARKER, PERIOD_M15, DeMarker15_SignalMethod, DeMarker_SignalLevel, DeMarker15_OpenCondition1, DeMarker15_OpenCondition2, DeMarker15_CloseCondition, DeMarker15_MaxSpread);
  init &= !DeMarker30_Active | InitStrategy(DEMARKER30, "DeMarker M30", DeMarker30_Active, INDI_DEMARKER, PERIOD_M30, DeMarker30_SignalMethod, DeMarker_SignalLevel, DeMarker30_OpenCondition1, DeMarker30_OpenCondition2, DeMarker30_CloseCondition, DeMarker30_MaxSpread);

  init &= !Envelopes1_Active  | InitStrategy(ENVELOPES1,  "Envelopes M1",   Envelopes1_Active,  INDI_ENVELOPES, PERIOD_M1,  Envelopes1_SignalMethod,  Envelopes_SignalLevel, Envelopes1_OpenCondition1,  Envelopes1_OpenCondition2,  Envelopes1_CloseCondition,  Envelopes1_MaxSpread);
  init &= !Envelopes5_Active  | InitStrategy(ENVELOPES5,  "Envelopes M5",   Envelopes5_Active,  INDI_ENVELOPES, PERIOD_M5,  Envelopes5_SignalMethod,  Envelopes_SignalLevel, Envelopes5_OpenCondition1,  Envelopes5_OpenCondition2,  Envelopes5_CloseCondition,  Envelopes5_MaxSpread);
  init &= !Envelopes15_Active | InitStrategy(ENVELOPES15, "Envelopes M15", Envelopes15_Active, INDI_ENVELOPES, PERIOD_M15, Envelopes15_SignalMethod, Envelopes_SignalLevel, Envelopes15_OpenCondition1, Envelopes15_OpenCondition2, Envelopes15_CloseCondition, Envelopes15_MaxSpread);
  init &= !Envelopes30_Active | InitStrategy(ENVELOPES30, "Envelopes M30", Envelopes30_Active, INDI_ENVELOPES, PERIOD_M30, Envelopes30_SignalMethod, Envelopes_SignalLevel, Envelopes30_OpenCondition1, Envelopes30_OpenCondition2, Envelopes30_CloseCondition, Envelopes30_MaxSpread);

  init &= !Force1_Active  | InitStrategy(FORCE1,  "Force M1",   Force1_Active,  INDI_FORCE, PERIOD_M1,  Force1_SignalMethod,  Force_SignalLevel, Force1_OpenCondition1,  Force1_OpenCondition2,  Force1_CloseCondition,  Force1_MaxSpread);
  init &= !Force5_Active  | InitStrategy(FORCE5,  "Force M5",   Force5_Active,  INDI_FORCE, PERIOD_M5,  Force5_SignalMethod,  Force_SignalLevel, Force5_OpenCondition1,  Force5_OpenCondition2,  Force5_CloseCondition,  Force5_MaxSpread);
  init &= !Force15_Active | InitStrategy(FORCE15, "Force M15", Force15_Active, INDI_FORCE, PERIOD_M15, Force15_SignalMethod, Force_SignalLevel, Force15_OpenCondition1, Force15_OpenCondition2, Force15_CloseCondition, Force15_MaxSpread);
  init &= !Force30_Active | InitStrategy(FORCE30, "Force M30", Force30_Active, INDI_FORCE, PERIOD_M30, Force30_SignalMethod, Force_SignalLevel, Force30_OpenCondition1, Force30_OpenCondition2, Force30_CloseCondition, Force30_MaxSpread);

  init &= !Fractals1_Active  | InitStrategy(FRACTALS1,  "Fractals M1",   Fractals1_Active,  INDI_FRACTALS, PERIOD_M1,  Fractals1_SignalMethod,  Fractals_SignalLevel, Fractals1_OpenCondition1,  Fractals1_OpenCondition2,  Fractals1_CloseCondition,  Fractals1_MaxSpread);
  init &= !Fractals5_Active  | InitStrategy(FRACTALS5,  "Fractals M5",   Fractals5_Active,  INDI_FRACTALS, PERIOD_M5,  Fractals5_SignalMethod,  Fractals_SignalLevel, Fractals5_OpenCondition1,  Fractals5_OpenCondition2,  Fractals5_CloseCondition,  Fractals5_MaxSpread);
  init &= !Fractals15_Active | InitStrategy(FRACTALS15, "Fractals M15", Fractals15_Active, INDI_FRACTALS, PERIOD_M15, Fractals15_SignalMethod, Fractals_SignalLevel, Fractals15_OpenCondition1, Fractals15_OpenCondition2, Fractals15_CloseCondition, Fractals15_MaxSpread);
  init &= !Fractals30_Active | InitStrategy(FRACTALS30, "Fractals M30", Fractals30_Active, INDI_FRACTALS, PERIOD_M30, Fractals30_SignalMethod, Fractals_SignalLevel, Fractals30_OpenCondition1, Fractals30_OpenCondition2, Fractals30_CloseCondition, Fractals30_MaxSpread);

  init &= !Gator1_Active  | InitStrategy(GATOR1,  "Gator M1",   Gator1_Active,  INDI_GATOR, PERIOD_M1,  Gator1_SignalMethod,  Gator_SignalLevel, Gator1_OpenCondition1,  Gator1_OpenCondition2,  Gator1_CloseCondition,  Gator1_MaxSpread);
  init &= !Gator5_Active  | InitStrategy(GATOR5,  "Gator M5",   Gator5_Active,  INDI_GATOR, PERIOD_M5,  Gator5_SignalMethod,  Gator_SignalLevel, Gator5_OpenCondition1,  Gator5_OpenCondition2,  Gator5_CloseCondition,  Gator5_MaxSpread);
  init &= !Gator15_Active | InitStrategy(GATOR15, "Gator M15", Gator15_Active, INDI_GATOR, PERIOD_M15, Gator15_SignalMethod, Gator_SignalLevel, Gator15_OpenCondition1, Gator15_OpenCondition2, Gator15_CloseCondition, Gator15_MaxSpread);
  init &= !Gator30_Active | InitStrategy(GATOR30, "Gator M30", Gator30_Active, INDI_GATOR, PERIOD_M30, Gator30_SignalMethod, Gator_SignalLevel, Gator30_OpenCondition1, Gator30_OpenCondition2, Gator30_CloseCondition, Gator30_MaxSpread);

  init &= !Ichimoku1_Active  | InitStrategy(ICHIMOKU1,  "Ichimoku M1",   Ichimoku1_Active,  INDI_ICHIMOKU, PERIOD_M1,  Ichimoku1_SignalMethod,  Ichimoku_SignalLevel, Ichimoku1_OpenCondition1,  Ichimoku1_OpenCondition2,  Ichimoku1_CloseCondition,  Ichimoku1_MaxSpread);
  init &= !Ichimoku5_Active  | InitStrategy(ICHIMOKU5,  "Ichimoku M5",   Ichimoku5_Active,  INDI_ICHIMOKU, PERIOD_M5,  Ichimoku5_SignalMethod,  Ichimoku_SignalLevel, Ichimoku5_OpenCondition1,  Ichimoku5_OpenCondition2,  Ichimoku5_CloseCondition,  Ichimoku5_MaxSpread);
  init &= !Ichimoku15_Active | InitStrategy(ICHIMOKU15, "Ichimoku M15", Ichimoku15_Active, INDI_ICHIMOKU, PERIOD_M15, Ichimoku15_SignalMethod, Ichimoku_SignalLevel, Ichimoku15_OpenCondition1, Ichimoku15_OpenCondition2, Ichimoku15_CloseCondition, Ichimoku15_MaxSpread);
  init &= !Ichimoku30_Active | InitStrategy(ICHIMOKU30, "Ichimoku M30", Ichimoku30_Active, INDI_ICHIMOKU, PERIOD_M30, Ichimoku30_SignalMethod, Ichimoku_SignalLevel, Ichimoku30_OpenCondition1, Ichimoku30_OpenCondition2, Ichimoku30_CloseCondition, Ichimoku30_MaxSpread);

  init &= !MA1_Active  | InitStrategy(MA1,  "MA M1",   MA1_Active,  INDI_MA, PERIOD_M1,  MA1_SignalMethod,  MA_SignalLevel,  MA1_OpenCondition1, MA1_OpenCondition2,  MA1_CloseCondition,  MA1_MaxSpread);
  init &= !MA5_Active  | InitStrategy(MA5,  "MA M5",   MA5_Active,  INDI_MA, PERIOD_M5,  MA5_SignalMethod,  MA_SignalLevel,  MA5_OpenCondition1, MA5_OpenCondition2,  MA5_CloseCondition,  MA5_MaxSpread);
  init &= !MA15_Active | InitStrategy(MA15, "MA M15", MA15_Active, INDI_MA, PERIOD_M15, MA15_SignalMethod, MA_SignalLevel, MA15_OpenCondition1, MA15_OpenCondition2, MA15_CloseCondition, MA15_MaxSpread);
  init &= !MA30_Active | InitStrategy(MA30, "MA M30", MA30_Active, INDI_MA, PERIOD_M30, MA30_SignalMethod, MA_SignalLevel, MA30_OpenCondition1, MA30_OpenCondition2, MA30_CloseCondition, MA30_MaxSpread);

  init &= !MACD1_Active  | InitStrategy(MACD1,  "MACD M1",   MACD1_Active,  INDI_MACD, PERIOD_M1,  MACD1_SignalMethod,  MACD_SignalLevel, MACD1_OpenCondition1,  MACD1_OpenCondition2,  MACD1_CloseCondition,  MACD1_MaxSpread);
  init &= !MACD5_Active  | InitStrategy(MACD5,  "MACD M5",   MACD5_Active,  INDI_MACD, PERIOD_M5,  MACD5_SignalMethod,  MACD_SignalLevel, MACD5_OpenCondition1,  MACD5_OpenCondition2,  MACD5_CloseCondition,  MACD5_MaxSpread);
  init &= !MACD15_Active | InitStrategy(MACD15, "MACD M15", MACD15_Active, INDI_MACD, PERIOD_M15, MACD15_SignalMethod, MACD_SignalLevel, MACD15_OpenCondition1, MACD15_OpenCondition2, MACD15_CloseCondition, MACD15_MaxSpread);
  init &= !MACD30_Active | InitStrategy(MACD30, "MACD M30", MACD30_Active, INDI_MACD, PERIOD_M30, MACD30_SignalMethod, MACD_SignalLevel, MACD30_OpenCondition1, MACD30_OpenCondition2, MACD30_CloseCondition, MACD30_MaxSpread);

  init &= !MFI1_Active  | InitStrategy(MFI1,  "MFI M1",   MFI1_Active,  INDI_MFI, PERIOD_M1,  MFI1_SignalMethod,  MFI_SignalLevel, MFI1_OpenCondition1,  MFI1_OpenCondition2,  MFI1_CloseCondition,  MFI1_MaxSpread);
  init &= !MFI5_Active  | InitStrategy(MFI5,  "MFI M5",   MFI5_Active,  INDI_MFI, PERIOD_M5,  MFI5_SignalMethod,  MFI_SignalLevel, MFI5_OpenCondition1,  MFI5_OpenCondition2,  MFI5_CloseCondition,  MFI5_MaxSpread);
  init &= !MFI15_Active | InitStrategy(MFI15, "MFI M15", MFI15_Active, INDI_MFI, PERIOD_M15, MFI15_SignalMethod, MFI_SignalLevel, MFI15_OpenCondition1, MFI15_OpenCondition2, MFI15_CloseCondition, MFI15_MaxSpread);
  init &= !MFI30_Active | InitStrategy(MFI30, "MFI M30", MFI30_Active, INDI_MFI, PERIOD_M30, MFI30_SignalMethod, MFI_SignalLevel, MFI30_OpenCondition1, MFI30_OpenCondition2, MFI30_CloseCondition, MFI30_MaxSpread);

  init &= !Momentum1_Active  | InitStrategy(MOM1,  "Momentum M1",   Momentum1_Active,  INDI_MOMENTUM, PERIOD_M1,  Momentum1_SignalMethod,  Momentum_SignalLevel, Momentum1_OpenCondition1,  Momentum1_OpenCondition2,  Momentum1_CloseCondition,  Momentum1_MaxSpread);
  init &= !Momentum5_Active  | InitStrategy(MOM5,  "Momentum M5",   Momentum5_Active,  INDI_MOMENTUM, PERIOD_M5,  Momentum5_SignalMethod,  Momentum_SignalLevel, Momentum5_OpenCondition1,  Momentum5_OpenCondition2,  Momentum5_CloseCondition,  Momentum5_MaxSpread);
  init &= !Momentum15_Active | InitStrategy(MOM15, "Momentum M15", Momentum15_Active, INDI_MOMENTUM, PERIOD_M15, Momentum15_SignalMethod, Momentum_SignalLevel, Momentum15_OpenCondition1, Momentum15_OpenCondition2, Momentum15_CloseCondition, Momentum15_MaxSpread);
  init &= !Momentum30_Active | InitStrategy(MOM30, "Momentum M30", Momentum30_Active, INDI_MOMENTUM, PERIOD_M30, Momentum30_SignalMethod, Momentum_SignalLevel, Momentum30_OpenCondition1, Momentum30_OpenCondition2, Momentum30_CloseCondition, Momentum30_MaxSpread);

  init &= !OBV1_Active  | InitStrategy(OBV1,  "OBV M1",   OBV1_Active,  INDI_OBV, PERIOD_M1,  OBV1_SignalMethod,  OBV_SignalLevel,  OBV1_OpenCondition1, OBV1_OpenCondition2,  OBV1_CloseCondition,  OBV1_MaxSpread);
  init &= !OBV5_Active  | InitStrategy(OBV5,  "OBV M5",   OBV5_Active,  INDI_OBV, PERIOD_M5,  OBV5_SignalMethod,  OBV_SignalLevel,  OBV5_OpenCondition1, OBV5_OpenCondition2,  OBV5_CloseCondition,  OBV5_MaxSpread);
  init &= !OBV15_Active | InitStrategy(OBV15, "OBV M15", OBV15_Active, INDI_OBV, PERIOD_M15, OBV15_SignalMethod, OBV_SignalLevel, OBV15_OpenCondition1, OBV15_OpenCondition2, OBV15_CloseCondition, OBV15_MaxSpread);
  init &= !OBV30_Active | InitStrategy(OBV30, "OBV M30", OBV30_Active, INDI_OBV, PERIOD_M30, OBV30_SignalMethod, OBV_SignalLevel, OBV30_OpenCondition1, OBV30_OpenCondition2, OBV30_CloseCondition, OBV30_MaxSpread);

  init &= !OSMA1_Active  | InitStrategy(OSMA1,  "OSMA M1",   OSMA1_Active,  INDI_OSMA, PERIOD_M1,  OSMA1_SignalMethod,  OSMA_SignalLevel, OSMA1_OpenCondition1,  OSMA1_OpenCondition2,  OSMA1_CloseCondition,  OSMA1_MaxSpread);
  init &= !OSMA5_Active  | InitStrategy(OSMA5,  "OSMA M5",   OSMA5_Active,  INDI_OSMA, PERIOD_M5,  OSMA5_SignalMethod,  OSMA_SignalLevel, OSMA5_OpenCondition1,  OSMA5_OpenCondition2,  OSMA5_CloseCondition,  OSMA5_MaxSpread);
  init &= !OSMA15_Active | InitStrategy(OSMA15, "OSMA M15", OSMA15_Active, INDI_OSMA, PERIOD_M15, OSMA15_SignalMethod, OSMA_SignalLevel, OSMA15_OpenCondition1, OSMA15_OpenCondition2, OSMA15_CloseCondition, OSMA15_MaxSpread);
  init &= !OSMA30_Active | InitStrategy(OSMA30, "OSMA M30", OSMA30_Active, INDI_OSMA, PERIOD_M30, OSMA30_SignalMethod, OSMA_SignalLevel, OSMA30_OpenCondition1, OSMA30_OpenCondition2, OSMA30_CloseCondition, OSMA30_MaxSpread);

  init &= !RSI1_Active  | InitStrategy(RSI1,  "RSI M1",   RSI1_Active,  INDI_RSI, PERIOD_M1,  RSI1_SignalMethod,  RSI_SignalLevel, RSI1_OpenCondition1,  RSI1_OpenCondition2,  RSI1_CloseCondition,  RSI1_MaxSpread);
  init &= !RSI5_Active  | InitStrategy(RSI5,  "RSI M5",   RSI5_Active,  INDI_RSI, PERIOD_M5,  RSI5_SignalMethod,  RSI_SignalLevel, RSI5_OpenCondition1,  RSI5_OpenCondition2,  RSI5_CloseCondition,  RSI5_MaxSpread);
  init &= !RSI15_Active | InitStrategy(RSI15, "RSI M15", RSI15_Active, INDI_RSI, PERIOD_M15, RSI15_SignalMethod, RSI_SignalLevel, RSI15_OpenCondition1, RSI15_OpenCondition2, RSI15_CloseCondition, RSI15_MaxSpread);
  init &= !RSI30_Active | InitStrategy(RSI30, "RSI M30", RSI30_Active, INDI_RSI, PERIOD_M30, RSI30_SignalMethod, RSI_SignalLevel, RSI30_OpenCondition1, RSI30_OpenCondition2, RSI30_CloseCondition, RSI30_MaxSpread);

  init &= !RVI1_Active  |  InitStrategy(RVI1,  "RVI M1",   RVI1_Active,  INDI_RVI, PERIOD_M1,  RVI1_SignalMethod,  RVI_SignalLevel, RVI1_OpenCondition1,  RVI1_OpenCondition2,  RVI1_CloseCondition,  RVI1_MaxSpread);
  init &= !RVI5_Active  |  InitStrategy(RVI5,  "RVI M5",   RVI5_Active,  INDI_RVI, PERIOD_M5,  RVI5_SignalMethod,  RVI_SignalLevel, RVI5_OpenCondition1,  RVI5_OpenCondition2,  RVI5_CloseCondition,  RVI5_MaxSpread);
  init &= !RVI15_Active | InitStrategy(RVI15, "RVI M15", RVI15_Active, INDI_RVI, PERIOD_M15, RVI15_SignalMethod, RVI_SignalLevel, RVI15_OpenCondition1, RVI15_OpenCondition2, RVI15_CloseCondition, RVI15_MaxSpread);
  init &= !RVI30_Active | InitStrategy(RVI30, "RVI M30", RVI30_Active, INDI_RVI, PERIOD_M30, RVI30_SignalMethod, RVI_SignalLevel, RVI30_OpenCondition1, RVI30_OpenCondition2, RVI30_CloseCondition, RVI30_MaxSpread);

  init &= !SAR1_Active  | InitStrategy(SAR1,  "SAR M1",   SAR1_Active,  INDI_SAR, PERIOD_M1,  SAR1_SignalMethod,  SAR_SignalLevel, SAR1_OpenCondition1,  SAR1_OpenCondition2,  SAR1_CloseCondition,  SAR1_MaxSpread);
  init &= !SAR5_Active  | InitStrategy(SAR5,  "SAR M5",   SAR5_Active,  INDI_SAR, PERIOD_M5,  SAR5_SignalMethod,  SAR_SignalLevel, SAR5_OpenCondition1,  SAR5_OpenCondition2,  SAR5_CloseCondition,  SAR5_MaxSpread);
  init &= !SAR15_Active | InitStrategy(SAR15, "SAR M15", SAR15_Active, INDI_SAR, PERIOD_M15, SAR15_SignalMethod, SAR_SignalLevel, SAR15_OpenCondition1, SAR15_OpenCondition2, SAR15_CloseCondition, SAR15_MaxSpread);
  init &= !SAR30_Active | InitStrategy(SAR30, "SAR M30", SAR30_Active, INDI_SAR, PERIOD_M30, SAR30_SignalMethod, SAR_SignalLevel, SAR30_OpenCondition1, SAR30_OpenCondition2, SAR30_CloseCondition, SAR30_MaxSpread);

  init &= !StdDev1_Active  | InitStrategy(STDDEV1,  "StdDev M1",   StdDev1_Active,  INDI_STDDEV, PERIOD_M1,  StdDev1_SignalMethod,  StdDev_SignalLevel,  StdDev1_OpenCondition1,  StdDev1_OpenCondition2,  StdDev1_CloseCondition,  StdDev1_MaxSpread);
  init &= !StdDev5_Active  | InitStrategy(STDDEV5,  "StdDev M5",   StdDev5_Active,  INDI_STDDEV, PERIOD_M5,  StdDev5_SignalMethod,  StdDev_SignalLevel,  StdDev5_OpenCondition1,  StdDev5_OpenCondition2,  StdDev5_CloseCondition,  StdDev5_MaxSpread);
  init &= !StdDev15_Active | InitStrategy(STDDEV15, "StdDev M15", StdDev15_Active, INDI_STDDEV, PERIOD_M15, StdDev15_SignalMethod, StdDev_SignalLevel, StdDev15_OpenCondition1, StdDev15_OpenCondition2, StdDev15_CloseCondition, StdDev15_MaxSpread);
  init &= !StdDev30_Active | InitStrategy(STDDEV30, "StdDev M30", StdDev30_Active, INDI_STDDEV, PERIOD_M30, StdDev30_SignalMethod, StdDev_SignalLevel, StdDev30_OpenCondition1, StdDev30_OpenCondition2, StdDev30_CloseCondition, StdDev30_MaxSpread);

  init &= !Stochastic1_Active  | InitStrategy(STOCHASTIC1,  "Stochastic M1",   Stochastic1_Active,  INDI_STOCHASTIC, PERIOD_M1,  Stochastic1_SignalMethod,  Stochastic_SignalLevel,  Stochastic1_OpenCondition1,  Stochastic1_OpenCondition2,  Stochastic1_CloseCondition,  Stochastic1_MaxSpread);
  init &= !Stochastic5_Active  | InitStrategy(STOCHASTIC5,  "Stochastic M5",   Stochastic5_Active,  INDI_STOCHASTIC, PERIOD_M5,  Stochastic5_SignalMethod,  Stochastic_SignalLevel,  Stochastic5_OpenCondition1,  Stochastic5_OpenCondition2,  Stochastic5_CloseCondition,  Stochastic5_MaxSpread);
  init &= !Stochastic15_Active | InitStrategy(STOCHASTIC15, "Stochastic M15", Stochastic15_Active, INDI_STOCHASTIC, PERIOD_M15, Stochastic15_SignalMethod, Stochastic_SignalLevel, Stochastic15_OpenCondition1, Stochastic15_OpenCondition2, Stochastic15_CloseCondition, Stochastic15_MaxSpread);
  init &= !Stochastic30_Active | InitStrategy(STOCHASTIC30, "Stochastic M30", Stochastic30_Active, INDI_STOCHASTIC, PERIOD_M30, Stochastic30_SignalMethod, Stochastic_SignalLevel, Stochastic30_OpenCondition1, Stochastic30_OpenCondition2, Stochastic30_CloseCondition, Stochastic30_MaxSpread);

  init &= !WPR1_Active  | InitStrategy(WPR1,  "WPR M1",   WPR1_Active,  INDI_WPR, PERIOD_M1,  WPR1_SignalMethod,  WPR_SignalLevel, WPR1_OpenCondition1,  WPR1_OpenCondition2,  WPR1_CloseCondition,  WPR1_MaxSpread);
  init &= !WPR5_Active  | InitStrategy(WPR5,  "WPR M5",   WPR5_Active,  INDI_WPR, PERIOD_M5,  WPR5_SignalMethod,  WPR_SignalLevel, WPR5_OpenCondition1,  WPR5_OpenCondition2,  WPR5_CloseCondition,  WPR5_MaxSpread);
  init &= !WPR15_Active | InitStrategy(WPR15, "WPR M15", WPR15_Active, INDI_WPR, PERIOD_M15, WPR15_SignalMethod, WPR_SignalLevel, WPR15_OpenCondition1, WPR15_OpenCondition2, WPR15_CloseCondition, WPR15_MaxSpread);
  init &= !WPR30_Active | InitStrategy(WPR30, "WPR M30", WPR30_Active, INDI_WPR, PERIOD_M30, WPR30_SignalMethod, WPR_SignalLevel, WPR30_OpenCondition1, WPR30_OpenCondition2, WPR30_CloseCondition, WPR30_MaxSpread);

  init &= !ZigZag1_Active  | InitStrategy(ZIGZAG1,  "ZigZag M1",   ZigZag1_Active,  INDI_ZIGZAG, PERIOD_M1,  ZigZag1_SignalMethod,  ZigZag_SignalLevel, ZigZag1_OpenCondition1,  ZigZag1_OpenCondition2,  ZigZag1_CloseCondition,  ZigZag1_MaxSpread);
  init &= !ZigZag5_Active  | InitStrategy(ZIGZAG5,  "ZigZag M5",   ZigZag5_Active,  INDI_ZIGZAG, PERIOD_M5,  ZigZag5_SignalMethod,  ZigZag_SignalLevel, ZigZag5_OpenCondition1,  ZigZag5_OpenCondition2,  ZigZag5_CloseCondition,  ZigZag5_MaxSpread);
  init &= !ZigZag15_Active | InitStrategy(ZIGZAG15, "ZigZag M15", ZigZag15_Active, INDI_ZIGZAG, PERIOD_M15, ZigZag15_SignalMethod, ZigZag_SignalLevel, ZigZag15_OpenCondition1, ZigZag15_OpenCondition2, ZigZag15_CloseCondition, ZigZag15_MaxSpread);
  init &= !ZigZag30_Active | InitStrategy(ZIGZAG30, "ZigZag M30", ZigZag30_Active, INDI_ZIGZAG, PERIOD_M30, ZigZag30_SignalMethod, ZigZag_SignalLevel, ZigZag30_OpenCondition1, ZigZag30_OpenCondition2, ZigZag30_CloseCondition, ZigZag30_MaxSpread);

  if (!init && ValidateSettings) {
    Msg::ShowText(Chart::ListTimeframes(), "Info", __FUNCTION__, __LINE__, VerboseInfo);
    Msg::ShowText("Initiation of strategies failed!", "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
  }

  Array::ArrSetValueD(conf, FACTOR, 1.0);
  Array::ArrSetValueD(conf, LOT_SIZE, ea_lot_size);

  #ifdef __profiler__ PROFILER_STOP #endif
  return init || !ValidateSettings;
}

/**
 * Init classes.
 */
bool InitClasses() {
  #ifdef __profiler__ PROFILER_START #endif

  // Initialize main classes.
  account = new Account();
  logger = new Log(V_DEBUG);
  market = new Market(_Symbol, logger);

  // Initialize the current chart.
  ENUM_TIMEFRAMES_INDEX _tfi = Chart::TfToIndex(PERIOD_CURRENT);
  TradeParams trade_params;
  trade_params.account = account;
  trade_params.chart = new Chart(_tfi);
  trade_params.logger = logger;
  trade[_tfi] = new Trade(trade_params);

  // Verify that the current chart has been initialized correctly.
  if (Object::IsDynamic(trade[_tfi]) && trade[_tfi].Chart().IsValidTf()) {
    // Assign to the current chart.
    chart = trade[_tfi].Chart();
  }
  else {
    Msg::ShowText(
      StringFormat("Cannot initialize the current timeframe (%s)!", Chart::IndexToString(_tfi)),
      "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
    return false;
  }

  // Initialize the trend's chart.
  ENUM_TIMEFRAMES_INDEX _ttfi = Chart::TfToIndex(TrendPeriod);
  if (!Object::IsDynamic(trade[_ttfi]) || !trade[_ttfi].Chart().IsValidTf()) {
    TradeParams ttrade_params;
    ttrade_params.account = account;
    ttrade_params.chart = new Chart(_ttfi);
    ttrade_params.logger = logger;
    trade[_ttfi] = new Trade(ttrade_params);
    // Verify the trend's chart.
    if (!Object::IsDynamic(trade[_ttfi]) || !trade[_ttfi].Chart().IsValidTf()) {
      Msg::ShowText(
        StringFormat("Cannot initialize the trend's timeframe (%s)!", Chart::IndexToString(_ttfi)),
        "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
      return false;
    }
  }

  ticker = new Ticker(market);
  summary_report = new SummaryReport();
  terminal = market.TerminalHandler();
  #ifdef __profiler__ PROFILER_STOP #endif
  return market.GetSymbol() == _Symbol;
}

/**
 * Initialize specific strategy.
 */
bool InitStrategy(int key, string name, bool active, ENUM_INDICATOR_TYPE indicator, ENUM_TIMEFRAMES _tf, int signal_method = 0, double signal_level = 0.0, int open_cond1 = 0, int open_cond2 = 0, int close_cond = 0, double max_spread = 0.0) {
  if (active) {
    ENUM_TIMEFRAMES_INDEX _tfi = Chart::TfToIndex(_tf);
    // Validate the timeframe.
    if (!Object::IsValid(trade[_tfi]) || !trade[_tfi].Chart().IsValidTf(_tf)) {

      // Initialize the Trade instance and its chart.
      TradeParams trade_params;
      trade_params.account = account;
      trade_params.chart = new Chart(_tfi);
      trade_params.logger = logger;
      trade[_tfi] = new Trade(trade_params);

      if (!Object::IsValid(trade[_tfi]) || !trade[_tfi].Chart().IsValidTf(_tf)) {
        Msg::ShowText(
          StringFormat("Cannot initialize %s strategy, because its timeframe (%d) is not active!%s", name, _tf, ValidateSettings ? " Disabling..." : ""),
          "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
        active = false;
      }
    }
    // Validate whether indicator of the strategy is working.
    else if (!UpdateIndicator(trade[_tfi].Chart(), indicator)) {
      Msg::ShowText(
        StringFormat("Cannot initialize indicator for the %s strategy!%s", name, ValidateSettings ? " Disabling..." : ""),
        "Error", __FUNCTION__, __LINE__, VerboseErrors, PrintLogOnChart, ValidateSettings);
      active = false;
    }
  }
  sname[key]                 = name;
  info[key][ACTIVE]          = active;
  info[key][SUSPENDED]       = false;
  info[key][TIMEFRAME]       = _tf;
  info[key][INDICATOR]       = indicator;
  info[key][OPEN_METHOD]     = signal_method;
  conf[key][OPEN_LEVEL]      = signal_level;
  conf[key][PROFIT_FACTOR]   = GetDefaultProfitFactor();
  info[key][CLOSE_CONDITION] = close_cond;
  // #ifdef __advanced__
  info[key][OPEN_CONDITION1] = open_cond1;
  info[key][OPEN_CONDITION2] = open_cond2;
  conf[key][SPREAD_LIMIT]    = max_spread;
  // #endif
  return active || !ValidateSettings;
}

/**
 * Update global variables.
 */
void UpdateVariables() {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  time_current = TimeCurrent();
  //curr_bar_time = chart.GetBarTime(PERIOD_M1);
  last_close_profit = EMPTY;
  total_orders = GetTotalOrders();
  curr_spread = market.GetSpreadInPips();
  // Calculate trend.
  // curr_trend = trade.GetTrend(fabs(TrendMethod), TrendMethod < 0 ? PERIOD_M1 : (ENUM_TIMEFRAMES) NULL);
  double curr_rsi = iRSI(market.GetSymbol(), TrendPeriod, RSI_Period, RSI_Applied_Price, 0);
  curr_trend = fabs(curr_rsi - 50) > 10 ? (double) (1.0 / 50) * (curr_rsi - 50) : 0;
  // PrintFormat("Curr Trend: %g (%g: %g/%g), RSI: %g", curr_trend, (double) (1.0 / 50) * (curr_rsi - 50), 1 / 50, curr_rsi - 50, curr_rsi);
  #ifdef __profiler__ PROFILER_STOP #endif
}

/* END: VARIABLE FUNCTIONS */

/* BEGIN: CONDITION FUNCTIONS */

/**
 * Initialize user defined conditions.
 */
bool InitializeConditions() {
  acc_conditions[0][0] = Account_Condition_1;
  acc_conditions[0][1] = Market_Condition_1;
  acc_conditions[0][2] = Action_On_Condition_1;

  acc_conditions[1][0] = Account_Condition_2;
  acc_conditions[1][1] = Market_Condition_2;
  acc_conditions[1][2] = Action_On_Condition_2;

  acc_conditions[2][0] = Account_Condition_3;
  acc_conditions[2][1] = Market_Condition_3;
  acc_conditions[2][2] = Action_On_Condition_3;

  acc_conditions[3][0] = Account_Condition_4;
  acc_conditions[3][1] = Market_Condition_4;
  acc_conditions[3][2] = Action_On_Condition_4;

  acc_conditions[4][0] = Account_Condition_5;
  acc_conditions[4][1] = Market_Condition_5;
  acc_conditions[4][2] = Action_On_Condition_5;

  #ifdef __advanced__
  acc_conditions[5][0] = Account_Condition_6;
  acc_conditions[5][1] = Market_Condition_6;
  acc_conditions[5][2] = Action_On_Condition_6;
  acc_conditions[6][0] = Account_Condition_7;
  acc_conditions[6][1] = Market_Condition_7;
  acc_conditions[6][2] = Action_On_Condition_7;
  acc_conditions[7][0] = Account_Condition_8;
  acc_conditions[7][1] = Market_Condition_8;
  acc_conditions[7][2] = Action_On_Condition_8;
  acc_conditions[8][0] = Account_Condition_9;
  acc_conditions[8][1] = Market_Condition_9;
  acc_conditions[8][2] = Action_On_Condition_9;
  acc_conditions[9][0] = Account_Condition_10;
  acc_conditions[9][1] = Market_Condition_10;
  acc_conditions[9][2] = Action_On_Condition_10;
  acc_conditions[10][0] = Account_Condition_11;
  acc_conditions[10][1] = Market_Condition_11;
  acc_conditions[10][2] = Action_On_Condition_11;
  acc_conditions[11][0] = Account_Condition_12;
  acc_conditions[11][1] = Market_Condition_12;
  acc_conditions[11][2] = Action_On_Condition_12;
  acc_conditions[12][0] = Account_Condition_13;
  acc_conditions[12][1] = Market_Condition_13;
  acc_conditions[12][2] = Action_On_Condition_13;
  acc_conditions[13][0] = Account_Condition_14;
  acc_conditions[13][1] = Market_Condition_14;
  acc_conditions[13][2] = Action_On_Condition_14;
  acc_conditions[14][0] = Account_Condition_15;
  acc_conditions[14][1] = Market_Condition_15;
  acc_conditions[14][2] = Action_On_Condition_15;
  acc_conditions[15][0] = Account_Condition_16;
  acc_conditions[15][1] = Market_Condition_16;
  acc_conditions[15][2] = Action_On_Condition_16;
  acc_conditions[16][0] = Account_Condition_17;
  acc_conditions[16][1] = Market_Condition_17;
  acc_conditions[16][2] = Action_On_Condition_17;
  acc_conditions[17][0] = Account_Condition_18;
  acc_conditions[17][1] = Market_Condition_18;
  acc_conditions[17][2] = Action_On_Condition_18;
  acc_conditions[18][0] = Account_Condition_19;
  acc_conditions[18][1] = Market_Condition_19;
  acc_conditions[18][2] = Action_On_Condition_19;
  acc_conditions[19][0] = Account_Condition_20;
  acc_conditions[19][1] = Market_Condition_20;
  acc_conditions[19][2] = Action_On_Condition_20;
  acc_conditions[20][0] = Account_Condition_21;
  acc_conditions[20][1] = Market_Condition_21;
  acc_conditions[20][2] = Action_On_Condition_21;
  acc_conditions[21][0] = Account_Condition_22;
  acc_conditions[21][1] = Market_Condition_22;
  acc_conditions[21][2] = Action_On_Condition_22;
  acc_conditions[22][0] = Account_Condition_23;
  acc_conditions[22][1] = Market_Condition_23;
  acc_conditions[22][2] = Action_On_Condition_23;
  acc_conditions[23][0] = Account_Condition_24;
  acc_conditions[23][1] = Market_Condition_24;
  acc_conditions[23][2] = Action_On_Condition_24;
  acc_conditions[24][0] = Account_Condition_25;
  acc_conditions[24][1] = Market_Condition_25;
  acc_conditions[24][2] = Action_On_Condition_25;
  acc_conditions[25][0] = Account_Condition_26;
  acc_conditions[25][1] = Market_Condition_26;
  acc_conditions[25][2] = Action_On_Condition_26;
  acc_conditions[26][0] = Account_Condition_27;
  acc_conditions[26][1] = Market_Condition_27;
  acc_conditions[26][2] = Action_On_Condition_27;
  acc_conditions[27][0] = Account_Condition_28;
  acc_conditions[27][1] = Market_Condition_28;
  acc_conditions[27][2] = Action_On_Condition_28;
  acc_conditions[28][0] = Account_Condition_29;
  acc_conditions[28][1] = Market_Condition_29;
  acc_conditions[28][2] = Action_On_Condition_29;
  acc_conditions[29][0] = Account_Condition_30;
  acc_conditions[29][1] = Market_Condition_30;
  acc_conditions[29][2] = Action_On_Condition_30;
  #endif

  if (AccountConditionToDisable > 0 && AccountConditionToDisable < ArraySize(acc_conditions)) {
    acc_conditions[AccountConditionToDisable - 1][0] = C_ACC_NONE;
    acc_conditions[AccountConditionToDisable - 1][1] = C_MARKET_NONE;
    acc_conditions[AccountConditionToDisable - 1][2] = A_NONE;
  }
  return true;
}

/**
 * Check account condition.
 */
bool AccCondition(int condition = C_ACC_NONE) {
  switch(condition) {
    case C_ACC_TRUE:
      last_cname = "true";
      return true;
    case C_EQUITY_LOWER:
      last_cname = "Equ<Bal";
      return account.AccountEquity() < account.AccountBalance() + account.AccountCredit();
    case C_EQUITY_HIGHER:
      last_cname = "Equ>Bal";
      return account.AccountEquity() > account.AccountBalance() + account.AccountCredit();
    case C_EQUITY_50PC_HIGH: // Equity 50% high
      last_cname = "Equ>50%";
      return account.AccountEquity() > (account.AccountBalance() + account.AccountCredit()) * 2;
    case C_EQUITY_20PC_HIGH: // Equity 20% high
      last_cname = "Equ>20%";
      return account.AccountEquity() > (account.AccountBalance() + account.AccountCredit()) / 100 * 120;
    case C_EQUITY_10PC_HIGH: // Equity 10% high
      last_cname = "Equ>10%";
      return account.AccountEquity() > (account.AccountBalance() + account.AccountCredit()) / 100 * 110;
    case C_EQUITY_10PC_LOW:  // Equity 10% low
      last_cname = "Equ<10%";
      return account.AccountEquity() < (account.AccountBalance() + account.AccountCredit()) / 100 * 90;
    case C_EQUITY_20PC_LOW:  // Equity 20% low
      last_cname = "Equ<20%";
      return account.AccountEquity() < (account.AccountBalance() + account.AccountCredit()) / 100 * 80;
    case C_EQUITY_50PC_LOW:  // Equity 50% low
      last_cname = "Equ<50%";
      return account.AccountEquity() <= (account.AccountBalance() + account.AccountCredit()) / 2;
    case C_MARGIN_USED_50PC: // 50% Margin Used
      last_cname = "Margin>50%";
      return account.AccountMargin() >= account.AccountEquity() /100 * 50;
    case C_MARGIN_USED_70PC: // 70% Margin Used
      // Note that in some accounts, Stop Out will occur in your account when equity reaches 70% of your used margin resulting in immediate closing of all positions.
      last_cname = "Margin>70%";
      return account.AccountMargin() >= account.AccountEquity() /100 * 70;
    case C_MARGIN_USED_80PC: // 80% Margin Used
      last_cname = "Margin>80%";
      return account.AccountMargin() >= account.AccountEquity() /100 * 80;
    case C_MARGIN_USED_90PC: // 90% Margin Used
      last_cname = "Margin>90%";
      return account.AccountMargin() >= account.AccountEquity() /100 * 90;
    case C_NO_FREE_MARGIN:
      last_cname = "NoMargin%";
      return account.AccountFreeMargin() <= 10;
    case C_ACC_IN_LOSS:
      last_cname = "AccInLoss";
      return GetTotalProfit() < 0;
    case C_ACC_IN_PROFIT:
      last_cname = "AccInProfit";
      return GetTotalProfit() > 0;
    case C_DBAL_LT_WEEKLY:
      last_cname = "DBal<WBal";
      return daily[MAX_BALANCE] < weekly[MAX_BALANCE];
    case C_DBAL_GT_WEEKLY:
      last_cname = "DBal>WBal";
      return daily[MAX_BALANCE] > weekly[MAX_BALANCE];
    case C_WBAL_LT_MONTHLY:
      last_cname = "WBal<MBal";
      return weekly[MAX_BALANCE] < monthly[MAX_BALANCE];
    case C_WBAL_GT_MONTHLY:
      last_cname = "WBal>MBal";
      return weekly[MAX_BALANCE] > monthly[MAX_BALANCE];
    case C_ACC_IN_TREND:
      last_cname = "InTrend";
      return (Convert::ValueToOp(curr_trend) == ORDER_TYPE_BUY && Orders::GetOrdersByType(ORDER_TYPE_BUY)  > Orders::GetOrdersByType(ORDER_TYPE_SELL))
          || (Convert::ValueToOp(curr_trend) == ORDER_TYPE_SELL && Orders::GetOrdersByType(ORDER_TYPE_SELL) > Orders::GetOrdersByType(ORDER_TYPE_BUY));
    case C_ACC_IN_NON_TREND:
      last_cname = "InNonTrend";
      return !AccCondition(C_ACC_IN_TREND);
    case C_ACC_CDAY_IN_PROFIT: // Check if current day in profit.
      last_cname = "TodayInProfit";
      return Array::GetArrSumKey1(hourly_profit, day_of_year, 10) > 0;
    case C_ACC_CDAY_IN_LOSS: // Check if current day in loss.
      last_cname = "TodayInLoss";
      return Array::GetArrSumKey1(hourly_profit, day_of_year, 10) < 0;
    case C_ACC_PDAY_IN_PROFIT: // Check if previous day in profit.
      {
        last_cname = "YesterdayInProfit";
        int yesterday1 = DateTime::TimeDayOfYear(time_current - 24*60*60);
        return Array::GetArrSumKey1(hourly_profit, yesterday1) > 0;
      }
    case C_ACC_PDAY_IN_LOSS: // Check if previous day in loss.
      {
        last_cname = "YesterdayInLoss";
        int yesterday2 = DateTime::TimeDayOfYear(time_current - 24*60*60);
        return Array::GetArrSumKey1(hourly_profit, yesterday2) < 0;
      }
    case C_ACC_MAX_ORDERS:
      return total_orders >= max_orders;
    default:
    case C_ACC_NONE:
      last_cname = "None";
      return false;
  }
  return false;
}

/**
 * Check market condition.
 */
bool MarketCondition(Chart *_chart, int condition = C_MARKET_NONE) {
  static int counter = 0;
  // if (VerboseTrace) Print(__FUNCTION__);
  switch(condition) {
    case C_MARKET_TRUE:
      return true;
    case C_MA1_FS_TREND_OPP: // MA Fast and Slow M1 are in opposite directions.
      return CheckMarketEvent(trade[M1].Chart(), Convert::ValueToOp(curr_trend), C_MA_FAST_SLOW_OPP);
    case C_MA5_FS_TREND_OPP: // MA Fast and Slow M5 are in opposite directions.
      return CheckMarketEvent(trade[M5].Chart(), Convert::ValueToOp(curr_trend), C_MA_FAST_SLOW_OPP);
    case C_MA15_FS_TREND_OPP:
      return CheckMarketEvent(trade[M15].Chart(), Convert::ValueToOp(curr_trend), C_MA_FAST_SLOW_OPP);
    case C_MA30_FS_TREND_OPP:
      return CheckMarketEvent(trade[M30].Chart(), Convert::ValueToOp(curr_trend), C_MA_FAST_SLOW_OPP);
    case C_MA1_FS_ORDERS_OPP: // MA Fast and Slow M1 are in opposite directions.
      return CheckMarketEvent(trade[M1].Chart(), GetCmdByOrders(), C_MA_FAST_SLOW_OPP);
    case C_MA5_FS_ORDERS_OPP: // MA Fast and Slow M5 are in opposite directions.
      return CheckMarketEvent(trade[M5].Chart(), GetCmdByOrders(), C_MA_FAST_SLOW_OPP);
    case C_MA15_FS_ORDERS_OPP:
      return CheckMarketEvent(trade[M15].Chart(), GetCmdByOrders(), C_MA_FAST_SLOW_OPP);
    case C_MA30_FS_ORDERS_OPP:
      return CheckMarketEvent(trade[M30].Chart(), GetCmdByOrders(), C_MA_FAST_SLOW_OPP);
    case C_DAILY_PEAK:
      return hour_of_day >= HourAfterPeak && (market.GetLastAsk() >= _chart.iHigh(_Symbol, PERIOD_D1, CURR) || market.GetLastAsk() <= _chart.iLow(_Symbol, PERIOD_D1, CURR));
    case C_WEEKLY_PEAK:
      return hour_of_day >= HourAfterPeak && (market.GetLastAsk() >= _chart.iHigh(_Symbol, PERIOD_W1, CURR) || market.GetLastAsk() <= _chart.iLow(_Symbol, PERIOD_W1, CURR));
    case C_MONTHLY_PEAK:
      return hour_of_day >= HourAfterPeak && (market.GetLastAsk() >= _chart.iHigh(_Symbol, PERIOD_MN1, CURR) || market.GetLastAsk() <= _chart.iLow(_Symbol, PERIOD_MN1, CURR));
    case C_MARKET_BIG_DROP:
      return last_pip_change > MarketSuddenDropSize;
    case C_MARKET_VBIG_DROP:
      return last_pip_change > MarketBigDropSize;
    case C_MARKET_AT_HOUR:
      {
        static int hour_invoked = -1;
        if (MarketSpecificHour == hour_of_day && hour_invoked <= hour_of_day) {
          // Invoke only once a day.
          hour_invoked = hour_of_day + 1;
          return (true);
        } else {
          if (hour_of_day < hour_invoked) {
            // Reset hour on the next day.
            hour_invoked = -1;
          }
          return (false);
        }
      }
    case C_NEW_HOUR:
      return hour_of_day != Hour();
    case C_NEW_DAY:
      return day_of_week != DayOfWeek();
    case C_NEW_WEEK:
      return DayOfWeek() < day_of_week;
    case C_NEW_MONTH:
      return Day() < day_of_month;
    case C_MARKET_NONE:
    default:
      return false;
  }
  return false;
}

/**
 * Check the account for configured conditions.
 */
void CheckAccConditions(Chart *_chart) {
  if (!Account_Conditions_Active || last_action_time + 60 < DateTime::TimeTradeServer()) {
    // Do not execute action more often than a minute.
    // @todo: Move 60 second rule into the external param.
    return;
  }

  #ifdef __profiler__ PROFILER_START #endif

  for (int i = 0; i < ArrayRange(acc_conditions, 0); i++) {
    if (AccCondition(acc_conditions[i][0]) && MarketCondition(_chart, acc_conditions[i][1]) && acc_conditions[i][2] != A_NONE) {
      ActionExecute(acc_conditions[i][2], i);
    }
  } // end: for
  #ifdef __profiler__ PROFILER_STOP #endif
}

/**
 * Get default multiplier lot factor.
 */
double GetDefaultProfitFactor() {
  return 1.0;
}

/* BEGIN: STRATEGY FUNCTIONS */

/**
 * Calculate lot size for specific strategy.
 */
double GetStrategyLotSize(int sid, ENUM_ORDER_TYPE cmd) {
  double trade_lot = (conf[sid][LOT_SIZE] > 0 ? conf[sid][LOT_SIZE] : ea_lot_size) * (conf[sid][FACTOR] > 0 ? conf[sid][FACTOR] : 1.0);
  if (Boosting_Enabled) {
    double pf = GetStrategyProfitFactor(sid);
    if (pf > 0) {
      if (StrategyBoostByPF && pf > 1.0) trade_lot *= fmax(GetStrategyProfitFactor(sid), 1.0);
      else if (StrategyHandicapByPF && pf < 1.0) trade_lot *= fmin(GetStrategyProfitFactor(sid), 1.0);
    }
    if (Convert::ValueToOp(curr_trend) == cmd && BoostTrendFactor != 1.0) {
      if (VerboseDebug) PrintFormat("%s:%d: %s: Factor: %g, Trade lot: %g, Final trade lot: %g",
        __FUNCTION__, __LINE__, sname[sid], conf[sid][FACTOR], trade_lot, trade_lot * BoostTrendFactor);
      trade_lot *= BoostTrendFactor;
    }
  }
  return market.NormalizeLots(trade_lot);
}

/**
 * Get strategy comment for opened order.
 */
string GetStrategyComment(int sid) {
  return StringFormat("%s; %.1f pips spread; sid: %d", sname[sid], curr_spread, sid);
}

/**
 * Get strategy report based on the total orders.
 */
string GetStrategyReport(string sep = "\n") {
  string output = "Strategy stats:" + sep;
  for (int id = 0; id < FINAL_STRATEGY_TYPE_ENTRY; id++) {
    if (info[id][TOTAL_ORDERS] > 0) {
      output += StringFormat("Profit factor: %.2f, ",
                GetStrategyProfitFactor(id));
      output += StringFormat("Total net profit: %.2f%s [%+.2f/%-.2f] (%.2fpips), ",
        stats[id][TOTAL_NET_PROFIT], account.GetCurrency(),
        stats[id][TOTAL_GROSS_PROFIT], stats[id][TOTAL_GROSS_LOSS],
        stats[id][TOTAL_PIP_PROFIT]);
      output += StringFormat("Total orders: %d (Won: %.1f%% [%d] / Loss: %.1f%% [%d])",
                info[id][TOTAL_ORDERS],
                (100 / NormalizeDouble(info[id][TOTAL_ORDERS], 2)) * info[id][TOTAL_ORDERS_WON],
                info[id][TOTAL_ORDERS_WON],
                (100 / NormalizeDouble(info[id][TOTAL_ORDERS], 2)) * info[id][TOTAL_ORDERS_LOSS],
                info[id][TOTAL_ORDERS_LOSS]);
      output += info[id][TOTAL_ERRORS] > 0 ? StringFormat(", Errors: %d", info[id][TOTAL_ERRORS]) : "";
      output += StringFormat(" - %s", sname[id]);
      output += sep;
    }
  }
  return output;
}

/**
 * Apply strategy boosting.
 */
void UpdateStrategyFactor(uint period) {
  switch (period) {
    case DAILY:
      ApplyStrategyMultiplierFactor(DAILY, 1, BestDailyStrategyMultiplierFactor);
      ApplyStrategyMultiplierFactor(DAILY, -1, WorseDailyStrategyMultiplierFactor);
      break;
    case WEEKLY:
      if (day_of_week > 1) {
        // FIXME: When commented out with 1.0, the profit is different.
        ApplyStrategyMultiplierFactor(WEEKLY, 1, BestWeeklyStrategyMultiplierFactor);
        ApplyStrategyMultiplierFactor(WEEKLY, -1, WorseWeeklyStrategyMultiplierFactor);
      }
    break;
    case MONTHLY:
      ApplyStrategyMultiplierFactor(MONTHLY, 1, BestMonthlyStrategyMultiplierFactor);
      ApplyStrategyMultiplierFactor(MONTHLY, -1, WorseMonthlyStrategyMultiplierFactor);
    break;
  }
}

/**
 * Update strategy lot size.
 */
void UpdateStrategyLotSize() {
  for (int i = 0; i < ArrayRange(conf, 0); i++) {
    conf[i][LOT_SIZE] = ea_lot_size * conf[i][FACTOR];
  }
}

/**
 * Calculate strategy profit factor.
 */
double GetStrategyProfitFactor(int sid) {
  if (info[sid][TOTAL_ORDERS] > InitNoOfOrdersToCalcPF && stats[sid][TOTAL_GROSS_LOSS] < 0) {
    return stats[sid][TOTAL_GROSS_PROFIT] / -stats[sid][TOTAL_GROSS_LOSS];
  } else {
    return 1.0; // @todo?
  }
}

/**
 * Fetch strategy signal level based on the indicator and timeframe.
 */
double GetStrategySignalLevel(ENUM_INDICATOR_TYPE indicator, ENUM_TIMEFRAMES timeframe = PERIOD_M30, double default_value = 0.0) {
  DEBUG_CHECKPOINT_ADD
  int sid = GetStrategyViaIndicator(indicator, timeframe);
  // Message(StringFormat("%s(): indi = %d, timeframe = %d, sid = %d, signal_level = %f", __FUNCTION__, indicator, timeframe, sid, conf[sid][OPEN_LEVEL]));
  DEBUG_CHECKPOINT_POP
  return sid >= 0 ? conf[sid][OPEN_LEVEL] : default_value;
}

/**
 * Fetch strategy signal level based on the indicator and timeframe.
 */
int GetStrategySignalMethod(ENUM_INDICATOR_TYPE indicator, ENUM_TIMEFRAMES timeframe = PERIOD_M30, int default_value = 0) {
  DEBUG_CHECKPOINT_ADD
  int sid = GetStrategyViaIndicator(indicator, timeframe);
  DEBUG_CHECKPOINT_POP
  return sid >= 0 ? info[sid][OPEN_METHOD] : default_value;
}

/**
 * Fetch strategy timeframe based on the strategy type.
 */
ENUM_TIMEFRAMES GetStrategyTimeframe(int sid, int default_value = PERIOD_M1) {
  return (ENUM_TIMEFRAMES) (sid >= 0 ? info[sid][TIMEFRAME] : default_value);
}

/**
 * Fetch strategy timeframe index based on the strategy type.
 */
ENUM_TIMEFRAMES_INDEX GetStrategyTimeframeIndex(int sid, int default_value = PERIOD_M1) {
  return (ENUM_TIMEFRAMES_INDEX) (sid >= 0 ? Chart::TfToIndex((ENUM_TIMEFRAMES) info[sid][TIMEFRAME]) : default_value);
}

/**
 * Get strategy id based on the indicator and tf.
 */
int GetStrategyViaIndicator(ENUM_INDICATOR_TYPE _indicator, ENUM_TIMEFRAMES _tf) {
  DEBUG_CHECKPOINT_ADD
  for (int sid = 0; sid < ArrayRange(info, 0); sid++) {
    if ((ENUM_INDICATOR_TYPE) info[sid][INDICATOR] == _indicator && (ENUM_TIMEFRAMES) info[sid][TIMEFRAME] == _tf) {
      return sid;
    }
  }
  Msg::ShowText(
    StringFormat("Cannot find indicator %d (%s) for timeframe: %d", _indicator, EnumToString(_indicator), _tf),
    "Error", __FUNCTION__, __LINE__, VerboseErrors | VerboseDebug
    );
  DEBUG_STACK_PRINT
  DEBUG_CHECKPOINT_POP
  return EMPTY;
}

/**
 * Calculate total strategy profit.
 */
double GetTotalProfit() {
  double total_profit = 0;
  for (int id = 0; id < ArrayRange(stats, 0); id++) {
    total_profit += stats[id][TOTAL_NET_PROFIT];
  }
  return total_profit;
}

/**
 * Apply strategy multiplier factor based on the strategy profit or loss.
 */
void ApplyStrategyMultiplierFactor(uint period = DAILY, int direction = 0, double factor = 1.0) {
  if (GetNoOfStrategies() <= 1 || factor == 1.0) return;
  int key = period == MONTHLY ? MONTHLY_PROFIT : (period == WEEKLY ? (int)WEEKLY_PROFIT : (int)DAILY_PROFIT);
  string period_name = period == MONTHLY ? "montly" : (period == WEEKLY ? "weekly" : "daily");
  int new_strategy = direction > 0 ? Array::GetArrKey1ByHighestKey2ValueD(stats, key) : Array::GetArrKey1ByLowestKey2ValueD(stats, key);
  if (new_strategy == EMPTY) return;
  int previous = direction > 0 ? best_strategy[period] : worse_strategy[period];
  double new_factor = 1.0;
  if (direction > 0) { // Best strategy.
    if (info[new_strategy][ACTIVE] && stats[new_strategy][key] > 10 && new_strategy != previous) { // Check if it's different than the previous one.
      if (previous != EMPTY) {
        if (!info[previous][ACTIVE]) info[previous][ACTIVE] = true;
        conf[previous][FACTOR] = GetDefaultProfitFactor(); // Set previous strategy multiplier factor to default.
        Msg::ShowText(StringFormat("Setting multiplier factor to default for strategy: %g", previous), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
      }
      best_strategy[period] = new_strategy; // Assign the new worse strategy.
      info[new_strategy][ACTIVE] = true;
      new_factor = GetDefaultProfitFactor() * factor;
      conf[new_strategy][FACTOR] = new_factor; // Apply multiplier factor for the new strategy.
     Msg::ShowText(StringFormat("Setting multiplier factor to %g for strategy: %d (period: %s)", new_factor, new_strategy, period_name), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
    }
  } else { // Worse strategy.
    if (info[new_strategy][ACTIVE] && stats[new_strategy][key] < 10 && new_strategy != previous) { // Check if it's different than the previous one.
      if (previous != EMPTY) {
        if (!info[previous][ACTIVE]) info[previous][ACTIVE] = true;
        conf[previous][FACTOR] = GetDefaultProfitFactor(); // Set previous strategy multiplier factor to default.
        Msg::ShowText(StringFormat("Setting multiplier factor to default for strategy: %g to default.", previous), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
      }
      worse_strategy[period] = new_strategy; // Assign the new worse strategy.
      if (factor > 0) {
        new_factor = GetDefaultProfitFactor() * factor;
        info[new_strategy][ACTIVE] = true;
        conf[new_strategy][FACTOR] = new_factor; // Apply multiplier factor for the new strategy.
        Msg::ShowText(StringFormat("Setting multiplier factor to %g for strategy: %d (period: %s)", new_factor, new_strategy, period_name), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
      } else {
        info[new_strategy][ACTIVE] = false;
        //conf[new_strategy][FACTOR] = GetDefaultProfitFactor();
        Msg::ShowText(StringFormat("Disabling strategy: %d", new_strategy), "Debug", __FUNCTION__, __LINE__, VerboseDebug);
      }
    }
  }
}

#ifdef __advanced__
/**
 * Check if RSI period needs any change.
 *
 * FIXME: Doesn't improve much.
 */
/*
void RSI_CheckPeriod() {

  uint period;
  // 1 minute period.
  period = M1;
  if (rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] < RSI1_IncreasePeriod_MinDiff) {
    info[RSI1][CUSTOM_PERIOD] = fmin(info[RSI1][CUSTOM_PERIOD] + 1, RSI_Period * 2);
    if (VerboseDebug) PrintFormat("Increased " + sname[RSI1] + " period to %d", info[RSI1][CUSTOM_PERIOD]);
    // Reset stats.
    rsi_stats[period][LINE_UPPER] = 0;
    rsi_stats[period][LINE_LOWER] = 0;
  } else if (rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] > RSI1_DecreasePeriod_MaxDiff) {
    info[RSI1][CUSTOM_PERIOD] = fmax(info[RSI1][CUSTOM_PERIOD] - 1, RSI_Period / 2);
    if (VerboseDebug) PrintFormat("Decreased " + sname[RSI1] + " period to %d", info[RSI1][CUSTOM_PERIOD]);
    // Reset stats.
    rsi_stats[period][LINE_UPPER] = 0;
    rsi_stats[period][LINE_LOWER] = 0;
  }
  // 5 minute period.
  period = M5;
  if (rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] < RSI5_IncreasePeriod_MinDiff) {
    info[RSI5][CUSTOM_PERIOD] = fmin(info[RSI5][CUSTOM_PERIOD] + 1, RSI_Period * 2);
    if (VerboseDebug) PrintFormat("Increased " + sname[RSI5] + " period to %d", info[RSI1][CUSTOM_PERIOD]);
    // Reset stats.
    rsi_stats[period][LINE_UPPER] = 0;
    rsi_stats[period][LINE_LOWER] = 0;
  } else if (rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] > RSI5_DecreasePeriod_MaxDiff) {
    info[RSI5][CUSTOM_PERIOD] = fmax(info[RSI5][CUSTOM_PERIOD] - 1, RSI_Period / 2);
    if (VerboseDebug) PrintFormat("Decreased " + sname[RSI5] + " period to %d", info[RSI1][CUSTOM_PERIOD]);
    // Reset stats.
    rsi_stats[period][LINE_UPPER] = 0;
    rsi_stats[period][LINE_LOWER] = 0;
  }
  // 15 minute period.

  period = M15;
  if (rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] < RSI15_IncreasePeriod_MinDiff) {
    info[RSI15][CUSTOM_PERIOD] = fmin(info[RSI15][CUSTOM_PERIOD] + 1, RSI_Period * 2);
    if (VerboseDebug) PrintFormat("Increased " + sname[RSI15] + " period to %d", info[RSI15][CUSTOM_PERIOD]);
    // Reset stats.
    rsi_stats[period][LINE_UPPER] = 0;
    rsi_stats[period][LINE_LOWER] = 0;
  } else if (rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] > RSI15_DecreasePeriod_MaxDiff) {
    info[RSI15][CUSTOM_PERIOD] = fmax(info[RSI15][CUSTOM_PERIOD] - 1, RSI_Period / 2);
    if (VerboseDebug) PrintFormat("Decreased " + sname[RSI15] + " period to %d", info[RSI15][CUSTOM_PERIOD]);
    // Reset stats.
    rsi_stats[period][LINE_UPPER] = 0;
    rsi_stats[period][LINE_LOWER] = 0;
  }
  /*
  Print(__FUNCTION__ + ": M1: Avg: " + rsi_stats[period][0] + ", Min: " + rsi_stats[period][LINE_LOWER] + ", Max: " + rsi_stats[period][LINE_UPPER] + ", Diff: " + ( rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] ));
  period = M5;
  Print(__FUNCTION__ + ": M5: Avg: " + rsi_stats[period][0] + ", Min: " + rsi_stats[period][LINE_LOWER] + ", Max: " + rsi_stats[period][LINE_UPPER] + ", Diff: " + ( rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] ));
  period = M15;
  Print(__FUNCTION__ + ": M15: Avg: " + rsi_stats[period][0] + ", Min: " + rsi_stats[period][LINE_LOWER] + ", Max: " + rsi_stats[period][LINE_UPPER] + ", Diff: " + ( rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] ));
  period = M30;
  Print(__FUNCTION__ + ": M30: Avg: " + rsi_stats[period][0] + ", Min: " + rsi_stats[period][LINE_LOWER] + ", Max: " + rsi_stats[period][LINE_UPPER] + ", Diff: " + ( rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] ));
  /
}
*/

// FIXME: Doesn't improve anything.
bool RSI_IncreasePeriod(Chart *_chart, int condition = 0) {
  bool result = condition > 0;
  UpdateIndicator(_chart, INDI_RSI);
  uint period = _chart.TfToIndex();
  if (METHOD(condition, 0)) result &= (rsi_stats[period][LINE_UPPER] > 50 + RSI_SignalLevel + RSI_SignalLevel / 2 && rsi_stats[period][LINE_LOWER] < 50 - RSI_SignalLevel - RSI_SignalLevel / 2);
  if (METHOD(condition, 1)) result &= (rsi_stats[period][LINE_UPPER] > 50 + RSI_SignalLevel + RSI_SignalLevel / 2 || rsi_stats[period][LINE_LOWER] < 50 - RSI_SignalLevel - RSI_SignalLevel / 2);
  if (METHOD(condition, 2)) result &= (rsi_stats[period][0] < 50 + RSI_SignalLevel + RSI_SignalLevel / 3 && rsi_stats[period][0] > 50 - RSI_SignalLevel - RSI_SignalLevel / 3);
  // if (METHOD(condition, 0)) result = result || rsi_stats[period][0] < 50 + RSI_SignalLevel;
  if (METHOD(condition, 3)) result &= rsi_stats[period][LINE_UPPER] - rsi_stats[period][LINE_LOWER] < 50;
  // if (METHOD(condition, 0)) result &= rsi[period][CURR] - rsi[period][PREV] > rsi[period][PREV] - rsi[period][FAR];
  // if (METHOD(condition, 0)) result &= Open[CURR] > Close[PREV];
  return result;
}

// FIXME: Doesn't improve anything.
bool RSI_DecreasePeriod(Chart *_chart, int condition = 0) {
  bool result = condition > 0;
  UpdateIndicator(_chart, INDI_RSI);
  uint period = _chart.TfToIndex();
  if (METHOD(condition, 0)) result &= (rsi_stats[period][LINE_UPPER] <= 50 + RSI_SignalLevel && rsi_stats[period][LINE_LOWER] >= 50 - RSI_SignalLevel);
  if (METHOD(condition, 1)) result &= (rsi_stats[period][LINE_UPPER] <= 50 + RSI_SignalLevel || rsi_stats[period][LINE_LOWER] >= 50 - RSI_SignalLevel);
  // if (METHOD(condition, 0)) result &= (rsi_stats[period][0] > 50 + RSI_SignalLevel / 3 || rsi_stats[period][0] < 50 - RSI_SignalLevel / 3);
  // if (METHOD(condition, 0)) result &= rsi_stats[period][LINE_UPPER] > 50 + (RSI_SignalLevel / 3);
  // if (METHOD(condition, 0)) result &= && rsi_stats[period][LINE_UPPER] < 50 - (RSI_SignalLevel / 3);
  // if (METHOD(condition, 0)) result &= rsi[period][CURR] - rsi[period][PREV] > rsi[period][PREV] - rsi[period][FAR];
  // if (METHOD(condition, 0)) result &= Open[CURR] > Close[PREV];
  return result;
}
#endif

/**
 * Return strategy id by order magic number.
 */
int GetIdByMagic(int magic = -1) {
  if (magic == -1) magic = OrderMagicNumber();
  int id = magic - MagicNumber;
  return CheckOurMagicNumber(magic) ? id : -1;
}

/* END: STRATEGY FUNCTIONS */

/* BEGIN: SUPPORT/RESISTANCE CALCULATION */

/**
// See: http://forum.mql4.com/49780
void CalculateSupRes() {
   int commonPoint;
   int minLevel, maxLevel;
   double highest, lowest, stepIncrement, tolerance, high;
   double storeLevel[];
   ///ArrayResize(storeLevel, loopback);

   minLevel = iLowest(Symbol(), Period(), MODE_LOW, loopback, 0);
   maxLevel = iHighest(Symbol(), Period(), MODE_HIGH, loopback, 0);
   highest = iHigh(Symbol(), Period(), maxLevel);
   lowest = iLow(Symbol(), Period(), minLevel);

   //Print("max: " + highest + " min: " + lowest);
   stepIncrement = 0.0005;
   tolerance = 0.0002;
   static double tmp;
   tmp = 0.0;


   for (double actPrice = lowest; actPrice <= highest; actPrice += stepIncrement) {
      for (int i = 1; i <= loopback; i++) {
         //do some stuff here...
         high = iHigh(Symbol(), Period(), i);
         double topRange, bottomRange;
         // if is the first value tmp stores the first high encountered until that moment
         if (tmp == 0) {
            tmp = high;
         } else {
            //define a buffer adding a subtracting from tmp to check if the new high is within that value
            topRange = tmp + tolerance;
            bottomRange = tmp - tolerance;

            if (high <= topRange && high >= bottomRange) {
               commonPoint++;
            }
         }
         //if has been touched at least three times reset common point
         //tmp goes to the new high value to keep looping
         if (commonPoint == 3) {
            commonPoint = 0;
            tmp = high;
            ///Print("valore tmp: " + tmp);
            storeLevel[i] = tmp;
         }
      }
   }
}
*/

/* END: SUPPORT/RESISTANCE CALCULATION */

/* BEGIN: DISPLAYING FUNCTIONS */

/**
 * Get text output of hourly stats.
 */
string GetStats(string sep = ", ") {
  //string output = "Stats: ";
  //output += Minute() > 0 ? StringFormat("%.1f ticks/min", hourly_stats.GetTotalTicks() / Minute()) + sep : "";
  //return output;
  return "";
}

/**
 * Get text output of hourly profit report.
 */
string GetHourlyProfit(string sep = ", ") {
  string output = StringFormat("Hourly profit (total: %.1fp): ", Array::GetArrSumKey1(hourly_profit, day_of_year));
  for (int h = 0; h < hour_of_day; h++) {
    output += StringFormat("%d: %.1fp%s", h, hourly_profit[day_of_year][h], h < hour_of_day ? sep : "");
  }
  return output;
}

/**
 * Get text output of daily report.
 */
string GetDailyReport() {
  string output = "Daily max: ";
  int key;
  // output += "Low: "     + daily[MAX_LOW] + "; ";
  // output += "High: "    + daily[MAX_HIGH] + "; ";
  // output += StringFormat("Tick: %g; ", daily[MAX_TICK]);
  // output += "Drop: "    + daily[MAX_DROP] + "; ";
  output += StringFormat("Spread: %g pts; ",   daily[MAX_SPREAD]);
  output += StringFormat("Max opened orders: %.0f; ", daily[MAX_ORDERS]);
  output += StringFormat("Loss: %.2f; ",       daily[MAX_LOSS]);
  output += StringFormat("Profit: %.2f; ",     daily[MAX_PROFIT]);
  output += StringFormat("Equity: %.2f; ",     daily[MAX_EQUITY]);
  output += StringFormat("Balance: %.2f; ",    daily[MAX_BALANCE]);

  //output += GetAccountTextDetails() + "; " + GetOrdersStats();

  key = Array::GetArrKey1ByHighestKey2ValueD(stats, DAILY_PROFIT);
  if (key >= 0 && stats[key][DAILY_PROFIT] > 0) {
    output += StringFormat("Best: %s (%.2fp)", sname[key], stats[key][DAILY_PROFIT]);
  }
  key = Array::GetArrKey1ByLowestKey2ValueD(stats, DAILY_PROFIT);
  if (key >= 0 && stats[key][DAILY_PROFIT] < 0) {
    output += StringFormat("Worse: %s (%.2fp)", sname[key], stats[key][DAILY_PROFIT]);
  }

  return output;
}

/**
 * Get text output of weekly report.
 */
string GetWeeklyReport() {
  string output = "Weekly max: ";
  int key;
  // output =+ GetAccountTextDetails() + "; " + GetOrdersStats();
  // output += "Low: "     + weekly[MAX_LOW] + "; ";
  // output += "High: "    + weekly[MAX_HIGH] + "; ";
  // output += StringFormat("Tick: %g; ", weekly[MAX_TICK]);
  // output += "Drop: "    + weekly[MAX_DROP] + "; ";
  output += StringFormat("Spread: %g pts; ",   weekly[MAX_SPREAD]);
  output += StringFormat("Max opened orders: %.0f; ", weekly[MAX_ORDERS]);
  output += StringFormat("Loss: %.2f; ",       weekly[MAX_LOSS]);
  output += StringFormat("Profit: %.2f; ",     weekly[MAX_PROFIT]);
  output += StringFormat("Equity: %.2f; ",     weekly[MAX_EQUITY]);
  output += StringFormat("Balance: %.2f; ",    weekly[MAX_BALANCE]);

  key = Array::GetArrKey1ByHighestKey2ValueD(stats, WEEKLY_PROFIT);
  if (key >= 0 && stats[key][WEEKLY_PROFIT] > 0) {
    output += StringFormat("Best: %s (%.2fp)", sname[key], stats[key][WEEKLY_PROFIT]);
  }
  key = Array::GetArrKey1ByLowestKey2ValueD(stats, WEEKLY_PROFIT);
  if (key >= 0 && stats[key][WEEKLY_PROFIT] < 0) {
    output += StringFormat("Worse: %s (%.2fp)", sname[key], stats[key][WEEKLY_PROFIT]);
  }

  return output;
}

/**
 * Get text output of monthly report.
 */
string GetMonthlyReport() {
  string output = "Monthly max: ";
  int key;
  // output =+ GetAccountTextDetails() + "; " + GetOrdersStats();
  // output += "Low: "     + monthly[MAX_LOW] + "; ";
  // output += "High: "    + monthly[MAX_HIGH] + "; ";
  // output += StringFormat("Tick: %g; ", monthly[MAX_TICK]);
  // output += "Drop: "    + monthly[MAX_DROP] + "; ";
  output += StringFormat("Spread: %g pts; ",   monthly[MAX_SPREAD]);
  output += StringFormat("Max opened orders: %.0f; ", monthly[MAX_ORDERS]);
  output += StringFormat("Loss: %.2f; ",       monthly[MAX_LOSS]);
  output += StringFormat("Profit: %.2f; ",     monthly[MAX_PROFIT]);
  output += StringFormat("Equity: %.2f; ",     monthly[MAX_EQUITY]);
  output += StringFormat("Balance: %.2f; ",    monthly[MAX_BALANCE]);

  key = Array::GetArrKey1ByHighestKey2ValueD(stats, MONTHLY_PROFIT);
  if (key >= 0 && stats[key][MONTHLY_PROFIT] > 0) {
    output += StringFormat("Best: %s (%.2fp)", sname[key], stats[key][MONTHLY_PROFIT]);
  }
  key = Array::GetArrKey1ByLowestKey2ValueD(stats, MONTHLY_PROFIT);
  if (key >= 0 && stats[key][MONTHLY_PROFIT] < 0) {
    output += StringFormat("Worse: %s (%.2fp)", sname[key], stats[key][MONTHLY_PROFIT]);
  }

  return output;
}

/**
 * Display info on chart.
 */
string DisplayInfoOnChart(bool on_chart = true, string sep = "\n") {
  if (!terminal.IsRealtime() && !terminal.IsVisualMode()) {
    return NULL;
  }

  datetime _lastupdate = 0;
  string output;
  if (_lastupdate < TimeCurrent()) {
    return NULL;
  }

  // Prepare text for Stop Out.
  string stop_out_level = StringFormat("%d", account.AccountStopoutLevel());
  if (AccountStopoutMode() == 0) stop_out_level += "%"; else stop_out_level += account.AccountCurrency();
  stop_out_level += StringFormat(" (%.1f)", account.GetAccountStopoutLevel(VerboseErrors));
  // Prepare text to display max orders.
  string text_max_orders = StringFormat("Max orders: %d [Per type: %d]", max_orders, GetMaxOrdersPerType());
  #ifdef __advanced__
    if (MaxOrdersPerDay > 0) text_max_orders += StringFormat(" [Per day: %d]", MaxOrdersPerDay);
  #endif
  // Prepare text to display spread.
  string text_spread = StringFormat("Spread: %.1f pips (%d pts)", market.GetSpreadInPips(), market.GetSpreadInPts());
  // Check trend.
  string trend = "Neutral";
  if (Convert::ValueToOp(curr_trend) == ORDER_TYPE_BUY) trend = "Bullish";
  if (Convert::ValueToOp(curr_trend) == ORDER_TYPE_SELL) trend = "Bearish";
  if (fabs(curr_trend) > 0.3) trend = "Strong " + trend;
  trend += StringFormat(" (%-.1f)", curr_trend);
  // EA text.
  string ea_text = StringFormat("%s v%s", ea_name, ea_version);
  #ifdef __expire__ CheckExpireDate(); ea_text += StringFormat(" [expires on %s]", TimeToStr(ea_expire_date, TIME_DATE)); #endif
  // Print actual info.
  string indent = "";
  indent = "                      "; // if (total_orders > 5)?
  output = indent + "------------------------------------------------" + sep
                  + indent + StringFormat("| %s (Status: %s)%s", ea_text, (ea_active ? "ACTIVE" : "NOT ACTIVE"), sep)
                  + indent + StringFormat("| ACCOUNT INFORMATION:%s", sep)
                  + indent + StringFormat("| Server Name: %s, Time: %s%s", AccountInfoString(ACCOUNT_SERVER), TimeToStr(time_current, TIME_DATE|TIME_MINUTES|TIME_SECONDS), sep)
                  + indent + "| Acc Number: " + IntegerToString(account.AccountNumber()) + "; Acc Name: " + AccountName() + "; Broker: " + account.AccountCompany() + " (Type: " + account_type + ")" + sep
                  + indent + StringFormat("| Stop Out Level: %s, Leverage: 1:%d %s", stop_out_level, AccountLeverage(), sep)
                  + indent + "| Used Margin: " + Convert::ValueWithCurrency(account.AccountMargin()) + "; Free: " + Convert::ValueWithCurrency(account.AccountFreeMargin()) + sep
                  + indent + "| Equity: " + Convert::ValueWithCurrency(account.AccountEquity())
                     + "; Balance: " + Convert::ValueWithCurrency(account.AccountBalance())
                     + (account.AccountCredit() > 0 ? "; Credit: " + Convert::ValueWithCurrency(account.AccountCredit()) : "")
                     + sep
                  + indent + "| Lot size: " + DoubleToStr(ea_lot_size, market.GetVolumeDigits()) + "; " + text_max_orders + sep
                  + indent + "| Risk ratio: " + DoubleToStr(ea_risk_ratio, 1) + " (" + GetRiskRatioText() + ")" + sep
                  + indent + (RiskMarginTotal >= 0 ? StringFormat("| Risk margin level: Total: %.2f (Buy:%.2f, Sell:%.2f)", ea_margin_risk_level[2], ea_margin_risk_level[ORDER_TYPE_BUY], ea_margin_risk_level[ORDER_TYPE_SELL]) : "| Risk margin level: Disabled") + sep
                  + indent + "| " + GetOrdersStats("" + sep + indent + "| ") + "" + sep
                  + indent + "| Last error: " + last_err + "" + sep
                  + indent + "| Last message: " + last_msg + "" + sep
                  + indent + "| ------------------------------------------------" + sep
                  + indent + "| MARKET INFORMATION:" + sep
                  + indent + "| " + text_spread + "" + sep
                  + indent + "| Trend: " + trend + "" + sep
                  // + indent // + "Mini lot: " + MarketInfo(Symbol(), MODE_MINLOT) + "" + sep
                  + indent + "| ------------------------------------------------" + sep
                  + indent + "| STATISTICS:" + sep
                  + indent + "| " + GetStats() + "" + sep
                  + indent + "| " + GetHourlyProfit() + "" + sep
                  + indent + "| " + GetDailyReport() + "" + sep
                  + indent + "| " + GetWeeklyReport() + "" + sep
                  + indent + "| " + GetMonthlyReport() + "" + sep
                  + indent + "------------------------------------------------" + sep
                  ;
  if (on_chart) {
    /* FIXME: Text objects can't contain multi-line text so we need to create a separate object for each line instead.
    ObjectCreate(ea_name, OBJ_LABEL, 0, 0, 0, 0); // Create text object with given name.
    // Set pixel co-ordinates from top left corner (use OBJPROP_CORNER to set a different corner).
    ObjectSet(ea_name, OBJPROP_XDISTANCE, 0);
    ObjectSet(ea_name, OBJPROP_YDISTANCE, 10);
    ObjectSetText(ea_name, output, 10, "Arial", Red); // Set text, font, and colour for object.
    // ObjectDelete(ea_name);
    */
    Comment(output);
    ChartRedraw(); // Redraws the current chart forcedly.
  }
  _lastupdate = TimeCurrent();
  return output;
}

/**
 * Send e-mail about the order.
 */
bool SendEmailExecuteOrder(string sep = "<br>\n") {
  bool _res = false;
  if (!Terminal::IsRealtime()) {
    return _res;
  }
  string mail_title = "Trading Info - " + ea_name;
  string body = "Trade Information" + sep;
  body += sep + StringFormat("Event: %s", "Trade Opened");
  body += sep + StringFormat("Currency Pair: %s", _Symbol);
  body += sep + StringFormat("Time: %s", TimeToStr(time_current, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
  body += sep + StringFormat("Order Type: %s", Order::OrderTypeToString((ENUM_ORDER_TYPE) OrderType()));
  body += sep + StringFormat("Price: %s", DoubleToStr(OrderOpenPrice(), Digits));
  body += sep + StringFormat("Lot size: %g", Order::OrderLots());
  body += sep + StringFormat("Comment: %s", OrderComment());
  body += sep + StringFormat("Account Balance: %s", Convert::ValueWithCurrency(account.AccountBalance()));
  body += sep + StringFormat("Account Equity: %s", Convert::ValueWithCurrency(account.AccountEquity()));
  if (account.AccountCredit() > 0) {
    body += sep + StringFormat("Account Credit: %s", Convert::ValueWithCurrency(account.AccountCredit()));
  }
  return SendMail(mail_title, body);
}

/**
 * Get order statistics in percentage for each strategy.
 */
string GetOrdersStats(string sep = "\n") {
  // Prepare text for Total Orders.
  string total_orders_text = StringFormat("Open Orders: %d", total_orders);
  total_orders_text += StringFormat(" +%d/-%d", Orders::GetOrdersByType(ORDER_TYPE_BUY),  Orders::GetOrdersByType(ORDER_TYPE_SELL));
  total_orders_text += StringFormat(" [%.2f lots]", Orders::GetOpenLots(_Symbol, MagicNumber, FINAL_STRATEGY_TYPE_ENTRY));
  total_orders_text += StringFormat(" (other: %d)", GetTotalOrders(false));
  // Prepare data about open orders per strategy type.
  string orders_per_type = "Stats: "; // Display open orders per type.
  if (total_orders > 0) {
    for (int i = 0; i < FINAL_STRATEGY_TYPE_ENTRY; i++) {
      if (open_orders[i] > 0) {
        orders_per_type += StringFormat("%s: %.1f%% ", sname[i], MathFloor(100 / total_orders * open_orders[i]));
      }
    }
  } else {
    orders_per_type += "No orders open yet.";
  }
  return orders_per_type + sep + total_orders_text;
}

/**
 * Get information about account conditions in text format.
 */
string GetAccountTextDetails(string sep = "; ") {
   return StringConcatenate("Account Details: ",
      "Time: ", TimeToStr(time_current, TIME_DATE|TIME_MINUTES|TIME_SECONDS), sep,
      "Account Balance: ", Convert::ValueWithCurrency(account.AccountBalance()), sep,
      "Account Equity: ", Convert::ValueWithCurrency(account.AccountEquity()), sep,
      "Account Credit: ", Convert::ValueWithCurrency(account.AccountCredit()), sep,
      "Used Margin: ", Convert::ValueWithCurrency(account.AccountMargin()), sep,
      "Free Margin: ", Convert::ValueWithCurrency(account.AccountFreeMargin()), sep,
      "No of Orders: ", total_orders, " (BUY/SELL: ", Orders::GetOrdersByType(ORDER_TYPE_BUY), "/", Orders::GetOrdersByType(ORDER_TYPE_SELL), ")", sep,
      "Risk Ratio: ", DoubleToStr(ea_risk_ratio, 1)
   );
}

/**
 * Get information about market conditions in text format.
 */
string GetMarketTextDetails() {
   return StringConcatenate("MarketInfo: ",
     "Symbol: ", Symbol(), "; ",
     "Ask: ", DoubleToStr(Ask, Digits), "; ",
     "Bid: ", DoubleToStr(Bid, Digits), "; ",
     StringFormat("Spread: %gpts (%.2f pips)", market.GetSpreadInPts(), market.GetSpreadInPips())
   );
}

/**
 * Get account summary text.
 */
string GetSummaryText() {
  return GetAccountTextDetails();
}

/**
 * Get risk ratio text based on the value.
 */
string GetRiskRatioText() {
  string text = "Normal";
  if (RiskRatio != 0.0 && ea_risk_ratio < 0.9) text = "Set low manually";
  else if (RiskRatio != 0.0 && ea_risk_ratio > 1.9) text = "Set high manually";
  else if (ea_risk_ratio < 0.2) text = "Extremely risky!";
  else if (ea_risk_ratio < 0.3) text = "Very risky!";
  else if (ea_risk_ratio < 0.5) text = "Risky!";
  else if (ea_risk_ratio < 0.9) text = "Below normal, but ok";
  else if (ea_risk_ratio > 5.0) text = "Extremely high (risky!)";
  else if (ea_risk_ratio > 2.0) text = "Very high";
  else if (ea_risk_ratio > 1.4) text = "High";
  #ifdef __advanced__
    if (StringLen(rr_text) > 0) text += " - reason: " + rr_text;
  #endif
  return text;
}

/* END: DISPLAYING FUNCTIONS */

/* BEGIN: ACTION FUNCTIONS */

/**
 * Execute action to close the most profitable order.
 */
bool ActionCloseMostProfitableOrder(int reason_id = EMPTY, int min_profit = EMPTY){
  bool result = false;
  int selected_ticket = 0;
  double max_ticket_profit = 0, curr_ticket_profit = 0;
  for (int order = 0; order < OrdersTotal(); order++) {
    if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES))
     if (OrderSymbol() == Symbol() && CheckOurMagicNumber()) {
      curr_ticket_profit = Order::GetOrderProfit();
       if (curr_ticket_profit > max_ticket_profit) {
         selected_ticket = OrderTicket();
         max_ticket_profit = curr_ticket_profit;
       }
     }
  }

  if (selected_ticket > 0) {
    if (min_profit != EMPTY && max_ticket_profit < Account_Condition_MinProfitCloseOrder) { return (false); }
    last_close_profit = max_ticket_profit;
    return TaskAddCloseOrder(selected_ticket, reason_id);
  } else if (VerboseTrace) {
    Print(__FUNCTION__ + ": Can't find any profitable order.");
  }
  return (false);
}

/**
 * Execute action to close most unprofitable order.
 */
bool ActionCloseMostUnprofitableOrder(int reason_id = EMPTY){
  int selected_ticket = 0;
  double ticket_profit = 0;
  for (int order = 0; order < OrdersTotal(); order++) {
    if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES))
     if (OrderSymbol() == Symbol() && CheckOurMagicNumber()) {
       if (Order::GetOrderProfit() < ticket_profit) {
         selected_ticket = OrderTicket();
         ticket_profit = Order::GetOrderProfit();
       }
     }
  }

  if (selected_ticket > 0) {
    last_close_profit = ticket_profit;
    return TaskAddCloseOrder(selected_ticket, reason_id);
  } else if (VerboseDebug) {
    logger.Error("Can't find any unprofitable order as requested.", __FUNCTION__);
  }
  return (false);
}

/**
 * Execute action to close all profitable orders.
 */
bool ActionCloseAllProfitableOrders(int reason_id = EMPTY){
  bool result = false;
  int selected_orders = 0;
  double ticket_profit = 0, total_profit = 0;
  for (int order = 0; order < OrdersTotal(); order++) {
    if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && CheckOurMagicNumber())
       ticket_profit = Order::GetOrderProfit();
       if (ticket_profit > 0) {
         result = TaskAddCloseOrder(OrderTicket(), reason_id);
         selected_orders++;
         total_profit += ticket_profit;
     }
  }

  if (selected_orders > 0) {
    last_close_profit = total_profit;
    Msg::ShowText(StringFormat("Queued %d orders to close with expected profit of %g pips.", selected_orders, total_profit)
    , "Info", __FUNCTION__, __LINE__, VerboseInfo);
  }
  return (result);
}

/**
 * Execute action to close all unprofitable orders.
 */
bool ActionCloseAllUnprofitableOrders(int reason_id = EMPTY){
  bool result = false;
  int selected_orders = 0;
  double ticket_profit = 0, total_profit = 0;
  for (int order = 0; order < OrdersTotal(); order++) {
    if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && CheckOurMagicNumber())
       ticket_profit = Order::GetOrderProfit();
       if (ticket_profit < 0) {
         result = TaskAddCloseOrder(OrderTicket(), reason_id);
         selected_orders++;
         total_profit += ticket_profit;
     }
  }

  if (selected_orders > 0) {
    last_close_profit = total_profit;
    Msg::ShowText(StringFormat("Queued %d orders to close with expected loss of %g pips.", selected_orders, total_profit)
    , "Info", __FUNCTION__, __LINE__, VerboseInfo);
  }
  return (result);
}

/**
 * Execute action to close all orders by specified type.
 */
bool ActionCloseAllOrdersByType(ENUM_ORDER_TYPE cmd = EMPTY, int reason_id = EMPTY){
  if (cmd == EMPTY) return (false);
  #ifdef __profiler__ PROFILER_START #endif
  int selected_orders = 0;
  double ticket_profit = 0, total_profit = 0;
  for (int order = 0; order < OrdersTotal(); order++) {
    if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && CheckOurMagicNumber())
       if (OrderType() == cmd) {
         TaskAddCloseOrder(OrderTicket(), reason_id);
         selected_orders++;
         total_profit += ticket_profit;
     }
  }

  if (selected_orders > 0) {
    last_close_profit = total_profit;
    Msg::ShowText(StringFormat("Queued %d orders to close with expected profit of %g pips.", selected_orders, total_profit)
    , "Info", __FUNCTION__, __LINE__, VerboseInfo);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return (true);
}

/**
 * Execute action to close all orders.
 *
 * Notes:
 * - Useful when equity is low or high in order to secure our assets and avoid higher risk.
 * - Executing this action could indicate our poor money management and risk further losses.
 *
 * Parameter: only_ours
 *   When true (default), we should close only ours orders (determined by our magic number).
 *   When false, we should close all orders (including other stragegies if any).
 *     This is due the account equity and balance are shared,
 *     so potentially we don't know which strategy generated this kind of situation,
 *     therefore closing all make the things more predictable and to avoid any suprices.
 */
int ActionCloseAllOrders(int reason_id = EMPTY, bool only_ours = true) {
  #ifdef __profiler__ PROFILER_START #endif
   int processed = 0;
   int total = OrdersTotal();
   double total_profit = 0;
   for (int order = 0; order < total; order++) {
      if (OrderSelect(order, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderTicket() > 0) {
         if (only_ours && !CheckOurMagicNumber()) continue;
         total_profit += Order::GetOrderProfit();
         TaskAddCloseOrder(OrderTicket(), reason_id); // Add task to re-try.
         processed++;
      } else {
         Msg::ShowText(StringFormat("Error: Order Pos: %d; Message: %s", order, terminal.GetLastErrorText()),
            "Debug", __FUNCTION__, __LINE__, VerboseDebug);
      }
   }

   if (processed > 0) {
    last_close_profit = total_profit;
    Msg::ShowText(StringFormat("Queued %d orders out of %d for closure.", processed, total),
      "Info", __FUNCTION__, __LINE__, VerboseInfo);
   }
  #ifdef __profiler__ PROFILER_STOP #endif
   return (processed > 0);
}

/**
 * Execute action by its id. See: EA_Conditions parameters.
 *
 * @param int aid Action ID.
 * @param int id Condition ID.
 *
 * Note: Executing random actions can be potentially dangerous for the account if not used wisely.
 */
bool ActionExecute(int aid, int id = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  #ifdef __profiler__ PROFILER_START #endif
  bool result = false;
  int reason_id = (id != EMPTY ? acc_conditions[id][0] : EMPTY); // Account id condition.
  int mid = (id != EMPTY ? acc_conditions[id][1] : EMPTY); // Market id condition.
  ENUM_ORDER_TYPE cmd;
  #ifdef __expire__ CheckExpireDate(); #endif
  switch (aid) {
    case A_NONE: /* 0 */
      result = true;
      if (VerboseTrace) PrintFormat("%s(): No action taken. Reason (id: %d): %s", __FUNCTION__, reason_id, ReasonIdToText(reason_id));
      // Nothing.
      break;
    case A_CLOSE_ORDER_PROFIT: /* 1 */
      result = ActionCloseMostProfitableOrder(reason_id);
      break;
    case A_CLOSE_ORDER_PROFIT_MIN: /* 2 */
      result = ActionCloseMostProfitableOrder(reason_id, Account_Condition_MinProfitCloseOrder);
      break;
    case A_CLOSE_ORDER_LOSS: /* 3 */
      result = ActionCloseMostUnprofitableOrder(reason_id);
      break;
    case A_CLOSE_ALL_IN_PROFIT: /* 4 */
      result = ActionCloseAllProfitableOrders(reason_id);
      break;
    case A_CLOSE_ALL_IN_LOSS: /* 5 */
      result = ActionCloseAllUnprofitableOrders(reason_id);
      break;
    case A_CLOSE_ALL_PROFIT_SIDE: /* 6 */
      // TODO
      cmd = GetProfitableSide();
      result = cmd != NULL ? ActionCloseAllOrdersByType(cmd, reason_id) : true;
      break;
    case A_CLOSE_ALL_LOSS_SIDE: /* 7 */
      cmd = GetProfitableSide();
      result = cmd != NULL ? ActionCloseAllOrdersByType(Order::NegateOrderType(cmd), reason_id) : true;
      break;
    case A_CLOSE_ALL_TREND: /* 8 */
      cmd = Convert::ValueToOp(curr_trend);
      result = cmd != NULL ? ActionCloseAllOrdersByType(cmd, reason_id) : true;
      break;
    case A_CLOSE_ALL_NON_TREND: /* 9 */
      cmd = Convert::ValueToOp(curr_trend);
      result = cmd != NULL ? ActionCloseAllOrdersByType(Order::NegateOrderType(cmd), reason_id) : true;
      break;
    case A_CLOSE_ALL_ORDERS: /* 10 */
      result = ActionCloseAllOrders(reason_id);
      break;
    case A_SUSPEND_STRATEGIES: /* 11 */
      Array::ArrSetValueI(info, SUSPENDED, (int) true);
      result = true;
      break;
    case A_UNSUSPEND_STRATEGIES: /* 12 */
      Array::ArrSetValueI(info, SUSPENDED, (int) false);
      result = true;
      break;
    case A_RESET_STRATEGY_STATS: /* 13 */
      Array::ArrSetValueD(conf, PROFIT_FACTOR, GetDefaultProfitFactor());
      Array::ArrSetValueD(stats, TOTAL_GROSS_LOSS,   0.0);
      Array::ArrSetValueD(stats, TOTAL_GROSS_PROFIT, 0.0);
      result = true;
      break;
      /*
    case A_RISK_REDUCE:
      result = ActionRiskReduce();
      break;
    case A_RISK_INCREASE:
      result = ActionRiskIncrease();
      break;
      */
      /*
    case A_ORDER_STOPS_DECREASE:
      // result = TightenStops();
      break;
    case A_ORDER_PROFIT_DECREASE:
      // result = TightenProfits();
      break;*/
    default:
      Msg::ShowText(
        StringFormat("Unknown action id: %d", aid),
        "Error", __FUNCTION__, __LINE__, VerboseErrors);
  }
  // reason = "Account condition: " + acc_conditions[i][0] + ", Market condition: " + acc_conditions[i][1] + ", Action: " + acc_conditions[i][2] + " [E: " + Convert::ValueWithCurrency(AccountEquity()) + "/B: " + Convert::ValueWithCurrency(AccountBalance()) + "]";

  TaskProcessList(TRUE); // Process task list immediately after action has been taken.
  Msg::ShowText(GetAccountTextDetails() + "; " + GetOrdersStats(), "Info", __FUNCTION__, __LINE__, VerboseInfo);
  if (result) {
    Msg::ShowText(
        StringFormat("Executed action: %s (id: %d), because of market condition: %s (id: %d) and account condition is: %s (id: %d) [E:%s/B:%s/C:%s/P:%sp].",
          ActionIdToText(aid), aid, MarketIdToText(mid), mid, ReasonIdToText(reason_id), reason_id, Convert::ValueWithCurrency(account.AccountEquity()), Convert::ValueWithCurrency(AccountBalance()), Convert::ValueWithCurrency(AccountCredit()), DoubleToStr(last_close_profit, 1)),
        "Info", __FUNCTION__, __LINE__, VerboseInfo);
    Msg::ShowText(last_msg, "Debug", __FUNCTION__, __LINE__, VerboseDebug && aid != A_NONE);
    if (WriteReport && VerboseDebug) ReportAdd(GetLastMessage());
    last_action_time = DateTime::TimeTradeServer(); // Set last execution bar time.
  } else {
    Msg::ShowText(
      StringFormat("Failed to execute action: %s (id: %d), condition: %s (id: %d).",
        ActionIdToText(aid), aid, ReasonIdToText(reason_id), reason_id),
      "Warning", __FUNCTION__, __LINE__, VerboseErrors);
  }
  #ifdef __profiler__ PROFILER_STOP #endif
  return result;
}

/**
 * Convert action id into text representation.
 */
string ActionIdToText(int aid) {
  string output = "Unknown";
  switch (aid) {
    case A_NONE:                   output = "None"; break;
    case A_CLOSE_ORDER_PROFIT:     output = "Close most profitable order"; break;
    case A_CLOSE_ORDER_PROFIT_MIN: output = "Close most profitable order (above MinProfitCloseOrder)"; break;
    case A_CLOSE_ORDER_LOSS:       output = "Close worse order"; break;
    case A_CLOSE_ALL_IN_PROFIT:    output = "Close all in profit"; break;
    case A_CLOSE_ALL_IN_LOSS:      output = "Close all in loss"; break;
    case A_CLOSE_ALL_PROFIT_SIDE:  output = "Close profit side"; break;
    case A_CLOSE_ALL_LOSS_SIDE:    output = "Close loss side"; break;
    case A_CLOSE_ALL_TREND:        output = "Close trend side"; break;
    case A_CLOSE_ALL_NON_TREND:    output = "Close non-trend side"; break;
    case A_CLOSE_ALL_ORDERS:       output = "Close all!"; break;
  }
  return output;
}

/**
 * Convert reason id into text representation.
 */
string ReasonIdToText(int rid) {
  string output = "Unknown";
  switch (rid) {
    case EMPTY: output = "Empty"; break;
    case R_NONE: output = "None (inactive)"; break;
    case R_TRUE: output = "Always true"; break;
    case R_EQUITY_LOWER: output = "Equity lower than balance"; break;
    case R_EQUITY_HIGHER: output = "Equity higher than balance"; break;
    case R_EQUITY_50PC_HIGH: output = "Equity 50% high"; break;
    case R_EQUITY_20PC_HIGH: output = "Equity 20% high"; break;
    case R_EQUITY_10PC_HIGH: output = "Equity 10% high"; break;
    case R_EQUITY_10PC_LOW: output = "Equity 10% low"; break;
    case R_EQUITY_20PC_LOW: output = "Equity 20% low"; break;
    case R_EQUITY_50PC_LOW: output = "Equity 50% low"; break;
    case R_MARGIN_USED_50PC: output = "50% Margin Used"; break;
    case R_MARGIN_USED_70PC: output = "70% Margin Used"; break;
    case R_MARGIN_USED_80PC: output = "80% Margin Used"; break;
    case R_MARGIN_USED_90PC: output = "90% Margin Used"; break;
    case R_NO_FREE_MARGIN: output = "No free margin"; break;
    case R_ACC_IN_LOSS: output = "Account in loss"; break;
    case R_ACC_IN_PROFIT: output = "Account in profit"; break;
    case R_DBAL_LT_WEEKLY: output = "Max. daily balance < max. weekly"; break;
    case R_DBAL_GT_WEEKLY: output = "Max. daily balance > max. weekly"; break;
    case R_WBAL_LT_MONTHLY: output = "Max. weekly balance < max. monthly"; break;
    case R_WBAL_GT_MONTHLY: output = "Max. weekly balance > max. monthly"; break;
    case R_ACC_IN_TREND: output = "Account in trend"; break;
    case R_ACC_IN_NON_TREND: output = "Account is against trend"; break;
    case R_ACC_CDAY_IN_PROFIT: output = "Current day in profit"; break;
    case R_ACC_CDAY_IN_LOSS: output = "Current day in loss"; break;
    case R_ACC_PDAY_IN_PROFIT: output = "Previous day in profit"; break;
    case R_ACC_PDAY_IN_LOSS: output = "Previous day in loss"; break;
    case R_ACC_MAX_ORDERS: output = "Maximum orders opened"; break;
    case R_ORDER_EXPIRED: output = "Order expired (CloseOrderAfterXHours)"; break;
    case R_OPPOSITE_SIGNAL: output = "Opposite signal"; break;
  }
  return output;
}

/**
 * Convert market id condition into text representation.
 */
string MarketIdToText(int mid) {
  string output = "Unknown";
  switch (mid) {
    case C_MARKET_NONE: output = "None"; break;
    case C_MARKET_TRUE: output = "Always true"; break;
    case C_MA1_FS_TREND_OPP: output = "MA1 Fast&Slow trend-based opposite"; break;
    case C_MA5_FS_TREND_OPP: output = "MA5 Fast&Slow trend-based opposite"; break;
    case C_MA15_FS_TREND_OPP: output = "MA15 Fast&Slow trend-based opposite"; break;
    case C_MA30_FS_TREND_OPP: output = "MA30 Fast&Slow trend-based opposite"; break;
    case C_MA1_FS_ORDERS_OPP: output = "MA1 Fast&Slow orders-based opposite"; break;
    case C_MA5_FS_ORDERS_OPP: output = "MA5 Fast&Slow orders-based opposite"; break;
    case C_MA15_FS_ORDERS_OPP: output = "MA15 Fast&Slow orders-based opposite"; break;
    case C_MA30_FS_ORDERS_OPP: output = "MA30 Fast&Slow orders-based opposite"; break;
    case C_DAILY_PEAK: output = "Daily peak price"; break;
    case C_WEEKLY_PEAK: output = "Weekly peak price"; break;
    case C_MONTHLY_PEAK: output = "Monthly peak price"; break;
    case C_MARKET_BIG_DROP: output = "Market big drop"; break;
    case C_MARKET_VBIG_DROP: output = "Market very big drop"; break;
    case C_MARKET_AT_HOUR: output = StringFormat("at specific %d hour", MarketSpecificHour); break;
  }
  return output;
}

/* END: ACTION FUNCTIONS */

/* BEGIN: TICKET LIST/HISTORY CHECK FUNCTIONS */

/**
 * Add ticket to list for further processing.
 * @todo: Move to Array class.
 */
bool TicketAdd(int ticket_no) {
  DEBUG_CHECKPOINT_ADD
  int i, slot = EMPTY;
  int size = ArraySize(tickets);
  // Check if ticket is already in the list and at the same time find the empty slot.
  for (i = 0; i < size; i++) {
    if (tickets[i] == ticket_no) {
      return (true); // Ticket already in the list.
    } else if (slot < 0 && tickets[i] == 0) {
      slot = i;
    }
  }
  // Resize array if slot has not been allocated.
  if (slot == EMPTY) {
    if (size < 1000) { // Set array hard limit to prevent memory leak.
      ArrayResize(tickets, size + 10);
      // ArrayFill(tickets, size - 1, ArraySize(tickets) - size - 1, 0);
      if (VerboseDebug) Print(__FUNCTION__ + ": Couldn't allocate Ticket slot, re-sizing the array. New size: ",  (size + 1), ", Old size: ", size);
      slot = size;
    }
    return (false); // Array exceeded hard limit, probably because of some memory leak.
  }

  tickets[slot] = ticket_no;
  return (true);
}

/**
 * Remove ticket from the list after it has been processed.
 */
bool TicketRemove(int ticket_no) {
  DEBUG_CHECKPOINT_ADD
  for (int i = 0; i < ArraySize(tickets); i++) {
    if (tickets[i] == ticket_no) {
      tickets[i] = 0; // Remove the ticket number from the array slot.
      return (true); // Ticket has been removed successfully.
    }
  }
  return (false);
}

/**
 * Process order history.
 * @todo: Move to class.
 */
bool CheckHistory() {
  double total_profit = 0;
  int pos;
  #ifdef __profiler__ PROFILER_START #endif
  for (pos = last_history_check; pos < HistoryTotal(); pos++) {
    if (!Order::OrderSelect(pos, SELECT_BY_POS, MODE_HISTORY)) continue;
    if (Order::OrderCloseTime() > last_history_check && CheckOurMagicNumber()) {
      total_profit =+ OrderCalc();
    }
  }
  hourly_profit[day_of_year][hour_of_day] = total_profit; // Update hourly profit.
  last_history_check = pos;
  #ifdef __profiler__ PROFILER_STOP #endif
  return (true);
}

/* END: TICKET LIST/HISTORY CHECK FUNCTIONS */

/* BEGIN: ORDER QUEUE FUNCTIONS */

/**
 * Process AI queue of orders to see if we can open any trades.
 */
bool OrderQueueProcess(int method = EMPTY, int filter = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  bool result = true;
  int queue_size = OrderQueueCount();
  long sorted_queue[][2];
  int sid;
  ENUM_ORDER_TYPE cmd;
  datetime time;
  double volume;
  if (method == EMPTY) method = SmartQueueMethod;
  if (filter == EMPTY) filter = SmartQueueFilter;
  if (queue_size > 1) {
    int selected_qid = EMPTY, curr_qid = EMPTY;
    ArrayResize(sorted_queue, queue_size, 100);
    for (int i = 0; i < queue_size; i++) {
      curr_qid = OrderQueueNext(curr_qid);
      if (curr_qid == EMPTY) break;
      sorted_queue[i][0] = GetOrderQueueKeyValue((int) order_queue[curr_qid][Q_SID], method, curr_qid);
      sorted_queue[i][1] = curr_qid++;
    }
    // Sort array by first dimension (descending).
    ArraySort(sorted_queue, WHOLE_ARRAY, 0, MODE_DESCEND);
    for (int i = 0; i < queue_size; i++) {
      selected_qid = (int) sorted_queue[i][1];
      cmd = (ENUM_ORDER_TYPE) order_queue[selected_qid][Q_CMD];
      sid = (int) order_queue[selected_qid][Q_SID];
      time = (datetime) order_queue[selected_qid][Q_TIME];
      volume = GetStrategyLotSize(sid, cmd);
      if (!OpenOrderCondition(cmd, sid, time, filter)) continue;
      if (OpenOrderIsAllowed(cmd, sid, volume)) {
        string comment = GetStrategyComment(sid) + " [AIQueued]";
        result &= ExecuteOrder(cmd, sid, volume);
        break;
      }
    }
  }
  return result;
}

/**
 * Check for the market condition to filter out the order queue.
 */
bool OpenOrderCondition(ENUM_ORDER_TYPE cmd, int sid, datetime time, int method) {
  DEBUG_CHECKPOINT_ADD
  bool result = true;
  ENUM_TIMEFRAMES tf = GetStrategyTimeframe(sid);
  uint tfi = Chart::TfToIndex(tf);
  Chart *_chart = trade[tfi].Chart();
  uint qshift = _chart.GetBarShift(time, false); // Get the number of bars for the tf since queued.
  double qopen = _chart.GetOpen(tf, qshift);
  double qclose = _chart.GetClose(tf, qshift);
  double qhighest = _chart.GetPeakPrice(MODE_HIGH, qshift); // Get the high price since queued.
  double qlowest = _chart.GetPeakPrice(MODE_LOW, qshift); // Get the lowest price since queued.
  double diff = fmax(qhighest - market.GetOpen(), market.GetOpen() - qlowest);
  if (VerboseTrace) PrintFormat("%s(%s, %d, %s, %d)", __FUNCTION__, EnumToString(cmd), sid, DateTime::TimeToStr(time), method);
  if (method != 0) {
    if (METHOD(method,0)) result &= (cmd == ORDER_TYPE_BUY && qopen < market.GetOpen()) || (cmd == ORDER_TYPE_SELL && qopen > market.GetOpen());
    if (METHOD(method,1)) result &= (cmd == ORDER_TYPE_BUY && qclose < market.GetClose()) || (cmd == ORDER_TYPE_SELL && qclose > market.GetClose());
    if (METHOD(method,2)) result &= (cmd == ORDER_TYPE_BUY && qlowest < market.GetLow()) || (cmd == ORDER_TYPE_SELL && qlowest > market.GetLow());
    if (METHOD(method,3)) result &= (cmd == ORDER_TYPE_BUY && qhighest > market.GetHigh()) || (cmd == ORDER_TYPE_SELL && qhighest < market.GetHigh());
    if (METHOD(method,4)) result &= UpdateIndicator(_chart, INDI_SAR) && Trade_SAR(_chart, cmd, 0, 0);
    if (METHOD(method,5)) result &= UpdateIndicator(_chart, INDI_DEMARKER) && Trade_DeMarker(_chart, cmd, 0, 0);
    if (METHOD(method,6)) result &= UpdateIndicator(_chart, INDI_RSI) && Trade_RSI(_chart, cmd, 0, 0);
    if (METHOD(method,7)) result &= UpdateIndicator(_chart, INDI_MA) && Trade_MA(_chart, cmd, 0, 0);
  }
  Object::Delete(_chart);
  return (result);
}

/**
 * Get key based on strategy id in order to prioritize the queue.
 */
int GetOrderQueueKeyValue(int sid, int method, int qid) {
  DEBUG_CHECKPOINT_ADD
  int key = 0;
  switch (method) {
    case  0: key = (int) order_queue[qid][Q_TIME]; break; // 7867 OK (10k, 0.02)
    case  1: key = (int) (stats[sid][DAILY_PROFIT] * 10); break;
    case  2: key = (int) (stats[sid][WEEKLY_PROFIT] * 10); break;
    case  3: key = (int) (stats[sid][MONTHLY_PROFIT] * 10); break; // Has good results.
    case  4: key = (int) (stats[sid][TOTAL_NET_PROFIT] * 10); break; // Has good results.
    case  5: key = (int) (conf[sid][SPREAD_LIMIT] * 10); break;
    case  6: key = GetStrategyTimeframe(sid); break;
    case  7: key = (int) (GetStrategyProfitFactor(sid) * 100); break;
    case  8: key = (int) (GetStrategyLotSize(sid, (ENUM_ORDER_TYPE) order_queue[qid][Q_CMD]) * 100); break;
    case  9: key = (int) stats[sid][TOTAL_GROSS_PROFIT]; break;
    case 10: key = info[sid][TOTAL_ORDERS]; break; // --7846
    case 11: key -= info[sid][TOTAL_ORDERS_LOSS]; break; // --7662 TODO: To test.
    case 12: key = info[sid][TOTAL_ORDERS_WON]; break; // --7515
    case 13: key -= (int) stats[sid][TOTAL_GROSS_LOSS]; break;
    case 14: key = (int) (stats[sid][AVG_SPREAD] * 10); break; // --7396, TODO: To test.
    case 15: key = (int) (conf[sid][FACTOR] * 10); break; // --6976

    // case  4: key = -info[sid][OPEN_ORDERS]; break; // TODO
  }
  // Message("Key: " + key + " for sid: " + sid + ", qid: " + qid);

  return key;
}

/**
 * Get the next non-empty item from the queue.
 */
int OrderQueueNext(int index = EMPTY) {
  DEBUG_CHECKPOINT_ADD
  if (index == EMPTY) index = 0;
  for (int qid = index; qid < ArrayRange(order_queue, 0); qid++)
    if (order_queue[qid][Q_SID] != EMPTY) { return qid; }
  return (EMPTY);
}

/**
 * Add new order to the queue.
 */
bool OrderQueueAdd(int sid, ENUM_ORDER_TYPE cmd) {
  DEBUG_CHECKPOINT_ADD
  bool result = false;
  int qid = EMPTY, size = ArrayRange(order_queue, 0);
  for (int i = 0; i < size; i++) {
    if (order_queue[i][Q_SID] == sid && order_queue[i][Q_CMD] == cmd) {
      order_queue[i][Q_TOTAL]++;
      if (VerboseTrace) PrintFormat("%s(): Added qid %d with sid: %d, cmd: %d, time: %d, total: %d", __FUNCTION__, i, sid, cmd, time_current, order_queue[i][Q_TOTAL]);
      return (true); // Increase the existing if it's there.
    }
    if (order_queue[i][Q_SID] == EMPTY) { qid = i; break; } // Find the empty qid.
  }
  if (qid == EMPTY && size < 1000) { ArrayResize(order_queue, size + FINAL_ORDER_QUEUE_ENTRY); qid = size; }
  if (qid == EMPTY) {
    return (false);
  } else {
    order_queue[qid][Q_SID] = sid;
    order_queue[qid][Q_CMD] = cmd;
    order_queue[qid][Q_TIME] = time_current;
    order_queue[qid][Q_TOTAL] = 1;
    result = true;
    if (VerboseTrace) PrintFormat("%s(): Added qid: %d with sid: %d, cmd: %d, time: %d, total: %d", __FUNCTION__, qid, sid, cmd, time_current, 1);
  }
  return result;
}

/**
 * Clear queue from the orders.
 */
void OrderQueueClear() {
  DEBUG_CHECKPOINT_ADD
  ArrayFill(order_queue, 0, ArraySize(order_queue), EMPTY);
}

/**
 * Check how many orders are in the queue.
 */
int OrderQueueCount() {
  DEBUG_CHECKPOINT_ADD
  int counter = 0;
  for (int i = 0; i < ArrayRange(order_queue, 0); i++)
    if (order_queue[i][Q_SID] != EMPTY) counter++;
  return (counter);
}

/* END: ORDER QUEUE FUNCTIONS */

/* BEGIN: TASK FUNCTIONS */

/**
 * Add new closing order task.
 */
bool TaskAddOrderOpen(ENUM_ORDER_TYPE cmd, double volume, int order_type) {
  int key = cmd + (int) volume + order_type;
  int job_id = TaskFindEmptySlot(cmd + (int) volume + order_type);
  if (job_id >= 0) {
    todo_queue[job_id][0] = key;
    todo_queue[job_id][1] = TASK_ORDER_OPEN;
    todo_queue[job_id][2] = MaxTries; // Set number of retries.
    todo_queue[job_id][3] = cmd;
    todo_queue[job_id][4] = EMPTY; // FIXME: Not used currently.
    todo_queue[job_id][5] = order_type;
    // todo_queue[job_id][6] = order_comment; // FIXME: Not used currently.
    // Print(__FUNCTION__ + ": Added task (", job_id, ") for ticket: ", todo_queue[job_id][0], ", type: ", todo_queue[job_id][1], " (", todo_queue[job_id][3], ").");
    return true;
  } else {
    return false; // Job not allocated.
  }
}

/**
 * Add new close task by job id.
 */
bool TaskAddCloseOrder(int ticket_no, int reason = EMPTY) {
  int job_id = TaskFindEmptySlot(ticket_no);
  if (job_id >= 0) {
    todo_queue[job_id][0] = ticket_no;
    todo_queue[job_id][1] = TASK_ORDER_CLOSE;
    todo_queue[job_id][2] = MaxTries; // Set number of retries.
    todo_queue[job_id][3] = reason;
    if (VerboseTrace) Print("TaskAddCloseOrder(): Allocated task (id: ", job_id, ") for ticket: ", todo_queue[job_id][0], ".");
    return true;
  } else {
    if (VerboseTrace) PrintFormat("%s(): Failed to allocate close task for ticket: %d", __FUNCTION__, ticket_no);
    return false; // Job is not allocated.
  }
}

/**
 * Add new task to recalculate loss/profit.
 */
bool TaskAddCalcStats(int ticket_no, int order_type = EMPTY) {
  int job_id = TaskFindEmptySlot(ticket_no);
  if (job_id >= 0) {
    todo_queue[job_id][0] = ticket_no;
    todo_queue[job_id][1] = TASK_CALC_STATS;
    todo_queue[job_id][2] = MaxTries; // Set number of retries.
    todo_queue[job_id][3] = order_type;
    if (VerboseTrace) Print(__FUNCTION__ + ": Allocated task (id: ", job_id, ") for ticket: ", todo_queue[job_id][0], ".");
    return true;
  } else {
    if (VerboseTrace) PrintFormat("%s(): Failed to allocate close task for ticket: %d", __FUNCTION__, ticket_no);
    return false; // Job is not allocated.
  }
}

/**
 * Remove specific task.
 * @todo: Move to Arrays.
 */
bool TaskRemove(int job_id) {
  todo_queue[job_id][0] = 0;
  todo_queue[job_id][2] = 0;
  if (VerboseTrace) PrintFormat("%: Task removed for id: %d", __FUNCTION__, job_id);
  return true;
}

/**
 * Check if task for specific ticket already exists.
 * @todo: Move to Arrays.
 */
bool TaskExistByKey(int key) {
  for (int job_id = 0; job_id < ArrayRange(todo_queue, 0); job_id++) {
    if (todo_queue[job_id][0] == key) {
      // if (VerboseTrace) Print(__FUNCTION__ + ": Task already allocated for key: " + key);
      return (true);
      break;
    }
  }
  return (false);
}

/**
 * Find available slot id.
 * @todo: Move to Arrays.
 */
int TaskFindEmptySlot(int key) {
  int taken = 0;
  if (!TaskExistByKey(key)) {
    for (int job_id = 0; job_id < ArrayRange(todo_queue, 0); job_id++) {
      // if (VerboseTrace) Print(__FUNCTION__ + ": job_id = " + job_id + "; key: " + todo_queue[job_id][0]);
      if (todo_queue[job_id][0] <= 0) { // Find empty slot.
        // if (VerboseTrace) Print(__FUNCTION__ + ": Found empty slot at: " + job_id);
        return job_id;
      } else taken++;
    }
    // If no empty slots, Otherwise increase size of array.
    int size = ArrayRange(todo_queue, 0);
    if (size < 1000) { // Set array hard limit.
      ArrayResize(todo_queue, size + 10);
      Msg::ShowText(StringFormat("Couldn't allocate a task slot, re-sizing array. New size: %d, Old size: %d", (size + 1), size),
         "Debug", __FUNCTION__, __LINE__, VerboseDebug);
      return size;
    } else {
      // Array exceeded hard limit, probably because of some memory leak.
      Msg::ShowText(StringFormat("Couldn't allocate a task slot, all are taken (%d of %d).", taken, size),
         "Debug", __FUNCTION__, __LINE__, VerboseDebug);
    }
  }
  return EMPTY;
}

/**
 * Run specific task.
 */
bool TaskRun(int job_id) {
  bool result = false;
  int key = todo_queue[job_id][0];
  int task_type = todo_queue[job_id][1];
  int retries = todo_queue[job_id][2];
  int cmd, sid, reason_id;
  // if (VerboseTrace) Print(__FUNCTION__ + ": Job id: " + job_id + "; Task type: " + task_type);

  switch (task_type) {
    case TASK_ORDER_OPEN:
       #ifdef __expire__ CheckExpireDate(); if (ea_expired) return false; #endif
       cmd = todo_queue[job_id][3];
       // double volume = todo_queue[job_id][4]; // FIXME: Not used as we can't use double to integer array.
       sid = todo_queue[job_id][5];
       // string order_comment = todo_queue[job_id][6]; // FIXME: Not used as we can't use double to integer array.
       result = ExecuteOrder((ENUM_ORDER_TYPE) cmd, sid, EMPTY, "", false);
      break;
    case TASK_ORDER_CLOSE:
        reason_id = todo_queue[job_id][3];
        if (OrderSelect(key, SELECT_BY_TICKET)) {
          if (CloseOrder(key, reason_id, false))
            result = TaskRemove(job_id);
        }
      break;
    case TASK_CALC_STATS:
        if (OrderSelect(key, SELECT_BY_TICKET, MODE_HISTORY)) {
          OrderCalc(key);
        } else {
          Msg::ShowText(StringFormat("Access to history failed with error: (%d).", GetLastError()),
            "Debug", __FUNCTION__, __LINE__, VerboseDebug);
        }
      break;
    default:
      Msg::ShowText(StringFormat("Unknown task: %d", task_type),
         "Debug", __FUNCTION__, __LINE__, VerboseDebug);
  };
  return result;
}

/**
 * Process task list.
 */
bool TaskProcessList(bool with_force = false) {
  int total_run = 0, total_failed = 0, total_removed = 0;
  int no_elem = 8;
  #ifdef __profiler__ PROFILER_START #endif

/* @todo
   // Check if bar time has been changed since last time.
   if (chart.GetBarTime() == last_queue_process && !with_force) {
     // if (VerboseTrace) Print("TaskProcessList(): Not executed. Bar time: " + bar_time + " == " + last_queue_process);
     return (false); // Do not process job list more often than per each minute bar.
   } else {
     last_queue_process = chart.GetBarTime(); // Set bar time of last queue process.
   }
 */

   market.RefreshRates();
   for (int job_id = 0; job_id < ArrayRange(todo_queue, 0); job_id++) {
      if (todo_queue[job_id][0] > 0) { // Find valid task.
        if (TaskRun(job_id)) {
          total_run++;
        } else {
          total_failed++;
          if (todo_queue[job_id][2]-- <= 0) { // Remove task if maximum tries reached.
            if (TaskRemove(job_id)) {
              total_removed++;
            }
          }
        }
      }
   } // end: for
   if (VerboseDebug && total_run+total_failed > 0)
     Print(__FUNCTION__, ": Processed ", total_run+total_failed, " jobs (", total_run, " run, ", total_failed, " failed (", total_removed, " removed)).");
  #ifdef __profiler__ PROFILER_STOP #endif
  return true;
}

/* END: TASK FUNCTIONS */

/**
 * Add message into the report file.
 */
void ReportAdd(string msg) {
  int last = ArraySize(log);
  ArrayResize(log, last + 1);
  log[last] = TimeToStr(time_current,TIME_DATE|TIME_SECONDS) + ": " + msg;
}

/**
 * Get extra stat report.
 */
string GetStatReport(string sep = "\n") {
  string output = "";
  output += StringFormat("Modelling quality:                          %.2f%%", Chart::CalcModellingQuality()) + sep;
  if (RecordTicksToCSV) {
    output += StringFormat("Total bars processed:                       %d", total_stats.GetTotalBars()) + sep;
    output += StringFormat("Total ticks processed:                      %d", ticker.GetTotalProcessed()) + sep;
    output += StringFormat("Total ticks ignored:                        %d", ticker.GetTotalIgnored()) + sep;
    output += StringFormat("Bars per hour (avg):                        %d", total_stats.GetBarsPerPeriod(PERIOD_H1)) + sep;
    output += StringFormat("Ticks per bar (avg):                        %d (bar=%dmins)", total_stats.GetTicksPerBar(), Period()) + sep;
  }
  //output += StringFormat("Ticks per min (avg):                        %d", total_stats.GetTicksPerMin()) + sep; / @todo

  return output;
}

//+------------------------------------------------------------------+
