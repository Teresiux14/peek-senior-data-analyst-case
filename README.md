# TheLook Commerce: Senior Data Analyst Case

**The short answer:** TheLook is growing fast, and most of that growth comes from new customers. The weak point is repeat purchase: in June 2026, only 6.2% of active customers bought again within 90 days. Improving repeat purchase is the biggest lever that was found.

**Dashboard (Sigma):** https://app.sigmacomputing.com/embed/1-61XNPEKuMmIA5z1xJUkAWf
**Presentation:** https://canva.link/9ljypds25bhnugx

---

## 1. Key findings

- **Revenue** reached $123,745 in September 2026, up 7.4% from August. Gross margin has stayed between 48.9% and 55.0% every month since 2019, around 52% on average.
- **Growth comes mainly from acquisition.** In July to September 2026, new customers were 83.5% of active customers.
- **Repeat behavior is low, not falling.** Returning customers pay for about 17% of revenue in September 2026, and that share has risen since 2019. The absolute number of returning customers also grew, from 73 in September 2025 to 226 in September 2026.
- **Few customers come back within 90 days.** In June 2026, 93.8% of active customers made no purchase in the following 90 days.

The CEO's concern is partly right: growth depends on acquisition. But the data does not show repeat purchase weakening. It shows that repeat purchase has always been low.

## 2. Data window and cutoff

- **Cutoff: 30 September 2026.** October 2026 has only 17 days of data, so it is a partial month and is excluded.
- **Window: January 2019 to September 2026.** The full history is kept because retention needs complete customer histories.
- **Low-volume months** (fewer than 500 orders) are flagged, from January 2019 to February 2025. With few orders, one purchase can move a percentage a lot. 
- **The public dataset keeps receiving orders**, so totals change slightly over time. All figures in this README were read from the views as of 17 October 2026.

## 3. Data quality: what I checked and what I decided

I ran 16 checks (see `sql/part1_queries.sql`). The main findings:

| Finding | Impact | Decision |
|---|---|---|
| About 30% of shipped items have a shipping date before their creation date. About 76% of items fall outside their order's time window. | Using item dates would shift monthly revenue by up to 2.3%. About $3,661 of September revenue would move into October. | Use `orders.created_at` as the reference date. The order header passes every check (item counts match, no order ships before it is created). |
| 272 events (0.02%) are dated before their user's signup, all within 3 hours before it. | Consistent with browsing as a guest before creating an account. | Flagged, not removed. Customer metrics use the first completed order, so they do not depend on signup dates. |
| No orders dated before their user's signup. | None. | No action. |
| No duplicate keys, orphan links, invalid prices, or costs above list price. | None. | Passed. |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Completed sale | `status = 'Complete'` and `returned_at IS NULL` (case definition) |
| Revenue | Sum of `sale_price` for completed sales |
| Gross profit | Revenue minus the cost of the item sold (`inventory_items.cost`) |
| Gross margin % | Gross profit ÷ revenue |
| AOV | Revenue ÷ number of distinct orders |
| Active customer | At least one completed order in the month |
| New customer | Their first completed order falls in that month |
| Returning customer | Active in a month after their first order month |
| Churned customer (90 days) | Active in month M, with no completed order in the 90 days after the end of M |
| Mature month | The 90-day window closes on or before the cutoff. The last mature month is June 2026. |
| Session conversion (case definition) | Sessions with a `purchase` event ÷ sessions with a `department` event |

## 5. One number to read carefully: session conversion

Session conversion, as the case defines it, is 76% in September 2026. That is high for a reason. A `purchase` event is a click on "buy," not a completed order. In the same month there were 8,396 sessions with a purchase click and 1,385 orders.

I report the case definition as requested, with this explanation, and do not use it as a headline. As a supporting signal, about 80% of orders have a purchase click from the same user within the 6 hours before the order. That share is stable every year. It shows that purchase clicks are a reasonable intent signal, but it is not a funnel conversion rate.

## 6. Recommendation: improve repeat purchase

**Why this one:** retention at 90 days is about 6%, returning customers are 17% of revenue, and each new customer who never returns is an acquisition cost that is not recovered. Activation and returns were not chosen: the case's activation step (first completed order) is nearly universal in this data, and the funnel cannot be measured reliably from the session data.

**Recommendations**

1. **A second-purchase program for new customers** during their first 90 days.
2. **Measure repeat rate by monthly acquisition cohort** for brand partners and campaigns, so each acquisition channel can be judged on whether its customers come back.

**Success metrics**

- **Primary:** share of new customers who place a second order within 90 days.
- **Secondary:** AOV of second orders.
- **Guardrail:** gross margin stays around its current 52%.

This is a hypothesis, not a proven result. Test it with a control group before scaling.

## 7. Assumptions

- The 90-day churn window comes from the case. It is not calibrated to actual purchase intervals. In production, I would set it from the median time between purchases.
- The attribution window is 6 hours. A 24-hour window gave nearly the same result.
- The low-volume threshold is 500 orders per month.
- A sale above 2× list price is a warning threshold, not proof of an error.
- Churn counts customers, not revenue. A high-volume buyer weighs the same as a one-time buyer.
- The dataset is synthetic. Its margins are very stable (about 52%), which real data rarely is.

## 8. What I skipped, and what I would do next

- **Duplicate-event check:** not run. Duplicate orders and items were checked.
- **Return analysis by product category:** the case's third priority. With more time, I would measure return rate by category and brand.
- **Order-level conversion funnel:** the data has no session-to-order key, so a true funnel needs better event tracking.
- **Calibrating the churn window** against purchase cycles.

## 9. How to run

1. In BigQuery, create a dataset named `analysis` in project `peek-data-case`, in the **US** location. The public dataset is in US, and queries across regions fail.
2. Run `sql/part1_queries.sql` as a script. It creates the view `completed_order_items`, then returns the checks, the monthly health table, the attribution table, new vs. returning customers, and 90-day churn.
3. Run `sql/dashboard_views.sql`. It creates `monthly_summary` and `cohort_retention`, which the dashboard reads.
4. Connect Sigma to these views.

**To change the cutoff:** views cannot use `DECLARE`, so the date `2026-09-30` appears inside `completed_order_items` and `monthly_summary`, and the `as_of_date` parameter in `part1_queries.sql`. Update all of them together.

## 10. Files

```
sql/
├── part1_queries.sql      checks, base view, monthly health, attribution, B1, B2
└── dashboard_views.sql    monthly_summary (for Sigma)
└── dashboard_views.sql    Optional_stretch (for Sigma)
analysis/
└── presentation.pdf       presentation
```
## 11. AI Usage
## Part 3: AI & Analytics

### 1. Proposed workflow: monthly anomaly notes

- **Workflow and data:** SQL flags unusual monthly changes; AI drafts a short note using approved metrics, comparisons, definitions, and reporting dates from `monthly_summary`. No customer IDs, raw transactions, or other partners’ data.
- **Prompt:** “Summarize the flagged changes using only the supplied figures. Cite the source fields, suggest one next check, and label possible explanations as hypotheses. Flag missing information rather than guessing.”
- **Guardrails and human review:** Calculate and validate numbers outside the model, enforce partner access before retrieval, and require analyst approval before sending.
- **Measurement:** Track readership and follow-up actions, factual accuracy and edits, time saved, and useful issues identified. Pause immediately for data leakage or repeated factual errors; discontinue if review effort outweighs the benefit.

### 2. AI use in this challenge

- I used ChatGPT to help me write the cohort retention SQL and understand its logic, then configure the heatmap in Sigma.
- **Example prompt (paraphrased):** “Help me write BigQuery SQL for monthly cohort retention, from month 0 to 12. Include observed months with no repeat purchases as zero, but leave future months out.”
- **Validation:** I reviewed the SQL logic and checked the resulting heatmap, including that month 0 showed 100%.
- **Correction:** AI initially suggested `Today()` for dashboard reporting indicators. I replaced it with a fixed reference aligned with the September 2026 cutoff to keep the analysis reproducible.


## 12. Links

- Dashboard: https://app.sigmacomputing.com/embed/1-61XNPEKuMmIA5z1xJUkAWf
- Presentation: https://canva.link/9ljypds25bhnugx
- Repository: https://github.com/Teresiux14/peek-senior-data-analyst-case
