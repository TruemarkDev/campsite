# YJIT benchmark

The API includes `script/benchmark-yjit`, a repeatable process-level benchmark
for JSON, Markdown, and Active Support transformations used in API request
paths. It alternates interpreter and YJIT child processes, verifies identical
checksums, and reports raw timings alongside median throughput.

Run it inside the same image and host class as the API:

```bash
bundle exec script/benchmark-yjit
```

Environment variables tune the sample without changing the workload:

- `CAMPSITE_YJIT_BENCHMARK_RUNS` controls runs per mode (default: 5).
- `CAMPSITE_YJIT_BENCHMARK_ITERATIONS` controls iterations per run (default: 2000).

## Homelab staging result

On 2026-08-26, revision `65aa744c68ddaf8209b410af0cb22c55b1dba0fd`
was sampled in the running `campsite-api-staging` container on Odin. Ruby
4.0.6 reported YJIT support on x86_64 Linux. Two sequential 1,000-iteration
runs per mode produced:

| Mode        | Throughput samples (iterations/second) | Mean |
| ----------- | -------------------------------------- | ---- |
| Interpreter | 254.85, 257.62                         | 256.24 |
| YJIT        | 262.88, 263.48                         | 263.18 |

YJIT improved mean throughput by 2.71% for this narrow workload. No service
was restarted and no deployment setting was changed.

🟡 This microbenchmark does not measure endpoint latency, memory growth, or
production traffic. YJIT remains disabled by default until a staging release
can compare representative HTTP load and resident memory over a sustained
window.
