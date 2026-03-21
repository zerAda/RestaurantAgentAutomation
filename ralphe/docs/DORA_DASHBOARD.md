# 📊 DORA Metrics Dashboard (Diamond SaaS)

This dashboard tracks the four key metrics for measuring software delivery performance.

## 🚀 Speed Metrics

### 1. Deployment Frequency

#### Goal: At least once per day

- [ ] Weekly Avg:
- [ ] Trend: 📈/📉

### 2. Lead Time for Changes

#### Goal: Less than one day

- [ ] Median (Commit to Production):
- [ ] Performance Level: Elite / High / Medium / Low

## 🛡️ Stability Metrics

### 3. Change Failure Rate

#### Goal: Less than 15%

- [ ] Total Deploys:
- [ ] Failed Deploys:
- [ ] Rate: %

### 4. Time to Restore Service (MTTR)

#### Goal: Less than one hour

- [ ] Last Rollback Time:
- [ ] Avg Recovery:

---

## 📈 Recent Activity (from `dora_metrics.jsonl`)

| Timestamp  | Version | Status  | Lead Time | Duration |
| :--------- | :------ | :------ | :-------- | :------- |
| 2026-02-09 | v1.2.0  | SUCCESS | 450s      | 95s      |

> [!TIP]
> Use `scripts/generate-dora-report.sh` (Future Phase) to auto-populate this markdown from `dora_metrics.jsonl`.
