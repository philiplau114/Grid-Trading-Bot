# MT4 Grid EA — Stepwise Design

## Goals
- Adaptive grid strategy capable of handling ranging and trending regimes.
- Fully configurable parameters (inputs) for indicators, grid, risk, and closures.
- Strong observability: on-chart visuals and structured logs for Strategy Tester and live.
- Stepwise delivery to simplify validation:
  - Step 1: Regime detector (no trading), visualization + logs.
  - Step 2: Trading/grid engine and basket management.
  - Step 3+: Extras (ATR grid sizing, news filters, advanced risk, extended indicators).

## Architecture

### Modules
1) Indicator Engine
   - Provides normalized signals from pluggable indicators.
   - Each indicator has:
     - enabled (bool)
     - role: Trend or Range
     - parameters
     - outputs: raw value(s) and boolean signal(s)

2) Signal Aggregator
   - Combines indicator signals into:
     - Directional bias: +1 up, -1 down, 0 neutral
     - Regime: Trend, Range
   - Two modes:
     - Strict Coherence: All required conditions must be true within `SignalWindowBars`.
     - Weighted Score: Each signal contributes to score; act if score ≥ `SignalScoreThreshold`.

3) Grid Engine (Step 2)
   - Grid center: VWAP, ZigZag mid, or Blend.
   - Step size: Fixed or ATR-based with min/max bounds.
   - Placement: LimitsOnly (range), StopsTrend (breakout), BothEntries.
   - Lot sizing: Fixed, Multiplier, Volatility-scaled (default).
   - Auto re-center triggers: drift threshold, flat, periodic, squeeze release.

4) Basket Manager (Step 2)
   - Same-direction basket TP and breakeven+profit (per side).
   - Opposite-direction net breakeven+profit.
   - Priority policy: breakeven-first (global + regime overrides).

5) Risk Manager (Step 2+)
   - Equity DD stop, margin safety, spread/volatility halts, max orders/lots.
   - News blackout windows (manual first; optional integration later).

6) UI & Logging
   - On-chart panel, labels, lines, arrows.
   - CSV logs (and journal) with consistent schema and log levels.

## Indicators (Plug-and-Play)

### Core (initial)
- ZigZag (Range): last confirmed swing high/low; derived range width and midpoint.
- VWAP:
  - Modes: Rolling, Daily (midnight), Session (user-defined).
  - Outputs: value, slope over N bars, price-vs-VWAP distance.
- Squeeze (Compression/Expansion):
  - Default: Bollinger Bands vs. Keltner Channels.
  - Option: TTM Squeeze via iCustom buffer mapping.

### Additional Trend Indicators (all toggleable)
- EMA stack (Fast > Mid > Slow) and slope checks.
- ADX (trend strength), DI+/DI- for direction.
- Supertrend direction.
- Donchian bias (price vs mid/upper band).
- RSI trend bias (e.g., >55 up; <45 down).
- Ichimoku (kijun/tenkan, cloud position).

### Additional Range Indicators (all toggleable)
- Bollinger bandwidth threshold.
- Donchian channel width threshold.
- ATR bandwidth (ATR relative to price or recent ATR average).
- ZigZag range width constraints.

## Regime Detection (Step 1)

- TrendUp condition examples:
  - VWAP slope ≥ threshold AND price > VWAP
  - (Optional) EMA stack aligned AND ADX ≥ threshold
- TrendDown mirrors the above.
- Range condition examples:
  - Squeeze On OR (BB bandwidth < threshold) OR (Donchian width < threshold)
  - VWAP slope near zero within tolerance

Resolution strategies:
- Strict mode:
  - If TrendUp XOR TrendDown => Regime = Trend (direction = ±1)
  - Else => Regime = Range (direction = 0)
- Score mode:
  - Aggregate TrendUpScore and TrendDownScore; if both below thresholds => Range
  - If one dominates => Trend with direction

All checks apply within `SignalWindowBars` to ensure coherence.

## Visualization (Step 1)

- Lines:
  - VWAP (gold) with slope arrow and slope value.
  - ZigZag Mid (purple), optional last high/low markers.
- Badges / Panel (top-left by default):
  - Regime: Trend Up / Trend Down / Range
  - VWAP: value, slope
  - Squeeze: On / Released Up / Released Down
  - EMA, ADX, Donchian, RSI, Ichimoku: ON/OFF + brief status if enabled
  - Coherence mode: Strict or Score (with current score)
  - Timeframe and Symbol
- Colors and styles configurable; visibility toggles for each element.

## Logging (Step 1)

- CSV file per symbol+TF+magic:
  - Filename: `logs/{Symbol}_{Timeframe}_{Magic}_regime.csv`
- Columns:
  - timestamp, bar_time, bar_index, symbol, timeframe
  - price, vwap, vwap_slope, vwap_mode, vwap_window
  - zz_high, zz_low, zz_mid, zz_range_pips
  - squeeze_on, squeeze_rel_up, squeeze_rel_dn
  - ema_ok, adx_ok, supertrend_ok, donch_ok, rsi_ok, ichi_ok
  - trend_up, trend_dn, range_ok
  - coherence_mode, signal_window, score, regime, direction
- Log levels:
  - INFO (state), DECISION (regime switches), ERROR

## Parameters (Step 1 subset)

- Core:
  - MagicNumber, TradeComment, AllowedDirection (still present, but no trading in Step 1)
- Regime/Signals:
  - RegimeMode = Auto (in Step 1 we only detect; no order placement)
  - CoherenceMode: Strict | Score
  - SignalWindowBars
  - SignalScoreThreshold (Score mode)
- VWAP:
  - VwapMode: Rolling | Daily | Session
  - RollingVwapBars (N)
  - DailyAnchor: server midnight or user-specified (future)
  - SessionStartHour, SessionLengthHours (future)
  - VwapSlopePeriod, VwapSlopeThreshold
- ZigZag:
  - ZZ_Depth, ZZ_Deviation, ZZ_Backstep
- Squeeze:
  - BB_Period, BB_Dev, KC_Period, KC_MultATR
  - UseTTMSqueeze (iCustom), TTM_IndicatorName, Buffer mapping
- Trend indicators toggles:
  - UseEMAStack (EMAFast, EMAMid, EMASlow, SlopeMin)
  - UseADX (ADXPeriod, ADXThreshold)
  - UseSupertrend (inputs...)
  - UseDonchianTrend (DonchPeriod)
  - UseRSITrend (RSIPeriod, RSIUpperTrend, RSILowerTrend)
  - UseIchimoku (inputs...)
- Range indicators toggles:
  - UseBBBandwidth (BBWThreshold)
  - UseDonchWidth (DonchWidthMin/Max)
  - UseATRBandwidth (ATRPeriod, ATRBandwidthMax)
- UI & Logging:
  - ShowPanel, ShowVWAP, ShowZigZag, ShowSignals
  - WriteCSV, CSVPath, LogLevel

Defaults tuned for M30/H1 (no trading yet):
- VwapMode=Rolling, RollingVwapBars=96 (2 days of M30 data) or 48 for H1
- VwapSlopePeriod=14, VwapSlopeThreshold≈0
- Squeeze defaults: BB(20,2), KC(20,1.5)
- ZigZag default: Depth=12, Deviation=5, Backstep=3
- Coherence: Strict with SignalWindowBars=5

## Step 2 (Trading) — Preview

- Grid:
  - Center: VWAP / ZZMid / Blend (weight configurable)
  - Step: Fixed or ATR-based (ATRPeriod, ATRMult, StepMin/Max)
  - LevelsPerSide; EntryMode (LimitsOnly / StopsTrend / Both)
- Lots:
  - LotMode: Fixed | Multiplier | VolatilityScaled (default)
  - BaseLot, LotMultiplier, VolScaleATRRef, MaxLot
- Basket & Closures:
  - Same-direction:
    - BasketTPMoneyLong/Short
    - BasketBreakevenMinProfitLong/Short
  - Opposite-direction:
    - NetCloseMinProfitMoney
  - Priority:
    - PriorityBreakevenFirst (global)
    - RegimeOverrideBreakevenFirst: None | Enforce | Disable
- Risk:
  - MaxOrders/PerSide, MaxLots/PerSide
  - EquityStopPct, MarginSafetyPct
  - SpreadMax, VolatilityHaltATRMult
  - TradeHours, News windows

## Testing Plan

- Step 1:
  - Visual inspection: panel updates, VWAP line + slope arrow, ZZ mid line, squeeze status.
  - CSV verification across diverse days (range, trend, squeeze release).
- Step 2:
  - Strategy Tester with CSV logs for entries/exits.
  - Parameter sweeps: step size, levels, lot modes.
  - Stress: widening spreads, high ATR bursts, equity stops.

## Notes on Rolling VWAP

- Default: Rolling VWAP over `RollingVwapBars` using typical price * volume.
- User can later switch to Daily/Session anchors.
- If you have a TradingView script with specific behavior (reset rules, calculation nuances), please share; we can mirror it closely.