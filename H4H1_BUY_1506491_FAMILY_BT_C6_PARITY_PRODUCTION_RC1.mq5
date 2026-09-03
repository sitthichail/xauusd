//+------------------------------------------------------------------+
//| AUREX RELEASE MANIFEST                                           |
//| EA            : H4H1 BUY                                         |
//| EA Version    : 5.1.1 C4 Transition Research v0.1                                          |
//| Magic         : 1506491                                          |
//| Shared UEE    : 1.1.3 (frozen dependency)                        |
//| Shared PRME   : current validated snapshot; formal tag pending   |
//| Shared SOF    : current validated snapshot; formal tag pending   |
//| Status        : PRODUCTION CANDIDATE                              |
//| Release Scope : Apply Aurex Research Management Profile v1.0  |
//| Entry Logic   : C4 RESEARCH BRANCH — H4 transition admission only         |
//+------------------------------------------------------------------+
// C4 TRANSITION RESEARCH v0.1 — production/control 1506272 source remains untouched.
// H4 transition thresholds are expressed in AUREX POINTS (100 pts = 1.00 XAUUSD).
//+------------------------------------------------------------------+
// H4H1 BUY v5.1.1 RESEARCH PROFILE RC1 — Aurex Shared UEE v1.1.3 — Magic 1506491
// Baseline: 1506272. Scope: add immutable candidate contract and route
// already-qualified H4H1 signals through Aurex Shared UEE. Strategy gates,
// pending-order construction, PRME V3, SOF, risk, SL/TP and sessions unchanged.
// No UEE optimization is permitted in this parity build.
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| *** THIS COPY: magic changed to 1506272, CSV filenames/SOF       |
//| identity suffixed _1506272, ONLY to run parallel-safe alongside  |
//| the still-live 1506262 instance for shared-PRME-engine migration |
//| validation (STAGE 1 -- PARITY BUILD). Scope of this copy: fixed  |
//| SL/TP position closing is replaced by the shared Aurex PRME      |
//| engine (CAurexPRME) configured through PRME V3 unified XAU price-move triggers.            |
//| TP1=500 Gold points (= $5.00 XAU price move), close 50%, BE after partial, ATR trailing. |
//| no time exit, i.e. behaviorally a no-op, so 1506272 should          |
//| reproduce 1506262's real trade history exactly. This file has NO     |
//| embedded management to begin with -- fixed SL/TP set once at pending  |
//| BuyStop fill, never touched again (same Phase 0 audit finding as the   |
//| completed H4H1 SELL 1506271 migration). H4 trend/H1 pullback/M5          |
//| confirmation/M5 exhaustion filter/BuyStop placement/pending-order         |
//| cancellation-expiry/entry rules/gate ordering/sessions/bias/initial SL/    |
//| initial TP/risk calc/lot sizing/position cap/SOF logging/BUY-only          |
//| direction are all untouched -- see the accompanying migration report        |
//| for the full mapping. IMPORTANT: PRME adoption is hooked into                |
//| CheckTicketLifecycle() at the exact point the pending order is confirmed      |
//| to have become an open position -- NOT at pending-order placement. An          |
//| active management policy is NOT implemented in this copy. ***                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  H4H1_Trend_EA_v4.3.mq5    Magic 1506261                                     |
//|  v4.3 STANDARDIZED — H4H1 BUY Forensic (50-bar log)                     |
//|  Based on v4.2. Diagnostics confirmed: 341 raw H4 bear bars in   |
//|  2024, 83 in 2025, ALL suppressed to NEUTRAL by EMA distance     |
//|  filter. Filter logic (< MinDistance) is symmetric for BULL and  |
//|  BEAR. Audit goal: print actual EMA50, EMA200, and distance for  |
//|  every raw bear bar (up to 50) — regardless of suppression — to  |
//|  confirm whether the EMA gap is genuinely below 40 on every bar  |
//|  or whether an asymmetric logic error is misclassifying bars.    |
//|  Also adds explicit suppression direction check to verify the    |
//|  distance filter applies identically to BULL and BEAR branches.  |
//|  Standardized: Gold symbol validation, Ask-Bid spread filter, dynamic risk lot defaults.                          |
//|  ---------------------------------------------------------------|
//|  [M5X] v4.4: M5 Exhaustion Filter LIVE PORT (candle scope).      |
//|    Ported verbatim from H4H1_BUY_Research_v3_2_1506361.mq5,      |
//|    whose scope=CANDLE path is the exact validated v3.0 Variant A |
//|    implementation (Stage 0-3 research, Jul 2026, QA-approved).   |
//|    Mechanism: raw EngulfRatio (cur body / prv body). Rejects the |
//|    bullish engulf candidate when ratio > InpM5ExhaustionCap.     |
//|    Cap default 4.5 = middle of validated stable region 4.0-5.0.  |
//|    Applied after the min-ratio filter, BEFORE the trend gate and |
//|    order creation. BUY-side only. Rejection does NOT lock the    |
//|    setup: later candidates in the same pullback remain eligible. |
//|    [M5X-B] pullback-scope machinery (experimental) is            |
//|    deliberately NOT ported: scope is structurally CANDLE here.   |
//|    LIVE DEPLOYMENT DEFAULT: InpUseM5ExhaustionFilter = true      |
//|    (research file defaults false; live mandates protection ON).  |
//|    All other logic byte-identical to v4.3 STANDARDIZED.          |
//+------------------------------------------------------------------+
#property copyright "ThankYou4Watching"
#property version   "5.12"
#property strict

#include <Trade\Trade.mqh>
#include <Aurex\UEE\UEE_Facade.mqh>
#include <Aurex\Observation\SOF_Framework.mqh>
#include <Aurex\Management\PRME_Core_RC25.mqh>
#include <Aurex\Session\SessionManager.mqh>
#include <Aurex\MarketPhase\MarketPhase_Engine.mqh> // [STRUCT-OBS] read-only H4/H1/M15 stage context

//--- Inputs
input group "=== H4 EMA Settings ==="
input int    InpH4_EMA_Fast        = 50;    // H4 EMA Fast period (trend)
input int    InpH4_EMA_Slow        = 200;   // H4 EMA Slow period (trend)
input double InpMinH4EMADistance   = 40.0;  // Min EMA50-EMA200 distance (0=disabled)

input group "=== C4 BULLISH TRANSITION RESEARCH (AUREX POINTS) ==="
input bool   InpC4EnableTransition          = true;   // Research branch: allow pre-crossover bullish-transition admission
input double InpC4MaxBearGapAurexPoints    = 2000.0; // Max remaining H4 EMA50<EMA200 gap; 100 Aurex pts = 1.00 price
input double InpC4MinGapContractAurexPoints= 100.0;  // Minimum H4 gap contraction vs previous closed H4 bar
input bool   InpC4RequireH1BullAlignment   = true;   // Require H1 EMA20>EMA50, close>EMA20, EMA20 rising

input group "=== H1 EMA Settings ==="
input int    InpH1_EMA_Fast        = 20;    // H1 EMA Fast period (pullback)
input int    InpH1_EMA_Slow        = 50;    // H1 EMA Slow period (pullback)

input group "=== Order Settings ==="
input int    InpTradeDirection      = 1;     // Trade direction: 0=Both 1=Buy Only 2=Sell Only
input double InpMinPullbackDepthATR = 0.60; // Pullback depth ATR multiplier (0=disabled)
input int    InpMinPullbackBars     = 4;    // Min closed H1 bars of pullback before M5 gate opens
input int    InpEntryBufferPoints   = 20;   // Entry buffer above/below signal candle (points)
input bool   InpUseRiskLot          = false;// Use dynamic risk sizing? false = FIXED LOT 0.02
input double InpRiskPercent         = 1.0;  // Ignored while dynamic risk sizing = false
input double InpFixedLot            = 0.02; // ACTIVE fixed entry lot for Research Profile
input double InpRiskReward          = 3.0;  // Risk:Reward ratio
input int    InpMaxPositionSlots     = 3;    // MAX 3 slots: open positions + live pending orders
input double InpMinEngulfRatio      = 1.0;  // Min body ratio cur/prv (1.0=disabled)
input bool   InpUseM5ExhaustionFilter = true; // [M5X] Reject bullish engulf when ratio exceeds cap (LIVE default ON per deployment decision)
input double InpM5ExhaustionCap       = 4.5;  // [M5X] Max body ratio cur/prv (stable region 4.0-5.0; 4.5 = research default)
input bool   InpRequireEMA20Touch   = false;// Require H1 EMA20 touch before M5 gate opens

input group "=== SELL Confirmation Filters ==="
input bool   InpSellBreakPrevLow    = false; // Filter 1: engulf close must be < previous candle low
input bool   InpSellBreakSwingLow   = false; // Filter 2: engulf low must break lowest low of prior 3 M5 bars
input bool   InpSellEMA20Slope      = false; // Filter 3: M5 EMA20 slope must be negative at signal candle

input group "=== STANDARD SYMBOL / SPREAD ==="
input bool   InpRequireGoldSymbol  = true;  // true=EA runs only on Gold symbols (GOLD/XAU*)
input double InpMaxSpreadDollars   = 0.80;  // Max Gold spread in price dollars (Ask-Bid), e.g. 0.80 = 80 cents
input int    InpDeviationPoints    = 30;    // Max trade deviation in broker points

input group "=== PRME V3 Management ==="
input double InpPRME_TP1GoldPoints    = 500.0;// PORTABLE: 100 Gold pts=1.00 XAU price; 500=5.00 price move
input double InpPRME_PartialPct       = 50.0; // Percent of current position volume closed at TP1
input double InpPRME_BEBufferPoints   = 0.0;  // Legacy broker-point BE offset (kept for compatibility; production B1 uses spread-aware Gold-price protection)
input double InpPRME_BEExtraGoldPoints= 0.0;  // Extra protection beyond live spread; Aurex Gold points (100=$1.00 XAU move)
input double InpPRME_ATRTrailMult     = 1.5;  // H1 ATR multiplier after protected BE
input bool   InpPRME_DebugManagement  = false;// Verbose per-tick PRME diagnostics

input group "=== LIVE DIAGNOSTIC HEARTBEAT ==="
input bool   InpHeartbeatEnable       = true; // Telemetry only; never gates or creates orders
input int    InpHeartbeatSeconds      = 30;   // Print H4H1 runtime state every N seconds while ticks arrive


input group "=== H4/H1 STRUCTURAL EVENT OBSERVER (READ-ONLY) ==="
input bool   InpStructObsEnable                 = true;   // Observation only; never gates or creates orders
input int    InpStructObsBootstrapBars          = 5000;   // Shared MarketPhase bootstrap
input string InpStructObsFile                   = "V01.csv";
input double InpStructObsMinLowerWickBodyRatio  = 1.50;   // Context tag only
input double InpStructObsMinLowerWickRangePct   = 0.35;   // Context tag only (0..1)


input group "=== STRUCTURE V0.2 — BOS + RBR/DBD OBSERVER ==="
input int    InpStructPivotLeft=2;
input int    InpStructPivotRight=2;
input int    InpStructSwingLookback=120;
input int    InpStructBaseMaxBars=6;
input double InpStructBaseMaxRangeATR=2.00;
input double InpStructRallyMinBodyATR=0.55;
input double InpStructRallyMinBodyRatio=0.55;
input string InpStructObsV02File="V02.csv";


input group "=== STRUCTURE V0.3 — DIRECTIONAL EVIDENCE OBSERVER ==="
input string InpDirObsFile="V03.csv";
input int    InpDirEvidenceLookbackH1=12;       // rolling H1 hours/events
input int    InpDirDevelopThreshold=60;         // evidence score threshold
input int    InpDirConfirmThreshold=75;         // evidence score threshold
input int    InpDirConflictMargin=10;           // minimum Bull-Bear separation
input int    InpDirH4BOSWeight=35;
input int    InpDirH4PatternWeight=20;          // RBR/DBD
input int    InpDirH1BOSWeight=15;
input int    InpDirH1PatternWeight=10;          // RBR/DBD
input int    InpDirOppositeH1BOSPenalty=15;


input group "=== STRUCTURE V0.4 — BREAKOUT LIFECYCLE OBSERVER ==="
input string InpLifecycleObsFile="V04.csv";
input int    InpLifecycleAcceptanceH4Bars=2;        // hold beyond breakout for N closed H4 bars
input int    InpLifecycleConfirmWindowH1Hours=12;   // H1 confirmation must occur after H4 break within this window
input int    InpLifecycleFailureTolerancePoints=300;// Aurex points back through broken level -> fail
input bool   InpLifecycleRequireH4RBRForAccepted=false;
input bool   InpLifecycleRequireH1BOSForConfirmed=true;
input bool   InpLifecycleAllowH1RBRForConfirmed=true;


input group "=== STRUCTURE V0.5 — BREAKOUT/RETEST/ACCEPTANCE OBSERVER ==="
input string InpV05ObsFile="V05.csv";
input int    InpV05RetestTolerancePoints=500;       // Aurex points around broken H4 level
input int    InpV05HardFailurePoints=1200;          // Aurex points through broken level => hard fail
input int    InpV05MaxRetestH4Bars=3;               // retest/hold window after initial H4 break
input int    InpV05ConfirmWindowH1Hours=16;          // H1 confirmation must be after H4 break
input bool   InpV05RequireH1BOS=true;
input bool   InpV05AllowH1RBR=true;
input bool   InpV05RequireFreshContinuationEvent=true;


input group "=== STRUCTURE V0.6 — GENERAL MARKET LIFECYCLE OBSERVER ==="
input string InpV06StateFile="V06S.csv";
input string InpV06EpisodeFile="V06E.csv";
input int    InpV06BaseLookbackH4Bars=12;           // Base-quality window before H4 break
input int    InpV06CompressionRecentBars=4;          // Recent H4 range window
input int    InpV06BoundaryTestTolerancePoints=400; // Aurex points near base boundary
input int    InpV06RetestTolerancePoints=500;       // Aurex points around broken level
input int    InpV06HardFailurePoints=1200;          // Aurex points through broken level
input int    InpV06MaxRetestH4Bars=3;
input int    InpV06ConfirmWindowH1Hours=16;
input bool   InpV06RequireH1BOS=true;
input bool   InpV06AllowH1RBR=true;


input group "=== STRUCTURE V0.7 — TREND EPISODE / LEG OBSERVER ==="
input string InpV07EpisodeLegFile="V07.csv";
input int    InpV07HardFailurePoints=1200;      // same structural failure concept as V0.6
input int    InpV07ConfirmWindowH1Hours=16;
input bool   InpV07RequireH1BOSForUnlock=true;
input bool   InpV07AllowRBRForContinuation=true;


input group "=== STRUCTURE V0.8 — LEG FAILURE / EPISODE UNRESOLVED OBSERVER ==="
input string InpV08EventFile="V08E.csv";
input string InpV08ResolutionFile="V08R.csv";
input int    InpV08HardFailurePoints=1200;        // active-leg invalidation only
input int    InpV08ConfirmWindowH1Hours=16;
input bool   InpV08RequireFreshH1ConfirmAfterRecovery=true;


input group "=== STRUCTURE V0.9 — H1 EVENT DEDUP OBSERVER ==="
input string InpV09EventFile="V09.csv";
input double InpV09LevelEpsilonPoints=10.0;     // same structural level tolerance
input bool   InpV09DedupRBRDBDByBase=true;


input group "=== BTB C5 — BEAR->BULL TRANSITION ACTUAL-EXECUTION CHALLENGER ==="
input bool   InpBTBShadowEnable=true;                 // keep observer telemetry active
input bool   InpBTBC5ExecuteTransition=true;            // C5: execute pre-registered BTB challenger; research/backtest only
input bool   InpBTBC5UseCandidateA=true;                // A = V08 BEAR_CONTINUATION + BOS penetration <= threshold
input double InpBTBC5CandidateABosMaxGoldPts=250.0;     // plateau edge from C4 robustness matrix
input bool   InpBTBC5UseCandidateB=true;                // B = H1 lower wick in stable 5-10% band
input double InpBTBC5CandidateBWickMinPct=5.0;
input double InpBTBC5CandidateBWickMaxPct=10.0;
input string InpBTBShadowFile="BTB_C4_FEATURES.csv";
input string InpBTBMatrixFile="BTB_C4_ROBUSTNESS.csv";
input int    InpBTBHorizonH1Bars=24;                  // follow each event for 24 H1 bars
input double InpBTBFirstHitGoldPoints=500.0;          // +$5 / -$5 first-hit diagnostic




input group "=== H4H1 BUY B RC2.5 — CERTIFICATION PERFORMANCE CLEANUP ==="
input bool   InpRC2EnforceRunnerATRTrail=true;
input string InpRC2RunnerAuditFile="RUNNER.csv";

input group "=== H4H1 BUY B LIVE-DEMO RC1 ==="
input bool   InpBRC_NoFixedTP=true;        // runner uses PRME, not fixed RR TP
input bool   InpBRC_RequireBuyOnly=true;   // deployment guard
input bool   InpBRC_RequireFamilyBOnly=true;// deployment guard

input group "=== V1.0 TRADEABLE STRUCTURAL RESEARCH ==="
input bool   InpV10EnableTrading=true;
input bool   InpV10EnableLegacyEntries=false;       // isolate structural strategy from old EMA/pullback entry path
input int    InpV10TradeDirection=1;                // RC1 BUY only                // 0=Both 1=Buy 2=Sell
input bool   InpV10FamilyA_FirstConfirm=false;      // RC1 disabled
input bool   InpV10FamilyB_ContinuationBOS=true;  // RC1 baseline
input bool   InpV10FamilyC_RBRDBD=false;           // RC1 disabled
input bool   InpV10FamilyD_RecoveryConfirm=false; // RC1 observer only
input double InpV10EntryBufferAurexPoints=20.0;     // 20 pts = 0.20 XAU
input int    InpV10PendingExpiryM5Bars=12;           // 1 hour freshness for H1 structural signal
input string InpV10TradeFile="V10.csv";
input group "=== 1506491 FAMILY-B B1 PRODUCTION ==="
input bool   InpB1ProductionEnable=true;
input double InpB1AdaptiveRangeThresholdATR=0.75;
input double InpB1LimitDepthATR=0.25;

input group "=== RC3C CROSSED-LIMIT GEOMETRY SAFETY ==="
input bool     InpB1RejectCollapsedLimitGeometry = true; // live-demo safety fix
input double   InpB1MinFillToSL_ATR              = 0.20; // minimum actual executable distance to structural SL
input double   InpB1MinFillToSLGoldPoints        = 100;  // absolute minimum = $1.00 XAU price
input int    InpB1GraceMinutes=15;
input bool   InpBTBC6TImmediateProtectedBE=true; // C6 research: Family-T only gets immediate spread-aware BE after TP1; Family-B retains grace
input string InpB1LifecycleFile="B1_Lifecycle.csv";
input bool   InpB1RequireHedgingForMax3=true;


input group "=== 1506290 ENTRY + TP RUNNER SHADOW RESEARCH ==="
input bool   InpEPRShadowEnable=true;                 // observation only; real order path remains current BUY STOP
input string InpEPRShadowFile="H4H1_BUY_1506290_EntryTP_Shadow.csv";
input double InpEPRLimitATR_1=0.10;
input double InpEPRLimitATR_2=0.15;
input double InpEPRLimitATR_3=0.20;
input double InpEPRLimitATR_4=0.25;
input double InpEPRLimitATR_5=0.33;
input double InpEPRProtectATR_0=0.00;                 // BE control
input double InpEPRProtectATR_1=0.10;
input double InpEPRProtectATR_2=0.15;
input double InpEPRProtectATR_3=0.20;
input double InpEPRProtectATR_4=0.25;
input bool   InpEPRUseCurrentTrail=true;              // preserve current 1.50 H1 ATR runner trail in shadow model



input group "=== LD1 PARITY / LIFECYCLE CERTIFICATION ==="
input bool   InpLD1DirectionNeutralPRMEAdopt=true;
input string InpLD1ParityFile="H4H1_TREND_LD1_ParityAudit.csv";

input group "=== Log Settings ==="
input bool   InpShowLog            = true;  // Log state changes to Experts tab
input int    InpMagicNumber        = 1506491; // Unique magic number for H4H1 BUY
input bool   InpEnableCSVLog       = true;  // Enable CSV forensic logging
input string InpLiveCSVFile        = "LIVE.csv"; // CSV filename
// [PRME EXTRACTION] New for this migration -- H4H1 BUY had no lifecycle/
// PRME-state CSV concept before this. Written by the shared Aurex PRME
// engine, not this EA's own live-test logger above.
input string InpPRMELifecycleFile  = "PRME_L.csv";
input string InpPRMEStateFile      = "PRME_S.csv";

input group "=== V5.0 AUREX SHARED UEE STANDARD ==="
input bool   InpEnableCandidateCSV = true;
input string InpCandidateCSVFile   = "UEE_C.csv";
input string InpUEEDecisionsFile   = "UEE_D.csv";
input string InpUEEStateFile       = "UEE_S.csv";
// UEE logging is mandatory in the Aurex standard; retained only for input-file compatibility.
input bool   InpEnableUEELogging   = true;



//+------------------------------------------------------------------+
//| H4H1 V5.0 immutable Candidate Contract                           |
//| Strategy owns facts. Shared UEE owns qualification verdict.      |
//+------------------------------------------------------------------+
struct H4H1Candidate
  {
   ulong           CandidateID;
   string          StrategyID;
   datetime        SignalTime;
   ENUM_ORDER_TYPE Direction;
   double          EntryPrice;
   double          StopLoss;
   double          TakeProfit;
   double          ATR;
   int             H4TrendDirection;
   int             PullbackBars;
   double          SignalHigh;
   double          SignalLow;
   double          CurrentBody;
   double          PreviousBody;
   double          EngulfRatio;
   bool            EngulfObserved;
   bool            ExhaustionObserved;
  };

ulong      g_candidate_sequence = 0;
int        g_candidate_csv_handle = INVALID_HANDLE;
string     g_uee_session_id = "";
UEE_State  g_h4h1_uee_state;
UEE_Config g_h4h1_uee_config;

ulong NextCandidateID(const datetime signal_time)
  {
   g_candidate_sequence++;
   return (ulong)signal_time * 1000ULL + (g_candidate_sequence % 1000ULL);
  }

H4H1Candidate CreateH4H1Candidate(const int direction,
                                  const datetime signal_time,
                                  const double entry,
                                  const double sl,
                                  const double tp,
                                  const int trend,
                                  const int pullback_bars,
                                  const double signal_high,
                                  const double signal_low,
                                  const double cur_body,
                                  const double prv_body)
  {
   H4H1Candidate c;
   c.CandidateID        = NextCandidateID(signal_time);
   c.StrategyID         = "H4H1_BUY_1506491_B1_PROD";
   c.SignalTime         = signal_time;
   c.Direction          = (direction == 1 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);
   c.EntryPrice         = entry;
   c.StopLoss           = sl;
   c.TakeProfit         = tp;
   c.ATR                = GetPRME_ATR();
   c.H4TrendDirection   = trend;
   c.PullbackBars       = pullback_bars;
   c.SignalHigh         = signal_high;
   c.SignalLow          = signal_low;
   c.CurrentBody        = cur_body;
   c.PreviousBody       = prv_body;
   c.EngulfRatio        = (prv_body > 0.0 ? cur_body / prv_body : 0.0);
   c.EngulfObserved     = true;
   c.ExhaustionObserved = IsM5Exhaustion(cur_body, prv_body);
   return c;
  }

void LogCandidateCreated(const H4H1Candidate &c)
  {
   if(!InpEnableCandidateCSV) return;
   if(g_candidate_csv_handle == INVALID_HANDLE)
     {
      g_candidate_csv_handle = FileOpen(g_pathCandidateCSV,
                                        FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
      if(g_candidate_csv_handle == INVALID_HANDLE)
        {
         Print("[V5-CANDIDATE] Cannot open ", g_pathCandidateCSV,
               " error=", GetLastError());
         return;
        }
      FileWrite(g_candidate_csv_handle,
                "CandidateID","StrategyID","Lifecycle","SignalTime","Direction",
                "EntryPrice","StopLoss","TakeProfit","ATR","H4TrendDirection",
                "PullbackBars","SignalHigh","SignalLow","CurrentBody",
                "PreviousBody","EngulfRatio","EngulfObserved","ExhaustionObserved",
                "RoutingMode");
     }
   FileWrite(g_candidate_csv_handle,
             (string)c.CandidateID,c.StrategyID,"CREATED",
             TimeToString(c.SignalTime,TIME_DATE|TIME_SECONDS),
             EnumToString(c.Direction),
             DoubleToString(c.EntryPrice,_Digits),DoubleToString(c.StopLoss,_Digits),
             DoubleToString(c.TakeProfit,_Digits),DoubleToString(c.ATR,_Digits),
             c.H4TrendDirection,c.PullbackBars,
             DoubleToString(c.SignalHigh,_Digits),DoubleToString(c.SignalLow,_Digits),
             DoubleToString(c.CurrentBody,_Digits),DoubleToString(c.PreviousBody,_Digits),
             DoubleToString(c.EngulfRatio,6),
             (c.EngulfObserved ? "true" : "false"),
             (c.ExhaustionObserved ? "true" : "false"),
             "SHARED_UEE_STANDARD");
   FileFlush(g_candidate_csv_handle);
  }

void RouteH4H1Candidate(const H4H1Candidate &candidate)
  {
   if(!InpV10EnableLegacyEntries)
     {
      LogCandidateCreated(candidate);
      return;
     }
   LogCandidateCreated(candidate);

   const int direction = (candidate.Direction == ORDER_TYPE_BUY_STOP ? 1 : -1);
   const ENUM_UEE_DIRECTION ueeDirection = (direction == 1 ? UEE_DIR_UP : UEE_DIR_DOWN);
   const double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   const double rangePts = (point > 0.0 ? MathAbs(candidate.SignalHigh-candidate.SignalLow)/point : 0.0);
   const double atrPts   = (point > 0.0 ? candidate.ATR/point : 0.0);
   const double bodyPts  = (point > 0.0 ? candidate.CurrentBody/point : 0.0);
   const double rangeToATR = (atrPts > 0.0 ? rangePts/atrPts : 0.0);
   const double bodyRatio   = (rangePts > 0.0 ? bodyPts/rangePts : 0.0);
   const bool directionAgreement = (candidate.H4TrendDirection == direction);
   const string patternTag = (candidate.EngulfObserved ? "H4H1_BULL_ENGULF" : "NONE");

   UEE_EvaluationContext ueeCtx = UEE_MakeEvaluationContext(
      g_uee_session_id,
      candidate.StrategyID,
      InpMagicNumber,
      candidate.CandidateID,
      "H4H1_PULLBACK",
      _Symbol,
      "M5",
      candidate.SignalTime,
      (bool)MQLInfoInteger(MQL_TESTER) ? "BACKTEST" : "LIVE");

   UEE_DecisionPackage pkg;
   UEE_EvaluateStrategyEvidenceStandard(ueeCtx,
                                        g_h4h1_uee_state,g_h4h1_uee_config,
                                        ueeDirection,"H4H1_PULLBACK",
                                        MathMax(1,candidate.PullbackBars),
                                        rangeToATR,bodyRatio,0.0,
                                        directionAgreement,patternTag,true,pkg);

   PrintFormat("[H4H1-UEE] ID=%I64u Verdict=%s Reason=%s Pattern=%s",
               candidate.CandidateID,pkg.Verdict,pkg.ReasonCode,pkg.PatternTag);

   if(pkg.Verdict != "QUALIFIED")
     {
      PrintFormat("[H4H1-UEE] Candidate %I64u blocked by Shared UEE",candidate.CandidateID);
      return;
     }

   PlacePending(direction,candidate.EntryPrice,candidate.StopLoss);
  }


// [V1.0] Globals declared before PlacePending() so the common order path
// can stamp research order comments and suppress legacy SOF gate coupling.
bool   g_v10Placing=false;
string g_v10OrderComment="";

//--- Indicator handles
int g_h4_ema50_handle  = INVALID_HANDLE;
int g_h4_ema200_handle = INVALID_HANDLE;
int g_h1_ema20_handle  = INVALID_HANDLE;
int g_h1_ema50_handle  = INVALID_HANDLE;
int g_h1_atr_handle    = INVALID_HANDLE;
// [RC2.5] Dedicated H1 ATR(14) handle for runner management.
int g_rc24_h1_atr_handle = INVALID_HANDLE;
int g_m5_ema20_handle  = INVALID_HANDLE;   // M5 EMA20 — used for SELL EMA slope filter

// [PRME EXTRACTION] Reuses g_h1_atr_handle above -- no new indicator
// handle created for PRME's use. Inert under PRME V3's PRME_P0_FIXED
// policy (no trailing to compute), but wired now for a later activation
// step.
double GetPRME_ATR()
  {
   if(g_h1_atr_handle == INVALID_HANDLE) return(0.0);
   double buf[];
   if(CopyBuffer(g_h1_atr_handle, 0, 1, 1, buf) <= 0) return(0.0);
   return(buf[0]);
  }

//--- Trade object
CTrade g_trade;

// [PRME EXTRACTION] The shared Aurex PRME engine instance. PRME V3
// (this file) configures it as PRME_P0_FIXED -- fixed SL/TP only, no
// active management -- so it only adopts/tracks positions and logs
// their lifecycle; it does not modify a stop or close volume. See
// CH4H1BuyPRMEEvents below for the SOF event-sink wiring. Adoption is
// hooked into CheckTicketLifecycle(), not into pending-order placement
// -- see that function for exactly where.
CAurexPRME g_prme;

//--- State tracking
//    g_last_trend:      1=BULLISH | -1=BEARISH | 0=NEUTRAL | 99=uninitialised
//    g_setup_triggered: true once a signal fires this pullback — no further signals
//    g_locked_engulfing: 1=BUY locked | -1=SELL locked | 0=none
//    g_pending_ticket:  0 = no pending order live
int      g_last_trend        = 99;
bool     g_last_pullback     = false;
int      g_last_engulfing    = 0;
string   g_last_signal       = "NONE";
bool     g_setup_triggered   = false;
int      g_locked_engulfing  = 0;
double   g_signal_high       = 0.0;
double   g_signal_low        = 0.0;
datetime g_signal_time       = 0;
ulong    g_pending_ticket    = 0;
int      g_pending_direction = 0; // [LD1] +1 BUY, -1 SELL for direction-neutral telemetry
double   g_order_price       = 0.0;
double   g_stop_loss         = 0.0;
long     g_risk_points       = 0;
double   g_calc_lot          = 0.0;
double   g_risk_money        = 0.0;
double   g_take_profit       = 0.0;

//--- Pullback filters — state
bool     g_ema20_accepted_this_pb = false;
bool     g_ema20_reject_logged    = false;
bool     g_depth_logged_this_pb   = false;
int      g_pullback_bar_count     = 0;
datetime g_last_pb_h1_bar_time    = 0;
bool     g_duration_gate_reached  = false;

//--- H4 EMA distance filter — bar guard
datetime g_last_h4_suppressed_bar_time = 0;

//--- v4.2 H4 trend detection diagnostics
//    All counters are H4-bar-level (one increment per closed H4 bar, not per tick).
//    "raw" = BEFORE the EMA distance filter overwrites trend.
//    Bar guard: g_h4_diag_last_bar_time prevents double-counting within the same H4 bar.
datetime g_h4_diag_last_bar_time  = 0;   // bar-time guard for all H4 diagnostic counters
int      g_h4_raw_bear_bars       = 0;   // H4 bars where EMA50 < EMA200 (raw, pre-filter)
int      g_h4_raw_bull_bars       = 0;   // H4 bars where EMA50 > EMA200 (raw, pre-filter)
int      g_h4_raw_neutral_bars    = 0;   // H4 bars where EMA50 == EMA200 (raw)
int      g_h4_post_bear_bars      = 0;   // H4 bars where trend==-1 after distance filter
int      g_h4_post_bull_bars      = 0;   // H4 bars where trend==1  after distance filter
int      g_h4_post_neutral_bars   = 0;   // H4 bars where trend==0  after distance filter (incl. suppressed)
int      g_h4_suppressed_bear     = 0;   // H4 bars: raw==BEAR but distance filter → NEUTRAL
int      g_h4_suppressed_bull     = 0;   // H4 bars: raw==BULL but distance filter → NEUTRAL

//--- EMA distance running stats (updated every H4 bar)
double   g_ema_dist_min           = DBL_MAX; // smallest gap seen (initialise to max so first real value wins)
double   g_ema_dist_max           = 0.0;     // largest gap seen
double   g_ema_dist_sum           = 0.0;     // accumulator for average calculation
int      g_ema_dist_count         = 0;       // number of H4 bars sampled

//--- First-50 audit logs for raw H4 bear bars
//    Two separate logs, both capped at 50 entries each:
//      RAW-BEAR-BAR  : every raw bear bar (EMA50 < EMA200), shows actual distance
//                      vs MinDistance threshold — fires regardless of suppression.
//                      This is the primary audit log to verify the filter direction.
//      SUPPRESS-BEAR : subset where distance < MinDist → trend forced to NEUTRAL.
//    Comparing the two logs isolates whether ALL bear bars are suppressed
//    or only a subset, and whether the distance values justify suppression.
int      g_raw_bear_log_count      = 0;   // RAW-BEAR-BAR lines logged so far
int      g_suppress_bear_log_count = 0;   // SUPPRESS-BEAR lines logged so far

//--- Session summary counters
int      g_cnt_pullbacks_found    = 0;
int      g_cnt_duration_gate_pass = 0;
int      g_cnt_duration_gate_rej  = 0;
int      g_cnt_m5_after_duration  = 0;   // engulfings that reached FinalSignal
int      g_orders_placed          = 0;
int      g_depth_rejected         = 0;
int      g_ema_dist_suppressed    = 0;   // H4 bars suppressed by EMA distance filter

//--- Signal counters
int      g_buy_signals   = 0;
int      g_sell_signals  = 0;

//--- [M5X] exhaustion filter state
int g_m5x_rejects = 0;   // count of bullish engulf signals rejected by the exhaustion cap

//+------------------------------------------------------------------+
//| [M5X] IsM5Exhaustion -- single source of truth for the cap test. |
//| Returns true only when the filter is enabled AND the ratio is    |
//| defined (prv_body > 0) AND cur/prv exceeds the cap.              |
//| prv_body == 0 (doji previous): ratio undefined -> NOT exhaustion,|
//| matching the research definition (logged EngulfRatio = 0 there). |
//+------------------------------------------------------------------+
bool IsM5Exhaustion(const double cur_body, const double prv_body)
  {
   if(!InpUseM5ExhaustionFilter) return false;
   if(prv_body <= 0.0)           return false;
   return (cur_body > prv_body * InpM5ExhaustionCap);
  }

//--- SELL pipeline diagnostic counters
//    RawBearEngulf    : raw bearish body-engulf detected (pre-ratio, pre-trend)
//    TrendAlignedBear : raw bearish engulf AND trend==-1 (post-ratio, pre-direction-filter)
//    SellOrdersPlaced : SELL STOP orders successfully sent to broker
//    SellRejStops     : SELL STOP rejected by broker stops-level distance check
//    (SellSignals reuses g_sell_signals declared above)
int      g_raw_bear_engulf      = 0;
int      g_trend_aligned_bear   = 0;
int      g_sell_orders_placed   = 0;
int      g_sell_rej_stops       = 0;

//--- v4.1 SELL confirmation pipeline counters
//    Waterfall: RawBearEngulf → BreakPrevLow → BreakSwingLow → EMA20SlopeBear → FinalSellSignal
//    Each counter is incremented when a bearish engulf (engulfing==-1, post-trend-gate) passes
//    up to and including that stage. Disabled filters pass all candidates through.
//    RawBearEngulf already declared above — reused as PRME V3 entry point.
int      g_diag_break_prev_low   = 0;   // Stage 2: close < previous candle low
int      g_diag_break_swing_low  = 0;   // Stage 3: low < lowest low of prior 3 M5 bars
int      g_diag_ema20_slope_bear = 0;   // Stage 4: M5 EMA20[1] < M5 EMA20[2] (slope negative)
int      g_diag_final_sell       = 0;   // Stage 5: all enabled filters passed → signal fires

//--- Trade outcome counters — populated in OnTradeTransaction
int      g_stat_trades   = 0;
int      g_stat_wins     = 0;
int      g_stat_losses   = 0;
int      g_buy_wins      = 0;
int      g_buy_losses    = 0;
int      g_sell_wins     = 0;
int      g_sell_losses   = 0;


//+------------------------------------------------------------------+
//| Forward-test CSV forensic logging                                |
//+------------------------------------------------------------------+
int    g_hCSV            = INVALID_HANDLE;

//--- SOF V2 SessionManager and runtime-resolved Run paths
CAurexSessionManager g_sessionMgr;
string g_pathLiveCSV        = "";
string g_pathCandidateCSV   = "";
string g_pathUEEDecisions   = "";
string g_pathUEEState       = "";
string g_pathPRMELifecycle  = "";
string g_pathPRMEState      = "";
string g_pathSOFSession     = "";
string g_pathSOFErrors      = "";
string g_pathSOFGates       = "";
string g_pathSOFTrades      = "";
string g_pathSOFSummary     = "";
bool   g_recoveryPending    = false;
int    g_recoveryPosCount   = 0;

//+------------------------------------------------------------------+
//| SOF (Strategy Observability Framework) INTEGRATION — ADDITIVE ONLY|
//| Everything here and every call site elsewhere in this file is    |
//| read-only observation. SOF is a passive observer only — see the  |
//| H4H1 BUY SOF v1 integration task and its approved Phase 0        |
//| (14 source-literal gates, decomposed compound-condition gates    |
//| 1-5, one Evaluation per new completed M5 bar).                   |
//+------------------------------------------------------------------+
SOF_Instance g_sof;
bool         g_sofStarted = false;

// 14 registered gates, source order, as approved.
string       g_sofGateOrder[14] =
  {
   "H4Trend",               // 0
   "PullbackActive",        // 1
   "OneSignalPerPullback",  // 2
   "PullbackDepth",         // 3
   "PullbackMaturity",      // 4
   "EMA20Touch",            // 5
   "BullishEngulf",         // 6
   "MinimumEngulfRatio",    // 7
   "M5Exhaustion",          // 8
   "DirectionAllowed",      // 9
   "Spread",                // 10
   "StopsLevelValid",       // 11
   "LotValid",              // 12
   "OrderExecution"         // 13
  };

//--- Position <-> TradeObservationID correlation map, for the CLOSED
//    event only. Keyed by the real POSITION_IDENTIFIER, fetched fresh
//    at fill time -- never assumed equal to the pending order ticket.
#define SOF_POS_MAP_SIZE 64
struct SOF_PosCorrelation
  {
   long   positionId;
   ulong  tradeObservationId;
   datetime openTime;
   bool   active;
  };
SOF_PosCorrelation g_sofPosMap[SOF_POS_MAP_SIZE];

//--- SOF-only pending-order tracking. Scalar, not an array: this EA
//    tracks exactly one pending order at a time (g_pending_ticket),
//    so SOF mirrors that shape rather than inventing a map for a
//    cardinality that never exceeds 1. Entirely separate from
//    g_pending_ticket itself -- never read from or written into it.
ulong  g_sofPendingOrderTicket = 0;
ulong  g_sofPendingTradeObsID  = 0;
ulong  g_sofPendingEvalID      = 0;

//--- SOF-only M5-bar evaluation-scoping guard (approved decision 3).
//    Purely additive: controls only whether SOF opens an Evaluation
//    this tick. Never gates, skips, or alters any strategy code --
//    every tick still runs the full strategy logic below regardless
//    of this guard's value.
datetime g_sofLastM5BarTime = 0;

//--- SOF plumbing only -- passes the current Evaluation/trade-observation
//    identity into PlacePending() without changing its signature.
ulong  g_sofCurrentEvalID     = 0;
ulong  g_sofCurrentTradeObsID = 0;
bool   g_sofRecordThisCall    = false;


string TrendLabel(const int trend)
  {
   if(trend ==  1) return "BULLISH";
   if(trend == -1) return "BEARISH";
   if(trend ==  0) return "NEUTRAL";
   return "UNINIT";
  }

string BoolLabel(const bool v) { return v ? "TRUE" : "FALSE"; }

void CSVOpen()
  {
   if(!InpEnableCSVLog) return;

   bool file_exists = FileIsExist(g_pathLiveCSV);
   if(file_exists)
      g_hCSV = FileOpen(g_pathLiveCSV, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ);
   else
      g_hCSV = FileOpen(g_pathLiveCSV, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ);
   if(g_hCSV == INVALID_HANDLE)
     { PrintFormat("ERROR: Cannot open CSV: %s err=%d", g_pathLiveCSV, GetLastError()); return; }
   if(!file_exists)
     {
      FileWrite(g_hCSV,
                "Time","Event","Direction","H4Trend",
                "PullbackDetected","PullbackBars","PullbackDepthATR",
                "EngulfDetected","EngulfRatio","EMA20Slope",
                "BreakPrevLow","BreakSwingLow",
                "EntryPrice","StopLoss","TakeProfit",
                "Ticket","LotSize","RiskPoints",
                "ProfitMoney","ProfitPoints","ExitReason","Note");
      FileFlush(g_hCSV);
     }
   else
      FileSeek(g_hCSV, 0, SEEK_END);
  }

void CSVClose()
  {
   if(g_candidate_csv_handle != INVALID_HANDLE)
     {
      FileClose(g_candidate_csv_handle);
      g_candidate_csv_handle = INVALID_HANDLE;
     }
   if(g_hCSV != INVALID_HANDLE) { FileFlush(g_hCSV); FileClose(g_hCSV); g_hCSV = INVALID_HANDLE; }
  }

//--- General events: INIT, DEINIT, PENDING_PLACED, PENDING_CANCELLED, etc.
void CSVWrite(string event_type, string direction, ulong ticket,
              double entry, double sl, double tp, double lot,
              long risk_points, double risk_money, double profit_money, string note)
  {
   if(g_hCSV == INVALID_HANDLE) return;
   FileWrite(g_hCSV,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             event_type, direction,
             TrendLabel(g_last_trend),
             BoolLabel(g_last_pullback),
             IntegerToString(g_pullback_bar_count),
             "","","","","",
             DoubleToString(entry, _Digits),
             DoubleToString(sl, _Digits),
             DoubleToString(tp, _Digits),
             (string)ticket,
             DoubleToString(lot, 2),
             IntegerToString((int)risk_points),
             DoubleToString(profit_money, 2),
             "","",
             note);
   FileFlush(g_hCSV);
  }

//--- SIGNAL row — written when engulf fires, before PlacePending
void CSVWriteSignal(string direction,
                    double entry_candidate, double sl_candidate, double tp_candidate,
                    int    pullback_bars,   double pullback_depth_atr,
                    double engulf_ratio,    double ema20_slope,
                    bool   break_prev_low,  bool   break_swing_low)
  {
   if(g_hCSV == INVALID_HANDLE) return;
   FileWrite(g_hCSV,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             "SIGNAL", direction,
             TrendLabel(g_last_trend),
             "TRUE",
             IntegerToString(pullback_bars),
             DoubleToString(pullback_depth_atr, 5),
             "TRUE",
             DoubleToString(engulf_ratio, 4),
             DoubleToString(ema20_slope, 5),
             BoolLabel(break_prev_low),
             BoolLabel(break_swing_low),
             DoubleToString(entry_candidate, _Digits),
             DoubleToString(sl_candidate, _Digits),
             DoubleToString(tp_candidate, _Digits),
             "","","","","","","");
   FileFlush(g_hCSV);
  }

//--- TRADE_CLOSE row — includes ExitReason and ProfitPoints
void CSVWriteClose(string direction, ulong ticket,
                   double entry_price, double exit_price,
                   double lot, double profit_money, string exit_reason)
  {
   if(g_hCSV == INVALID_HANDLE) return;
   double profit_points = (direction == "BUY")
                          ? (exit_price - entry_price) / SymbolInfoDouble(_Symbol, SYMBOL_POINT)
                          : (entry_price - exit_price) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   FileWrite(g_hCSV,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             "TRADE_CLOSE", direction,
             TrendLabel(g_last_trend),
             "","","","","","","","",
             DoubleToString(entry_price, _Digits),
             "","",
             (string)ticket,
             DoubleToString(lot, 2),
             "",
             DoubleToString(profit_money, 2),
             DoubleToString(profit_points, 1),
             exit_reason,
             "");
   FileFlush(g_hCSV);
  }

//+------------------------------------------------------------------+
//| Cancel pending order by ticket if it still exists               |
//|                                                                  |
//| OrderDelete returns false with retcode 4756 if the order was     |
//| already filled or expired — treat as non-fatal and clear ticket. |
//+------------------------------------------------------------------+
void CancelPending()
  {
   if(g_pending_ticket == 0) return;

   bool deleted = g_trade.OrderDelete(g_pending_ticket);
   bool sofConfirmedTerminal = false;    // order deleted or confirmed already-gone -- REJECTED
   bool sofAmbiguousAttempt  = false;    // OrderDelete failed, broker state unconfirmed -- stays MANAGED, correlation retained
   string sofNote = "";
   if(deleted)
     {
      if(InpShowLog)
         PrintFormat("Pending order cancelled | Ticket: %I64u", g_pending_ticket);
      sofConfirmedTerminal = true;
      sofNote = "PENDING_CANCELLED";
     }
   else
     {
      uint retcode = g_trade.ResultRetcode();
      if(retcode == 4756 || retcode == 10018)
        {
         if(InpShowLog)
            PrintFormat("Pending order %I64u already gone (retcode %d) — clearing ticket",
                        g_pending_ticket, retcode);
        }
      else
        {
         PrintFormat("ERROR: OrderDelete failed | Ticket: %I64u | Retcode: %d | %s",
                     g_pending_ticket, retcode, g_trade.ResultComment());
        }

      // SOF-only classification — deliberately independent of the original
      // if/else above (which only ever selected a Print() message and is
      // otherwise untouched). Only retcode 4756 is treated as confirmed
      // terminal here. 10018 (TRADE_RETCODE_MARKET_CLOSED) does NOT prove
      // the order is gone -- it only means this delete request failed
      // because the market was closed; the order may still be active at
      // the broker. 10018, and every other retcode, falls into the
      // ambiguous branch and is resolved later by
      // SOF_VerifyUnresolvedPending() instead of being assumed terminal
      // here -- even though the original code's own Print() groups 10018
      // together with 4756, SOF does not inherit that grouping.
      if(retcode == 4756)
        {
         sofConfirmedTerminal = true;
         sofNote = "PENDING_EXPIRED_OR_DISAPPEARED";
        }
      else
        {
         // Genuinely ambiguous outcome -- the order may still be live on the
         // broker side even though the existing code below unconditionally
         // clears LOCAL (strategy) tracking. SOF does NOT treat this as
         // terminal and does NOT clear its own correlation here -- see
         // SOF_VerifyUnresolvedPending(), which independently re-checks
         // this exact ticket on later ticks using SOF's own saved copy,
         // since g_pending_ticket will already be 0 by the next tick and
         // CheckTicketLifecycle() will therefore never look at it again.
         sofAmbiguousAttempt = true;
         sofNote = StringFormat("PENDING_CANCEL_ATTEMPT_FAILED retcode=%d", retcode);
        }
     }

   // SOF-only: pending-order terminal observation (no fill occurred).
   // Fires here only if a fill was never observed for this ticket --
   // CheckTicketLifecycle()'s fill branch clears g_sofPendingOrderTicket
   // before CancelPending() could ever reach it for the same ticket.
   // Terminal outcomes are SOF_STAGE_REJECTED (an order that never became
   // a position is not a successful lifecycle event) -- CLOSED is never
   // used here, only for a position that actually existed.
   if(g_sofStarted && g_sofPendingOrderTicket == g_pending_ticket)
     {
      if(sofConfirmedTerminal)
        {
         g_sof.Trades.RecordTrade(g_sofPendingTradeObsID, g_sofPendingEvalID, 0, (g_pending_direction<0?SOF_DIR_SELL:SOF_DIR_BUY), SOF_STAGE_REJECTED,
                                   0, 0, 0, 0, 0, 0, 0, 0, sofNote);
         g_sofPendingOrderTicket = 0;
         g_sofPendingTradeObsID  = 0;
         g_sofPendingEvalID      = 0;
        }
      else if(sofAmbiguousAttempt)
        {
         g_sof.Trades.RecordTrade(g_sofPendingTradeObsID, g_sofPendingEvalID, 0,
                                   (g_pending_direction<0?SOF_DIR_SELL:SOF_DIR_BUY), SOF_STAGE_MANAGED,
                                   0, 0, 0, 0, 0, 0, 0, 0, sofNote);
         // Correlation deliberately retained -- g_sofPendingOrderTicket/
         // TradeObsID/EvalID are NOT cleared here. SOF_VerifyUnresolvedPending()
         // will resolve this ticket on a later tick.
        }
     }

   g_pending_ticket = 0;
   g_order_price    = 0.0;
   g_stop_loss      = 0.0;
   g_risk_points    = 0;
   g_calc_lot       = 0.0;
   g_risk_money     = 0.0;
   g_take_profit    = 0.0;
  }


//==========================================================================
// [LD1 PARITY] Direction-neutral helpers
//==========================================================================
ENUM_SOF_DIRECTION LD1_SOFDirectionFromPositionType(const long posType)
  {
   return (posType==POSITION_TYPE_SELL ? SOF_DIR_SELL : SOF_DIR_BUY);
  }

ENUM_SOF_DIRECTION LD1_SOFDirectionFromPositionId(const long positionId)
  {
   if(HistorySelectByPosition(positionId))
     {
      int totalDeals=HistoryDealsTotal();
      for(int i=0;i<totalDeals;i++)
        {
         ulong d=HistoryDealGetTicket(i);
         if(d==0) continue;
         if((long)HistoryDealGetInteger(d,DEAL_POSITION_ID)!=positionId) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
         ENUM_DEAL_TYPE t=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
         return (t==DEAL_TYPE_SELL ? SOF_DIR_SELL : SOF_DIR_BUY);
        }
     }
   return SOF_DIR_BUY;
  }

bool LD1_PositionStillOpenByIdentifier(const long positionId)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if((long)PositionGetInteger(POSITION_IDENTIFIER)==positionId) return true;
     }
   return false;
  }

int g_ld1ParityFile=INVALID_HANDLE;

void LD1ParityHeader()
  {
   if(g_ld1ParityFile==INVALID_HANDLE) return;
   FileWrite(g_ld1ParityFile,
      "Time","Event","PositionID","DealTicket","Direction","DealEntry",
      "DealType","Volume","Price","Profit","Note");
   FileFlush(g_ld1ParityFile);
  }

void LD1ParityLog(string ev,long posId,ulong deal,string note)
  {
   if(g_ld1ParityFile==INVALID_HANDLE) return;
   string dir="";
   string de="";
   string dt="";
   double vol=0,price=0,profit=0;
   if(deal!=0 && HistoryDealSelect(deal))
     {
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      ENUM_DEAL_TYPE  t=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      de=EnumToString(e); dt=EnumToString(t);
      if(e==DEAL_ENTRY_IN)
         dir=(t==DEAL_TYPE_SELL?"SELL":"BUY");
      else
         dir=(LD1_SOFDirectionFromPositionId(posId)==SOF_DIR_SELL?"SELL":"BUY");
      vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
      price=HistoryDealGetDouble(deal,DEAL_PRICE);
      profit=HistoryDealGetDouble(deal,DEAL_PROFIT)
            +HistoryDealGetDouble(deal,DEAL_SWAP)
            +HistoryDealGetDouble(deal,DEAL_COMMISSION)
            +HistoryDealGetDouble(deal,DEAL_FEE);
     }
   FileWrite(g_ld1ParityFile,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
             ev,(string)posId,(string)deal,dir,de,dt,
             DoubleToString(vol,2),DoubleToString(price,_Digits),
             DoubleToString(profit,2),note);
   FileFlush(g_ld1ParityFile);
  }

//+------------------------------------------------------------------+
//| Ticket lifecycle — call once per tick at top of OnTick           |
//|                                                                  |
//| Clears g_pending_ticket when the order has been filled or has    |
//| disappeared, so CancelPending() at pullback end never calls      |
//| OrderDelete on a ticket that is already a live position.         |
//+------------------------------------------------------------------+
void CheckTicketLifecycle()
  {
   if(g_pending_ticket == 0) return;

   //--- Still pending?
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
      if(OrderGetTicket(i) == g_pending_ticket) return;

   //--- Filled and now an active position?
   if(PositionSelectByTicket(g_pending_ticket))
     {
      if(InpShowLog)
         PrintFormat("Ticket %I64u filled — position open | clearing pending state",
                     g_pending_ticket);

      // [PRME EXTRACTION] Adopt the just-filled position into the shared
      // engine, right here -- the pending order has just been confirmed
      // to be an actual open position (PositionSelectByTicket() above
      // succeeded), not merely placed. This is the one and only PRME
      // adoption point in this file; nothing calls AdoptPosition() at
      // pending-order placement (see the BuyStop() call site, which has
      // no adoption call at all). The entry deal ticket is resolved
      // independently via PRME_FindEntryDealTicket() (mirroring SOF's
      // own SOF_GetEntryDealInfo() technique) since there is no
      // trade.ResultDeal() available for an asynchronously-filled
      // pending order. H4H1 has no strategy score concept -- pass 0,
      // matching every other migrated strategy without one.
      //
      // Duplicate-adoption protection: this branch only runs when
      // g_pending_ticket is nonzero AND PositionSelectByTicket() just
      // succeeded for it -- g_pending_ticket is unconditionally zeroed
      // at the end of this same branch (see below), so the next tick's
      // CheckTicketLifecycle() call returns immediately at its own
      // top-of-function `if(g_pending_ticket == 0) return;` guard and
      // never re-enters this branch for the same fill. AdoptPosition()
      // itself is also independently idempotent -- AddOrRefreshOpenPosition()
      // only creates a new registry entry (and only then logs OPEN_TRACK)
      // if the position wasn't already adopted; a second call for the
      // same position would just refresh, never duplicate.
      //
      // Missing-history protection: if PRME_FindEntryDealTicket() returns
      // 0 (history not yet available this exact tick -- a real, brief
      // timing window), AdoptPosition() is deliberately NOT called with a
      // dummy/zero deal ticket -- that would queue an unresolvable entry
      // into the engine's bounded pending-adoption retry (which exists for
      // a DIFFERENT failure mode: AdoptPosition() being called with a real
      // ticket that transiently fails to resolve, not for never having a
      // ticket to call it with at all). Instead, the position is simply
      // not adopted this tick; it is not lost, though -- see the WARNING
      // Print() below for exactly how it still gets picked up.
      ulong prmeEntryDeal = PRME_FindEntryDealTicket(PositionGetInteger(POSITION_IDENTIFIER));
      if(prmeEntryDeal != 0)
         g_prme.AdoptPosition(prmeEntryDeal, 0);
      else
         Print("[H4H1_BUY_1506272] WARNING: PRME_FindEntryDealTicket() could not resolve the entry deal for ticket ",
               g_pending_ticket, " -- position will still be picked up by the engine's own per-tick discovery scan ",
               "(DiscoverAndRefreshAllPositions, every ManageOpenPositions() pass), but with the -1 sentinel score ",
               "rather than 0, since AdoptPosition() was never reached. Inconsequential for this strategy specifically ",
               "(PRME does not interpret H4H1's score under PRME_P0_FIXED), but noted for completeness.");

      // SOF-only fill observation. Independent identifier recovery, per
      // Phase 0 §6: does not assume the position identifier equals the
      // pending order ticket (g_pending_ticket) -- reads the real
      // POSITION_IDENTIFIER from the position PositionSelectByTicket()
      // just selected above, and recovers the actual fill price/time
      // from the DEAL_ENTRY_IN deal rather than assuming the fill
      // occurred exactly at the requested BuyStop price.
      if(g_sofStarted && g_sofPendingOrderTicket == g_pending_ticket)
        {
         long sofPositionId = PositionGetInteger(POSITION_IDENTIFIER);
         double sofEntryPrice = g_order_price;   // fallback if history lookup fails
         datetime sofEntryTime = 0;
         SOF_GetEntryDealInfo(sofPositionId, sofEntryPrice, sofEntryTime);
         ENUM_SOF_DIRECTION ld1FillDir=LD1_SOFDirectionFromPositionType(PositionGetInteger(POSITION_TYPE));
         g_sof.Trades.RecordTrade(g_sofPendingTradeObsID, g_sofPendingEvalID, sofPositionId,
                                   ld1FillDir, SOF_STAGE_ENTRY_FILLED,
                                   sofEntryPrice, g_calc_lot, g_stop_loss, g_take_profit,
                                   0, 0, 0, 0,
                                   StringFormat("Ticket=%I64u PosId=%I64u", g_pending_ticket, (ulong)sofPositionId));
         SOF_MapInsertOrUpdate(sofPositionId, g_sofPendingTradeObsID);
         g_sofPendingOrderTicket = 0;
         g_sofPendingTradeObsID  = 0;
         g_sofPendingEvalID      = 0;
        }

      g_pending_ticket = 0;
      g_order_price    = 0.0;
      g_stop_loss      = 0.0;
      g_risk_points    = 0;
      g_calc_lot       = 0.0;
      g_risk_money     = 0.0;
      g_take_profit    = 0.0;
      g_pending_direction = 0;
      return;
     }

   //--- Gone (expired or manually deleted)
   if(InpShowLog)
      PrintFormat("Ticket %I64u no longer exists — clearing pending state",
                  g_pending_ticket);

   // SOF-only: terminal non-fill observation. Mutually exclusive with
   // CancelPending()'s own terminal recording -- whichever path runs
   // first for a given ticket clears g_sofPendingOrderTicket, so the
   // other becomes a no-op if it's ever reached for the same ticket.
   // Terminal outcome -- SOF_STAGE_REJECTED, not CLOSED, since no
   // position ever existed for this ticket.
   if(g_sofStarted && g_sofPendingOrderTicket == g_pending_ticket)
     {
      g_sof.Trades.RecordTrade(g_sofPendingTradeObsID, g_sofPendingEvalID, 0, SOF_DIR_BUY, SOF_STAGE_REJECTED,
                                0, 0, 0, 0, 0, 0, 0, 0, "PENDING_EXPIRED_OR_DISAPPEARED");
      g_sofPendingOrderTicket = 0;
      g_sofPendingTradeObsID  = 0;
      g_sofPendingEvalID      = 0;
     }

   g_pending_ticket = 0;
   g_order_price    = 0.0;
   g_stop_loss      = 0.0;
   g_risk_points    = 0;
   g_calc_lot       = 0.0;
   g_risk_money     = 0.0;
   g_take_profit    = 0.0;
   g_pending_direction = 0;
  }


//+------------------------------------------------------------------+
//| STANDARD: Gold symbol validation                                 |
//+------------------------------------------------------------------+
string StringToUpperCopy(string value)
  {
   StringToUpper(value);
   return value;
  }

bool IsGoldSymbol(const string symbol)
  {
   string s    = StringToUpperCopy(symbol);
   string desc = StringToUpperCopy(SymbolInfoString(symbol, SYMBOL_DESCRIPTION));
   string base = StringToUpperCopy(SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE));

   if(base == "XAU")              return true;
   if(StringFind(s, "XAU") >= 0)  return true;
   if(StringFind(s, "GOLD") >= 0) return true;
   if(StringFind(desc, "XAU") >= 0)  return true;
   if(StringFind(desc, "GOLD") >= 0) return true;

   return false;
  }

//+------------------------------------------------------------------+
//| Research Profile capacity control                                |
//| A slot is reserved by either an open position or a live pending  |
//| order for this symbol and magic number. This prevents a fourth   |
//| fill while three independent PRME ticket states are active.      |
//+------------------------------------------------------------------+
int CountResearchOpenPositions()
  {
   int count=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      count++;
     }
   return count;
  }

int CountResearchPendingOrders()
  {
   int count=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_SELL_LIMIT ||
         type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP ||
         type==ORDER_TYPE_BUY_STOP_LIMIT || type==ORDER_TYPE_SELL_STOP_LIMIT)
         count++;
     }
   return count;
  }

int CountResearchReservedSlots()
  {
   return CountResearchOpenPositions()+CountResearchPendingOrders();
  }

//+------------------------------------------------------------------+
//| STANDARD: Gold spread in price dollars                           |
//+------------------------------------------------------------------+
double GetGoldSpreadDollars()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return 999999.0;
   return NormalizeDouble(ask - bid, 3);
  }

bool IsSpreadOK()
  {
   double spread = GetGoldSpreadDollars();
   if(spread > InpMaxSpreadDollars)
     {
      if(InpShowLog)
         PrintFormat("SKIP — spread $%.3f > max $%.2f", spread, InpMaxSpreadDollars);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Risk-based lot calculation                                       |
//|                                                                  |
//| RawLot = (Balance * Risk%) / (SL_distance / TickSize * TickValue)|
//| Floors to broker volume step. Returns 0.0 on any invalid input.  |
//+------------------------------------------------------------------+
double CalcLotSize(double entry, double sl, double &out_risk_money)
  {
   out_risk_money = 0.0;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double vol_min    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tick_size <= 0.0 || tick_value <= 0.0)
     { Print("CalcLotSize ERROR: invalid tick_size or tick_value"); return 0.0; }

   double sl_dist = MathAbs(entry - sl);
   if(sl_dist <= 0.0)
     { Print("CalcLotSize ERROR: SL distance is zero"); return 0.0; }

   double risk_money   = balance * InpRiskPercent / 100.0;
   double loss_per_lot = sl_dist / tick_size * tick_value;
   if(loss_per_lot <= 0.0)
     { Print("CalcLotSize ERROR: loss_per_lot is zero"); return 0.0; }

   double raw_lot = risk_money / loss_per_lot;
   if(raw_lot < vol_min)
     {
      PrintFormat("RISK LOT BELOW MINIMUM — Trade skipped | RawLot: %.4f | MinLot: %.2f",
                  raw_lot, vol_min);
      return 0.0;
     }

   double norm_lot = NormalizeDouble(MathFloor(raw_lot / vol_step) * vol_step, 2);
   norm_lot = MathMin(vol_max, norm_lot);

   out_risk_money = risk_money;

   if(InpShowLog)
      PrintFormat("CalcLotSize | Balance: %.2f | Risk: %.1f%% | RiskMoney: %.2f | SL_Dist: %s | LossPerLot: %.2f | RawLot: %.4f | NormLot: %.2f",
                  balance, InpRiskPercent, risk_money,
                  DoubleToString(sl_dist, _Digits),
                  loss_per_lot, raw_lot, norm_lot);
   return norm_lot;
  }

//+------------------------------------------------------------------+
//| Validate and place BUY STOP or SELL STOP with SL and TP         |
//|                                                                  |
//| direction:  1 = BUY STOP  | -1 = SELL STOP                      |
//| BUY STOP  : entry > Ask + stops_level | SL below entry           |
//| SELL STOP : entry < Bid - stops_level | SL above entry           |
//| TP = entry ± (entry - SL) * InpRiskReward                        |
//+------------------------------------------------------------------+
void PlacePending(int direction, double entry_price, double sl_price)
  {
   g_pending_direction = direction; // [LD1] preserve requested side
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool sofActive = (g_sofStarted && g_sofRecordThisCall && direction == 1 && !g_v10Placing);

   const int reservedSlots=CountResearchReservedSlots();
   if(InpMaxPositionSlots > 0 && reservedSlots >= InpMaxPositionSlots)
     {
      PrintFormat("[RESEARCH_PROFILE] Entry blocked: reserved slots %d/%d | Open=%d Pending=%d",
                  reservedSlots,InpMaxPositionSlots,
                  CountResearchOpenPositions(),CountResearchPendingOrders());
      if(sofActive)
        {
         SOF_SkipRemainingGatesFrom(10);
         g_sof.Gates.EndEvaluation();
        }
      return;
     }

   //--- STANDARD spread filter: use Gold price distance, not SYMBOL_SPREAD
   if(!IsSpreadOK())
     {
      if(sofActive)
        {
         g_sof.Gates.RecordGate("Spread", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, InpMaxSpreadDollars, "");
         SOF_SkipRemainingGatesFrom(11);
         g_sof.Gates.EndEvaluation();
        }
      return;
     }
   if(sofActive)
      g_sof.Gates.RecordGate("Spread", SOF_DIR_BUY, SOF_RESULT_PASS, 0, InpMaxSpreadDollars, "");

   long   stops_pts  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stops_dist = stops_pts * point;

   //--- Stops level validation
   if(direction == 1 && entry_price <= ask + stops_dist)
     {
      PrintFormat("BUY STOP rejected — entry too close to Ask | Entry: %s | Ask: %s | MinDist: %s",
                  DoubleToString(entry_price, _Digits),
                  DoubleToString(ask,         _Digits),
                  DoubleToString(stops_dist,  _Digits));
      if(sofActive)
        {
         g_sof.Gates.RecordGate("StopsLevelValid", SOF_DIR_BUY, SOF_RESULT_FAIL, entry_price, ask + stops_dist, "");
         SOF_SkipRemainingGatesFrom(12);
         g_sof.Gates.EndEvaluation();
        }
      return;
     }
   if(direction == -1 && entry_price >= bid - stops_dist)
     {
      g_sell_rej_stops++;
      PrintFormat("SELL STOP rejected — entry too close to Bid | Entry: %s | Bid: %s | MinDist: %s",
                  DoubleToString(entry_price, _Digits),
                  DoubleToString(bid,         _Digits),
                  DoubleToString(stops_dist,  _Digits));
      return;
     }
   if(sofActive)
      g_sof.Gates.RecordGate("StopsLevelValid", SOF_DIR_BUY, SOF_RESULT_PASS, entry_price, ask + stops_dist, "");

   //--- Normalize prices
   double norm_entry = NormalizeDouble(entry_price, _Digits);
   double norm_sl    = NormalizeDouble(sl_price,    _Digits);

   //--- Calculate TP: entry ± risk_distance * RR
   double risk_dist  = MathAbs(norm_entry - norm_sl);
   double norm_tp;
   if(g_v10Placing && InpBRC_NoFixedTP && StringFind(g_v10OrderComment,"V10_B_")==0)
      norm_tp = 0.0;
   else if(direction == 1)
      norm_tp = NormalizeDouble(norm_entry + risk_dist * InpRiskReward, _Digits);
   else
      norm_tp = NormalizeDouble(norm_entry - risk_dist * InpRiskReward, _Digits);

   //--- Lot size
   double risk_money = 0.0;
   double lot = InpUseRiskLot
                ? CalcLotSize(norm_entry, norm_sl, risk_money)
                : InpFixedLot;
   if(lot <= 0.0)
     {
      if(sofActive)
        {
         g_sof.Gates.RecordGate("LotValid", SOF_DIR_BUY, SOF_RESULT_FAIL, lot, 0, "");
         SOF_SkipRemainingGatesFrom(13);
         g_sof.Gates.EndEvaluation();
        }
      return;
     }
   if(sofActive)
      g_sof.Gates.RecordGate("LotValid", SOF_DIR_BUY, SOF_RESULT_PASS, lot, 0, "");

   //--- Risk points
   long risk_pts = (long)MathRound(risk_dist / point);

   ulong sofTradeObsID = 0;
   if(sofActive)
     {
      sofTradeObsID = g_sof.Trades.TradeBegin(g_sofCurrentEvalID, SOF_DIR_BUY);  // records SIGNAL
      g_sof.Trades.RecordTrade(sofTradeObsID, g_sofCurrentEvalID, 0, SOF_DIR_BUY, SOF_STAGE_ENTRY_SENT,
                                norm_entry, lot, norm_sl, norm_tp, 0, 0, 0, 0, "H4H1 BUY STOP request");
     }

   //--- Place order
   bool ok;
   if(direction == 1)
      ok = g_trade.BuyStop(lot, norm_entry, _Symbol, norm_sl, norm_tp,
                           ORDER_TIME_GTC, 0, g_v10Placing ? g_v10OrderComment : "H4H1 BUY");
   else
      ok = g_trade.SellStop(lot, norm_entry, _Symbol, norm_sl, norm_tp,
                            ORDER_TIME_GTC, 0, g_v10Placing ? g_v10OrderComment : "H4H1 SELL");

   if(ok)
     {
      g_pending_ticket = g_trade.ResultOrder();
      g_order_price    = norm_entry;
      g_stop_loss      = norm_sl;
      g_take_profit    = norm_tp;
      g_risk_points    = risk_pts;
      g_calc_lot       = lot;
      g_risk_money     = risk_money;
      g_orders_placed++;
      if(direction == -1) g_sell_orders_placed++;

      PrintFormat("Pending order placed | %s STOP | Ticket: %I64u",
                  (direction == 1) ? "BUY" : "SELL", g_pending_ticket);
      PrintFormat("  Entry      : %s", DoubleToString(g_order_price,  _Digits));
      PrintFormat("  Stop Loss  : %s", DoubleToString(g_stop_loss,    _Digits));
      PrintFormat("  Take Profit: %s", DoubleToString(g_take_profit,  _Digits));
      PrintFormat("  RR         : %.1f", InpRiskReward);
      PrintFormat("  Lot        : %.2f", g_calc_lot);
      PrintFormat("  Risk Money : %.2f", g_risk_money);
      PrintFormat("  Risk Points: %d",   g_risk_points);

      // SOF: OrderExecution PASS -- "pending order accepted", NOT a fill.
      // Evaluation closes here (all 14 gates cleared); the fill itself is
      // only ever confirmed later, from CheckTicketLifecycle()'s own
      // PositionSelectByTicket() check -- never inferred from BuyStop()
      // returning true. Pending-order tracking (g_sofPendingOrderTicket
      // etc.) is separate from, and does not touch, g_pending_ticket.
      if(sofActive)
        {
         uint retcode = g_trade.ResultRetcode();
         g_sof.Gates.RecordGate("OrderExecution", SOF_DIR_BUY, SOF_RESULT_PASS,
                                 (double)retcode, 0, "", g_trade.ResultRetcodeDescription());
         g_sof.Gates.EndEvaluation();   // all 14 gates cleared -- Evaluation PASSED
         g_sof.Trades.RecordTrade(sofTradeObsID, g_sofCurrentEvalID, 0, SOF_DIR_BUY, SOF_STAGE_MANAGED,
                                   norm_entry, lot, norm_sl, norm_tp, 0, 0, 0, 0,
                                   StringFormat("PENDING_ACCEPTED Ticket=%I64u", g_pending_ticket));
         g_sofPendingOrderTicket = g_pending_ticket;
         g_sofPendingTradeObsID  = sofTradeObsID;
         g_sofPendingEvalID      = g_sofCurrentEvalID;
        }
     }
   else
     {
      PrintFormat("ERROR: Pending order failed | Retcode: %d | %s",
                  g_trade.ResultRetcode(), g_trade.ResultComment());
      if(sofActive)
        {
         uint retcode = g_trade.ResultRetcode();
         g_sof.Gates.RecordGate("OrderExecution", SOF_DIR_BUY, SOF_RESULT_FAIL,
                                 (double)retcode, 0,
                                 StringFormat("Retcode=%d(%s)", (int)retcode, g_trade.ResultComment()), "");
         g_sof.Gates.EndEvaluation();   // OrderExecution FAIL -- final gate, no downstream gates to skip
         g_sof.Trades.RecordTrade(sofTradeObsID, g_sofCurrentEvalID, 0, SOF_DIR_BUY, SOF_STAGE_REJECTED,
                                   norm_entry, lot, norm_sl, norm_tp, 0, 0, 0, 0,
                                   StringFormat("ORDER_REJECTED Retcode=%d(%s)", (int)retcode, g_trade.ResultComment()));
        }
     }
  }

//+------------------------------------------------------------------+
//| Build and push Comment() display                                 |
//+------------------------------------------------------------------+
void UpdateComment(int trend, bool pullback, bool setup_triggered,
                   int engulfing, string signal)
  {
   string trend_text;
   if(trend ==  1) trend_text = "BULLISH  [+]";
   else if(trend == -1) trend_text = "BEARISH  [-]";
   else                 trend_text = "NEUTRAL  [=]";

   string pb_text    = pullback        ? "TRUE"  : "FALSE";
   string lock_text  = setup_triggered ? "TRUE"  : "FALSE";

   string locked_text;
   if(g_locked_engulfing ==  1) locked_text = "BULLISH  [+]";
   else if(g_locked_engulfing == -1) locked_text = "BEARISH  [-]";
   else                              locked_text = "NONE";

   string sig_time_text = (g_signal_time > 0)
                          ? TimeToString(g_signal_time, TIME_DATE|TIME_MINUTES) : "---";
   string order_text    = (g_order_price  > 0.0)
                          ? DoubleToString(g_order_price,  _Digits) : "---";
   string sl_text       = (g_stop_loss    > 0.0)
                          ? DoubleToString(g_stop_loss,    _Digits) : "---";
   string tp_text       = (g_take_profit  > 0.0)
                          ? DoubleToString(g_take_profit,  _Digits) : "---";
   string risk_text     = (g_risk_points  > 0)
                          ? IntegerToString(g_risk_points) + " pts" : "---";
   string lot_mode_text = InpUseRiskLot ? "RISK-BASED" : "FIXED";
   string risk_pct_text = InpUseRiskLot
                          ? DoubleToString(InpRiskPercent, 1) + " %" : "---";
   string risk_usd_text = (g_risk_money > 0.0)
                          ? DoubleToString(g_risk_money, 2) : "---";
   string calc_lot_text = (g_calc_lot   > 0.0)
                          ? DoubleToString(g_calc_lot, 2)   : "---";
   string ticket_text   = (g_pending_ticket > 0)
                          ? IntegerToString((long)g_pending_ticket) : "NONE";

   string dir_text  = (InpTradeDirection == 1) ? "BUY ONLY" :
                      (InpTradeDirection == 2) ? "SELL ONLY" : "BOTH";

   double win_rate = (g_stat_trades > 0)
                     ? (double)g_stat_wins / g_stat_trades * 100.0 : 0.0;

   string pb_bars_text = IntegerToString(g_pullback_bar_count)
                         + " / " + IntegerToString(InpMinPullbackBars)
                         + (g_pullback_bar_count >= InpMinPullbackBars
                            ? "  [GATE OPEN]" : "  [waiting]");

   string msg = "====== H4H1 Trend EA v4.3 ======"
              + "\n  Direction       : " + dir_text
              + "\n  H4 Trend        : " + trend_text
              + "\n  Pullback        : " + pb_text
              + "\n  PB Bars         : " + pb_bars_text
              + "\n  Signal          : " + signal
              + "\n  Setup Lock      : " + lock_text
              + "\n  Locked Engulfing: " + locked_text
              + "\n  ---"
              + "\n  Entry Price     : " + order_text
              + "\n  Stop Loss       : " + sl_text
              + "\n  Take Profit     : " + tp_text
              + "\n  Risk Points     : " + risk_text
              + "\n  RR              : " + DoubleToString(InpRiskReward, 1)
              + "\n  ---"
              + "\n  Lot Mode        : " + lot_mode_text
              + "\n  Risk Percent    : " + risk_pct_text
              + "\n  Risk Money      : " + risk_usd_text
              + "\n  Calculated Lot  : " + calc_lot_text
              + "\n  Pending Ticket  : " + ticket_text
              + "\n  ---  Session Stats  ---"
              + "\n  Pullbacks Found : " + IntegerToString(g_cnt_pullbacks_found)
              + "\n  Gate Passed     : " + IntegerToString(g_cnt_duration_gate_pass)
              + "\n  BUY Signals     : " + IntegerToString(g_buy_signals)
              + "\n  SELL Signals    : " + IntegerToString(g_sell_signals)
              + "\n  Orders Placed   : " + IntegerToString(g_orders_placed)
              + "\n  ---  Trade Stats  ---"
              + "\n  Trades          : " + IntegerToString(g_stat_trades)
              + "\n  Wins            : " + IntegerToString(g_stat_wins)
              + "\n  Losses          : " + IntegerToString(g_stat_losses)
              + "\n  Win Rate        : " + DoubleToString(win_rate, 2) + " %";

   Comment(msg);
  }

//+------------------------------------------------------------------+
//| SOF INTEGRATION HELPERS — additive, read-only observation only    |
//+------------------------------------------------------------------+

void SOF_SkipRemainingGatesFrom(const int fromIndexInclusive)
  {
   int n = ArraySize(g_sofGateOrder);
   for(int i = fromIndexInclusive; i < n; i++)
      g_sof.Gates.RecordGate(g_sofGateOrder[i], SOF_DIR_BUY, SOF_RESULT_SKIPPED, 0, 0, "");
  }

void SOF_EndSession()
  {
   if(!g_sofStarted)
      return;
   g_sof.End();
   g_sofStarted = false;
  }

void SOF_MapReset()
  {
   for(int i = 0; i < SOF_POS_MAP_SIZE; i++)
     {
      g_sofPosMap[i].positionId         = 0;
      g_sofPosMap[i].tradeObservationId = 0;
      g_sofPosMap[i].openTime           = 0;
      g_sofPosMap[i].active             = false;
     }
  }

int SOF_MapFindSlot(const long positionId)
  {
   for(int i = 0; i < SOF_POS_MAP_SIZE; i++)
      if(g_sofPosMap[i].positionId == positionId && (g_sofPosMap[i].active || g_sofPosMap[i].openTime != 0))
         return(i);
   return(-1);
  }

void SOF_MapInsertOrUpdate(const long positionId, const ulong tradeObservationId)
  {
   int existing = SOF_MapFindSlot(positionId);
   if(existing >= 0)
     {
      g_sofPosMap[existing].tradeObservationId = tradeObservationId;
      g_sofPosMap[existing].active             = true;
      return;
     }

   int      bestSlot = -1;
   datetime bestSlotTime = 0;
   for(int i = 0; i < SOF_POS_MAP_SIZE; i++)
     {
      if(g_sofPosMap[i].active)
         continue;
      if(g_sofPosMap[i].openTime == 0)
        { bestSlot = i; break; }
      if(bestSlot < 0 || g_sofPosMap[i].openTime < bestSlotTime)
        { bestSlot = i; bestSlotTime = g_sofPosMap[i].openTime; }
     }

   if(bestSlot < 0)
     {
      g_sof.Session.GetErrorChannel().Report(SOF_ERR_BUFFER_OVERFLOW,
                                              "SOF_MapInsertOrUpdate",
                                              StringFormat("Position correlation map full (%d slots), positionId=%d dropped",
                                                            SOF_POS_MAP_SIZE, (int)positionId));
      return;
     }

   g_sofPosMap[bestSlot].positionId         = positionId;
   g_sofPosMap[bestSlot].tradeObservationId = tradeObservationId;
   g_sofPosMap[bestSlot].openTime           = TimeCurrent();
   g_sofPosMap[bestSlot].active             = true;
  }

void SOF_MapMarkInactive(const long positionId)
  {
   int slot = SOF_MapFindSlot(positionId);
   if(slot >= 0)
      g_sofPosMap[slot].active = false;
  }

bool SOF_SelectPositionByIdentifier(const long positionId)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetInteger(POSITION_IDENTIFIER) == positionId) return true;
     }
   return false;
  }

double SOF_AggregatePositionPnL(const long positionId)
  {
   double total = 0.0;
   if(!HistorySelectByPosition(positionId)) return total;
   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
     {
      ulong dTicket = HistoryDealGetTicket(i);
      if(dTicket == 0) continue;
      if((long)HistoryDealGetInteger(dTicket, DEAL_POSITION_ID) != positionId) continue;
      long entryType = HistoryDealGetInteger(dTicket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) continue;
      total += HistoryDealGetDouble(dTicket, DEAL_PROFIT);
      total += HistoryDealGetDouble(dTicket, DEAL_SWAP);
      total += HistoryDealGetDouble(dTicket, DEAL_COMMISSION);
      total += HistoryDealGetDouble(dTicket, DEAL_FEE);
     }
   return total;
  }

//--- Recovers the actual entry-fill price/time from history (DEAL_ENTRY_IN),
//    rather than assuming the fill equals the requested BuyStop price.
bool SOF_GetEntryDealInfo(const long positionId, double &entryPrice, datetime &entryTime)
  {
   entryPrice = 0.0; entryTime = 0;
   if(!HistorySelectByPosition(positionId)) return false;
   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
     {
      ulong dTicket = HistoryDealGetTicket(i);
      if(dTicket == 0) continue;
      if((long)HistoryDealGetInteger(dTicket, DEAL_POSITION_ID) != positionId) continue;
      if(HistoryDealGetInteger(dTicket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      entryPrice = HistoryDealGetDouble(dTicket, DEAL_PRICE);
      entryTime  = (datetime)HistoryDealGetInteger(dTicket, DEAL_TIME);
      return true;
     }
   return false;
  }

// [PRME EXTRACTION] Mirrors SOF_GetEntryDealInfo()'s exact scan above,
// but returns the entry deal's own ticket rather than its price/time --
// AdoptPosition() needs the deal ticket itself (it resolves
// DEAL_POSITION_ID from it internally). Needed here specifically
// because H4H1 trades via a pending BuyStop that fills asynchronously
// -- there is no trade.ResultDeal() available at the point the fill is
// detected (unlike a direct market order send), so the entry deal has
// to be found the same way SOF already does it, independently. Same
// helper as the completed H4H1 SELL 1506271 migration, ported verbatim
// (direction-agnostic -- operates purely on positionId/deal history).
ulong PRME_FindEntryDealTicket(const long positionId)
  {
   if(!HistorySelectByPosition(positionId)) return 0;
   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
     {
      ulong dTicket = HistoryDealGetTicket(i);
      if(dTicket == 0) continue;
      if((long)HistoryDealGetInteger(dTicket, DEAL_POSITION_ID) != positionId) continue;
      if(HistoryDealGetInteger(dTicket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      return dTicket;
     }
   return 0;
  }

//--- SOF-only, independent of g_pending_ticket entirely. Resolves a ticket
//    left in an ambiguous state by CancelPending()'s OrderDelete-failed
//    branch. That branch deliberately does NOT clear g_sofPendingOrderTicket
//    (Fix 2), but the EA's own g_pending_ticket IS cleared unconditionally
//    (unchanged, per "do not affect parity") -- meaning CheckTicketLifecycle()
//    will never look at this ticket again on any later tick. This function
//    is therefore the only path that can ever resolve it. Called once per
//    tick, guarded on g_sofPendingOrderTicket != 0, so it is a no-op in the
//    overwhelming majority of ticks and never interferes with the normal
//    fill/gone resolution CheckTicketLifecycle() already performs via
//    g_pending_ticket (those two trackers are cleared together in the
//    normal path, so there is nothing left here for this function to see).
void SOF_VerifyUnresolvedPending()
  {
   if(!g_sofStarted || g_sofPendingOrderTicket == 0) return;

   //--- Order still exists? Retain correlation, do nothing.
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
      if(OrderGetTicket(i) == g_sofPendingOrderTicket) return;

   //--- Gone from the orders list. Filled?
   if(PositionSelectByTicket(g_sofPendingOrderTicket))
     {
      long sofPositionId = PositionGetInteger(POSITION_IDENTIFIER);
      double sofEntryPrice = 0.0;
      datetime sofEntryTime = 0;
      SOF_GetEntryDealInfo(sofPositionId, sofEntryPrice, sofEntryTime);
      g_sof.Trades.RecordTrade(g_sofPendingTradeObsID, g_sofPendingEvalID, sofPositionId,
                                SOF_DIR_BUY, SOF_STAGE_ENTRY_FILLED,
                                sofEntryPrice, 0, 0, 0, 0, 0, 0, 0,
                                StringFormat("Ticket=%I64u PosId=%I64u (resolved via SOF_VerifyUnresolvedPending)",
                                              g_sofPendingOrderTicket, (ulong)sofPositionId));
      SOF_MapInsertOrUpdate(sofPositionId, g_sofPendingTradeObsID);
      g_sofPendingOrderTicket = 0;
      g_sofPendingTradeObsID  = 0;
      g_sofPendingEvalID      = 0;
      return;
     }

   //--- Gone and no position -- confirmed expired/disappeared unfilled.
   g_sof.Trades.RecordTrade(g_sofPendingTradeObsID, g_sofPendingEvalID, 0, SOF_DIR_BUY, SOF_STAGE_REJECTED,
                             0, 0, 0, 0, 0, 0, 0, 0,
                             "PENDING_EXPIRED_OR_DISAPPEARED (resolved via SOF_VerifyUnresolvedPending)");
   g_sofPendingOrderTicket = 0;
   g_sofPendingTradeObsID  = 0;
   g_sofPendingEvalID      = 0;
  }

double SOF_LastExitPriceForPosition(const long positionId)
  {
   if(!HistorySelect(0,TimeCurrent())) return 0.0;
   double px=0.0;
   datetime latest=0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong d=HistoryDealGetTicket(i);
      if(d==0 || HistoryDealGetInteger(d,DEAL_POSITION_ID)!=positionId) continue;
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(e!=DEAL_ENTRY_OUT && e!=DEAL_ENTRY_OUT_BY) continue;
      datetime t=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      if(t>=latest){latest=t;px=HistoryDealGetDouble(d,DEAL_PRICE);}
     }
   return px;
  }

void SOF_MapPruneStale()
  {
   // RC2: OnTradeTransaction may fire before the terminal position disappears
   // from PositionsTotal(). Reconcile/deallocate on the next housekeeping pass.
   for(int i=0;i<SOF_POS_MAP_SIZE;i++)
     {
      if(g_sofPosMap[i].openTime==0) continue;
      bool positionGone=!SOF_SelectPositionByIdentifier(g_sofPosMap[i].positionId);
      if(!positionGone) continue;

      if(g_sofPosMap[i].active && g_sofStarted && g_sofPosMap[i].tradeObservationId>0)
        {
         long posId=g_sofPosMap[i].positionId;
         double pnl=SOF_AggregatePositionPnL(posId);
         double exitPx=SOF_LastExitPriceForPosition(posId);
         ENUM_SOF_DIRECTION dir=LD1_SOFDirectionFromPositionId(posId);
         g_sof.Trades.RecordTrade(g_sofPosMap[i].tradeObservationId,0,posId,dir,SOF_STAGE_CLOSED,
                                  exitPx,0,0,0,0,pnl,0,0,
                                  "Deferred CLOSED reconciliation: position absent after trade transaction");
        }

      g_sofPosMap[i].positionId=0;
      g_sofPosMap[i].tradeObservationId=0;
      g_sofPosMap[i].openTime=0;
      g_sofPosMap[i].active=false;
     }
  }

//+------------------------------------------------------------------+
//| [PRME EXTRACTION] CH4H1BuyPRMEEvents -- this EA's own               |
//| CPRMEEventSink implementation. Converts shared PRME events into the  |
//| existing H4H1 SOF trade events, same SOF_MapFindSlot lookup and       |
//| SOF_STAGE_* constants as every other migrated strategy's sink.         |
//| PRME_Core.mqh itself never includes SOF_Framework.mqh and never         |
//| references g_sof anywhere -- this sink is the only place the two         |
//| connect, and only in this EA file, not in the shared engine.               |
//|                                                                               |
//| Under PRME V3's PRME_P0_FIXED policy, OnPartialClosed/OnPartialSkipped/       |
//| OnBEMoved/OnTrailUpdated will never actually fire -- implemented fully         |
//| anyway, matching the established pattern.                                       |
//|                                                                                    |
//| OnPositionClosed is intentionally a NO-OP: H4H1 BUY already has its own            |
//| independent, event-driven SOF close observation in OnTradeTransaction               |
//| (untouched by this migration, and its own comment there confirms the same            |
//| reasoning: "This EA has no partial-close mechanism (fixed SL/TP, no PRME)").           |
//| Letting this sink ALSO record SOF_STAGE_CLOSED would double-record every close.          |
//+------------------------------------------------------------------+
class CH4H1BuyPRMEEvents : public CPRMEEventSink
  {
public:
   virtual void OnPartialClosed(const PRME_PositionState &pos, const double closedVolume,
                                 const double verifiedRemainingVolume, const bool verified) override
     {
      if(!g_sofStarted) return;
      long sofActualPositionId = (long)pos.positionId;
      ENUM_SOF_DIRECTION ld1Dir=LD1_SOFDirectionFromPositionId(sofActualPositionId);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int sofSlot = SOF_MapFindSlot(sofActualPositionId);
      if(sofSlot < 0) return;
      double curSL = 0.0;
      if(PositionSelectByTicket(pos.ticket)) curSL = PositionGetDouble(POSITION_SL);
      if(verified)
         g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId, 0, sofActualPositionId,
                                   ld1Dir, SOF_STAGE_PARTIAL_CLOSE, bid, closedVolume, curSL, 0,
                                   0, PositionGetDouble(POSITION_PROFIT), pos.mfePoints, pos.maePoints,
                                   StringFormat("PARTIAL_CLOSED VerifiedRemainingVol=%.2f", verifiedRemainingVolume));
      else
         g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId, 0, sofActualPositionId,
                                   ld1Dir, SOF_STAGE_MANAGED, bid, closedVolume, curSL, 0,
                                   0, PositionGetDouble(POSITION_PROFIT), pos.mfePoints, pos.maePoints,
                                   StringFormat("PARTIAL_NOT_VERIFIED VerifiedVolume=%.2f", verifiedRemainingVolume));
     }

   virtual void OnPartialSkipped(const PRME_PositionState &pos, const string &reason) override
     {
      if(!g_sofStarted) return;
      long sofActualPositionId = (long)pos.positionId;
      ENUM_SOF_DIRECTION ld1Dir=LD1_SOFDirectionFromPositionId(sofActualPositionId);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int sofSlot = SOF_MapFindSlot(sofActualPositionId);
      if(sofSlot < 0) return;
      double curSL = 0.0;
      if(PositionSelectByTicket(pos.ticket)) curSL = PositionGetDouble(POSITION_SL);
      g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId, 0, sofActualPositionId,
                                ld1Dir, SOF_STAGE_MANAGED, bid, 0, curSL, 0,
                                0, PositionGetDouble(POSITION_PROFIT), pos.mfePoints, pos.maePoints,
                                "PARTIAL_SKIPPED -- no partial close occurred, " + reason);
     }

   virtual void OnBEMoved(const PRME_PositionState &pos, const double requestedSL,
                           const double verifiedSL, const bool verified) override
     {
      if(!g_sofStarted) return;
      long sofActualPositionId = (long)pos.positionId;
      ENUM_SOF_DIRECTION ld1Dir=LD1_SOFDirectionFromPositionId(sofActualPositionId);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int sofSlot = SOF_MapFindSlot(sofActualPositionId);
      if(sofSlot < 0) return;
      double volume = pos.lots;
      if(verified)
         g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId, 0, sofActualPositionId,
                                   ld1Dir, SOF_STAGE_BE_MOVED, bid, volume, verifiedSL, 0,
                                   0, PositionGetDouble(POSITION_PROFIT), pos.mfePoints, pos.maePoints,
                                   "BE_TRIGGERED");
      else
         g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId, 0, sofActualPositionId,
                                   ld1Dir, SOF_STAGE_MANAGED, bid, volume, verifiedSL, 0,
                                   0, PositionGetDouble(POSITION_PROFIT), pos.mfePoints, pos.maePoints,
                                   StringFormat("BE_ATTEMPT_FAILED RequestedSL=%.5f VerifiedSL=%.5f", requestedSL, verifiedSL));
     }

   virtual void OnTrailUpdated(const PRME_PositionState &pos, const double requestedSL,
                                const double verifiedSL, const bool verified) override
     {
      if(!g_sofStarted) return;
      long sofActualPositionId = (long)pos.positionId;
      ENUM_SOF_DIRECTION ld1Dir=LD1_SOFDirectionFromPositionId(sofActualPositionId);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int sofSlot = SOF_MapFindSlot(sofActualPositionId);
      if(sofSlot < 0) return;
      double volume = pos.lots;
      if(verified)
         g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId, 0, sofActualPositionId,
                                   ld1Dir, SOF_STAGE_TRAIL_UPDATE, bid, volume, verifiedSL, 0,
                                   0, PositionGetDouble(POSITION_PROFIT), pos.mfePoints, pos.maePoints,
                                   StringFormat("TRAIL_MOVED RequestedSL=%.5f", requestedSL));
      else
         g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId, 0, sofActualPositionId,
                                   ld1Dir, SOF_STAGE_MANAGED, bid, volume, verifiedSL, 0,
                                   0, PositionGetDouble(POSITION_PROFIT), pos.mfePoints, pos.maePoints,
                                   StringFormat("TRAIL_ATTEMPT_FAILED RequestedSL=%.5f VerifiedSL=%.5f", requestedSL, verifiedSL));
     }

   virtual void OnPositionClosed(const PRME_PositionState &pos, const double exitPrice,
                                  const double aggregatedProfit, const string &exitReason,
                                  const bool historyConfirmed) override
     {
      // Intentionally empty -- see class header comment above. H4H1 BUY's
      // own OnTradeTransaction handles SOF close observation independently.
     }
  };

CH4H1BuyPRMEEvents g_prmeEvents;

//+------------------------------------------------------------------+
//| SOF V2 runtime helpers                                           |
//+------------------------------------------------------------------+
bool ResolveSOFV2RunPaths()
  {
   g_pathLiveCSV       = g_sessionMgr.GetRunFilePath("LiveTest.csv");
   g_pathCandidateCSV  = g_sessionMgr.GetRunFilePath("UEE_Candidates.csv");
   g_pathUEEDecisions  = g_sessionMgr.GetRunFilePath("UEE_Decisions.csv");
   g_pathUEEState      = g_sessionMgr.GetRunFilePath("UEE_State.csv");
   g_pathPRMELifecycle = g_sessionMgr.GetRunFilePath("PRME_Lifecycle.csv");
   g_pathPRMEState     = g_sessionMgr.GetRunFilePath("PRME_State.csv");
   g_pathSOFSession    = g_sessionMgr.GetRunFilePath("SOF_Session.csv");
   g_pathSOFErrors     = g_sessionMgr.GetRunFilePath("SOF_Errors.csv");
   g_pathSOFGates      = g_sessionMgr.GetRunFilePath("SOF_Gates.csv");
   g_pathSOFTrades     = g_sessionMgr.GetRunFilePath("SOF_Trades.csv");
   g_pathSOFSummary    = g_sessionMgr.GetRunFilePath("SOF_Summary.csv");

   return(g_pathLiveCSV!="" && g_pathCandidateCSV!="" &&
          g_pathUEEDecisions!="" && g_pathUEEState!="" &&
          g_pathPRMELifecycle!="" && g_pathPRMEState!="" &&
          g_pathSOFSession!="" && g_pathSOFErrors!="" &&
          g_pathSOFGates!="" && g_pathSOFTrades!="" &&
          g_pathSOFSummary!="");
  }

void CloseEAOwnedLoggers()
  {
   CSVClose();
  }

void ReleaseIndicatorHandlesSOFV2()
  {
   if(g_h4_ema50_handle  != INVALID_HANDLE) { IndicatorRelease(g_h4_ema50_handle);  g_h4_ema50_handle=INVALID_HANDLE; }
   if(g_h4_ema200_handle != INVALID_HANDLE) { IndicatorRelease(g_h4_ema200_handle); g_h4_ema200_handle=INVALID_HANDLE; }
   if(g_h1_ema20_handle  != INVALID_HANDLE) { IndicatorRelease(g_h1_ema20_handle);  g_h1_ema20_handle=INVALID_HANDLE; }
   if(g_h1_ema50_handle  != INVALID_HANDLE) { IndicatorRelease(g_h1_ema50_handle);  g_h1_ema50_handle=INVALID_HANDLE; }
   if(g_h1_atr_handle    != INVALID_HANDLE) { IndicatorRelease(g_h1_atr_handle);    g_h1_atr_handle=INVALID_HANDLE; }
   if(g_rc24_h1_atr_handle != INVALID_HANDLE) { IndicatorRelease(g_rc24_h1_atr_handle); g_rc24_h1_atr_handle=INVALID_HANDLE; }
   if(g_m5_ema20_handle  != INVALID_HANDLE) { IndicatorRelease(g_m5_ema20_handle);  g_m5_ema20_handle=INVALID_HANDLE; }
  }

int FailInitialization(const string reason)
  {
   Print("[H4H1 BUY SOF V2][INIT FATAL] ",reason);
   CloseEAOwnedLoggers();
   UEE_ShutdownLogging();
   g_prme.Shutdown();
   SOF_EndSession();
   ReleaseIndicatorHandlesSOFV2();
   g_sessionMgr.LogRunEnded("InitFailed: "+reason);
   return INIT_FAILED;
  }

bool ReopenSOFV2LoggersAfterRollover()
  {
   CloseEAOwnedLoggers();
   UEE_ShutdownLogging();

   if(!ResolveSOFV2RunPaths())
     {
      Print("[H4H1 BUY SOF V2][ROLLOVER FATAL] Path resolution incomplete.");
      return false;
     }

   if(InpEnableCSVLog)
     {
      CSVOpen();
      if(g_hCSV==INVALID_HANDLE)
         return false;
     }

   if(!UEE_InitializeLogging(g_pathUEEDecisions,g_pathUEEState,true) || !UEE_LoggingReady())
     {
      Print("[H4H1 BUY SOF V2][ROLLOVER FATAL] Shared UEE logger reopen failed.");
      return false;
     }

   if(g_sofStarted)
      g_sof.ReopenAtNewPaths(g_pathSOFSession,g_pathSOFErrors,g_pathSOFGates,g_pathSOFTrades,g_pathSOFSummary);

   g_prme.ReopenLogger(g_pathPRMELifecycle,g_pathPRMEState);
   return true;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+

//==========================================================================
// [STRUCT-OBS V0.1] H4/H1 Breakout-Trend Structural Event Observer
// Read-only by design. It never changes trend, pullback, UEE, PRME,
// pending-order, scoring, lot, SL/TP, or execution decisions.
// BOS is sourced from the existing shared MarketPhase engine's confirmed
// structure_break_direction / structure_break_price fields.
//==========================================================================
MarketPhase_Engine g_structMP_H4;
MarketPhase_Engine g_structMP_H1;
MarketPhase_Engine g_structMP_M15;
bool     g_structMPReady = false;
int      g_structObsHandle = INVALID_HANDLE;
datetime g_structLastH4Closed = 0;
datetime g_structLastH1Closed = 0;
double   g_structLastH4BullBreakPrice = 0.0;
double   g_structLastH1BullBreakPrice = 0.0;
ulong    g_structEventSeq = 0;

double StructAurexPoints(const double priceDistance)
  {
   return priceDistance * 100.0; // Aurex convention: 1.00 XAU price = 100 points
  }

string StructBool(const bool v) { return v ? "1" : "0"; }

string StructEventID(const datetime t,const string type)
  {
   g_structEventSeq++;
   return StringFormat("%s_%s_%I64u",
                       TimeToString(t,TIME_DATE|TIME_MINUTES),
                       type,g_structEventSeq);
  }

bool StructBullishBodyEngulf(const MqlRates &cur,const MqlRates &prev)
  {
   if(cur.close <= cur.open) return false;
   if(prev.close >= prev.open) return false;
   return (cur.open <= prev.close && cur.close >= prev.open);
  }

void StructWriteHeader()
  {
   if(g_structObsHandle==INVALID_HANDLE) return;
   FileWrite(g_structObsHandle,
      "EventID","EventTime","TF","EventType",
      "MP_CurrentPhase","MP_PreviousPhase","MP_PhaseAge","MP_Confidence",
      "StructureBreakDirection","StructureBreakPrice","BreakDistancePoints",
      "ConfirmedSwingHigh","ConfirmedSwingLow",
      "ImpulseDirection","ImpulseDisplacementATR","ImpulseBodyRatio",
      "PullbackState","PullbackDepth","PullbackFinished",
      "ContinuationState","ContinuationActive",
      "Open","High","Low","Close","BodyPoints","RangePoints",
      "LowerWickPoints","LowerWickBodyRatio","LowerWickRangePct",
      "BullishEngulf","LowerWickRejection",
      "H1Phase","M15Phase","Notes");
   FileFlush(g_structObsHandle);
  }

void StructWriteEvent(const string eventID,
                      const datetime eventTime,
                      const string tf,
                      const string eventType,
                      const MarketPhaseSnapshot &snap,
                      const MqlRates &bar,
                      const bool bullishEngulf,
                      const bool lowerWickReject,
                      const string h1Phase,
                      const string m15Phase,
                      const string notes)
  {
   if(g_structObsHandle==INVALID_HANDLE) return;

   double body = MathAbs(bar.close-bar.open);
   double range = MathMax(0.0,bar.high-bar.low);
   double lowerWick = MathMax(0.0,MathMin(bar.open,bar.close)-bar.low);
   double wickBodyRatio = (body>0.0 ? lowerWick/body : 999.0);
   double wickRangePct = (range>0.0 ? lowerWick/range : 0.0);
   double breakDistPts = 0.0;
   if(snap.structure_break_direction==1 && snap.structure_break_price>0.0)
      breakDistPts = StructAurexPoints(bar.close-snap.structure_break_price);

   FileWrite(g_structObsHandle,
      eventID,
      TimeToString(eventTime,TIME_DATE|TIME_MINUTES),
      tf,eventType,
      MarketPhaseName(snap.current_phase),
      MarketPhaseName(snap.previous_phase),
      snap.phase_age_bars,
      (int)snap.phase_confidence,
      snap.structure_break_direction,
      DoubleToString(snap.structure_break_price,_Digits),
      DoubleToString(breakDistPts,1),
      DoubleToString(snap.last_confirmed_swing_high,_Digits),
      DoubleToString(snap.last_confirmed_swing_low,_Digits),
      snap.impulse_direction,
      DoubleToString(snap.impulse_displacement_atr,3),
      DoubleToString(snap.impulse_body_ratio,3),
      (int)snap.pullback_state,
      DoubleToString(snap.pullback_depth,3),
      StructBool(snap.has_pullback_finished),
      (int)snap.last_continuation_state,
      StructBool(snap.continuation_is_active),
      DoubleToString(bar.open,_Digits),
      DoubleToString(bar.high,_Digits),
      DoubleToString(bar.low,_Digits),
      DoubleToString(bar.close,_Digits),
      DoubleToString(StructAurexPoints(body),1),
      DoubleToString(StructAurexPoints(range),1),
      DoubleToString(StructAurexPoints(lowerWick),1),
      DoubleToString(wickBodyRatio,3),
      DoubleToString(wickRangePct,3),
      StructBool(bullishEngulf),
      StructBool(lowerWickReject),
      h1Phase,m15Phase,notes);
   FileFlush(g_structObsHandle);
  }

void StructObserve()
  {
   if(!InpStructObsEnable || !g_structMPReady || g_structObsHandle==INVALID_HANDLE) return;

   // Keep shared MarketPhase state current.
   ENUM_MARKETPHASE_EVAL_RESULT evH4  = g_structMP_H4.Evaluate();
   ENUM_MARKETPHASE_EVAL_RESULT evH1  = g_structMP_H1.Evaluate();
   ENUM_MARKETPHASE_EVAL_RESULT evM15 = g_structMP_M15.Evaluate();
   if(evH4==MP_EVAL_FAILED || evH1==MP_EVAL_FAILED || evM15==MP_EVAL_FAILED) return;

   MarketPhaseSnapshot h4Snap,h1Snap,m15Snap;
   g_structMP_H4.GetSnapshot(h4Snap);
   g_structMP_H1.GetSnapshot(h1Snap);
   g_structMP_M15.GetSnapshot(m15Snap);

   // H4: log every newly closed H4 candle as state context and emit a
   // separate event row for a fresh bullish BOS and/or strong lower wick.
   MqlRates h4[3];
   // Static array: CopyRates stores oldest -> newest. With 3 bars:
   // h4[0]=shift2, h4[1]=shift1 (last closed), h4[2]=shift0 (current).
   // Do NOT call ArraySetAsSeries() on a statically allocated array.
   if(CopyRates(_Symbol,PERIOD_H4,0,3,h4)>=3 && h4[1].time!=g_structLastH4Closed)
     {
      g_structLastH4Closed=h4[1].time;
      double body=MathAbs(h4[1].close-h4[1].open);
      double range=MathMax(0.0,h4[1].high-h4[1].low);
      double lowerWick=MathMax(0.0,MathMin(h4[1].open,h4[1].close)-h4[1].low);
      double wb=(body>0.0?lowerWick/body:999.0);
      double wr=(range>0.0?lowerWick/range:0.0);
      bool reject=(wb>=InpStructObsMinLowerWickBodyRatio && wr>=InpStructObsMinLowerWickRangePct);

      StructWriteEvent(StructEventID(h4[1].time,"H4_STATE"),h4[1].time,"H4","STATE",
                       h4Snap,h4[1],false,reject,
                       MarketPhaseName(h1Snap.current_phase),
                       MarketPhaseName(m15Snap.current_phase),"closed-H4 context");

      bool freshBullBOS=(h4Snap.structure_break_direction==1 &&
                         h4Snap.structure_break_price>0.0 &&
                         MathAbs(h4Snap.structure_break_price-g_structLastH4BullBreakPrice)>_Point);
      if(freshBullBOS)
        {
         g_structLastH4BullBreakPrice=h4Snap.structure_break_price;
         string typ=(h4Snap.previous_phase==MARKETPHASE_IMPULSE_DOWN ||
                     h4Snap.previous_phase==MARKETPHASE_RANGE ||
                     h4Snap.previous_phase==MARKETPHASE_TRANSITION)
                    ? "H4_BOS_TRANSITION" : "H4_BOS_CONTINUATION";
         StructWriteEvent(StructEventID(h4[1].time,typ),h4[1].time,"H4",typ,
                          h4Snap,h4[1],false,reject,
                          MarketPhaseName(h1Snap.current_phase),
                          MarketPhaseName(m15Snap.current_phase),
                          "MarketPhase confirmed bullish structure break");
        }

      if(reject)
         StructWriteEvent(StructEventID(h4[1].time,"H4_LOWER_WICK_REJECTION"),
                          h4[1].time,"H4","H4_LOWER_WICK_REJECTION",
                          h4Snap,h4[1],false,true,
                          MarketPhaseName(h1Snap.current_phase),
                          MarketPhaseName(m15Snap.current_phase),
                          "context only; inspect H1/M15 decomposition");
     }

   // H1: fresh bullish BOS and bullish body engulf are independent new
   // structural events. They do NOT place/re-arm an order in this build.
   MqlRates h1[3];
   // Static array: h1[1] is the last closed H1 candle; h1[0] is its predecessor.
   // Do NOT call ArraySetAsSeries() on a statically allocated array.
   if(CopyRates(_Symbol,PERIOD_H1,0,3,h1)>=3 && h1[1].time!=g_structLastH1Closed)
     {
      g_structLastH1Closed=h1[1].time;
      bool engulf=StructBullishBodyEngulf(h1[1],h1[0]);

      bool freshH1BOS=(h1Snap.structure_break_direction==1 &&
                       h1Snap.structure_break_price>0.0 &&
                       MathAbs(h1Snap.structure_break_price-g_structLastH1BullBreakPrice)>_Point);
      if(freshH1BOS)
        {
         g_structLastH1BullBreakPrice=h1Snap.structure_break_price;
         StructWriteEvent(StructEventID(h1[1].time,"H1_BOS"),h1[1].time,"H1","H1_BOS",
                          h1Snap,h1[1],engulf,false,
                          MarketPhaseName(h1Snap.current_phase),
                          MarketPhaseName(m15Snap.current_phase),
                          "fresh H1 bullish structure break");
        }
      if(engulf)
        {
         StructWriteEvent(StructEventID(h1[1].time,"H1_BULL_ENGULF"),h1[1].time,"H1","H1_BULL_ENGULF",
                          h1Snap,h1[1],true,false,
                          MarketPhaseName(h1Snap.current_phase),
                          MarketPhaseName(m15Snap.current_phase),
                          "fresh H1 body engulf; observer only");
        }
     }
  }



// [STRUCT-OBS V0.2] Dedicated closed-bar pivot BOS + RBR/DBD observer.
// MarketPhase remains context only. Nothing here changes trading decisions.
int g_v02File=INVALID_HANDLE;
datetime g_v02H4=0,g_v02H1=0;
double g_v02H4Bull=0,g_v02H4Bear=0,g_v02H1Bull=0,g_v02H1Bear=0;
ulong g_v02Seq=0;

double V02ATR(ENUM_TIMEFRAMES tf)
{
 int h=iATR(_Symbol,tf,14); if(h==INVALID_HANDLE) return 0;
 double x[1]; double v=(CopyBuffer(h,0,1,1,x)==1?x[0]:0); IndicatorRelease(h); return v;
}
bool V02PH(MqlRates &r[],int i,int n)
{
 if(i-InpStructPivotLeft<0 || i+InpStructPivotRight>=n) return false;
 for(int k=1;k<=InpStructPivotLeft;k++) if(r[i-k].high>=r[i].high) return false;
 for(int k=1;k<=InpStructPivotRight;k++) if(r[i+k].high>r[i].high) return false;
 return true;
}
bool V02PL(MqlRates &r[],int i,int n)
{
 if(i-InpStructPivotLeft<0 || i+InpStructPivotRight>=n) return false;
 for(int k=1;k<=InpStructPivotLeft;k++) if(r[i-k].low<=r[i].low) return false;
 for(int k=1;k<=InpStructPivotRight;k++) if(r[i+k].low<r[i].low) return false;
 return true;
}
bool V02Swings(ENUM_TIMEFRAMES tf,double &sh,datetime &sht,double &sl,datetime &slt)
{
 int need=MathMax(40,InpStructSwingLookback+InpStructPivotLeft+InpStructPivotRight+5);
 MqlRates r[]; ArrayResize(r,need);
 int n=CopyRates(_Symbol,tf,1,need,r); if(n<10) return false;
 sh=0;sl=0;sht=0;slt=0;
 int last=n-1-InpStructPivotRight;
 for(int i=last;i>=InpStructPivotLeft;i--)
 {
   if(sht==0 && V02PH(r,i,n)){sh=r[i].high;sht=r[i].time;}
   if(slt==0 && V02PL(r,i,n)){sl=r[i].low;slt=r[i].time;}
   if(sht>0 && slt>0) break;
 }
 return sht>0 || slt>0;
}
bool V02Strong(MqlRates &b,double atr,bool bull)
{
 double range=b.high-b.low; double body=(bull?b.close-b.open:b.open-b.close);
 return atr>0 && range>0 && body>0 &&
        body/atr>=InpStructRallyMinBodyATR && body/range>=InpStructRallyMinBodyRatio;
}
string V02Pattern(ENUM_TIMEFRAMES tf,int &nb,double &bh,double &bl)
{
 int maxb=MathMax(1,InpStructBaseMaxBars), need=maxb+4;
 MqlRates r[]; ArrayResize(r,need);
 int n=CopyRates(_Symbol,tf,1,need,r); if(n<4) return "NONE";
 int d2=n-1; double atr=V02ATR(tf); if(atr<=0) return "NONE";
 for(int b=1;b<=maxb;b++)
 {
   int d1=d2-b-1; if(d1<0) break;
   bh=-DBL_MAX; bl=DBL_MAX;
   for(int j=d1+1;j<d2;j++){bh=MathMax(bh,r[j].high);bl=MathMin(bl,r[j].low);}
   if((bh-bl)/atr>InpStructBaseMaxRangeATR) continue;
   if(V02Strong(r[d1],atr,true)&&V02Strong(r[d2],atr,true)&&r[d2].close>bh){nb=b;return "RBR";}
   if(V02Strong(r[d1],atr,false)&&V02Strong(r[d2],atr,false)&&r[d2].close<bl){nb=b;return "DBD";}
 }
 return "NONE";
}
void V02Header()
{
 FileWrite(g_v02File,"EventID","EventTime","TF","EventType","MarketStage","PreviousStage",
 "Close","SwingHigh","SwingHighTime","SwingLow","SwingLowTime","BullBOS","BearBOS",
 "BreakLevel","BreakDistancePoints","Pattern","BaseBars","BaseHigh","BaseLow","BaseRangePoints",
 "BodyPoints","RangePoints","ATRPoints","BodyATR","BodyRangeRatio","LowerWickPoints",
 "UpperWickPoints","ImpulseDirection","ImpulseATR","PullbackDepth","ContinuationActive","Notes");
 FileFlush(g_v02File);
}
void V02Write(datetime t,ENUM_TIMEFRAMES tf,string tn,string et,MarketPhaseSnapshot &mp,
 MqlRates &b,double sh,datetime sht,double sl,datetime slt,bool ub,bool db,double level,
 string pat,int nb,double bh,double bl,string note)
{
 double range=b.high-b.low,body=MathAbs(b.close-b.open),atr=V02ATR(tf);
 double lw=MathMax(0.0,MathMin(b.open,b.close)-b.low),uw=MathMax(0.0,b.high-MathMax(b.open,b.close));
 double dist=(ub?StructAurexPoints(b.close-level):(db?StructAurexPoints(level-b.close):0));
 string id=StringFormat("%s_%s_%s_%I64u",TimeToString(t,TIME_DATE|TIME_MINUTES),tn,et,++g_v02Seq);
 FileWrite(g_v02File,id,TimeToString(t,TIME_DATE|TIME_MINUTES),tn,et,
 MarketPhaseName(mp.current_phase),MarketPhaseName(mp.previous_phase),DoubleToString(b.close,_Digits),
 DoubleToString(sh,_Digits),TimeToString(sht,TIME_DATE|TIME_MINUTES),DoubleToString(sl,_Digits),
 TimeToString(slt,TIME_DATE|TIME_MINUTES),StructBool(ub),StructBool(db),DoubleToString(level,_Digits),
 DoubleToString(dist,1),pat,nb,DoubleToString(bh,_Digits),DoubleToString(bl,_Digits),
 DoubleToString(StructAurexPoints(MathMax(0.0,bh-bl)),1),DoubleToString(StructAurexPoints(body),1),
 DoubleToString(StructAurexPoints(range),1),DoubleToString(StructAurexPoints(atr),1),
 DoubleToString(atr>0?body/atr:0,3),DoubleToString(range>0?body/range:0,3),
 DoubleToString(StructAurexPoints(lw),1),DoubleToString(StructAurexPoints(uw),1),
 mp.impulse_direction,DoubleToString(mp.impulse_displacement_atr,3),DoubleToString(mp.pullback_depth,3),
 StructBool(mp.continuation_is_active),note); FileFlush(g_v02File);
}
void V02TF(ENUM_TIMEFRAMES tf,string tn,MarketPhase_Engine &eng,datetime &last,double &lastBull,double &lastBear)
{
 MqlRates b[2]; if(CopyRates(_Symbol,tf,0,2,b)<2 || b[0].time==last) return; last=b[0].time;
 MarketPhaseSnapshot mp; eng.GetSnapshot(mp);
 double sh,sl;datetime sht,slt;if(!V02Swings(tf,sh,sht,sl,slt))return;
 bool ub=sh>0&&b[0].close>sh&&MathAbs(sh-lastBull)>_Point;
 bool db=sl>0&&b[0].close<sl&&MathAbs(sl-lastBear)>_Point;
 if(ub)lastBull=sh;if(db)lastBear=sl;
 int nb=0;double bh=0,bl=0;string pat=V02Pattern(tf,nb,bh,bl);
 V02Write(b[0].time,tf,tn,"STATE",mp,b[0],sh,sht,sl,slt,false,false,0,pat,nb,bh,bl,"state/context only");
 if(ub)V02Write(b[0].time,tf,tn,"BULL_BOS",mp,b[0],sh,sht,sl,slt,true,false,sh,pat,nb,bh,bl,"close above confirmed pivot high");
 if(db)V02Write(b[0].time,tf,tn,"BEAR_BOS",mp,b[0],sh,sht,sl,slt,false,true,sl,pat,nb,bh,bl,"close below confirmed pivot low");
 if(pat=="RBR"||pat=="DBD")V02Write(b[0].time,tf,tn,pat,mp,b[0],sh,sht,sl,slt,ub,db,(ub?sh:(db?sl:0)),pat,nb,bh,bl,"fresh continuation structure");
}
void StructObserveV02()
{
 if(!InpStructObsEnable||!g_structMPReady||g_v02File==INVALID_HANDLE)return;
 V02TF(PERIOD_H4,"H4",g_structMP_H4,g_v02H4,g_v02H4Bull,g_v02H4Bear);
 V02TF(PERIOD_H1,"H1",g_structMP_H1,g_v02H1,g_v02H1Bull,g_v02H1Bear);
}


// [STRUCT-OBS V0.3] Directional Evidence Observer.
// Research only. Uses only events known at/after their CLOSED-bar timestamps.
// It never changes native 1506272 execution.
int g_dirFile=INVALID_HANDLE;
datetime g_dirLastH1=0,g_dirLastH4=0;
datetime g_dirLastH4BullBOS=0,g_dirLastH4BearBOS=0;
datetime g_dirLastH4RBR=0,g_dirLastH4DBD=0;
datetime g_dirLastH1BullBOS=0,g_dirLastH1BearBOS=0;
datetime g_dirLastH1RBR=0,g_dirLastH1DBD=0;
string g_dirState="UNKNOWN";
ulong g_dirSeq=0;

bool DirRecent(datetime e,datetime now,int hours){return(e>0 && now>=e && (now-e)<=hours*3600);}

void DirHeader()
{
 FileWrite(g_dirFile,"Seq","Time","TriggerTF","TriggerEvent","MarketStageH4","MarketStageH1",
 "BullScore","BearScore","NetEvidence","DirectionState",
 "H4BullBOSRecent","H4BearBOSRecent","H4RBRRecent","H4DBDRecent",
 "H1BullBOSRecent","H1BearBOSRecent","H1RBRRecent","H1DBDRecent","StateChanged","Notes");
 FileFlush(g_dirFile);
}

void DirScore(datetime now,string triggerTF,string triggerEvent)
{
 int bull=0,bear=0;
 // H4 evidence deliberately persists longer than H1 evidence.
 bool h4bb=DirRecent(g_dirLastH4BullBOS,now,48), h4sb=DirRecent(g_dirLastH4BearBOS,now,48);
 bool h4r =DirRecent(g_dirLastH4RBR,now,48),     h4d =DirRecent(g_dirLastH4DBD,now,48);
 bool h1bb=DirRecent(g_dirLastH1BullBOS,now,InpDirEvidenceLookbackH1);
 bool h1sb=DirRecent(g_dirLastH1BearBOS,now,InpDirEvidenceLookbackH1);
 bool h1r =DirRecent(g_dirLastH1RBR,now,InpDirEvidenceLookbackH1);
 bool h1d =DirRecent(g_dirLastH1DBD,now,InpDirEvidenceLookbackH1);

 if(h4bb) bull+=InpDirH4BOSWeight; if(h4sb) bear+=InpDirH4BOSWeight;
 if(h4r)  bull+=InpDirH4PatternWeight; if(h4d) bear+=InpDirH4PatternWeight;
 if(h1bb) bull+=InpDirH1BOSWeight; if(h1sb) bear+=InpDirH1BOSWeight;
 if(h1r)  bull+=InpDirH1PatternWeight; if(h1d) bear+=InpDirH1PatternWeight;

 // Opposite fresh H1 BOS explicitly penalizes directional confidence.
 if(h1sb) bull=MathMax(0,bull-InpDirOppositeH1BOSPenalty);
 if(h1bb) bear=MathMax(0,bear-InpDirOppositeH1BOSPenalty);

 int net=bull-bear;
 string next="UNKNOWN";
 if(bull>=InpDirConfirmThreshold && net>=InpDirConflictMargin) next="BULL_CONFIRMED";
 else if(bear>=InpDirConfirmThreshold && -net>=InpDirConflictMargin) next="BEAR_CONFIRMED";
 else if(bull>=InpDirDevelopThreshold && net>=InpDirConflictMargin) next="BULL_DEVELOPING";
 else if(bear>=InpDirDevelopThreshold && -net>=InpDirConflictMargin) next="BEAR_DEVELOPING";

 bool changed=(next!=g_dirState); g_dirState=next;
 MarketPhaseSnapshot h4,h1; g_structMP_H4.GetSnapshot(h4);g_structMP_H1.GetSnapshot(h1);
 FileWrite(g_dirFile,++g_dirSeq,TimeToString(now,TIME_DATE|TIME_MINUTES),triggerTF,triggerEvent,
 MarketPhaseName(h4.current_phase),MarketPhaseName(h1.current_phase),bull,bear,net,next,
 StructBool(h4bb),StructBool(h4sb),StructBool(h4r),StructBool(h4d),
 StructBool(h1bb),StructBool(h1sb),StructBool(h1r),StructBool(h1d),StructBool(changed),
 "observer only; no trade permission");
 FileFlush(g_dirFile);
}

void DirObserve()
{
 if(!InpStructObsEnable||!g_structMPReady||g_dirFile==INVALID_HANDLE)return;

 // Reuse V0.2's causal event definitions, independently on each newly closed bar.
 MqlRates h4[2];
 if(CopyRates(_Symbol,PERIOD_H4,0,2,h4)>=2 && h4[0].time!=g_dirLastH4)
 {
   g_dirLastH4=h4[0].time;
   double sh,sl;datetime sht,slt;
   if(V02Swings(PERIOD_H4,sh,sht,sl,slt))
   {
     bool ub=sh>0 && h4[0].close>sh;
     bool db=sl>0 && h4[0].close<sl;
     int nb=0;double bh=0,bl=0;string p=V02Pattern(PERIOD_H4,nb,bh,bl);
     string trig="H4_STATE";
     if(ub){g_dirLastH4BullBOS=h4[0].time;trig="H4_BULL_BOS";}
     if(db){g_dirLastH4BearBOS=h4[0].time;trig="H4_BEAR_BOS";}
     if(p=="RBR"){g_dirLastH4RBR=h4[0].time;trig+=(string)"+RBR";}
     if(p=="DBD"){g_dirLastH4DBD=h4[0].time;trig+=(string)"+DBD";}
     DirScore(h4[0].time,"H4",trig);
   }
 }
 MqlRates h1[2];
 if(CopyRates(_Symbol,PERIOD_H1,0,2,h1)>=2 && h1[0].time!=g_dirLastH1)
 {
   g_dirLastH1=h1[0].time;
   double sh,sl;datetime sht,slt;
   if(V02Swings(PERIOD_H1,sh,sht,sl,slt))
   {
     bool ub=sh>0 && h1[0].close>sh;
     bool db=sl>0 && h1[0].close<sl;
     int nb=0;double bh=0,bl=0;string p=V02Pattern(PERIOD_H1,nb,bh,bl);
     string trig="H1_STATE";
     if(ub){g_dirLastH1BullBOS=h1[0].time;trig="H1_BULL_BOS";}
     if(db){g_dirLastH1BearBOS=h1[0].time;trig="H1_BEAR_BOS";}
     if(p=="RBR"){g_dirLastH1RBR=h1[0].time;trig+=(string)"+RBR";}
     if(p=="DBD"){g_dirLastH1DBD=h1[0].time;trig+=(string)"+DBD";}
     DirScore(h1[0].time,"H1",trig);
   }
 }
}


// [STRUCT-OBS V0.4] Ordered Breakout Lifecycle State Machine.
// Observer only. No trade decision impact.
enum ENUM_BREAKOUT_LIFECYCLE
  {
   LC_ACCUMULATION=0,
   LC_BULL_BREAK_ATTEMPT,
   LC_BULL_ACCEPTED,
   LC_BULL_CONFIRMED,
   LC_BULL_CONTINUATION,
   LC_BEAR_BREAK_ATTEMPT,
   LC_BEAR_ACCEPTED,
   LC_BEAR_CONFIRMED,
   LC_BEAR_CONTINUATION
  };

string LifecycleName(ENUM_BREAKOUT_LIFECYCLE s)
  {
   switch(s)
     {
      case LC_ACCUMULATION: return "ACCUMULATION";
      case LC_BULL_BREAK_ATTEMPT: return "BULL_BREAK_ATTEMPT";
      case LC_BULL_ACCEPTED: return "BULL_ACCEPTED";
      case LC_BULL_CONFIRMED: return "BULL_CONFIRMED";
      case LC_BULL_CONTINUATION: return "BULL_CONTINUATION";
      case LC_BEAR_BREAK_ATTEMPT: return "BEAR_BREAK_ATTEMPT";
      case LC_BEAR_ACCEPTED: return "BEAR_ACCEPTED";
      case LC_BEAR_CONFIRMED: return "BEAR_CONFIRMED";
      case LC_BEAR_CONTINUATION: return "BEAR_CONTINUATION";
     }
   return "UNKNOWN";
  }

int g_lcFile=INVALID_HANDLE;
ENUM_BREAKOUT_LIFECYCLE g_lcState=LC_ACCUMULATION;
datetime g_lcLastH4=0,g_lcLastH1=0;
datetime g_lcBreakTime=0;
double g_lcBreakLevel=0.0;
int g_lcDirection=0; // +1 bull, -1 bear
int g_lcAcceptedBars=0;
bool g_lcSawH4RBR=false;
bool g_lcSawH1BOS=false;
bool g_lcSawH1RBR=false;
ulong g_lcSeq=0;

void LifecycleHeader()
  {
   FileWrite(g_lcFile,
      "Seq","Time","TriggerTF","TriggerEvent","LifecycleState",
      "Direction","BreakTime","BreakLevel","AcceptedH4Bars",
      "H4RBRSeen","H1BOSSeen","H1RBRSeen",
      "H4Stage","H1Stage","M15Stage",
      "Close","DistanceFromBreakPoints","StateChanged","ResetReason","Notes");
   FileFlush(g_lcFile);
  }

void LifecycleWrite(datetime t,string tf,string event,MqlRates &bar,string resetReason,string notes,bool changed)
  {
   MarketPhaseSnapshot h4,h1,m15;
   g_structMP_H4.GetSnapshot(h4); g_structMP_H1.GetSnapshot(h1); g_structMP_M15.GetSnapshot(m15);
   double dist=0.0;
   if(g_lcBreakLevel>0.0)
      dist=StructAurexPoints((g_lcDirection>=0?bar.close-g_lcBreakLevel:g_lcBreakLevel-bar.close));
   FileWrite(g_lcFile,++g_lcSeq,TimeToString(t,TIME_DATE|TIME_MINUTES),tf,event,
      LifecycleName(g_lcState),g_lcDirection,
      TimeToString(g_lcBreakTime,TIME_DATE|TIME_MINUTES),DoubleToString(g_lcBreakLevel,_Digits),
      g_lcAcceptedBars,StructBool(g_lcSawH4RBR),StructBool(g_lcSawH1BOS),StructBool(g_lcSawH1RBR),
      MarketPhaseName(h4.current_phase),MarketPhaseName(h1.current_phase),MarketPhaseName(m15.current_phase),
      DoubleToString(bar.close,_Digits),DoubleToString(dist,1),StructBool(changed),resetReason,notes);
   FileFlush(g_lcFile);
  }

void LifecycleReset(const datetime t,string tf,string event,MqlRates &bar,string why)
  {
   bool changed=(g_lcState!=LC_ACCUMULATION);
   g_lcState=LC_ACCUMULATION;
   g_lcBreakTime=0; g_lcBreakLevel=0; g_lcDirection=0; g_lcAcceptedBars=0;
   g_lcSawH4RBR=false; g_lcSawH1BOS=false; g_lcSawH1RBR=false;
   LifecycleWrite(t,tf,event,bar,why,"reset to accumulation",changed);
  }

void LifecycleOnH4()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H4,0,2,b)<2 || b[0].time==g_lcLastH4) return;
   g_lcLastH4=b[0].time;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H4,sh,sht,sl,slt)) return;
   bool bullBos=(sh>0 && b[0].close>sh);
   bool bearBos=(sl>0 && b[0].close<sl);
   int nb=0; double bh=0,bl=0;
   string pat=V02Pattern(PERIOD_H4,nb,bh,bl);

   // Opposite H4 structural break immediately invalidates current directional lifecycle.
   if(g_lcDirection==1 && bearBos){LifecycleReset(b[0].time,"H4","H4_BEAR_BOS",b[0],"OPPOSITE_H4_BOS"); return;}
   if(g_lcDirection==-1 && bullBos){LifecycleReset(b[0].time,"H4","H4_BULL_BOS",b[0],"OPPOSITE_H4_BOS"); return;}

   if(g_lcState==LC_ACCUMULATION)
     {
      if(bullBos)
        {
         g_lcDirection=1; g_lcBreakTime=b[0].time; g_lcBreakLevel=sh; g_lcAcceptedBars=0;
         g_lcSawH4RBR=(pat=="RBR"); g_lcSawH1BOS=false; g_lcSawH1RBR=false;
         g_lcState=LC_BULL_BREAK_ATTEMPT;
         LifecycleWrite(b[0].time,"H4","H4_BULL_BOS",b[0],"","fresh H4 bullish breakout attempt",true);
         return;
        }
      if(bearBos)
        {
         g_lcDirection=-1; g_lcBreakTime=b[0].time; g_lcBreakLevel=sl; g_lcAcceptedBars=0;
         g_lcSawH4RBR=(pat=="DBD"); g_lcSawH1BOS=false; g_lcSawH1RBR=false;
         g_lcState=LC_BEAR_BREAK_ATTEMPT;
         LifecycleWrite(b[0].time,"H4","H4_BEAR_BOS",b[0],"","fresh H4 bearish breakout attempt",true);
         return;
        }
      LifecycleWrite(b[0].time,"H4","H4_STATE",b[0],"","accumulation / no confirmed H4 breakout",false);
      return;
     }

   // Failure: close materially back through the broken level.
   double tol=InpLifecycleFailureTolerancePoints/100.0;
   if(g_lcDirection==1 && b[0].close<g_lcBreakLevel-tol){LifecycleReset(b[0].time,"H4","H4_FAILURE",b[0],"CLOSE_BACK_BELOW_BREAK");return;}
   if(g_lcDirection==-1 && b[0].close>g_lcBreakLevel+tol){LifecycleReset(b[0].time,"H4","H4_FAILURE",b[0],"CLOSE_BACK_ABOVE_BREAK");return;}

   if(g_lcDirection==1 && pat=="RBR") g_lcSawH4RBR=true;
   if(g_lcDirection==-1 && pat=="DBD") g_lcSawH4RBR=true;

   // Acceptance requires persistence beyond the breakout on closed H4 bars.
   if((g_lcDirection==1 && b[0].close>g_lcBreakLevel) ||
      (g_lcDirection==-1 && b[0].close<g_lcBreakLevel))
      g_lcAcceptedBars++;

   if(g_lcState==LC_BULL_BREAK_ATTEMPT &&
      g_lcAcceptedBars>=InpLifecycleAcceptanceH4Bars &&
      (!InpLifecycleRequireH4RBRForAccepted || g_lcSawH4RBR))
     { g_lcState=LC_BULL_ACCEPTED; LifecycleWrite(b[0].time,"H4","H4_ACCEPTED",b[0],"","bull breakout accepted",true); return; }

   if(g_lcState==LC_BEAR_BREAK_ATTEMPT &&
      g_lcAcceptedBars>=InpLifecycleAcceptanceH4Bars &&
      (!InpLifecycleRequireH4RBRForAccepted || g_lcSawH4RBR))
     { g_lcState=LC_BEAR_ACCEPTED; LifecycleWrite(b[0].time,"H4","H4_ACCEPTED",b[0],"","bear breakout accepted",true); return; }

   // Once confirmed, a new same-direction H4 RBR/DBD marks continuation.
   if(g_lcState==LC_BULL_CONFIRMED && pat=="RBR")
     {g_lcState=LC_BULL_CONTINUATION;LifecycleWrite(b[0].time,"H4","H4_RBR",b[0],"","bull continuation structure",true);return;}
   if(g_lcState==LC_BEAR_CONFIRMED && pat=="DBD")
     {g_lcState=LC_BEAR_CONTINUATION;LifecycleWrite(b[0].time,"H4","H4_DBD",b[0],"","bear continuation structure",true);return;}

   LifecycleWrite(b[0].time,"H4","H4_STATE",b[0],"","lifecycle hold",false);
  }

void LifecycleOnH1()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H1,0,2,b)<2 || b[0].time==g_lcLastH1) return;
   g_lcLastH1=b[0].time;
   if(g_lcState==LC_ACCUMULATION || g_lcBreakTime==0) return;

   // H1 confirmation must occur after the H4 break, never retroactively.
   if(b[0].time<=g_lcBreakTime) return;
   if((b[0].time-g_lcBreakTime)>InpLifecycleConfirmWindowH1Hours*3600) return;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H1,sh,sht,sl,slt)) return;
   bool bullBos=(sh>0 && b[0].close>sh);
   bool bearBos=(sl>0 && b[0].close<sl);
   int nb=0; double bh=0,bl=0;
   string pat=V02Pattern(PERIOD_H1,nb,bh,bl);

   // Opposite H1 BOS does not immediately reverse H4 lifecycle, but resets
   // confirmation evidence to prevent chop from accumulating.
   if(g_lcDirection==1 && bearBos)
     {g_lcSawH1BOS=false;g_lcSawH1RBR=false;LifecycleWrite(b[0].time,"H1","H1_BEAR_BOS",b[0],"","bull confirmation evidence cleared",false);return;}
   if(g_lcDirection==-1 && bullBos)
     {g_lcSawH1BOS=false;g_lcSawH1RBR=false;LifecycleWrite(b[0].time,"H1","H1_BULL_BOS",b[0],"","bear confirmation evidence cleared",false);return;}

   if(g_lcDirection==1)
     {
      if(bullBos) g_lcSawH1BOS=true;
      if(pat=="RBR") g_lcSawH1RBR=true;
      bool confirm=(!InpLifecycleRequireH1BOSForConfirmed || g_lcSawH1BOS) &&
                   (!InpLifecycleAllowH1RBRForConfirmed || g_lcSawH1RBR || g_lcSawH1BOS);
      if((g_lcState==LC_BULL_ACCEPTED || g_lcState==LC_BULL_BREAK_ATTEMPT) && confirm)
        {g_lcState=LC_BULL_CONFIRMED;LifecycleWrite(b[0].time,"H1","H1_CONFIRM",b[0],"","fresh post-break H1 confirmation",true);return;}
      if((g_lcState==LC_BULL_CONFIRMED || g_lcState==LC_BULL_CONTINUATION) && (bullBos || pat=="RBR"))
        {g_lcState=LC_BULL_CONTINUATION;LifecycleWrite(b[0].time,"H1",(bullBos?"H1_BULL_BOS":"H1_RBR"),b[0],"","fresh bull continuation event",g_lcState!=LC_BULL_CONTINUATION);return;}
     }
   else if(g_lcDirection==-1)
     {
      if(bearBos) g_lcSawH1BOS=true;
      if(pat=="DBD") g_lcSawH1RBR=true;
      bool confirm=(!InpLifecycleRequireH1BOSForConfirmed || g_lcSawH1BOS) &&
                   (!InpLifecycleAllowH1RBRForConfirmed || g_lcSawH1RBR || g_lcSawH1BOS);
      if((g_lcState==LC_BEAR_ACCEPTED || g_lcState==LC_BEAR_BREAK_ATTEMPT) && confirm)
        {g_lcState=LC_BEAR_CONFIRMED;LifecycleWrite(b[0].time,"H1","H1_CONFIRM",b[0],"","fresh post-break H1 confirmation",true);return;}
      if((g_lcState==LC_BEAR_CONFIRMED || g_lcState==LC_BEAR_CONTINUATION) && (bearBos || pat=="DBD"))
        {g_lcState=LC_BEAR_CONTINUATION;LifecycleWrite(b[0].time,"H1",(bearBos?"H1_BEAR_BOS":"H1_DBD"),b[0],"","fresh bear continuation event",g_lcState!=LC_BEAR_CONTINUATION);return;}
     }
  }

void LifecycleObserve()
  {
   if(!InpStructObsEnable||!g_structMPReady||g_lcFile==INVALID_HANDLE)return;
   LifecycleOnH4();
   LifecycleOnH1();
  }


// [STRUCT-OBS V0.5] Breakout -> Retest/Hold -> H1 Confirmation -> Continuation
// Observer only. Designed to distinguish failed breakout probes from accepted
// structure without waiting for a full 2-H4-bar acceptance delay.
enum ENUM_V05_STATE
  {
   V05_ACCUMULATION=0,
   V05_BULL_BREAK_ATTEMPT,
   V05_BULL_RETEST_HOLD,
   V05_BULL_CONFIRMED,
   V05_BULL_CONTINUATION,
   V05_BEAR_BREAK_ATTEMPT,
   V05_BEAR_RETEST_HOLD,
   V05_BEAR_CONFIRMED,
   V05_BEAR_CONTINUATION
  };

string V05Name(ENUM_V05_STATE x)
  {
   switch(x)
     {
      case V05_ACCUMULATION:return "ACCUMULATION";
      case V05_BULL_BREAK_ATTEMPT:return "BULL_BREAK_ATTEMPT";
      case V05_BULL_RETEST_HOLD:return "BULL_RETEST_HOLD";
      case V05_BULL_CONFIRMED:return "BULL_CONFIRMED";
      case V05_BULL_CONTINUATION:return "BULL_CONTINUATION";
      case V05_BEAR_BREAK_ATTEMPT:return "BEAR_BREAK_ATTEMPT";
      case V05_BEAR_RETEST_HOLD:return "BEAR_RETEST_HOLD";
      case V05_BEAR_CONFIRMED:return "BEAR_CONFIRMED";
      case V05_BEAR_CONTINUATION:return "BEAR_CONTINUATION";
     }
   return "UNKNOWN";
  }

int g_v05File=INVALID_HANDLE;
ENUM_V05_STATE g_v05State=V05_ACCUMULATION;
datetime g_v05LastH4=0,g_v05LastH1=0;
datetime g_v05BreakTime=0;
double g_v05BreakLevel=0.0;
int g_v05Dir=0;
int g_v05BarsSinceBreak=0;
bool g_v05RetestSeen=false;
bool g_v05H1BOSSeen=false;
bool g_v05H1PatternSeen=false;
ulong g_v05Seq=0;

void V05Header()
  {
   FileWrite(g_v05File,
      "Seq","Time","TriggerTF","TriggerEvent","State","Direction",
      "BreakTime","BreakLevel","BarsSinceBreak","RetestSeen","H1BOSSeen","H1PatternSeen",
      "H4Stage","H1Stage","M15Stage",
      "Close","DistanceFromBreakPoints","WithinRetestZone","HardFailure",
      "FreshH4BOS","FreshH1BOS","FreshRBR_DBD","StateChanged","ResetReason","Notes");
   FileFlush(g_v05File);
  }

void V05Write(datetime t,string tf,string ev,MqlRates &bar,
              bool withinRetest,bool hardFailure,bool freshH4BOS,bool freshH1BOS,bool freshPattern,
              bool changed,string resetReason,string notes)
  {
   MarketPhaseSnapshot h4,h1,m15;
   g_structMP_H4.GetSnapshot(h4); g_structMP_H1.GetSnapshot(h1); g_structMP_M15.GetSnapshot(m15);
   double dist=0;
   if(g_v05BreakLevel>0)
      dist=StructAurexPoints(g_v05Dir>=0?bar.close-g_v05BreakLevel:g_v05BreakLevel-bar.close);

   FileWrite(g_v05File,++g_v05Seq,TimeToString(t,TIME_DATE|TIME_MINUTES),tf,ev,V05Name(g_v05State),
      g_v05Dir,TimeToString(g_v05BreakTime,TIME_DATE|TIME_MINUTES),DoubleToString(g_v05BreakLevel,_Digits),
      g_v05BarsSinceBreak,StructBool(g_v05RetestSeen),StructBool(g_v05H1BOSSeen),StructBool(g_v05H1PatternSeen),
      MarketPhaseName(h4.current_phase),MarketPhaseName(h1.current_phase),MarketPhaseName(m15.current_phase),
      DoubleToString(bar.close,_Digits),DoubleToString(dist,1),StructBool(withinRetest),StructBool(hardFailure),
      StructBool(freshH4BOS),StructBool(freshH1BOS),StructBool(freshPattern),StructBool(changed),
      resetReason,notes);
   FileFlush(g_v05File);
  }

void V05Reset(datetime t,string tf,string ev,MqlRates &bar,string why)
  {
   bool changed=(g_v05State!=V05_ACCUMULATION);
   g_v05State=V05_ACCUMULATION; g_v05Dir=0; g_v05BreakTime=0; g_v05BreakLevel=0;
   g_v05BarsSinceBreak=0; g_v05RetestSeen=false; g_v05H1BOSSeen=false; g_v05H1PatternSeen=false;
   V05Write(t,tf,ev,bar,false,false,false,false,false,changed,why,"reset");
  }

void V05OnH4()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H4,0,2,b)<2 || b[0].time==g_v05LastH4) return;
   g_v05LastH4=b[0].time;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H4,sh,sht,sl,slt)) return;
   bool bullBos=(sh>0 && b[0].close>sh);
   bool bearBos=(sl>0 && b[0].close<sl);

   int nb=0; double bh=0,bl=0;
   string pat=V02Pattern(PERIOD_H4,nb,bh,bl);
   bool bullPattern=(pat=="RBR"), bearPattern=(pat=="DBD");

   // Fresh opposite H4 BOS invalidates current directional hypothesis immediately.
   if(g_v05Dir==1 && bearBos){V05Reset(b[0].time,"H4","H4_BEAR_BOS",b[0],"OPPOSITE_H4_BOS");return;}
   if(g_v05Dir==-1 && bullBos){V05Reset(b[0].time,"H4","H4_BULL_BOS",b[0],"OPPOSITE_H4_BOS");return;}

   if(g_v05State==V05_ACCUMULATION)
     {
      if(bullBos)
        {
         g_v05Dir=1;g_v05BreakTime=b[0].time;g_v05BreakLevel=sh;g_v05BarsSinceBreak=0;
         g_v05RetestSeen=false;g_v05H1BOSSeen=false;g_v05H1PatternSeen=false;
         g_v05State=V05_BULL_BREAK_ATTEMPT;
         V05Write(b[0].time,"H4","H4_BULL_BOS",b[0],false,false,true,false,bullPattern,true,"","fresh bullish breakout attempt");
         return;
        }
      if(bearBos)
        {
         g_v05Dir=-1;g_v05BreakTime=b[0].time;g_v05BreakLevel=sl;g_v05BarsSinceBreak=0;
         g_v05RetestSeen=false;g_v05H1BOSSeen=false;g_v05H1PatternSeen=false;
         g_v05State=V05_BEAR_BREAK_ATTEMPT;
         V05Write(b[0].time,"H4","H4_BEAR_BOS",b[0],false,false,true,false,bearPattern,true,"","fresh bearish breakout attempt");
         return;
        }
      V05Write(b[0].time,"H4","H4_STATE",b[0],false,false,false,false,false,false,"","accumulation");
      return;
     }

   g_v05BarsSinceBreak++;

   double retTol=InpV05RetestTolerancePoints/100.0;
   double failTol=InpV05HardFailurePoints/100.0;
   bool withinRetest=false,hardFail=false;

   if(g_v05Dir==1)
     {
      withinRetest=(b[0].low<=g_v05BreakLevel+retTol && b[0].close>=g_v05BreakLevel-failTol);
      hardFail=(b[0].close<g_v05BreakLevel-failTol);
     }
   else
     {
      withinRetest=(b[0].high>=g_v05BreakLevel-retTol && b[0].close<=g_v05BreakLevel+failTol);
      hardFail=(b[0].close>g_v05BreakLevel+failTol);
     }

   if(hardFail){V05Reset(b[0].time,"H4","H4_HARD_FAILURE",b[0],"HARD_CLOSE_THROUGH_BREAK");return;}

   if(withinRetest && g_v05BarsSinceBreak<=InpV05MaxRetestH4Bars)
     {
      g_v05RetestSeen=true;
      ENUM_V05_STATE old=g_v05State;
      g_v05State=(g_v05Dir==1?V05_BULL_RETEST_HOLD:V05_BEAR_RETEST_HOLD);
      V05Write(b[0].time,"H4","H4_RETEST_HOLD",b[0],true,false,false,false,(g_v05Dir==1?bullPattern:bearPattern),
               g_v05State!=old,"","breakout boundary retest/hold");
      return;
     }

   // A second same-direction H4 BOS refreshes the hypothesis with new evidence,
   // rather than reusing the old candidate.
   if(g_v05Dir==1 && bullBos && sh>g_v05BreakLevel)
     {
      g_v05BreakTime=b[0].time;g_v05BreakLevel=sh;g_v05BarsSinceBreak=0;
      g_v05RetestSeen=false;g_v05H1BOSSeen=false;g_v05H1PatternSeen=false;
      g_v05State=V05_BULL_BREAK_ATTEMPT;
      V05Write(b[0].time,"H4","H4_NEW_BULL_BOS",b[0],false,false,true,false,bullPattern,true,"","new bullish structural event");
      return;
     }
   if(g_v05Dir==-1 && bearBos && sl<g_v05BreakLevel)
     {
      g_v05BreakTime=b[0].time;g_v05BreakLevel=sl;g_v05BarsSinceBreak=0;
      g_v05RetestSeen=false;g_v05H1BOSSeen=false;g_v05H1PatternSeen=false;
      g_v05State=V05_BEAR_BREAK_ATTEMPT;
      V05Write(b[0].time,"H4","H4_NEW_BEAR_BOS",b[0],false,false,true,false,bearPattern,true,"","new bearish structural event");
      return;
     }

   // Confirmation/continuation state holds unless contradicted.
   V05Write(b[0].time,"H4","H4_STATE",b[0],withinRetest,false,false,false,(g_v05Dir==1?bullPattern:bearPattern),false,"","lifecycle hold");
  }

void V05OnH1()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H1,0,2,b)<2 || b[0].time==g_v05LastH1) return;
   g_v05LastH1=b[0].time;
   if(g_v05State==V05_ACCUMULATION || g_v05BreakTime==0 || b[0].time<=g_v05BreakTime) return;
   if((b[0].time-g_v05BreakTime)>InpV05ConfirmWindowH1Hours*3600) return;

   double sh,sl;datetime sht,slt;
   if(!V02Swings(PERIOD_H1,sh,sht,sl,slt)) return;
   bool bullBos=(sh>0 && b[0].close>sh);
   bool bearBos=(sl>0 && b[0].close<sl);

   int nb=0;double bh=0,bl=0;
   string pat=V02Pattern(PERIOD_H1,nb,bh,bl);
   bool bullRBR=(pat=="RBR"),bearDBD=(pat=="DBD");

   // Opposite H1 BOS clears confirmation evidence but does not reverse H4 hypothesis.
   if(g_v05Dir==1 && bearBos)
     {
      g_v05H1BOSSeen=false;g_v05H1PatternSeen=false;
      V05Write(b[0].time,"H1","H1_BEAR_CONFLICT",b[0],false,false,false,true,bearDBD,false,"","bull confirmation evidence cleared");
      return;
     }
   if(g_v05Dir==-1 && bullBos)
     {
      g_v05H1BOSSeen=false;g_v05H1PatternSeen=false;
      V05Write(b[0].time,"H1","H1_BULL_CONFLICT",b[0],false,false,false,true,bullRBR,false,"","bear confirmation evidence cleared");
      return;
     }

   if(g_v05Dir==1)
     {
      if(bullBos) g_v05H1BOSSeen=true;
      if(bullRBR) g_v05H1PatternSeen=true;

      bool eligible=(g_v05State==V05_BULL_BREAK_ATTEMPT || g_v05State==V05_BULL_RETEST_HOLD);
      bool confirm=( !InpV05RequireH1BOS || g_v05H1BOSSeen ) &&
                   ( !InpV05AllowH1RBR || g_v05H1PatternSeen || g_v05H1BOSSeen );

      if(eligible && confirm)
        {
         g_v05State=V05_BULL_CONFIRMED;
         V05Write(b[0].time,"H1","H1_CONFIRM",b[0],false,false,false,bullBos,bullRBR,true,"","fresh post-break H1 confirmation");
         return;
        }

      if((g_v05State==V05_BULL_CONFIRMED || g_v05State==V05_BULL_CONTINUATION) &&
         (bullBos || bullRBR))
        {
         if(InpV05RequireFreshContinuationEvent)
           {
            bool changed=(g_v05State!=V05_BULL_CONTINUATION);
            g_v05State=V05_BULL_CONTINUATION;
            V05Write(b[0].time,"H1",(bullBos?"H1_BULL_BOS":"H1_RBR"),b[0],false,false,false,bullBos,bullRBR,changed,"","fresh bullish continuation event");
           }
         return;
        }
     }
   else if(g_v05Dir==-1)
     {
      if(bearBos) g_v05H1BOSSeen=true;
      if(bearDBD) g_v05H1PatternSeen=true;

      bool eligible=(g_v05State==V05_BEAR_BREAK_ATTEMPT || g_v05State==V05_BEAR_RETEST_HOLD);
      bool confirm=( !InpV05RequireH1BOS || g_v05H1BOSSeen ) &&
                   ( !InpV05AllowH1RBR || g_v05H1PatternSeen || g_v05H1BOSSeen );

      if(eligible && confirm)
        {
         g_v05State=V05_BEAR_CONFIRMED;
         V05Write(b[0].time,"H1","H1_CONFIRM",b[0],false,false,false,bearBos,bearDBD,true,"","fresh post-break H1 confirmation");
         return;
        }

      if((g_v05State==V05_BEAR_CONFIRMED || g_v05State==V05_BEAR_CONTINUATION) &&
         (bearBos || bearDBD))
        {
         bool changed=(g_v05State!=V05_BEAR_CONTINUATION);
         g_v05State=V05_BEAR_CONTINUATION;
         V05Write(b[0].time,"H1",(bearBos?"H1_BEAR_BOS":"H1_DBD"),b[0],false,false,false,bearBos,bearDBD,changed,"","fresh bearish continuation event");
         return;
        }
     }
  }

void V05Observe()
  {
   if(!InpStructObsEnable||!g_structMPReady||g_v05File==INVALID_HANDLE)return;
   V05OnH4();
   V05OnH1();
  }


//==========================================================================
// [STRUCT-OBS V0.6] General Market Lifecycle Observer
//
// Objective:
//   Measure balance/base quality, breakout attempt, retest/hold, H1 causal
//   confirmation, expansion/continuation, and failure in BOTH directions.
//
// V0.6 is OBSERVER ONLY. It never changes:
//   native H4/H1 trend, pullback gates, UEE, PRME, pending orders,
//   lot sizing, SL/TP, or execution.
//
// MarketPhase is retained as context. Dedicated confirmed-pivot BOS and
// RBR/DBD from V0.2 remain the structural event layer.
//==========================================================================
enum ENUM_V06_STATE
  {
   V06_BALANCE=0,
   V06_BULL_BREAK_ATTEMPT,
   V06_BULL_RETEST_HOLD,
   V06_BULL_CONFIRMED,
   V06_BULL_EXPANSION,
   V06_BULL_CONTINUATION,
   V06_BEAR_BREAK_ATTEMPT,
   V06_BEAR_RETEST_HOLD,
   V06_BEAR_CONFIRMED,
   V06_BEAR_EXPANSION,
   V06_BEAR_CONTINUATION
  };

string V06StateName(const ENUM_V06_STATE x)
  {
   switch(x)
     {
      case V06_BALANCE: return "BALANCE";
      case V06_BULL_BREAK_ATTEMPT: return "BULL_BREAK_ATTEMPT";
      case V06_BULL_RETEST_HOLD: return "BULL_RETEST_HOLD";
      case V06_BULL_CONFIRMED: return "BULL_CONFIRMED";
      case V06_BULL_EXPANSION: return "BULL_EXPANSION";
      case V06_BULL_CONTINUATION: return "BULL_CONTINUATION";
      case V06_BEAR_BREAK_ATTEMPT: return "BEAR_BREAK_ATTEMPT";
      case V06_BEAR_RETEST_HOLD: return "BEAR_RETEST_HOLD";
      case V06_BEAR_CONFIRMED: return "BEAR_CONFIRMED";
      case V06_BEAR_EXPANSION: return "BEAR_EXPANSION";
      case V06_BEAR_CONTINUATION: return "BEAR_CONTINUATION";
     }
   return "UNKNOWN";
  }

int g_v06StateFile=INVALID_HANDLE;
int g_v06EpisodeFile=INVALID_HANDLE;
ENUM_V06_STATE g_v06State=V06_BALANCE;

datetime g_v06LastH4=0;
datetime g_v06LastH1=0;
ulong    g_v06EpisodeSeq=0;
string   g_v06EpisodeID="";
datetime g_v06EpisodeStart=0;
datetime g_v06BreakTime=0;
double   g_v06BreakLevel=0.0;
int      g_v06Direction=0; // +1 bull, -1 bear
int      g_v06H4BarsSinceBreak=0;

bool g_v06RetestSeen=false;
bool g_v06H1BOSSeen=false;
bool g_v06H1PatternSeen=false;
bool g_v06ExpansionSeen=false;

double g_v06BaseHigh=0.0;
double g_v06BaseLow=0.0;
double g_v06BaseRangePoints=0.0;
double g_v06BaseRangeATR=0.0;
double g_v06CompressionRatio=0.0;
int    g_v06UpperTests=0;
int    g_v06LowerTests=0;
int    g_v06FailedBullProbes=0;
int    g_v06FailedBearProbes=0;

double g_v06MaxFavorablePoints=0.0;
double g_v06MaxAdversePoints=0.0;

string V06EpisodeID(const datetime t,const int dir)
  {
   g_v06EpisodeSeq++;
   return StringFormat("V06_%s_%s_%I64u",
                       TimeToString(t,TIME_DATE|TIME_MINUTES),
                       dir>0?"BULL":"BEAR",g_v06EpisodeSeq);
  }

bool V06CalcBaseMetrics(double &baseHigh,double &baseLow,double &baseRangePts,
                        double &baseRangeATR,double &compression,
                        int &upperTests,int &lowerTests,
                        int &failedBull,int &failedBear)
  {
   int n=MathMax(6,InpV06BaseLookbackH4Bars);
   MqlRates r[];
   ArrayResize(r,n);
   int got=CopyRates(_Symbol,PERIOD_H4,2,n,r); // bars BEFORE the last closed breakout bar
   if(got<n) return false;

   baseHigh=-DBL_MAX;
   baseLow=DBL_MAX;
   for(int i=0;i<got;i++)
     {
      baseHigh=MathMax(baseHigh,r[i].high);
      baseLow =MathMin(baseLow ,r[i].low);
     }

   double atr=V02ATR(PERIOD_H4);
   baseRangePts=StructAurexPoints(MathMax(0.0,baseHigh-baseLow));
   baseRangeATR=(atr>0.0 ? (baseHigh-baseLow)/atr : 0.0);

   int recent=MathMax(2,MathMin(InpV06CompressionRecentBars,got/2));
   double recentAvg=0.0, priorAvg=0.0;
   for(int i=got-recent;i<got;i++)
      recentAvg += (r[i].high-r[i].low);
   recentAvg/=recent;

   int priorCount=got-recent;
   if(priorCount>0)
     {
      for(int i=0;i<priorCount;i++)
         priorAvg += (r[i].high-r[i].low);
      priorAvg/=priorCount;
     }
   compression=(priorAvg>0.0 ? recentAvg/priorAvg : 1.0);

   double tol=InpV06BoundaryTestTolerancePoints/100.0;
   upperTests=0; lowerTests=0; failedBull=0; failedBear=0;

   for(int i=0;i<got;i++)
     {
      if(baseHigh-r[i].high<=tol) upperTests++;
      if(r[i].low-baseLow<=tol) lowerTests++;

      // Sequential failed probes use only information available BEFORE that bar.
      if(i>=2)
        {
         double prevHigh=-DBL_MAX,prevLow=DBL_MAX;
         for(int j=0;j<i;j++)
           {
            prevHigh=MathMax(prevHigh,r[j].high);
            prevLow =MathMin(prevLow ,r[j].low);
           }
         if(r[i].high>prevHigh && r[i].close<=prevHigh) failedBull++;
         if(r[i].low <prevLow  && r[i].close>=prevLow ) failedBear++;
        }
     }
   return true;
  }

void V06StateHeader()
  {
   FileWrite(g_v06StateFile,
      "Seq","Time","TriggerTF","TriggerEvent","EpisodeID","State","Direction",
      "BreakTime","BreakLevel","H4BarsSinceBreak",
      "MarketStageH4","MarketStageH1","MarketStageM15",
      "Close","DistanceFromBreakPoints","RetestSeen","H1BOSSeen","H1PatternSeen",
      "BaseBars","BaseHigh","BaseLow","BaseRangePoints","BaseRangeATR",
      "CompressionRatio","UpperTests","LowerTests","FailedBullProbes","FailedBearProbes",
      "BreakBodyPoints","BreakBodyATR","BreakBodyRangeRatio","BreakCloseBeyondPoints",
      "MaxFavorablePoints","MaxAdversePoints",
      "FreshH4BOS","FreshH1BOS","FreshRBR_DBD",
      "StateChanged","ResetReason","Notes");
   FileFlush(g_v06StateFile);
  }

void V06EpisodeHeader()
  {
   FileWrite(g_v06EpisodeFile,
      "EpisodeID","Direction","StartTime","EndTime","EndState","EndReason",
      "BreakLevel","BaseBars","BaseHigh","BaseLow","BaseRangePoints","BaseRangeATR",
      "CompressionRatio","UpperTests","LowerTests","FailedBullProbes","FailedBearProbes",
      "RetestSeen","H1BOSSeen","H1PatternSeen","ExpansionSeen",
      "MaxFavorablePoints","MaxAdversePoints","DurationHours");
   FileFlush(g_v06EpisodeFile);
  }

void V06UpdateExcursions(const double closePrice)
  {
   if(g_v06Direction==0 || g_v06BreakLevel<=0.0) return;

   double fav=0.0,adv=0.0;
   if(g_v06Direction>0)
     {
      fav=StructAurexPoints(closePrice-g_v06BreakLevel);
      adv=StructAurexPoints(g_v06BreakLevel-closePrice);
     }
   else
     {
      fav=StructAurexPoints(g_v06BreakLevel-closePrice);
      adv=StructAurexPoints(closePrice-g_v06BreakLevel);
     }

   if(fav>g_v06MaxFavorablePoints) g_v06MaxFavorablePoints=fav;
   if(adv>g_v06MaxAdversePoints)   g_v06MaxAdversePoints=adv;
  }

void V06WriteState(datetime t,string tf,string ev,MqlRates &bar,
                   bool freshH4BOS,bool freshH1BOS,bool freshPattern,
                   bool changed,string resetReason,string notes)
  {
   MarketPhaseSnapshot h4,h1,m15;
   g_structMP_H4.GetSnapshot(h4);
   g_structMP_H1.GetSnapshot(h1);
   g_structMP_M15.GetSnapshot(m15);

   V06UpdateExcursions(bar.close);

   double dist=0.0;
   if(g_v06Direction!=0 && g_v06BreakLevel>0.0)
      dist=StructAurexPoints(g_v06Direction>0 ?
                            bar.close-g_v06BreakLevel :
                            g_v06BreakLevel-bar.close);

   double body=MathAbs(bar.close-bar.open);
   double range=bar.high-bar.low;
   double atr=(tf=="H4" ? V02ATR(PERIOD_H4) : V02ATR(PERIOD_H1));
   double breakBeyond=0.0;
   if(freshH4BOS && g_v06BreakLevel>0.0)
      breakBeyond=StructAurexPoints(g_v06Direction>0 ?
                                   bar.close-g_v06BreakLevel :
                                   g_v06BreakLevel-bar.close);

   FileWrite(g_v06StateFile,
      ++g_v06EpisodeSeq,
      TimeToString(t,TIME_DATE|TIME_MINUTES),tf,ev,g_v06EpisodeID,
      V06StateName(g_v06State),g_v06Direction,
      TimeToString(g_v06BreakTime,TIME_DATE|TIME_MINUTES),
      DoubleToString(g_v06BreakLevel,_Digits),g_v06H4BarsSinceBreak,
      MarketPhaseName(h4.current_phase),MarketPhaseName(h1.current_phase),MarketPhaseName(m15.current_phase),
      DoubleToString(bar.close,_Digits),DoubleToString(dist,1),
      StructBool(g_v06RetestSeen),StructBool(g_v06H1BOSSeen),StructBool(g_v06H1PatternSeen),
      InpV06BaseLookbackH4Bars,
      DoubleToString(g_v06BaseHigh,_Digits),DoubleToString(g_v06BaseLow,_Digits),
      DoubleToString(g_v06BaseRangePoints,1),DoubleToString(g_v06BaseRangeATR,3),
      DoubleToString(g_v06CompressionRatio,3),g_v06UpperTests,g_v06LowerTests,
      g_v06FailedBullProbes,g_v06FailedBearProbes,
      DoubleToString(StructAurexPoints(body),1),
      DoubleToString(atr>0.0?body/atr:0.0,3),
      DoubleToString(range>0.0?body/range:0.0,3),
      DoubleToString(breakBeyond,1),
      DoubleToString(g_v06MaxFavorablePoints,1),DoubleToString(g_v06MaxAdversePoints,1),
      StructBool(freshH4BOS),StructBool(freshH1BOS),StructBool(freshPattern),
      StructBool(changed),resetReason,notes);
   FileFlush(g_v06StateFile);
  }

void V06CloseEpisode(datetime t,string endReason)
  {
   if(g_v06EpisodeID=="") return;

   double dur=(g_v06EpisodeStart>0 ? (double)(t-g_v06EpisodeStart)/3600.0 : 0.0);
   FileWrite(g_v06EpisodeFile,
      g_v06EpisodeID,g_v06Direction>0?"BULL":"BEAR",
      TimeToString(g_v06EpisodeStart,TIME_DATE|TIME_MINUTES),
      TimeToString(t,TIME_DATE|TIME_MINUTES),
      V06StateName(g_v06State),endReason,
      DoubleToString(g_v06BreakLevel,_Digits),InpV06BaseLookbackH4Bars,
      DoubleToString(g_v06BaseHigh,_Digits),DoubleToString(g_v06BaseLow,_Digits),
      DoubleToString(g_v06BaseRangePoints,1),DoubleToString(g_v06BaseRangeATR,3),
      DoubleToString(g_v06CompressionRatio,3),
      g_v06UpperTests,g_v06LowerTests,g_v06FailedBullProbes,g_v06FailedBearProbes,
      StructBool(g_v06RetestSeen),StructBool(g_v06H1BOSSeen),StructBool(g_v06H1PatternSeen),
      StructBool(g_v06ExpansionSeen),
      DoubleToString(g_v06MaxFavorablePoints,1),DoubleToString(g_v06MaxAdversePoints,1),
      DoubleToString(dur,2));
   FileFlush(g_v06EpisodeFile);
  }

void V06ResetState()
  {
   g_v06State=V06_BALANCE;
   g_v06EpisodeID="";
   g_v06EpisodeStart=0;
   g_v06BreakTime=0;
   g_v06BreakLevel=0.0;
   g_v06Direction=0;
   g_v06H4BarsSinceBreak=0;
   g_v06RetestSeen=false;
   g_v06H1BOSSeen=false;
   g_v06H1PatternSeen=false;
   g_v06ExpansionSeen=false;
   g_v06MaxFavorablePoints=0.0;
   g_v06MaxAdversePoints=0.0;
  }

void V06BeginEpisode(datetime t,int dir,double level,MqlRates &bar,bool freshPattern)
  {
   g_v06Direction=dir;
   g_v06EpisodeStart=t;
   g_v06BreakTime=t;
   g_v06BreakLevel=level;
   g_v06H4BarsSinceBreak=0;
   g_v06RetestSeen=false;
   g_v06H1BOSSeen=false;
   g_v06H1PatternSeen=false;
   g_v06ExpansionSeen=false;
   g_v06MaxFavorablePoints=0.0;
   g_v06MaxAdversePoints=0.0;

   V06CalcBaseMetrics(g_v06BaseHigh,g_v06BaseLow,g_v06BaseRangePoints,
                      g_v06BaseRangeATR,g_v06CompressionRatio,
                      g_v06UpperTests,g_v06LowerTests,
                      g_v06FailedBullProbes,g_v06FailedBearProbes);

   g_v06EpisodeID=V06EpisodeID(t,dir);
   g_v06State=(dir>0 ? V06_BULL_BREAK_ATTEMPT : V06_BEAR_BREAK_ATTEMPT);
   V06WriteState(t,"H4",dir>0?"H4_BULL_BOS":"H4_BEAR_BOS",bar,
                 true,false,freshPattern,true,"","new H4 breakout episode");
  }

void V06OnH4()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H4,0,2,b)<2 || b[0].time==g_v06LastH4) return;
   g_v06LastH4=b[0].time;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H4,sh,sht,sl,slt)) return;

   bool bullBos=(sh>0.0 && b[0].close>sh);
   bool bearBos=(sl>0.0 && b[0].close<sl);

   int nb=0; double bh=0.0,bl=0.0;
   string pat=V02Pattern(PERIOD_H4,nb,bh,bl);
   bool bullPattern=(pat=="RBR");
   bool bearPattern=(pat=="DBD");

   if(g_v06State==V06_BALANCE)
     {
      if(bullBos){V06BeginEpisode(b[0].time,1,sh,b[0],bullPattern); return;}
      if(bearBos){V06BeginEpisode(b[0].time,-1,sl,b[0],bearPattern); return;}
      V06WriteState(b[0].time,"H4","H4_BALANCE_STATE",b[0],false,false,false,false,"",
                    "no active H4 breakout episode");
      return;
     }

   // New opposite H4 BOS ends the current episode and returns to balance.
   if(g_v06Direction>0 && bearBos)
     {
      V06WriteState(b[0].time,"H4","OPPOSITE_H4_BOS",b[0],true,false,bearPattern,false,
                    "OPPOSITE_H4_BOS","episode invalidated");
      V06CloseEpisode(b[0].time,"OPPOSITE_H4_BOS");
      V06ResetState();
      return;
     }
   if(g_v06Direction<0 && bullBos)
     {
      V06WriteState(b[0].time,"H4","OPPOSITE_H4_BOS",b[0],true,false,bullPattern,false,
                    "OPPOSITE_H4_BOS","episode invalidated");
      V06CloseEpisode(b[0].time,"OPPOSITE_H4_BOS");
      V06ResetState();
      return;
     }

   g_v06H4BarsSinceBreak++;

   double retTol=InpV06RetestTolerancePoints/100.0;
   double failTol=InpV06HardFailurePoints/100.0;
   bool withinRetest=false;
   bool hardFail=false;

   if(g_v06Direction>0)
     {
      withinRetest=(b[0].low<=g_v06BreakLevel+retTol &&
                    b[0].close>=g_v06BreakLevel-failTol);
      hardFail=(b[0].close<g_v06BreakLevel-failTol);
     }
   else
     {
      withinRetest=(b[0].high>=g_v06BreakLevel-retTol &&
                    b[0].close<=g_v06BreakLevel+failTol);
      hardFail=(b[0].close>g_v06BreakLevel+failTol);
     }

   if(hardFail)
     {
      V06WriteState(b[0].time,"H4","H4_HARD_FAILURE",b[0],false,false,false,false,
                    "HARD_CLOSE_THROUGH_BREAK","episode failed");
      V06CloseEpisode(b[0].time,"HARD_CLOSE_THROUGH_BREAK");
      V06ResetState();
      return;
     }

   // IMPORTANT V0.6 fix:
   // Retest may only move BREAK_ATTEMPT -> RETEST_HOLD.
   // CONFIRMED/EXPANSION/CONTINUATION are NEVER downgraded by a normal retest.
   bool canEnterRetest=
      (g_v06State==V06_BULL_BREAK_ATTEMPT ||
       g_v06State==V06_BEAR_BREAK_ATTEMPT ||
       g_v06State==V06_BULL_RETEST_HOLD ||
       g_v06State==V06_BEAR_RETEST_HOLD);

   if(withinRetest && g_v06H4BarsSinceBreak<=InpV06MaxRetestH4Bars && canEnterRetest)
     {
      g_v06RetestSeen=true;
      ENUM_V06_STATE old=g_v06State;
      g_v06State=(g_v06Direction>0 ? V06_BULL_RETEST_HOLD : V06_BEAR_RETEST_HOLD);
      V06WriteState(b[0].time,"H4","H4_RETEST_HOLD",b[0],false,false,
                    g_v06Direction>0?bullPattern:bearPattern,
                    g_v06State!=old,"","break boundary retained");
      return;
     }

   // A materially new same-direction H4 BOS starts a NEW episode.
   if(g_v06Direction>0 && bullBos && sh>g_v06BreakLevel+_Point)
     {
      V06WriteState(b[0].time,"H4","H4_NEW_BULL_BOS",b[0],true,false,bullPattern,false,
                    "NEW_SAME_DIRECTION_H4_BOS","close old episode; new structural event");
      V06CloseEpisode(b[0].time,"NEW_SAME_DIRECTION_H4_BOS");
      V06ResetState();
      V06BeginEpisode(b[0].time,1,sh,b[0],bullPattern);
      return;
     }
   if(g_v06Direction<0 && bearBos && sl<g_v06BreakLevel-_Point)
     {
      V06WriteState(b[0].time,"H4","H4_NEW_BEAR_BOS",b[0],true,false,bearPattern,false,
                    "NEW_SAME_DIRECTION_H4_BOS","close old episode; new structural event");
      V06CloseEpisode(b[0].time,"NEW_SAME_DIRECTION_H4_BOS");
      V06ResetState();
      V06BeginEpisode(b[0].time,-1,sl,b[0],bearPattern);
      return;
     }

   // Expansion classification: after confirmation, strong same-direction H4
   // departure or RBR/DBD marks expansion; subsequent fresh structure marks continuation.
   double atr=V02ATR(PERIOD_H4);
   bool strongBull=V02Strong(b[0],atr,true);
   bool strongBear=V02Strong(b[0],atr,false);

   if(g_v06Direction>0 &&
      (g_v06State==V06_BULL_CONFIRMED || g_v06State==V06_BULL_CONTINUATION) &&
      (strongBull || bullPattern))
     {
      bool changed=(g_v06State!=V06_BULL_EXPANSION);
      g_v06State=V06_BULL_EXPANSION;
      g_v06ExpansionSeen=true;
      V06WriteState(b[0].time,"H4","H4_BULL_EXPANSION",b[0],false,false,bullPattern,
                    changed,"","post-confirmation H4 expansion");
      return;
     }

   if(g_v06Direction<0 &&
      (g_v06State==V06_BEAR_CONFIRMED || g_v06State==V06_BEAR_CONTINUATION) &&
      (strongBear || bearPattern))
     {
      bool changed=(g_v06State!=V06_BEAR_EXPANSION);
      g_v06State=V06_BEAR_EXPANSION;
      g_v06ExpansionSeen=true;
      V06WriteState(b[0].time,"H4","H4_BEAR_EXPANSION",b[0],false,false,bearPattern,
                    changed,"","post-confirmation H4 expansion");
      return;
     }

   V06WriteState(b[0].time,"H4","H4_STATE",b[0],false,false,
                 g_v06Direction>0?bullPattern:bearPattern,
                 false,"","episode holds");
  }

void V06OnH1()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H1,0,2,b)<2 || b[0].time==g_v06LastH1) return;
   g_v06LastH1=b[0].time;

   if(g_v06State==V06_BALANCE || g_v06BreakTime==0) return;
   if(b[0].time<=g_v06BreakTime) return;
   if((b[0].time-g_v06BreakTime)>InpV06ConfirmWindowH1Hours*3600) return;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H1,sh,sht,sl,slt)) return;

   bool bullBos=(sh>0.0 && b[0].close>sh);
   bool bearBos=(sl>0.0 && b[0].close<sl);

   int nb=0; double bh=0.0,bl=0.0;
   string pat=V02Pattern(PERIOD_H1,nb,bh,bl);
   bool bullRBR=(pat=="RBR");
   bool bearDBD=(pat=="DBD");

   if(g_v06Direction>0 && bearBos)
     {
      g_v06H1BOSSeen=false;
      g_v06H1PatternSeen=false;
      V06WriteState(b[0].time,"H1","H1_BEAR_CONFLICT",b[0],false,true,bearDBD,false,
                    "","bull confirmation evidence cleared");
      return;
     }

   if(g_v06Direction<0 && bullBos)
     {
      g_v06H1BOSSeen=false;
      g_v06H1PatternSeen=false;
      V06WriteState(b[0].time,"H1","H1_BULL_CONFLICT",b[0],false,true,bullRBR,false,
                    "","bear confirmation evidence cleared");
      return;
     }

   if(g_v06Direction>0)
     {
      if(bullBos) g_v06H1BOSSeen=true;
      if(bullRBR) g_v06H1PatternSeen=true;

      bool eligible=(g_v06State==V06_BULL_BREAK_ATTEMPT ||
                     g_v06State==V06_BULL_RETEST_HOLD);
      bool confirm=(!InpV06RequireH1BOS || g_v06H1BOSSeen) &&
                   (!InpV06AllowH1RBR || g_v06H1PatternSeen || g_v06H1BOSSeen);

      if(eligible && confirm)
        {
         g_v06State=V06_BULL_CONFIRMED;
         V06WriteState(b[0].time,"H1","H1_BULL_CONFIRM",b[0],false,bullBos,bullRBR,
                       true,"","fresh causal H1 confirmation after H4 break");
         return;
        }

      if((g_v06State==V06_BULL_CONFIRMED ||
          g_v06State==V06_BULL_EXPANSION ||
          g_v06State==V06_BULL_CONTINUATION) &&
         (bullBos || bullRBR))
        {
         bool changed=(g_v06State!=V06_BULL_CONTINUATION);
         g_v06State=V06_BULL_CONTINUATION;
         V06WriteState(b[0].time,"H1",bullBos?"H1_BULL_BOS":"H1_RBR",
                       b[0],false,bullBos,bullRBR,changed,"",
                       "fresh bullish continuation event");
         return;
        }
     }
   else
     {
      if(bearBos) g_v06H1BOSSeen=true;
      if(bearDBD) g_v06H1PatternSeen=true;

      bool eligible=(g_v06State==V06_BEAR_BREAK_ATTEMPT ||
                     g_v06State==V06_BEAR_RETEST_HOLD);
      bool confirm=(!InpV06RequireH1BOS || g_v06H1BOSSeen) &&
                   (!InpV06AllowH1RBR || g_v06H1PatternSeen || g_v06H1BOSSeen);

      if(eligible && confirm)
        {
         g_v06State=V06_BEAR_CONFIRMED;
         V06WriteState(b[0].time,"H1","H1_BEAR_CONFIRM",b[0],false,bearBos,bearDBD,
                       true,"","fresh causal H1 confirmation after H4 break");
         return;
        }

      if((g_v06State==V06_BEAR_CONFIRMED ||
          g_v06State==V06_BEAR_EXPANSION ||
          g_v06State==V06_BEAR_CONTINUATION) &&
         (bearBos || bearDBD))
        {
         bool changed=(g_v06State!=V06_BEAR_CONTINUATION);
         g_v06State=V06_BEAR_CONTINUATION;
         V06WriteState(b[0].time,"H1",bearBos?"H1_BEAR_BOS":"H1_DBD",
                       b[0],false,bearBos,bearDBD,changed,"",
                       "fresh bearish continuation event");
         return;
        }
     }
  }

void V06Observe()
  {
   if(!InpStructObsEnable || !g_structMPReady ||
      g_v06StateFile==INVALID_HANDLE || g_v06EpisodeFile==INVALID_HANDLE) return;
   V06OnH4();
   V06OnH1();
  }


//==========================================================================
// [STRUCT-OBS V0.7] TrendEpisode + TrendLeg hierarchy
//
// V0.6 lifecycle logic is treated as FROZEN research context.
// V0.7 adds identity/hierarchy only:
//   TrendEpisodeID -> TrendLegID -> StructureEventID
//
// A same-direction H4 BOS does NOT terminate the TrendEpisode.
// It starts a NEW TrendLeg inside the same episode.
// The TrendEpisode terminates only on opposite H4 BOS or hard structural
// invalidation.
//
// OBSERVER ONLY. No entry, score, UEE, PRME or order changes.
//==========================================================================
int      g_v07File=INVALID_HANDLE;
ulong    g_v07EpisodeSeq=0;
ulong    g_v07LegSeq=0;
ulong    g_v07EventSeq=0;

string   g_v07EpisodeID="";
string   g_v07LegID="";
int      g_v07Direction=0; // +1 bull, -1 bear
datetime g_v07EpisodeStart=0;
datetime g_v07LegStart=0;
datetime g_v07BreakTime=0;
double   g_v07BreakLevel=0.0;
string   g_v07Stage="BALANCE";
int      g_v07LegNumber=0;

datetime g_v07LastH4=0;
datetime g_v07LastH1=0;
bool     g_v07H1Confirmed=false;
bool     g_v07ExpansionSeen=false;
int      g_v07ContinuationCount=0;

string V07EpisodeID(datetime t,int dir)
  {
   return StringFormat("TE_%s_%s_%I64u",
      TimeToString(t,TIME_DATE|TIME_MINUTES),dir>0?"BULL":"BEAR",++g_v07EpisodeSeq);
  }

string V07LegID(datetime t,int legNo)
  {
   return StringFormat("%s_L%02d_%s",g_v07EpisodeID,legNo,
      TimeToString(t,TIME_DATE|TIME_MINUTES));
  }

string V07EventID(datetime t,string type)
  {
   return StringFormat("%s_E%04I64u_%s_%s",
      g_v07EpisodeID,++g_v07EventSeq,type,TimeToString(t,TIME_DATE|TIME_MINUTES));
  }

void V07Header()
  {
   FileWrite(g_v07File,
      "Time","TrendEpisodeID","TrendLegID","StructureEventID",
      "Direction","TrendStage","LegNumber","ContinuationIndex",
      "TriggerTF","EventType",
      "EpisodeStart","LegStart","BreakTime","BreakLevel",
      "H4Stage","H1Stage","M15Stage",
      "Close","DistanceFromBreakPoints",
      "H1Confirmed","ExpansionSeen",
      "EpisodeAction","LegAction","Notes");
   FileFlush(g_v07File);
  }

void V07Write(datetime t,string tf,string eventType,MqlRates &bar,
              string episodeAction,string legAction,string notes)
  {
   if(g_v07File==INVALID_HANDLE) return;
   MarketPhaseSnapshot h4,h1,m15;
   g_structMP_H4.GetSnapshot(h4);
   g_structMP_H1.GetSnapshot(h1);
   g_structMP_M15.GetSnapshot(m15);

   double dist=0.0;
   if(g_v07Direction!=0 && g_v07BreakLevel>0.0)
      dist=StructAurexPoints(g_v07Direction>0 ?
           bar.close-g_v07BreakLevel : g_v07BreakLevel-bar.close);

   FileWrite(g_v07File,
      TimeToString(t,TIME_DATE|TIME_MINUTES),
      g_v07EpisodeID,g_v07LegID,V07EventID(t,eventType),
      g_v07Direction,g_v07Stage,g_v07LegNumber,g_v07ContinuationCount,
      tf,eventType,
      TimeToString(g_v07EpisodeStart,TIME_DATE|TIME_MINUTES),
      TimeToString(g_v07LegStart,TIME_DATE|TIME_MINUTES),
      TimeToString(g_v07BreakTime,TIME_DATE|TIME_MINUTES),
      DoubleToString(g_v07BreakLevel,_Digits),
      MarketPhaseName(h4.current_phase),
      MarketPhaseName(h1.current_phase),
      MarketPhaseName(m15.current_phase),
      DoubleToString(bar.close,_Digits),
      DoubleToString(dist,1),
      StructBool(g_v07H1Confirmed),StructBool(g_v07ExpansionSeen),
      episodeAction,legAction,notes);
   FileFlush(g_v07File);
  }

void V07StartEpisode(datetime t,int dir,double level,MqlRates &bar,string eventType)
  {
   g_v07Direction=dir;
   g_v07EpisodeStart=t;
   g_v07EpisodeID=V07EpisodeID(t,dir);
   g_v07LegNumber=1;
   g_v07LegStart=t;
   g_v07LegID=V07LegID(t,g_v07LegNumber);
   g_v07BreakTime=t;
   g_v07BreakLevel=level;
   g_v07Stage=(dir>0?"BULL_BREAK_ATTEMPT":"BEAR_BREAK_ATTEMPT");
   g_v07H1Confirmed=false;
   g_v07ExpansionSeen=false;
   g_v07ContinuationCount=0;
   V07Write(t,"H4",eventType,bar,"START_EPISODE","START_LEG",
            "new H4 structural hypothesis");
  }

void V07StartNewLeg(datetime t,double level,MqlRates &bar,string eventType)
  {
   g_v07LegNumber++;
   g_v07LegStart=t;
   g_v07LegID=V07LegID(t,g_v07LegNumber);
   g_v07BreakTime=t;
   g_v07BreakLevel=level;
   g_v07Stage=(g_v07Direction>0?"BULL_BREAK_ATTEMPT":"BEAR_BREAK_ATTEMPT");
   g_v07H1Confirmed=false;
   g_v07ExpansionSeen=false;
   g_v07ContinuationCount=0;
   V07Write(t,"H4",eventType,bar,"KEEP_EPISODE","START_NEW_LEG",
            "same-direction H4 BOS creates a new leg inside the existing trend episode");
  }

void V07EndEpisode(datetime t,string reason,MqlRates &bar,string eventType)
  {
   V07Write(t,"H4",eventType,bar,"END_EPISODE","END_LEG",reason);
   g_v07EpisodeID="";
   g_v07LegID="";
   g_v07Direction=0;
   g_v07EpisodeStart=0;
   g_v07LegStart=0;
   g_v07BreakTime=0;
   g_v07BreakLevel=0.0;
   g_v07Stage="BALANCE";
   g_v07LegNumber=0;
   g_v07H1Confirmed=false;
   g_v07ExpansionSeen=false;
   g_v07ContinuationCount=0;
  }

void V07OnH4()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H4,0,2,b)<2 || b[0].time==g_v07LastH4) return;
   g_v07LastH4=b[0].time;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H4,sh,sht,sl,slt)) return;

   bool bullBos=(sh>0.0 && b[0].close>sh);
   bool bearBos=(sl>0.0 && b[0].close<sl);

   int nb=0; double bh=0.0,bl=0.0;
   string pat=V02Pattern(PERIOD_H4,nb,bh,bl);
   bool bullRBR=(pat=="RBR");
   bool bearDBD=(pat=="DBD");

   if(g_v07Direction==0)
     {
      if(bullBos){V07StartEpisode(b[0].time,1,sh,b[0],"H4_BULL_BOS"); return;}
      if(bearBos){V07StartEpisode(b[0].time,-1,sl,b[0],"H4_BEAR_BOS"); return;}
      return;
     }

   // Opposite H4 BOS ends the whole TrendEpisode.
   if(g_v07Direction>0 && bearBos)
     {V07EndEpisode(b[0].time,"OPPOSITE_H4_BOS",b[0],"H4_BEAR_BOS"); return;}
   if(g_v07Direction<0 && bullBos)
     {V07EndEpisode(b[0].time,"OPPOSITE_H4_BOS",b[0],"H4_BULL_BOS"); return;}

   // Hard invalidation also ends the whole TrendEpisode.
   double failTol=InpV07HardFailurePoints/100.0;
   if(g_v07BreakLevel>0.0)
     {
      if(g_v07Direction>0 && b[0].close<g_v07BreakLevel-failTol)
        {V07EndEpisode(b[0].time,"HARD_CLOSE_THROUGH_ACTIVE_LEG_BREAK",b[0],"H4_HARD_FAILURE"); return;}
      if(g_v07Direction<0 && b[0].close>g_v07BreakLevel+failTol)
        {V07EndEpisode(b[0].time,"HARD_CLOSE_THROUGH_ACTIVE_LEG_BREAK",b[0],"H4_HARD_FAILURE"); return;}
     }

   // Same-direction H4 BOS = new leg, NOT new episode.
   if(g_v07Direction>0 && bullBos && sh>g_v07BreakLevel+_Point)
     {V07StartNewLeg(b[0].time,sh,b[0],"H4_NEW_BULL_BOS"); return;}
   if(g_v07Direction<0 && bearBos && sl<g_v07BreakLevel-_Point)
     {V07StartNewLeg(b[0].time,sl,b[0],"H4_NEW_BEAR_BOS"); return;}

   // Post-confirmation H4 displacement/RBR/DBD marks expansion.
   double atr=V02ATR(PERIOD_H4);
   bool strongBull=V02Strong(b[0],atr,true);
   bool strongBear=V02Strong(b[0],atr,false);

   if(g_v07H1Confirmed && g_v07Direction>0 && (strongBull || bullRBR))
     {
      g_v07ExpansionSeen=true;
      g_v07Stage="BULL_EXPANSION";
      V07Write(b[0].time,"H4","H4_BULL_EXPANSION",b[0],
               "KEEP_EPISODE","KEEP_LEG","H4 expansion inside active bullish leg");
      return;
     }

   if(g_v07H1Confirmed && g_v07Direction<0 && (strongBear || bearDBD))
     {
      g_v07ExpansionSeen=true;
      g_v07Stage="BEAR_EXPANSION";
      V07Write(b[0].time,"H4","H4_BEAR_EXPANSION",b[0],
               "KEEP_EPISODE","KEEP_LEG","H4 expansion inside active bearish leg");
      return;
     }
  }

void V07OnH1()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H1,0,2,b)<2 || b[0].time==g_v07LastH1) return;
   g_v07LastH1=b[0].time;

   if(g_v07Direction==0 || g_v07BreakTime==0 || b[0].time<=g_v07BreakTime) return;
   if((b[0].time-g_v07BreakTime)>InpV07ConfirmWindowH1Hours*3600 && !g_v07H1Confirmed) return;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H1,sh,sht,sl,slt)) return;

   bool bullBos=(sh>0.0 && b[0].close>sh);
   bool bearBos=(sl>0.0 && b[0].close<sl);

   int nb=0; double bh=0.0,bl=0.0;
   string pat=V02Pattern(PERIOD_H1,nb,bh,bl);
   bool bullRBR=(pat=="RBR");
   bool bearDBD=(pat=="DBD");

   // Opposite H1 structure degrades the current leg but does not end the episode.
   if(g_v07Direction>0 && bearBos)
     {
      g_v07Stage="BULL_CONFLICT";
      V07Write(b[0].time,"H1","H1_BEAR_CONFLICT",b[0],
               "KEEP_EPISODE","DEGRADE_LEG",
               "opposite H1 BOS inside bullish trend episode");
      return;
     }
   if(g_v07Direction<0 && bullBos)
     {
      g_v07Stage="BEAR_CONFLICT";
      V07Write(b[0].time,"H1","H1_BULL_CONFLICT",b[0],
               "KEEP_EPISODE","DEGRADE_LEG",
               "opposite H1 BOS inside bearish trend episode");
      return;
     }

   // First causal post-H4 confirmation unlocks the trend leg.
   if(!g_v07H1Confirmed)
     {
      bool confirm=false;
      if(g_v07Direction>0)
         confirm=(!InpV07RequireH1BOSForUnlock || bullBos);
      else
         confirm=(!InpV07RequireH1BOSForUnlock || bearBos);

      if(confirm)
        {
         g_v07H1Confirmed=true;
         g_v07Stage=(g_v07Direction>0?"BULL_CONFIRMED":"BEAR_CONFIRMED");
         V07Write(b[0].time,"H1",g_v07Direction>0?"H1_BULL_CONFIRM":"H1_BEAR_CONFIRM",
                  b[0],"UNLOCK_EPISODE_DIRECTION","UNLOCK_LEG",
                  "first causal H1 structural confirmation after H4 BOS");
         return;
        }
     }

   // Every fresh same-direction H1 BOS or RBR/DBD after unlock is a NEW
   // StructureEvent inside the SAME TrendLeg. Later entry research can attach
   // one or more CandidateIDs to these events without losing parent context.
   if(g_v07H1Confirmed)
     {
      bool cont=false;
      string evt="";
      if(g_v07Direction>0 && (bullBos || (InpV07AllowRBRForContinuation && bullRBR)))
        {cont=true;evt=(bullBos?"H1_BULL_BOS_CONT":"H1_RBR_CONT");}
      if(g_v07Direction<0 && (bearBos || (InpV07AllowRBRForContinuation && bearDBD)))
        {cont=true;evt=(bearBos?"H1_BEAR_BOS_CONT":"H1_DBD_CONT");}

      if(cont)
        {
         g_v07ContinuationCount++;
         g_v07Stage=(g_v07Direction>0?"BULL_CONTINUATION":"BEAR_CONTINUATION");
         V07Write(b[0].time,"H1",evt,b[0],
                  "KEEP_EPISODE","KEEP_LEG",
                  "fresh continuation StructureEvent inside active TrendLeg");
         return;
        }
     }
  }

void V07Observe()
  {
   if(!InpStructObsEnable || !g_structMPReady || g_v07File==INVALID_HANDLE) return;
   V07OnH4();
   V07OnH1();
  }


//==========================================================================
// [STRUCT-OBS V0.8] Leg Failure / Episode Unresolved
//
// Core distinction:
//   Entry failure != TrendLeg failure != TrendEpisode failure.
//
// A hard close through the ACTIVE LEG break level:
//   - ends the active TrendLeg,
//   - moves the parent TrendEpisode to EPISODE_UNRESOLVED,
//   - LOCKS new trend entries conceptually,
//   - but DOES NOT terminate the parent TrendEpisode.
//
// Resolution:
//   same-direction H4 BOS -> RECOVER SAME EPISODE, START NEW LEG
//   opposite-direction H4 BOS -> END EPISODE
//
// Observer only. No MarketPhase, entry, UEE, PRME, order, SL/TP changes.
//==========================================================================
enum ENUM_V08_STATE
  {
   V08_BALANCE=0,
   V08_BULL_BREAK_ATTEMPT,
   V08_BULL_CONFIRMED,
   V08_BULL_CONTINUATION,
   V08_BULL_EXPANSION,
   V08_BULL_UNRESOLVED,
   V08_BEAR_BREAK_ATTEMPT,
   V08_BEAR_CONFIRMED,
   V08_BEAR_CONTINUATION,
   V08_BEAR_EXPANSION,
   V08_BEAR_UNRESOLVED
  };

string V08StateName(const ENUM_V08_STATE x)
  {
   switch(x)
     {
      case V08_BALANCE:return "BALANCE";
      case V08_BULL_BREAK_ATTEMPT:return "BULL_BREAK_ATTEMPT";
      case V08_BULL_CONFIRMED:return "BULL_CONFIRMED";
      case V08_BULL_CONTINUATION:return "BULL_CONTINUATION";
      case V08_BULL_EXPANSION:return "BULL_EXPANSION";
      case V08_BULL_UNRESOLVED:return "BULL_EPISODE_UNRESOLVED";
      case V08_BEAR_BREAK_ATTEMPT:return "BEAR_BREAK_ATTEMPT";
      case V08_BEAR_CONFIRMED:return "BEAR_CONFIRMED";
      case V08_BEAR_CONTINUATION:return "BEAR_CONTINUATION";
      case V08_BEAR_EXPANSION:return "BEAR_EXPANSION";
      case V08_BEAR_UNRESOLVED:return "BEAR_EPISODE_UNRESOLVED";
     }
   return "UNKNOWN";
  }

int      g_v08EventFile=INVALID_HANDLE;
int      g_v08ResolutionFile=INVALID_HANDLE;
ENUM_V08_STATE g_v08State=V08_BALANCE;

ulong    g_v08EpisodeSeq=0;
ulong    g_v08LegSeq=0;
ulong    g_v08EventSeq=0;
ulong    g_v08UnresolvedSeq=0;

string   g_v08EpisodeID="";
string   g_v08LegID="";
string   g_v08UnresolvedID="";
int      g_v08Direction=0;
int      g_v08LegNumber=0;

datetime g_v08EpisodeStart=0;
datetime g_v08LegStart=0;
datetime g_v08BreakTime=0;
double   g_v08BreakLevel=0.0;

datetime g_v08LastH4=0;
datetime g_v08LastH1=0;

bool     g_v08H1Confirmed=false;
bool     g_v08ExpansionSeen=false;
int      g_v08ContinuationIndex=0;

// unresolved interval facts
datetime g_v08UnresolvedStart=0;
double   g_v08FailureClose=0.0;
double   g_v08FailedLegBreakLevel=0.0;
int      g_v08UnresolvedH1BullBOS=0;
int      g_v08UnresolvedH1BearBOS=0;
int      g_v08UnresolvedRBR=0;
int      g_v08UnresolvedDBD=0;
double   g_v08UnresolvedMaxFav=0.0;
double   g_v08UnresolvedMaxAdv=0.0;

string V08EpisodeID(datetime t,int dir)
  {
   return StringFormat("TE8_%s_%s_%I64u",
      TimeToString(t,TIME_DATE|TIME_MINUTES),dir>0?"BULL":"BEAR",++g_v08EpisodeSeq);
  }

string V08LegID(datetime t)
  {
   return StringFormat("%s_L%02d_%s",g_v08EpisodeID,g_v08LegNumber,
      TimeToString(t,TIME_DATE|TIME_MINUTES));
  }

string V08EventID(datetime t,string type)
  {
   return StringFormat("%s_EV%05I64u_%s_%s",
      g_v08EpisodeID,++g_v08EventSeq,type,TimeToString(t,TIME_DATE|TIME_MINUTES));
  }

void V08EventHeader()
  {
   FileWrite(g_v08EventFile,
      "Time","TrendEpisodeID","TrendLegID","StructureEventID","UnresolvedID",
      "Direction","State","LegNumber","ContinuationIndex",
      "TriggerTF","EventType",
      "EpisodeStart","LegStart","BreakTime","BreakLevel",
      "H4Stage","H1Stage","M15Stage",
      "Close","DistanceFromActiveLegBreakPoints",
      "H1Confirmed","ExpansionSeen",
      "UnresolvedHours","UnresolvedH1BullBOS","UnresolvedH1BearBOS",
      "UnresolvedRBR","UnresolvedDBD",
      "EpisodeAction","LegAction","EntrySearchState","Notes");
   FileFlush(g_v08EventFile);
  }

void V08ResolutionHeader()
  {
   FileWrite(g_v08ResolutionFile,
      "UnresolvedID","TrendEpisodeID","Direction",
      "UnresolvedStart","ResolutionTime","ResolutionHours",
      "FailedLegNumber","FailedLegBreakLevel","FailureClose",
      "ResolutionType","ResolutionH4Level",
      "H1BullBOSDuringUnresolved","H1BearBOSDuringUnresolved",
      "RBRDuringUnresolved","DBDDuringUnresolved",
      "MaxFavorablePointsDuringUnresolved","MaxAdversePointsDuringUnresolved",
      "EpisodeContinued","NewLegNumber","Notes");
   FileFlush(g_v08ResolutionFile);
  }

void V08UpdateUnresolvedExcursion(double closePrice)
  {
   if(g_v08UnresolvedStart==0 || g_v08FailedLegBreakLevel<=0.0 || g_v08Direction==0) return;
   double fav=0.0,adv=0.0;
   if(g_v08Direction>0)
     {
      fav=StructAurexPoints(closePrice-g_v08FailedLegBreakLevel);
      adv=StructAurexPoints(g_v08FailedLegBreakLevel-closePrice);
     }
   else
     {
      fav=StructAurexPoints(g_v08FailedLegBreakLevel-closePrice);
      adv=StructAurexPoints(closePrice-g_v08FailedLegBreakLevel);
     }
   if(fav>g_v08UnresolvedMaxFav) g_v08UnresolvedMaxFav=fav;
   if(adv>g_v08UnresolvedMaxAdv) g_v08UnresolvedMaxAdv=adv;
  }

void V08Write(datetime t,string tf,string eventType,MqlRates &bar,
              string episodeAction,string legAction,string notes)
  {
   MarketPhaseSnapshot h4,h1,m15;
   g_structMP_H4.GetSnapshot(h4);
   g_structMP_H1.GetSnapshot(h1);
   g_structMP_M15.GetSnapshot(m15);

   V08UpdateUnresolvedExcursion(bar.close);

   double dist=0.0;
   if(g_v08Direction!=0 && g_v08BreakLevel>0.0)
      dist=StructAurexPoints(g_v08Direction>0 ?
           bar.close-g_v08BreakLevel : g_v08BreakLevel-bar.close);

   double unresolvedHours=(g_v08UnresolvedStart>0 ?
      (double)(t-g_v08UnresolvedStart)/3600.0 : 0.0);

   string entrySearchState=
      (g_v08State==V08_BULL_UNRESOLVED || g_v08State==V08_BEAR_UNRESOLVED)
      ? "LOCKED_UNRESOLVED"
      : (g_v08H1Confirmed ? "UNLOCKED" : "LOCKED_WAIT_CONFIRM");

   FileWrite(g_v08EventFile,
      TimeToString(t,TIME_DATE|TIME_MINUTES),
      g_v08EpisodeID,g_v08LegID,V08EventID(t,eventType),g_v08UnresolvedID,
      g_v08Direction,V08StateName(g_v08State),g_v08LegNumber,g_v08ContinuationIndex,
      tf,eventType,
      TimeToString(g_v08EpisodeStart,TIME_DATE|TIME_MINUTES),
      TimeToString(g_v08LegStart,TIME_DATE|TIME_MINUTES),
      TimeToString(g_v08BreakTime,TIME_DATE|TIME_MINUTES),
      DoubleToString(g_v08BreakLevel,_Digits),
      MarketPhaseName(h4.current_phase),MarketPhaseName(h1.current_phase),MarketPhaseName(m15.current_phase),
      DoubleToString(bar.close,_Digits),DoubleToString(dist,1),
      StructBool(g_v08H1Confirmed),StructBool(g_v08ExpansionSeen),
      DoubleToString(unresolvedHours,2),
      g_v08UnresolvedH1BullBOS,g_v08UnresolvedH1BearBOS,g_v08UnresolvedRBR,g_v08UnresolvedDBD,
      episodeAction,legAction,entrySearchState,notes);
   FileFlush(g_v08EventFile);
  }

void V08StartEpisode(datetime t,int dir,double level,MqlRates &bar,string eventType)
  {
   g_v08Direction=dir;
   g_v08EpisodeStart=t;
   g_v08EpisodeID=V08EpisodeID(t,dir);
   g_v08LegNumber=1;
   g_v08LegStart=t;
   g_v08LegID=V08LegID(t);
   g_v08BreakTime=t;
   g_v08BreakLevel=level;
   g_v08State=(dir>0?V08_BULL_BREAK_ATTEMPT:V08_BEAR_BREAK_ATTEMPT);
   g_v08H1Confirmed=false;
   g_v08ExpansionSeen=false;
   g_v08ContinuationIndex=0;
   g_v08UnresolvedID="";
   g_v08UnresolvedStart=0;
   V08Write(t,"H4",eventType,bar,"START_EPISODE","START_LEG","new H4 trend hypothesis");
  }

void V08StartNewLeg(datetime t,double level,MqlRates &bar,string eventType,string notes)
  {
   g_v08LegNumber++;
   g_v08LegStart=t;
   g_v08LegID=V08LegID(t);
   g_v08BreakTime=t;
   g_v08BreakLevel=level;
   g_v08H1Confirmed=false;
   g_v08ExpansionSeen=false;
   g_v08ContinuationIndex=0;
   g_v08State=(g_v08Direction>0?V08_BULL_BREAK_ATTEMPT:V08_BEAR_BREAK_ATTEMPT);
   V08Write(t,"H4",eventType,bar,"KEEP_EPISODE","START_NEW_LEG",notes);
  }

void V08EnterUnresolved(datetime t,MqlRates &bar,string why)
  {
   g_v08UnresolvedStart=t;
   g_v08FailureClose=bar.close;
   g_v08FailedLegBreakLevel=g_v08BreakLevel;
   g_v08UnresolvedID=StringFormat("%s_U%03I64u_%s",
      g_v08EpisodeID,++g_v08UnresolvedSeq,TimeToString(t,TIME_DATE|TIME_MINUTES));
   g_v08UnresolvedH1BullBOS=0;
   g_v08UnresolvedH1BearBOS=0;
   g_v08UnresolvedRBR=0;
   g_v08UnresolvedDBD=0;
   g_v08UnresolvedMaxFav=0.0;
   g_v08UnresolvedMaxAdv=0.0;
   g_v08H1Confirmed=false;
   g_v08ExpansionSeen=false;
   g_v08ContinuationIndex=0;
   g_v08State=(g_v08Direction>0?V08_BULL_UNRESOLVED:V08_BEAR_UNRESOLVED);
   V08Write(t,"H4","H4_LEG_HARD_FAILURE",bar,"KEEP_EPISODE","END_FAILED_LEG",
            why+"; episode unresolved; entry search locked");
  }

void V08WriteResolution(datetime t,string type,double level,bool continued,string notes)
  {
   if(g_v08ResolutionFile==INVALID_HANDLE || g_v08UnresolvedStart==0) return;
   double hrs=(double)(t-g_v08UnresolvedStart)/3600.0;

   FileWrite(g_v08ResolutionFile,
      g_v08UnresolvedID,g_v08EpisodeID,g_v08Direction>0?"BULL":"BEAR",
      TimeToString(g_v08UnresolvedStart,TIME_DATE|TIME_MINUTES),
      TimeToString(t,TIME_DATE|TIME_MINUTES),DoubleToString(hrs,2),
      g_v08LegNumber,DoubleToString(g_v08FailedLegBreakLevel,_Digits),
      DoubleToString(g_v08FailureClose,_Digits),
      type,DoubleToString(level,_Digits),
      g_v08UnresolvedH1BullBOS,g_v08UnresolvedH1BearBOS,
      g_v08UnresolvedRBR,g_v08UnresolvedDBD,
      DoubleToString(g_v08UnresolvedMaxFav,1),DoubleToString(g_v08UnresolvedMaxAdv,1),
      StructBool(continued),continued?g_v08LegNumber+1:0,notes);
   FileFlush(g_v08ResolutionFile);
  }

void V08EndEpisode(datetime t,MqlRates &bar,string eventType,string reason)
  {
   V08Write(t,"H4",eventType,bar,"END_EPISODE","END_LEG",reason);
   g_v08EpisodeID="";
   g_v08LegID="";
   g_v08UnresolvedID="";
   g_v08Direction=0;
   g_v08LegNumber=0;
   g_v08EpisodeStart=0;
   g_v08LegStart=0;
   g_v08BreakTime=0;
   g_v08BreakLevel=0.0;
   g_v08State=V08_BALANCE;
   g_v08H1Confirmed=false;
   g_v08ExpansionSeen=false;
   g_v08ContinuationIndex=0;
   g_v08UnresolvedStart=0;
  }

void V08OnH4()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H4,0,2,b)<2 || b[0].time==g_v08LastH4) return;
   g_v08LastH4=b[0].time;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H4,sh,sht,sl,slt)) return;

   bool bullBos=(sh>0.0 && b[0].close>sh);
   bool bearBos=(sl>0.0 && b[0].close<sl);

   int nb=0; double bh=0.0,bl=0.0;
   string pat=V02Pattern(PERIOD_H4,nb,bh,bl);
   bool bullRBR=(pat=="RBR");
   bool bearDBD=(pat=="DBD");

   if(g_v08Direction==0)
     {
      if(bullBos){V08StartEpisode(b[0].time,1,sh,b[0],"H4_BULL_BOS"); return;}
      if(bearBos){V08StartEpisode(b[0].time,-1,sl,b[0],"H4_BEAR_BOS"); return;}
      return;
     }

   // UNRESOLVED resolution comes before normal active-leg logic.
   if(g_v08State==V08_BULL_UNRESOLVED || g_v08State==V08_BEAR_UNRESOLVED)
     {
      V08UpdateUnresolvedExcursion(b[0].close);

      // Same original direction -> recover SAME episode, NEW leg.
      if(g_v08Direction>0 && bullBos)
        {
         V08WriteResolution(b[0].time,"SAME_DIRECTION_H4_BOS_RECOVERY",sh,true,
                            "parent trend episode resumed with a fresh H4 leg");
         string oldU=g_v08UnresolvedID;
         g_v08UnresolvedID="";
         g_v08UnresolvedStart=0;
         V08StartNewLeg(b[0].time,sh,b[0],"H4_RECOVERY_BULL_BOS",
                        "recovery from "+oldU+"; fresh H1 confirmation required");
         return;
        }
      if(g_v08Direction<0 && bearBos)
        {
         V08WriteResolution(b[0].time,"SAME_DIRECTION_H4_BOS_RECOVERY",sl,true,
                            "parent trend episode resumed with a fresh H4 leg");
         string oldU=g_v08UnresolvedID;
         g_v08UnresolvedID="";
         g_v08UnresolvedStart=0;
         V08StartNewLeg(b[0].time,sl,b[0],"H4_RECOVERY_BEAR_BOS",
                        "recovery from "+oldU+"; fresh H1 confirmation required");
         return;
        }

      // Opposite H4 BOS -> parent episode truly ends.
      if(g_v08Direction>0 && bearBos)
        {
         V08WriteResolution(b[0].time,"OPPOSITE_H4_BOS_REVERSAL",sl,false,
                            "unresolved bullish episode structurally reversed");
         V08EndEpisode(b[0].time,b[0],"H4_BEAR_BOS","episode ended after unresolved reversal");
         return;
        }
      if(g_v08Direction<0 && bullBos)
        {
         V08WriteResolution(b[0].time,"OPPOSITE_H4_BOS_REVERSAL",sh,false,
                            "unresolved bearish episode structurally reversed");
         V08EndEpisode(b[0].time,b[0],"H4_BULL_BOS","episode ended after unresolved reversal");
         return;
        }

      V08Write(b[0].time,"H4","H4_UNRESOLVED_STATE",b[0],
               "KEEP_EPISODE","NO_ACTIVE_LEG","waiting for H4 structural resolution");
      return;
     }

   // Active episode: opposite H4 BOS ends the episode directly.
   if(g_v08Direction>0 && bearBos)
     {V08EndEpisode(b[0].time,b[0],"H4_BEAR_BOS","opposite H4 BOS"); return;}
   if(g_v08Direction<0 && bullBos)
     {V08EndEpisode(b[0].time,b[0],"H4_BULL_BOS","opposite H4 BOS"); return;}

   // Hard failure invalidates the ACTIVE LEG only.
   double failTol=InpV08HardFailurePoints/100.0;
   if(g_v08Direction>0 && b[0].close<g_v08BreakLevel-failTol)
     {V08EnterUnresolved(b[0].time,b[0],"bull leg hard failure"); return;}
   if(g_v08Direction<0 && b[0].close>g_v08BreakLevel+failTol)
     {V08EnterUnresolved(b[0].time,b[0],"bear leg hard failure"); return;}

   // Same-direction H4 BOS -> new leg, same episode.
   if(g_v08Direction>0 && bullBos && sh>g_v08BreakLevel+_Point)
     {V08StartNewLeg(b[0].time,sh,b[0],"H4_NEW_BULL_BOS","same episode; fresh leg"); return;}
   if(g_v08Direction<0 && bearBos && sl<g_v08BreakLevel-_Point)
     {V08StartNewLeg(b[0].time,sl,b[0],"H4_NEW_BEAR_BOS","same episode; fresh leg"); return;}

   // Expansion is a stage inside the active leg.
   double atr=V02ATR(PERIOD_H4);
   if(g_v08H1Confirmed && g_v08Direction>0 && (V02Strong(b[0],atr,true)||bullRBR))
     {
      g_v08ExpansionSeen=true;
      g_v08State=V08_BULL_EXPANSION;
      V08Write(b[0].time,"H4","H4_BULL_EXPANSION",b[0],
               "KEEP_EPISODE","KEEP_LEG","post-confirmation bullish expansion");
      return;
     }
   if(g_v08H1Confirmed && g_v08Direction<0 && (V02Strong(b[0],atr,false)||bearDBD))
     {
      g_v08ExpansionSeen=true;
      g_v08State=V08_BEAR_EXPANSION;
      V08Write(b[0].time,"H4","H4_BEAR_EXPANSION",b[0],
               "KEEP_EPISODE","KEEP_LEG","post-confirmation bearish expansion");
      return;
     }
  }

void V08OnH1()
  {
   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H1,0,2,b)<2 || b[0].time==g_v08LastH1) return;
   g_v08LastH1=b[0].time;

   if(g_v08Direction==0) return;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H1,sh,sht,sl,slt)) return;

   bool bullBos=(sh>0.0 && b[0].close>sh);
   bool bearBos=(sl>0.0 && b[0].close<sl);

   int nb=0; double bh=0.0,bl=0.0;
   string pat=V02Pattern(PERIOD_H1,nb,bh,bl);
   bool bullRBR=(pat=="RBR");
   bool bearDBD=(pat=="DBD");

   // During unresolved, only OBSERVE. Never unlock.
   if(g_v08State==V08_BULL_UNRESOLVED || g_v08State==V08_BEAR_UNRESOLVED)
     {
      if(bullBos) g_v08UnresolvedH1BullBOS++;
      if(bearBos) g_v08UnresolvedH1BearBOS++;
      if(bullRBR) g_v08UnresolvedRBR++;
      if(bearDBD) g_v08UnresolvedDBD++;

      if(bullBos || bearBos || bullRBR || bearDBD)
         V08Write(b[0].time,"H1","H1_UNRESOLVED_EVIDENCE",b[0],
                  "KEEP_EPISODE","NO_ACTIVE_LEG",
                  "evidence recorded only; entry search remains locked");
      return;
     }

   if(g_v08BreakTime==0 || b[0].time<=g_v08BreakTime) return;
   if((b[0].time-g_v08BreakTime)>InpV08ConfirmWindowH1Hours*3600 && !g_v08H1Confirmed) return;

   // Opposite H1 BOS is leg conflict, not episode termination.
   if(g_v08Direction>0 && bearBos)
     {
      V08Write(b[0].time,"H1","H1_BEAR_CONFLICT",b[0],
               "KEEP_EPISODE","DEGRADE_LEG","opposite H1 BOS; parent trend remains");
      return;
     }
   if(g_v08Direction<0 && bullBos)
     {
      V08Write(b[0].time,"H1","H1_BULL_CONFLICT",b[0],
               "KEEP_EPISODE","DEGRADE_LEG","opposite H1 BOS; parent trend remains");
      return;
     }

   // Every fresh leg, including RECOVERY leg, requires fresh H1 confirmation.
   if(!g_v08H1Confirmed)
     {
      bool confirm=(g_v08Direction>0 ? bullBos : bearBos);
      if(!InpV08RequireFreshH1ConfirmAfterRecovery && g_v08LegNumber>1)
         confirm = confirm || (g_v08Direction>0?bullRBR:bearDBD);

      if(confirm)
        {
         g_v08H1Confirmed=true;
         g_v08State=(g_v08Direction>0?V08_BULL_CONFIRMED:V08_BEAR_CONFIRMED);
         V08Write(b[0].time,"H1",g_v08Direction>0?"H1_BULL_CONFIRM":"H1_BEAR_CONFIRM",
                  b[0],"UNLOCK_EPISODE_DIRECTION","UNLOCK_LEG",
                  "fresh causal H1 confirmation for active leg");
         return;
        }
     }

   if(g_v08H1Confirmed)
     {
      bool cont=false; string evt="";
      if(g_v08Direction>0 && (bullBos || bullRBR))
        {cont=true;evt=bullBos?"H1_BULL_BOS_CONT":"H1_RBR_CONT";}
      if(g_v08Direction<0 && (bearBos || bearDBD))
        {cont=true;evt=bearBos?"H1_BEAR_BOS_CONT":"H1_DBD_CONT";}

      if(cont)
        {
         g_v08ContinuationIndex++;
         g_v08State=(g_v08Direction>0?V08_BULL_CONTINUATION:V08_BEAR_CONTINUATION);
         V08Write(b[0].time,"H1",evt,b[0],
                  "KEEP_EPISODE","KEEP_LEG","fresh continuation structure event");
         return;
        }
     }
  }

void V08Observe()
  {
   if(!InpStructObsEnable || !g_structMPReady ||
      g_v08EventFile==INVALID_HANDLE || g_v08ResolutionFile==INVALID_HANDLE) return;
   V08OnH4();
   V08OnH1();
  }


//==========================================================================
// [STRUCT-OBS V0.9] H1 Structural Event Deduplication
//
// Purpose:
//   Prevent persistent structure from masquerading as multiple fresh events.
//
// Rule:
//   - A confirmed swing level may generate ONE BOS event per TrendLeg.
//   - Repeated closes beyond the SAME swing are raw detections, not new events.
//   - A new confirmed swing + break can generate a new BOS event.
//   - RBR/DBD is deduped by its base signature (BaseHigh/BaseLow).
//
// Observer only. No trading changes.
//==========================================================================
int      g_v09File=INVALID_HANDLE;
datetime g_v09LastH1=0;
string   g_v09LastEpisodeID="";
string   g_v09LastLegID="";

double   g_v09LastBullSwingBroken=0.0;
double   g_v09LastBearSwingBroken=0.0;
double   g_v09LastRBRBaseHigh=0.0;
double   g_v09LastRBRBaseLow=0.0;
double   g_v09LastDBDBaseHigh=0.0;
double   g_v09LastDBDBaseLow=0.0;

ulong    g_v09RawBullBOS=0;
ulong    g_v09RawBearBOS=0;
ulong    g_v09FreshBullBOS=0;
ulong    g_v09FreshBearBOS=0;
ulong    g_v09RawRBR=0;
ulong    g_v09RawDBD=0;
ulong    g_v09FreshRBR=0;
ulong    g_v09FreshDBD=0;

bool V09SameLevel(double a,double b)
  {
   if(a<=0.0 || b<=0.0) return false;
   return MathAbs(a-b) <= InpV09LevelEpsilonPoints/100.0;
  }

bool V09SameBase(double ah,double al,double bh,double bl)
  {
   if(!InpV09DedupRBRDBDByBase) return false;
   return V09SameLevel(ah,bh) && V09SameLevel(al,bl);
  }

void V09ResetForLeg()
  {
   g_v09LastBullSwingBroken=0.0;
   g_v09LastBearSwingBroken=0.0;
   g_v09LastRBRBaseHigh=0.0;
   g_v09LastRBRBaseLow=0.0;
   g_v09LastDBDBaseHigh=0.0;
   g_v09LastDBDBaseLow=0.0;
  }

void V09Header()
  {
   FileWrite(g_v09File,
      "Time","TrendEpisodeID","TrendLegID","Direction","V08State",
      "RawEvent","FreshEvent","IsFresh",
      "SwingLevel","BaseHigh","BaseLow",
      "Close","BreakDistancePoints",
      "RawBullBOSCount","FreshBullBOSCount",
      "RawBearBOSCount","FreshBearBOSCount",
      "RawRBRCount","FreshRBRCount",
      "RawDBDCount","FreshDBDCount",
      "EntrySearchState","Notes");
   FileFlush(g_v09File);
  }

void V09Write(datetime t,string rawEvent,string freshEvent,bool fresh,
              double swingLevel,double bh,double bl,MqlRates &bar,string notes)
  {
   double dist=0.0;
   if(swingLevel>0.0)
     {
      if(rawEvent=="H1_BULL_BOS") dist=StructAurexPoints(bar.close-swingLevel);
      if(rawEvent=="H1_BEAR_BOS") dist=StructAurexPoints(swingLevel-bar.close);
     }

   string entrySearchState=
      (g_v08State==V08_BULL_UNRESOLVED || g_v08State==V08_BEAR_UNRESOLVED)
      ? "LOCKED_UNRESOLVED"
      : (g_v08H1Confirmed ? "UNLOCKED" : "LOCKED_WAIT_CONFIRM");

   FileWrite(g_v09File,
      TimeToString(t,TIME_DATE|TIME_MINUTES),
      g_v08EpisodeID,g_v08LegID,g_v08Direction,V08StateName(g_v08State),
      rawEvent,freshEvent,StructBool(fresh),
      DoubleToString(swingLevel,_Digits),
      DoubleToString(bh,_Digits),DoubleToString(bl,_Digits),
      DoubleToString(bar.close,_Digits),DoubleToString(dist,1),
      g_v09RawBullBOS,g_v09FreshBullBOS,
      g_v09RawBearBOS,g_v09FreshBearBOS,
      g_v09RawRBR,g_v09FreshRBR,
      g_v09RawDBD,g_v09FreshDBD,
      entrySearchState,notes);
   FileFlush(g_v09File);
  }

//==========================================================================
// [BTB C5] BEAR -> BULL H1 transition robustness observer
// Research-only. It observes the exact population currently suppressed by
// Family-B ownership: fresh H1 bullish BOS while V08 parent direction is BEAR.
// C5 preserves the C4 observer and executes ONLY the pre-registered A OR B challenger.
// Candidate A: V08 BEAR_CONTINUATION + BOS penetration <= 250 Gold points.
// Candidate B: H1 lower wick >=5% and <10%.
// All qualification uses event-time information only; no forward label is used.
// Existing Family-B execution remains unchanged and is the control population.
//==========================================================================
struct BTBShadowEvent
  {
   ulong    id;
   bool     active;
   datetime eventTime;
   datetime expiryTime;
   string   episodeId;
   string   legId;
   int      parentDirection;
   int      v08State;
   double   entryPrice;
   double   swingLevel;
   double   atrH1;
   double   bosBeyondPts;
   int      legacyH4Trend;
   bool     legacyPullback;
   string   legacyM5Signal;

   // C2 entry-time structural/context features (NO future information)
   string   h4Phase;
   string   h1Phase;
   string   m15Phase;
   double   h1BodyPct;
   double   h1UpperWickPct;
   double   h1LowerWickPct;
   double   h1RecoveryPts;
   double   h1RecoveryATR;
   int      h1BarsSinceRecentLow;
   int      h1PrevBearBars6;
   double   hoursSinceFreshBearBOS;
   double   freshBearBOSLevel;
   double   m15BodyPct;
   bool     m15BreakPrevHigh;
   bool     m15HHHL;
   double   m15RecoveryPts;
   double   m15RecoveryATR;
   double   m5BodyPct;
   bool     m5BreakPrevHigh;
   bool     m5HHHL;
   double   m5RecoveryPts;
   double   m5RecoveryATR;

   // Forward labels/outcomes
   double   mfePts;
   double   maePts;
   string   firstHit;
   datetime firstHitTime;
   bool     parentBullSeen;
  };

int              g_btbFile=INVALID_HANDLE;
int              g_btbMatrixFile=INVALID_HANDLE;
BTBShadowEvent   g_btbEvents[];
ulong            g_btbSeq=0;
datetime         g_btbLastFreshBearBosTime=0;
double           g_btbLastFreshBearBosLevel=0.0;

double BTBRangePct(double num,double den)
  {
   if(den<=0.0) return 0.0;
   return 100.0*num/den;
  }

double BTBAvgTR(ENUM_TIMEFRAMES tf,int firstShift,int bars)
  {
   double sum=0.0; int n=0;
   for(int k=0;k<bars;k++)
     {
      int sh=firstShift+k;
      double hi=iHigh(_Symbol,tf,sh), lo=iLow(_Symbol,tf,sh);
      double prevClose=iClose(_Symbol,tf,sh+1);
      if(hi<=0.0 || lo<=0.0 || prevClose<=0.0) continue;
      double tr=MathMax(hi-lo,MathMax(MathAbs(hi-prevClose),MathAbs(lo-prevClose)));
      sum+=tr; n++;
     }
   return (n>0 ? sum/n : 0.0);
  }

void BTBLTFContext(ENUM_TIMEFRAMES tf,
                   double &bodyPct,bool &breakPrevHigh,bool &hhhl,
                   double &recoveryPts,double &recoveryATR)
  {
   bodyPct=0.0; breakPrevHigh=false; hhhl=false; recoveryPts=0.0; recoveryATR=0.0;
   // Called at the H1 transition detection tick. Shift 1 is therefore the
   // last fully closed lower-TF candle and is safe from look-ahead.
   double o1=iOpen(_Symbol,tf,1), h1=iHigh(_Symbol,tf,1), l1=iLow(_Symbol,tf,1), c1=iClose(_Symbol,tf,1);
   double h2=iHigh(_Symbol,tf,2), l2=iLow(_Symbol,tf,2);
   double h3=iHigh(_Symbol,tf,3), l3=iLow(_Symbol,tf,3);
   if(o1<=0.0 || h1<=0.0 || l1<=0.0 || c1<=0.0) return;
   double range=h1-l1;
   bodyPct=BTBRangePct(MathAbs(c1-o1),range);
   breakPrevHigh=(h2>0.0 && c1>h2);
   hhhl=(h2>0.0 && l2>0.0 && h3>0.0 && l3>0.0 && h1>h2 && l1>l2 && h2>h3 && l2>l3);

   double recentLow=l1;
   for(int k=2;k<=8;k++)
     {
      double lk=iLow(_Symbol,tf,k);
      if(lk>0.0 && (recentLow<=0.0 || lk<recentLow)) recentLow=lk;
     }
   if(recentLow>0.0) recoveryPts=StructAurexPoints(MathMax(0.0,c1-recentLow));
   double atr=BTBAvgTR(tf,1,14);
   recoveryATR=(atr>0.0 ? ((recoveryPts/100.0)/atr) : 0.0);
  }

void BTBH1Context(datetime eventBarTime,double closePrice,BTBShadowEvent &e)
  {
   int sh=iBarShift(_Symbol,PERIOD_H1,eventBarTime,false);
   if(sh<0) sh=1;
   double o=iOpen(_Symbol,PERIOD_H1,sh), h=iHigh(_Symbol,PERIOD_H1,sh), l=iLow(_Symbol,PERIOD_H1,sh), c=iClose(_Symbol,PERIOD_H1,sh);
   if(c<=0.0) c=closePrice;
   double range=h-l;
   e.h1BodyPct=BTBRangePct(MathAbs(c-o),range);
   e.h1UpperWickPct=BTBRangePct(MathMax(0.0,h-MathMax(o,c)),range);
   e.h1LowerWickPct=BTBRangePct(MathMax(0.0,MathMin(o,c)-l),range);

   double recentLow=0.0; int lowK=0;
   for(int k=0;k<12;k++)
     {
      double lk=iLow(_Symbol,PERIOD_H1,sh+k);
      if(lk>0.0 && (recentLow<=0.0 || lk<recentLow)) { recentLow=lk; lowK=k; }
     }
   e.h1BarsSinceRecentLow=lowK;
   e.h1RecoveryPts=(recentLow>0.0 ? StructAurexPoints(MathMax(0.0,c-recentLow)) : 0.0);
   e.h1RecoveryATR=(e.atrH1>0.0 ? ((e.h1RecoveryPts/100.0)/e.atrH1) : 0.0);

   e.h1PrevBearBars6=0;
   for(int k=1;k<=6;k++)
     {
      double ok=iOpen(_Symbol,PERIOD_H1,sh+k), ck=iClose(_Symbol,PERIOD_H1,sh+k);
      if(ok>0.0 && ck>0.0 && ck<ok) e.h1PrevBearBars6++;
     }
  }

void BTBHeader()
  {
   if(g_btbFile==INVALID_HANDLE) return;
   FileWrite(g_btbFile,
      "RecordType","EventID","Time","EpisodeID","LegID","ParentDirection","V08State",
      "EntryPrice","BullSwingLevel","H1ATR","BOSBeyondGoldPts",
      "LegacyH4Trend","LegacyPullback","LegacyM5Signal",
      "H4Phase","H1Phase","M15Phase",
      "H1BodyPct","H1UpperWickPct","H1LowerWickPct","H1RecoveryGoldPts","H1RecoveryATR","H1BarsSinceRecentLow","H1PrevBearBars6",
      "HoursSinceFreshBearBOS","FreshBearBOSLevel",
      "M15BodyPct","M15BreakPrevHigh","M15_HHHL","M15RecoveryGoldPts","M15RecoveryATR",
      "M5BodyPct","M5BreakPrevHigh","M5_HHHL","M5RecoveryGoldPts","M5RecoveryATR",
      "CAND_A_V08CONT_BOSLE200","CAND_B_H1LOWWICK_5_10","CAND_C_BOSLE200_M15RECATRLE3","CAND_D_V08CONT_NOM5HHHL",
      "MFE_GoldPts","MAE_GoldPts","MFE_ATR","MAE_ATR",
      "FirstHit500","FirstHitTime","ParentBullSeen","AgeH1Bars","Reason");
   FileFlush(g_btbFile);
  }

void BTBWrite(const string recordType,const BTBShadowEvent &e,const string reason)
  {
   if(g_btbFile==INVALID_HANDLE) return;
   double mfeAtr=(e.atrH1>0.0 ? (e.mfePts/100.0)/e.atrH1 : 0.0);
   double maeAtr=(e.atrH1>0.0 ? (e.maePts/100.0)/e.atrH1 : 0.0);
   int ageBars=(int)MathMax(0,(TimeCurrent()-e.eventTime)/PeriodSeconds(PERIOD_H1));
   FileWrite(g_btbFile,
      recordType,(long)e.id,TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),
      e.episodeId,e.legId,e.parentDirection,V08StateName((ENUM_V08_STATE)e.v08State),
      DoubleToString(e.entryPrice,_Digits),DoubleToString(e.swingLevel,_Digits),DoubleToString(e.atrH1,_Digits),DoubleToString(e.bosBeyondPts,1),
      e.legacyH4Trend,StructBool(e.legacyPullback),e.legacyM5Signal,
      e.h4Phase,e.h1Phase,e.m15Phase,
      DoubleToString(e.h1BodyPct,1),DoubleToString(e.h1UpperWickPct,1),DoubleToString(e.h1LowerWickPct,1),
      DoubleToString(e.h1RecoveryPts,1),DoubleToString(e.h1RecoveryATR,3),e.h1BarsSinceRecentLow,e.h1PrevBearBars6,
      DoubleToString(e.hoursSinceFreshBearBOS,2),DoubleToString(e.freshBearBOSLevel,_Digits),
      DoubleToString(e.m15BodyPct,1),StructBool(e.m15BreakPrevHigh),StructBool(e.m15HHHL),DoubleToString(e.m15RecoveryPts,1),DoubleToString(e.m15RecoveryATR,3),
      DoubleToString(e.m5BodyPct,1),StructBool(e.m5BreakPrevHigh),StructBool(e.m5HHHL),DoubleToString(e.m5RecoveryPts,1),DoubleToString(e.m5RecoveryATR,3),
      StructBool(e.v08State==(int)V08_BEAR_CONTINUATION && e.bosBeyondPts<=200.0),
      StructBool(e.h1LowerWickPct>=5.0 && e.h1LowerWickPct<=10.0),
      StructBool(e.bosBeyondPts<=200.0 && e.m15RecoveryATR<=3.0),
      StructBool(e.v08State==(int)V08_BEAR_CONTINUATION && !e.m5HHHL),
      DoubleToString(e.mfePts,1),DoubleToString(e.maePts,1),DoubleToString(mfeAtr,3),DoubleToString(maeAtr,3),
      e.firstHit,(e.firstHitTime>0?TimeToString(e.firstHitTime,TIME_DATE|TIME_MINUTES):""),StructBool(e.parentBullSeen),ageBars,reason);
   FileFlush(g_btbFile);
  }


void BTBMatrixHeader()
  {
   if(g_btbMatrixFile==INVALID_HANDLE) return;
   FileWrite(g_btbMatrixFile,
      "EventID","EventTime","EpisodeID","V08State","BOSBeyondGoldPts","H1LowerWickPct","H1RecoveryATR","M15RecoveryATR","M5_HHHL",
      "FirstHit500","MFE_GoldPts","MAE_GoldPts",
      "BOS_LE100","BOS_LE150","BOS_LE200","BOS_LE250","BOS_LE300",
      "CONT_BOS_LE100","CONT_BOS_LE150","CONT_BOS_LE200","CONT_BOS_LE250","CONT_BOS_LE300",
      "WICK_0_5","WICK_5_7P5","WICK_7P5_10","WICK_5_10","WICK_10_15","WICK_15_20","WICK_20_30",
      "H1REC_ATR_1_2","H1REC_ATR_2_3","H1REC_ATR_3_4","H1REC_ATR_4_5",
      "FINAL_A_CONT_BOS_LE250","FINAL_B_WICK_5_10","FINAL_UNION_A_OR_B");
   FileFlush(g_btbMatrixFile);
  }

void BTBMatrixWriteFinal(const BTBShadowEvent &e)
  {
   if(g_btbMatrixFile==INVALID_HANDLE) return;
   bool cont=(e.v08State==(int)V08_BEAR_CONTINUATION);
   bool A=(cont && e.bosBeyondPts<=250.0);
   bool B=(e.h1LowerWickPct>=5.0 && e.h1LowerWickPct<10.0);
   FileWrite(g_btbMatrixFile,
      (long)e.id,TimeToString(e.eventTime,TIME_DATE|TIME_MINUTES),e.episodeId,V08StateName((ENUM_V08_STATE)e.v08State),
      DoubleToString(e.bosBeyondPts,1),DoubleToString(e.h1LowerWickPct,1),DoubleToString(e.h1RecoveryATR,3),DoubleToString(e.m15RecoveryATR,3),StructBool(e.m5HHHL),
      e.firstHit,DoubleToString(e.mfePts,1),DoubleToString(e.maePts,1),
      StructBool(e.bosBeyondPts<=100.0),StructBool(e.bosBeyondPts<=150.0),StructBool(e.bosBeyondPts<=200.0),StructBool(e.bosBeyondPts<=250.0),StructBool(e.bosBeyondPts<=300.0),
      StructBool(cont && e.bosBeyondPts<=100.0),StructBool(cont && e.bosBeyondPts<=150.0),StructBool(cont && e.bosBeyondPts<=200.0),StructBool(cont && e.bosBeyondPts<=250.0),StructBool(cont && e.bosBeyondPts<=300.0),
      StructBool(e.h1LowerWickPct>=0.0 && e.h1LowerWickPct<5.0),StructBool(e.h1LowerWickPct>=5.0 && e.h1LowerWickPct<7.5),StructBool(e.h1LowerWickPct>=7.5 && e.h1LowerWickPct<10.0),StructBool(B),StructBool(e.h1LowerWickPct>=10.0 && e.h1LowerWickPct<15.0),StructBool(e.h1LowerWickPct>=15.0 && e.h1LowerWickPct<20.0),StructBool(e.h1LowerWickPct>=20.0 && e.h1LowerWickPct<30.0),
      StructBool(e.h1RecoveryATR>=1.0 && e.h1RecoveryATR<2.0),StructBool(e.h1RecoveryATR>=2.0 && e.h1RecoveryATR<3.0),StructBool(e.h1RecoveryATR>=3.0 && e.h1RecoveryATR<4.0),StructBool(e.h1RecoveryATR>=4.0 && e.h1RecoveryATR<5.0),
      StructBool(A),StructBool(B),StructBool(A || B));
   FileFlush(g_btbMatrixFile);
  }

void BTBCreateFreshBullAgainstBear(datetime t,double closePrice,double swingLevel)
  {
   if(!InpBTBShadowEnable || g_btbFile==INVALID_HANDLE) return;
   if(g_v08Direction>=0 || g_v08EpisodeID=="") return;

   BTBShadowEvent e;
   ZeroMemory(e);
   g_btbSeq++;
   e.id=(ulong)t*1000+g_btbSeq;
   e.active=true;
   e.eventTime=t;
   e.expiryTime=t+(datetime)(MathMax(1,InpBTBHorizonH1Bars)*PeriodSeconds(PERIOD_H1));
   e.episodeId=g_v08EpisodeID;
   e.legId=g_v08LegID;
   e.parentDirection=g_v08Direction;
   e.v08State=(int)g_v08State;
   e.entryPrice=closePrice;
   e.swingLevel=swingLevel;
   e.atrH1=BTBAvgTR(PERIOD_H1,1,14); // C3 fix: direct closed-H1 ATR context, independent of PRME position state
   e.bosBeyondPts=(swingLevel>0.0 ? StructAurexPoints(MathMax(0.0,closePrice-swingLevel)) : 0.0);
   e.legacyH4Trend=g_last_trend;
   e.legacyPullback=g_last_pullback;
   e.legacyM5Signal=g_last_signal;

   MarketPhaseSnapshot h4s,h1s,m15s;
   g_structMP_H4.GetSnapshot(h4s); g_structMP_H1.GetSnapshot(h1s); g_structMP_M15.GetSnapshot(m15s);
   e.h4Phase=MarketPhaseName(h4s.current_phase);
   e.h1Phase=MarketPhaseName(h1s.current_phase);
   e.m15Phase=MarketPhaseName(m15s.current_phase);

   BTBH1Context(t,closePrice,e);
   e.hoursSinceFreshBearBOS=(g_btbLastFreshBearBosTime>0 ? (double)(t-g_btbLastFreshBearBosTime)/3600.0 : -1.0);
   e.freshBearBOSLevel=g_btbLastFreshBearBosLevel;
   BTBLTFContext(PERIOD_M15,e.m15BodyPct,e.m15BreakPrevHigh,e.m15HHHL,e.m15RecoveryPts,e.m15RecoveryATR);
   BTBLTFContext(PERIOD_M5,e.m5BodyPct,e.m5BreakPrevHigh,e.m5HHHL,e.m5RecoveryPts,e.m5RecoveryATR);

   // C5 pre-registered actual-execution challenger. Qualification uses entry-time data only.
   bool c5A=(InpBTBC5UseCandidateA && e.v08State==(int)V08_BEAR_CONTINUATION &&
             e.bosBeyondPts<=InpBTBC5CandidateABosMaxGoldPts);
   bool c5B=(InpBTBC5UseCandidateB && e.h1LowerWickPct>=InpBTBC5CandidateBWickMinPct &&
             e.h1LowerWickPct<InpBTBC5CandidateBWickMaxPct);
   bool c5Qualified=(InpBTBC5ExecuteTransition && (c5A || c5B));
   if(c5Qualified)
     {
      int sh=iBarShift(_Symbol,PERIOD_H1,t,false);
      if(sh<0) sh=1;
      double sigHi=iHigh(_Symbol,PERIOD_H1,sh);
      double sigLo=iLow(_Symbol,PERIOD_H1,sh);
      string why=StringFormat("BTB_T_%s%s_BOS%.0f_WICK%.1f",c5A?"A":"",c5B?"B":"",e.bosBeyondPts,e.h1LowerWickPct);
      // Priority 4 keeps the transition challenger explicit if another same-bar hypothesis exists.
      V10QueueCandidate("T",4,1,t,sigHi,sigLo,e.episodeId,e.legId,why);
      PrintFormat("[BTB_C5_EXEC] QUEUED id=%I64u A=%s B=%s episode=%s BOS=%.1f wick=%.1f",
                  e.id,c5A?"YES":"NO",c5B?"YES":"NO",e.episodeId,e.bosBeyondPts,e.h1LowerWickPct);
     }

   e.mfePts=0.0; e.maePts=0.0;
   e.firstHit="NONE"; e.firstHitTime=0; e.parentBullSeen=false;

   int n=ArraySize(g_btbEvents);
   ArrayResize(g_btbEvents,n+1);
   g_btbEvents[n]=e;
   BTBWrite("START",g_btbEvents[n],"FRESH_H1_BULL_BOS_WHILE_PARENT_BEAR");
   PrintFormat("[BTB_C5] shadow START id=%I64u episode=%s entry=%.3f swing=%.3f ATR=%.3f H1RecATR=%.2f M15RecATR=%.2f M5RecATR=%.2f",
               e.id,e.episodeId,e.entryPrice,e.swingLevel,e.atrH1,e.h1RecoveryATR,e.m15RecoveryATR,e.m5RecoveryATR);
  }

void BTBUpdate()
  {
   if(!InpBTBShadowEnable || ArraySize(g_btbEvents)==0) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double px=tick.bid; // executable BUY closing side for forward excursion
   datetime now=TimeCurrent();
   double hitPts=MathMax(1.0,InpBTBFirstHitGoldPoints);

   for(int i=0;i<ArraySize(g_btbEvents);i++)
     {
      if(!g_btbEvents[i].active) continue;
      double fav=StructAurexPoints(px-g_btbEvents[i].entryPrice);
      double adv=StructAurexPoints(g_btbEvents[i].entryPrice-px);
      if(fav>g_btbEvents[i].mfePts) g_btbEvents[i].mfePts=fav;
      if(adv>g_btbEvents[i].maePts) g_btbEvents[i].maePts=adv;
      if(g_v08Direction>0) g_btbEvents[i].parentBullSeen=true;

      if(g_btbEvents[i].firstHit=="NONE")
        {
         if(fav>=hitPts)
           {
            g_btbEvents[i].firstHit="TP500_FIRST";
            g_btbEvents[i].firstHitTime=now;
            BTBWrite("FIRST_HIT",g_btbEvents[i],"FAVORABLE_THRESHOLD_REACHED_FIRST");
           }
         else if(adv>=hitPts)
           {
            g_btbEvents[i].firstHit="ADV500_FIRST";
            g_btbEvents[i].firstHitTime=now;
            BTBWrite("FIRST_HIT",g_btbEvents[i],"ADVERSE_THRESHOLD_REACHED_FIRST");
           }
        }

      if(now>=g_btbEvents[i].expiryTime)
        {
         g_btbEvents[i].active=false;
         BTBWrite("FINAL",g_btbEvents[i],"HORIZON_EXPIRED");
         BTBMatrixWriteFinal(g_btbEvents[i]);
        }
     }
  }

void BTBFlushAtEnd()
  {
   if(!InpBTBShadowEnable) return;
   for(int i=0;i<ArraySize(g_btbEvents);i++)
     if(g_btbEvents[i].active)
       {
        g_btbEvents[i].active=false;
        BTBWrite("FINAL",g_btbEvents[i],"TEST_END_OR_DEINIT");
        BTBMatrixWriteFinal(g_btbEvents[i]);
       }
  }

void V09Observe()
  {
   if(!InpStructObsEnable || g_v09File==INVALID_HANDLE) return;

   // Reset dedup memory whenever parent leg identity changes.
   if(g_v08EpisodeID!=g_v09LastEpisodeID || g_v08LegID!=g_v09LastLegID)
     {
      g_v09LastEpisodeID=g_v08EpisodeID;
      g_v09LastLegID=g_v08LegID;
      V09ResetForLeg();
     }

   MqlRates b[2];
   if(CopyRates(_Symbol,PERIOD_H1,0,2,b)<2 || b[0].time==g_v09LastH1) return;
   g_v09LastH1=b[0].time;

   if(g_v08Direction==0 || g_v08EpisodeID=="") return;

   double sh,sl; datetime sht,slt;
   if(!V02Swings(PERIOD_H1,sh,sht,sl,slt)) return;

   bool rawBullBOS=(sh>0.0 && b[0].close>sh);
   bool rawBearBOS=(sl>0.0 && b[0].close<sl);

   int nb=0; double bh=0.0,bl=0.0;
   string pat=V02Pattern(PERIOD_H1,nb,bh,bl);
   bool rawRBR=(pat=="RBR");
   bool rawDBD=(pat=="DBD");

   if(rawBullBOS)
     {
      g_v09RawBullBOS++;
      bool fresh=!V09SameLevel(sh,g_v09LastBullSwingBroken);
      if(fresh)
        {
         g_v09FreshBullBOS++;
         g_v09LastBullSwingBroken=sh;
         if(g_v08Direction<0) BTBCreateFreshBullAgainstBear(b[0].time,b[0].close,sh);
         if(g_v08Direction>0) V10QueueFreshBOS(b[0].time,1,b[0].high,b[0].low);
        }
      V09Write(b[0].time,"H1_BULL_BOS",
               fresh?"H1_BULL_BOS_FRESH":"H1_BULL_BOS_DUP",
               fresh,sh,bh,bl,b[0],
               fresh ? "new confirmed H1 swing high broken" :
                       "same H1 swing high already consumed in this TrendLeg");
     }

   if(rawBearBOS)
     {
      g_v09RawBearBOS++;
      bool fresh=!V09SameLevel(sl,g_v09LastBearSwingBroken);
      if(fresh)
        {
         g_v09FreshBearBOS++;
         g_v09LastBearSwingBroken=sl;
         g_btbLastFreshBearBosTime=b[0].time;
         g_btbLastFreshBearBosLevel=sl;
         if(g_v08Direction<0) V10QueueFreshBOS(b[0].time,-1,b[0].high,b[0].low);
        }
      V09Write(b[0].time,"H1_BEAR_BOS",
               fresh?"H1_BEAR_BOS_FRESH":"H1_BEAR_BOS_DUP",
               fresh,sl,bh,bl,b[0],
               fresh ? "new confirmed H1 swing low broken" :
                       "same H1 swing low already consumed in this TrendLeg");
     }

   if(rawRBR)
     {
      g_v09RawRBR++;
      bool fresh=!V09SameBase(bh,bl,g_v09LastRBRBaseHigh,g_v09LastRBRBaseLow);
      if(fresh)
        {
         g_v09FreshRBR++;
         g_v09LastRBRBaseHigh=bh;
         g_v09LastRBRBaseLow=bl;
         if(g_v08Direction>0) V10QueueFreshPattern(b[0].time,1,b[0].high,b[0].low,"H1_RBR_FRESH");
        }
      V09Write(b[0].time,"H1_RBR",
               fresh?"H1_RBR_FRESH":"H1_RBR_DUP",
               fresh,0.0,bh,bl,b[0],
               fresh ? "new RBR base signature" :
                       "same RBR base already consumed in this TrendLeg");
     }

   if(rawDBD)
     {
      g_v09RawDBD++;
      bool fresh=!V09SameBase(bh,bl,g_v09LastDBDBaseHigh,g_v09LastDBDBaseLow);
      if(fresh)
        {
         g_v09FreshDBD++;
         g_v09LastDBDBaseHigh=bh;
         g_v09LastDBDBaseLow=bl;
         if(g_v08Direction<0) V10QueueFreshPattern(b[0].time,-1,b[0].high,b[0].low,"H1_DBD_FRESH");
        }
      V09Write(b[0].time,"H1_DBD",
               fresh?"H1_DBD_FRESH":"H1_DBD_DUP",
               fresh,0.0,bh,bl,b[0],
               fresh ? "new DBD base signature" :
                       "same DBD base already consumed in this TrendLeg");
     }
  }


//==========================================================================
// [V1.0] First TRADEABLE structural research branch
//
// Families:
// A = first H1 confirmation after a normal H4 TrendLeg
// B = fresh deduplicated same-direction H1 continuation BOS
// C = fresh deduplicated RBR/DBD continuation
// D = first H1 confirmation after an UNRESOLVED episode recovers via H4 BOS
//
// Entry/exit treatment is intentionally frozen across all families:
// - H1 structural signal candle high/low defines pending stop + SL
// - same fixed lot / RR inputs as the parent EA
// - pending signal expires after a fixed M5-bar age
//
// Legacy H4 EMA/pullback entry path is disabled by default.
//==========================================================================

struct V10TradeMap
  {
   long     positionId;
   ulong    candidateId;
   string   family;
   string   episodeId;
   string   legId;
   string   structureEventId;
   int      direction;
   datetime signalTime;
   datetime openTime;
   double   signalPrice;
   double   entryPrice;
   double   sl;
   double   tp;
   double   volume;
   double   closedVolume;
   double   realizedProfit;
   string   entryMode;
   double   atrSignal;
   datetime tp1Time;
   bool     graceDone;
   bool     beApplied;
   bool     beWaitLogged;
   bool     closed;
  };

int       g_v10File=INVALID_HANDLE;
ulong     g_v10CandidateSeq=0;
V10TradeMap g_v10Trades[];

bool      g_v10QueueActive=false;
int       g_v10QueuePriority=0;
string    g_v10QueueFamily="";
int       g_v10QueueDirection=0;
datetime  g_v10QueueSignalTime=0;
double    g_v10QueueHigh=0.0;
double    g_v10QueueLow=0.0;
string    g_v10QueueEpisode="";
string    g_v10QueueLeg="";
string    g_v10QueueEvent="";

bool      g_v10PendingActive=false;
ulong     g_v10PendingCandidateId=0;
string    g_v10PendingFamily="";
string    g_v10PendingEpisode="";
string    g_v10PendingLeg="";
string    g_v10PendingEvent="";
int       g_v10PendingDirection=0;
datetime  g_v10PendingSignalTime=0;
datetime  g_v10PendingPlacedTime=0;
double    g_v10PendingEntry=0.0;
double    g_v10PendingSL=0.0;
double    g_v10PendingTP=0.0;

string    g_v10PrevEpisode="";
string    g_v10PrevLeg="";
ENUM_V08_STATE g_v10PrevV08State=V08_BALANCE;
bool      g_v10PrevH1Confirmed=false;
bool      g_v10CurrentLegRecovery=false;
datetime  g_v10LastQueuedSignalTime=0;


struct B1PendingSlot
  {
   bool active;
   bool localArmed;
   bool actionFailureLogged;
   ulong orderTicket,candidateId,sofTradeObsID;
   string family,episodeId,legId,eventId,entryMode;
   int direction;
   datetime signalTime,placedTime;
   double signalHigh,signalLow,atrSignal,entry,sl,tp,volume;
  };
B1PendingSlot g_b1Pending[];
int g_b1LifecycleFile=INVALID_HANDLE;

void B1LifeHeader()
  {
   if(g_b1LifecycleFile==INVALID_HANDLE) return;
   FileWrite(g_b1LifecycleFile,"Time","Event","CandidateID","OrderTicket","PositionID","EntryMode",
             "ATRSignal","Entry","SL","Volume","TP1Time","OldSL","NewSL","ATRNow","Note");
   FileFlush(g_b1LifecycleFile);
  }
void B1LifeLog(const string ev,const ulong cid,const ulong ord,const long posId,const string mode,
               const double atrSig,const double entry,const double sl,const double vol,const datetime tp1,
               const double oldSL,const double newSL,const double atrNow,const string note)
  {
   if(g_b1LifecycleFile==INVALID_HANDLE) return;
   FileWrite(g_b1LifecycleFile,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),ev,(string)cid,(string)ord,
             (string)posId,mode,DoubleToString(atrSig,_Digits),DoubleToString(entry,_Digits),
             DoubleToString(sl,_Digits),DoubleToString(vol,2),
             (tp1>0?TimeToString(tp1,TIME_DATE|TIME_SECONDS):""),
             DoubleToString(oldSL,_Digits),DoubleToString(newSL,_Digits),DoubleToString(atrNow,_Digits),note);
   FileFlush(g_b1LifecycleFile);
  }
int B1FindPendingByOrder(const ulong ticket)
  {
   for(int i=0;i<ArraySize(g_b1Pending);i++)
      if(g_b1Pending[i].active && g_b1Pending[i].orderTicket==ticket) return i;
   return -1;
  }

bool B1PendingTicketRepresented(const ulong ticket)
  {
   if(ticket==0) return false;
   for(int i=0;i<ArraySize(g_b1Pending);i++)
      if(g_b1Pending[i].active && g_b1Pending[i].orderTicket==ticket) return true;
   return false;
  }

bool B1SlotRepresentedByOpenPosition(const int i)
  {
   if(i<0 || i>=ArraySize(g_b1Pending) || !g_b1Pending[i].active) return false;

   // Preferred path: once an order has filled, MT5 history links that order
   // to its POSITION_ID. If that position is still live, the open-position
   // count already owns the capacity unit.
   ulong orderTicket=g_b1Pending[i].orderTicket;
   if(orderTicket!=0 && HistoryOrderSelect(orderTicket))
     {
      long posId=(long)HistoryOrderGetInteger(orderTicket,ORDER_POSITION_ID);
      if(posId>0 && LD1_PositionStillOpenByIdentifier(posId))
         return true;
     }

   // Immediate market execution can make the position visible before the
   // trade-transaction callback has consumed the registry slot. Match the
   // stable B1 candidate comment as a race-safe fallback.
   string want=StringFormat("B1_%I64u",g_b1Pending[i].candidateId%100000000ULL);
   for(int k=PositionsTotal()-1;k>=0;k--)
     {
      ulong pt=PositionGetTicket(k);
      if(pt==0 || !PositionSelectByTicket(pt)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) continue;
      if(PositionGetString(POSITION_COMMENT)==want) return true;
     }
   return false;
  }

int B1CountActiveEntryReservations()
  {
   int count=0;

   // Active registry slots count only while they are NOT yet represented by
   // a live position. This makes reservation -> position an atomic capacity
   // transition instead of briefly counting the same event twice.
   for(int i=0;i<ArraySize(g_b1Pending);i++)
      if(g_b1Pending[i].active && !B1SlotRepresentedByOpenPosition(i))
         count++;

   // Count broker pendings belonging to this EA that are not represented in
   // the in-memory registry (important after terminal restart/reload).
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool pending=(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_SELL_LIMIT ||
                    type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP ||
                    type==ORDER_TYPE_BUY_STOP_LIMIT || type==ORDER_TYPE_SELL_STOP_LIMIT);
      if(pending && !B1PendingTicketRepresented(ticket)) count++;
     }
   return count;
  }

int B1CountGlobalReservedSlots()
  {
   int openCount=CountResearchOpenPositions();
   int entryReservations=B1CountActiveEntryReservations();
   return openCount+entryReservations;
  }
void B1RegisterPending(const ulong ticket,const ulong cid,const string family,const string ep,const string leg,
                       const string ev,const int dir,const datetime sigTime,const datetime placed,const double hi,
                       const double lo,const double atrSig,const string mode,const double entry,const double sl,
                       const double tp,const double vol,const ulong sofObs)
  {
   int n=ArraySize(g_b1Pending); ArrayResize(g_b1Pending,n+1);
   B1PendingSlot p;
   p.active=true;p.localArmed=(ticket==0);p.actionFailureLogged=false;
   p.orderTicket=ticket;p.candidateId=cid;p.sofTradeObsID=sofObs;p.family=family;p.episodeId=ep;
   p.legId=leg;p.eventId=ev;p.entryMode=mode;p.direction=dir;p.signalTime=sigTime;p.placedTime=placed;
   p.signalHigh=hi;p.signalLow=lo;p.atrSignal=atrSig;p.entry=entry;p.sl=sl;p.tp=tp;p.volume=vol;
   g_b1Pending[n]=p;
  }
bool B1StartSOFObservation(const ulong cid,const double rangeATR,const double plannedEntry,
                           const double lot,const double sl,const double tp,ulong &sofObs)
  {
   sofObs=0;
   if(!g_sofStarted) return true;
   sofObs=g_sof.Trades.TradeBegin(0,SOF_DIR_BUY);
   if(sofObs<=0) return false;
   g_sof.Trades.RecordTrade(sofObs,0,0,SOF_DIR_BUY,SOF_STAGE_ENTRY_SENT,
                            plannedEntry,lot,sl,tp,0,0,0,0,
                            StringFormat("Family-B adaptive candidate=%I64u rangeATR=%.4f",cid,rangeATR));
   return true;
  }

bool B1SubmitBrokerPending(const int i)
  {
   if(i<0 || i>=ArraySize(g_b1Pending) || !g_b1Pending[i].active) return false;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                 SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   bool legal=(g_b1Pending[i].entryMode=="STOP" ? g_b1Pending[i].entry>tick.ask+minDist : g_b1Pending[i].entry<tick.ask-minDist);
   if(!legal) return false;

   string comment=StringFormat("B1_%I64u",g_b1Pending[i].candidateId%100000000ULL);
   bool ok=(g_b1Pending[i].entryMode=="STOP"
            ? g_trade.BuyStop(g_b1Pending[i].volume,g_b1Pending[i].entry,_Symbol,g_b1Pending[i].sl,g_b1Pending[i].tp,ORDER_TIME_GTC,0,comment)
            : g_trade.BuyLimit(g_b1Pending[i].volume,g_b1Pending[i].entry,_Symbol,g_b1Pending[i].sl,g_b1Pending[i].tp,ORDER_TIME_GTC,0,comment));
   if(!ok)
     {
      if(!g_b1Pending[i].actionFailureLogged)
        {
         g_b1Pending[i].actionFailureLogged=true;
         B1LifeLog("PENDING_SUBMIT_FAILED",g_b1Pending[i].candidateId,0,0,g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,g_b1Pending[i].entry,g_b1Pending[i].sl,g_b1Pending[i].volume,
                   0,0,0,0,StringFormat("retcode=%u comment=%s err=%d",
                                        g_trade.ResultRetcode(),g_trade.ResultComment(),GetLastError()));
        }
      return false;
     }

   g_b1Pending[i].orderTicket=g_trade.ResultOrder();
   g_b1Pending[i].localArmed=false;
   g_b1Pending[i].actionFailureLogged=false;
   B1LifeLog("ORDER_PLACED",g_b1Pending[i].candidateId,g_b1Pending[i].orderTicket,0,g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,g_b1Pending[i].entry,g_b1Pending[i].sl,g_b1Pending[i].volume,
             0,0,0,0,StringFormat("broker pending accepted reserved=%d/%d",
                                  B1CountGlobalReservedSlots(),InpMaxPositionSlots));
   if(g_sofStarted && g_b1Pending[i].sofTradeObsID>0)
      g_sof.Trades.RecordTrade(g_b1Pending[i].sofTradeObsID,0,0,SOF_DIR_BUY,SOF_STAGE_MANAGED,
                               g_b1Pending[i].entry,g_b1Pending[i].volume,g_b1Pending[i].sl,g_b1Pending[i].tp,0,0,0,0,
                               StringFormat("PENDING_ACCEPTED ticket=%I64u mode=%s",g_b1Pending[i].orderTicket,g_b1Pending[i].entryMode));
   return true;
  }


double B1GoldPointsToPrice(const double pts)
{
   return MathMax(0.0,pts)/100.0;
}

double B1MinimumFillToSLDistance(const double atrSignal)
{
   double atrFloor=MathMax(0.0,atrSignal)*MathMax(0.0,InpB1MinFillToSL_ATR);
   double absFloor=B1GoldPointsToPrice(InpB1MinFillToSLGoldPoints);
   return MathMax(atrFloor,absFloor);
}

bool B1CrossedLimitGeometryCollapsed(const int i,const double executableAsk,string &diag)
{
   diag="";
   if(i<0 || i>=ArraySize(g_b1Pending) || !g_b1Pending[i].active) return false;
   if(!InpB1RejectCollapsedLimitGeometry) return false;
   if(g_b1Pending[i].entryMode!="LIMIT") return false;

   // This safety applies only after the intended LIMIT has already been crossed.
   if(executableAsk>g_b1Pending[i].entry) return false;

   double remaining=executableAsk-g_b1Pending[i].sl;
   double minAllowed=B1MinimumFillToSLDistance(g_b1Pending[i].atrSignal);

   if(remaining<minAllowed)
   {
      diag=StringFormat("crossed LIMIT geometry collapsed: intended=%.*f ask=%.*f sl=%.*f remaining=%.3f min=%.3f ATRsig=%.3f",
                        _Digits,g_b1Pending[i].entry,
                        _Digits,executableAsk,
                        _Digits,g_b1Pending[i].sl,
                        remaining,minAllowed,g_b1Pending[i].atrSignal);
      return true;
   }
   return false;
}

void B1RejectCollapsedLimit(const int i,const string diag)
{
   if(i<0 || i>=ArraySize(g_b1Pending) || !g_b1Pending[i].active) return;

   B1LifeLog("LIMIT_GEOMETRY_REJECTED",
             g_b1Pending[i].candidateId,
             g_b1Pending[i].orderTicket,0,
             g_b1Pending[i].entryMode,
             g_b1Pending[i].atrSignal,
             g_b1Pending[i].entry,
             g_b1Pending[i].sl,
             g_b1Pending[i].volume,
             0,0,0,0,diag);

   if(g_sofStarted && g_b1Pending[i].sofTradeObsID>0)
      g_sof.Trades.RecordTrade(g_b1Pending[i].sofTradeObsID,0,0,SOF_DIR_BUY,SOF_STAGE_REJECTED,
                               g_b1Pending[i].entry,g_b1Pending[i].volume,g_b1Pending[i].sl,0,
                               0,0,0,0,"RC3C LIMIT_GEOMETRY_REJECTED | "+diag);

   // Permanent retirement of this candidate. Do not keep LOCAL_ARMED waiting
   // for price to recover just enough above the old structural SL.
   g_b1Pending[i].active=false;
   g_b1Pending[i].localArmed=false;
   g_b1Pending[i].orderTicket=0;
}

bool B1ExecuteMarketFromSlot(const int i,const string why)
  {
   if(i<0 || i>=ArraySize(g_b1Pending) || !g_b1Pending[i].active) return false;
   if(!IsSpreadOK()) return false;

   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;

   // RC3C: if a BUY LIMIT has already been crossed but the executable market
   // price has collapsed too close to the original structural SL, the setup
   // geometry is no longer valid. Reject permanently instead of LOCAL_ARMED.
   string geometryDiag="";
   if(B1CrossedLimitGeometryCollapsed(i,tick.ask,geometryDiag))
   {
      B1RejectCollapsedLimit(i,geometryDiag);
      return false;
   }

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                 SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   if(g_b1Pending[i].sl>=tick.bid-minDist)
     {
      if(!g_b1Pending[i].actionFailureLogged)
        {
         g_b1Pending[i].actionFailureLogged=true;
         B1LifeLog("MARKET_WAIT_SL_NOT_VALID",g_b1Pending[i].candidateId,0,0,g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,g_b1Pending[i].entry,g_b1Pending[i].sl,g_b1Pending[i].volume,
                   0,0,0,0,"trigger crossed but structural SL is not broker-valid yet");
        }
      return false;
     }

   string comment=StringFormat("B1_%I64u",g_b1Pending[i].candidateId%100000000ULL);
   if(!g_trade.Buy(g_b1Pending[i].volume,_Symbol,0.0,g_b1Pending[i].sl,g_b1Pending[i].tp,comment))
     {
      if(!g_b1Pending[i].actionFailureLogged)
        {
         g_b1Pending[i].actionFailureLogged=true;
         B1LifeLog("MARKET_EXEC_FAILED",g_b1Pending[i].candidateId,0,0,g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,g_b1Pending[i].entry,g_b1Pending[i].sl,g_b1Pending[i].volume,
                   0,0,0,0,StringFormat("%s | retcode=%u comment=%s err=%d",
                                        why,g_trade.ResultRetcode(),g_trade.ResultComment(),GetLastError()));
        }
      return false;
     }

   g_b1Pending[i].orderTicket=g_trade.ResultOrder();
   g_b1Pending[i].localArmed=false;
   g_b1Pending[i].actionFailureLogged=false;
   int reservedNow=B1CountGlobalReservedSlots();
   B1LifeLog("MARKET_EXECUTED",g_b1Pending[i].candidateId,g_b1Pending[i].orderTicket,0,g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,g_b1Pending[i].entry,g_b1Pending[i].sl,g_b1Pending[i].volume,
             0,0,0,0,StringFormat("%s | intended=%.*f ask=%.*f reserved=%d/%d",
                                  why,_Digits,g_b1Pending[i].entry,_Digits,tick.ask,
                                  reservedNow,InpMaxPositionSlots));
   if(InpMaxPositionSlots>0 && reservedNow>InpMaxPositionSlots)
      B1LifeLog("CAPACITY_INVARIANT_BREACH",g_b1Pending[i].candidateId,g_b1Pending[i].orderTicket,0,
                g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,g_b1Pending[i].entry,g_b1Pending[i].sl,
                g_b1Pending[i].volume,0,0,0,0,
                StringFormat("unique reserved=%d max=%d",reservedNow,InpMaxPositionSlots));
   if(g_sofStarted && g_b1Pending[i].sofTradeObsID>0)
      g_sof.Trades.RecordTrade(g_b1Pending[i].sofTradeObsID,0,0,SOF_DIR_BUY,SOF_STAGE_MANAGED,
                               tick.ask,g_b1Pending[i].volume,g_b1Pending[i].sl,g_b1Pending[i].tp,0,0,0,0,
                               StringFormat("MARKET_TRIGGERED mode=%s intended=%.*f",g_b1Pending[i].entryMode,_Digits,g_b1Pending[i].entry));
   return true;
  }

void B1ProcessLocalArmedEntries()
  {
   if(!InpB1ProductionEnable) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                 SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;

   for(int i=0;i<ArraySize(g_b1Pending);i++)
     {
      if(!g_b1Pending[i].active || !g_b1Pending[i].localArmed || g_b1Pending[i].orderTicket!=0) continue;

      bool crossed=(g_b1Pending[i].entryMode=="LIMIT"
                    ? tick.ask<=g_b1Pending[i].entry
                    : tick.ask>=g_b1Pending[i].entry);
      if(crossed)
        {
         B1ExecuteMarketFromSlot(i,"local armed trigger reached/crossed");
         continue;
        }

      bool legal=(g_b1Pending[i].entryMode=="LIMIT"
                  ? g_b1Pending[i].entry<tick.ask-minDist
                  : g_b1Pending[i].entry>tick.ask+minDist);
      if(legal) B1SubmitBrokerPending(i);
     }
  }

bool B1PlaceAdaptiveOrder(const ulong cid,const string family,const string ep,const string leg,const string ev,
                          const datetime sigTime,const double hi,const double lo,const double legacyStopEntry,
                          const double structuralSL,double &plannedEntry,string &entryMode,ulong &outTicket)
  {
   outTicket=0;plannedEntry=0;entryMode="";
   if(!InpB1ProductionEnable || (family!="B" && family!="T") || B1CountGlobalReservedSlots()>=InpMaxPositionSlots) return false;

   string atrDiag="";
   double atrSig=RC25GetRunnerATR(atrDiag);
   if(atrSig<=0) return false;

   double rangeATR=MathMax(0.0,legacyStopEntry-structuralSL)/atrSig;
   bool useLimit=(rangeATR>=InpB1AdaptiveRangeThresholdATR);
   entryMode=(useLimit?"LIMIT":"STOP");
   plannedEntry=NormalizeDouble(useLimit ? legacyStopEntry-atrSig*InpB1LimitDepthATR : legacyStopEntry,_Digits);

   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                 SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   if(!IsSpreadOK()) return false;

   double lot=InpFixedLot;
   double sl=NormalizeDouble(structuralSL,_Digits),tp=0.0;
   ulong sofObs=0;
   if(!B1StartSOFObservation(cid,rangeATR,plannedEntry,lot,sl,tp,sofObs)) return false;

   bool crossed=(useLimit ? tick.ask<=plannedEntry : tick.ask>=plannedEntry);
   bool pendingLegal=(useLimit ? plannedEntry<tick.ask-minDist : plannedEntry>tick.ask+minDist);

   // Reserve a slot immediately for this independent event.
   B1RegisterPending(0,cid,family,ep,leg,ev,1,sigTime,TimeCurrent(),hi,lo,atrSig,entryMode,
                     plannedEntry,sl,tp,lot,sofObs);
   int pi=ArraySize(g_b1Pending)-1;

   if(crossed)
     {
      bool ok=B1ExecuteMarketFromSlot(pi,useLimit
                                     ? "LIMIT price already reached; current Ask equal/better"
                                     : "STOP trigger already crossed");
      if(ok){outTicket=g_b1Pending[pi].orderTicket;return true;}

      // RC3C geometry rejection permanently deactivates the slot.
      if(!g_b1Pending[pi].active)
         return false;

      g_b1Pending[pi].orderTicket=0;
      g_b1Pending[pi].localArmed=true;
      B1LifeLog("LOCAL_ARMED",cid,0,0,entryMode,atrSig,plannedEntry,sl,lot,0,0,0,0,
                StringFormat("crossed but immediate market unavailable; reserved=%d/%d",
                             B1CountGlobalReservedSlots(),InpMaxPositionSlots));
      return true;
     }

   if(pendingLegal && B1SubmitBrokerPending(pi))
     {
      outTicket=g_b1Pending[pi].orderTicket;
      return true;
     }

   g_b1Pending[pi].orderTicket=0;
   g_b1Pending[pi].localArmed=true;
   B1LifeLog("LOCAL_ARMED",cid,0,0,entryMode,atrSig,plannedEntry,sl,lot,0,0,0,0,
             StringFormat("pending not legal/accepted yet; reserved=%d/%d",
                          B1CountGlobalReservedSlots(),InpMaxPositionSlots));
   if(g_sofStarted && sofObs>0)
      g_sof.Trades.RecordTrade(sofObs,0,0,SOF_DIR_BUY,SOF_STAGE_MANAGED,
                               plannedEntry,lot,sl,tp,0,0,0,0,
                               StringFormat("LOCAL_ARMED mode=%s reserved=%d/%d",
                                            entryMode,B1CountGlobalReservedSlots(),InpMaxPositionSlots));
   return true;
  }

void B1ExpirePendingOrders()
  {
   int maxAge=MathMax(1,InpV10PendingExpiryM5Bars)*PeriodSeconds(PERIOD_M5);
   for(int i=0;i<ArraySize(g_b1Pending);i++)
     {
      if(!g_b1Pending[i].active || TimeCurrent()-g_b1Pending[i].placedTime<maxAge) continue;

      ulong t=g_b1Pending[i].orderTicket;

      if(t==0)
        {
         B1LifeLog("EXPIRED",g_b1Pending[i].candidateId,0,0,g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,
                   g_b1Pending[i].entry,g_b1Pending[i].sl,g_b1Pending[i].volume,0,0,0,0,
                   "local armed freshness expired");
         if(g_sofStarted && g_b1Pending[i].sofTradeObsID>0)
            g_sof.Trades.RecordTrade(g_b1Pending[i].sofTradeObsID,0,0,SOF_DIR_BUY,SOF_STAGE_REJECTED,
                                     g_b1Pending[i].entry,g_b1Pending[i].volume,g_b1Pending[i].sl,0,
                                     0,0,0,0,"local armed expired");
         g_b1Pending[i].active=false;
         continue;
        }

      bool live=false;
      for(int k=OrdersTotal()-1;k>=0;k--)
        if(OrderGetTicket(k)==t){live=true;break;}

      if(live)
        {
         if(!g_trade.OrderDelete(t)) continue;
        }
      else if(HistoryOrderSelect(t))
        {
         ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(t,ORDER_STATE);
         if(state==ORDER_STATE_FILLED || state==ORDER_STATE_PARTIAL)
            continue; // keep mapping alive until deal transaction is processed
        }

      B1LifeLog("EXPIRED",g_b1Pending[i].candidateId,t,0,g_b1Pending[i].entryMode,g_b1Pending[i].atrSignal,
                g_b1Pending[i].entry,g_b1Pending[i].sl,g_b1Pending[i].volume,0,0,0,0,
                "broker pending freshness expired");
      if(g_sofStarted && g_b1Pending[i].sofTradeObsID>0)
         g_sof.Trades.RecordTrade(g_b1Pending[i].sofTradeObsID,0,0,SOF_DIR_BUY,SOF_STAGE_REJECTED,
                                  g_b1Pending[i].entry,g_b1Pending[i].volume,g_b1Pending[i].sl,0,
                                  0,0,0,0,"broker pending expired");
      g_b1Pending[i].active=false;
     }
  }

void B1CancelAllPending()
  {
   for(int i=0;i<ArraySize(g_b1Pending);i++)
     {
      if(!g_b1Pending[i].active) continue;
      ulong t=g_b1Pending[i].orderTicket;
      if(t!=0)
         for(int k=OrdersTotal()-1;k>=0;k--) if(OrderGetTicket(k)==t){g_trade.OrderDelete(t);break;}
      g_b1Pending[i].active=false;
     }
  }
void B1AddTradeFromPending(const int pi,const long positionId,const double fillPrice,const datetime fillTime,const double vol)
  {
   if(pi<0 || pi>=ArraySize(g_b1Pending)) return;
   B1PendingSlot p=g_b1Pending[pi]; int n=ArraySize(g_v10Trades); ArrayResize(g_v10Trades,n+1);
   g_v10Trades[n].positionId=positionId;g_v10Trades[n].candidateId=p.candidateId;g_v10Trades[n].family=p.family;
   g_v10Trades[n].episodeId=p.episodeId;g_v10Trades[n].legId=p.legId;g_v10Trades[n].structureEventId=p.eventId;
   g_v10Trades[n].direction=p.direction;g_v10Trades[n].signalTime=p.signalTime;g_v10Trades[n].openTime=fillTime;
   g_v10Trades[n].signalPrice=p.entry;g_v10Trades[n].entryPrice=fillPrice;g_v10Trades[n].sl=p.sl;g_v10Trades[n].tp=0;
   g_v10Trades[n].volume=vol;g_v10Trades[n].closedVolume=0;g_v10Trades[n].realizedProfit=0;g_v10Trades[n].entryMode=p.entryMode;
   g_v10Trades[n].atrSignal=p.atrSignal;g_v10Trades[n].tp1Time=0;g_v10Trades[n].graceDone=false;g_v10Trades[n].beApplied=false;
   g_v10Trades[n].beWaitLogged=false;g_v10Trades[n].closed=false;
   V10Log("OPEN",p.candidateId,p.family,p.episodeId,p.legId,p.eventId,p.direction,p.signalTime,p.signalHigh,p.signalLow,
          p.entry,p.sl,0,StructAurexPoints(MathAbs(p.entry-p.sl)),p.orderTicket,positionId,fillTime,0,0,0,0,
          "B1 production fill mode="+p.entryMode);
   B1LifeLog("FILLED",p.candidateId,p.orderTicket,positionId,p.entryMode,p.atrSignal,fillPrice,p.sl,vol,0,0,0,0,"");
   if(g_sofStarted && p.sofTradeObsID>0)
     {
      g_sof.Trades.RecordTrade(p.sofTradeObsID,0,positionId,SOF_DIR_BUY,SOF_STAGE_ENTRY_FILLED,
                               fillPrice,vol,p.sl,0,0,0,0,0,"Family-B B1 fill");
      SOF_MapInsertOrUpdate(positionId,p.sofTradeObsID);
     }
   g_b1Pending[pi].active=false;
  }
double B1ProtectedBEPrice(const double entry,const MqlTick &tick)
  {
   // BUY runner protection in canonical XAU price geometry.
   // Entry was paid on Ask; the position exits on Bid. Exact entry is only nominal BE.
   // Protect at entry + current live spread + optional Aurex Gold-point buffer.
   // No account-profit USD/USC calculation is used.
   double spread=MathMax(0.0,tick.ask-tick.bid);
   double extra=MathMax(0.0,InpPRME_BEExtraGoldPoints)/100.0;
   return RC21NormalizeToTick(entry+spread+extra);
  }

void B1ManageProductionRunners()
  {
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT); if(point<=0) return;
   double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                 SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); if(step<=0) step=0.01;
   for(int i=0;i<ArraySize(g_v10Trades);i++)
     {
      if(g_v10Trades[i].closed || (g_v10Trades[i].family!="B" && g_v10Trades[i].family!="T") || g_v10Trades[i].direction<=0) continue;
      long posId=g_v10Trades[i].positionId; ulong ticket=0;
      for(int p=PositionsTotal()-1;p>=0;p--)
        {
         ulong t=PositionGetTicket(p); if(t==0 || !PositionSelectByTicket(t)) continue;
         if((long)PositionGetInteger(POSITION_IDENTIFIER)==posId && PositionGetString(POSITION_SYMBOL)==_Symbol &&
            (int)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber){ticket=t;break;}
        }
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      double intended=g_v10Trades[i].volume*(InpPRME_PartialPct/100.0);
      if(g_v10Trades[i].closedVolume+step*0.25<intended || g_v10Trades[i].tp1Time<=0) continue;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),curSL=PositionGetDouble(POSITION_SL),curTP=PositionGetDouble(POSITION_TP);
      double liveVol=PositionGetDouble(POSITION_VOLUME);
      int effectiveGraceMinutes=InpB1GraceMinutes;
      if(InpBTBC6TImmediateProtectedBE && g_v10Trades[i].family=="T") effectiveGraceMinutes=0;
      if(TimeCurrent()<g_v10Trades[i].tp1Time+(datetime)(effectiveGraceMinutes*60)) continue;
      if(!g_v10Trades[i].graceDone)
        {
         g_v10Trades[i].graceDone=true;
         B1LifeLog("GRACE_DONE",g_v10Trades[i].candidateId,0,posId,g_v10Trades[i].entryMode,g_v10Trades[i].atrSignal,
                   entry,curSL,liveVol,g_v10Trades[i].tp1Time,curSL,curSL,0,
                   StringFormat("effective grace completed family=%s minutes=%d",g_v10Trades[i].family,effectiveGraceMinutes));
        }
      double be=B1ProtectedBEPrice(entry,tick);
      if(curSL<be-point*0.5)
        {
         if(be>=tick.bid-minDist)
           {
            if(!g_v10Trades[i].beWaitLogged)
              {
               g_v10Trades[i].beWaitLogged=true;
               B1LifeLog("BE_WAITING_NOT_VALID",g_v10Trades[i].candidateId,0,posId,g_v10Trades[i].entryMode,
                         g_v10Trades[i].atrSignal,entry,curSL,liveVol,g_v10Trades[i].tp1Time,
                         curSL,be,0,
                         StringFormat("Protected BE not broker-valid | Bid=%.*f MinDist=%.*f",_Digits,tick.bid,_Digits,minDist));
              }
            continue;
           }
         double oldSL=curSL;
         if(!g_trade.PositionModify(ticket,be,curTP))
           {
            B1LifeLog("BE_MODIFY_FAILED",g_v10Trades[i].candidateId,0,posId,g_v10Trades[i].entryMode,
                      g_v10Trades[i].atrSignal,entry,curSL,liveVol,g_v10Trades[i].tp1Time,
                      oldSL,be,0,
                      StringFormat("retcode=%u comment=%s err=%d",
                                   g_trade.ResultRetcode(),g_trade.ResultComment(),GetLastError()));
            continue;
           }
         g_v10Trades[i].beApplied=true;curSL=be;
         B1LifeLog("BE_APPLIED",g_v10Trades[i].candidateId,0,posId,g_v10Trades[i].entryMode,g_v10Trades[i].atrSignal,
                   entry,curSL,liveVol,g_v10Trades[i].tp1Time,oldSL,be,0,
                   g_v10Trades[i].beWaitLogged?"spread-aware floor applied after BE_WAITING_NOT_VALID":"spread-aware floor applied when grace completed");
        }
      string atrDiag="";double atrNow=RC25GetRunnerATR(atrDiag);if(atrNow<=0) continue;
      double candidate=RC21NormalizeToTick(tick.bid-atrNow*InpPRME_ATRTrailMult);
      if(candidate<be) candidate=be;
      if(candidate<=curSL+point*0.5 || candidate>=tick.bid-minDist) continue;
      double oldSL=curSL;
      if(g_trade.PositionModify(ticket,candidate,curTP))
         B1LifeLog("TRAIL_MOVED",g_v10Trades[i].candidateId,0,posId,g_v10Trades[i].entryMode,g_v10Trades[i].atrSignal,
                   entry,candidate,liveVol,g_v10Trades[i].tp1Time,oldSL,candidate,atrNow,"H1 ATR trail");
     }
  }

ulong V10NextCandidateID(datetime t)
  {
   g_v10CandidateSeq++;
   return (ulong)t*1000ULL + (g_v10CandidateSeq%1000ULL);
  }

bool V10DirectionAllowed(int d)
  {
   if(InpV10TradeDirection==0) return true;
   if(InpV10TradeDirection==1) return d>0;
   if(InpV10TradeDirection==2) return d<0;
   return false;
  }

bool V10FamilyEnabled(string f)
  {
   if(f=="A") return InpV10FamilyA_FirstConfirm;
   if(f=="B") return InpV10FamilyB_ContinuationBOS;
   if(f=="C") return InpV10FamilyC_RBRDBD;
   if(f=="D") return InpV10FamilyD_RecoveryConfirm;
   if(f=="T") return InpBTBC5ExecuteTransition;
   return false;
  }

void V10Header()
  {
   FileWrite(g_v10File,
      "Time","Lifecycle","CandidateID","Family","TrendEpisodeID","TrendLegID","StructureEventID",
      "Direction","SignalTime","SignalHigh","SignalLow",
      "Entry","SL","TP","RiskPoints","PendingTicket","PositionID",
      "OpenTime","CloseTime","ExitPrice","MovePoints","ProfitUSD","Reason");
   FileFlush(g_v10File);
  }

void V10Log(string lifecycle,ulong cid,string family,string episode,string leg,string ev,
            int dir,datetime sigTime,double hi,double lo,double entry,double sl,double tp,
            double riskPts,ulong pending,long posId,datetime openTime,datetime closeTime,
            double exitPrice,double movePts,double profit,string reason)
  {
   if(g_v10File==INVALID_HANDLE) return;
   FileWrite(g_v10File,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),lifecycle,(string)cid,family,episode,leg,ev,
      dir,TimeToString(sigTime,TIME_DATE|TIME_MINUTES),
      DoubleToString(hi,_Digits),DoubleToString(lo,_Digits),
      DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),
      DoubleToString(riskPts,1),(string)pending,(string)posId,
      TimeToString(openTime,TIME_DATE|TIME_SECONDS),TimeToString(closeTime,TIME_DATE|TIME_SECONDS),
      DoubleToString(exitPrice,_Digits),DoubleToString(movePts,1),DoubleToString(profit,2),reason);
   FileFlush(g_v10File);
  }

void V10QueueCandidate(string family,int priority,int direction,datetime sigTime,
                       double hi,double lo,string episode,string leg,string ev)
  {
   if(!InpV10EnableTrading || !V10FamilyEnabled(family) || !V10DirectionAllowed(direction)) return;
   if(episode=="" || leg=="") return;
   // C5 transition family intentionally studies ownership while the BEAR parent may still be unresolved.
   if(family!="T" && (g_v08State==V08_BULL_UNRESOLVED || g_v08State==V08_BEAR_UNRESOLVED)) return;

   // One executable hypothesis per closed H1 bar. A/D > B > C.
   if(g_v10QueueActive && g_v10QueueSignalTime==sigTime && priority<=g_v10QueuePriority) return;

   g_v10QueueActive=true;
   g_v10QueuePriority=priority;
   g_v10QueueFamily=family;
   g_v10QueueDirection=direction;
   g_v10QueueSignalTime=sigTime;
   g_v10QueueHigh=hi;
   g_v10QueueLow=lo;
   g_v10QueueEpisode=episode;
   g_v10QueueLeg=leg;
   g_v10QueueEvent=ev;
  }

void V10ObserveConfirmationTransition()
  {
   bool legChanged=(g_v08LegID!=g_v10PrevLeg || g_v08EpisodeID!=g_v10PrevEpisode);

   if(legChanged)
     {
      g_v10CurrentLegRecovery=
         (g_v10PrevEpisode!="" &&
          g_v10PrevEpisode==g_v08EpisodeID &&
          (g_v10PrevV08State==V08_BULL_UNRESOLVED || g_v10PrevV08State==V08_BEAR_UNRESOLVED));
     }

   bool newConfirm=(g_v08H1Confirmed &&
                    (!g_v10PrevH1Confirmed || legChanged));

   if(newConfirm && g_v08Direction!=0)
     {
      MqlRates h1[2];
      if(CopyRates(_Symbol,PERIOD_H1,0,2,h1)>=2)
        {
         string family=g_v10CurrentLegRecovery ? "D" : "A";
         string ev=family=="D" ? "RECOVERY_FIRST_H1_CONFIRM" : "FIRST_H1_CONFIRM";
         V10QueueCandidate(family,3,g_v08Direction,h1[0].time,
                           h1[0].high,h1[0].low,g_v08EpisodeID,g_v08LegID,ev);
        }
     }

   g_v10PrevEpisode=g_v08EpisodeID;
   g_v10PrevLeg=g_v08LegID;
   g_v10PrevV08State=g_v08State;
   g_v10PrevH1Confirmed=g_v08H1Confirmed;
  }

void V10QueueFreshBOS(datetime t,int direction,double hi,double lo)
  {
   if(!g_v08H1Confirmed) return;
   V10QueueCandidate("B",2,direction,t,hi,lo,g_v08EpisodeID,g_v08LegID,
                     direction>0?"H1_BULL_BOS_FRESH":"H1_BEAR_BOS_FRESH");
  }

void V10QueueFreshPattern(datetime t,int direction,double hi,double lo,string pat)
  {
   if(!g_v08H1Confirmed) return;
   V10QueueCandidate("C",1,direction,t,hi,lo,g_v08EpisodeID,g_v08LegID,pat);
  }

int V10FindTrade(long positionId)
  {
   for(int i=0;i<ArraySize(g_v10Trades);i++)
      if(g_v10Trades[i].positionId==positionId && !g_v10Trades[i].closed) return i;
   return -1;
  }

void V10AddTrade(long positionId,double fillPrice,datetime fillTime,double vol)
  {
   if(!g_v10PendingActive) return;

   int n=ArraySize(g_v10Trades);
   ArrayResize(g_v10Trades,n+1);
   g_v10Trades[n].positionId=positionId;
   g_v10Trades[n].candidateId=g_v10PendingCandidateId;
   g_v10Trades[n].family=g_v10PendingFamily;
   g_v10Trades[n].episodeId=g_v10PendingEpisode;
   g_v10Trades[n].legId=g_v10PendingLeg;
   g_v10Trades[n].structureEventId=g_v10PendingEvent;
   g_v10Trades[n].direction=g_v10PendingDirection;
   g_v10Trades[n].signalTime=g_v10PendingSignalTime;
   g_v10Trades[n].openTime=fillTime;
   g_v10Trades[n].signalPrice=g_v10PendingEntry;
   g_v10Trades[n].entryPrice=fillPrice;
   g_v10Trades[n].sl=g_v10PendingSL;
   g_v10Trades[n].tp=g_v10PendingTP;
   g_v10Trades[n].volume=vol;
   g_v10Trades[n].closedVolume=0.0;
   g_v10Trades[n].realizedProfit=0.0;
   g_v10Trades[n].closed=false;

   double riskPts=StructAurexPoints(MathAbs(g_v10PendingEntry-g_v10PendingSL));
   V10Log("OPEN",g_v10PendingCandidateId,g_v10PendingFamily,g_v10PendingEpisode,
          g_v10PendingLeg,g_v10PendingEvent,g_v10PendingDirection,g_v10PendingSignalTime,
          0,0,g_v10PendingEntry,g_v10PendingSL,g_v10PendingTP,riskPts,
          0,positionId,fillTime,0,0,0,0,"filled");

   g_v10PendingActive=false;
   g_v10PendingCandidateId=0;
  }

void V10OnTradeTransaction()
  {
   ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(HistoryDealGetTicket(0),DEAL_ENTRY);
  }

void V10ProcessTradeDeal(ulong deal)
  {
   if(!HistoryDealSelect(deal)) return;
   if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber) return;

   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   long posId=(long)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   double price=HistoryDealGetDouble(deal,DEAL_PRICE);
   double vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
   datetime tm=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);

   if(entry==DEAL_ENTRY_IN)
     {
      if(InpLD1DirectionNeutralPRMEAdopt){g_prme.AdoptPosition(deal,0);LD1ParityLog("PRME_ADOPT_REQUEST",posId,deal,"B1 production entry adoption");}
      ulong orderTicket=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      int pi=B1FindPendingByOrder(orderTicket);
      if(pi>=0){B1AddTradeFromPending(pi,posId,price,tm,vol);return;}
      LD1ParityLog("ENTRY_UNMAPPED",posId,deal,"no B1 pending registry match");
      return;
     }

   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
     {
      int i=V10FindTrade(posId);
      if(i<0)
        {
         LD1ParityLog("EXIT_UNMAPPED",posId,deal,"no V10 map entry");
         return;
        }

      double dealProfit=HistoryDealGetDouble(deal,DEAL_PROFIT)
                       +HistoryDealGetDouble(deal,DEAL_SWAP)
                       +HistoryDealGetDouble(deal,DEAL_COMMISSION)
                       +HistoryDealGetDouble(deal,DEAL_FEE);
      g_v10Trades[i].realizedProfit += dealProfit;
      g_v10Trades[i].closedVolume   += vol;

      double movePts=(g_v10Trades[i].direction>0 ?
         StructAurexPoints(price-g_v10Trades[i].entryPrice) :
         StructAurexPoints(g_v10Trades[i].entryPrice-price));

      double riskPts=StructAurexPoints(MathAbs(g_v10Trades[i].signalPrice-g_v10Trades[i].sl));
      bool stillOpen=LD1_PositionStillOpenByIdentifier(posId);

      if(stillOpen)
        {
         double intended=g_v10Trades[i].volume*(InpPRME_PartialPct/100.0);
         double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(vstep<=0)vstep=0.01;
         if(g_v10Trades[i].tp1Time<=0 && g_v10Trades[i].closedVolume+vstep*0.25>=intended)
           {
            g_v10Trades[i].tp1Time=tm;
            B1LifeLog("TP1_DONE",g_v10Trades[i].candidateId,0,posId,g_v10Trades[i].entryMode,g_v10Trades[i].atrSignal,
                      g_v10Trades[i].entryPrice,g_v10Trades[i].sl,g_v10Trades[i].volume,g_v10Trades[i].tp1Time,
                      0,0,0,StringFormat("50%% partial complete; family=%s effectiveGraceMin=%d",g_v10Trades[i].family,(InpBTBC6TImmediateProtectedBE && g_v10Trades[i].family=="T")?0:InpB1GraceMinutes));
           }
         V10Log("PARTIAL_EXIT",g_v10Trades[i].candidateId,g_v10Trades[i].family,
                g_v10Trades[i].episodeId,g_v10Trades[i].legId,g_v10Trades[i].structureEventId,
                g_v10Trades[i].direction,g_v10Trades[i].signalTime,0,0,
                g_v10Trades[i].signalPrice,g_v10Trades[i].sl,g_v10Trades[i].tp,riskPts,
                0,posId,g_v10Trades[i].openTime,tm,price,movePts,dealProfit,
                StringFormat("partial exit; cumulative=%.2f",g_v10Trades[i].realizedProfit));
         LD1ParityLog("PARTIAL_EXIT",posId,deal,"position remains open");
        }
      else
        {
         V10Log("CLOSE",g_v10Trades[i].candidateId,g_v10Trades[i].family,
                g_v10Trades[i].episodeId,g_v10Trades[i].legId,g_v10Trades[i].structureEventId,
                g_v10Trades[i].direction,g_v10Trades[i].signalTime,0,0,
                g_v10Trades[i].signalPrice,g_v10Trades[i].sl,g_v10Trades[i].tp,riskPts,
                0,posId,g_v10Trades[i].openTime,tm,price,movePts,g_v10Trades[i].realizedProfit,
                StringFormat("FULL_LIFECYCLE closedVolume=%.2f",g_v10Trades[i].closedVolume));
         g_v10Trades[i].closed=true;
         LD1ParityLog("FINAL_EXIT",posId,deal,
                      StringFormat("aggregateProfit=%.2f",g_v10Trades[i].realizedProfit));
        }
     }
  }


//==========================================================================
// [LD1 v1.2] Transactional pending expiry
//
// Only declare the V10 candidate EXPIRED after broker-confirmed deletion.
// If deletion loses a race to a fill, preserve Candidate/Episode mapping so
// OnTradeTransaction can attach the resulting position to the same candidate.
//==========================================================================
bool V12TryExpirePending(const ulong ticket,string &result)
  {
   result="";
   if(ticket==0)
     {
      result="NO_TICKET";
      return false;
     }

   // If still present in the active order pool, attempt a real deletion.
   if(OrderSelect(ticket))
     {
      if(g_trade.OrderDelete(ticket))
        {
         result="DELETED_CONFIRMED";
         return true;
        }

      uint rc=g_trade.ResultRetcode();
      result=StringFormat("DELETE_NOT_CONFIRMED retcode=%u comment=%s",
                          rc,g_trade.ResultComment());

      // IMPORTANT: do not clear V10 identity here. The order can have filled
      // between the lifecycle check and this delete request.
      return false;
     }

   // Not in active orders. Check history to distinguish terminal non-fill
   // from a fill race. A filled order must keep V10 identity alive.
   if(HistoryOrderSelect(ticket))
     {
      ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket,ORDER_STATE);
      if(state==ORDER_STATE_CANCELED || state==ORDER_STATE_EXPIRED || state==ORDER_STATE_REJECTED)
        {
         result=StringFormat("HISTORY_TERMINAL_NONFILL state=%s",EnumToString(state));
         return true;
        }

      if(state==ORDER_STATE_FILLED || state==ORDER_STATE_PARTIAL)
        {
         result=StringFormat("FILL_RACE_PRESERVE_MAPPING state=%s",EnumToString(state));
         return false;
        }

      result=StringFormat("HISTORY_AMBIGUOUS state=%s",EnumToString(state));
      return false;
     }

   result="ORDER_STATE_UNRESOLVED_PRESERVE_MAPPING";
   return false;
  }

void V10ManagePendingExpiry()
  {
   if(!g_v10PendingActive || g_pending_ticket==0 || g_v10PendingPlacedTime==0) return;
   if(InpV10PendingExpiryM5Bars<=0) return;

   int age=(int)((TimeCurrent()-g_v10PendingPlacedTime)/PeriodSeconds(PERIOD_M5));
   if(age<InpV10PendingExpiryM5Bars) return;

   ulong expTicket=g_pending_ticket;
   string expiryResult="";
   bool terminalNonFill=V12TryExpirePending(expTicket,expiryResult);

   if(!terminalNonFill)
     {
      // Preserve candidate identity. On a fill race, OnTradeTransaction will
      // still be able to map the entry deal to Candidate/TrendEpisode/Leg.
      LD1ParityLog("EXPIRY_DEFERRED",0,0,
                   StringFormat("ticket=%I64u %s",expTicket,expiryResult));
      return;
     }

   double riskPts=StructAurexPoints(MathAbs(g_v10PendingEntry-g_v10PendingSL));
   V10Log("EXPIRED",g_v10PendingCandidateId,g_v10PendingFamily,g_v10PendingEpisode,
          g_v10PendingLeg,g_v10PendingEvent,g_v10PendingDirection,g_v10PendingSignalTime,
          0,0,g_v10PendingEntry,g_v10PendingSL,g_v10PendingTP,riskPts,
          expTicket,0,0,0,0,0,0,expiryResult);

   LD1ParityLog("PENDING_EXPIRED_CONFIRMED",0,0,
                StringFormat("ticket=%I64u %s",expTicket,expiryResult));

   // The broker/order-history state is now terminal non-fill. Clear local V10
   // and legacy pending state directly; do NOT send a second OrderDelete().
   if(g_pending_ticket==expTicket)
     {
      g_pending_ticket=0;
      g_pending_direction=0;
      g_order_price=0.0;
      g_stop_loss=0.0;
      g_risk_points=0;
      g_calc_lot=0.0;
      g_risk_money=0.0;
      g_take_profit=0.0;
     }

   g_v10PendingActive=false;
   g_v10PendingCandidateId=0;
   g_v10PendingFamily="";
   g_v10PendingEpisode="";
   g_v10PendingLeg="";
   g_v10PendingEvent="";
   g_v10PendingDirection=0;
   g_v10PendingSignalTime=0;
   g_v10PendingPlacedTime=0;
   g_v10PendingEntry=0.0;
   g_v10PendingSL=0.0;
   g_v10PendingTP=0.0;
  }

void V10ProcessQueuedCandidate()
  {
   if(!g_v10QueueActive) return;
   string family=g_v10QueueFamily;int direction=g_v10QueueDirection;datetime sigTime=g_v10QueueSignalTime;
   double hi=g_v10QueueHigh,lo=g_v10QueueLow;string ep=g_v10QueueEpisode,leg=g_v10QueueLeg,ev=g_v10QueueEvent;
   g_v10QueueActive=false;g_v10QueuePriority=0;
   if(!InpV10EnableTrading || !V10FamilyEnabled(family) || !V10DirectionAllowed(direction)) return;
   if((family!="B" && family!="T") || direction<=0) return;
   ulong cid=V10NextCandidateID(sigTime);double buf=InpV10EntryBufferAurexPoints/100.0;
   double legacyStopEntry=NormalizeDouble(hi+buf,_Digits),sl=NormalizeDouble(lo-buf,_Digits);
   V10Log("CANDIDATE",cid,family,ep,leg,ev,direction,sigTime,hi,lo,legacyStopEntry,sl,0,
          StructAurexPoints(MathAbs(legacyStopEntry-sl)),0,0,0,0,0,0,0,(family=="T" ? "BTB Transition T actual-execution challenger" : "Family-B B1 production candidate"));
   if(InpMaxPositionSlots>0 && B1CountGlobalReservedSlots()>=InpMaxPositionSlots)
     {
      V10Log("SKIP",cid,family,ep,leg,ev,direction,sigTime,hi,lo,legacyStopEntry,sl,0,
             StructAurexPoints(MathAbs(legacyStopEntry-sl)),0,0,0,0,0,0,0,"global MaxOpen reserved-slot limit");
      return;
     }
   double planned=0;string mode="";ulong ticket=0;
   if(B1PlaceAdaptiveOrder(cid,family,ep,leg,ev,sigTime,hi,lo,legacyStopEntry,sl,planned,mode,ticket))
      V10Log("ENTRY_RESERVED",cid,family,ep,leg,ev,direction,sigTime,hi,lo,planned,sl,0,
             StructAurexPoints(MathAbs(planned-sl)),ticket,0,0,0,0,0,0,
             StringFormat("%s adaptive %s reserved=%d/%d",family,mode,B1CountGlobalReservedSlots(),InpMaxPositionSlots));
   else
      V10Log("ORDER_REJECTED",cid,family,ep,leg,ev,direction,sigTime,hi,lo,planned,sl,0,
             StructAurexPoints(MathAbs(planned-sl)),0,0,0,0,0,0,0,(family=="T" ? "BTB T adaptive placement failed" : "B1 adaptive placement failed"));
  }



//==========================================================================
// [1506290] ENTRY + TP/RUNNER SHADOW MATRIX
// Observation only. No additional broker orders are created here.
// For each qualified Family-B BUY signal:
//   Entry modes: existing STOP control + LIMIT at STOP - X*ATR(signal)
//   Protection modes after TP1: BE control + ATR floors 0.10/0.15/0.20/0.25
//   Runner retains current dynamic H1 ATR trail (InpPRME_ATRTrailMult).
//==========================================================================
struct EPRShadowPath
  {
   bool active;
   bool filled;
   bool tp1Done;
   bool closed;
   ulong candidateId;
   datetime signalTime;
   datetime createdTime;
   datetime expiryTime;
   datetime fillTime;
   datetime tp1Time;
   datetime closeTime;
   string entryMode;
   double entryFactor;
   double protectFactor;
   double signalHigh;
   double signalLow;
   double atrSignal;
   double plannedEntry;
   double fillPrice;
   double structuralSL;
   double runnerSL;
   double tp1Move;
   double atrTP1;
   double mfe;
   double mae;
   double peakAfterTP1;
   double exitPrice;
   string exitReason;
  };

int g_eprFile=INVALID_HANDLE;
EPRShadowPath g_eprPaths[];

double H4H1_GoldPointsToPriceMove(const double goldPoints)
  {
   // Aurex canonical broker-independent Gold geometry:
   // 100 Gold points = 1.00 XAU price movement.
   // Example: BUY 4500.00 + 500 Gold points => TP1 price 4505.00.
   // This is NOT an account-profit amount. Account denomination, lot size,
   // contract size, and broker symbol suffix do not change this market distance.
   return MathMax(0.0,goldPoints)/100.0;
  }

double EPR_TP1PriceMove(const double volume)
  {
   // volume intentionally does not affect a market-distance TP1.
   // Kept in the signature so the existing EPR/ADP observer call sites remain unchanged.
   return H4H1_GoldPointsToPriceMove(InpPRME_TP1GoldPoints);
  }

void EPR_Header()
  {
   if(g_eprFile==INVALID_HANDLE) return;
   FileWrite(g_eprFile,
      "Time","Lifecycle","CandidateID","SignalTime","EntryMode","EntryATRFactor","ProtectATRFactor",
      "SignalHigh","SignalLow","ATR_Signal","PlannedEntry","FillPrice","StructuralSL",
      "TP1Move","ATR_TP1","MFE_Price","MAE_Price","PeakAfterTP1","RunnerSL","ExitPrice","ExitReason","Note");
   FileFlush(g_eprFile);
  }

void EPR_Log(const string lifecycle,const EPRShadowPath &p,const string note)
  {
   if(g_eprFile==INVALID_HANDLE) return;
   FileWrite(g_eprFile,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),lifecycle,(string)p.candidateId,
      TimeToString(p.signalTime,TIME_DATE|TIME_MINUTES),p.entryMode,
      DoubleToString(p.entryFactor,2),DoubleToString(p.protectFactor,2),
      DoubleToString(p.signalHigh,_Digits),DoubleToString(p.signalLow,_Digits),DoubleToString(p.atrSignal,_Digits),
      DoubleToString(p.plannedEntry,_Digits),DoubleToString(p.fillPrice,_Digits),DoubleToString(p.structuralSL,_Digits),
      DoubleToString(p.tp1Move,_Digits),DoubleToString(p.atrTP1,_Digits),
      DoubleToString(p.mfe,_Digits),DoubleToString(p.mae,_Digits),DoubleToString(p.peakAfterTP1,_Digits),
      DoubleToString(p.runnerSL,_Digits),DoubleToString(p.exitPrice,_Digits),p.exitReason,note);
   FileFlush(g_eprFile);
  }

void EPR_AddPath(const ulong cid,const datetime sigTime,const datetime created,const string mode,
                 const double entryFactor,const double protectFactor,const double hi,const double lo,
                 const double atrSignal,const double plannedEntry,const double structuralSL)
  {
   int n=ArraySize(g_eprPaths);
   ArrayResize(g_eprPaths,n+1);
   EPRShadowPath p;
   p.active=true; p.filled=false; p.tp1Done=false; p.closed=false;
   p.candidateId=cid; p.signalTime=sigTime; p.createdTime=created;
   p.expiryTime=created + (datetime)(MathMax(1,InpV10PendingExpiryM5Bars)*PeriodSeconds(PERIOD_M5));
   p.fillTime=0; p.tp1Time=0; p.closeTime=0;
   p.entryMode=mode; p.entryFactor=entryFactor; p.protectFactor=protectFactor;
   p.signalHigh=hi; p.signalLow=lo; p.atrSignal=atrSignal;
   p.plannedEntry=NormalizeDouble(plannedEntry,_Digits); p.fillPrice=0.0;
   p.structuralSL=NormalizeDouble(structuralSL,_Digits); p.runnerSL=p.structuralSL;
   p.tp1Move=EPR_TP1PriceMove(InpFixedLot); p.atrTP1=0.0;
   p.mfe=0.0; p.mae=0.0; p.peakAfterTP1=0.0; p.exitPrice=0.0; p.exitReason="";
   g_eprPaths[n]=p;
   EPR_Log("ARMED",g_eprPaths[n],"shadow only; same Family-B signal");
  }

void EPR_ArmFamilyB(const ulong cid,const datetime sigTime,const double hi,const double lo,
                    const double stopEntry,const double structuralSL)
  {
   if(!InpEPRShadowEnable) return;
   string diag="";
   double atr=RC25GetRunnerATR(diag);
   if(atr<=0.0)
     {
      Print("[1506491 EPR] ATR unavailable at signal | ",diag);
      return;
     }
   double entryFactors[6]={-1.0,InpEPRLimitATR_1,InpEPRLimitATR_2,InpEPRLimitATR_3,InpEPRLimitATR_4,InpEPRLimitATR_5};
   double protectFactors[5]={InpEPRProtectATR_0,InpEPRProtectATR_1,InpEPRProtectATR_2,InpEPRProtectATR_3,InpEPRProtectATR_4};
   datetime now=TimeCurrent();
   for(int e=0;e<6;e++)
     {
      string mode=(e==0 ? "STOP" : "LIMIT");
      double planned=(e==0 ? stopEntry : stopEntry-atr*entryFactors[e]);
      if(planned<=structuralSL) continue;
      for(int p=0;p<5;p++)
         EPR_AddPath(cid,sigTime,now,mode,(e==0?0.0:entryFactors[e]),protectFactors[p],hi,lo,atr,planned,structuralSL);
     }

   // [1506290 v0.2] Fully wired adaptive-entry/delayed-protection matrix.
   ADP_ArmFamilyB(cid,sigTime,hi,lo,stopEntry,structuralSL);
  }

void EPR_ClosePath(const int i,const double price,const string reason,const string note)
  {
   g_eprPaths[i].closed=true; g_eprPaths[i].active=false; g_eprPaths[i].closeTime=TimeCurrent();
   g_eprPaths[i].exitPrice=price; g_eprPaths[i].exitReason=reason;
   EPR_Log("CLOSED",g_eprPaths[i],note);
  }

void EPR_Update()
  {
   if(!InpEPRShadowEnable || ArraySize(g_eprPaths)==0) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT); if(point<=0.0) return;
   long stopsPts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezePts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minStopDist=(double)MathMax(stopsPts,freezePts)*point;

   for(int i=0;i<ArraySize(g_eprPaths);i++)
     {
      if(!g_eprPaths[i].active || g_eprPaths[i].closed) continue;

      if(!g_eprPaths[i].filled)
        {
         if(TimeCurrent()>g_eprPaths[i].expiryTime)
           { EPR_ClosePath(i,0.0,"NOT_FILLED_EXPIRED","same expiry as real pending setup"); continue; }

         bool fill=false;
         if(g_eprPaths[i].entryMode=="STOP") fill=(tick.ask>=g_eprPaths[i].plannedEntry);
         else fill=(tick.ask<=g_eprPaths[i].plannedEntry);
         if(!fill) continue;

         g_eprPaths[i].filled=true; g_eprPaths[i].fillTime=TimeCurrent();
         // Conservative executable fill: STOP can gap worse; LIMIT can receive price improvement.
         g_eprPaths[i].fillPrice=(g_eprPaths[i].entryMode=="STOP" ?
                                  MathMax(g_eprPaths[i].plannedEntry,tick.ask) :
                                  MathMin(g_eprPaths[i].plannedEntry,tick.ask));
         g_eprPaths[i].fillPrice=NormalizeDouble(g_eprPaths[i].fillPrice,_Digits);
         g_eprPaths[i].runnerSL=g_eprPaths[i].structuralSL;
         EPR_Log("FILLED",g_eprPaths[i],"shadow executable BUY fill");
        }

      double fav=tick.bid-g_eprPaths[i].fillPrice;
      double adv=g_eprPaths[i].fillPrice-tick.bid;
      if(fav>g_eprPaths[i].mfe) g_eprPaths[i].mfe=fav;
      if(adv>g_eprPaths[i].mae) g_eprPaths[i].mae=adv;

      if(!g_eprPaths[i].tp1Done)
        {
         if(tick.bid<=g_eprPaths[i].structuralSL)
           { EPR_ClosePath(i,tick.bid,"INITIAL_SL","SL before TP1"); continue; }
         if(g_eprPaths[i].tp1Move>0.0 && fav>=g_eprPaths[i].tp1Move)
           {
            g_eprPaths[i].tp1Done=true; g_eprPaths[i].tp1Time=TimeCurrent();
            string d=""; g_eprPaths[i].atrTP1=RC25GetRunnerATR(d);
            if(g_eprPaths[i].atrTP1<=0.0) g_eprPaths[i].atrTP1=g_eprPaths[i].atrSignal;
            // Current real policy attempts BE after partial, subject to broker-valid distance.
            if(g_eprPaths[i].fillPrice<tick.bid-minStopDist)
               g_eprPaths[i].runnerSL=MathMax(g_eprPaths[i].runnerSL,g_eprPaths[i].fillPrice);
            EPR_Log("TP1_DONE",g_eprPaths[i],"50% partial assumed; ATR frozen for permanent floor");
           }
         continue;
        }

      double after=tick.bid-g_eprPaths[i].fillPrice;
      if(after>g_eprPaths[i].peakAfterTP1) g_eprPaths[i].peakAfterTP1=after;

      // Permanent floor: only becomes actionable once broker-valid.
      double floorSL=g_eprPaths[i].fillPrice+g_eprPaths[i].atrTP1*g_eprPaths[i].protectFactor;
      if(floorSL<tick.bid-minStopDist && floorSL>g_eprPaths[i].runnerSL)
         g_eprPaths[i].runnerSL=RC21NormalizeToTick(floorSL);

      // Existing trend runner remains current H1 ATR * InpPRME_ATRTrailMult.
      if(InpEPRUseCurrentTrail)
        {
         string d=""; double atrNow=RC25GetRunnerATR(d);
         if(atrNow>0.0)
           {
            double trail=RC21NormalizeToTick(tick.bid-atrNow*InpPRME_ATRTrailMult);
            if(trail<g_eprPaths[i].fillPrice) trail=g_eprPaths[i].fillPrice;
            if(trail<tick.bid-minStopDist && trail>g_eprPaths[i].runnerSL)
               g_eprPaths[i].runnerSL=trail;
           }
        }

      if(tick.bid<=g_eprPaths[i].runnerSL+point*0.5)
        { EPR_ClosePath(i,tick.bid,"RUNNER_SL","post-TP1 protected runner exit"); continue; }
     }
  }

void EPR_FlushOpenAtEnd()
  {
   for(int i=0;i<ArraySize(g_eprPaths);i++)
     {
      if(!g_eprPaths[i].active || g_eprPaths[i].closed) continue;
      g_eprPaths[i].exitReason="TEST_END_OPEN";
      EPR_Log("TEST_END_OPEN",g_eprPaths[i],"path unresolved at deinit");
     }
  }


//==========================================================================
// [1506290 v0.2] ADAPTIVE ENTRY + DELAYED RUNNER PROTECTION SHADOW
// Fully wired shadow lifecycle. NO broker orders or PositionModify calls.
// For each Family-B signal:
//   - adaptive threshold selects STOP or LIMIT(-0.25*ATRsignal)
//   - TP1/50% partial is simulated from the same USD trigger geometry
//   - BE is the immediate post-TP1 control (same as baseline 1506289)
//   - profit lock is delayed until runner MFE reaches ArmMFEATR
//   - after arming, LockATR becomes a permanent floor when broker-valid
//   - current uncapped 1.50*H1 ATR trend trail remains active
// The later TP1 grace/time experiment is intentionally NOT implemented here.
//==========================================================================
struct ADPShadowPath
  {
   bool active;
   bool filled;
   bool tp1Done;
   bool protectArmed;
   bool floorApplied;
   bool closed;
   ulong candidateId;
   datetime signalTime;
   datetime createdTime;
   datetime expiryTime;
   datetime fillTime;
   datetime tp1Time;
   datetime armTime;
   datetime closeTime;
   double entryThresholdATR;
   double signalRangeATR;
   string entryMode;
   double limitDepthATR;
   double armMFEATR;
   double lockATR;
   double signalHigh;
   double signalLow;
   double atrSignal;
   double plannedEntry;
   double fillPrice;
   double structuralSL;
   double tp1Move;
   double atrTP1;
   double mfe;
   double mae;
   double peakAfterTP1;
   double runnerSL;
   double exitPrice;
   double totalCaptureEq;
   double runnerCaptureEfficiency;
   string exitReason;
  };

int g_adpFile=INVALID_HANDLE;
ADPShadowPath g_adpPaths[];

void ADP_Header()
  {
   if(g_adpFile==INVALID_HANDLE) return;
   FileWrite(g_adpFile,
      "Time","Lifecycle","CandidateID","SignalTime",
      "EntryThresholdATR","SignalRangeATR","ChosenEntryMode","LimitDepthATR",
      "ArmMFEATR","LockATR","SignalHigh","SignalLow","ATR_Signal",
      "PlannedEntry","FillPrice","StructuralSL","TP1Move","ATR_TP1",
      "MFE_Price","MAE_Price","PeakAfterTP1","RunnerSL","ExitPrice",
      "TotalCaptureEq","RunnerCaptureEfficiency","ExitReason","Note");
   FileFlush(g_adpFile);
  }

void ADP_Log(const string lifecycle,const ADPShadowPath &p,const string note)
  {
   if(g_adpFile==INVALID_HANDLE) return;
   FileWrite(g_adpFile,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),lifecycle,(string)p.candidateId,
      TimeToString(p.signalTime,TIME_DATE|TIME_MINUTES),
      DoubleToString(p.entryThresholdATR,2),DoubleToString(p.signalRangeATR,4),p.entryMode,
      DoubleToString(p.limitDepthATR,2),DoubleToString(p.armMFEATR,2),DoubleToString(p.lockATR,2),
      DoubleToString(p.signalHigh,_Digits),DoubleToString(p.signalLow,_Digits),DoubleToString(p.atrSignal,_Digits),
      DoubleToString(p.plannedEntry,_Digits),DoubleToString(p.fillPrice,_Digits),DoubleToString(p.structuralSL,_Digits),
      DoubleToString(p.tp1Move,_Digits),DoubleToString(p.atrTP1,_Digits),
      DoubleToString(p.mfe,_Digits),DoubleToString(p.mae,_Digits),DoubleToString(p.peakAfterTP1,_Digits),
      DoubleToString(p.runnerSL,_Digits),DoubleToString(p.exitPrice,_Digits),
      DoubleToString(p.totalCaptureEq,_Digits),DoubleToString(p.runnerCaptureEfficiency,4),
      p.exitReason,note);
   FileFlush(g_adpFile);
  }

void ADP_AddPath(const ulong cid,const datetime sigTime,const datetime created,
                 const double thresholdATR,const double signalRangeATR,const string mode,
                 const double limitDepthATR,const double armMFEATR,const double lockATR,
                 const double hi,const double lo,const double atrSignal,
                 const double plannedEntry,const double structuralSL)
  {
   int n=ArraySize(g_adpPaths);
   ArrayResize(g_adpPaths,n+1);
   ADPShadowPath p;
   p.active=true; p.filled=false; p.tp1Done=false; p.protectArmed=false; p.floorApplied=false; p.closed=false;
   p.candidateId=cid; p.signalTime=sigTime; p.createdTime=created;
   p.expiryTime=created+(datetime)(MathMax(1,InpV10PendingExpiryM5Bars)*PeriodSeconds(PERIOD_M5));
   p.fillTime=0; p.tp1Time=0; p.armTime=0; p.closeTime=0;
   p.entryThresholdATR=thresholdATR; p.signalRangeATR=signalRangeATR; p.entryMode=mode;
   p.limitDepthATR=limitDepthATR; p.armMFEATR=armMFEATR; p.lockATR=lockATR;
   p.signalHigh=hi; p.signalLow=lo; p.atrSignal=atrSignal;
   p.plannedEntry=NormalizeDouble(plannedEntry,_Digits); p.fillPrice=0.0;
   p.structuralSL=NormalizeDouble(structuralSL,_Digits); p.tp1Move=EPR_TP1PriceMove(InpFixedLot); p.atrTP1=0.0;
   p.mfe=0.0; p.mae=0.0; p.peakAfterTP1=0.0; p.runnerSL=p.structuralSL; p.exitPrice=0.0;
   p.totalCaptureEq=0.0; p.runnerCaptureEfficiency=0.0; p.exitReason="";
   g_adpPaths[n]=p;
   ADP_Log("ARMED",g_adpPaths[n],"adaptive/delayed shadow only; no broker operation");
  }

void ADP_ArmFamilyB(const ulong cid,const datetime sigTime,const double hi,const double lo,
                    const double stopEntry,const double structuralSL)
  {
   if(!Inp1290EnableAdaptiveDelayedShadow) return;
   string diag="";
   double atr=RC25GetRunnerATR(diag);
   if(atr<=0.0)
     {
      Print("[1506290 ADP] ATR unavailable at signal | ",diag);
      return;
     }

   double riskRange=MathMax(0.0,stopEntry-structuralSL);
   double rangeATR=(atr>0.0 ? riskRange/atr : 0.0);
   double thresholds[4]={Inp1290EntryThreshold1ATR,Inp1290EntryThreshold2ATR,Inp1290EntryThreshold3ATR,Inp1290EntryThreshold4ATR};
   double arms[4]={Inp1290ArmMFE1ATR,Inp1290ArmMFE2ATR,Inp1290ArmMFE3ATR,Inp1290ArmMFE4ATR};
   double locks[4]={Inp1290Lock1ATR,Inp1290Lock2ATR,Inp1290Lock3ATR,Inp1290Lock4ATR};
   datetime now=TimeCurrent();

   for(int t=0;t<4;t++)
     {
      bool useLimit=(rangeATR>=thresholds[t]);
      string mode=(useLimit ? "LIMIT" : "STOP");
      double planned=(useLimit ? stopEntry-atr*Inp1290AdaptiveLimitDepthATR : stopEntry);
      if(planned<=structuralSL)
        {
         // Invalid acquisition geometry for this threshold; record nothing rather than fabricate a fill.
         continue;
        }
      for(int a=0;a<4;a++)
         for(int l=0;l<4;l++)
            ADP_AddPath(cid,sigTime,now,thresholds[t],rangeATR,mode,
                        (useLimit?Inp1290AdaptiveLimitDepthATR:0.0),arms[a],locks[l],
                        hi,lo,atr,planned,structuralSL);
     }
  }

void ADP_ClosePath(const int i,const double price,const string reason,const string note)
  {
   ADPShadowPath p=g_adpPaths[i];
   p.closed=true; p.active=false; p.closeTime=TimeCurrent(); p.exitPrice=price; p.exitReason=reason;
   if(!p.tp1Done)
      p.totalCaptureEq=(p.filled ? price-p.fillPrice : 0.0); // full-volume price-equivalent
   else
     {
      double runnerMove=price-p.fillPrice;
      p.totalCaptureEq=0.5*p.tp1Move+0.5*runnerMove; // 50% TP1 + 50% runner, normalized to initial volume
      if(p.peakAfterTP1>0.0) p.runnerCaptureEfficiency=runnerMove/p.peakAfterTP1;
     }
   g_adpPaths[i]=p;
   ADP_Log("CLOSED",g_adpPaths[i],note);
  }

void ADP_Update()
  {
   if(!Inp1290EnableAdaptiveDelayedShadow || ArraySize(g_adpPaths)==0) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT); if(point<=0.0) return;
   long stopsPts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezePts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minStopDist=(double)MathMax(stopsPts,freezePts)*point;

   for(int i=0;i<ArraySize(g_adpPaths);i++)
     {
      if(!g_adpPaths[i].active || g_adpPaths[i].closed) continue;

      if(!g_adpPaths[i].filled)
        {
         if(TimeCurrent()>g_adpPaths[i].expiryTime)
           { ADP_ClosePath(i,0.0,"NOT_FILLED_EXPIRED","same one-hour freshness as Family-B pending setup"); continue; }

         bool fill=(g_adpPaths[i].entryMode=="STOP" ? tick.ask>=g_adpPaths[i].plannedEntry : tick.ask<=g_adpPaths[i].plannedEntry);
         if(!fill) continue;
         g_adpPaths[i].filled=true; g_adpPaths[i].fillTime=TimeCurrent();
         g_adpPaths[i].fillPrice=(g_adpPaths[i].entryMode=="STOP" ?
                                  MathMax(g_adpPaths[i].plannedEntry,tick.ask) :
                                  MathMin(g_adpPaths[i].plannedEntry,tick.ask));
         g_adpPaths[i].fillPrice=NormalizeDouble(g_adpPaths[i].fillPrice,_Digits);
         g_adpPaths[i].runnerSL=g_adpPaths[i].structuralSL;
         ADP_Log("FILLED",g_adpPaths[i],"adaptive shadow BUY fill");
        }

      double fav=tick.bid-g_adpPaths[i].fillPrice;
      double adv=g_adpPaths[i].fillPrice-tick.bid;
      if(fav>g_adpPaths[i].mfe) g_adpPaths[i].mfe=fav;
      if(adv>g_adpPaths[i].mae) g_adpPaths[i].mae=adv;

      if(!g_adpPaths[i].tp1Done)
        {
         if(tick.bid<=g_adpPaths[i].structuralSL)
           { ADP_ClosePath(i,tick.bid,"INITIAL_SL","structural SL before TP1"); continue; }

         if(g_adpPaths[i].tp1Move>0.0 && fav>=g_adpPaths[i].tp1Move)
           {
            g_adpPaths[i].tp1Done=true; g_adpPaths[i].tp1Time=TimeCurrent();
            string d=""; g_adpPaths[i].atrTP1=RC25GetRunnerATR(d);
            if(g_adpPaths[i].atrTP1<=0.0) g_adpPaths[i].atrTP1=g_adpPaths[i].atrSignal;
            // 1506290 contract: BE remains the immediate post-TP1 baseline. The later grace-time study is deferred.
            if(g_adpPaths[i].fillPrice<tick.bid-minStopDist)
               g_adpPaths[i].runnerSL=MathMax(g_adpPaths[i].runnerSL,g_adpPaths[i].fillPrice);
            ADP_Log("TP1_DONE",g_adpPaths[i],"50% partial assumed; BE baseline; ATR frozen for delayed lock");
           }
         continue;
        }

      double after=tick.bid-g_adpPaths[i].fillPrice;
      if(after>g_adpPaths[i].peakAfterTP1) g_adpPaths[i].peakAfterTP1=after;
      double mfeATR=(g_adpPaths[i].atrTP1>0.0 ? g_adpPaths[i].mfe/g_adpPaths[i].atrTP1 : 0.0);

      if(!g_adpPaths[i].protectArmed && mfeATR>=g_adpPaths[i].armMFEATR)
        {
         g_adpPaths[i].protectArmed=true; g_adpPaths[i].armTime=TimeCurrent();
         ADP_Log("PROTECTION_ARMED",g_adpPaths[i],StringFormat("runner MFE %.4f ATR reached arm %.2f",mfeATR,g_adpPaths[i].armMFEATR));
        }

      if(g_adpPaths[i].protectArmed)
        {
         double floorSL=RC21NormalizeToTick(g_adpPaths[i].fillPrice+g_adpPaths[i].atrTP1*g_adpPaths[i].lockATR);
         if(floorSL<tick.bid-minStopDist && floorSL>g_adpPaths[i].runnerSL+point*0.5)
           {
            double oldSL=g_adpPaths[i].runnerSL;
            g_adpPaths[i].runnerSL=floorSL;
            if(!g_adpPaths[i].floorApplied)
              {
               g_adpPaths[i].floorApplied=true;
               ADP_Log("PROTECTION_FLOOR_APPLIED",g_adpPaths[i],StringFormat("oldSL=%.5f floor=%.5f",oldSL,floorSL));
              }
           }
        }

      if(InpEPRUseCurrentTrail)
        {
         string d=""; double atrNow=RC25GetRunnerATR(d);
         if(atrNow>0.0)
           {
            double trail=RC21NormalizeToTick(tick.bid-atrNow*InpPRME_ATRTrailMult);
            if(trail<g_adpPaths[i].fillPrice) trail=g_adpPaths[i].fillPrice;
            if(trail<tick.bid-minStopDist && trail>g_adpPaths[i].runnerSL+point*0.5)
               g_adpPaths[i].runnerSL=trail;
           }
        }

      if(tick.bid<=g_adpPaths[i].runnerSL+point*0.5)
        { ADP_ClosePath(i,tick.bid,"RUNNER_SL","delayed protection/current ATR trail exit"); continue; }
     }
  }

void ADP_FlushOpenAtEnd()
  {
   for(int i=0;i<ArraySize(g_adpPaths);i++)
     {
      if(!g_adpPaths[i].active || g_adpPaths[i].closed) continue;
      g_adpPaths[i].exitReason="TEST_END_OPEN";
      ADP_Log("TEST_END_OPEN",g_adpPaths[i],"path unresolved at tester end");
     }
  }


// ============================================================================
// [1506491] TP1 GRACE / DELAYED-BE SHADOW ENGINE
// Shadow only. Never sends Buy/Sell orders and never calls PositionModify.
// Seven policies are compared on the SAME frozen adaptive entry:
//   IMMEDIATE_BE control
//   TIME_15M / TIME_30M / TIME_60M
//   MFE_0.50ATR / MFE_1.00ATR / MFE_1.50ATR
//
// During grace, the original structural SL is retained intentionally.
// Once grace condition is satisfied, BE is armed/applied when broker-valid,
// then the existing 1.50 x current H1 ATR trail becomes eligible.
// ============================================================================

struct GraceShadowPath
  {
   bool active,filled,tp1Done,beArmed,beApplied,closed,wouldImmediateBEHit;
   ulong candidateId;
   datetime signalTime,createdTime,expiryTime,fillTime,tp1Time,beArmTime,beApplyTime,closeTime;
   string entryMode,graceMode,exitReason;
   double graceValue;
   double signalRangeATR,atrSignal,plannedEntry,fillPrice,structuralSL,tp1Move,atrTP1;
   double mfe,mae,postTP1Peak,postTP1MinBid,runnerSL,exitPrice,totalCaptureEq,runnerCaptureEfficiency;
  };

int g_graceFile=INVALID_HANDLE;
GraceShadowPath g_gracePaths[];

void GRACE_Header()
  {
   if(g_graceFile==INVALID_HANDLE) return;
   FileWrite(g_graceFile,
      "Time","Lifecycle","CandidateID","SignalTime",
      "EntryMode","SignalRangeATR","ATR_Signal","PlannedEntry","FillPrice","StructuralSL",
      "GraceMode","GraceValue","TP1Move","ATR_TP1",
      "MFE_Price","MAE_Price","PostTP1Peak","PostTP1MinBid",
      "WouldImmediateBEHit","BEArmTime","BEApplyTime","RunnerSL","ExitPrice",
      "TotalCaptureEq","RunnerCaptureEfficiency","ExitReason","Note");
   FileFlush(g_graceFile);
  }

void GRACE_Log(const string lifecycle,const GraceShadowPath &p,const string note)
  {
   if(g_graceFile==INVALID_HANDLE) return;
   FileWrite(g_graceFile,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),lifecycle,(string)p.candidateId,
      TimeToString(p.signalTime,TIME_DATE|TIME_MINUTES),
      p.entryMode,DoubleToString(p.signalRangeATR,4),DoubleToString(p.atrSignal,_Digits),
      DoubleToString(p.plannedEntry,_Digits),DoubleToString(p.fillPrice,_Digits),
      DoubleToString(p.structuralSL,_Digits),p.graceMode,DoubleToString(p.graceValue,2),
      DoubleToString(p.tp1Move,_Digits),DoubleToString(p.atrTP1,_Digits),
      DoubleToString(p.mfe,_Digits),DoubleToString(p.mae,_Digits),
      DoubleToString(p.postTP1Peak,_Digits),DoubleToString(p.postTP1MinBid,_Digits),
      (p.wouldImmediateBEHit?"TRUE":"FALSE"),
      (p.beArmTime>0?TimeToString(p.beArmTime,TIME_DATE|TIME_SECONDS):""),
      (p.beApplyTime>0?TimeToString(p.beApplyTime,TIME_DATE|TIME_SECONDS):""),
      DoubleToString(p.runnerSL,_Digits),DoubleToString(p.exitPrice,_Digits),
      DoubleToString(p.totalCaptureEq,_Digits),DoubleToString(p.runnerCaptureEfficiency,4),
      p.exitReason,note);
   FileFlush(g_graceFile);
  }

void GRACE_AddPath(const ulong cid,const datetime sigTime,const datetime created,
                   const string entryMode,const double rangeATR,const double atrSignal,
                   const double plannedEntry,const double structuralSL,
                   const string graceMode,const double graceValue)
  {
   int n=ArraySize(g_gracePaths);
   ArrayResize(g_gracePaths,n+1);
   GraceShadowPath p;
   p.active=true; p.filled=false; p.tp1Done=false; p.beArmed=false; p.beApplied=false;
   p.closed=false; p.wouldImmediateBEHit=false;
   p.candidateId=cid; p.signalTime=sigTime; p.createdTime=created;
   p.expiryTime=created+(datetime)(MathMax(1,InpV10PendingExpiryM5Bars)*PeriodSeconds(PERIOD_M5));
   p.fillTime=0; p.tp1Time=0; p.beArmTime=0; p.beApplyTime=0; p.closeTime=0;
   p.entryMode=entryMode; p.graceMode=graceMode; p.graceValue=graceValue;
   p.signalRangeATR=rangeATR; p.atrSignal=atrSignal;
   p.plannedEntry=NormalizeDouble(plannedEntry,_Digits); p.fillPrice=0.0;
   p.structuralSL=NormalizeDouble(structuralSL,_Digits);
   p.tp1Move=EPR_TP1PriceMove(InpFixedLot); p.atrTP1=0.0;
   p.mfe=0.0; p.mae=0.0; p.postTP1Peak=0.0; p.postTP1MinBid=0.0;
   p.runnerSL=p.structuralSL; p.exitPrice=0.0; p.totalCaptureEq=0.0;
   p.runnerCaptureEfficiency=0.0; p.exitReason="";
   g_gracePaths[n]=p;
   GRACE_Log("ARMED",g_gracePaths[n],"1506491 shadow only; adaptive entry frozen from 1506290");
  }

void GRACE_ArmFamilyB(const ulong cid,const datetime sigTime,const double hi,const double lo,
                      const double stopEntry,const double structuralSL)
  {
   if(!Inp1291EnableGraceShadow) return;
   string diag="";
   double atr=RC25GetRunnerATR(diag);
   if(atr<=0.0)
     {
      Print("[1506491 GRACE] ATR unavailable at signal | ",diag);
      return;
     }

   double rangeATR=MathMax(0.0,stopEntry-structuralSL)/atr;
   bool useLimit=(rangeATR>=Inp1291AdaptiveThresholdATR);
   string mode=(useLimit?"LIMIT":"STOP");
   double planned=(useLimit ? stopEntry-atr*Inp1291LimitDepthATR : stopEntry);
   if(planned<=structuralSL) return;

   string modes[7]={"IMMEDIATE_BE","TIME_M5","TIME_M5","TIME_M5","MFE_ATR","MFE_ATR","MFE_ATR"};
   double vals[7]={0.0,
                   (double)Inp1291GraceM5Bars_1,(double)Inp1291GraceM5Bars_2,(double)Inp1291GraceM5Bars_3,
                   Inp1291GraceMFEATR_1,Inp1291GraceMFEATR_2,Inp1291GraceMFEATR_3};
   datetime now=TimeCurrent();
   for(int k=0;k<7;k++)
      GRACE_AddPath(cid,sigTime,now,mode,rangeATR,atr,planned,structuralSL,modes[k],vals[k]);
  }

void GRACE_ClosePath(const int i,const double price,const string reason,const string note)
  {
   GraceShadowPath p=g_gracePaths[i];
   p.closed=true; p.active=false; p.closeTime=TimeCurrent(); p.exitPrice=price; p.exitReason=reason;
   if(!p.tp1Done)
      p.totalCaptureEq=(p.filled ? price-p.fillPrice : 0.0);
   else
     {
      double runnerMove=price-p.fillPrice;
      p.totalCaptureEq=0.5*p.tp1Move+0.5*runnerMove;
      if(p.postTP1Peak>0.0) p.runnerCaptureEfficiency=runnerMove/p.postTP1Peak;
     }
   g_gracePaths[i]=p;
   GRACE_Log("CLOSED",g_gracePaths[i],note);
  }

bool GRACE_ShouldArmBE(const GraceShadowPath &p,const double mfeATR)
  {
   if(p.graceMode=="IMMEDIATE_BE") return true;
   if(p.graceMode=="TIME_M5")
     {
      int bars=(int)MathRound(p.graceValue);
      return (TimeCurrent()>=p.tp1Time+(datetime)(MathMax(0,bars)*PeriodSeconds(PERIOD_M5)));
     }
   if(p.graceMode=="MFE_ATR") return (mfeATR>=p.graceValue);
   return false;
  }

void GRACE_Update()
  {
   if(!Inp1291EnableGraceShadow || ArraySize(g_gracePaths)==0) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT); if(point<=0.0) return;
   long stopsPts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezePts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minStopDist=(double)MathMax(stopsPts,freezePts)*point;

   for(int i=0;i<ArraySize(g_gracePaths);i++)
     {
      if(!g_gracePaths[i].active || g_gracePaths[i].closed) continue;

      if(!g_gracePaths[i].filled)
        {
         if(TimeCurrent()>g_gracePaths[i].expiryTime)
           { GRACE_ClosePath(i,0.0,"NOT_FILLED_EXPIRED","same Family-B pending freshness"); continue; }

         bool fill=(g_gracePaths[i].entryMode=="STOP" ? tick.ask>=g_gracePaths[i].plannedEntry
                                                       : tick.ask<=g_gracePaths[i].plannedEntry);
         if(!fill) continue;
         g_gracePaths[i].filled=true; g_gracePaths[i].fillTime=TimeCurrent();
         g_gracePaths[i].fillPrice=(g_gracePaths[i].entryMode=="STOP" ?
                                    MathMax(g_gracePaths[i].plannedEntry,tick.ask) :
                                    MathMin(g_gracePaths[i].plannedEntry,tick.ask));
         g_gracePaths[i].fillPrice=NormalizeDouble(g_gracePaths[i].fillPrice,_Digits);
         g_gracePaths[i].runnerSL=g_gracePaths[i].structuralSL;
         GRACE_Log("FILLED",g_gracePaths[i],"frozen adaptive entry shadow fill");
        }

      double fav=tick.bid-g_gracePaths[i].fillPrice;
      double adv=g_gracePaths[i].fillPrice-tick.bid;
      if(fav>g_gracePaths[i].mfe) g_gracePaths[i].mfe=fav;
      if(adv>g_gracePaths[i].mae) g_gracePaths[i].mae=adv;

      if(!g_gracePaths[i].tp1Done)
        {
         if(tick.bid<=g_gracePaths[i].structuralSL)
           { GRACE_ClosePath(i,tick.bid,"INITIAL_SL","structural SL before TP1"); continue; }

         if(g_gracePaths[i].tp1Move>0.0 && fav>=g_gracePaths[i].tp1Move)
           {
            g_gracePaths[i].tp1Done=true; g_gracePaths[i].tp1Time=TimeCurrent();
            string d=""; g_gracePaths[i].atrTP1=RC25GetRunnerATR(d);
            if(g_gracePaths[i].atrTP1<=0.0) g_gracePaths[i].atrTP1=g_gracePaths[i].atrSignal;
            g_gracePaths[i].postTP1MinBid=tick.bid;
            GRACE_Log("TP1_DONE",g_gracePaths[i],"50% partial assumed; structural SL retained during grace");
           }
         continue;
        }

      double runnerMove=tick.bid-g_gracePaths[i].fillPrice;
      if(runnerMove>g_gracePaths[i].postTP1Peak) g_gracePaths[i].postTP1Peak=runnerMove;
      if(g_gracePaths[i].postTP1MinBid<=0.0 || tick.bid<g_gracePaths[i].postTP1MinBid)
         g_gracePaths[i].postTP1MinBid=tick.bid;

      // Direct forensic marker: would immediate BE already have stopped this runner?
      if(!g_gracePaths[i].beApplied && !g_gracePaths[i].wouldImmediateBEHit &&
         tick.bid<=g_gracePaths[i].fillPrice+point*0.5)
        {
         g_gracePaths[i].wouldImmediateBEHit=true;
         GRACE_Log("IMMEDIATE_BE_WOULD_HIT",g_gracePaths[i],"price revisited entry before this grace policy applied BE");
        }

      // During grace, retain the original structural SL.
      if(!g_gracePaths[i].beArmed && tick.bid<=g_gracePaths[i].structuralSL)
        {
         GRACE_ClosePath(i,tick.bid,"POST_TP1_STRUCTURAL_SL","runner failed during grace before BE activation");
         continue;
        }

      double mfeATR=(g_gracePaths[i].atrTP1>0.0 ? g_gracePaths[i].mfe/g_gracePaths[i].atrTP1 : 0.0);
      if(!g_gracePaths[i].beArmed && GRACE_ShouldArmBE(g_gracePaths[i],mfeATR))
        {
         g_gracePaths[i].beArmed=true; g_gracePaths[i].beArmTime=TimeCurrent();
         GRACE_Log("BE_ARMED",g_gracePaths[i],
                   StringFormat("grace satisfied | mode=%s value=%.2f mfeATR=%.4f",
                                g_gracePaths[i].graceMode,g_gracePaths[i].graceValue,mfeATR));
        }

      if(g_gracePaths[i].beArmed && !g_gracePaths[i].beApplied)
        {
         double be=RC21NormalizeToTick(g_gracePaths[i].fillPrice);
         if(be<tick.bid-minStopDist)
           {
            g_gracePaths[i].runnerSL=MathMax(g_gracePaths[i].runnerSL,be);
            g_gracePaths[i].beApplied=true; g_gracePaths[i].beApplyTime=TimeCurrent();
            GRACE_Log("BE_APPLIED",g_gracePaths[i],"BE became broker-valid after grace");
           }
        }

      // Existing trend trail activates only AFTER grace/BE application.
      if(g_gracePaths[i].beApplied && InpEPRUseCurrentTrail)
        {
         string d=""; double atrNow=RC25GetRunnerATR(d);
         if(atrNow>0.0)
           {
            double trail=RC21NormalizeToTick(tick.bid-atrNow*InpPRME_ATRTrailMult);
            if(trail<g_gracePaths[i].fillPrice) trail=g_gracePaths[i].fillPrice;
            if(trail<tick.bid-minStopDist && trail>g_gracePaths[i].runnerSL+point*0.5)
               g_gracePaths[i].runnerSL=trail;
           }
        }

      if(tick.bid<=g_gracePaths[i].runnerSL+point*0.5)
        {
         string why=(g_gracePaths[i].beApplied?"RUNNER_SL":"POST_TP1_STRUCTURAL_SL");
         GRACE_ClosePath(i,tick.bid,why,"1506491 grace/delayed-BE shadow exit");
         continue;
        }
     }
  }

void GRACE_FlushOpenAtEnd()
  {
   for(int i=0;i<ArraySize(g_gracePaths);i++)
     {
      if(!g_gracePaths[i].active || g_gracePaths[i].closed) continue;
      g_gracePaths[i].exitReason="TEST_END_OPEN";
      GRACE_Log("TEST_END_OPEN",g_gracePaths[i],"path unresolved at tester end");
     }
  }


//==========================================================================
// [RC2.5] Lifecycle-driven runner management certification
//
// RC2 forensic showed:
//   - partial close + BE events existed,
//   - zero RunnerAudit data rows,
//   - old 0.01 runners could survive to tester end.
//
// RC2.1 does NOT change the B entry strategy.
// Runner identity is derived from the V10 lifecycle map, not inferred only
// from current volume. A position is a runner when:
//   * it belongs to an open V10 Family-B trade map,
//   * the V10 map has recorded a partial exit,
//   * the live position still exists.
//
// Management after partial:
//   A) guarantee BE or better;
//   B) apply monotonic BUY trail = Bid - H1 ATR * 1.5.
//==========================================================================
int g_rc2RunnerAudit=INVALID_HANDLE;

void RC21RunnerAuditHeader()
  {
   if(g_rc2RunnerAudit==INVALID_HANDLE) return;
   FileWrite(g_rc2RunnerAudit,
      "Time","Event","PositionID","Ticket","CandidateID","Family",
      "InitialVolume","ClosedVolume","LiveVolume",
      "Entry","Bid","CurrentSL","CandidateSL",
      "ATR_H1","ATRMult","ProfitUSD","Note");
   FileFlush(g_rc2RunnerAudit);
  }

void RC21RunnerAudit(string ev,long posId,ulong ticket,ulong candidateId,string family,
                     double initialVol,double closedVol,double liveVol,
                     double entry,double bid,double curSL,double candSL,
                     double atr,double profit,string note)
  {
   if(g_rc2RunnerAudit==INVALID_HANDLE) return;
   FileWrite(g_rc2RunnerAudit,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),ev,
      (string)posId,(string)ticket,(string)candidateId,family,
      DoubleToString(initialVol,2),DoubleToString(closedVol,2),DoubleToString(liveVol,2),
      DoubleToString(entry,_Digits),DoubleToString(bid,_Digits),
      DoubleToString(curSL,_Digits),DoubleToString(candSL,_Digits),
      DoubleToString(atr,_Digits),DoubleToString(InpPRME_ATRTrailMult,2),
      DoubleToString(profit,2),note);
   FileFlush(g_rc2RunnerAudit);
  }

double RC21NormalizeToTick(double price)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick>0.0)
      price=MathRound(price/tick)*tick;
   return NormalizeDouble(price,_Digits);
  }

double RC25GetRunnerATR(string &diag)
  {
   // RC2.5: deterministic handle-free H1 ATR(14).
   // 15 completed H1 bars provide 14 True Range observations.
   diag="";

   MqlRates r[15];
   ResetLastError();
   int copied=CopyRates(_Symbol,PERIOD_H1,1,15,r);
   if(copied!=15)
     {
      diag=StringFormat("COPYRATES_FAIL copied=%d err=%d",copied,GetLastError());
      return 0.0;
     }

   double sumTR=0.0;
   for(int i=1;i<15;i++)
     {
      double trHL=r[i].high-r[i].low;
      double trHC=MathAbs(r[i].high-r[i-1].close);
      double trLC=MathAbs(r[i].low-r[i-1].close);
      double tr=MathMax(trHL,MathMax(trHC,trLC));

      if(tr<=0.0 || !MathIsValidNumber(tr))
        {
         diag=StringFormat("INVALID_TR i=%d high=%.5f low=%.5f prevClose=%.5f",
                           i,r[i].high,r[i].low,r[i-1].close);
         return 0.0;
        }
      sumTR+=tr;
     }

   double atr=sumTR/14.0;
   if(atr<=0.0 || !MathIsValidNumber(atr))
     {
      diag=StringFormat("INVALID_ATR sumTR=%.8f",sumTR);
      return 0.0;
     }

   diag="DIRECT_H1_TR14";
   return atr;
  }


bool RC25ShouldWriteTrailMoveAudit(const long posId)
  {
   static long ids[16];
   static datetime lastM5[16];
   static int used=0;

   datetime bar=iTime(_Symbol,PERIOD_M5,0);
   if(bar<=0) bar=TimeCurrent();

   for(int i=0;i<used;i++)
     {
      if(ids[i]!=posId) continue;
      if(lastM5[i]==bar) return false;
      lastM5[i]=bar;
      return true;
     }

   if(used<16)
     {
      ids[used]=posId;
      lastM5[used]=bar;
      used++;
      return true;
     }
   return false;
  }

bool RC25ShouldWriteRunnerAudit(const long posId,const string eventKey)
  {
   // I/O safety only: each diagnostic condition max once/H1 bar/position.
   static long ids[64];
   static string keys[64];
   static datetime lastH1[64];
   static int used=0;
   datetime h1bar=iTime(_Symbol,PERIOD_H1,0);
   if(h1bar<=0) h1bar=TimeCurrent();
   for(int i=0;i<used;i++)
     {
      if(ids[i]!=posId || keys[i]!=eventKey) continue;
      if(lastH1[i]==h1bar) return false;
      lastH1[i]=h1bar;
      return true;
     }
   if(used<64)
     {
      ids[used]=posId; keys[used]=eventKey; lastH1[used]=h1bar; used++;
      return true;
     }
   return false;
  }

bool RC21IsMappedBRunner(const long posId,int &mapIndex)
  {
   mapIndex=V10FindTrade(posId);
   if(mapIndex<0) return false;
   if(g_v10Trades[mapIndex].closed) return false;
   if(g_v10Trades[mapIndex].family!="B" && g_v10Trades[mapIndex].family!="T") return false;
   if(g_v10Trades[mapIndex].direction<=0) return false;

   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=0.01;

   double intendedPartial=g_v10Trades[mapIndex].volume*(InpPRME_PartialPct/100.0);

   // The transaction ledger is authoritative. Require that at least the
   // intended partial volume has actually been recorded as closed.
   if(g_v10Trades[mapIndex].closedVolume + step*0.25 < intendedPartial)
      return false;

   return true;
  }

void RC21ManageMappedRunners()
  {
   if(!InpRC2EnforceRunnerATRTrail) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0) return;

   long stopsPts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezePts=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minStopDist=(double)MathMax(stopsPts,freezePts)*point;

   for(int p=PositionsTotal()-1;p>=0;p--)
     {
      ulong ticket=PositionGetTicket(p);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) continue;

      long posId=(long)PositionGetInteger(POSITION_IDENTIFIER);
      int mi=-1;
      if(!RC21IsMappedBRunner(posId,mi)) continue;

      double liveVol=PositionGetDouble(POSITION_VOLUME);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);

      ulong candidateId=g_v10Trades[mi].candidateId;
      string family=g_v10Trades[mi].family;
      double initialVol=g_v10Trades[mi].volume;
      double closedVol=g_v10Trades[mi].closedVolume;

      // Emit positive evidence that the runner path is alive.
      // Only once per bar/position is not required for certification; this
      // audit intentionally proves the path is being reached.
      if(RC25ShouldWriteRunnerAudit(posId,"RUNNER_DETECTED"))
         RC21RunnerAudit("RUNNER_DETECTED",posId,ticket,candidateId,family,
                         initialVol,closedVol,liveVol,entry,tick.bid,curSL,0.0,
                         0.0,profit,"mapped Family-B runner alive; diagnostic presence throttled to once/H1 bar");

      // 1) Capital-protection invariant: after partial, runner must never
      // remain below BE. Restore BE first if shared PRME has not done so yet.
      double beSL=B1ProtectedBEPrice(entry,tick);
      if(curSL < beSL-point*0.5)
        {
         if(beSL < tick.bid-minStopDist)
           {
            ResetLastError();
            if(g_trade.PositionModify(ticket,beSL,curTP))
              {
               RC21RunnerAudit("RUNNER_BE_RESTORED",posId,ticket,candidateId,family,
                               initialVol,closedVol,liveVol,entry,tick.bid,
                               curSL,beSL,0.0,profit,
                               "partial recorded; enforced BE invariant");
               curSL=beSL;
              }
            else
              {
               if(RC25ShouldWriteRunnerAudit(posId,"RUNNER_BE_REJECTED"))
                  RC21RunnerAudit("RUNNER_BE_REJECTED",posId,ticket,candidateId,family,
                               initialVol,closedVol,liveVol,entry,tick.bid,
                               curSL,beSL,0.0,profit,
                               StringFormat("retcode=%u comment=%s err=%d",
                                            g_trade.ResultRetcode(),
                                            g_trade.ResultComment(),GetLastError()));
               continue;
              }
           }
         else
           {
            if(RC25ShouldWriteRunnerAudit(posId,"RUNNER_BE_WAIT_DISTANCE"))
               RC21RunnerAudit("RUNNER_BE_WAIT_DISTANCE",posId,ticket,candidateId,family,
                            initialVol,closedVol,liveVol,entry,tick.bid,
                            curSL,beSL,0.0,profit,
                            "BE not broker-valid yet; preserve position and retry");
            continue;
           }
        }

      // 2) Trend runner trail.
      string atrDiag="";
      double atr=RC25GetRunnerATR(atrDiag);
      if(atr<=0.0)
        {
         if(RC25ShouldWriteRunnerAudit(posId,"RUNNER_ATR_UNAVAILABLE"))
            RC21RunnerAudit("RUNNER_ATR_UNAVAILABLE",posId,ticket,candidateId,family,
                            initialVol,closedVol,liveVol,entry,tick.bid,
                            curSL,0.0,0.0,profit,
                            "H1 ATR unavailable | "+atrDiag);
         continue;
        }

      double candidate=RC21NormalizeToTick(tick.bid-atr*InpPRME_ATRTrailMult);

      // Never move below BE and never loosen an existing stop.
      if(candidate<beSL) candidate=beSL;
      if(candidate<=curSL+point*0.5) continue;

      if(candidate>=tick.bid-minStopDist)
        {
         if(RC25ShouldWriteRunnerAudit(posId,"RUNNER_TRAIL_WAIT_DISTANCE"))
            RC21RunnerAudit("RUNNER_TRAIL_WAIT_DISTANCE",posId,ticket,candidateId,family,
                         initialVol,closedVol,liveVol,entry,tick.bid,
                         curSL,candidate,atr,profit,
                         "candidate violates broker stop/freeze distance");
         continue;
        }

      double oldSL=curSL;
      ResetLastError();
      if(g_trade.PositionModify(ticket,candidate,curTP))
        {
         if(RC25ShouldWriteTrailMoveAudit(posId))
            RC21RunnerAudit("RUNNER_TRAIL_MOVED",posId,ticket,candidateId,family,
                            initialVol,closedVol,liveVol,entry,tick.bid,
                            oldSL,candidate,atr,profit,
                            "lifecycle-driven H1 ATR runner protection | ATRSource="+atrDiag+" | audit<=once/M5");
        }
      else
        {
         if(RC25ShouldWriteRunnerAudit(posId,"RUNNER_TRAIL_REJECTED"))
            RC21RunnerAudit("RUNNER_TRAIL_REJECTED",posId,ticket,candidateId,family,
                         initialVol,closedVol,liveVol,entry,tick.bid,
                         oldSL,candidate,atr,profit,
                         StringFormat("retcode=%u comment=%s err=%d",
                                      g_trade.ResultRetcode(),
                                      g_trade.ResultComment(),GetLastError()));
        }
     }
  }



// ============================================================================
// [1506290 RESEARCH] Adaptive STOP/LIMIT + Delayed Runner Protection Shadow
// Baseline 1506289 real-order path is intentionally unchanged.
// This block defines the next shadow experiment. It MUST NOT place orders.
// Adaptive entry candidates use SignalRange/H1ATR thresholds.
// Delayed protection candidates arm only after runner MFE reaches an ATR
// maturity threshold; the existing uncapped 1.50 ATR trend trail remains the
// conceptual terminal management layer.
// ============================================================================
input bool   Inp1290EnableAdaptiveDelayedShadow = true;
input double Inp1290AdaptiveLimitDepthATR       = 0.25;
input double Inp1290EntryThreshold1ATR          = 0.75;
input double Inp1290EntryThreshold2ATR          = 1.00;
input double Inp1290EntryThreshold3ATR          = 1.25;
input double Inp1290EntryThreshold4ATR          = 1.50;

input double Inp1290ArmMFE1ATR                  = 0.50;
input double Inp1290ArmMFE2ATR                  = 1.00;
input double Inp1290ArmMFE3ATR                  = 1.50;
input double Inp1290ArmMFE4ATR                  = 2.00;

input double Inp1290Lock1ATR                    = 0.10;
input double Inp1290Lock2ATR                    = 0.15;
input double Inp1290Lock3ATR                    = 0.20;
input double Inp1290Lock4ATR                    = 0.25;

input string Inp1290ShadowFile                  = "ADP.csv";

// [1506290] Research helper: entry ownership decision only.
// 0 = STOP, 1 = LIMIT(-0.25 ATR). Threshold is supplied by the matrix caller.
int R1290AdaptiveEntryMode(const double signalRangeATR,const double thresholdATR)
{
   if(signalRangeATR >= thresholdATR) return 1;
   return 0;
}

// [1506290] Research helper: delayed lock becomes eligible only after maturity.
// BUY protection floor; caller must still enforce broker stop/freeze distance
// and monotonic tightening. No production PositionModify() is performed here.
double R1290DelayedBuyFloor(const double entry,
                           const double frozenATR,
                           const double mfeATR,
                           const double armATR,
                           const double lockATR)
{
   if(frozenATR<=0.0 || mfeATR<armATR) return entry; // BE/control until armed
   return entry + frozenATR*lockATR;
}


// ============================================================================
// [1506491 RESEARCH] TP1 Grace / Delayed-BE Shadow
// Entry is FROZEN from 1506290 finding:
//   SignalRangeATR < 0.75 => STOP
//   SignalRangeATR >=0.75 => LIMIT = STOP - 0.25 * H1 ATR(signal)
// This branch studies ONLY post-TP1 breathing room before BE.
// Real broker trade path is unchanged.
// ============================================================================
input bool   Inp1291EnableGraceShadow       = true;
input double Inp1291AdaptiveThresholdATR    = 0.75;
input double Inp1291LimitDepthATR           = 0.25;
input int    Inp1291GraceM5Bars_1           = 3;    // 15 minutes
input int    Inp1291GraceM5Bars_2           = 6;    // 30 minutes
input int    Inp1291GraceM5Bars_3           = 12;   // 60 minutes
input double Inp1291GraceMFEATR_1           = 0.50;
input double Inp1291GraceMFEATR_2           = 1.00;
input double Inp1291GraceMFEATR_3           = 1.50;
input string Inp1291GraceFile               = "GRC.csv";

datetime g_h4h1HeartbeatLast=0;

int H4H1HeartbeatActiveB1Candidates()
  {
   int n=0;
   for(int i=0;i<ArraySize(g_b1Pending);i++)
      if(g_b1Pending[i].active) n++;
   return n;
  }

int H4H1HeartbeatOpenMagicPositions()
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      n++;
     }
   return n;
  }

void H4H1Heartbeat()
  {
   if(!InpHeartbeatEnable) return;
   int sec=MathMax(5,InpHeartbeatSeconds);
   datetime now=TimeCurrent();
   if(g_h4h1HeartbeatLast>0 && (now-g_h4h1HeartbeatLast)<sec) return;
   g_h4h1HeartbeatLast=now;

   MqlTick tick;
   double spread=0.0;
   if(SymbolInfoTick(_Symbol,tick)) spread=MathMax(0.0,tick.ask-tick.bid);

   PrintFormat("[H4H1_HEARTBEAT] Magic=%d | Alive=YES | TerminalAlgo=%s | MQLTrade=%s | AccountTrade=%s | H4Trend=%d | Pullback=%s | PBars=%d/%d | H1Confirmed=%s | B1Active=%d | OpenMagic=%d | Spread=$%.3f",
               InpMagicNumber,
               TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"YES":"NO",
               MQLInfoInteger(MQL_TRADE_ALLOWED)?"YES":"NO",
               AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)?"YES":"NO",
               g_last_trend,
               g_last_pullback?"YES":"NO",
               g_pullback_bar_count,InpMinPullbackBars,
               g_v08H1Confirmed?"YES":"NO",
               H4H1HeartbeatActiveB1Candidates(),
               H4H1HeartbeatOpenMagicPositions(),
               spread);
  }

int OnInit()
// CSV logging enabled
  {
   string dir_label = (InpTradeDirection == 1) ? "BUY ONLY" :
                      (InpTradeDirection == 2) ? "SELL ONLY" : "BOTH";

   if(InpRequireGoldSymbol && !IsGoldSymbol(_Symbol))
     {
      PrintFormat("ERROR: This EA is for Gold only. Current symbol=%s | Description=%s | Base=%s",
                  _Symbol,
                  SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION),
                  SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE));
      return INIT_FAILED;
     }

   PrintFormat("[INIT] Gold symbol validated | Symbol=%s | Desc=%s | Spread=$%.3f | MaxSpread=$%.2f",
               _Symbol,
               SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION),
               GetGoldSpreadDollars(),
               InpMaxSpreadDollars);

   Aurex_DeploymentIdentity deployId;
   deployId.Strategy    = "H4H1_BUY";
   deployId.EAVersion   = "5.11-SOFV2";
   deployId.BuildNumber = "1506491.BTB.C6.EXEC.RC1";
   deployId.MagicNumber = InpMagicNumber;
   deployId.PRMEVersion = PRME_CORE_VERSION;
   deployId.UEEVersion  = "SHARED-v1.1.3";
   deployId.SOFVersion  = SOF_FRAMEWORK_VERSION;
   deployId.CompileTime = "";
   deployId.Operator    = "sitth";
   deployId.Reason      = "BTB C6 management-isolation challenger: Family-T immediate protected BE after TP1; Family-B retains 15-minute grace; entry rules unchanged; shared MaxSlots=3";

   string initReason="ChartSetup";
   switch(UninitializeReason())
     {
      case REASON_RECOMPILE:   initReason="Recompile";       break;
      case REASON_CHARTCHANGE: initReason="ChartChange";     break;
      case REASON_CHARTCLOSE:  initReason="ChartClose";      break;
      case REASON_PARAMETERS:  initReason="Parameters";      break;
      case REASON_ACCOUNT:     initReason="AccountChange";   break;
      case REASON_TEMPLATE:    initReason="Template";        break;
      case REASON_INITFAILED:  initReason="PriorInitFailed"; break;
      case REASON_CLOSE:       initReason="TerminalClose";   break;
     }

   if(!g_sessionMgr.Initialize("H4H1_BUY",deployId,initReason))
     {
      Print("[H4H1 BUY SOF V2] SessionManager initialization failed.");
      return INIT_FAILED;
     }
   if(!ResolveSOFV2RunPaths())
      return FailInitialization("SessionManager path resolution incomplete");

   // Observational recovery intent only. PRME completion is logged after its
   // first real ManageOpenPositions() pass in OnTick().
   for(int rp=PositionsTotal()-1; rp>=0; rp--)
     {
      ulong pt=PositionGetTicket(rp);
      if(pt==0 || !PositionSelectByTicket(pt)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      g_recoveryPosCount++;
      long posId=(long)PositionGetInteger(POSITION_IDENTIFIER);
      long posType=PositionGetInteger(POSITION_TYPE);
      string dirStr=(posType==POSITION_TYPE_BUY ? "BUY" : "SELL");
      datetime openTm=(datetime)PositionGetInteger(POSITION_TIME);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      g_sessionMgr.LogExistingPositionDetected(pt,posId,dirStr,openTm,openPrice);
     }
   if(g_recoveryPosCount==0)
      g_sessionMgr.LogNoExistingPosition();
   else
     {
      g_sessionMgr.LogRecoveryPending(StringFormat("%d H4H1 BUY position(s) await PRME refresh",g_recoveryPosCount));
      g_recoveryPending=true;
     }

   PrintFormat("=== H4H1 Trend EA v4.3 STANDARDIZED | Dir=%s | PBBars=%d | DepthATR=%.2f | EMADist=%.1f | RR=%.1f | RiskLot=%s Risk=%.2f%% FixedLot=%.2f | MaxSpread=$%.2f | BPL=%s BSL=%s EMA=%s ===",
               dir_label, InpMinPullbackBars, InpMinPullbackDepthATR,
               InpMinH4EMADistance, InpRiskReward,
               InpUseRiskLot ? "ON" : "OFF", InpRiskPercent, InpFixedLot,
               InpMaxSpreadDollars,
               InpSellBreakPrevLow  ? "ON" : "off",
               InpSellBreakSwingLow ? "ON" : "off",
               InpSellEMA20Slope    ? "ON" : "off");

   PrintFormat("[M5X] ExhaustionFilter=%s | Cap=%.2f | Scope=CANDLE (structural) | live port of validated v3.0 Variant A",
               InpUseM5ExhaustionFilter ? "ON" : "OFF", InpM5ExhaustionCap); // [M5X] deploy verification banner

   Print("[RC2.5 PORTABLE v1.1] Telemetry CSVs are routed into the active SOF Run folder; trading logic unchanged.");

   g_h4_ema50_handle  = iMA(_Symbol, PERIOD_H4, InpH4_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_h4_ema200_handle = iMA(_Symbol, PERIOD_H4, InpH4_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   g_h1_ema20_handle  = iMA(_Symbol, PERIOD_H1, InpH1_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_h1_ema50_handle  = iMA(_Symbol, PERIOD_H1, InpH1_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   g_h1_atr_handle    = iATR(_Symbol, PERIOD_H1, 14);
   g_rc24_h1_atr_handle = iATR(_Symbol, PERIOD_H1, 14);
   g_m5_ema20_handle  = iMA(_Symbol, PERIOD_M5, 20,             0, MODE_EMA, PRICE_CLOSE);

   if(g_h4_ema50_handle  == INVALID_HANDLE ||
      g_h4_ema200_handle == INVALID_HANDLE ||
      g_h1_ema20_handle  == INVALID_HANDLE ||
      g_h1_ema50_handle  == INVALID_HANDLE ||
      g_h1_atr_handle    == INVALID_HANDLE ||
      g_rc24_h1_atr_handle == INVALID_HANDLE ||
      g_m5_ema20_handle  == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create one or more indicator handles. Check symbol/timeframe.");
      return FailInitialization("Indicator handle creation failed");
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);

   // Shared UEE parity configuration: H4H1 strategy gates have already
   // established maturity and engulf evidence before Candidate creation.
   UEE_ResetState(g_h4h1_uee_state);
   g_h4h1_uee_config = UEE_MakeConfig(UEE_DIR_UP,1,UEE_PATTERN_REQUIRED,UEE_TAG_CANONICAL);
   g_uee_session_id = IntegerToString((int)TimeCurrent()) + "_" + IntegerToString(InpMagicNumber);
   // Non-fatal observability initialization: a logging failure must never
   // change entry decisions or order execution. Header files are created at
   // OnInit even when the test produces zero UEE evaluations.
   // Aurex Shared UEE Standard: observability is mandatory. A build that
   // cannot create its UEE audit artifacts must not silently continue.
   const bool ueeLoggingOK = UEE_InitializeLogging(g_pathUEEDecisions,g_pathUEEState,true);
   PrintFormat("[UEE][LOGGER][V1.1.2] InitStatus=%s | Decisions=%s | State=%s",
               (ueeLoggingOK ? "OK" : "FAILED"),g_pathUEEDecisions,g_pathUEEState);
   if(!ueeLoggingOK || !UEE_LoggingReady())
     {
      PrintFormat("[UEE][LOGGER][FATAL] Standard artifacts unavailable. Error=%d",GetLastError());
      return FailInitialization("Shared UEE logger initialization failed");
     }
   UEE_EvaluationContext initCtx = UEE_MakeEvaluationContext(
      g_uee_session_id,"H4H1_BUY_1506491_B1_PROD",InpMagicNumber,0,
      "UEE_STANDARD",_Symbol,"M5",TimeCurrent(),
      (bool)MQLInfoInteger(MQL_TESTER) ? "BACKTEST" : "LIVE");
   UEE_LogInitialization(initCtx);
   g_trade.SetDeviationInPoints(InpDeviationPoints);

   Comment("H4H1 Trend EA v4.3 — initialising...");
   CSVOpen();
   CSVWrite("INIT", "SYSTEM", 0, 0.0, 0.0, 0.0, 0.0, 0, 0.0, 0.0,
            "H4H1 Trend EA v4.3 BUY-only ForensicLog initialised");

   //--- SOF session start. Deliberately non-fatal: SOF is a read-only
   //    observer, so a failure here must never block live trading.
   SOF_MapReset();
   g_sofStarted = g_sof.Begin(
                     "H4H1_BUY_1506491_FAMILY_B_B1",
                     InpMagicNumber,
                     _Symbol,
                     SOF_DIR_BUY,
                     (bool)MQLInfoInteger(MQL_TESTER) ? SOF_MODE_BACKTEST : SOF_MODE_DEMO,
                     "1506491.FAMILY_B.B1.PRODUCTION.RC1",
                     "5.11",
                     "baseline=1506292-shadow-certified-B1",
                     g_pathSOFSession,g_pathSOFErrors,g_pathSOFGates,g_pathSOFTrades,g_pathSOFSummary
                  );
   if(g_sofStarted)
     {
      // 14 source-literal gates, as approved. Gates 1-5 are a decomposition
      // of the original compound "if(pullback && !g_setup_triggered &&
      // depth_ok && duration_ok && ema20_ok)" condition -- SOF evaluates the
      // same already-computed booleans in the same short-circuit order;
      // the compound condition itself is never modified. One Evaluation is
      // opened per new completed M5 bar (see g_sofLastM5BarTime), not per
      // tick -- proven safe because the engulf-detection path uses only
      // rates[1]/rates[2] (closed candles), never rates[0].
      g_sof.Gates.RegisterGate("H4Trend",              0,  "H4 trend non-neutral after EMA-distance filter");
      g_sof.Gates.RegisterGate("PullbackActive",       1,  "H1 pullback into EMA20/EMA50 detected");
      g_sof.Gates.RegisterGate("OneSignalPerPullback", 2,  "No signal has fired yet this pullback (!g_setup_triggered)");
      g_sof.Gates.RegisterGate("PullbackDepth",        3,  "Pullback depth >= ATR(14) * InpMinPullbackDepthATR (or disabled)");
      g_sof.Gates.RegisterGate("PullbackMaturity",     4,  "Closed H1 bar count >= InpMinPullbackBars");
      g_sof.Gates.RegisterGate("EMA20Touch",           5,  "H1 EMA20 touched this pullback (or InpRequireEMA20Touch=false)");
      g_sof.Gates.RegisterGate("BullishEngulf",        6,  "Body-only bullish engulf detected on rates[1]/rates[2]");
      g_sof.Gates.RegisterGate("MinimumEngulfRatio",   7,  "cur_body >= prv_body * InpMinEngulfRatio");
      g_sof.Gates.RegisterGate("M5Exhaustion",         8,  "!IsM5Exhaustion(cur_body, prv_body) -- [M5X] cap filter");
      g_sof.Gates.RegisterGate("DirectionAllowed",     9,  "trend==1 && InpTradeDirection != 2 (BUY permitted)");
      g_sof.Gates.RegisterGate("Spread",               10, "IsSpreadOK() inside PlacePending");
      g_sof.Gates.RegisterGate("StopsLevelValid",      11, "Entry price clears broker stops level vs current Ask");
      g_sof.Gates.RegisterGate("LotValid",             12, "CalcLotSize()/InpFixedLot result > 0");
      g_sof.Gates.RegisterGate("OrderExecution",       13, "g_trade.BuyStop() request accepted by broker");
      Print("[SOF] Session started for H4H1_BUY_1506272_v4_4_M5X_SOF");
     }
   else
     {
      Print("[SOF] Session failed to start -- EA continues normally without observability.");
     }

   //-----------------------------------------------------------------
   // [PRME EXTRACTION] Shared Aurex PRME engine setup -- PRME V3 ACTIVE
   // BUILD. PRME_DefaultH4H1BuyConfig() sets Policy=PRME_P0_FIXED (no
   // partial/BE/trail/time-exit), matching H4H1 BUY's actual current
   // live behavior exactly, since it has no embedded management to
   // begin with. Deliberately non-fatal, same reasoning as SOF above.
   // Reuses g_h1_atr_handle (already created above for the strategy's
   // own H1 ATR pullback-depth logic) rather than creating a duplicate
   // handle.
   //-----------------------------------------------------------------

   g_b1LifecycleFile=FileOpen(g_sessionMgr.GetRunFilePath(InpB1LifecycleFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(g_b1LifecycleFile==INVALID_HANDLE) return FailInitialization("B1 lifecycle logger initialization failed");
   B1LifeHeader();
   if(InpB1RequireHedgingForMax3 && InpMaxPositionSlots>1)
     {
      ENUM_ACCOUNT_MARGIN_MODE mm=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return FailInitialization("B1 Max3 requires hedging account");
     }
   PrintFormat("[1506491 C6 RESEARCH] READY | Family-B 15m grace control + BTB-T immediate protected BE after TP1 | entry rules unchanged | 0.02 lot | SHARED global MaxSlots=%d",InpMaxPositionSlots);

   // [B RC1] Base deployment contract remains narrow for A/B/C/D; C5 adds research family T outside that legacy family toggle set.
   // Fail fast instead of silently turning it back into A/B/C/D ALL.
   if(InpBRC_RequireBuyOnly && InpV10TradeDirection!=1)
     {
      Print("[B_RC_CONFIG_ERROR] Required InpV10TradeDirection=1 (BUY only).");
      return FailInitialization("B RC1 BUY-only contract violated");
     }
   if(InpBRC_RequireFamilyBOnly &&
      (InpV10FamilyA_FirstConfirm || !InpV10FamilyB_ContinuationBOS ||
       InpV10FamilyC_RBRDBD || InpV10FamilyD_RecoveryConfirm))
     {
      Print("[B_RC_CONFIG_ERROR] Required families: A=OFF B=ON C=OFF D=OFF.");
      return FailInitialization("B RC1 family contract violated");
     }

   // Research Profile contract. Fail fast rather than silently testing a
   // different sizing/partial-close configuration.
   if(InpUseRiskLot || MathAbs(InpFixedLot-0.02)>0.0000001 ||
      MathAbs(InpPRME_TP1GoldPoints-500.0)>0.0000001 ||
      MathAbs(InpPRME_PartialPct-50.0)>0.0000001 || InpMaxPositionSlots!=3)
     {
      Print("[RESEARCH_PROFILE_CONFIG_ERROR] Required: UseRiskLot=false; FixedLot=0.02; MaxSlots=3; TP1GoldPoints=500; PartialPct=50.");
      return FailInitialization("Research Profile input contract violated");
     }

   PRME_Config prmeCfg       = PRME_DefaultH4H1BuyConfig();
   // [LD1 v1.2] This structural EA trades BOTH directions. The H4H1 BUY
   // factory defaults DirectionMode to BUY, which caused SELL positions to
   // be adopted but skipped by ManageOpenPositions_Internal().
   prmeCfg.DirectionMode       = PRME_DIRECTION_MODE_BOTH;
   prmeCfg.Symbol             = _Symbol;
   prmeCfg.MagicNumber        = InpMagicNumber;
   prmeCfg.DeviationPoints    = InpDeviationPoints;

   // B RC1 capital-protection runner: each fresh B entry is 0.02.
   // At USD 10 floating profit -> close 50% (0.01), then protect the
   // remaining 0.01 runner with BE + ATR trail. Structural B orders have
   // no fixed TP so the runner can participate in extended H4/H1 trends.
   // The unified trigger engine measures favorable XAU PRICE MOVE for
   // each independently tracked ticket. Entry logic remains native H4H1.
   prmeCfg.Policy                  = PRME_P6_BE_TRAIL_PART;
   prmeCfg.PartialPct              = InpPRME_PartialPct;
   prmeCfg.RequirePartialBeforeBE  = true;
   prmeCfg.BEBufferPoints          = InpPRME_BEBufferPoints;
   prmeCfg.ATRMult                 = 1000.0; // B1 production: local runner manager owns trail
   prmeCfg.DebugLogManagement      = InpPRME_DebugManagement;

   double tp1PriceMove = H4H1_GoldPointsToPriceMove(InpPRME_TP1GoldPoints);

   prmeCfg.UseTP1Points            = false;
   prmeCfg.UseTP1PriceMove         = true;
   prmeCfg.TP1PriceMove            = tp1PriceMove; // keep legacy PRME validator synchronized
   prmeCfg.UseTP1PointsForBE       = false;
   prmeCfg.UseUnifiedTriggerEngine = true;
   prmeCfg.PartialTriggerMode      = PRME_TRIGGER_PRICE_MOVE;
   prmeCfg.PartialTriggerValue     = tp1PriceMove;
   prmeCfg.BETriggerMode           = PRME_TRIGGER_PRICE_MOVE;
   prmeCfg.BETriggerValue          = 1.0e9; // B1 production: shared-PRME BE suppressed; local 15m grace/BE owns protection
   if(!g_prme.Initialize(prmeCfg, GetPointer(g_prmeEvents), g_pathPRMELifecycle, g_pathPRMEState))
     {
      Print("[H4H1_BUY_1506272] FATAL: Aurex PRME engine failed to initialize -- see PRME diagnostics.");
      return FailInitialization("Shared PRME initialization failed");
     }
   else
     {
      Print("[H4H1_BUY_1506272] Aurex PRME engine initialized OK | Lifecycle=", g_pathPRMELifecycle, " | PRMEState=", g_pathPRMEState,
            " | Profile=RESEARCH_V1 | Policy=P6_BE_TRAIL_PART | TP1Mode=PRICE_MOVE | TP1GoldPts=",
            DoubleToString(InpPRME_TP1GoldPoints,0), " | TP1PriceMove=", DoubleToString(tp1PriceMove,3),
            " | Partial=", DoubleToString(InpPRME_PartialPct,1), "% | local 15m grace/BE | ATRTrail=",
            DoubleToString(InpPRME_ATRTrailMult,2));
   Print("[AUREX_GOLD_GEOMETRY] STANDARD | 100 GoldPts=1.00 XAU price | TP1=500 GoldPts=5.00 XAU price move | AccountCurrency=REPORTING_ONLY");
     }

   
   // [STRUCT-OBS] Shared MarketPhase observer initialization; read-only.
   if(InpStructObsEnable)
     {
      MarketPhaseConfig structCfg = MarketPhaseConfig_Defaults();
      structCfg.BootstrapBars = MathMax(500,InpStructObsBootstrapBars);
      bool sh4 = g_structMP_H4.Init(_Symbol,PERIOD_H4,structCfg,"H4H1_STRUCT_H4");
      bool sh1 = g_structMP_H1.Init(_Symbol,PERIOD_H1,structCfg,"H4H1_STRUCT_H1");
      bool sm15= g_structMP_M15.Init(_Symbol,PERIOD_M15,structCfg,"H4H1_STRUCT_M15");
      g_structMPReady=(sh4 && sh1 && sm15);
      if(!g_structMPReady)
        {
         PrintFormat("[STRUCT-OBS][INIT FATAL] MarketPhase H4=%s H1=%s M15=%s",
                     sh4?"OK":"FAIL",sh1?"OK":"FAIL",sm15?"OK":"FAIL");
         return INIT_FAILED;
        }
      g_structObsHandle=FileOpen(g_sessionMgr.GetRunFilePath(InpStructObsFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_structObsHandle==INVALID_HANDLE)
        {
         PrintFormat("[STRUCT-OBS][INIT FATAL] Cannot open %s err=%d",g_sessionMgr.GetRunFilePath(InpStructObsFile),GetLastError());
         return INIT_FAILED;
        }
      StructWriteHeader();
      PrintFormat("[STRUCT-OBS] READY | file=%s | bootstrap=%d | observer-only",
                  g_sessionMgr.GetRunFilePath(InpStructObsFile),structCfg.BootstrapBars);
     }


   if(InpStructObsEnable)
     {
      g_v02File=FileOpen(g_sessionMgr.GetRunFilePath(InpStructObsV02File),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_v02File==INVALID_HANDLE){PrintFormat("[STRUCT V0.2] file open failed %d",GetLastError());return INIT_FAILED;}
      V02Header();
      Print("[STRUCT V0.2] READY — dedicated pivot BOS + RBR/DBD, observer only");
     }

   if(InpStructObsEnable)
     {
      g_dirFile=FileOpen(g_sessionMgr.GetRunFilePath(InpDirObsFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_dirFile==INVALID_HANDLE){PrintFormat("[DIR V0.3] file open failed %d",GetLastError());return INIT_FAILED;}
      DirHeader();
      Print("[DIR V0.3] READY — UNKNOWN/DEVELOPING/CONFIRMED observer only");
     }

   if(InpStructObsEnable)
     {
      g_lcFile=FileOpen(g_sessionMgr.GetRunFilePath(InpLifecycleObsFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_lcFile==INVALID_HANDLE){PrintFormat("[LIFECYCLE V0.4] file open failed %d",GetLastError());return INIT_FAILED;}
      LifecycleHeader();
      Print("[LIFECYCLE V0.4] READY — ordered breakout lifecycle observer only");
     }

   if(InpStructObsEnable)
     {
      g_v05File=FileOpen(g_sessionMgr.GetRunFilePath(InpV05ObsFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_v05File==INVALID_HANDLE){PrintFormat("[V0.5] file open failed %d",GetLastError());return INIT_FAILED;}
      V05Header();
      Print("[V0.5] READY — breakout/retest/acceptance lifecycle observer only");
     }

   if(InpStructObsEnable)
     {
      g_v06StateFile=FileOpen(g_sessionMgr.GetRunFilePath(InpV06StateFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      g_v06EpisodeFile=FileOpen(g_sessionMgr.GetRunFilePath(InpV06EpisodeFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_v06StateFile==INVALID_HANDLE || g_v06EpisodeFile==INVALID_HANDLE)
        {
         PrintFormat("[V0.6] telemetry open failed | state=%d episode=%d err=%d",
                     g_v06StateFile,g_v06EpisodeFile,GetLastError());
         return INIT_FAILED;
        }
      V06StateHeader();
      V06EpisodeHeader();
      Print("[V0.6] READY — general market lifecycle observer only");
     }


   if(InpStructObsEnable)
     {
      g_v07File=FileOpen(g_sessionMgr.GetRunFilePath(InpV07EpisodeLegFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_v07File==INVALID_HANDLE)
        {
         PrintFormat("[V0.7] file open failed %d",GetLastError());
         return INIT_FAILED;
        }
      V07Header();
      Print("[V0.7] READY — TrendEpisode/TrendLeg hierarchy observer only");
     }


   if(InpStructObsEnable)
     {
      g_v08EventFile=FileOpen(g_sessionMgr.GetRunFilePath(InpV08EventFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      g_v08ResolutionFile=FileOpen(g_sessionMgr.GetRunFilePath(InpV08ResolutionFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_v08EventFile==INVALID_HANDLE || g_v08ResolutionFile==INVALID_HANDLE)
        {
         PrintFormat("[V0.8] telemetry open failed event=%d resolution=%d err=%d",
                     g_v08EventFile,g_v08ResolutionFile,GetLastError());
         return INIT_FAILED;
        }
      V08EventHeader();
      V08ResolutionHeader();
      Print("[V0.8] READY — leg failure / episode unresolved observer only");
     }


   if(InpStructObsEnable)
     {
      g_v09File=FileOpen(g_sessionMgr.GetRunFilePath(InpV09EventFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_v09File==INVALID_HANDLE)
        {
         PrintFormat("[V0.9] file open failed %d",GetLastError());
         return INIT_FAILED;
        }
      V09Header();
      Print("[V0.9] READY — H1 structural event dedup observer only");
     }

   if(InpBTBShadowEnable)
     {
      g_btbFile=FileOpen(g_sessionMgr.GetRunFilePath(InpBTBShadowFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_btbFile==INVALID_HANDLE)
        {
         PrintFormat("[BTB_C5] shadow file open failed %d",GetLastError());
         return INIT_FAILED;
        }
      BTBHeader();
      g_btbMatrixFile=FileOpen(g_sessionMgr.GetRunFilePath(InpBTBMatrixFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_btbMatrixFile==INVALID_HANDLE)
         PrintFormat("[BTB_C5] robustness file open failed %d",GetLastError());
      else
         BTBMatrixHeader();
      PrintFormat("[BTB_C5] READY — A_OR_B actual-execution challenger=%s | Family-B control unchanged | shared MaxSlots=%d",InpBTBC5ExecuteTransition?"ON":"OFF",InpMaxPositionSlots);
     }


   g_ld1ParityFile=FileOpen(g_sessionMgr.GetRunFilePath(InpLD1ParityFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(g_ld1ParityFile==INVALID_HANDLE)
     {
      PrintFormat("[LD1] parity audit file open failed %d",GetLastError());
      return INIT_FAILED;
     }
   LD1ParityHeader();

   g_v10File=FileOpen(g_sessionMgr.GetRunFilePath(InpV10TradeFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(g_v10File==INVALID_HANDLE)
     {
      PrintFormat("[V1.0] trade research file open failed %d",GetLastError());
      return INIT_FAILED;
     }
   V10Header();
   PrintFormat("[V1.0] TRADEABLE STRUCTURAL RESEARCH READY | Legacy=%s | Direction=%d | Magic=%d",
               InpV10EnableLegacyEntries?"ON":"OFF",InpV10TradeDirection,InpMagicNumber);


   if(InpEPRShadowEnable)
     {
      g_eprFile=FileOpen(g_sessionMgr.GetRunFilePath(InpEPRShadowFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_eprFile==INVALID_HANDLE)
        {
         PrintFormat("[1506491 EPR] shadow file open failed %d",GetLastError());
         return INIT_FAILED;
        }
      EPR_Header();
      Print("[1506491 EPR] READY — real BUY STOP unchanged; paired LIMIT + TP protection matrix is shadow-only");
     }

   if(Inp1290EnableAdaptiveDelayedShadow)
     {
      g_adpFile=FileOpen(g_sessionMgr.GetRunFilePath(Inp1290ShadowFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_adpFile==INVALID_HANDLE)
        {
         PrintFormat("[1506290 ADP] shadow file open failed %d",GetLastError());
         return INIT_FAILED;
        }
      ADP_Header();
      Print("[1506290 ADP] READY — adaptive STOP/LIMIT + delayed runner protection matrix is ACTIVE (shadow only)");
     }


   if(Inp1291EnableGraceShadow)
     {
      g_graceFile=FileOpen(g_sessionMgr.GetRunFilePath(Inp1291GraceFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(g_graceFile==INVALID_HANDLE)
        {
         PrintFormat("[1506491 GRACE] shadow file open failed %d",GetLastError());
         return INIT_FAILED;
        }
      GRACE_Header();
      Print("[1506491 GRACE] READY — adaptive entry frozen; TP1 grace/delayed-BE policies ACTIVE (shadow only)");
     }


   if(!InpRC2EnforceRunnerATRTrail)
     {
      Print("[RC2_CONFIG_ERROR] InpRC2EnforceRunnerATRTrail must remain true for RC2 certification.");
      return FailInitialization("RC2 runner-trail enforcement disabled");
     }

   g_rc2RunnerAudit=FileOpen(g_sessionMgr.GetRunFilePath(InpRC2RunnerAuditFile),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(g_rc2RunnerAudit==INVALID_HANDLE)
     {
      PrintFormat("[RC2] Runner audit open failed err=%d",GetLastError());
      return INIT_FAILED;
     }
   RC21RunnerAuditHeader();
   Print("[RC2.5] READY — B-only BUY | lifecycle-driven partial->BE->H1 ATR runner");

return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
  {
   B1CancelAllPending();
   if(g_b1LifecycleFile!=INVALID_HANDLE){FileFlush(g_b1LifecycleFile);FileClose(g_b1LifecycleFile);g_b1LifecycleFile=INVALID_HANDLE;}
   GRACE_FlushOpenAtEnd();
   if(g_graceFile!=INVALID_HANDLE)
     {
      FileFlush(g_graceFile);
      FileClose(g_graceFile);
      g_graceFile=INVALID_HANDLE;
     }

   ADP_FlushOpenAtEnd();
   if(g_adpFile!=INVALID_HANDLE)
     {
      FileFlush(g_adpFile);
      FileClose(g_adpFile);
      g_adpFile=INVALID_HANDLE;
     }

   EPR_FlushOpenAtEnd();
   if(g_eprFile!=INVALID_HANDLE)
     {
      FileFlush(g_eprFile);
      FileClose(g_eprFile);
      g_eprFile=INVALID_HANDLE;
     }

   if(g_rc2RunnerAudit!=INVALID_HANDLE)
     {
      FileFlush(g_rc2RunnerAudit);
      FileClose(g_rc2RunnerAudit);
      g_rc2RunnerAudit=INVALID_HANDLE;
     }

   if(g_v02File!=INVALID_HANDLE){FileFlush(g_v02File);FileClose(g_v02File);g_v02File=INVALID_HANDLE;}
   if(g_dirFile!=INVALID_HANDLE){FileFlush(g_dirFile);FileClose(g_dirFile);g_dirFile=INVALID_HANDLE;}
   if(g_lcFile!=INVALID_HANDLE){FileFlush(g_lcFile);FileClose(g_lcFile);g_lcFile=INVALID_HANDLE;}
   if(g_v05File!=INVALID_HANDLE){FileFlush(g_v05File);FileClose(g_v05File);g_v05File=INVALID_HANDLE;}
   if(g_v06EpisodeID!="")
     {
      V06CloseEpisode(TimeCurrent(),"TEST_END_OR_DEINIT");
      V06ResetState();
     }
   if(g_v06StateFile!=INVALID_HANDLE)
     {
      FileFlush(g_v06StateFile);
      FileClose(g_v06StateFile);
      g_v06StateFile=INVALID_HANDLE;
     }
   if(g_v06EpisodeFile!=INVALID_HANDLE)
     {
      FileFlush(g_v06EpisodeFile);
      FileClose(g_v06EpisodeFile);
      g_v06EpisodeFile=INVALID_HANDLE;
     }

   if(g_v07File!=INVALID_HANDLE)
     {
      FileFlush(g_v07File);
      FileClose(g_v07File);
      g_v07File=INVALID_HANDLE;
     }

   if(g_v08EventFile!=INVALID_HANDLE)
     {
      FileFlush(g_v08EventFile);
      FileClose(g_v08EventFile);
      g_v08EventFile=INVALID_HANDLE;
     }
   if(g_v08ResolutionFile!=INVALID_HANDLE)
     {
      FileFlush(g_v08ResolutionFile);
      FileClose(g_v08ResolutionFile);
      g_v08ResolutionFile=INVALID_HANDLE;
     }

   BTBFlushAtEnd();
   if(g_btbFile!=INVALID_HANDLE)
     {
      FileFlush(g_btbFile);
      FileClose(g_btbFile);
      g_btbFile=INVALID_HANDLE;
     }
   if(g_btbMatrixFile!=INVALID_HANDLE)
     {
      FileFlush(g_btbMatrixFile);
      FileClose(g_btbMatrixFile);
      g_btbMatrixFile=INVALID_HANDLE;
     }

   if(g_v09File!=INVALID_HANDLE)
     {
      FileFlush(g_v09File);
      FileClose(g_v09File);
      g_v09File=INVALID_HANDLE;
     }

   if(g_ld1ParityFile!=INVALID_HANDLE)
     {
      FileFlush(g_ld1ParityFile);
      FileClose(g_ld1ParityFile);
      g_ld1ParityFile=INVALID_HANDLE;
     }

   if(g_v10File!=INVALID_HANDLE)
     {
      FileFlush(g_v10File);
      FileClose(g_v10File);
      g_v10File=INVALID_HANDLE;
     }

   // [STRUCT-OBS] Observer cleanup; no trade operations.
   if(g_structObsHandle!=INVALID_HANDLE)
     {
      FileFlush(g_structObsHandle);
      FileClose(g_structObsHandle);
      g_structObsHandle=INVALID_HANDLE;
     }
   if(g_structMPReady)
     {
      g_structMP_H4.Shutdown();
      g_structMP_H1.Shutdown();
      g_structMP_M15.Shutdown();
      g_structMPReady=false;
     }

   CancelPending();
   ReleaseIndicatorHandlesSOFV2();
   Comment("");

   // [PRME EXTRACTION] SyncOnShutdown() does the lifecycle-only part and
   // NEVER calls trade management -- removing this EA or changing
   // timeframe cannot place or modify a real trade operation via this
   // path. Shutdown() then closes the engine's own Lifecycle.csv/
   // PRMEState.csv file handles. No separate indicator handle to
   // release here -- PRME reuses g_h1_atr_handle, already released
   // above.
   g_prme.SyncOnShutdown();
   g_prme.Shutdown();
   UEE_ShutdownLogging();


   double win_rate  = (g_stat_trades > 0)
                      ? (double)g_stat_wins  / g_stat_trades * 100.0 : 0.0;
   double buy_wr    = (g_buy_wins  + g_buy_losses  > 0)
                      ? (double)g_buy_wins  / (g_buy_wins  + g_buy_losses)  * 100.0 : 0.0;
   double sell_wr   = (g_sell_wins + g_sell_losses > 0)
                      ? (double)g_sell_wins / (g_sell_wins + g_sell_losses) * 100.0 : 0.0;

   string dir_label = (InpTradeDirection == 1) ? "BUY ONLY" :
                      (InpTradeDirection == 2) ? "SELL ONLY" : "BOTH";

   Print("======================== SESSION SUMMARY");
   PrintFormat("Version                  : H4H1 BUY v5.1.1 RESEARCH PROFILE RC1 | UEE 1.1.3");
   PrintFormat("Direction                : %s", dir_label);
   PrintFormat("InpMinPullbackBars       : %d", InpMinPullbackBars);
   PrintFormat("InpMinPullbackDepthATR   : %.2f", InpMinPullbackDepthATR);
   PrintFormat("InpPRME_TP1GoldPoints    : %.0f (= %.3f XAU price move)", InpPRME_TP1GoldPoints, H4H1_GoldPointsToPriceMove(InpPRME_TP1GoldPoints));
   PrintFormat("InpPRME_PartialPct       : %.1f", InpPRME_PartialPct);
   PrintFormat("InpPRME_BEBufferPoints   : %.1f", InpPRME_BEBufferPoints);
   PrintFormat("InpPRME_ATRTrailMult     : %.2f", InpPRME_ATRTrailMult);
   PrintFormat("InpMinH4EMADistance      : %.1f", InpMinH4EMADistance);
   PrintFormat("InpRiskReward            : %.1f", InpRiskReward);
   PrintFormat("InpMinEngulfRatio        : %.1f", InpMinEngulfRatio);
   PrintFormat("[M5X] ExhaustionFilter    : %s | Cap=%.2f | Scope=CANDLE (structural)",
               InpUseM5ExhaustionFilter ? "ON" : "OFF", InpM5ExhaustionCap); // [M5X]
   PrintFormat("InpRequireEMA20Touch     : %s",   InpRequireEMA20Touch ? "true" : "false");
   Print("---  v4.3 H4 Trend Detection Diagnostics + Bear Bar Audit");
   PrintFormat("H4 bars sampled          : %d", g_ema_dist_count);
   Print("  --- Raw H4 EMA alignment (BEFORE distance filter) ---");
   PrintFormat("H4 Bear Trend Bars (raw) : %d  (EMA50 < EMA200)", g_h4_raw_bear_bars);
   PrintFormat("H4 Bull Trend Bars (raw) : %d  (EMA50 > EMA200)", g_h4_raw_bull_bars);
   PrintFormat("H4 Neutral Bars (raw)    : %d  (EMA50 == EMA200)", g_h4_raw_neutral_bars);
   Print("  --- Post-filter H4 trend (AFTER distance filter) ---");
   PrintFormat("H4 Bear Trend Bars (post): %d  (trend==-1 used by strategy)", g_h4_post_bear_bars);
   PrintFormat("H4 Bull Trend Bars (post): %d  (trend==1  used by strategy)", g_h4_post_bull_bars);
   PrintFormat("H4 Neutral Bars (post)   : %d  (trend==0  — includes suppressed)", g_h4_post_neutral_bars);
   Print("  --- Distance filter suppression ---");
   PrintFormat("SuppressedBearBars       : %d  (raw BEAR → forced NEUTRAL)", g_h4_suppressed_bear);
   PrintFormat("SuppressedBullBars       : %d  (raw BULL → forced NEUTRAL)", g_h4_suppressed_bull);
   PrintFormat("H4 EMA Dist Suppressed   : %d  (tick-level counter, may differ from bar count)", g_ema_dist_suppressed);
   Print("  --- Symmetry verification ---");
   PrintFormat("Filter is symmetric      : %s  (same < MinDist condition for BULL and BEAR)",
               "YES — single branch: if(MathAbs(EMA50-EMA200) < MinDist) trend=0");
   PrintFormat("Bear suppressed %%        : %.1f %%  (%d of %d raw bear bars suppressed)",
               (g_h4_raw_bear_bars > 0) ? (double)g_h4_suppressed_bear / g_h4_raw_bear_bars * 100.0 : 0.0,
               g_h4_suppressed_bear, g_h4_raw_bear_bars);
   PrintFormat("Bull suppressed %%        : %.1f %%  (%d of %d raw bull bars suppressed)",
               (g_h4_raw_bull_bars > 0) ? (double)g_h4_suppressed_bull / g_h4_raw_bull_bars * 100.0 : 0.0,
               g_h4_suppressed_bull, g_h4_raw_bull_bars);
   Print("  --- EMA distance statistics ---");
   {
    double ema_avg = (g_ema_dist_count > 0) ? g_ema_dist_sum / g_ema_dist_count : 0.0;
    double ema_min_display = (g_ema_dist_min == DBL_MAX) ? 0.0 : g_ema_dist_min;
    PrintFormat("EMA Distance Min         : %.2f", ema_min_display);
    PrintFormat("EMA Distance Max         : %.2f", g_ema_dist_max);
    PrintFormat("EMA Distance Avg         : %.2f", ema_avg);
    PrintFormat("MinDist threshold        : %.2f  (%s)",
                InpMinH4EMADistance,
                (ema_min_display < InpMinH4EMADistance)
                ? "gap dips BELOW threshold — some bars suppressed"
                : "gap never below threshold — no suppression expected");
   }
   PrintFormat("RAW-BEAR-BAR log         : %d of %d entries printed (search RAW-BEAR-BAR in Experts tab)",
               g_raw_bear_log_count, g_h4_raw_bear_bars);
   PrintFormat("SUPPRESS-BEAR log        : %d of %d entries printed (search SUPPRESS-BEAR in Experts tab)",
               g_suppress_bear_log_count, g_h4_suppressed_bear);
   PrintFormat("If RAW-BEAR-BAR==SUPPRESS-BEAR : 100%% of bear bars have Dist < MinDist (%.2f)",
               InpMinH4EMADistance);
   Print("---  Pullback Filter");
   PrintFormat("Pullbacks Found          : %d", g_cnt_pullbacks_found);
   PrintFormat("Gate Passed (>=%d bars)  : %d", InpMinPullbackBars, g_cnt_duration_gate_pass);
   PrintFormat("Gate Rejected (<%d bars) : %d  (pullback ended before gate opened)", InpMinPullbackBars, g_cnt_duration_gate_rej);
   PrintFormat("Depth Rejected Pullbacks : %d", g_depth_rejected);
   PrintFormat("H4 EMA Dist Suppressed   : %d H4 bars", g_ema_dist_suppressed);
   Print("---  Signal Pipeline");
   PrintFormat("M5 Engulf Signals        : %d  (gate cleared → signal fired)", g_cnt_m5_after_duration);
   PrintFormat("BUY  Signals             : %d", g_buy_signals);
   PrintFormat("SELL Signals             : %d", g_sell_signals);
   PrintFormat("Orders Placed            : %d", g_orders_placed);
   Print("---  SELL Pipeline Diagnostics");
   PrintFormat("RawBearishEngulf         : %d  (body engulfs body, pre-ratio, pre-trend)", g_raw_bear_engulf);
   PrintFormat("TrendAlignedBear         : %d  (raw bear AND trend==-1, pre-direction-filter)", g_trend_aligned_bear);
   PrintFormat("SellSignals              : %d  (TrendAligned AND direction!=BuyOnly → signal fired)", g_sell_signals);
   PrintFormat("SellOrdersPlaced         : %d  (SELL STOP sent to broker successfully)", g_sell_orders_placed);
   PrintFormat("SellRejectedByStopsLevel : %d  (SELL STOP rejected — entry too close to Bid)", g_sell_rej_stops);
   Print("---  v4.1 SELL Confirmation Waterfall");
   PrintFormat("  Filters active: BreakPrevLow=%s  BreakSwingLow=%s  EMA20Slope=%s",
               InpSellBreakPrevLow  ? "ON" : "off",
               InpSellBreakSwingLow ? "ON" : "off",
               InpSellEMA20Slope    ? "ON" : "off");
   PrintFormat("  PRME V3 | RawBearishEngulf  : %d  (entry — bearish engulf post-trend-gate)", g_trend_aligned_bear);
   PrintFormat("  Stage 2 | BreakPrevLow      : %d  (close < previous candle low)", g_diag_break_prev_low);
   PrintFormat("  Stage 3 | BreakSwingLow     : %d  (low < lowest low of prior 3 M5 bars)", g_diag_break_swing_low);
   PrintFormat("  Stage 4 | EMA20SlopeBear    : %d  (M5 EMA20[1] < EMA20[2])", g_diag_ema20_slope_bear);
   PrintFormat("  Stage 5 | FinalSellSignal   : %d  (all enabled filters passed → signal fired)", g_diag_final_sell);
   PrintFormat("  Drop-off: S1→S2=%d  S2→S3=%d  S3→S4=%d  S4→S5=%d",
               g_trend_aligned_bear   - g_diag_break_prev_low,
               g_diag_break_prev_low  - g_diag_break_swing_low,
               g_diag_break_swing_low - g_diag_ema20_slope_bear,
               g_diag_ema20_slope_bear - g_diag_final_sell);
   Print("---  BUY Trade Outcomes");
   PrintFormat("BUY  Wins                : %d", g_buy_wins);
   PrintFormat("BUY  Losses              : %d", g_buy_losses);
   PrintFormat("BUY  Win Rate            : %.2f %%", buy_wr);
   Print("---  SELL Trade Outcomes");
   PrintFormat("SELL Wins                : %d", g_sell_wins);
   PrintFormat("SELL Losses              : %d", g_sell_losses);
   PrintFormat("SELL Win Rate            : %.2f %%", sell_wr);
   Print("---  Overall");
   PrintFormat("Total Trades             : %d", g_stat_trades);
   PrintFormat("Total Wins               : %d", g_stat_wins);
   PrintFormat("Total Losses             : %d", g_stat_losses);
   PrintFormat("Overall Win Rate         : %.2f %%", win_rate);
   Print("---  (PF / Net Profit / MaxDD : read from MT5 Report)");
   Print("======================== END SUMMARY");

   double win_rate_final = (g_stat_trades > 0)
                           ? (double)g_stat_wins / g_stat_trades * 100.0 : 0.0;
   CSVWrite("DEINIT", "SYSTEM", 0, 0.0, 0.0, 0.0, 0.0, 0, 0.0, 0.0,
            StringFormat("Trades=%d Wins=%d Losses=%d WR=%.2f",
                         g_stat_trades, g_stat_wins, g_stat_losses, win_rate_final));
   if(InpUseM5ExhaustionFilter)
      PrintFormat("[M5X] SUMMARY: %d bullish engulf signal(s) rejected by exhaustion cap %.2f", g_m5x_rejects, InpM5ExhaustionCap); // [M5X]
   CSVClose();

   SOF_EndSession();
   g_sessionMgr.LogRunEnded(StringFormat("Deinit reason=%d",reason));
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   H4H1Heartbeat(); // telemetry only: proves live tick/trade-permission/state path
   StructObserve(); // [STRUCT-OBS] read-only structural/MarketStage telemetry
   StructObserveV02(); // [STRUCT V0.2] BOS + RBR/DBD observer
   DirObserve(); // [STRUCT V0.3] directional evidence observer
   LifecycleObserve(); // [STRUCT V0.4] ordered breakout lifecycle observer
   V05Observe(); // [STRUCT V0.5] breakout/retest/acceptance observer
   V06Observe(); // [STRUCT V0.6] general market lifecycle/base-quality observer
   V07Observe(); // [STRUCT V0.7] TrendEpisode/TrendLeg hierarchy observer
   V08Observe(); // [STRUCT V0.8] leg-failure / unresolved-episode observer
   V10ObserveConfirmationTransition(); // [V1.0] queue A/D first-confirm candidates
   V09Observe(); // [STRUCT V0.9] H1 structural event dedup observer
   BTBUpdate(); // [BTB C5] shadow outcome tracking; no trade operations

   // SOF V2 trading-day rollover: move all logger handles to a new Run
   // before any strategy, UEE, PRME or SOF write occurs on this tick.
   if(g_sessionMgr.CheckDailyRollover())
     {
      if(!ReopenSOFV2LoggersAfterRollover())
        {
         Print("[H4H1 BUY SOF V2][ROLLOVER FATAL] Logging unavailable; skipping this tick.");
         return;
        }
     }

   //------------------------------------------------------------
   // 1. Ticket lifecycle check — must run first
   //    Clears g_pending_ticket if filled or gone, so
   //    CancelPending() never calls OrderDelete on a live position.
   //------------------------------------------------------------
   CheckTicketLifecycle();
   SOF_VerifyUnresolvedPending();
   V10ManagePendingExpiry();

   // [PRME EXTRACTION] Runs every tick, right after CheckTicketLifecycle()
   // so a position adopted this exact tick is picked up by
   // ManageOpenPositions() the same tick, not one tick later. Placed
   // before the SOF new-bar evaluation guard below -- that guard is
   // observational only (controls whether SOF opens an Evaluation this
   // tick) and must not, and does not, gate PRME. Under PRME V3's
   // PRME_P0_FIXED policy this is a no-op beyond adoption/tracking.
   g_prme.SetCurrentATR(GetPRME_ATR());
   g_prme.ManageOpenPositions();
   B1ProcessLocalArmedEntries();
   B1ExpirePendingOrders();
   B1ManageProductionRunners();
   EPR_Update();              // [1506290] baseline STOP/LIMIT + immediate-floor matrix; shadow only
   ADP_Update();              // [1506290 v0.2] adaptive-entry + delayed-protection matrix; shadow only
   GRACE_Update();            // [1506491] TP1 grace/delayed-BE matrix; shadow only
   V10ProcessQueuedCandidate(); // [V1.0] trade only after ticket lifecycle + PRME refresh
   if(g_recoveryPending)
     {
      g_sessionMgr.LogStateReconstructed(StringFormat("%d position(s) refreshed by PRME on first management tick",g_recoveryPosCount));
      g_sessionMgr.LogPRMEResumed(StringFormat("%d position(s) under normal PRME management",g_recoveryPosCount));
      g_recoveryPending=false;
     }

   //------------------------------------------------------------
   // SOF: M5-bar evaluation-scoping guard (approved decision 3). Purely
   // additive -- controls only whether SOF opens an Evaluation this tick.
   // Every tick below still runs the full strategy logic unconditionally,
   // regardless of this guard's value. Safe because the engulf-detection
   // path (further below) uses only rates[1]/rates[2] -- closed M5
   // candles -- and never rates[0], so the gate-chain result cannot
   // change mid-bar; re-observing it every tick would be pure duplication.
   //------------------------------------------------------------
   bool sofNewM5Bar = false;
   bool sofEvalOpen = false;
   if(g_sofStarted)
     {
      SOF_MapPruneStale();
      datetime sofM5Bar[1];
      if(CopyTime(_Symbol, PERIOD_M5, 0, 1, sofM5Bar) > 0 && sofM5Bar[0] != g_sofLastM5BarTime)
        {
         g_sofLastM5BarTime = sofM5Bar[0];
         sofNewM5Bar = true;
        }
     }
   g_sofRecordThisCall = sofNewM5Bar;   // plumbing for PlacePending(), read this tick only

   ulong sofEvalID = 0;
   if(sofNewM5Bar)
     {
      sofEvalID = g_sof.Gates.BeginEvaluation();
      sofEvalOpen = true;
     }
   g_sofCurrentEvalID = sofEvalID;

   //------------------------------------------------------------
   // 2. H4 trend — last CLOSED candle EMA values (shift=1)
   //------------------------------------------------------------
   double h4_ema50[1], h4_ema200[1];
   if(CopyBuffer(g_h4_ema50_handle,  0, 1, 1, h4_ema50)  <= 0)
     {
      // Data-integrity guard, not a registered gate (Phase 0 §3). Still
      // close any open SOF evaluation cleanly before the existing return.
      if(sofEvalOpen) { SOF_SkipRemainingGatesFrom(0); g_sof.Gates.EndEvaluation(); }
      return;
     }
   if(CopyBuffer(g_h4_ema200_handle, 0, 1, 1, h4_ema200) <= 0)
     {
      if(sofEvalOpen) { SOF_SkipRemainingGatesFrom(0); g_sof.Gates.EndEvaluation(); }
      return;
     }

   int trend;
   if(h4_ema50[0] > h4_ema200[0])      trend =  1;   // BULLISH
   else if(h4_ema50[0] < h4_ema200[0]) trend = -1;   // BEARISH
   else                                trend =  0;   // NEUTRAL

   //--- v4.2: capture raw trend BEFORE distance filter overwrites it
   int trend_raw = trend;

   //------------------------------------------------------------
   // 3. H4 EMA distance filter
   //    Gap < InpMinH4EMADistance → suppress trend to NEUTRAL.
   //    Prevents trading when EMA50 and EMA200 are converging.
   //    Counter increments once per H4 closed bar.
   //------------------------------------------------------------
   if(InpMinH4EMADistance > 0.0 && trend != 0)
     {
      if(MathAbs(h4_ema50[0] - h4_ema200[0]) < InpMinH4EMADistance)
        {
         datetime h4_bar_time[1];
         if(CopyTime(_Symbol, PERIOD_H4, 1, 1, h4_bar_time) > 0)
           {
            if(h4_bar_time[0] != g_last_h4_suppressed_bar_time)
              {
               g_last_h4_suppressed_bar_time = h4_bar_time[0];
               g_ema_dist_suppressed++;
              }
           }
         trend = 0;
        }
     }

   //------------------------------------------------------------
   // C4 RESEARCH: bullish transition admission BEFORE H4 EMA50/200 crossover.
   // Aurex point standard: 100 points = 1.00 XAUUSD price movement.
   // This does NOT place an order. It only upgrades the H4 admission state
   // to bullish; all native H1 pullback, M5 engulf/exhaustion, UEE, spread,
   // stops, sizing and order-execution gates remain unchanged downstream.
   //------------------------------------------------------------
   bool   c4_transition_admitted = false;
   double c4_gap_price           = 0.0;
   double c4_prev_gap_price      = 0.0;
   double c4_contract_price      = 0.0;
   double c4_fast_slope_price    = 0.0;
   bool   c4_h1_bull             = false;

   if(InpC4EnableTransition && trend_raw == -1)
     {
      double h4_ema50_prev[1], h4_ema200_prev[1];
      double c4_h1_ema20[1], c4_h1_ema20_prev[1], c4_h1_ema50[1];
      double c4_h1_close[1];

      bool c4_data_ok =
         (CopyBuffer(g_h4_ema50_handle,  0, 2, 1, h4_ema50_prev)  > 0) &&
         (CopyBuffer(g_h4_ema200_handle, 0, 2, 1, h4_ema200_prev) > 0) &&
         (CopyBuffer(g_h1_ema20_handle,  0, 1, 1, c4_h1_ema20)    > 0) &&
         (CopyBuffer(g_h1_ema20_handle,  0, 2, 1, c4_h1_ema20_prev)>0) &&
         (CopyBuffer(g_h1_ema50_handle,  0, 1, 1, c4_h1_ema50)    > 0) &&
         (CopyClose(_Symbol, PERIOD_H1, 1, 1, c4_h1_close)        > 0);

      if(c4_data_ok)
        {
         c4_gap_price        = MathMax(0.0, h4_ema200[0]      - h4_ema50[0]);
         c4_prev_gap_price   = MathMax(0.0, h4_ema200_prev[0] - h4_ema50_prev[0]);
         c4_contract_price   = c4_prev_gap_price - c4_gap_price;
         c4_fast_slope_price = h4_ema50[0] - h4_ema50_prev[0];

         double c4_max_gap_price = InpC4MaxBearGapAurexPoints / 100.0;
         double c4_min_contract_price = InpC4MinGapContractAurexPoints / 100.0;

         c4_h1_bull = (c4_h1_ema20[0] > c4_h1_ema50[0] &&
                       c4_h1_close[0] > c4_h1_ema20[0] &&
                       c4_h1_ema20[0] > c4_h1_ema20_prev[0]);

         bool c4_gap_ok      = (c4_gap_price <= c4_max_gap_price);
         bool c4_contract_ok = (c4_contract_price >= c4_min_contract_price);
         bool c4_slope_ok    = (c4_fast_slope_price > 0.0);
         bool c4_h1_ok       = (!InpC4RequireH1BullAlignment || c4_h1_bull);

         c4_transition_admitted = (c4_gap_ok && c4_contract_ok && c4_slope_ok && c4_h1_ok);
         if(c4_transition_admitted)
            trend = 1;

         if(sofNewM5Bar)
           {
            PrintFormat("[C4_TRANSITION] Admit=%s | Raw=%d Post=%d | GapPts=%.0f PrevGapPts=%.0f ContractPts=%.0f | H4FastSlopePts=%.0f | H1Bull=%s | MaxGapPts=%.0f MinContractPts=%.0f",
                        c4_transition_admitted ? "YES" : "NO", trend_raw, trend,
                        c4_gap_price*100.0, c4_prev_gap_price*100.0, c4_contract_price*100.0,
                        c4_fast_slope_price*100.0, c4_h1_bull ? "YES" : "NO",
                        InpC4MaxBearGapAurexPoints, InpC4MinGapContractAurexPoints);
           }
        }
     }

   if(sofEvalOpen)
     {
      if(trend != 0)
         g_sof.Gates.RecordGate("H4Trend", SOF_DIR_BUY, SOF_RESULT_PASS, trend, 0,
                                c4_transition_admitted ? "C4_TRANSITION_BULL" : "NATIVE_H4_TREND");
      else
        {
         g_sof.Gates.RecordGate("H4Trend", SOF_DIR_BUY, SOF_RESULT_FAIL, trend, 0,
                                (trend_raw==-1 ? "RAW_BEAR_NOT_C4_ADMITTED" : "neutral or suppressed"));
         SOF_SkipRemainingGatesFrom(1);
         g_sof.Gates.EndEvaluation();
         sofEvalOpen = false;
        }
     }

   //------------------------------------------------------------
   // v4.3 H4 trend detection diagnostics + bear bar full audit
   //
   // Runs once per closed H4 bar (bar-time guard: g_h4_diag_last_bar_time).
   //
   // SYMMETRY VERIFICATION (printed in log, confirmed in summary):
   //   The distance filter gate is:
   //     if(MathAbs(EMA50 - EMA200) < MinDistance) → trend = 0
   //   This is applied inside "if(trend != 0)" so both BULL and BEAR
   //   reach it. We verify this by logging SuppressedBull vs SuppressedBear —
   //   if both are > 0 when distances are small, the filter is symmetric.
   //
   // RAW-BEAR-BAR log (up to 50): fires on EVERY raw bear H4 bar, whether
   //   suppressed or not. Shows actual EMA values and distance vs threshold.
   //   This directly answers: "is distance < 40 on every bear bar?"
   //
   // SUPPRESS-BEAR log (up to 50): subset of RAW-BEAR-BAR where the bar
   //   was also suppressed. If RAW-BEAR-BAR count == SUPPRESS-BEAR count,
   //   then 100% of bear bars have distance < MinDistance.
   //------------------------------------------------------------
   {
    datetime h4_diag_bar[1];
    if(CopyTime(_Symbol, PERIOD_H4, 1, 1, h4_diag_bar) > 0 &&
       h4_diag_bar[0] != g_h4_diag_last_bar_time)
      {
       g_h4_diag_last_bar_time = h4_diag_bar[0];

       double ema_dist = MathAbs(h4_ema50[0] - h4_ema200[0]);

       //--- Raw trend bar counts (pre-filter)
       if(trend_raw ==  1) g_h4_raw_bull_bars++;
       else if(trend_raw == -1) g_h4_raw_bear_bars++;
       else                     g_h4_raw_neutral_bars++;

       //--- Post-filter trend bar counts
       if(trend ==  1) g_h4_post_bull_bars++;
       else if(trend == -1) g_h4_post_bear_bars++;
       else                 g_h4_post_neutral_bars++;

       //--- Suppressed bars
       if(trend_raw ==  1 && trend == 0) g_h4_suppressed_bull++;
       if(trend_raw == -1 && trend == 0) g_h4_suppressed_bear++;

       //--- EMA distance running stats
       g_ema_dist_count++;
       g_ema_dist_sum += ema_dist;
       if(ema_dist < g_ema_dist_min) g_ema_dist_min = ema_dist;
       if(ema_dist > g_ema_dist_max) g_ema_dist_max = ema_dist;

       //--- RAW-BEAR-BAR audit log (up to 50 entries)
       //    Fires on every H4 bar where EMA50 < EMA200, regardless of suppression.
       //    Column layout:
       //      Suppressed : YES/NO (distance < MinDist)
       //      EMA50      : raw EMA50 value
       //      EMA200     : raw EMA200 value
       //      Distance   : abs(EMA50 - EMA200)
       //      MinDist    : InpMinH4EMADistance threshold
       //      PostTrend  : actual trend value used by strategy (−1 or 0)
       if(trend_raw == -1 && g_raw_bear_log_count < 50)
         {
          g_raw_bear_log_count++;
          bool suppressed = (trend == 0);
          PrintFormat("RAW-BEAR-BAR #%02d | %s | Date: %s | EMA50: %s | EMA200: %s | Dist: %.2f | MinDist: %.2f | PostTrend: %d",
                      g_raw_bear_log_count,
                      suppressed ? "SUPPRESSED" : "PASSED    ",
                      TimeToString(h4_diag_bar[0], TIME_DATE|TIME_MINUTES),
                      DoubleToString(h4_ema50[0],  _Digits),
                      DoubleToString(h4_ema200[0], _Digits),
                      ema_dist,
                      InpMinH4EMADistance,
                      trend);
          if(g_raw_bear_log_count == 50)
             Print("RAW-BEAR-BAR | First-50 log complete. Further bear bars counted only.");
         }

       //--- SUPPRESS-BEAR log (up to 50 entries, subset of RAW-BEAR-BAR)
       //    Fires only when the bar was suppressed: EMA50 < EMA200 AND distance < MinDist.
       //    Kept separate so the two counts can be compared directly in the summary.
       if(trend_raw == -1 && trend == 0 && g_suppress_bear_log_count < 50)
         {
          g_suppress_bear_log_count++;
          PrintFormat("SUPPRESS-BEAR #%02d | Date: %s | EMA50: %s | EMA200: %s | Dist: %.2f | MinDist: %.2f",
                      g_suppress_bear_log_count,
                      TimeToString(h4_diag_bar[0], TIME_DATE|TIME_MINUTES),
                      DoubleToString(h4_ema50[0],  _Digits),
                      DoubleToString(h4_ema200[0], _Digits),
                      ema_dist,
                      InpMinH4EMADistance);
          if(g_suppress_bear_log_count == 50)
             Print("SUPPRESS-BEAR | First-50 log complete. Further suppressions counted only.");
         }
      }
   }

   //------------------------------------------------------------
   // 4. H1 data — last CLOSED candle (shift=1)
   //------------------------------------------------------------
   double h1_ema20[1], h1_ema50[1];
   double h1_high[1],  h1_low[1];
   if(CopyBuffer(g_h1_ema20_handle, 0, 1, 1, h1_ema20) <= 0)
     { if(sofEvalOpen) { SOF_SkipRemainingGatesFrom(1); g_sof.Gates.EndEvaluation(); sofEvalOpen = false; } return; }
   if(CopyBuffer(g_h1_ema50_handle, 0, 1, 1, h1_ema50) <= 0)
     { if(sofEvalOpen) { SOF_SkipRemainingGatesFrom(1); g_sof.Gates.EndEvaluation(); sofEvalOpen = false; } return; }
   if(CopyHigh(_Symbol, PERIOD_H1, 1, 1, h1_high)      <= 0)
     { if(sofEvalOpen) { SOF_SkipRemainingGatesFrom(1); g_sof.Gates.EndEvaluation(); sofEvalOpen = false; } return; }
   if(CopyLow (_Symbol, PERIOD_H1, 1, 1, h1_low)       <= 0)
     { if(sofEvalOpen) { SOF_SkipRemainingGatesFrom(1); g_sof.Gates.EndEvaluation(); sofEvalOpen = false; } return; }

   //------------------------------------------------------------
   // 5. Pullback detection — direction-specific and symmetric
   //
   //    BULLISH trend pullback:
   //      H1 closed candle low touches or crosses H1 EMA20 or EMA50
   //      (price retracing DOWN into the rising EMA stack)
   //
   //    BEARISH trend pullback:
   //      H1 closed candle high touches or crosses H1 EMA20 or EMA50
   //      (price retracing UP into the falling EMA stack)
   //------------------------------------------------------------
   bool pullback = false;
   if(trend == 1)
     {
      if(h1_low[0] <= h1_ema20[0] || h1_low[0] <= h1_ema50[0])
         pullback = true;
     }
   else if(trend == -1)
     {
      if(h1_high[0] >= h1_ema20[0] || h1_high[0] >= h1_ema50[0])
         pullback = true;
     }

   if(sofEvalOpen)
     {
      if(pullback)
         g_sof.Gates.RecordGate("PullbackActive", SOF_DIR_BUY, SOF_RESULT_PASS, 0, 0, "");
      else
        {
         g_sof.Gates.RecordGate("PullbackActive", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, 0, "no pullback detected");
         SOF_SkipRemainingGatesFrom(2);
         g_sof.Gates.EndEvaluation();
         sofEvalOpen = false;
        }
     }

   //------------------------------------------------------------
   // 6. Pullback edge detection — reset state on each new pullback
   //------------------------------------------------------------
   if(pullback && !g_last_pullback)
     {
      //--- New pullback started — fresh slate
      g_ema20_accepted_this_pb  = false;
      g_setup_triggered         = false;
      g_last_signal             = "NONE";
      g_locked_engulfing        = 0;
      g_signal_high             = 0.0;
      g_signal_low              = 0.0;
      g_signal_time             = 0;
      g_stop_loss               = 0.0;
      g_risk_points             = 0;
      g_calc_lot                = 0.0;
      g_risk_money              = 0.0;
      g_take_profit             = 0.0;
      g_depth_logged_this_pb    = false;
      g_pullback_bar_count      = 0;
      g_last_pb_h1_bar_time     = 0;
      g_duration_gate_reached   = false;
      g_cnt_pullbacks_found++;
      if(InpShowLog) Print("Pullback started — setup lock reset");
     }
   else if(!pullback && g_last_pullback)
     {
      //--- Pullback just ended — tally gate result and cancel pending
      if(g_duration_gate_reached)
         g_cnt_duration_gate_pass++;
      else
         g_cnt_duration_gate_rej++;
      g_pullback_bar_count    = 0;
      g_last_pb_h1_bar_time   = 0;
      g_duration_gate_reached = false;
      if(InpShowLog) Print("Pullback ended — legacy pending cancellation check");
      if(InpV10EnableLegacyEntries) CancelPending();
      g_setup_triggered  = false;
      g_last_signal      = "NONE";
      g_locked_engulfing = 0;
      g_signal_high      = 0.0;
      g_signal_low       = 0.0;
      g_signal_time      = 0;
      g_stop_loss        = 0.0;
      g_risk_points      = 0;
      g_calc_lot         = 0.0;
      g_risk_money       = 0.0;
      g_take_profit      = 0.0;
     }

   //------------------------------------------------------------
   // 7. Pullback depth ATR filter
   //
   //    Measures pullback depth relative to H1 ATR(14).
   //    BULLISH: depth = |H1 EMA20 - H1 Low|  (how far low penetrates EMA)
   //    BEARISH: depth = |H1 High - H1 EMA20| (how far high penetrates EMA)
   //    Pass: depth >= ATR(14) * InpMinPullbackDepthATR
   //    InpMinPullbackDepthATR = 0.0 → disabled (always passes)
   //------------------------------------------------------------
   bool depth_ok = true;
   if(pullback && InpMinPullbackDepthATR > 0.0)
     {
      double h1_atr[1];
      if(CopyBuffer(g_h1_atr_handle, 0, 1, 1, h1_atr) > 0 && h1_atr[0] > 0.0)
        {
         //--- Depth is direction-specific: BUY uses low penetration, SELL uses high penetration
         double depth = (trend == 1)
                        ? MathAbs(h1_ema20[0] - h1_low[0])    // BUY: how deep low is below EMA20
                        : MathAbs(h1_high[0]  - h1_ema20[0]); // SELL: how high high is above EMA20
         double threshold = h1_atr[0] * InpMinPullbackDepthATR;
         depth_ok = (depth >= threshold);

         if(!depth_ok && !g_depth_logged_this_pb)
           {
            g_depth_logged_this_pb = true;
            g_depth_rejected++;
            if(InpShowLog)
               PrintFormat("Pullback depth rejected | Depth: %s | ATR: %s | Required: %s (%.2fx ATR) | Dir: %s",
                           DoubleToString(depth,     _Digits),
                           DoubleToString(h1_atr[0], _Digits),
                           DoubleToString(threshold, _Digits),
                           InpMinPullbackDepthATR,
                           (trend == 1) ? "BUY" : "SELL");
           }
         else if(depth_ok && g_depth_logged_this_pb)
            g_depth_logged_this_pb = false;  // depth recovered mid-pullback
        }
     }

   //------------------------------------------------------------
   // 8. Pullback maturity counter
   //
   //    Increments once per distinct closed H1 bar while pullback
   //    is active. Gate blocks M5 engulf detection until:
   //      g_pullback_bar_count >= InpMinPullbackBars
   //------------------------------------------------------------
   if(pullback)
     {
      datetime h1_bar_now[1];
      if(CopyTime(_Symbol, PERIOD_H1, 1, 1, h1_bar_now) > 0 &&
         h1_bar_now[0] != g_last_pb_h1_bar_time)
        {
         g_last_pb_h1_bar_time = h1_bar_now[0];
         g_pullback_bar_count++;
         if(InpShowLog && g_pullback_bar_count <= InpMinPullbackBars)
            PrintFormat("Pullback bar %d / %d | Trend: %s | EMA20: %s | H1 High: %s | H1 Low: %s",
                        g_pullback_bar_count, InpMinPullbackBars,
                        (trend == 1) ? "BULL" : "BEAR",
                        DoubleToString(h1_ema20[0], _Digits),
                        DoubleToString(h1_high[0],  _Digits),
                        DoubleToString(h1_low[0],   _Digits));
        }
      if(!g_duration_gate_reached && g_pullback_bar_count >= InpMinPullbackBars)
        {
         g_duration_gate_reached = true;
         if(InpShowLog)
            PrintFormat("Pullback maturity gate OPEN | Bars: %d >= %d | Trend: %s | M5 engulf now eligible",
                        g_pullback_bar_count, InpMinPullbackBars,
                        (trend == 1) ? "BULLISH" : "BEARISH");
        }
     }

   //------------------------------------------------------------
   // 9. H1 EMA20 touch filter (optional)
   //
   //    When InpRequireEMA20Touch = true, at least one closed H1
   //    candle must have touched the EMA20 line during this pullback
   //    before any M5 engulf is considered:
   //    BULLISH: H1 low <= H1 EMA20
   //    BEARISH: H1 high >= H1 EMA20
   //------------------------------------------------------------
   bool ema20_touch = false;
   if(pullback)
     {
      if(trend ==  1 && h1_low[0]  <= h1_ema20[0]) ema20_touch = true;
      if(trend == -1 && h1_high[0] >= h1_ema20[0]) ema20_touch = true;
     }

   if(ema20_touch && !g_ema20_accepted_this_pb)
      g_ema20_accepted_this_pb = true;

   if(InpRequireEMA20Touch && pullback && !ema20_touch && !g_ema20_reject_logged)
     {
      if(InpShowLog)
         PrintFormat("EMA20 touch filter: no touch yet | Trend: %s | H1 Low: %s | H1 High: %s | EMA20: %s",
                     (trend == 1) ? "BULL" : "BEAR",
                     DoubleToString(h1_low[0],   _Digits),
                     DoubleToString(h1_high[0],  _Digits),
                     DoubleToString(h1_ema20[0], _Digits));
      g_ema20_reject_logged = true;
     }
   if(!pullback || ema20_touch)
      g_ema20_reject_logged = false;

   //------------------------------------------------------------
   // 10. Gate booleans
   //------------------------------------------------------------
   bool ema20_ok    = !InpRequireEMA20Touch || g_ema20_accepted_this_pb;
   bool duration_ok = (g_pullback_bar_count >= InpMinPullbackBars);

   int    engulfing = 0;
   string signal    = g_last_signal;

   //------------------------------------------------------------
   // 11. M5 engulfing detection — runs only when all gates open
   //
   //    Gate conditions (all must be true):
   //      pullback == true
   //      !g_setup_triggered  (one signal per pullback)
   //      depth_ok            (ATR depth filter)
   //      duration_ok         (pullback maturity filter)
   //      ema20_ok            (EMA20 touch filter, if enabled)
   //
   //    CopyRates with ArraySetAsSeries(true):
   //      rates[0] = forming bar  (ignored)
   //      rates[1] = last CLOSED  = engulfing candle candidate
   //      rates[2] = prior CLOSED = engulfed candle
   //
   //    BUY engulf  : cur_bull, prv_bear, cur_open < prv_close, cur_close > prv_open
   //    SELL engulf : cur_bear, prv_bull, cur_open > prv_close, cur_close < prv_open
   //
   //    Trend-direction gate:
   //      raw_engulf==1  valid only when trend==1 (BULLISH) AND direction != SELL ONLY
   //      raw_engulf==-1 valid only when trend==-1 (BEARISH) AND direction != BUY ONLY
   //------------------------------------------------------------
   //------------------------------------------------------------
   // SOF: decomposition of the compound gate condition immediately below
   // into gates 2-5, per approved Phase 0 Finding 3. Evaluates the same
   // already-computed booleans (!g_setup_triggered, depth_ok, duration_ok,
   // ema20_ok) in the same short-circuit order the && chain uses, purely
   // as observation -- the compound `if` on the next line is never
   // modified and is the sole authority for what the strategy actually
   // does next.
   //------------------------------------------------------------
   if(sofEvalOpen)
     {
      if(!pullback)
        {
         // Already recorded as PullbackActive FAIL above and the
         // evaluation closed there -- sofEvalOpen would be false in that
         // case, so this branch is unreachable in practice. Defensive only.
        }
      else if(g_setup_triggered)
        {
         g_sof.Gates.RecordGate("OneSignalPerPullback", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, 0, "signal already fired this pullback");
         SOF_SkipRemainingGatesFrom(3);
         g_sof.Gates.EndEvaluation();
         sofEvalOpen = false;
        }
      else
        {
         g_sof.Gates.RecordGate("OneSignalPerPullback", SOF_DIR_BUY, SOF_RESULT_PASS, 0, 0, "");

         if(!depth_ok)
           {
            g_sof.Gates.RecordGate("PullbackDepth", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, InpMinPullbackDepthATR, "");
            SOF_SkipRemainingGatesFrom(4);
            g_sof.Gates.EndEvaluation();
            sofEvalOpen = false;
           }
         else
           {
            g_sof.Gates.RecordGate("PullbackDepth", SOF_DIR_BUY, SOF_RESULT_PASS, 0, InpMinPullbackDepthATR, "");

            if(!duration_ok)
              {
               g_sof.Gates.RecordGate("PullbackMaturity", SOF_DIR_BUY, SOF_RESULT_FAIL, g_pullback_bar_count, InpMinPullbackBars, "");
               SOF_SkipRemainingGatesFrom(5);
               g_sof.Gates.EndEvaluation();
               sofEvalOpen = false;
              }
            else
              {
               g_sof.Gates.RecordGate("PullbackMaturity", SOF_DIR_BUY, SOF_RESULT_PASS, g_pullback_bar_count, InpMinPullbackBars, "");

               if(!ema20_ok)
                 {
                  g_sof.Gates.RecordGate("EMA20Touch", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, 0, "");
                  SOF_SkipRemainingGatesFrom(6);
                  g_sof.Gates.EndEvaluation();
                  sofEvalOpen = false;
                 }
               else
                  g_sof.Gates.RecordGate("EMA20Touch", SOF_DIR_BUY, SOF_RESULT_PASS, 0, 0, "");
              }
           }
        }
     }

   if(pullback && !g_setup_triggered && depth_ok && duration_ok && ema20_ok)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, PERIOD_M5, 0, 3, rates) < 3)
        {
         if(sofEvalOpen) { SOF_SkipRemainingGatesFrom(6); g_sof.Gates.EndEvaluation(); sofEvalOpen = false; }
         return;
        }

      double cur_open  = rates[1].open;
      double cur_close = rates[1].close;
      double prv_open  = rates[2].open;
      double prv_close = rates[2].close;

      bool cur_bull = (cur_close > cur_open);
      bool cur_bear = (cur_close < cur_open);
      bool prv_bull = (prv_close > prv_open);
      bool prv_bear = (prv_close < prv_open);

      //--- Raw engulf detection (body-only, no wicks)
      int raw_engulfing = 0;
      if(cur_bull && prv_bear)
        {
         if(cur_open < prv_close && cur_close > prv_open)
            raw_engulfing = 1;    // bullish engulf candidate
        }
      else if(cur_bear && prv_bull)
        {
         if(cur_open > prv_close && cur_close < prv_open)
            raw_engulfing = -1;   // bearish engulf candidate
        }

      //--- Count raw bearish engulf (pre-ratio, pre-trend)
      if(raw_engulfing == -1) g_raw_bear_engulf++;

      // SOF-only snapshot: state of raw_engulfing right after raw detection,
      // before any filter has touched it. Read-only, does not affect
      // raw_engulfing itself.
      bool sofBullishEngulfRaw = (raw_engulfing == 1);

      //--- Minimum body ratio filter
      //    cur_body >= prv_body * InpMinEngulfRatio
      //    1.0 = body must be at least equal (no penalty for equal sizes)
      if(raw_engulfing != 0 && InpMinEngulfRatio > 0.0)
        {
         double cur_body = MathAbs(cur_close - cur_open);
         double prv_body = MathAbs(prv_close - prv_open);
         if(prv_body > 0.0 && cur_body < prv_body * InpMinEngulfRatio)
            raw_engulfing = 0;   // failed ratio — discard
         //--- doji previous (prv_body == 0): ratio check skipped, counts as passed
        }

      // SOF-only snapshot: survived the ratio filter (or ratio filter n/a).
      bool sofAfterRatio = (raw_engulfing == 1);

      //--- [M5X] Exhaustion cap filter (BUY-side bullish engulf only).
      //    Mirror image of the minimum-ratio filter above: rejects the candidate
      //    when the engulf body is TOO large relative to the previous body.
      //    Runs BEFORE the trend gate and any order creation.
      //    Candle scope (validated v3.0 Variant A): only the exhaustion candle is
      //    rejected; the setup is NOT locked, so later candidates in the same
      //    pullback remain eligible.
      if(raw_engulfing == 1)
        {
         double m5x_cur_body = MathAbs(cur_close - cur_open);
         double m5x_prv_body = MathAbs(prv_close - prv_open);
         if(IsM5Exhaustion(m5x_cur_body, m5x_prv_body))
           {
            g_m5x_rejects++;
            PrintFormat("[M5X] REJECT | EngulfRatio=%.3f > Cap=%.2f | reason=M5_EXHAUSTION",
                        m5x_prv_body > 0.0 ? m5x_cur_body / m5x_prv_body : 0.0,
                        InpM5ExhaustionCap);
            raw_engulfing = 0;   // reject candidate before trend gate / order creation
           }
         else if(InpUseM5ExhaustionFilter)
            PrintFormat("[M5X] PASS   | EngulfRatio=%.3f <= Cap=%.2f",
                        m5x_prv_body > 0.0 ? m5x_cur_body / m5x_prv_body : 0.0,
                        InpM5ExhaustionCap);
        }

      // SOF-only snapshot: survived the M5 exhaustion filter.
      bool sofAfterExhaustion = (raw_engulfing == 1);

      //--- Trend-direction gate
      //    BUY : bullish engulf + bullish trend + not Sell Only
      //    SELL: bearish engulf + bearish trend + not Buy Only
      if(raw_engulfing == 1 && trend == 1 && InpTradeDirection != 2)
         engulfing = 1;
      else if(raw_engulfing == -1 && trend == -1 && InpTradeDirection != 1)
         engulfing = -1;

      // SOF-only snapshot: direction gate result for the BUY side specifically.
      bool sofDirectionOk = (engulfing == 1);

      // SOF: gates 6-9, evaluated from the snapshots above, in the same
      // order the strategy's own filter chain runs them. Read-only --
      // none of raw_engulfing/engulfing/trend/InpTradeDirection are
      // touched by this block.
      if(sofEvalOpen)
        {
         if(!sofBullishEngulfRaw)
           {
            g_sof.Gates.RecordGate("BullishEngulf", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, 0, "no bullish engulf detected");
            SOF_SkipRemainingGatesFrom(7);
            g_sof.Gates.EndEvaluation();
            sofEvalOpen = false;
           }
         else
           {
            g_sof.Gates.RecordGate("BullishEngulf", SOF_DIR_BUY, SOF_RESULT_PASS, 0, 0, "");
            if(!sofAfterRatio)
              {
               g_sof.Gates.RecordGate("MinimumEngulfRatio", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, InpMinEngulfRatio, "");
               SOF_SkipRemainingGatesFrom(8);
               g_sof.Gates.EndEvaluation();
               sofEvalOpen = false;
              }
            else
              {
               g_sof.Gates.RecordGate("MinimumEngulfRatio", SOF_DIR_BUY, SOF_RESULT_PASS, 0, InpMinEngulfRatio, "");
               if(!sofAfterExhaustion)
                 {
                  g_sof.Gates.RecordGate("M5Exhaustion", SOF_DIR_BUY, SOF_RESULT_FAIL, 0, InpM5ExhaustionCap, "");
                  SOF_SkipRemainingGatesFrom(9);
                  g_sof.Gates.EndEvaluation();
                  sofEvalOpen = false;
                 }
               else
                 {
                  g_sof.Gates.RecordGate("M5Exhaustion", SOF_DIR_BUY, SOF_RESULT_PASS, 0, InpM5ExhaustionCap, "");
                  if(!sofDirectionOk)
                    {
                     g_sof.Gates.RecordGate("DirectionAllowed", SOF_DIR_BUY, SOF_RESULT_FAIL, trend, 0, "");
                     SOF_SkipRemainingGatesFrom(10);
                     g_sof.Gates.EndEvaluation();
                     sofEvalOpen = false;
                    }
                  else
                     g_sof.Gates.RecordGate("DirectionAllowed", SOF_DIR_BUY, SOF_RESULT_PASS, trend, 0, "");
                 }
              }
           }
        }

      //--- Count trend-aligned bearish engulf (post-ratio, post-trend gate, pre-direction-filter)
      //    Counts raw_engulfing==-1 AND trend==-1, regardless of InpTradeDirection.
      //    This shows how many bearish engulfings aligned with the bearish trend,
      //    before the direction filter (Buy Only) could block them.
      if(raw_engulfing == -1 && trend == -1) g_trend_aligned_bear++;

      //--- Signal fire — BUY
      if(engulfing == 1)
        {
         g_cnt_m5_after_duration++;
         g_buy_signals++;
         signal             = "BUY";
         g_last_signal      = "BUY";
         g_setup_triggered  = true;
         g_locked_engulfing = 1;
         g_signal_high      = rates[1].high;
         g_signal_low       = rates[1].low;
         g_signal_time      = rates[1].time;

         if(InpShowLog)
           {
            Print("M5 Bullish Engulfing → Signal: BUY | Setup locked");
            PrintFormat("  Current  candle → Open: %s | Close: %s",
                        DoubleToString(cur_open,  _Digits),
                        DoubleToString(cur_close, _Digits));
            PrintFormat("  Previous candle → Open: %s | Close: %s",
                        DoubleToString(prv_open,  _Digits),
                        DoubleToString(prv_close, _Digits));
            PrintFormat("  Signal candle   → High: %s | Low: %s | Time: %s",
                        DoubleToString(g_signal_high, _Digits),
                        DoubleToString(g_signal_low,  _Digits),
                        TimeToString(g_signal_time, TIME_DATE|TIME_MINUTES));
           }

         //--- BUY STOP above signal high, SL below signal low
         double entry = NormalizeDouble(
                           g_signal_high + InpEntryBufferPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                           _Digits);
         double sl    = NormalizeDouble(
                           g_signal_low  - InpEntryBufferPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                           _Digits);
         double tp_cand = NormalizeDouble(entry + MathAbs(entry - sl) * InpRiskReward, _Digits);
         {
          double cur_body = MathAbs(rates[1].close - rates[1].open);
          double prv_body = MathAbs(rates[2].close - rates[2].open);
          double eratio   = (prv_body > 0.0) ? cur_body / prv_body : 0.0;
          CSVWriteSignal("BUY", entry, sl, tp_cand,
                         g_pullback_bar_count, 0.0,
                         eratio, 0.0, false, false);
         }
         {
          double cur_body = MathAbs(rates[1].close - rates[1].open);
          double prv_body = MathAbs(rates[2].close - rates[2].open);
          H4H1Candidate candidate = CreateH4H1Candidate(1,g_signal_time,
                                                        entry,sl,tp_cand,
                                                        trend,g_pullback_bar_count,
                                                        g_signal_high,g_signal_low,
                                                        cur_body,prv_body);
          RouteH4H1Candidate(candidate);
         }
        }

      //--- Signal fire — SELL (with staged confirmation pipeline)
      //
      //    After the bearish engulf passes the trend-direction gate (engulfing==-1),
      //    three optional confirmation filters are applied in sequence.
      //    Each filter is independently toggled by its input. A disabled filter
      //    passes all candidates through so it does not affect trade count.
      //
      //    Diagnostic counters increment at each stage that a candidate reaches,
      //    regardless of which later stage it may fail. This gives a full waterfall:
      //      RawBearEngulf → BreakPrevLow → BreakSwingLow → EMA20SlopeBear → FinalSellSignal
      //
      //    IMPORTANT: rates[] already has 3 elements (shift 0,1,2). Filters 2 and 3
      //    need up to shift 5. We fetch extended_rates[] (6 bars) only when needed,
      //    guarded so CopyRates is not called on every tick unnecessarily.
      else if(engulfing == -1)
        {
         //--- PRME V3 already counted in g_raw_bear_engulf (above, pre-ratio)
         //    Here we are post-trend-gate, so all remaining stages are SELL-specific.

         bool sell_ok = true;   // accumulates: false at first failed enabled filter

         //--- Stage 2: BreakPrevLow
         //    Engulf candle close must be strictly below the previous candle low.
         //    Rationale: a close below the prior low shows the bear has enough momentum
         //    to break structure, not merely engulf the body.
         //    rates[1] = signal candle, rates[2] = previous candle.
         bool pass_break_prev_low = true;
         if(InpSellBreakPrevLow)
           {
            double prv_low = rates[2].low;
            pass_break_prev_low = (cur_close < prv_low);
            if(!pass_break_prev_low)
              {
               sell_ok = false;
               if(InpShowLog)
                  PrintFormat("SELL CONF | BreakPrevLow FAILED | Close: %s >= PrvLow: %s | Bar: %s",
                              DoubleToString(cur_close,  _Digits),
                              DoubleToString(prv_low,    _Digits),
                              TimeToString(rates[1].time, TIME_DATE|TIME_MINUTES));
              }
           }
         if(pass_break_prev_low) g_diag_break_prev_low++;

         //--- Stage 3: BreakSwingLow
         //    Signal candle low must be strictly below the lowest low of the 3 bars
         //    immediately preceding it (rates[2], rates[3], rates[4]).
         //    Rationale: price is breaking a local swing low, confirming directional momentum.
         //    Requires fetching 5 closed bars (shifts 0–4, plus forming bar = 5 total).
         bool pass_break_swing_low = true;
         if(InpSellBreakSwingLow && sell_ok)
           {
            MqlRates ext_rates[];
            ArraySetAsSeries(ext_rates, true);
            if(CopyRates(_Symbol, PERIOD_M5, 0, 5, ext_rates) >= 5)
              {
               double cur_low    = rates[1].low;
               //--- Lowest low of the 3 bars before the signal candle (shifts 2, 3, 4)
               double swing_low  = MathMin(ext_rates[2].low,
                                   MathMin(ext_rates[3].low, ext_rates[4].low));
               pass_break_swing_low = (cur_low < swing_low);
               if(!pass_break_swing_low)
                 {
                  sell_ok = false;
                  if(InpShowLog)
                     PrintFormat("SELL CONF | BreakSwingLow FAILED | CurLow: %s >= SwingLow: %s | Bar: %s",
                                 DoubleToString(cur_low,   _Digits),
                                 DoubleToString(swing_low, _Digits),
                                 TimeToString(rates[1].time, TIME_DATE|TIME_MINUTES));
                 }
              }
            else
              {
               //--- Not enough bars (startup) — treat as not passed, do not count
               pass_break_swing_low = false;
               sell_ok = false;
              }
           }
         if(pass_break_swing_low) g_diag_break_swing_low++;

         //--- Stage 4: EMA20SlopeBear
         //    M5 EMA20 at the signal candle (shift=1) must be below M5 EMA20 at the
         //    prior candle (shift=2): EMA20[1] < EMA20[2] → slope is negative.
         //    Rationale: confirms the short-term M5 trend is already pointing down
         //    before the entry is taken.
         bool pass_ema20_slope = true;
         if(InpSellEMA20Slope && sell_ok)
           {
            double m5_ema20_cur[1], m5_ema20_prv[1];
            bool slope_ok = false;
            if(CopyBuffer(g_m5_ema20_handle, 0, 1, 1, m5_ema20_cur) > 0 &&
               CopyBuffer(g_m5_ema20_handle, 0, 2, 1, m5_ema20_prv) > 0)
              {
               slope_ok = (m5_ema20_cur[0] < m5_ema20_prv[0]);
              }
            pass_ema20_slope = slope_ok;
            if(!pass_ema20_slope)
              {
               sell_ok = false;
               if(InpShowLog)
                  PrintFormat("SELL CONF | EMA20Slope FAILED | EMA20[1]: %s >= EMA20[2]: %s | Bar: %s",
                              DoubleToString(m5_ema20_cur[0], _Digits),
                              DoubleToString(m5_ema20_prv[0], _Digits),
                              TimeToString(rates[1].time, TIME_DATE|TIME_MINUTES));
              }
           }
         if(pass_ema20_slope) g_diag_ema20_slope_bear++;

         //--- Stage 5: FinalSellSignal — all enabled filters passed
         if(sell_ok)
           {
            g_diag_final_sell++;
            g_cnt_m5_after_duration++;
            g_sell_signals++;
            signal             = "SELL";
            g_last_signal      = "SELL";
            g_setup_triggered  = true;
            g_locked_engulfing = -1;
            g_signal_high      = rates[1].high;
            g_signal_low       = rates[1].low;
            g_signal_time      = rates[1].time;

            if(InpShowLog)
              {
               Print("M5 Bearish Engulfing → Signal: SELL | Setup locked");
               PrintFormat("  Current  candle → Open: %s | Close: %s",
                           DoubleToString(cur_open,  _Digits),
                           DoubleToString(cur_close, _Digits));
               PrintFormat("  Previous candle → Open: %s | Close: %s",
                           DoubleToString(prv_open,  _Digits),
                           DoubleToString(prv_close, _Digits));
               PrintFormat("  Signal candle   → High: %s | Low: %s | Time: %s",
                           DoubleToString(g_signal_high, _Digits),
                           DoubleToString(g_signal_low,  _Digits),
                           TimeToString(g_signal_time, TIME_DATE|TIME_MINUTES));
              }

            //--- SELL STOP below signal low, SL above signal high
            double entry = NormalizeDouble(
                              g_signal_low  - InpEntryBufferPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                              _Digits);
            double sl    = NormalizeDouble(
                              g_signal_high + InpEntryBufferPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                              _Digits);
            double tp_cand = NormalizeDouble(entry - MathAbs(sl - entry) * InpRiskReward, _Digits);
            {
             double cur_body = MathAbs(rates[1].close - rates[1].open);
             double prv_body = MathAbs(rates[2].close - rates[2].open);
             double eratio   = (prv_body > 0.0) ? cur_body / prv_body : 0.0;
             CSVWriteSignal("SELL", entry, sl, tp_cand,
                            g_pullback_bar_count, 0.0,
                            eratio, 0.0, false, false);
            }
            if(InpV10EnableLegacyEntries) PlacePending(-1, entry, sl);
           }
        }
     }

   //------------------------------------------------------------
   // 12. Log H4 trend changes
   //------------------------------------------------------------
   if(InpShowLog && trend != g_last_trend && g_last_trend != 99)
     {
      string lbl = (trend == 1) ? "BULLISH" : (trend == -1) ? "BEARISH" : "NEUTRAL";
      PrintFormat("H4 Trend changed → %s | EMA50: %s | EMA200: %s | Gap: %.2f",
                  lbl,
                  DoubleToString(h4_ema50[0],  _Digits),
                  DoubleToString(h4_ema200[0], _Digits),
                  MathAbs(h4_ema50[0] - h4_ema200[0]));
     }

   //--- Update state
   g_last_trend     = trend;
   g_last_pullback  = pullback;
   g_last_engulfing = engulfing;

   //--- Refresh Comment display
   UpdateComment(trend, pullback, g_setup_triggered, engulfing, signal);
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction — track closed trades for stats               |
//|                                                                  |
//| Fires on DEAL_ENTRY_OUT (position close).                        |
//| DEAL_TYPE on a closing deal reflects the closing side:           |
//|   DEAL_TYPE_SELL = closed a BUY  position (sell to close)        |
//|   DEAL_TYPE_BUY  = closed a SELL position (buy to close)         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;

   V10ProcessTradeDeal(trans.deal);

   ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(deal_entry != DEAL_ENTRY_OUT) return;

   // SOF-only close observation. This EA has no partial-close mechanism
   // (fixed SL/TP, no PRME), so DEAL_ENTRY_OUT alone -- matching the
   // existing check immediately above -- is the correct, complete net;
   // no need to widen to DEAL_ENTRY_OUT_BY as in strategies with partials.
   if(g_sofStarted)
     {
      long sofPosId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      int  sofSlot  = SOF_MapFindSlot(sofPosId);
      if(sofSlot < 0)
        {
         g_sof.Session.GetErrorChannel().Report(SOF_ERR_REGISTRY_MISMATCH,
                     "OnTradeTransaction - SOF correlation",
                     StringFormat("No map entry for closing deal, positionId=%d dealTicket=%d",
                                   (int)sofPosId, (int)trans.deal));
        }
      else if(!g_sofPosMap[sofSlot].active)
        {
         // CLOSED already emitted for this position — no-op by design.
        }
      else
        {
         bool fullyClosed = !SOF_SelectPositionByIdentifier(sofPosId);
         if(fullyClosed)
           {
            double sofTotalPnL = SOF_AggregatePositionPnL(sofPosId);
            double sofExitPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            ENUM_SOF_DIRECTION ld1CloseDir=LD1_SOFDirectionFromPositionId(sofPosId);
            g_sof.Trades.RecordTrade(g_sofPosMap[sofSlot].tradeObservationId,
                                      0, sofPosId, ld1CloseDir, SOF_STAGE_CLOSED,
                                      sofExitPrice, 0, 0, 0,
                                      0, sofTotalPnL, 0, 0,
                                      "Closed via OnTradeTransaction");
            SOF_MapMarkInactive(sofPosId);
           }
        }
     }

   double profit    = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   //--- Closing a BUY position uses DEAL_TYPE_SELL; closing a SELL position uses DEAL_TYPE_BUY
   bool was_buy = (deal_type == DEAL_TYPE_SELL);

   g_stat_trades++;
   if(profit > 0.0)
     {
      g_stat_wins++;
      if(was_buy) g_buy_wins++;
      else        g_sell_wins++;
     }
   else
     {
      g_stat_losses++;
      if(was_buy) g_buy_losses++;
      else        g_sell_losses++;
     }

   //--- Determine ExitReason from deal comment
   string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   string exit_reason;
   if(StringFind(deal_comment, "tp") >= 0 || StringFind(deal_comment, "TP") >= 0)
      exit_reason = "TP";
   else if(StringFind(deal_comment, "sl") >= 0 || StringFind(deal_comment, "SL") >= 0)
      exit_reason = "SL";
   else if(StringFind(deal_comment, "so") >= 0)
      exit_reason = "SL";
   else if(deal_comment == "" || deal_comment == "close")
      exit_reason = "MANUAL";
   else
      exit_reason = "UNKNOWN";

   //--- Entry price from position history
   double entry_price = 0.0;
   if(HistorySelectByPosition(HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID)))
     {
      int deals_total = HistoryDealsTotal();
      for(int d = 0; d < deals_total; d++)
        {
         ulong dticket = HistoryDealGetTicket(d);
         if(HistoryDealGetInteger(dticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            entry_price = HistoryDealGetDouble(dticket, DEAL_PRICE);
            break;
           }
        }
     }

   double close_price2 = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double close_vol    = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   CSVWriteClose(was_buy ? "BUY" : "SELL",
                 trans.deal,
                 entry_price, close_price2,
                 close_vol, profit, exit_reason);

   double win_rate = (g_stat_trades > 0)
                     ? (double)g_stat_wins / g_stat_trades * 100.0 : 0.0;
   if(InpShowLog)
      PrintFormat("Trade closed | %s | Profit: %.2f | Total: %d | Wins: %d | Losses: %d | WinRate: %.2f%%",
                  was_buy ? "BUY" : "SELL",
                  profit, g_stat_trades, g_stat_wins, g_stat_losses, win_rate);
  }
//+------------------------------------------------------------------+
