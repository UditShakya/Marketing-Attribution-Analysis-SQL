# Marketing-Attribution-Analysis-SQL
A multi-channel marketing attribution project using SQL Server and Excel to identify conversion drivers across the customer journey.
# Multi-Channel Marketing Attribution Analysis

## Project Overview
This project analyzes 10,000+ marketing touchpoints to determine the effectiveness of different channels (Social Media, Email, Display Ads, etc.) using First-Touch and Last-Touch attribution models.

## Technologies Used
* **SQL Server (T-SQL):** Data transformation and Window Functions.
* **Excel:** Data visualization and dashboarding.

## Key Insights
* **Display Ads** were identified as the primary 'Discovery' channel, initiating the most customer journeys.
* **Referral Traffic** acted as the strongest 'Closer,' with the highest Last-Touch conversion credit.
* **Business Recommendation:** Reallocate 15% of the budget from Search Ads to Display Ads to increase top-of-funnel growth.

## How to Run the SQL
1. Import `multi_touch_attribution_data.csv` into SQL Server.
2. Execute the script found in `/SQL_Scripts/attribution_logic.sql`.
