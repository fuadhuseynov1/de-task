import argparse
from pathlib import Path
import pandas as pd
import pycountry


def read_data_csv(path):
    return pd.read_csv(path)

def normalize_country(name):
    if pd.isna(name):
        return "XX"
    name_clean = str(name).strip()
    try:
        country = pycountry.countries.lookup(name_clean)
        return country.alpha_2
    except LookupError:
        return "XX"



def transform_data(df, since_date):
    """Processes raw DataFrame, applies filtering, deduplication, and quarantining."""
    rows_in = len(df)

    # 1. Identify malformed / quarantined rows
    parsed_event_time = pd.to_datetime(df['event_time'], errors='coerce', utc=True)
    parsed_ingested_at = pd.to_datetime(df['ingested_at'], errors='coerce', utc=True)

    is_malformed = (
        df['event_id'].isna() |
        parsed_event_time.isna() |
        parsed_ingested_at.isna()
    )

    df_quarantine = df[is_malformed].copy()
    df_clean = df[~is_malformed].copy()

    # Apply parsed timestamps to clean set
    df_clean['event_time'] = parsed_event_time[~is_malformed] #serve as the partition key
    df_clean['ingested_at'] = parsed_ingested_at[~is_malformed]

    # 2. Filter by --since date (on event_time) if specified
    if since_date:
        since_dt = pd.to_datetime(since_date, utc=True)
        date_mask = df_clean['event_time'] >= since_dt
        # Move out-of-range rows away from processing (or ignore)
        df_clean = df_clean[date_mask]

    # 3. Clean revenue_usd
    cleaned_revenue_strings = (
        df_clean["revenue_usd"].astype(str).str.replace(",", ".").str.strip()
    )
    df_clean['revenue_usd'] = pd.to_numeric(cleaned_revenue_strings, errors="coerce").fillna(0.0)

    # 4. Normalize country
    df_clean["country"] = df_clean["country"].apply(normalize_country)

    # 5. Drop test rows
    df_clean = df_clean[df_clean['is_test'] == False]

    # 6. Track and resolve duplicates
    rows_before_dedup = len(df_clean)

    df_clean = df_clean.sort_values(by = ['event_id', 'ingested_at'], ascending = [True, True])
    df_clean = df_clean.drop_duplicates(subset=['event_id'], keep='last')

    duplicates_removed = rows_before_dedup - len(df_clean)

    # 7. Add event_date for Hive partitioning
    df_clean['event_date'] = df_clean['event_time'].dt.strftime('%Y-%m-%d')

    stats = {
        "rows_in": rows_in,
        "rows_out": len(df_clean),
        "duplicates_removed": duplicates_removed,
        "rows_quarantined": len(df_quarantine)
    }

    return df_clean, df_quarantine, stats


def main():
    parser = argparse.ArgumentParser(description="Clean and partition event data.")
    parser.add_argument("--input", required=True, type=Path, help="Input directory or specific CSV file path")
    parser.add_argument("--output", required=True, type=Path, help="Output base directory")
    parser.add_argument("--since", type=str, default=None, help="Filter events starting from date (YYYY-MM-DD)")
    
    args = parser.parse_args()
    input_path = args.input

    # Target event files specifically
    if input_path.is_dir():
        # Matches events_raw.csv, events_raw_incremental.csv, etc.
        csv_files = sorted(list(input_path.glob("events_raw*.csv")))
        if not csv_files:
            raise FileNotFoundError(f"No 'events_raw*.csv' files found in directory: {input_path}")
        print(f"Ingesting event files: {[f.name for f in csv_files]}")
        df_raw = pd.concat([pd.read_csv(f) for f in csv_files], ignore_index=True)
    elif input_path.is_file():
        df_raw = pd.read_csv(input_path)
    else:
        raise FileNotFoundError(f"Specified input path does not exist: {input_path}")

    # Process events and output partitioned parquet
    df_clean, df_quarantine, stats = transform_data(df_raw, since_date=args.since)

    clean_out_dir = args.output / "events"
    quarantine_out_dir = args.output / "quarantine"
    
    clean_out_dir.mkdir(parents=True, exist_ok=True)
    quarantine_out_dir.mkdir(parents=True, exist_ok=True)

    # Write Hive-partitioned parquet files safely
    df_clean.to_parquet(
        clean_out_dir,
        engine='pyarrow',
        partition_cols=['event_date'],
        index=False,
        existing_data_behavior='delete_matching'
    )

    df_quarantine.to_csv(quarantine_out_dir / "quarantined_events.csv", index=False)

    print(
        f"rows in: {stats['rows_in']}, "
        f"rows out: {stats['rows_out']}, "
        f"duplicates removed: {stats['duplicates_removed']}, "
        f"rows quarantined: {stats['rows_quarantined']}"
    )





if __name__ == "__main__":
    main()