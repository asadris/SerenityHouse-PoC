# Serenity House Synthetic Data Generator

This repository contains a fully featured synthetic data generation system for a transitional housing program. The generator produces realistic resident behavior, rent compliance patterns, incidents, drug tests, employment snapshots, financial assistance, and fundraising activity.

## Features

### ✔ Behavioral Clustering (In-Memory Only)
Residents are assigned to one of three behavioral clusters:
- **Reliable (50%)**
- **Struggling (25%)**
- **Chronic (25%)**

Clusters influence rent behavior, compliance, employment, and outcomes but are **not stored** in the database.

### ✔ Realistic Rent Simulation
- Weekly rent charges  
- Cluster-driven payment probability  
- On-time vs late payments  
- Full vs partial payments  
- Waivers and financial assistance  

### ✔ Compliance & Employment Modeling
- Drug tests  
- Incidents  
- Employment snapshots  
- Case management and service encounters  

### ✔ Outcomes
- Successful vs unsuccessful exits  
- Destination types  
- Employment at exit  

### ✔ Fundraising & Donors
- Donor profiles  
- Fundraising events  
- Donations  

### ✔ SQL Views for Analytics
- `vw_StayFinancialSummary`  
- `vw_InferredCluster`  
- `vw_InferredRiskScore`  

### ✔ No Schema Changes Required
All behavioral logic is internal to the generator.

## Requirements
- Python 3.10+
- pyodbc
- SQL Server with the Serenity House schema installed

## Running the Generator
```bash
python generate_serenity_data.py