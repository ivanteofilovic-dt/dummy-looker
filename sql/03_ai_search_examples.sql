-- =============================================================================
-- VoC demo: AI.SEARCH examples + Conversational Analytics notes
-- =============================================================================
-- Replace placeholders:
--   YOUR_PROJECT  -> Google Cloud project ID
--   YOUR_DATASET  -> BigQuery dataset ID
--
-- Requires:
--   1) CALL_TRANSCRIPTIONS_DEMO_F populated (01_*.sql)
--   2) Autonomous embeddings finished for transcript_text
--      (transcript_embedding.status IS NULL or '')
--
-- Docs:
--   https://docs.cloud.google.com/bigquery/docs/autonomous-embedding-generation
--   https://docs.cloud.google.com/bigquery/docs/conversational-analytics#bigquery-ml-support
--   https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/bigqueryml-syntax-ai-search
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0) Embedding readiness check (run until ready ~= total)
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(
    transcript_embedding.status IS NULL
    OR transcript_embedding.status = ''
  ) AS ready_embeddings,
  COUNTIF(
    transcript_embedding.status IS NOT NULL
    AND transcript_embedding.status != ''
  ) AS pending_or_error,
  COUNT(*) AS total_rows
FROM `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`;

-- -----------------------------------------------------------------------------
-- 1) Semantic search over call transcripts (source column = transcript_text)
--    AI.SEARCH only uses autonomous embeddings; do not pass the embedding column.
-- -----------------------------------------------------------------------------
SELECT
  base.transcript_key,
  base.conversation_id,
  base.transcript_start_utc,
  SUBSTR(base.transcript_text, 1, 280) AS transcript_preview,
  distance
FROM AI.SEARCH(
  TABLE `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`,
  'transcript_text',
  'Customers calling about delayed broadband delivery and router setup problems',
  top_k => 10,
  distance_type => 'COSINE'
)
ORDER BY distance;

-- Billing / invoice confusion
SELECT
  base.transcript_key,
  SUBSTR(base.transcript_text, 1, 280) AS transcript_preview,
  distance
FROM AI.SEARCH(
  TABLE `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`,
  'transcript_text',
  'Faktura förvirring efter prisplansändring',
  top_k => 10
)
ORDER BY distance;

-- Churn + competitor offers
SELECT
  base.transcript_key,
  SUBSTR(base.transcript_text, 1, 280) AS transcript_preview,
  distance
FROM AI.SEARCH(
  TABLE `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`,
  'transcript_text',
  'Customer wants to leave because competitor offered cheaper mobile data plan',
  top_k => 10
)
ORDER BY distance;

-- -----------------------------------------------------------------------------
-- 2) Pre-filter + search (only SELECT/FROM/WHERE allowed in the subquery form)
-- -----------------------------------------------------------------------------
SELECT
  base.transcript_key,
  base.transcript_start_utc,
  SUBSTR(base.transcript_text, 1, 200) AS transcript_preview,
  distance
FROM AI.SEARCH(
  (
    SELECT *
    FROM `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`
    WHERE transcript_start_utc >= DATETIME_SUB(CURRENT_DATETIME('UTC'), INTERVAL 90 DAY)
  ),
  'transcript_text',
  'Failed self-service then called customer service',
  top_k => 5
)
ORDER BY distance;

-- -----------------------------------------------------------------------------
-- 3) Search insights summaries (after 02_*.sql and summary_embedding ready)
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(summary_embedding.status IS NULL OR summary_embedding.status = '') AS ready,
  COUNT(*) AS total
FROM `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F`;

SELECT
  base.transcript_key,
  base.main_intent,
  base.demand_type,
  base.insight_summary_en,
  distance
FROM AI.SEARCH(
  TABLE `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F`,
  'insight_summary_en',
  'Failure demand related to onboarding and activation',
  top_k => 10
)
ORDER BY distance;

-- -----------------------------------------------------------------------------
-- 4) Join search hits to structured VoC insights (Looker / agent-friendly)
-- -----------------------------------------------------------------------------
SELECT
  s.base.transcript_key,
  s.distance,
  i.main_intent,
  i.secondary_intents,
  i.symptom,
  i.driver,
  i.root_cause,
  i.primary_product,
  i.journey_step,
  i.demand_type,
  i.sentiment_label,
  i.churn_risk_flag,
  i.competitor_name,
  i.insight_summary_en
FROM AI.SEARCH(
  TABLE `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`,
  'transcript_text',
  'Number porting delayed after switching operator',
  top_k => 15
) AS s
LEFT JOIN `YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F` AS i
  ON s.base.transcript_key = i.transcript_key
ORDER BY s.distance;

-- =============================================================================
-- Conversational Analytics / data agent setup (console steps)
-- =============================================================================
-- 1. In BigQuery Studio, open Agent Catalog and create a data agent.
-- 2. Add knowledge sources:
--      - YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F
--      - YOUR_PROJECT.YOUR_DATASET.VOC_CALL_INSIGHTS_F
-- 3. Because autonomous embedding generation is enabled on transcript_text
--    (and insight_summary_en), the agent can use AI.SEARCH instead of
--    real-time AI.SIMILARITY for semantic questions.
-- 4. Suggested agent instructions (paste into agent instructions):
--
--    You are a Voice of Customer analyst for Swedish telecom call insights.
--    Prefer VOC_CALL_INSIGHTS_F for structured metrics (intent, symptom, driver,
--    root_cause, demand_type, product, sentiment, churn).
--    Use CALL_TRANSCRIPTIONS_DEMO_F for verbatim evidence and AI.SEARCH over
--    transcript_text when users ask "find calls about...".
--    Always distinguish interaction counts vs unique conversations.
--    Never expose or invent personal identifiers.
--    When confidence is low (categorization_accuracy_score < 0.6), say so.
--
-- 5. Example verified / golden questions for the agent:
--    - What are the top failure-demand intents in the last 90 days?
--    - Find calls similar to broadband delivery delays.
--    - Which products drive the most churn-risk contacts?
--    - Show competitor mentions with price points.
-- =============================================================================
