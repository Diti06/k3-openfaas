# Deep Dive: Replicating the Paper's Methodology

You have uncovered a fascinating and highly critical methodology gap. By adding `code="200"` to our script, we exposed the truth: **Your cluster is computing furiously (CPU is maxed out at 8797 millicores), but 100% of the requests are failing before they can successfully complete.** 

Here is the exact analysis of why this is happening and the plan to fix it.

## The Experiment Methodology Gap

1. **The Queue Timeout Collapse**: When you use a ramping tool like `k6` to push up to 20,000 concurrent Virtual Users (VUs) against only 5 function pods, the OpenFaaS gateway places thousands of requests into a waiting queue. 
2. **Default Platform Limits**: By default, OpenFaaS has strict hardcoded timeouts (typically 10 seconds). Because calculating `500!` takes substantial CPU time, the requests sitting at the back of the queue wait longer than 10 seconds.
3. **The Zero RPS Result**: Once the timeout threshold is breached, the OpenFaaS Gateway preemptively aborts the connection and drops the request. This means the gateway likely returns HTTP `502 Bad Gateway`, `504 Gateway Timeout`, or `429 Too Many Requests`. This is exactly why `code="200"` returns `0` RPS—none of the requests are surviving the queue!
4. **The Paper's Secret**: In academic research, testing a Serverless platform up to 20,000 concurrency requires reconfiguring the platform's baseline architecture. The researchers almost certainly increased the `read_timeout`, `write_timeout`, and `exec_timeout` parameters inside their OpenFaaS configuration to allow requests to queue for several minutes without failing. 

## User Review Required

Before we begin applying heavy architectural changes to your OpenFaaS gateway limits, we must scientifically confirm the exact HTTP failure code your cluster is experiencing under load. 

Are you okay with stopping the current 30-minute test to run a rapid 1-minute diagnostic load test?

## Proposed Changes and Verification Plan

To fix this inconsistency and achieve the paper's graph, we will execute the following sequence:

### 1. The Diagnostic Test (Client-Side Verification)
We will run a 1-minute `k6` test that explicitly prints out the HTTP status codes it receives from the OpenFaaS gateway.
This will instantly prove if we are hitting `502 Bad Gateway` (Timeouts) or `429` (Queue Full).

### 2. The Architectural Fix (Methodology Alignment)
Depending on the exact error code, we will implement the paper's methodology:
*   **If Timeouts (504/502/500)**: We will patch the `stack.yaml` file to increase the `exec_timeout` and `read_timeout` to 5 minutes, allowing your heavy `500!` math functions to survive the massive queue.
*   **If Queue Full (429)**: We will modify the Kubernetes HPA (Horizontal Pod Autoscaler) or OpenFaaS queue-worker limits to accommodate 20,000 pending requests.

### 3. The Final Replication Run
Once the timeouts are removed, we will launch the synchronized 30-minute test again. The CPU will max out, the queue will hold the traffic safely, and your `code="200"` RPS will perfectly curve up to the ~1300 plateau seen in the paper.
