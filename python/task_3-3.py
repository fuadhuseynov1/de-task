import pandas as pd


def load_daily(df, day):

    df['event_time'] = pd.to_datetime(df['event_time'], errors='coerce', utc=True)
    df_day = df[df['event_time'].dt.strftime('%Y-%m-%d') == day].copy()

    if df_day.empty:
        return pd.DataFrame(columns=['key', 'revenue'])
    
    cleaned_strings = (
        df_day["revenue_usd"].astype(str).str.replace(",", ".").str.strip()
    )

    convert_dt = pd.to_numeric(cleaned_strings, errors="coerce") #forcing unparseable text/empty values to NaN
    df_day['revenue_usd'] = convert_dt.fillna(0.0)

    # Create the key column explicitly before grouping
    df_day['key'] = df_day['app_id'].astype(str) + '-' + df_day['media_source'].astype(str)

    df_result = (
        df_day.groupby('key')['revenue_usd']
        .sum()
        .reset_index(name='revenue')
        .sort_values(by='revenue', ascending=False)
    )

    return df_result



if __name__ == "__main__":
    file_path = 'data/events_raw.csv'
    day = '2026-09-01'
    
    try:
        print(f"Loading data from {file_path}...")
        df_raw = pd.read_csv(file_path)
    except Exception as e:
        print(f"Failed to read CSV: {e}")
        df_raw = pd.DataFrame()

    if not df_raw.empty:
        df_result = load_daily(df_raw, day)

    print(df_result)