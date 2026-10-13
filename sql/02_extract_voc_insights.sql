-- =============================================================================
-- VoC demo: extract insights from transcripts via BigQuery generative AI
-- =============================================================================
-- Replace placeholders:
--   YOUR_PROJECT  -> Google Cloud project ID
--   YOUR_DATASET  -> BigQuery dataset ID
--
-- Source: CALL_TRANSCRIPTIONS_DEMO_F
-- Target: VOC_CALL_INSIGHTS_F
--
-- Features map to Voice of Customer MVP BRD (Area 4 Insight Extraction, plus
-- product/journey, churn/competitor, failure vs value demand, explainability).
--
-- Tip: For cost control while testing, add WHERE transcript_key IN (...) or LIMIT
-- in the source CTE before running the full 1000-row extraction.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Create insights table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F` (
  -- Keys / lineage (BRD 2.1.1 stable identifiers)
  transcript_key STRING,
  conversation_id STRING,
  session_id STRING,
  transcript_start_utc DATETIME,

  -- Intent taxonomy (BRD 4.1.1, 11.4.1 multi-reason)
  main_intent STRING,
  secondary_intents ARRAY<STRING>,
  categorization_accuracy_score FLOAT64,

  -- Symptom / driver / root cause / solution (BRD 4.4.1, 4.5.1, 5.2.1)
  symptom STRING,
  driver STRING,
  driver_type STRING,  -- internal | external | unknown
  root_cause STRING,
  solution STRING,

  -- Product & journey context (BRD 5.1.1, 5.7 / 5.4.x)
  primary_product STRING,
  secondary_products ARRAY<STRING>,
  journey_step STRING,
  product_attribution_confidence FLOAT64,

  -- Sentiment (supporting UX / steering views; not a substitute for survey CSAT)
  sentiment_label STRING,  -- negative | neutral | positive
  sentiment_score FLOAT64, -- -1.0 .. 1.0

  -- Value vs failure demand (BRD 11.1.1, 11.2.1)
  demand_type STRING,  -- value_demand | failure_demand | mixed | unknown

  -- Competitor & churn (BRD 5.12.1, 5.14.1)
  competitor_name STRING,
  competitor_offer_text STRING,
  competitor_price_point STRING,
  churn_risk_flag BOOL,
  reason_for_leaving_category STRING,

  -- Segment context extracted when present in transcript META / dialogue
  customer_type STRING,
  region STRING,
  lifetime_segment STRING,

  -- Explainability (BRD Area 10)
  insight_summary_en STRING,
  insight_summary_sv STRING,
  evidence_quotes ARRAY<STRING>,

  -- Pipeline metadata
  extraction_model STRING,
  extraction_status STRING,
  extracted_at_utc DATETIME,

  -- Optional: autonomous embeddings on English summary for agent search of insights
  summary_embedding STRUCT<result ARRAY<FLOAT64>, status STRING>
    GENERATED ALWAYS AS (
      AI.EMBED(insight_summary_en, model => 'embeddinggemma-300m')
    ) STORED OPTIONS (asynchronous = TRUE)
);

-- -----------------------------------------------------------------------------
-- 2) Generative extraction into typed columns (AI.GENERATE + output_schema)
-- -----------------------------------------------------------------------------
INSERT INTO `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F` (
  transcript_key,
  conversation_id,
  session_id,
  transcript_start_utc,
  main_intent,
  secondary_intents,
  categorization_accuracy_score,
  symptom,
  driver,
  driver_type,
  root_cause,
  solution,
  primary_product,
  secondary_products,
  journey_step,
  product_attribution_confidence,
  sentiment_label,
  sentiment_score,
  demand_type,
  competitor_name,
  competitor_offer_text,
  competitor_price_point,
  churn_risk_flag,
  reason_for_leaving_category,
  customer_type,
  region,
  lifetime_segment,
  insight_summary_en,
  insight_summary_sv,
  evidence_quotes,
  extraction_model,
  extraction_status,
  extracted_at_utc
)
WITH
source AS (
  SELECT
    transcript_key,
    conversation_id,
    session_id,
    transcript_start_utc,
    transcript_text
  FROM `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`
  -- Uncomment to pilot on a subset:
  -- WHERE STARTS_WITH(transcript_key, 'TRK-000')
  -- LIMIT 50
),
extracted AS (
  SELECT
    s.transcript_key,
    s.conversation_id,
    s.session_id,
    s.transcript_start_utc,
    AI.GENERATE(
      CONCAT(
        'You are a Voice of Customer analyst for a Swedish telecom (Telenor-like). ',
        'Extract structured insights from the call transcript below. ',
        'Use concise English taxonomy labels for categorical fields (snake_case or short phrases). ',
        'Summaries: provide both English and Swedish. ',
        'If a field is not supported by the transcript, return null / empty array as appropriate. ',
        'Do not invent competitor names or prices unless explicitly mentioned. ',
        'demand_type: value_demand = creates customer/business value; ',
        'failure_demand = contact because something did not work as intended; mixed if both. ',
        'driver_type: internal (company process/comms/product) or external (competitor/market/life event). ',
        'categorization_accuracy_score and product_attribution_confidence are 0.0-1.0 self-assessed confidence. ',
        'sentiment_score is -1.0 (very negative) to 1.0 (very positive). ',
        'evidence_quotes: 1-3 short verbatim snippets from the transcript.\n\n',
        'TRANSCRIPT:\n',
        s.transcript_text
      ),
      endpoint => 'gemini-2.5-flash',
      output_schema => CONCAT(
        'main_intent STRING, ',
        'secondary_intents ARRAY<STRING>, ',
        'categorization_accuracy_score FLOAT64, ',
        'symptom STRING, ',
        'driver STRING, ',
        'driver_type STRING, ',
        'root_cause STRING, ',
        'solution STRING, ',
        'primary_product STRING, ',
        'secondary_products ARRAY<STRING>, ',
        'journey_step STRING, ',
        'product_attribution_confidence FLOAT64, ',
        'sentiment_label STRING, ',
        'sentiment_score FLOAT64, ',
        'demand_type STRING, ',
        'competitor_name STRING, ',
        'competitor_offer_text STRING, ',
        'competitor_price_point STRING, ',
        'churn_risk_flag BOOL, ',
        'reason_for_leaving_category STRING, ',
        'customer_type STRING, ',
        'region STRING, ',
        'lifetime_segment STRING, ',
        'insight_summary_en STRING, ',
        'insight_summary_sv STRING, ',
        'evidence_quotes ARRAY<STRING>'
      )
    ) AS g
  FROM source AS s
)
SELECT
  transcript_key,
  conversation_id,
  session_id,
  transcript_start_utc,
  g.main_intent,
  g.secondary_intents,
  g.categorization_accuracy_score,
  g.symptom,
  g.driver,
  g.driver_type,
  g.root_cause,
  g.solution,
  g.primary_product,
  g.secondary_products,
  g.journey_step,
  g.product_attribution_confidence,
  g.sentiment_label,
  g.sentiment_score,
  g.demand_type,
  g.competitor_name,
  g.competitor_offer_text,
  g.competitor_price_point,
  g.churn_risk_flag,
  g.reason_for_leaving_category,
  g.customer_type,
  g.region,
  g.lifetime_segment,
  g.insight_summary_en,
  g.insight_summary_sv,
  g.evidence_quotes,
  'gemini-2.5-flash' AS extraction_model,
  g.status AS extraction_status,
  CURRENT_DATETIME('UTC') AS extracted_at_utc
FROM extracted;

-- -----------------------------------------------------------------------------
-- 3) Validation / Looker-oriented sample queries
-- -----------------------------------------------------------------------------
-- Row counts & extraction health
-- SELECT
--   COUNT(*) AS insight_rows,
--   COUNTIF(extraction_status IS NULL OR extraction_status = '') AS ok_rows,
--   AVG(categorization_accuracy_score) AS avg_cat_confidence
-- FROM `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F`;

-- Intent volume (BRD 4.1.1)
-- SELECT main_intent, COUNT(*) AS calls
-- FROM `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F`
-- GROUP BY 1
-- ORDER BY calls DESC;

-- Multi-intent share (BRD 11.4.1)
-- SELECT
--   COUNTIF(ARRAY_LENGTH(secondary_intents) > 0) AS multi_intent_calls,
--   COUNT(*) AS total_calls
-- FROM `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F`;

-- Failure demand by product (BRD 11.2.1 + 5.1.1)
-- SELECT primary_product, demand_type, COUNT(*) AS calls
-- FROM `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F`
-- GROUP BY 1, 2
-- ORDER BY calls DESC;

-- Competitor mentions (BRD 5.14.1)
-- SELECT competitor_name, competitor_price_point, COUNT(*) AS mentions
-- FROM `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F`
-- WHERE competitor_name IS NOT NULL
-- GROUP BY 1, 2
-- ORDER BY mentions DESC;

-- Join path for Looker (transcript metrics + insights)
-- SELECT
--   t.transcript_key,
--   t.transcript_start_utc,
--   t.total_phrase_duration_ms,
--   t.avg_phrase_confidence,
--   i.main_intent,
--   i.symptom,
--   i.driver,
--   i.root_cause,
--   i.demand_type,
--   i.sentiment_label,
--   i.churn_risk_flag
-- FROM `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F` AS t
-- JOIN `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F` AS i
--   USING (transcript_key);
