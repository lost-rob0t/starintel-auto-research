%% Source contracts checked 2026-09-16; commercial demand remains unverified.
source_contract(sam_opportunities, official_gsa_public_api, api_key_and_date_window).
source_contract(usaspending_awards, official_usaspending_api, no_current_authorization_requirement).
source_contract(sec_edgar, official_sec_data_api, ten_requests_per_second_fair_access_ceiling).
candidate_actor(federal_opportunity, 1, procurement).
candidate_actor(federal_award_context, 2, contract).
candidate_actor(sec_filing_change, 3, financial_observation).
research_state(commercial_public_data_actors, pending_human_approval).
commercial_hypothesis(federal_opportunity, buyer_willingness_to_pay_unverified).
