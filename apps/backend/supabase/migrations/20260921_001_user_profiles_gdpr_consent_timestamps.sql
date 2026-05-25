-- GDPR Art 6 + Art 9 consent timestamps on user_profiles.
--
-- Background: audit/gdpr (2026-05-25) flagged two missing
-- consent capture points:
--
--   * Coach chat sends health data (DOB + HR zones + recent runs)
--     to Anthropic, a US-based sub-processor. Art 6(1)(a) requires
--     an affirmative consent act before the first dispatch; opening
--     /coach is not an affirmative act.
--   * Gender + date_of_birth are special-category data under Art 9
--     (gender + DOB combined are health-adjacent). Art 9(2)(a)
--     requires explicit consent at the point of collection — the
--     Preferences page currently saves them with no consent ticker.
--
-- Two nullable timestamptz columns capture the consent grant
-- timestamp. NULL means "consent not yet given"; the UI gates the
-- corresponding surface until the user signs the checkbox.
--
-- Health-data consent withdrawal: the UI writes NULL back into
-- health_data_consent_at AND nulls gender + date_of_birth in the
-- same UPDATE so the data subject's withdrawal of consent under
-- Art 7(3) is honoured atomically.

alter table user_profiles
  add column coach_consent_at timestamptz null;

alter table user_profiles
  add column health_data_consent_at timestamptz null;

comment on column user_profiles.coach_consent_at is
  'GDPR Art 6(1)(a) consent timestamp for sending health-adjacent '
  'data (DOB, HR zones, runs window) to the AI Coach Anthropic '
  'sub-processor. NULL means consent not yet given — the /coach '
  'page must show a first-use disclosure before any chat request '
  'fires. See audit/gdpr (2026-05-25).';

comment on column user_profiles.health_data_consent_at is
  'GDPR Art 9(2)(a) explicit-consent timestamp for collecting '
  'gender + date_of_birth (special-category health-adjacent data). '
  'NULL means consent not yet given — the Preferences page must '
  'require an explicit checkbox tick before persisting either '
  'field. Withdrawal nulls this column and both fields atomically. '
  'See audit/gdpr (2026-05-25).';
