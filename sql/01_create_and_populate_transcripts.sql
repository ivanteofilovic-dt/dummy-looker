-- =============================================================================
-- VoC demo: create CALL_TRANSCRIPTIONS_DEMO_F (1000 rows) + autonomous embeddings
-- =============================================================================
-- Replace placeholders before running:
--   YOUR_PROJECT  -> Google Cloud project ID
--   YOUR_DATASET  -> BigQuery dataset ID
--
-- Prerequisites:
--   - BigQuery AI functions available in your region (US / EU multi-region recommended)
--   - Permission to create tables and run AI.GENERATE / AI.EMBED
--
-- Embedding model: built-in embeddinggemma-300m (no Vertex connection required)
-- This enables AI.SEARCH for Conversational Analytics data agents.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Target table (schema aligned to CALL_TRANSCRIPTIONS_F + embedding column)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F` (
  transcript_key STRING,
  conversation_id STRING,
  session_id STRING,
  transcript_start_utc DATETIME,
  transcript_text STRING,
  avg_phrase_confidence FLOAT64,
  min_phrase_confidence FLOAT64,
  max_phrase_confidence FLOAT64,
  first_phrase_start_utc DATETIME,
  end_phrase_start_utc DATETIME,
  total_phrase_duration_ms INT64,
  phrase_count INT64,
  p_hdiff STRING,
  p_ldts DATETIME,
  -- Autonomous embedding for AI.SEARCH (source column = transcript_text)
  transcript_embedding STRUCT<result ARRAY<FLOAT64>, status STRING>
    GENERATED ALWAYS AS (
      AI.EMBED(transcript_text, model => 'embeddinggemma-300m')
    ) STORED OPTIONS (asynchronous = TRUE)
);

-- -----------------------------------------------------------------------------
-- 2) Scenario seed templates (~50 Swedish telecom CS scenarios)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `YOUR_PROJECT.YOUR_DATASET._voc_scenario_seeds` AS
SELECT * FROM UNNEST([
  STRUCT(1 AS scenario_id, 'billing_invoice' AS scenario_key, 'Billing' AS theme, 'Invoice confusion after price plan change' AS brief),
  STRUCT(2, 'billing_overcharge', 'Billing', 'Customer disputes unexpected charges on monthly bill'),
  STRUCT(3, 'billing_final_invoice', 'Billing', 'Questions about final invoice after termination'),
  STRUCT(4, 'price_plan_migration', 'Billing', 'Price plan migration email triggered contact'),
  STRUCT(5, 'delivery_delay_broadband', 'Delivery', 'Fixed broadband delivery delayed beyond promised date'),
  STRUCT(6, 'delivery_hardware', 'Delivery', 'Router / CPE not received after order'),
  STRUCT(7, 'onboarding_activation', 'Onboarding', 'Cannot activate new subscription'),
  STRUCT(8, 'onboarding_setup_wifi', 'Onboarding', 'WiFi setup issues with new router'),
  STRUCT(9, 'number_porting', 'Porting', 'Mobile number porting stuck or delayed'),
  STRUCT(10, 'network_outage', 'Network', 'No connectivity suspected local outage'),
  STRUCT(11, 'network_slow', 'Network', 'Slow speeds on fixed broadband'),
  STRUCT(12, 'mobile_no_service', 'Network', 'No mobile coverage / cannot make calls'),
  STRUCT(13, 'sim_replacement', 'Technical', 'SIM card not working, needs replacement'),
  STRUCT(14, 'app_login', 'Digital', 'Cannot log in to My Telenor app'),
  STRUCT(15, 'selfservice_failed', 'Digital', 'Failed self-service payment or order flow'),
  STRUCT(16, 'churn_competitor_tre', 'Churn', 'Considering leaving; mentions Tre offer'),
  STRUCT(17, 'churn_competitor_telenor_rival', 'Churn', 'Competitor offer with data and price mentioned'),
  STRUCT(18, 'churn_billing_frustration', 'Churn', 'Repeated billing contacts leading to termination request'),
  STRUCT(19, 'retention_upgrade', 'Sales', 'Device upgrade eligibility discussion'),
  STRUCT(20, 'sales_add_tv', 'Sales', 'Interest in adding TV package'),
  STRUCT(21, 'roaming_charges', 'Billing', 'Unexpected roaming charges abroad'),
  STRUCT(22, 'contract_length', 'Billing', 'Questions about binding period and early termination fee'),
  STRUCT(23, 'payment_failed', 'Billing', 'Failed Autogiro / card payment'),
  STRUCT(24, 'invoice_pdf', 'Billing', 'Cannot find or open invoice PDF'),
  STRUCT(25, 'broadband_install_tech', 'Delivery', 'Technician visit missed / reschedule needed'),
  STRUCT(26, 'address_move', 'Onboarding', 'Moving address and transferring service'),
  STRUCT(27, 'wifi_mesh', 'Technical', 'WiFi dead zones; mesh / extender advice'),
  STRUCT(28, 'tv_box_fault', 'Technical', 'TV box not starting or buffering'),
  STRUCT(29, 'streaming_quality', 'Technical', 'Streaming services buffering on Telenor TV'),
  STRUCT(30, 'data_cap', 'Mobile', 'Data bucket exhausted mid-month'),
  STRUCT(31, 'esim_setup', 'Mobile', 'eSIM activation problems on new phone'),
  STRUCT(32, 'handset_insurance', 'Mobile', 'Device insurance claim process'),
  STRUCT(33, 'spam_calls', 'Mobile', 'Spam / fraud call blocking help'),
  STRUCT(34, 'b2b_invoice', 'B2B', 'B2B company invoice split / cost centre issue'),
  STRUCT(35, 'b2b_new_lines', 'B2B', 'Add mobile lines for employees'),
  STRUCT(36, 'fixed_partner_network', 'Network', 'Issue on partner / open network address universe'),
  STRUCT(37, '5g_home_delivery', 'Delivery', 'Bredband 5G delivery / coverage disappointment'),
  STRUCT(38, 'campaign_mismatch', 'Billing', 'Campaign price not matching what was promised'),
  STRUCT(39, 'consent_marketing', 'Digital', 'Wants to stop marketing SMS / emails'),
  STRUCT(40, 'gdpr_data_request', 'Compliance', 'Customer asks what data is stored'),
  STRUCT(41, 'outage_followup', 'Network', 'Follow-up after known incident still not fixed'),
  STRUCT(42, 'repeat_contact_billing', 'Billing', 'Second call within 7 days about same invoice'),
  STRUCT(43, 'channel_switch_chat', 'Journey', 'Tried chat/app then called about same issue'),
  STRUCT(44, 'prepaid_topup', 'Mobile', 'Prepaid top-up not registered'),
  STRUCT(45, 'family_subscription', 'Mobile', 'Family share / extra user setup'),
  STRUCT(46, 'router_model_a', 'Technical', 'Setup issues specific to router model A'),
  STRUCT(47, 'router_model_b', 'Technical', 'WiFi instability on router model B'),
  STRUCT(48, 'price_increase_letter', 'Billing', 'Reaction to price increase notification letter'),
  STRUCT(49, 'cancellation_process', 'Churn', 'How to cancel and what happens to equipment'),
  STRUCT(50, 'loyalty_discount', 'Retention', 'Long-term customer asks for loyalty discount')
]);

-- -----------------------------------------------------------------------------
-- 3) AI expansion: one realistic transcript per scenario (hybrid base set)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `YOUR_PROJECT.YOUR_DATASET._voc_base_transcripts` AS
SELECT
  s.scenario_id,
  s.scenario_key,
  s.theme,
  s.brief,
  gen.transcript_text,
  gen.status AS generate_status
FROM `YOUR_PROJECT.YOUR_DATASET._voc_scenario_seeds` AS s,
UNNEST([
  AI.GENERATE(
    CONCAT(
      'You are generating synthetic, anonymized Swedish telecom customer-service call transcripts ',
      'for a Voice of Customer analytics demo (Telenor Sverige style). ',
      'Write a realistic bilingual-leaning Swedish transcript (Swedish dialogue is preferred; ',
      'short English terms OK) between Kund and Agent. ',
      'Include: greeting, problem description, clarifying questions, resolution or next step. ',
      'Do NOT include real person names, SSN, phone numbers, or addresses. ',
      'Use placeholders like [KUND], [AGENT], [ORDER_ID], [ADRESS]. ',
      'Length: 12-22 dialogue turns. Output only the transcript text.\n\n',
      'Theme: ', s.theme, '\n',
      'Scenario key: ', s.scenario_key, '\n',
      'Brief: ', s.brief
    ),
    endpoint => 'gemini-2.5-flash',
    output_schema => 'transcript_text STRING'
  )
]) AS gen;

-- Optional quality gate: keep only successful generations
-- (re-run this script section if some rows fail)
-- SELECT scenario_id, generate_status FROM `YOUR_PROJECT.YOUR_DATASET._voc_base_transcripts`
-- WHERE generate_status IS NOT NULL AND generate_status != '';

-- -----------------------------------------------------------------------------
-- 4) SQL variation layer: expand ~50 bases to 1000 distinct rows
--    Variation axes: product, customer type, region, lifetime segment, rewrite tag
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `YOUR_PROJECT.YOUR_DATASET._voc_variation_dims` AS
SELECT * FROM UNNEST([
  STRUCT(0 AS variant_id, 'Mobil' AS product, 'B2C' AS customer_type, 'Stockholm' AS region, '0-90 days' AS lifetime_segment),
  STRUCT(1, 'Bredband', 'B2C', 'Göteborg', '3-12 months'),
  STRUCT(2, 'TV', 'B2C', 'Malmö', '1-2 years'),
  STRUCT(3, 'Bredband 5G', 'B2C', 'Uppsala', '2-5 years'),
  STRUCT(4, 'Mobil + Bredband', 'B2C', 'Västerås', '5-10 years'),
  STRUCT(5, 'Företag Mobil', 'B2B', 'Linköping', '10+ years'),
  STRUCT(6, 'Företag Bredband', 'B2B', 'Örebro', '1-2 years'),
  STRUCT(7, 'Mobil', 'B2C', 'Helsingborg', '0-90 days'),
  STRUCT(8, 'Bredband', 'B2C', 'Norrköping', '3-12 months'),
  STRUCT(9, 'TV + Bredband', 'B2C', 'Jönköping', '2-5 years'),
  STRUCT(10, 'Mobil', 'B2C', 'Umeå', '5-10 years'),
  STRUCT(11, 'Bredband', 'B2C', 'Lund', '10+ years'),
  STRUCT(12, 'Mobil', 'B2C', 'Gävle', '0-90 days'),
  STRUCT(13, 'Bredband 5G', 'B2C', 'Borås', '3-12 months'),
  STRUCT(14, 'Företag Mobil', 'B2B', 'Sundsvall', '1-2 years'),
  STRUCT(15, 'Mobil', 'B2C', 'Karlstad', '2-5 years'),
  STRUCT(16, 'TV', 'B2C', 'Växjö', '5-10 years'),
  STRUCT(17, 'Bredband', 'B2C', 'Halmstad', '10+ years'),
  STRUCT(18, 'Mobil + TV', 'B2C', 'Eskilstuna', '0-90 days'),
  STRUCT(19, 'Bredband', 'B2C', 'Trollhättan', '3-12 months')
]);

-- Build 1000 rows: 50 scenarios x 20 variants
INSERT INTO `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F` (
  transcript_key,
  conversation_id,
  session_id,
  transcript_start_utc,
  transcript_text,
  avg_phrase_confidence,
  min_phrase_confidence,
  max_phrase_confidence,
  first_phrase_start_utc,
  end_phrase_start_utc,
  total_phrase_duration_ms,
  phrase_count,
  p_hdiff,
  p_ldts
)
WITH
numbered AS (
  SELECT
    b.scenario_id,
    b.scenario_key,
    b.theme,
    b.transcript_text AS base_text,
    v.variant_id,
    v.product,
    v.customer_type,
    v.region,
    v.lifetime_segment,
    -- Stable row number 1..1000
    (b.scenario_id - 1) * 20 + v.variant_id + 1 AS row_num
  FROM `YOUR_PROJECT.YOUR_DATASET._voc_base_transcripts` AS b
  CROSS JOIN `YOUR_PROJECT.YOUR_DATASET._voc_variation_dims` AS v
  WHERE b.transcript_text IS NOT NULL
    AND LENGTH(b.transcript_text) > 80
),
enriched AS (
  SELECT
    row_num,
    scenario_id,
    scenario_key,
    theme,
    product,
    customer_type,
    region,
    lifetime_segment,
    -- Deterministic synthetic IDs
    FORMAT('TRK-%s', LPAD(CAST(row_num AS STRING), 6, '0')) AS transcript_key,
    FORMAT(
      'CONV-%s',
      SUBSTR(TO_HEX(SHA256(CONCAT(CAST(row_num AS STRING), scenario_key))), 1, 16)
    ) AS conversation_id,
    FORMAT(
      'SESS-%s',
      SUBSTR(TO_HEX(SHA256(CONCAT('sess', CAST(row_num AS STRING)))), 1, 16)
    ) AS session_id,
    -- Spread starts across last ~13 months
    DATETIME_SUB(
      CURRENT_DATETIME('UTC'),
      INTERVAL CAST(MOD(ABS(FARM_FINGERPRINT(CAST(row_num AS STRING))), 390) AS INT64) DAY
    )
    - INTERVAL CAST(MOD(ABS(FARM_FINGERPRINT(CONCAT('h', CAST(row_num AS STRING)))), 14) + 8 AS INT64) HOUR
    - INTERVAL CAST(MOD(ABS(FARM_FINGERPRINT(CONCAT('m', CAST(row_num AS STRING)))), 60) AS INT64) MINUTE
      AS transcript_start_utc,
    -- SQL variation of transcript (context banner + light lexical swaps)
    CONCAT(
      '[META product=', product,
      '; customer_type=', customer_type,
      '; region=', region,
      '; lifetime=', lifetime_segment,
      '; theme=', theme,
      '; scenario=', scenario_key,
      ']\n',
      REPLACE(
        REPLACE(
          REPLACE(base_text, '[PRODUCT]', product),
          'bredband',
          LOWER(product)
        ),
        'mobilabonnemang',
        CASE
          WHEN product LIKE '%Mobil%' THEN 'mobilabonnemang'
          WHEN product LIKE '%Bredband%' THEN 'bredbandsabonnemang'
          ELSE 'abonnemang'
        END
      )
    ) AS transcript_text,
    -- Plausible ASR confidence / duration stats
    ROUND(0.82 + MOD(ABS(FARM_FINGERPRINT(CONCAT('avg', CAST(row_num AS STRING)))), 15) / 100.0, 4)
      AS avg_phrase_confidence,
    ROUND(0.55 + MOD(ABS(FARM_FINGERPRINT(CONCAT('min', CAST(row_num AS STRING)))), 25) / 100.0, 4)
      AS min_phrase_confidence,
    ROUND(0.92 + MOD(ABS(FARM_FINGERPRINT(CONCAT('max', CAST(row_num AS STRING)))), 8) / 100.0, 4)
      AS max_phrase_confidence,
    180000 + MOD(ABS(FARM_FINGERPRINT(CONCAT('dur', CAST(row_num AS STRING)))), 720000)
      AS total_phrase_duration_ms,
    40 + MOD(ABS(FARM_FINGERPRINT(CONCAT('ph', CAST(row_num AS STRING)))), 120)
      AS phrase_count
  FROM numbered
)
SELECT
  transcript_key,
  conversation_id,
  session_id,
  transcript_start_utc,
  transcript_text,
  avg_phrase_confidence,
  LEAST(min_phrase_confidence, avg_phrase_confidence) AS min_phrase_confidence,
  GREATEST(max_phrase_confidence, avg_phrase_confidence) AS max_phrase_confidence,
  transcript_start_utc AS first_phrase_start_utc,
  DATETIME_ADD(
    transcript_start_utc,
    INTERVAL CAST(total_phrase_duration_ms / 1000 AS INT64) SECOND
  ) AS end_phrase_start_utc,
  total_phrase_duration_ms,
  phrase_count,
  TO_HEX(SHA256(transcript_text)) AS p_hdiff,
  CURRENT_DATETIME('UTC') AS p_ldts
FROM enriched
WHERE row_num <= 1000;

-- -----------------------------------------------------------------------------
-- 5) Validation
-- -----------------------------------------------------------------------------
-- Expected: 1000 rows
-- SELECT COUNT(*) AS row_count FROM `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`;

-- Wait for autonomous embeddings before AI.SEARCH (status should become NULL / empty when ready)
-- SELECT
--   COUNTIF(transcript_embedding.status IS NULL OR transcript_embedding.status = '') AS ready,
--   COUNTIF(transcript_embedding.status IS NOT NULL AND transcript_embedding.status != '') AS pending_or_error,
--   COUNT(*) AS total
-- FROM `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F`;

-- =============================================================================
-- OPTIONAL VARIANT: pure AI generation for all 1000 rows (slower / higher cost)
-- Uncomment and run instead of steps 3-4 if you prefer fully unique AI transcripts.
-- =============================================================================
/*
CREATE OR REPLACE TABLE `YOUR_PROJECT.YOUR_DATASET.CALL_TRANSCRIPTIONS_DEMO_F` AS
WITH
params AS (
  SELECT n AS row_num
  FROM UNNEST(GENERATE_ARRAY(1, 1000)) AS n
),
seeded AS (
  SELECT
    p.row_num,
    s.scenario_id,
    s.scenario_key,
    s.theme,
    s.brief,
    v.product,
    v.customer_type,
    v.region,
    v.lifetime_segment
  FROM params AS p
  JOIN `YOUR_PROJECT.YOUR_DATASET._voc_scenario_seeds` AS s
    ON s.scenario_id = MOD(p.row_num - 1, 50) + 1
  JOIN `YOUR_PROJECT.YOUR_DATASET._voc_variation_dims` AS v
    ON v.variant_id = DIV(p.row_num - 1, 50)
),
generated AS (
  SELECT
    seeded.*,
    AI.GENERATE(
      CONCAT(
        'Synthetic anonymized Swedish telecom CS transcript. ',
        'Theme=', theme, '; scenario=', scenario_key, '; brief=', brief,
        '; product=', product, '; customer_type=', customer_type,
        '; region=', region, '; lifetime=', lifetime_segment,
        '. No PII. 12-20 turns Kund/Agent. Output transcript only.'
      ),
      endpoint => 'gemini-2.5-flash',
      output_schema => 'transcript_text STRING'
    ).transcript_text AS transcript_text
  FROM seeded
)
SELECT
  FORMAT('TRK-%s', LPAD(CAST(row_num AS STRING), 6, '0')) AS transcript_key,
  FORMAT('CONV-%s', SUBSTR(TO_HEX(SHA256(CAST(row_num AS STRING))), 1, 16)) AS conversation_id,
  FORMAT('SESS-%s', SUBSTR(TO_HEX(SHA256(CONCAT('s', CAST(row_num AS STRING)))), 1, 16)) AS session_id,
  DATETIME_SUB(CURRENT_DATETIME('UTC'), INTERVAL MOD(row_num, 390) DAY) AS transcript_start_utc,
  transcript_text,
  0.90 AS avg_phrase_confidence,
  0.70 AS min_phrase_confidence,
  0.98 AS max_phrase_confidence,
  DATETIME_SUB(CURRENT_DATETIME('UTC'), INTERVAL MOD(row_num, 390) DAY) AS first_phrase_start_utc,
  DATETIME_SUB(CURRENT_DATETIME('UTC'), INTERVAL MOD(row_num, 390) DAY)
    + INTERVAL 8 MINUTE AS end_phrase_start_utc,
  480000 AS total_phrase_duration_ms,
  80 AS phrase_count,
  TO_HEX(SHA256(transcript_text)) AS p_hdiff,
  CURRENT_DATETIME('UTC') AS p_ldts,
  CAST(NULL AS STRUCT<result ARRAY<FLOAT64>, status STRING>) AS transcript_embedding
FROM generated;
-- Then ALTER TABLE to add GENERATED ALWAYS embedding column if creating via CTAS without it.
*/
