-- ==============================================================================
-- Perplex Alpha - Trading Data Analysis Queries
-- 
-- This file contains advanced SQL queries used to analyze the performance, 
-- risk metrics, and agent behaviors of the Perplex Alpha trading platform.
-- Designed for SQLite.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. AGENT PERFORMANCE & CONFIDENCE ANALYSIS (Using CTEs and Aggregations)
-- Objective: Analyze which LLM agent provides the most confident signals 
-- and how often their signals are approved by the risk engine.
-- ------------------------------------------------------------------------------
WITH AgentStats AS (
    SELECT 
        source_agent,
        COUNT(id) as total_signals,
        AVG(confidence) as avg_confidence,
        SUM(CASE WHEN risk_approved = 1 THEN 1 ELSE 0 END) as approved_signals
    FROM signals
    GROUP BY source_agent
)
SELECT 
    source_agent,
    total_signals,
    ROUND(avg_confidence, 2) AS average_confidence,
    approved_signals,
    ROUND(CAST(approved_signals AS FLOAT) / total_signals * 100, 2) AS approval_rate_pct
FROM AgentStats
ORDER BY approval_rate_pct DESC;


-- ------------------------------------------------------------------------------
-- 2. CUMULATIVE PORTFOLIO PNL (Using Window Functions)
-- Objective: Calculate the running total of realized PnL over time to visualize 
-- the portfolio's equity curve.
-- ------------------------------------------------------------------------------
SELECT 
    opened_at,
    symbol,
    realized_pnl,
    SUM(realized_pnl) OVER (
        ORDER BY opened_at 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_realized_pnl
FROM positions
WHERE realized_pnl != 0
ORDER BY opened_at;


-- ------------------------------------------------------------------------------
-- 3. TRADE PROFITABILITY BY ASSET (Using Joins and Date Functions)
-- Objective: Identify the most and least profitable assets traded, including 
-- the total commissions paid per asset.
-- ------------------------------------------------------------------------------
SELECT 
    t.symbol,
    COUNT(t.id) as total_trades,
    SUM(t.quantity) as total_volume,
    SUM(t.commission) as total_commissions_paid,
    SUM(p.realized_pnl) as net_realized_pnl
FROM trades t
LEFT JOIN positions p ON t.symbol = p.symbol
GROUP BY t.symbol
HAVING total_trades > 5
ORDER BY net_realized_pnl DESC;


-- ------------------------------------------------------------------------------
-- 4. RISK MANAGEMENT VETO ANALYSIS (Using Text Pattern Matching / CASE)
-- Objective: Categorize the reasons why the Refiner agent vetoed trades 
-- to understand the most common risk breaches.
-- ------------------------------------------------------------------------------
SELECT 
    symbol,
    strategy,
    confidence,
    CASE 
        WHEN risk_rejection_reason LIKE '%volatility%' THEN 'High Volatility'
        WHEN risk_rejection_reason LIKE '%drawdown%' THEN 'Drawdown Limit'
        WHEN risk_rejection_reason LIKE '%exposure%' THEN 'Max Exposure Reached'
        ELSE 'Other/Systematic'
    END AS rejection_category,
    COUNT(*) as rejection_count
FROM signals
WHERE risk_approved = 0
GROUP BY symbol, strategy, rejection_category
ORDER BY rejection_count DESC;


-- ------------------------------------------------------------------------------
-- 5. AGENT LATENCY vs TOKEN USAGE (Performance Optimization)
-- Objective: Check the correlation between the amount of data processed (tokens)
-- and the latency of the LLM responses to find optimization bottlenecks.
-- ------------------------------------------------------------------------------
SELECT 
    agent_name,
    model_name,
    AVG(prompt_tokens + completion_tokens) AS avg_total_tokens,
    AVG(latency_ms) AS avg_latency_ms,
    MAX(latency_ms) AS peak_latency_ms,
    (AVG(latency_ms) / NULLIF(AVG(prompt_tokens + completion_tokens), 0)) AS ms_per_token
FROM agent_outputs
GROUP BY agent_name, model_name
ORDER BY avg_latency_ms DESC;
