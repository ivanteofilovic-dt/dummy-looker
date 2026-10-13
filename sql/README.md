# BigQuery VoC Generative AI Pipeline

Sandbox SQL to (1) populate ~1000 synthetic call transcripts matching `CALL_TRANSCRIPTIONS_F`, (2) extract Voice of Customer insights with BigQuery generative AI, and (3) enable autonomous embeddings (`embeddinggemma-300m`) so Conversational Analytics data agents can use `AI.SEARCH`.

## Placeholders

Replace in every script before running:

| Placeholder | Meaning |
|---|---|
| `YOUR_PROJECT` | Google Cloud project ID |
| `YOUR_DATASET` | BigQuery dataset ID |

Example:

```bash
sed 's/YOUR_PROJECT/my-sandbox/g; s/YOUR_DATASET/voc_demo/g' \
  sql/01_create_and_populate_transcripts.sql
```

## Prerequisites

- BigQuery dataset in a region that supports AI functions (US/EU multi-region recommended)
- Permission to create tables and run `AI.GENERATE` / `AI.EMBED` / `AI.SEARCH`
- No Vertex AI connection required for the default path (`embeddinggemma-300m` + default Gemini endpoint for generation)

## Run order

1. **`01_create_and_populate_transcripts.sql`**
   - Creates `CALL_TRANSCRIPTIONS_DEMO_F` with autonomous `transcript_embedding`
   - Seeds ~50 telecom scenarios, expands with `AI.GENERATE`, SQL-varies to 1000 rows
2. **Wait for embeddings**
   - Run the readiness query in `03_ai_search_examples.sql` until `ready_embeddings ≈ total_rows`
3. **`02_extract_voc_insights.sql`**
   - Creates `VOC_CALL_INSIGHTS_F` and extracts structured features via `AI.GENERATE`
   - Pilot with `LIMIT 50` first if you want to validate cost/latency
4. **`03_ai_search_examples.sql`**
   - Semantic search examples + data-agent setup notes

## Tables

| Table | Purpose |
|---|---|
| `CALL_TRANSCRIPTIONS_DEMO_F` | Demo source transcripts (+ `transcript_embedding`) |
| `VOC_CALL_INSIGHTS_F` | Per-call VoC features (+ `summary_embedding` on English summary) |
| `_voc_scenario_seeds` | Intermediate scenario templates |
| `_voc_base_transcripts` | Intermediate AI-expanded bases |
| `_voc_variation_dims` | Intermediate variation dimensions |

## Cost & latency notes

- Step 01 hybrid path: ~50 `AI.GENERATE` calls (not 1000), then SQL expansion
- Step 02: up to 1000 `AI.GENERATE` structured extractions — expect minutes and Gemini usage; use a subset for dry runs
- Autonomous embeddings run asynchronously after insert; `AI.SEARCH` skips rows without ready embeddings
- Optional full-AI 1000-transcript variant is commented at the bottom of `01_*.sql`

## Insight columns → BRD mapping

| Column(s) | BRD requirement | Use in Looker |
|---|---|---|
| `transcript_key`, `conversation_id`, `session_id` | 2.1.1 stable identifiers | Primary keys / joins |
| `main_intent`, `secondary_intents` | 4.1.1, 11.4.1 multi-intent | Intent dashboards, multi-reason capture |
| `categorization_accuracy_score` | 4.1.1 accuracy scoring | Filter low-quality labels |
| `symptom` | 4.5 / 2.2.1 | Symptom views |
| `driver`, `driver_type` | 4.4.1, 5.2.1 | Trigger / driver analysis |
| `root_cause`, `solution` | 4.5.1 | Root-cause & remedy |
| `primary_product`, `secondary_products`, `journey_step`, `product_attribution_confidence` | 5.1.1, 5.7 / 5.4.x | Value-chain / product filters |
| `sentiment_label`, `sentiment_score` | Supporting UX (CSAT remains survey metadata per 9.1.1) | Experience context |
| `demand_type` | 11.1.1 / 11.2.1 | Value vs failure demand |
| `competitor_name`, `competitor_offer_text`, `competitor_price_point` | 5.14.1 | Competitor threat tracking |
| `churn_risk_flag`, `reason_for_leaving_category` | 5.12.1 / 5.14.1 | Retention analysis |
| `customer_type`, `region`, `lifetime_segment` | 5.8.1, 5.9.1 | Segmentation |
| `insight_summary_en`, `insight_summary_sv`, `evidence_quotes` | 7.3.1 bilingual, Area 10 explainability | Narrative + drill-to-evidence |
| `transcript_text` + autonomous embedding | Conversational analytics `AI.SEARCH` | Semantic search / data agents |

## Suggested Looker join

```
CALL_TRANSCRIPTIONS_DEMO_F.transcript_key
  = VOC_CALL_INSIGHTS_F.transcript_key
```

Use transcript metrics (`total_phrase_duration_ms`, confidence fields) as operational context next to intent / demand / churn fields (BRD 4.3.1 style).

## AI.SEARCH & data agents

- Autonomous embedding is defined on `transcript_text` → agents can call `AI.SEARCH` on that column
- Insights table also embeds `insight_summary_en` for summary-level semantic search
- Without autonomous embeddings, agents fall back to `AI.SIMILARITY` (real-time embedding)
- See comments at the end of `03_ai_search_examples.sql` for agent instructions and sample questions

## Out of scope (this folder)

- Writing to production `tse-prod-nexp-dataplatform.pub.CALL_TRANSCRIPTIONS_F`
- Vertex `text-embedding-005` connection setup
- Looker explores / dashboards (add after tables exist)
