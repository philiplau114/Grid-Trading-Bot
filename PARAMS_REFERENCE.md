# Parameter Reference (Step 1 focus)

## Regime and Coherence
- RegimeMode: Auto (read-only in Step 1; no order placement)
- CoherenceMode: Strict | Score
- SignalWindowBars: e.g., 5
- SignalScoreThreshold: e.g., 60

## VWAP
- VwapMode: Rolling | Daily | Session
- RollingVwapBars: e.g., 96 (M30 ~ 2 days) or 48 (H1 ~ 2 days)
- VwapSlopePeriod: e.g., 14
- VwapSlopeThreshold: e.g., 0.0

## ZigZag
- ZZ_Depth: 12
- ZZ_Deviation: 5
- ZZ_Backstep: 3

## Squeeze (BB vs KC)
- BB_Period: 20
- BB_Dev: 2.0
- KC_Period: 20
- KC_MultATR: 1.5
- UseTTMSqueeze: false
- TTM_IndicatorName: "TTM_Squeeze"
- TTM_Buffers: { squeeze, momentum, etc. } (mapping when enabled)

## Trend Indicators
- UseEMAStack: false
- EMAFast: 20, EMAMid: 50, EMASlow: 100
- EMASlopeMin: 0.0
- UseADX: false
- ADXPeriod: 14
- ADXThreshold: 20
- UseSupertrend: false (custom inputs…)
- UseDonchianTrend: false
- DonchPeriod: 20
- UseRSITrend: false
- RSIPeriod: 14, RSIUpperTrend: 55, RSILowerTrend: 45
- UseIchimoku: false (custom inputs…)

## Range Indicators
- UseBBBandwidth: true
- BBWThreshold: 0.015 (1.5% of price; tune per symbol)
- UseDonchWidth: false
- DonchWidthMin: 0.001, DonchWidthMax: 0.01
- UseATRBandwidth: false
- ATRPeriod: 14
- ATRBandwidthMax: 0.005

## UI & Logging
- ShowPanel: true
- ShowVWAP: true
- ShowZigZag: true
- ShowSignals: true
- WriteCSV: true
- CSVPath: "MQL4/Files/logs"
- LogLevel: INFO | DECISION | ERROR

## Step 2 (Preview-Only)
- LotMode: VolatilityScaled (default)
- GridCenterMode: VWAP | ZigZagMid | Blend
- LevelsPerSide, EntryMode, StepMode, etc.
- Same-direction BE+profit: BasketBreakevenMinProfitLong/Short
- Opposite-direction BE+profit: NetCloseMinProfitMoney
- PriorityBreakevenFirst: true