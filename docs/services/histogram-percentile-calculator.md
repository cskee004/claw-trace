# HistogramPercentileCalculator

`app/lib/histogram_percentile_calculator.rb`

Estimates P50, P95, and P99 percentiles from OTLP explicit-boundary histogram bucket data using linear interpolation within buckets.

---

## Interface

```ruby
result = HistogramPercentileCalculator.call(
  bucket_counts:   [10, 40, 60, 30, 10],
  explicit_bounds: [100.0, 300.0, 500.0, 700.0]
)
# => { p50: 383.3, p95: 875.0, p99: 1295.0 }

# Returns nil when there is no data
HistogramPercentileCalculator.call(bucket_counts: [], explicit_bounds: [])
# => nil

HistogramPercentileCalculator.call(bucket_counts: [0, 0], explicit_bounds: [10.0])
# => nil
```

**Input:**
- `bucket_counts:` — Array of integers, one per bucket (N+1 values for N bounds)
- `explicit_bounds:` — Array of floats defining the N bucket boundaries

**Output:** `{ p50: Float, p95: Float, p99: Float }` or `nil` if all counts are zero or the input is empty.

---

## How It Works

OTLP histograms use explicit boundaries to define buckets:

```
explicit_bounds: [100, 300, 500, 700]   → 4 boundaries → 5 buckets
bucket_counts:   [10,  40,  60,  30,  10]
                  ↑    ↑    ↑    ↑    ↑
               (-∞,100] (100,300] (300,500] (500,700] (700,+∞)
```

For each target percentile rank, the calculator finds the bucket containing that rank and linearly interpolates within it:

```
percentile = lower + (upper - lower) × (target - cumulative_before) / bucket_count
```

For the last bucket (no upper bound), `upper` is estimated as `last_bound × 2.0`.

---

## Usage in MetricsController

```ruby
dp   = metric_record.data_points
pcts = HistogramPercentileCalculator.call(
  bucket_counts:   dp["bucket_counts"]   || [],
  explicit_bounds: dp["explicit_bounds"] || []
)

pcts&.dig(:p50)  # => 383.3
pcts&.dig(:p95)  # => 875.0
pcts&.dig(:p99)  # => 1295.0
```

The `MetricsController#show` action calls this for each histogram record to build the P50/P95/P99 time-series chart data passed to ApexCharts.
