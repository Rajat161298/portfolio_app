from flask import Flask, request, jsonify
from flask_cors import CORS
import csv
import io
import math
import os
from collections import defaultdict
import numpy as np
import pandas as pd
import datetime
import yfinance as yf
from scipy.optimize import minimize

app = Flask(__name__)
CORS(app)

# --- Config / paths ---
MAP_PATH = os.environ.get('MAPPING_CSV', 'mapping.csv')  # optional mapping file for holdings mapping
NIFTY_CSV = os.path.join(os.path.dirname(__file__), 'nifty_100_full.csv')  # universe metadata for optimizer

# --- In-memory mappings loaded at startup (for Feature 1) ---
_sector_map = {}
_class_map = {}

def load_mapping_file(path=MAP_PATH):
    global _sector_map, _class_map
    _sector_map = {}
    _class_map = {}
    if not os.path.exists(path):
        app.logger.warning(f"Mapping file not found at {path}. All tickers will map to 'Other'.")
        return
    with open(path, 'r', encoding='utf-8') as f:
        reader = list(csv.reader(f))
        start = 0
        if reader and any(h.lower() in ['ticker', 'symbol'] for h in reader[0]):
            start = 1
        for i in range(start, len(reader)):
            row = reader[i]
            if not row or len(row) < 1:
                continue
            ticker = row[0].strip()
            sector = row[1].strip() if len(row) > 1 and row[1].strip() != '' else 'Other'
            cls = row[2].strip() if len(row) > 2 and row[2].strip() != '' else 'Other'
            _sector_map[ticker] = sector
            _class_map[ticker] = cls
    app.logger.info(f"Loaded {_sector_map.__len__()} tickers from mapping file {path}")

# load at startup (no-op if file absent)
load_mapping_file()

# -------------------------
# Feature 1: Current Holdings Analyzer (Updated)
# -------------------------

def parse_current_holdings_csv(text):
    """
    Expect CSV rows: Ticker, EntryDate, EntryPrice, Quantity (header optional). 
    Returns list of holdings with entry information.
    """
    reader = list(csv.reader(io.StringIO(text)))
    if not reader:
        return []

    # detect header
    start = 0
    hdr = reader[0]
    if len(hdr) >= 3 and any(h.lower() in ['ticker', 'symbol', 'entry', 'date', 'price', 'quantity'] for h in hdr):
        start = 1

    holdings = []
    for i in range(start, len(reader)):
        row = reader[i]
        if not row or len(row) < 3:
            continue
        
        ticker = row[0].strip()
        entry_date = row[1].strip()
        
        try:
            entry_price = float(row[2])
        except:
            entry_price = 0.0
            
        try:
            quantity = float(row[3]) if len(row) > 3 else 1.0
        except:
            quantity = 1.0
            
        holdings.append({
            'ticker': ticker,
            'entry_date': entry_date,
            'entry_price': entry_price,
            'quantity': quantity
        })
    
    return holdings

def get_current_prices(tickers):
    """Get current prices for list of tickers using Yahoo Finance"""
    try:
        # Remove duplicates and filter out empty tickers
        unique_tickers = list(set([t for t in tickers if t.strip()]))
        if not unique_tickers:
            return {}
            
        # Download current data (last 5 days to ensure we get latest price)
        end_date = datetime.date.today()
        start_date = end_date - datetime.timedelta(days=5)
        
        data = yf.download(unique_tickers, start=start_date, end=end_date, progress=False)
        
        if data.empty:
            return {}
            
        # Get the most recent closing price
        if 'Adj Close' in data.columns:
            if len(unique_tickers) == 1:
                # Single ticker case
                latest_price = data['Adj Close'].dropna().iloc[-1] if not data['Adj Close'].dropna().empty else 0.0
                return {unique_tickers[0]: float(latest_price)}
            else:
                # Multiple tickers case
                current_prices = {}
                for ticker in unique_tickers:
                    try:
                        if ticker in data['Adj Close'].columns:
                            price_series = data['Adj Close'][ticker].dropna()
                            if not price_series.empty:
                                current_prices[ticker] = float(price_series.iloc[-1])
                            else:
                                current_prices[ticker] = 0.0
                        else:
                            current_prices[ticker] = 0.0
                    except:
                        current_prices[ticker] = 0.0
                return current_prices
        else:
            return {}
            
    except Exception as e:
        app.logger.error(f"Error fetching current prices: {e}")
        return {}

def calculate_holdings_performance(holdings, current_prices, sector_map, class_map):
    """Calculate performance metrics for current holdings"""
    
    portfolio_data = []
    total_invested = 0.0
    total_current_value = 0.0
    
    # Calculate individual stock performance
    for holding in holdings:
        ticker = holding['ticker']
        entry_price = holding['entry_price']
        quantity = holding['quantity']
        current_price = current_prices.get(ticker, 0.0)
        
        if current_price > 0 and entry_price > 0:
            invested_amount = entry_price * quantity
            current_value = current_price * quantity
            gain_loss = current_value - invested_amount
            gain_loss_pct = (gain_loss / invested_amount) * 100 if invested_amount > 0 else 0.0
            
            portfolio_data.append({
                'ticker': ticker,
                'entry_price': entry_price,
                'current_price': current_price,
                'quantity': quantity,
                'invested_amount': invested_amount,
                'current_value': current_value,
                'gain_loss': gain_loss,
                'gain_loss_pct': gain_loss_pct,
                'sector': sector_map.get(ticker, 'Other'),
                'asset_class': class_map.get(ticker, 'Other')
            })
            
            total_invested += invested_amount
            total_current_value += current_value
    
    # Calculate portfolio-level metrics
    total_gain_loss = total_current_value - total_invested
    total_return_pct = (total_gain_loss / total_invested) * 100 if total_invested > 0 else 0.0
    
    # Sort stocks by performance
    portfolio_data.sort(key=lambda x: x['gain_loss_pct'], reverse=True)
    
    # Top gainers and losers
    top_gainers = [(stock['ticker'], stock['gain_loss_pct']/100) for stock in portfolio_data[:5] if stock['gain_loss_pct'] > 0]
    top_losers = [(stock['ticker'], stock['gain_loss_pct']/100) for stock in portfolio_data[-5:] if stock['gain_loss_pct'] < 0]
    top_losers.reverse()  # Show worst performers first
    
    # Calculate sector exposure (by current value)
    sector_exposure = defaultdict(float)
    class_exposure = defaultdict(float)
    
    for stock in portfolio_data:
        if total_current_value > 0:
            sector_weight = stock['current_value'] / total_current_value
            class_weight = stock['current_value'] / total_current_value
            
            sector_exposure[stock['sector']] += sector_weight
            class_exposure[stock['asset_class']] += class_weight
    
    return {
        'portfolio_data': portfolio_data,
        'total_invested': total_invested,
        'total_current_value': total_current_value,
        'total_gain_loss': total_gain_loss,
        'total_return_pct': total_return_pct,
        'top_gainers': top_gainers,
        'top_losers': top_losers,
        'sector_exposure': dict(sector_exposure),
        'asset_allocation': dict(class_exposure)
    }

@app.route('/upload', methods=['POST'])
def upload():
    """Upload current holdings CSV and get real-time analytics"""
    if 'file' not in request.files:
        return 'No holdings file part (key "file")', 400

    f_hold = request.files['file']
    holdings_text = f_hold.read().decode('utf-8')

    try:
        holdings = parse_current_holdings_csv(holdings_text)
        if not holdings:
            return 'No valid holdings found in CSV', 400
            
        # Get list of tickers
        tickers = [h['ticker'] for h in holdings]
        
        # Fetch current prices from Yahoo Finance
        current_prices = get_current_prices(tickers)
        
        if not current_prices:
            return 'Unable to fetch current prices from Yahoo Finance', 500
        
        # Use server-side mapping loaded at startup
        sector_map = _sector_map
        class_map = _class_map
        
        # Calculate performance analytics
        analytics = calculate_holdings_performance(holdings, current_prices, sector_map, class_map)
        
        # Find unmapped tickers
        all_tickers = set(tickers)
        unmapped = [t for t in all_tickers if t not in sector_map]
        
        # Prepare response
        response = {
            'portfolioValue': analytics['total_current_value'],
            'totalInvested': analytics['total_invested'],
            'totalGainLoss': analytics['total_gain_loss'],
            'totalReturn': analytics['total_return_pct'] / 100,  # Convert to decimal
            'topGainers': analytics['top_gainers'],
            'topLosers': analytics['top_losers'],
            'sectorExposure': analytics['sector_exposure'],
            'assetAllocation': analytics['asset_allocation'],
            'portfolioDetails': analytics['portfolio_data'],
            'unmappedTickers': unmapped,
            'pricesFetched': len(current_prices),
            'totalHoldings': len(holdings)
        }
        
        return jsonify(response)
        
    except Exception as e:
        app.logger.error(f"Error processing holdings: {e}")
        return f'Error processing holdings: {str(e)}', 500

@app.route('/reload-mapping', methods=['POST'])
def reload_mapping():
    load_mapping_file()
    return jsonify({'status': 'ok', 'loaded': len(_sector_map)})

# -------------------------
# Feature 2: Optimizer endpoints (unchanged)
# -------------------------

def load_nifty_mapping(csv_path=NIFTY_CSV):
    """Load CSV used for universe metadata (Symbol, Sector, AssetClass)."""
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Mapping CSV not found at {csv_path}")
    df = pd.read_csv(csv_path)
    df.columns = [c.strip() for c in df.columns]
    if "AssetClass" not in df.columns:
        df["AssetClass"] = "Equity"
    df["Ticker"] = df["Symbol"].astype(str).str.strip() + ".NS"
    return df

def download_adjclose(tickers, start_date, end_date):
    data = yf.download(tickers, start=start_date, end=end_date, auto_adjust=False, progress=False)["Adj Close"]
    if isinstance(data, pd.Series):
        data = data.to_frame()
    return data

def portfolio_stats(weights, returns_df, rf=0.0):
    mu = returns_df.mean().values
    Sigma = returns_df.cov().values
    port_return = float(np.dot(weights, mu) * 252)
    port_vol = float(np.sqrt(np.dot(weights.T, np.dot(Sigma, weights))) * np.sqrt(252))
    sharpe = (port_return - rf) / port_vol if port_vol > 0 else 0.0
    return port_return, port_vol, sharpe

def max_drawdown(cum_returns):
    roll_max = cum_returns.cummax()
    drawdowns = (cum_returns - roll_max) / roll_max
    return drawdowns.min()

def optimize_portfolio_weights(returns_df, objective="sharpe", rf=0.0):
    n = returns_df.shape[1]
    w0 = np.ones(n) / n
    bounds = [(0, 1)] * n
    constraints = {"type": "eq", "fun": lambda w: np.sum(w) - 1}

    def neg_sharpe(w): return -portfolio_stats(w, returns_df, rf)[2]
    def vol(w): return portfolio_stats(w, returns_df, rf)[1]
    def mdd_objective(w):
        port_returns = returns_df.dot(w)
        cum = (1 + port_returns).cumprod()
        return abs(max_drawdown(cum))

    if objective == "sharpe":
        result = minimize(neg_sharpe, w0, bounds=bounds, constraints=constraints)
    elif objective == "vol":
        result = minimize(vol, w0, bounds=bounds, constraints=constraints)
    elif objective == "mdd":
        result = minimize(mdd_objective, w0, bounds=bounds, constraints=constraints)
    else:
        raise ValueError("Unsupported objective")

    weights = result.x
    port_return, port_vol, sharpe = portfolio_stats(weights, returns_df, rf)
    return dict(zip(returns_df.columns, weights)), port_return, port_vol, sharpe

@app.route('/sectors', methods=['GET'])
def list_sectors():
    try:
        df = load_nifty_mapping()
    except FileNotFoundError:
        return jsonify([])   # empty if no mapping file provided
    return jsonify(sorted(df["Sector"].dropna().unique().tolist()))

@app.route('/asset_classes', methods=['GET'])
def list_asset_classes():
    try:
        df = load_nifty_mapping()
    except FileNotFoundError:
        return jsonify([])
    return jsonify(sorted(df["AssetClass"].dropna().unique().tolist()))

@app.route('/tickers', methods=['GET'])
def list_tickers():
    try:
        df = load_nifty_mapping()
    except FileNotFoundError:
        return jsonify([])
    return jsonify(df[["Ticker", "Symbol", "Sector", "AssetClass"]].to_dict(orient="records"))

@app.route('/optimize', methods=['POST'])
def optimize_endpoint():
    """
    Accept JSON:
    {
      "sectors": ["Sector1", ...],            # optional
      "asset_classes": ["Equity", ...],       # optional
      "num_stocks": 10,
      "objective": "sharpe"                   # sharpe | vol | mdd
    }
    """
    payload = request.get_json() or {}
    sectors = payload.get("sectors", [])
    asset_classes = payload.get("asset_classes", [])
    num_stocks = int(payload.get("num_stocks", 10))
    objective = payload.get("objective", "sharpe")

    today = datetime.date.today()
    try:
        df = load_nifty_mapping()
    except FileNotFoundError:
        return jsonify({"error": f"Universe mapping file missing at {NIFTY_CSV}"}), 400

    all_tickers = df["Ticker"].tolist()

    filtered = df.copy()
    if sectors:
        filtered = filtered[filtered["Sector"].isin(sectors)]
    if asset_classes:
        filtered = filtered[filtered["AssetClass"].isin(asset_classes)]

    tickers = filtered["Ticker"].tolist()
    if not tickers:
        tickers = all_tickers

    # --- Select top num_stocks by 6-month return ---
    lookback_start = today - pd.DateOffset(months=6)
    recent_prices = download_adjclose(tickers, lookback_start, today).dropna(how="all")

    if recent_prices.empty or recent_prices.shape[0] < 2:
        return jsonify({"error": "Not enough 6-month data to rank stocks."}), 400

    six_month_returns = recent_prices.iloc[-1] / recent_prices.iloc[0] - 1
    six_month_returns = six_month_returns.dropna().sort_values(ascending=False)
    chosen = six_month_returns.head(num_stocks).index.tolist()

    if len(chosen) < 2:
        return jsonify({"error": "Fewer than 2 valid stocks after ranking."}), 400

    # --- Optimization based on last 1 year ---
    opt_start = today - pd.DateOffset(years=1)
    prices = download_adjclose(chosen, opt_start, today).dropna(how="all")
    returns_df = prices.pct_change().dropna()

    if returns_df.shape[1] < 2:
        return jsonify({"error": "Not enough valid return series for optimization."}), 400

    weights, ann_return, ann_vol, sharpe = optimize_portfolio_weights(returns_df, objective=objective)

    # --- Benchmark comparison ---
    nifty = yf.download("^NSEI", start=today - pd.DateOffset(years=5), end=today, progress=False)["Adj Close"].dropna()
    nifty_rets = nifty.pct_change().dropna()

    port_returns = (returns_df @ np.array(list(weights.values()))).dropna()
    port_index = (1 + port_returns).cumprod()
    nifty_index = (1 + nifty_rets).cumprod()

    aligned = pd.DataFrame({"Portfolio": port_index, "Nifty": nifty_index}).dropna()

    horizons = {
        "1M": {"months": 1},
        "3M": {"months": 3},
        "6M": {"months": 6},
        "YTD": {"ytd": True},
        "1Y": {"years": 1},
    }

    results = {}
    chart_data = {}

    for h, params in horizons.items():
        def get_period(series):
            if params.get("ytd"):
                start = pd.Timestamp(datetime.date(today.year, 1, 1))
            elif "months" in params:
                start = today - pd.DateOffset(months=params["months"])
            elif "years" in params:
                start = today - pd.DateOffset(years=params["years"])
            else:
                return None
            sub = series[series.index >= pd.to_datetime(start)]
            if len(sub) < 2:
                return None
            return sub.iloc[-1] / sub.iloc[0] - 1

        results[h] = {
            "Portfolio": get_period(aligned["Portfolio"]),
            "Nifty": get_period(aligned["Nifty"]),
        }

        # series for charts
        if params.get("ytd"):
            start = pd.Timestamp(datetime.date(today.year, 1, 1))
        elif "months" in params:
            start = today - pd.DateOffset(months=params["months"])
        elif "years" in params:
            start = today - pd.DateOffset(years=params["years"])
        else:
            start = None

        if start is not None:
            sub = aligned[aligned.index >= start]
            chart_data[h] = {
                "dates": [d.strftime("%Y-%m-%d") for d in sub.index],
                "portfolio": sub["Portfolio"].tolist(),
                "nifty": sub["Nifty"].tolist(),
            }

    # Enriched weights table
    weight_table = []
    for t, w in weights.items():
        row = df[df["Ticker"] == t].iloc[0].to_dict()
        weight_table.append({
            "ticker": t,
            "symbol": row.get("Symbol", t),
            "sector": row.get("Sector", "Unknown"),
            "asset_class": row.get("AssetClass", "Equity"),
            "weight": w
        })

    return jsonify({
        "selected_stocks": chosen,
        "weights": weights,
        "weight_table": weight_table,
        "metrics": {
            "annualized_return": ann_return,
            "annualized_volatility": ann_vol,
            "sharpe": sharpe,
        },
        "benchmark_returns": results,
        "chart_data": chart_data
    })

if __name__ == '__main__':
    # Run Flask app (single backend for both features)
    app.run(host='0.0.0.0', port=5000, debug=True)