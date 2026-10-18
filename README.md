# TheLook Commerce: Senior Data Analyst Case

**What the data shows:** TheLook is growing fast, and most of that growth comes from new customers. A weak point is repeat purchases: in June 2026, only 6.2% of active customers bought again within 90 days after that month ended. The data suggests that it could be worth trialing an effort towards increasing repeat purchases. 

**Dashboard (Sigma):** https://app.sigmacomputing.com/embed/1-61XNPEKuMmIA5z1xJUkAWf

**Presentation:** https://canva.link/9ljypds25bhnugx

---

## 1. Key findings

- **Revenue** reached $123,745 in September 2026, up 7.4% from August. Gross margin has stayed between 48.9% and 55.0% every month since 2019, around 52% on average.
- **Most growth comes from acquisition.** In July to September 2026, new customers were 83.5% of active customers.
- **Repeat behavior is low, not decreasing.** Returning customers pay for about 17% of revenue in September 2026, and that share has risen since 2019. The absolute number of returning customers also grew, from 73 in September 2025 to 226 in September 2026.
- **Few customers come back within 90 days.** In June 2026, 93.8% of active customers made no purchase in the following 90 days.

There is partial truth to the CEO's concern: growth depends heavily on acquisition. But the data does not show repeat purchase weakening. It shows that repeat purchase has always been low.

## 2. Data window and cutoff

- **Cutoff: 30 September 2026.** October 2026 has only 17 days of data, so it is considered a partial month and is excluded.
- **Analysis Period: January 2019 to September 2026**. The entire dataset was retain to ensure we capture the complete customer journeys necessary for measuring retention accurately.
- **Low-volume months** (fewer than 500 orders) are flagged, this falls between January 2019 and February 2025. With fewer orders, one purchase can move a percentage a lot. 
- **The public dataset keeps updating, and receiving orders**, so totals change slightly over time. All figures in this README were extracted from the dataset views as of 17 October 2026.

## 3. Data quality: what I checked and what I decided

I ran 16 checks (see `sql/part1_queries.sql`). The main findings:

| Finding | Impact | Decision |
|---|---|---|
| About 30% of shipped items have a shipping date before their creation date. About 76% of items fall outside their order's time window. | Using item dates would shift monthly revenue by up to 2.3%. About $3,661 of September revenue would move into October. | Use `orders.created_at` as the reference date. The order header passes all of my checks (item counts match, no order ships before it is created). |
| 272 events (0.02%) are dated before their user's signup, all within 3 hours before it. | Behavior is consistent with browsing as a guest before creating an account. | Customer metrics use the first completed order, so they do not depend on signup dates. |
| No orders dated before their user's signup. | Ensures temporal accuracy for these user events. | No action. |
| No duplicate keys, orphan links, invalid prices, or costs above list price. | Ensures complete relational integrity across the dataset. | No action. |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Completed sale | `status = 'Complete'` and `returned_at IS NULL` (As defined in the case paperwork) |
| Revenue | Sum of `sale_price` for completed sales |
| Gross profit | Revenue minus the cost of the item sold (`inventory_items.cost`) |
| Gross margin % | Gross profit ÷ revenue |
| Average Order Value | Revenue ÷ number of distinct orders |
| Active customer | At least one completed order in the month |
| New customer | Their first completed order falls in that month |
| Returning customer | Active in a month after their first order month |
| Churned customer (90 days) | Active in month X, with no completed order in the 90 days after the end of X |
| Mature month | The 90-day window closes on or before the cutoff. The last mature month is June 2026. |
| Session conversion (case definition) | Sessions with a `purchase` event ÷ sessions with a `department` event |

## 5. Misleading Metric: Session Conversion

Caution should be used when interpreting the 76% session conversion rate for September 2026. Because a purchase event tracks "buy" clicks rather than completed checkouts, it drastically overstates performance. The metric's flaw is evident when comparing the 8,396 "purchase" sessions recorded that month against the 1,385 actual orders generated.

Though included to meet case requirements, this metric should not be used as a headline KPI. With a consistent 80% of orders preceded by a purchase click within six hours, it serves best as an early intent signal, provided it is not misinterpreted as a final conversion rate.

## 6. Recommendation: improve repeat purchase

Retention at 90 days is about 6%, returning customers are 17% of revenue, and each new customer who never returns is an acquisition cost that is not recovered. Activation and returns were not chosen: the case's activation step (first completed order) is nearly universal in this data, and the funnel cannot be measured reliably from the session data. 

**Recommendations**
1. **A second-purchase program for new customers** during their first 90 days.
2. **Measure repeat rate by monthly acquisition cohort** for brand partners and campaigns, so each acquisition channel can be judged on whether its customers come back.

**Success metrics**
- **Primary:** share of new customers who place a second order within 90 days.
- **Secondary:** AOV of second orders.
- **Guardrail:** gross margin stays around its current 52%.

*Validate this hypothesis through a controlled test before scaling.

## 7. Assumptions

- The 90-day churn window is defined by case parameters rather than actual purchase behavior. In a production environment, this threshold should be calibrated to the median time between purchases.
- The attribution window is 6 hours, the maximum recorded delay between a finalized purchase and system order creation. Expanding to 24 hours showed no significant variance. 
- The low-volume threshold is 500 orders per month.
- A sale above 2× list price is a warning threshold, not proof of an error.
- Churn counts customers, not revenue. A high-volume buyer weighs the same as a one-time buyer.
- The dataset is synthetic. Its margins are very stable (about 52%), which real data rarely is.
- A 60- or 120-day window would change the churn level. Shorter windows flag more churn but mature sooner. Longer windows are more reliable but leave fewer mature months.

## 8. What I skipped, and what I would do next

- **Run duplicate-event checks:** While orders and items have already been verified, event-level deduplication still needs to be implemented.
- **Return analysis by product category:** the case's third priority. With more time, I would measure return rate by category and brand.
- **Order-level conversion funnel:** the data has no session-to-order key, so a true funnel needs better event tracking.
- **Calibrating the churn window** against real purchase cycles.

## 9. How to run

1. In BigQuery, create a dataset named `analysis` in project `peek-data-case`, in the **US** location. The public dataset is in US, and queries across regions fail.
2. Run `sql/part1_queries.sql` as a script. It creates the view `completed_order_items`, then returns the checks, the monthly health table, the attribution table, new vs. returning customers, and 90-day churn.
3. Run `sql/dashboard_views.sql`. It creates `monthly_summary` and `cohort_retention`, which the dashboard reads.
4. Connect Sigma to these views.

**Where the cutoff and threshold live:**
- **Cutoff (`2026-09-30`):** written in `completed_order_items` (`part1_queries.sql`, section A2), `monthly_summary` and `cohort_retention` (`dashboard_views.sql`), and the churn maturity check in `monthly_summary`. The `as_of_date` parameter in `part1_queries.sql` is used by the checks and the attribution query.
- **Low-volume threshold (500 orders):** set as `low_volume_threshold` in `part1_queries.sql` (A3) and written again in `monthly_summary` (`is_low_volume`).

To change either value, update every location above and recreate the views in order.

## 10. Files

```
sql/
├── part1_queries.sql      checks, base view, monthly health, attribution, B1, B2
└── dashboard_views.sql    monthly_summary (for Sigma)
└── part1_queries.sql    Optional_stretch (for Sigma)
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
