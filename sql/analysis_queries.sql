-- =====================================================
-- MINING OPERATIONS ANALYSIS - SQL QUERIES
-- Western Australia Mining Performance Dashboard
-- Author: Flavio Coltellacci
-- Date: January 2026
-- =====================================================

-- =====================================================
-- QUERY 1: Overall Site Performance Ranking
-- Ranks sites by production efficiency, safety, and cost
-- =====================================================

SELECT 
    s.site_name,
    s.commodity,
    s.region,
    s.status,
    
    -- Production Metrics
    ROUND(AVG(p.plan_adherence_pct), 1) as avg_plan_adherence_pct,
    ROUND(SUM(p.tonnes_mined) / 1000000, 2) as total_tonnes_millions,
    ROUND(AVG(p.recovery_rate), 1) as avg_recovery_rate_pct,
    
    -- Cost Metrics
    ROUND(AVG(c.cost_per_unit), 2) as avg_cost_per_unit,
    ROUND(SUM(c.total_cost_aud) / 1000000, 2) as total_cost_millions_aud,
    
    -- Safety Metrics
    sm.trifr,
    sm.ltifr,
    
    -- Equipment Efficiency
    ROUND(AVG(e.oee_pct), 1) as avg_equipment_oee_pct,
    
    -- Overall Score (weighted composite)
    ROUND(
        (AVG(p.plan_adherence_pct) * 0.3) +
        (AVG(p.recovery_rate) * 0.2) +
        (AVG(e.oee_pct) * 0.2) +
        ((100 - sm.trifr * 10) * 0.15) +
        ((100 - (AVG(c.cost_per_unit) / s.cost_per_unit_target * 100)) * 0.15)
    , 1) as overall_performance_score

FROM mine_sites s
LEFT JOIN daily_production p ON s.site_id = p.site_id
LEFT JOIN daily_costs c ON s.site_id = c.site_id AND p.date = c.date
LEFT JOIN equipment_performance e ON s.site_id = e.site_id AND p.date = e.date
LEFT JOIN safety_metrics_summary sm ON s.site_id = sm.site_id

WHERE s.status = 'Operational'

GROUP BY s.site_id, s.site_name, s.commodity, s.region, s.status, 
         s.cost_per_unit_target, sm.trifr, sm.ltifr

ORDER BY overall_performance_score DESC;


-- =====================================================
-- QUERY 2: Equipment Downtime & Reliability Analysis
-- Identifies worst-performing equipment units
-- =====================================================

SELECT 
    e.site_id,
    s.site_name,
    e.equipment_type,
    e.equipment_id,
    e.model,
    e.autonomous,
    
    -- Availability Metrics
    COUNT(*) as days_tracked,
    ROUND(AVG(e.availability_pct), 1) as avg_availability_pct,
    ROUND(AVG(e.utilization_pct), 1) as avg_utilization_pct,
    ROUND(AVG(e.oee_pct), 1) as avg_oee_pct,
    
    -- Downtime Analysis
    ROUND(SUM(e.breakdown_hours), 1) as total_breakdown_hours,
    ROUND(SUM(e.maintenance_hours), 1) as total_maintenance_hours,
    ROUND(SUM(e.idle_hours), 1) as total_idle_hours,
    ROUND(SUM(e.breakdown_hours) + SUM(e.maintenance_hours), 1) as total_downtime_hours,
    
    -- Cost Impact
    ROUND(SUM(e.maintenance_cost_aud) / 1000, 1) as total_maintenance_cost_thousands_aud,
    ROUND(SUM(e.fuel_consumed_liters), 0) as total_fuel_liters,
    
    -- Performance vs Target
    CASE 
        WHEN AVG(e.oee_pct) >= 80 THEN 'Excellent'
        WHEN AVG(e.oee_pct) >= 70 THEN 'Good'
        WHEN AVG(e.oee_pct) >= 60 THEN 'Needs Improvement'
        ELSE 'Critical'
    END as performance_category

FROM equipment_performance e
JOIN mine_sites s ON e.site_id = s.site_id

WHERE s.status = 'Operational'

GROUP BY e.site_id, s.site_name, e.equipment_type, e.equipment_id, e.model, e.autonomous

ORDER BY total_downtime_hours DESC

LIMIT 20;


-- =====================================================
-- QUERY 3: Monthly Production Trends & Seasonality
-- Shows production patterns, cyclone impacts, grade trends
-- =====================================================

SELECT 
    strftime('%Y-%m', date) as month,
    site_name,
    commodity,
    
    -- Production Volumes
    COUNT(*) as operating_days,
    ROUND(SUM(tonnes_mined) / 1000, 1) as total_tonnes_thousands,
    ROUND(AVG(tonnes_mined), 0) as avg_daily_tonnes,
    
    -- Efficiency Metrics
    ROUND(AVG(plan_adherence_pct), 1) as avg_plan_adherence_pct,
    ROUND(AVG(head_grade), 2) as avg_head_grade,
    ROUND(AVG(recovery_rate), 1) as avg_recovery_rate_pct,
    
    -- Operational Challenges
    ROUND(SUM(weather_delay_hours), 1) as total_weather_delay_hours,
    ROUND(SUM(downtime_hours), 1) as total_downtime_hours,
    ROUND(AVG(operational_hours), 1) as avg_operational_hours_per_day,
    
    -- Production Lost
    ROUND(
        SUM(CASE WHEN plan_adherence_pct < 90 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 
        1
    ) as pct_days_below_target

FROM daily_production

WHERE status = 'Operational'

GROUP BY strftime('%Y-%m', date), site_name, commodity

ORDER BY month, site_name;


-- =====================================================
-- QUERY 4: Safety Incident Patterns & Root Cause Analysis
-- Identifies high-risk sites, incident types, and causes
-- =====================================================

SELECT 
    s.site_name,
    s.commodity,
    s.workforce_count,
    
    -- Incident Counts by Type
    COUNT(*) as total_incidents,
    SUM(CASE WHEN incident_type = 'Lost Time Injury (LTI)' THEN 1 ELSE 0 END) as lti_count,
    SUM(CASE WHEN incident_type = 'Medical Treatment Injury (MTI)' THEN 1 ELSE 0 END) as mti_count,
    SUM(CASE WHEN incident_type = 'First Aid Injury (FAI)' THEN 1 ELSE 0 END) as fai_count,
    SUM(CASE WHEN incident_type = 'Potential Significant Incident (PSI)' THEN 1 ELSE 0 END) as psi_count,
    SUM(CASE WHEN incident_type = 'Near Miss' THEN 1 ELSE 0 END) as near_miss_count,
    
    -- Severity Analysis
    SUM(days_lost) as total_days_lost,
    ROUND(AVG(days_lost), 1) as avg_days_lost_per_lti,
    
    -- Root Cause Breakdown
    SUM(CASE WHEN root_cause = 'Human Error' THEN 1 ELSE 0 END) as human_error_count,
    SUM(CASE WHEN root_cause = 'Equipment Failure' THEN 1 ELSE 0 END) as equipment_failure_count,
    SUM(CASE WHEN root_cause = 'Procedural Gap' THEN 1 ELSE 0 END) as procedural_gap_count,
    
    -- Safety Performance Metrics
    sm.trifr,
    sm.ltifr,
    
    -- Risk Category
    CASE 
        WHEN sm.trifr < 3.0 THEN 'Tier 1 (World Class)'
        WHEN sm.trifr < 6.0 THEN 'Industry Average'
        ELSE 'Needs Improvement'
    END as safety_performance_category

FROM safety_incidents si
JOIN mine_sites s ON si.site_id = s.site_id
JOIN safety_metrics_summary sm ON si.site_id = sm.site_id

GROUP BY s.site_name, s.commodity, s.workforce_count, sm.trifr, sm.ltifr

ORDER BY sm.trifr DESC;


-- =====================================================
-- QUERY 5: Cost Efficiency Analysis & Optimization
-- Identifies cost drivers and improvement opportunities
-- =====================================================

SELECT 
    s.site_name,
    s.commodity,
    
    -- Cost Breakdown
    ROUND(SUM(c.labor_cost_aud) / 1000000, 2) as labor_cost_millions,
    ROUND(SUM(c.equipment_cost_aud) / 1000000, 2) as equipment_cost_millions,
    ROUND(SUM(c.fuel_cost_aud) / 1000000, 2) as fuel_cost_millions,
    ROUND(SUM(c.maintenance_cost_aud) / 1000000, 2) as maintenance_cost_millions,
    ROUND(SUM(c.total_cost_aud) / 1000000, 2) as total_cost_millions,
    
    -- Cost Percentages
    ROUND(SUM(c.labor_cost_aud) * 100.0 / SUM(c.total_cost_aud), 1) as labor_pct,
    ROUND(SUM(c.equipment_cost_aud) * 100.0 / SUM(c.total_cost_aud), 1) as equipment_pct,
    ROUND(SUM(c.fuel_cost_aud) * 100.0 / SUM(c.total_cost_aud), 1) as fuel_pct,
    
    -- Unit Economics
    ROUND(AVG(c.cost_per_unit), 2) as avg_cost_per_unit,
    s.cost_per_unit_target as target_cost_per_unit,
    ROUND(
        ((AVG(c.cost_per_unit) - s.cost_per_unit_target) / s.cost_per_unit_target) * 100, 
        1
    ) as cost_variance_pct,
    
    -- Production Efficiency Impact
    ROUND(SUM(p.tonnes_mined) / 1000000, 2) as total_tonnes_millions,
    ROUND(
        SUM(c.total_cost_aud) / SUM(p.tonnes_mined), 
        2
    ) as actual_cost_per_tonne,
    
    -- Cost Efficiency Rating
    CASE 
        WHEN AVG(c.cost_per_unit) <= s.cost_per_unit_target THEN 'On Target'
        WHEN AVG(c.cost_per_unit) <= s.cost_per_unit_target * 1.1 THEN 'Acceptable'
        ELSE 'Over Budget'
    END as cost_performance

FROM daily_costs c
JOIN mine_sites s ON c.site_id = s.site_id
LEFT JOIN daily_production p ON c.site_id = p.site_id AND c.date = p.date

WHERE s.status = 'Operational'

GROUP BY s.site_name, s.commodity, s.cost_per_unit_target

ORDER BY cost_variance_pct DESC;


-- =====================================================
-- END OF QUERIES
-- =====================================================
