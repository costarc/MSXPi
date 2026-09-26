# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

from __future__ import annotations


# Standard library imports
import time
import logging
import threading

# Third-party imports
import requests

logger = logging.getLogger('msxpi')

from msxpi_const import (
    CommandResult,
    HTTP_TIMEOUT,
)
from msxpi_blocks import sendmultiblock
from msxpi_settings import getMSXPiVar


# -----------------------------
# API keys
# -----------------------------
# From msxpi.ini, like OPENAIKEY - never in this file. These were hardcoded
# here until v1.6, which put four live keys in a public repository; they have
# been revoked, and the replacements live on the Pi in
# /home/pi/msxpi/msxpi.ini, which is not in the repository. target/msxpi.ini
# lists the names with empty values.
#
# Read per call rather than once at import: `p set FINNHUBKEY ...` rewrites the
# file and updates _config, and a key set that way has to take effect without
# restarting the server.
def _api_key(name):
    return getMSXPiVar(name).strip()


RAPIDAPI_HOST_DEFAULT = "apidojo-yahoo-finance-v1.p.rapidapi.com"

DEFAULT_COOLDOWN = 60  # seconds
# Yahoo cooldown state
yahoo_cooldown_until = 0

def norm(sym):
    return sym.replace("-", "").upper()

# -----------------------------
# Provider base class
# -----------------------------
class QuoteProvider:
    name = "BASE"
    def fetch_batch(self, symbols):
        raise NotImplementedError

# -----------------------------
# Yahoo Provider
# -----------------------------
class YahooProvider(QuoteProvider):
    name = "Yahoo"
    def fetch_batch(self, symbols):
        host = _api_key("RAPIDAPIHOST") or RAPIDAPI_HOST_DEFAULT
        url = f"https://{host}/market/v2/get-quotes"
        params = {"region": "US", "symbols": ",".join(symbols)}
        headers = {"X-RapidAPI-Key": _api_key("RAPIDAPIKEY"),
                   "X-RapidAPI-Host": host}

        r = requests.get(url, headers=headers, params=params, timeout=10)
        r.raise_for_status()
        data = r.json()
        results = data.get("quoteResponse", {}).get("result", [])

        out = {}
        for item in results:
            sym = item.get("symbol")
            if sym:
                out[sym.upper()] = item
        return out

# -----------------------------
# Finnhub Provider
# -----------------------------
class FinnhubProvider(QuoteProvider):
    name = "Finnhub"
    def fetch_batch(self, symbols):
        out = {}
        for s in symbols:
            url = "https://finnhub.io/api/v1/quote"
            params = {"symbol": s, "token": _api_key("FINNHUBKEY")}
            r = requests.get(url, params=params, timeout=10)
            r.raise_for_status()
            q = r.json()
            out[s] = {
                "symbol": s,
                "regularMarketPrice": q.get("c", 0),
                "regularMarketChange": q.get("d", 0),
                "regularMarketVolume": int(q.get("v", 0))
            }
        return out
    def fetch_history(self, symbol, interval="1", range_="1d"):
        # interval: 1,5,15,30,60
        # range_: "1d","5d","1mo","3mo","6mo","1y"
        resolution = interval.replace("min", "")

        now = int(time.time())
        if range_ == "1d": start = now - 86400
        elif range_ == "5d": start = now - 5*86400
        elif range_ == "1mo": start = now - 30*86400
        else: start = now - 365*86400

        url = "https://finnhub.io/api/v1/stock/candle"
        params = {
            "symbol": symbol,
            "resolution": resolution,
            "from": start,
            "to": now,
            "token": _api_key("FINNHUBKEY")
        }

        r = requests.get(url, params=params, timeout=HTTP_TIMEOUT)
        data = r.json()

        if data.get("s") != "ok":
            return []

        candles = []
        for i in range(len(data["t"])):
            candles.append({
                "time": data["t"][i],
                "open": data["o"][i],
                "high": data["h"][i],
                "low": data["l"][i],
                "close": data["c"][i],
                "volume": data["v"][i]
            })

        return candles

# -----------------------------
# TwelveData Provider
# -----------------------------
def normalize_for_twelvedata(symbol):
    if "-USD" in symbol:
        return symbol.replace("-", "/")
    return symbol

class TwelveDataProvider(QuoteProvider):
    name = "TwelveData"
    def fetch_batch(self, symbols):
        # Convert BTC-USD → BTC/USD
        td_symbols = [normalize_for_twelvedata(s) for s in symbols]

        url = "https://api.twelvedata.com/quote"
        params = {"symbol": ",".join(td_symbols), "apikey": _api_key("TWELVEDATAKEY")}
        r = requests.get(url, params=params, timeout=10)
        r.raise_for_status()
        data = r.json()

        out = {}
        for s, td_s in zip(symbols, td_symbols):
            q = data.get(td_s)
            if not q:
                continue
            out[s] = {
                "symbol": s,
                "regularMarketPrice": float(q["close"]),
                "regularMarketChange": float(q["change"]),
                "regularMarketVolume": int(q.get("volume", 0))
            }
        return out

class CoinGeckoProvider(QuoteProvider):
    name = "CoinGecko"

    id_map = {
        "BTC-USD": "bitcoin",
        "XRP-USD": "ripple",
        "CRO-USD": "crypto-com-chain",
    }

    def fetch_batch(self, symbols):
        # Filter only symbols CoinGecko supports
        ids = []
        sym_map = {}

        for s in symbols:
            cid = self.id_map.get(s.upper())
            if cid:
                ids.append(cid)
                sym_map[cid] = s.upper()

        if not ids:
            return {}

        url = "https://api.coingecko.com/api/v3/simple/price"
        params = {
            "ids": ",".join(ids),
            "vs_currencies": "usd",
            "include_24hr_vol": "true"
        }

        try:
            r = requests.get(url, params=params, timeout=10)
            r.raise_for_status()
            data = r.json()
        except Exception as e:
            print(f"[PROVIDER] CoinGecko batch failed: {e}")
            cooldown_provider("CoinGecko", 60)
            return {}

        out = {}
        for cid, sym in sym_map.items():
            if cid in data:
                q = data[cid]
                out[sym] = {
                    "symbol": sym,
                    "regularMarketPrice": float(q["usd"]),
                    "regularMarketVolume": float(q.get("usd_24h_vol", 0)),
                    "regularMarketOpen": 0,
                    "regularMarketDayHigh": 0,
                    "regularMarketDayLow": 0,
                    "regularMarketPreviousClose": 0,
                }

        return out

    def fetch_history(self, symbol, interval="1m", range_="1d"):
        coin = symbol.split("-")[0].lower()

        url = f"https://api.coingecko.com/api/v3/coins/{coin}/market_chart"
        params = {
            "vs_currency": "usd",
            "days": "1" if range_=="1d" else "7"
        }

        r = requests.get(url, params=params, timeout=HTTP_TIMEOUT)
        data = r.json()

        candles = []
        for ts, price in data["prices"]:
            candles.append({
                "time": ts,
                "open": price,
                "high": price,
                "low": price,
                "close": price,
                "volume": 0
            })

        return candles

class StooqProvider(QuoteProvider):
    name = "Stooq"

    def fetch_history(self, symbol, interval="1d", range_="1mo"):
        # Stooq only supports daily data
        url = f"https://stooq.com/q/d/l/?s={symbol.lower()}&i=d"

        r = requests.get(url, timeout=HTTP_TIMEOUT)
        if r.status_code != 200:
            return []

        lines = r.text.strip().split("\n")
        if len(lines) < 2:
            return []

        candles = []
        for line in lines[1:]:
            date, o, h, l, c, v = line.split(",")
            candles.append({
                "time": date,
                "open": float(o),
                "high": float(h),
                "low": float(l),
                "close": float(c),
                "volume": int(v) if v.isdigit() else 0
            })

        return candles

    def convert_symbol(self, s):
        s = s.upper()
        if s.endswith(".L"):
            return s.replace(".L", ".UK")
        return None  # Stooq only used for LSE here

    def fetch_batch(self, symbols):
        out = {}

        for s in symbols:
            stooq_sym = self.convert_symbol(s)
            if not stooq_sym:
                continue

            url = f"https://stooq.com/q/l/?s={stooq_sym}&f=ohlcv"
            try:
                r = requests.get(url, timeout=10)
                r.raise_for_status()
                text = r.text.strip()

                # Format: SYMBOL,OPEN,HIGH,LOW,CLOSE,VOLUME
                parts = text.split(',')
                if len(parts) < 6:
                    continue

                _, o, h, l, c, v = parts

                out[s.upper()] = {
                    "symbol": s.upper(),
                    "regularMarketPrice": float(c),
                    "regularMarketOpen": float(o),
                    "regularMarketDayHigh": float(h),
                    "regularMarketDayLow": float(l),
                    "regularMarketPreviousClose": float(c),
                    "regularMarketVolume": int(float(v)),
                }

            except Exception as e:
                print(f"[Stooq] Failed for {s}: {e}")
                continue

        return out

class AlphaVantageProvider(QuoteProvider):
    name = "AlphaVantage"

    def convert_symbol(self, s):
        s = s.upper()
        if s.endswith(".L"):
            return s.replace(".L", ".LON")
        return s  # US stocks are fine

    def fetch_batch(self, symbols):
        out = {}

        for s in symbols:
            av_sym = self.convert_symbol(s)

            url = "https://www.alphavantage.co/query"
            params = {
                "function": "GLOBAL_QUOTE",
                "symbol": av_sym,
                "apikey": _api_key("ALPHAVANTAGEKEY")
            }

            try:
                r = requests.get(url, params=params, timeout=10)
                r.raise_for_status()
                data = r.json().get("Global Quote", {})

                if not data:
                    continue

                out[s.upper()] = {
                    "symbol": s.upper(),
                    "regularMarketPrice": float(data.get("05. price", 0)),
                    "regularMarketOpen": float(data.get("02. open", 0)),
                    "regularMarketDayHigh": float(data.get("03. high", 0)),
                    "regularMarketDayLow": float(data.get("04. low", 0)),
                    "regularMarketPreviousClose": float(data.get("08. previous close", 0)),
                    "regularMarketVolume": int(float(data.get("06. volume", 0))),
                }

            except Exception as e:
                print(f"[AlphaVantage] Failed for {s}: {e}")
                continue

        return out

    def fetch_history(self, symbol, interval="1min", range_="1d"):
        url = "https://www.alphavantage.co/query"
        params = {
            "function": "TIME_SERIES_INTRADAY",
            "symbol": symbol,
            "interval": interval,
            "apikey": _api_key("ALPHAVANTAGEKEY"),
            "outputsize": "compact" if range_ == "1d" else "full"
        }

        r = requests.get(url, params=params, timeout=HTTP_TIMEOUT)
        data = r.json()

        key = f"Time Series ({interval})"
        if key not in data:
            return []

        candles = []
        for ts, values in data[key].items():
            candles.append({
                "time": ts,
                "open": float(values["1. open"]),
                "high": float(values["2. high"]),
                "low": float(values["3. low"]),
                "close": float(values["4. close"]),
                "volume": int(values["5. volume"])
            })

        candles.reverse()  # chronological order
        return candles

# -----------------------------
# Determine symbol type
# -----------------------------
def get_symbol_type(symbol):
    if "-USD" in symbol:
        return "crypto"
    elif ".L" in symbol:
        return "uk_stock"
    else:
        return "us_stock"

# -----------------------------
# Provider priority per symbol type
# -----------------------------
symbol_provider_map = {
    "crypto": [TwelveDataProvider, YahooProvider, FinnhubProvider],
    "uk_stock": [YahooProvider, TwelveDataProvider, FinnhubProvider],
    "us_stock": [FinnhubProvider, YahooProvider, TwelveDataProvider],
}
provider_cooldowns = {
    "Yahoo": 0,
    "Finnhub": 0,
    "TwelveData": 0,
    "CoinGecko": 0,
    "Stooq": 0,
    "AlphaVantage": 0,
}

def provider_available(name):
    return time.time() >= provider_cooldowns[name]

def cooldown_provider(name, seconds=DEFAULT_COOLDOWN):
    provider_cooldowns[name] = time.time() + seconds
    print(f"[COOLDOWN] {name} disabled for {seconds}s")

def is_yahoo_available():
    return time.time() >= yahoo_cooldown_until

def mark_yahoo_rate_limited():
    global yahoo_cooldown_until
    yahoo_cooldown_until = time.time() + 60   # 60-second cooldown

def choose_providers(symbol):
    if "-USD" in symbol:  # crypto
        return [CoinGeckoProvider, YahooProvider]

    if ".L" in symbol:  # LSE stocks
        return [YahooProvider, StooqProvider, AlphaVantageProvider]

    # US stocks
    return [YahooProvider, FinnhubProvider, AlphaVantageProvider]

# -----------------------------
# Progressive batch fetch with failover
# -----------------------------
def fetch_batch(symbols):

    results = {}
    pending = list(symbols)

    # Split into chunks of 8 to avoid Yahoo throttling
    chunks = [pending[i:i+8] for i in range(0, len(pending), 8)]

    for chunk in chunks:
        for sym in chunk:
            providers = choose_providers(sym)

            for provider_cls in providers:
                # Skip Yahoo if in cooldown
                if provider_cls is YahooProvider and not is_yahoo_available():
                    continue

                p = provider_cls()
                try:
                    data = p.fetch_batch([sym])
                    if data:
                        results.update(data)
                        # Save last known good data
                        for k, v in data.items():
                            nk = norm(k)
                            v["_fallback"] = False
                            last_good[nk] = v
                            results[nk] = v

                        break  # success for this symbol

                except requests.exceptions.HTTPError as e:
                    if provider_cls is YahooProvider and e.response.status_code == 429:
                        print("[YAHOO] Rate limited, entering cooldown")
                        mark_yahoo_rate_limited()
                        continue
                    else:
                        print(f"[PROVIDER] {p.name} failed for {sym}: {e}")
                        continue

                except Exception as e:
                    print(f"[PROVIDER] {p.name} error for {sym}: {e}")
                    continue

    # Report failures
    missing = [s for s in symbols if norm(s) not in results]

    for sym in missing:
        key = norm(sym)
        if key in last_good:
            fallback = last_good[key].copy()
            fallback["_fallback"] = True
            results[key] = fallback
            print(f"[FALLBACK] Using last known data for {sym}")
        else:
            print(f"[FAIL] No data and no fallback for {sym}")

    return results

# -----------------------------
# Global cache state
# -----------------------------
cache = {}
last_good = {}
cache_timestamp = 0
cache_symbols = []
cache_lock = threading.Lock()

cache_thread = None
cache_running = False
cache_interval = 60

# -----------------------------
# Background cache updater
# -----------------------------
def cache_updater():
    global cache, cache_timestamp
    print(f"[CACHE] updater started interval={cache_interval}")

    while cache_running:
        try:
            if cache_symbols:
                # Check if ANY provider is available
                any_available = any(provider_available(p) for p in provider_cooldowns)

                if not any_available:
                    print("[CACHE] All providers cooling down, skipping this cycle")
                else:
                    data = fetch_batch(cache_symbols)
                    with cache_lock:
                        cache = data
                        cache_timestamp = time.time()
                    print(f"[CACHE] refreshed {len(data)} symbols")

        except Exception as e:
            print("[CACHE] error:", e)

        time.sleep(cache_interval)

    print("[CACHE] stopped")

def build_non_temporal_candles(candles, threshold):
    """
    Convert historical OHLC candles into non-temporal candles.
    threshold = price movement required to start a new candle
    """
    if not candles:
        return []

    nt = []  # final non-temporal candles

    # Start first candle
    active = {
        "open": candles[0]["open"],
        "high": candles[0]["open"],
        "low":  candles[0]["open"],
        "close": candles[0]["open"],
        "volume": 0
    }

    for c in candles:
        price = c["close"]

        # Update active candle
        active["high"] = max(active["high"], price)
        active["low"]  = min(active["low"], price)
        active["close"] = price
        active["volume"] += c["volume"]

        # Check threshold
        if abs(active["close"] - active["open"]) >= threshold:
            nt.append(active)

            # Start new candle
            active = {
                "open": price,
                "high": price,
                "low":  price,
                "close": price,
                "volume": 0
            }

    # Add last candle
    nt.append(active)

    return nt

def fetch_history_with_failover(symbol, interval="1m", range_="1d"):
    providers = choose_providers(symbol)

    # --- Symbol normalization helpers ---
    def normalize_for_alpha(sym):
        # LSE: AZN.L → AZN.LON
        if sym.endswith(".L"):
            return sym.replace(".L", ".LON")
        return sym

    def normalize_for_stooq(sym):
        # US stocks: MSTR → MSTR.US
        if sym.isalpha():
            return sym + ".US"
        return sym

    COINGECKO_MAP = {
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "DOGE": "dogecoin",
        "ADA": "cardano",
        "SOL": "solana",
        "XRP": "ripple",
        "DOT": "polkadot",
        "LTC": "litecoin",
        "BCH": "bitcoin-cash",
        "BNB": "binancecoin"
    }

    for provider_cls in providers:
        p = provider_cls()

        # Skip Yahoo (no history implemented)
        if provider_cls.__name__ == "YahooProvider":
            print("[HISTORY] Yahoo has no fetch_history()")
            continue

        # Skip Yahoo if cooling down
        if provider_cls.__name__ == "YahooProvider" and not is_yahoo_available():
            continue

        # --- Normalize symbol for this provider ---
        symbol_for_provider = symbol

        if provider_cls.__name__ == "AlphaVantageProvider":
            symbol_for_provider = normalize_for_alpha(symbol)

        elif provider_cls.__name__ == "StooqProvider":
            symbol_for_provider = normalize_for_stooq(symbol)

        elif provider_cls.__name__ == "CoinGeckoProvider":
            base = symbol.split("-")[0].upper()
            if base in COINGECKO_MAP:
                symbol_for_provider = COINGECKO_MAP[base]
            else:
                print(f"[HISTORY] CoinGecko: Unknown coin {base}")
                continue

        # --- Try fetching history ---
        try:
            if hasattr(p, "fetch_history"):
                candles = p.fetch_history(symbol_for_provider, interval, range_)
                if candles:
                    print(f"[HISTORY] {p.name} OK for {symbol} (as {symbol_for_provider})")
                    return candles
                else:
                    print(f"[HISTORY] {p.name} returned no data for {symbol_for_provider}")
            else:
                print(f"[HISTORY] {p.name} has no fetch_history()")

        except Exception as e:
            print(f"[HISTORY] {p.name} failed for {symbol_for_provider}: {e}")
            continue

    print(f"[HISTORY] No provider succeeded for {symbol}")
    return []

def scale_value(price, min_price, max_price):
    """
    Convert price to MSX SCREEN 2 Y coordinate.
    0 = top, 191 = bottom.
    We use 140..20 for chart area.
    """
    if max_price == min_price:
        return 100  # avoid division by zero

    # Chart height = 120 pixels
    chart_top = 20
    chart_bottom = 140
    chart_height = chart_bottom - chart_top

    # Normalize price
    ratio = (price - min_price) / (max_price - min_price)

    # Invert Y axis (higher price = lower Y)
    y = chart_bottom - int(ratio * chart_height)

    # Clamp
    if y < 0: y = 0
    if y > 191: y = 191

    return y

# -----------------------------
# STOCK command handler
# -----------------------------
def stock(command_str: str) -> CommandResult:
    print("stock()")
    global cache, cache_running, cache_thread, cache_interval, cache_symbols, cache_timestamp

    def fmt_volume(v):
        if v >= 1_000_000_000: return f"{v/1_000_000_000:.2f}B"
        if v >= 1_000_000: return f"{v/1_000_000:.2f}M"
        if v >= 1_000: return f"{v/1_000:.2f}K"
        return f"{v:.2f}U"

    parts = command_str.strip().split(" ", 1)
    subcmd = parts[0].upper()

    # -------------------------
    # STARTCACHE
    # -------------------------
    if subcmd == "STARTCACHE":
        print("STARTCACHE()")
        try:
            cache_interval = int(parts[1])
        except:
            sendmultiblock(b"ERROR: Use STARTCACHE <seconds>")
            return
        if cache_running:
            sendmultiblock(b"Cache already running")
            return
        cache_running = True
        cache_thread = threading.Thread(target=cache_updater, daemon=True)
        cache_thread.start()
        sendmultiblock(f"Cache started, interval={cache_interval}s".encode())
        return

    # -------------------------
    # STOPCACHE
    # -------------------------
    if subcmd == "STOPCACHE":
        cache_running = False
        sendmultiblock(b"Cache stopping...")
        return

    # -------------------------
    # STATUS
    # -------------------------
    if subcmd == "STATUS":
        with cache_lock:
            age = time.time() - cache_timestamp if cache_timestamp else -1
            count = len(cache)
        msg = (
            f"Cache running: {cache_running}\n"
            f"Symbols: {','.join(cache_symbols)}\n"
            f"Entries: {count}\n"
            f"Age: {age:.1f}s\n"
            f"Interval: {cache_interval}s"
        )
        sendmultiblock(msg.encode())
        return

    if subcmd == "HISTORY":
        if len(parts) < 2:
            sendmultiblock(b"ERROR: Use HISTORY <symbol>,<interval>,<range>")
            return

        args = parts[1].replace(" ", "").split(",")
        symbol = args[0]
        interval = args[1] if len(args) > 1 else "1m"
        range_   = args[2] if len(args) > 2 else "1d"

        candles = fetch_history_with_failover(symbol, interval, range_)

        if not candles:
            sendmultiblock(b"ERROR: No history data")
            return

        lines = []
        for i, c in enumerate(candles):
            lines.append(
                f"O({i})={c['open']}\n"
                f"H({i})={c['high']}\n"
                f"L({i})={c['low']}\n"
                f"C({i})={c['close']}\n"
                f"V({i})={c['volume']}"
            )

        sendmultiblock("\n".join(lines).encode())
        return

    # -------------------------
    # FETCHLIST
    # -------------------------
    if subcmd == "FETCHLIST":
        if len(parts) < 2:
            sendmultiblock(b"ERROR: Use FETCHLIST <symbols>")
            return

        raw_list = parts[1].replace(" ", "")
        symbols = raw_list.split(",")
        cache_symbols = symbols  # update cache list

        # Fetch batch with progressive failover
        try:
            with cache_lock:
                results = fetch_batch(symbols)
                cache = results
                cache_timestamp = time.time()
        except Exception as e:
            msg = f"ERROR: Batch request failed: {str(e)}"
            print(msg)
            sendmultiblock(msg.encode())
            return

        # Format output
        lines = []

        for sym in symbols:
            d = results.get(norm(sym))

            if not d:
                # No data at all
                line = f"{sym:<12}----   No data"
            else:
                # Display symbol (remove dash for crypto)
                disp = sym.replace("-", "")[:6].ljust(6)

                cur = float(d.get("regularMarketPrice", 0))
                o   = float(d.get("regularMarketOpen", 0))
                h   = float(d.get("regularMarketDayHigh", 0))
                l   = float(d.get("regularMarketDayLow", 0))
                pc  = float(d.get("regularMarketPreviousClose", 0))

                v_raw = int(d.get("regularMarketVolume", 0))
                v_fmt = fmt_volume(v_raw)

                # Fallback flag: "*" if using last_good, else " "
                fb_flag = "*" if d.get("_fallback") else " "

                # Append flag after volume
                line = "{:<6s}{:>10.2f}{:>10.2f}{:>10.2f}{:>10.2f}{:>10.2f}{:>12s} {}".format(
                    disp, cur, o, h, l, pc, v_fmt, fb_flag
                )

            lines.append(line)

        sendmultiblock("\n".join(lines).encode())
        return

    if subcmd == "NTCANDLE":
        if len(parts) < 2:
            sendmultiblock(b"ERROR: Use NTCANDLE <symbol>,<threshold>,<interval>,<range>")
            return

        # Parse MSX parameters
        args = parts[1].replace(" ", "").split(",")
        symbol    = args[0]
        threshold = float(args[1])
        interval  = args[2] if len(args) > 2 else "1m"
        range_    = args[3] if len(args) > 3 else "1d"

        # Fetch history using MSX parameters
        candles = fetch_history_with_failover(symbol, interval, range_)
        if not candles:
            sendmultiblock(b"ERROR: No history data")
            return

        # Build non-temporal candles
        nt = build_non_temporal_candles(candles, threshold)

        # Limit number of candles based on interval
        if interval == "1h":
            nt = nt[-24:]
        elif interval == "30m":
            nt = nt[-48:]
        elif interval == "15m":
            nt = nt[-96:]
        elif interval == "1m":
            nt = nt[-240:]

        # Compute min/max for scaling
        min_price = min(c["low"] for c in nt)
        max_price = max(c["high"] for c in nt)

        # Build DRAW commands
        lines = []
        for i, c in enumerate(nt):
            x = 8 + i*4

            yo = scale_value(c["open"],  min_price, max_price)
            yh = scale_value(c["high"],  min_price, max_price)
            yl = scale_value(c["low"],   min_price, max_price)
            yc = scale_value(c["close"], min_price, max_price)

            # Wick
            lines.append(f"D:W {x+1} {yh} {yl} 15")

            # Body color
            if c["close"] > c["open"]:
                col = 10
            elif c["close"] < c["open"]:
                col = 6
            else:
                col = 14

            # Body
            lines.append(f"D:B {x} {yo} {yc} {col}")

        lines.append("END")
        ll=lines
        print(len("\r\n".join(lines).encode()))
        sendmultiblock("\r\n".join(lines).encode())
