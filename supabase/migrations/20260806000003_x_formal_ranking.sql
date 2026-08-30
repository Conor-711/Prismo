create table if not exists sv_investor_score (
    investor_id text primary key,
    source text not null,
    name text,
    handle text,
    language text,
    sv double precision,
    raw_z double precision,
    confidence text,
    n_eff double precision,
    settled_calls integer,
    active_days integer,
    covered_tickers integer,
    top_tickers_json text,
    top_narratives_json text,
    platform_scores_json text,
    horizon_scores_json text,
    narrative_scores_json text,
    ticker_scores_json text,
    concentration_json text,
    rationale_zh text,
    rationale_en text,
    updated_at text,
    ability_scores_json text
);

create index if not exists ix_sv_investor_score_source
    on sv_investor_score (source);

create index if not exists ix_sv_investor_score_x_formal
    on sv_investor_score (source, settled_calls, n_eff, sv desc);
