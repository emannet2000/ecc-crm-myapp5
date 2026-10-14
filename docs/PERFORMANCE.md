# Performance measurements and component ownership

Run `npm run test:performance` from the project root. The Go benchmark creates
and removes its own temporary SQLite databases. It adds 5,000 contacts, 5,000
applications and 5,000 required documents to the demo data; 20% of those records
belong to another workspace. Application actions have deadlines and outstanding
document requirements. Setup and authentication token creation are excluded from
timing. Each HTTP handler must return success or the benchmark fails.

These measurements cover backend request processing and allocations, including
permissions, SQL reads and validated writes. They exclude network latency,
browser rendering and external services. Use the actual deployment's record mix
and a browser trace before setting user-facing loading targets. Three iterations
provide a short local baseline, not percentiles or production capacity.

## Baseline — 2026-10-11

Linux/amd64, Intel Core 2 Quad Q9400 at 2.66 GHz, benchmark parallelism 4,
three measured iterations per operation. Results are means for this local run.
The different hardware makes direct comparison with older baselines unreliable.

| Operation | Mean request time | Allocated bytes per operation |
| --- | ---: | ---: |
| Contact list, 25 records after offset 500 | 22.5 ms | 366,989 |
| Global search, `client-123` | 1,504.4 ms | 327,090,832 |
| Application record detail | 1.10 ms | 57,869 |
| Application requirements | 17.9 ms | 92,101 |
| Dashboard report aggregates | 608.0 ms | 114,078,648 |
| Daily work totals and first page | 533.7 ms | 117,649,205 |
| Validated contact save | 1.37 ms | 90,493 |

Application detail, requirements and dashboard report requests are measured
separately; these numbers cannot be summed into complete page-load times because
requests may run concurrently and pages fetch additional tools. The search
query matches a subset of records; repeat with names, emails and reference
numbers, both common and rare, on deployment data before prioritizing changes.

Global search was the first candidate for profiling because its latency and
allocations are highest here. Dashboard and daily-work aggregation are the next
candidates. Inspect query plans and allocation profiles, then compare the same
workload before and after any proposed fix. Preserve workspace boundaries,
visibility, counts, ordering and revision checks. This cycle records the evidence;
it does not assume that a faster individual query improves the whole page.

## Search improvement — 2026-10-11

Global search now reads its results directly from SQL. Previously, request
middleware loaded and cloned the complete workspace, and the handler serialized
every entity again for each candidate result to check visibility. Search now
shares the record-list SQL visibility predicate, including document, payment and
activity parent checks. Those checks run before sorting and the 31-candidate
limit, so hidden parents cannot crowd accessible matches out of the 30 results.
Literal matching, searched fields and title/entity/ID ordering are preserved.

Fresh before/after runs used the same hardware and 5,000-record workload above,
with three measured iterations per run:

| Search, `client-123` | Before | After |
| --- | ---: | ---: |
| Mean request time | 2,754.7 ms | 134.6 ms |
| Allocated bytes per request | 327,090,848 | 123,898 |
| Allocations per request | 691,122 | 915 |

The local result is about 20 times faster with 99.96% fewer allocated bytes.
The fresh before measurement differs from the earlier baseline; these short
samples remain sensitive to machine load and do not establish production
percentiles or complete browser loading times. Dashboard and daily-work
aggregation remain the next profiling candidates.

Reproduce the isolated comparison with:

```sh
cd golang-backend
go test -run '^$' -bench '^BenchmarkRepositoryWorkload/search$' -benchtime=3x -benchmem
```

Verification: the full backend suite passes. Search regression tests cover all
13 searchable entities, committed SQL records absent from the legacy cache,
workspace/team/private visibility, hidden/foreign/missing parents, optional
activity parents, document case precedence, and exact 30/31-result boundaries.
Existing authentication and literal wildcard tests also pass.

## JavaScript ownership

`public/bootstrap.js` initializes Elm and bridges ports. Workspace keyboard
access, modal focus, read-only affordances and handoff deep links belong to
`public/workspace-interactions.js`. Its controller owns one observer, delegated
document listeners and explicit `start()` / `stop()` methods; repeated starts do
not duplicate listeners. Changes to these behaviors should stay in that module.
The PWA shell includes it so offline work has the same interactions.

Daily work and student journey rendering remain owned by their custom elements
in `public/components.js`. Application requirements belong to `public/progress.js`;
modal drafts belong to `public/draft-recovery.js`; staff observations and review
priorities belong to `public/usability.js`. Continue consolidating by behavior
when editing those screens. Keep lifecycle cleanup and meaningful interaction
checks with each move, and avoid changing backend permission enforcement during
frontend reorganization.

## Daily-work and dashboard measurement — 2026-10-12

Current implementation, Linux/amd64, Intel Core i5-2415M at 2.30 GHz,
parallelism 4, three measured iterations using the same 5,000-record fixture.

| Operation | Mean request time | Bytes per request | Allocations per request |
| --- | ---: | ---: | ---: |
| Dashboard report aggregates | 292.3 ms | 41,716,333 | 218,871 |
| Daily work totals and first page | 246.4 ms | 64,664,717 | 188,473 |

Daily work reads only the scoped entities needed for its list and totals.
Dashboard creation counts use decoded records without serializing the workspace
again. The first Home work list requests ten items; secondary summary loads wait
for the work list or a 1.5-second fallback. Record visibility regression tests
remain part of backend verification.

The earlier baseline used different hardware, so these results do not establish
a before/after speedup. Browser measurements are recorded separately by
`node --test tests/improvements.browser.cjs` in
`tests/artifacts/improvements-timing.json`; that browser fixture uses demo data,
not the 5,000-record benchmark dataset. Neither measurement establishes production
percentiles.

The final desktop/phone browser verification measured navigation to usable Home
work at 279.8 ms and its daily-work request at 106.3 ms (3,122 transferred bytes,
ten requested items). An earlier local run measured 332.2 ms and 108.8 ms,
respectively. These are individual demo-data observations, not percentiles or a
controlled browser before/after comparison.

## Workspace aggregation comparison — 2026-10-12

Linux/amd64, Intel Core i5-2415M at 2.30 GHz, parallelism 4, three iterations
per operation on the same 5,000-contact/application/document workload. The
isolated baseline source reverses this cycle's backend aggregation changes.
Before and after benchmarks ran sequentially; short means remain sensitive to
machine load and do not establish production percentiles.

| Operation | Before mean | After mean | Before bytes/request | After bytes/request |
| --- | ---: | ---: | ---: | ---: |
| Dashboard reports | 285.6 ms | 177.8 ms | 41,716,240 | 27,588,482 |
| Daily work | 270.1 ms | 249.5 ms | 64,664,994 | 50,132,189 |
| Workspace priorities | 1,655.1 ms | 262.8 ms | 167,207,696 | 41,697,328 |
| Operational attention | 495.3 ms | 0.78 ms | 113,665,538 | 26,645 |

Allocation profiles identified decoded workspace records, repeated copies of
full applications, construction of unused overview rows and repeated document
parent scans. Summary reports and priorities now read only their required
entities. Daily work reuses its document slice, indexes parents by reference,
and constructs overview rows only for the requested category while preserving
all counts. Operational reporting indexes document parents instead of scanning
all applications for every document. Priorities and operational attention use
independent SQL reads; attention keeps related queries in a read snapshot.

The optional Home AI brief now checks assistant capabilities instead of fetching
the full control-center payload. Workspace Files renders 25 rows per page while
filter counts cover its full accessible dataset. These frontend changes are
shared by both browser runs, so the browser comparison isolates backend changes.

Reproduce current backend measurements with:

```sh
cd golang-backend
go test -run '^$' -bench 'BenchmarkRepositoryWorkload/(daily-work|dashboard-reports|workspace-priorities|operations-attention)$' -benchtime=3x -benchmem
```

For complete-page measurements, `npm run test:workspace-next` seeds 5,000
contacts, applications and required documents with 20% in another workspace,
then measures three authenticated Home loads. It records navigation load time,
time until daily work is usable, time until all Home summaries finish, request
durations and transferred bytes in `tests/artifacts/next-workspace-report.json`.
Set `ECC_BASELINE_BINARY` to an isolated baseline server binary to compare both
backends with the same current frontend. Timing boundaries are automation-observed
readiness, including polling overhead; they are not browser paint measurements.
Browser validation and backup restoration use synthetic data and remain distinct
from actual staff sessions and deployment-specific provider acceptance.

The final sequential representative browser comparison recorded:

| Home readiness | Before median (3 loads) | After median (3 loads) |
| --- | ---: | ---: |
| Usable daily-work list | 1308.8 ms | 1237.4 ms |
| All Home summaries ready | 3495.0 ms | 1528.2 ms |

The first after load took 7,700.5 ms to usable work and 7,973.7 ms to all
summaries, while its next two summary loads took 1,380.2 and 1,528.2 ms. The
outlier is retained in the report. Faster backend aggregation does not establish
uniform cold-load performance; deployment traces and larger samples are needed
before setting a loading target. Both runs use the same current frontend and
fresh copies of the same synthetic database.

## Daily workflow revision — 2026-10-14

Current build, same representative fixture (5,000 contacts, applications and
required documents; 20% foreign workspace). Three local authenticated Home loads:

| Load | Usable daily work | Home summaries ready |
| --- | ---: | ---: |
| 1 | 1,587.8 ms | 2,077.9 ms |
| 2 | 877.1 ms | 1,563.7 ms |
| 3 | 945.0 ms | 1,647.9 ms |
| Median | 945.0 ms | 1,647.9 ms |

My work now precedes the overview, attention categories and overview breakdowns
start collapsed, and application cards include accessible document verification
requirements. This run also passed navigation, document filters and isolated
restore checks. No baseline binary was supplied, so these observations establish
current loading times rather than a controlled speedup. The all-summary boundary
is the existing Home summary readiness probe; it is not a paint measurement or a
guarantee that every optional component has finished. Detailed request durations
and bytes are in `tests/artifacts/next-workspace-report.json`.

The synthetic integration assessment remains incomplete and actual participant
sessions remain pending. These timings do not establish provider acceptance or
staff usability.
