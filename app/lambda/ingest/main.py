# app/lambda/ingest/main.py
#
# Triggered every 1 minute by EventBridge.
#
# What it does:
#   1. Calls Binance public API — no key required
#   2. Gets last 100 one-minute candles for BTC/USDT
#   3. Calculates RSI, ATR, MA20, MA50
#   4. Publishes a JSON payload to GCP Pub/Sub
#
# Where the prices come from:
#   Binance public REST API — api.binance.com
#   Endpoint: GET /api/v3/klines
#   No API key needed. Free. Public.
#   Returns: [timestamp, open, high, low, close, volume, ...]

import os
import json
import logging
import hashlib
import urllib.request
import urllib.parse
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── environment variables ──────────────────────────────────
TRADING_PAIR    = os.environ.get("TRADING_PAIR", "BTC/USDT")
GCP_PROJECT_ID  = os.environ.get("GCP_PROJECT_ID")
PUBSUB_TOPIC    = os.environ.get("PUBSUB_TOPIC")
ENVIRONMENT     = os.environ.get("ENVIRONMENT", "dev")

# Binance uses BTCUSDT (no slash)
BINANCE_SYMBOL  = TRADING_PAIR.replace("/", "")
BINANCE_API     = "https://api.binance.com/api/v3/klines"


# ── Step 1: Fetch prices from Binance ─────────────────────
# No API key needed. Binance provides free public market data.
# We request 100 one-minute candles for BTC/USDT.
# Each candle = [open_time, open, high, low, close, volume, ...]

def fetch_candles(symbol: str, interval: str = "1m", limit: int = 100) -> list:
    """
    Fetch OHLCV candles from Binance public API.
    Returns a list of candles, each as a list of values.
    """
    params = urllib.parse.urlencode({
        "symbol":   symbol,
        "interval": interval,
        "limit":    limit,
    })

    url = f"{BINANCE_API}?{params}"
    logger.info(f"Fetching {limit} candles from Binance: {symbol} {interval}")

    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0"}
    )

    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())

    logger.info(f"Received {len(data)} candles")
    return data


# ── Step 2: Compute indicators ─────────────────────────────

def compute_rsi(closes: list, period: int = 14) -> float:
    """
    RSI — Relative Strength Index
    Tells us if the market is overbought (RSI > 70) or oversold (RSI < 30).
    Calculated from the last `period` closing prices.
    """
    if len(closes) < period + 1:
        return 50.0  # not enough data — return neutral

    gains, losses = [], []
    for i in range(1, period + 1):
        diff = closes[-period + i - 1] - closes[-period + i - 2]
        if diff > 0:
            gains.append(diff)
            losses.append(0)
        else:
            gains.append(0)
            losses.append(abs(diff))

    avg_gain = sum(gains) / period
    avg_loss = sum(losses) / period

    if avg_loss == 0:
        return 100.0

    rs  = avg_gain / avg_loss
    rsi = 100 - (100 / (1 + rs))
    return round(rsi, 2)


def compute_atr(highs: list, lows: list, closes: list, period: int = 14) -> float:
    """
    ATR — Average True Range
    Measures how much the price is moving — i.e. volatility.
    Used to set dynamic stop losses: stop_loss = price - (ATR x 1.5)
    """
    if len(closes) < period + 1:
        return 0.0

    true_ranges = []
    for i in range(1, period + 1):
        idx   = len(closes) - period + i - 1
        high  = highs[idx]
        low   = lows[idx]
        prev_close = closes[idx - 1]

        tr = max(
            high - low,
            abs(high - prev_close),
            abs(low  - prev_close)
        )
        true_ranges.append(tr)

    return round(sum(true_ranges) / period, 2)


def compute_ma(closes: list, period: int) -> float:
    """
    Moving Average — average of the last `period` closing prices.
    MA20 = short-term trend
    MA50 = long-term trend
    If price > MA50, we're in an uptrend.
    """
    if len(closes) < period:
        return closes[-1] if closes else 0.0
    return round(sum(closes[-period:]) / period, 2)


# ── Step 3: Parse candles and build payload ────────────────

def build_payload(candles: list) -> dict:
    """
    Parse the raw Binance candle data and compute all features.
    Binance candle format:
      [0]  open_time (ms)
      [1]  open price
      [2]  high price
      [3]  low price
      [4]  close price
      [5]  volume
      [6]  close_time
      ...  (we only need 0-5)
    """
    opens   = [float(c[1]) for c in candles]
    highs   = [float(c[2]) for c in candles]
    lows    = [float(c[3]) for c in candles]
    closes  = [float(c[4]) for c in candles]
    volumes = [float(c[5]) for c in candles]

    latest_close  = closes[-1]
    latest_candle = candles[-1]

    rsi  = compute_rsi(closes)
    atr  = compute_atr(highs, lows, closes)
    ma20 = compute_ma(closes, 20)
    ma50 = compute_ma(closes, 50)

    # Features passed to the ML model
    # Order matters — must match training data
    features = [rsi, atr, ma20, ma50, latest_close]

    # Dedup ID — SHA256 of symbol + candle open time
    # Prevents the Cloud Function from processing duplicates
    open_time = str(latest_candle[0])
    dedup_id  = hashlib.sha256(
        f"{BINANCE_SYMBOL}{open_time}".encode()
    ).hexdigest()[:16]

    payload = {
        "timestamp"   : datetime.now(timezone.utc).isoformat(),
        "trading_pair": TRADING_PAIR,
        "price"       : round(latest_close, 2),
        "open"        : round(float(latest_candle[1]), 2),
        "high"        : round(float(latest_candle[2]), 2),
        "low"         : round(float(latest_candle[3]), 2),
        "volume"      : round(volumes[-1], 4),
        "rsi"         : rsi,
        "atr"         : atr,
        "ma20"        : ma20,
        "ma50"        : ma50,
        "features"    : features,
        "environment" : ENVIRONMENT,
        "dedup_id"    : dedup_id,
        "source"      : "binance",
    }

    return payload


# ── Step 4: Publish to GCP Pub/Sub ────────────────────────
# Lambda authenticates to GCP using Workload Identity Federation.
# No GCP service account key is stored anywhere.
# Lambda gets a short-lived token from STS and exchanges it for a GCP token.

def publish_to_pubsub(payload: dict) -> None:
    """
    Publish the payload to GCP Pub/Sub.
    Uses google-cloud-pubsub which handles WIF auth automatically
    when GOOGLE_APPLICATION_CREDENTIALS is not set but
    the execution environment has the right AWS identity.
    """
    try:
        from google.cloud import pubsub_v1
        from google.auth import aws as google_aws_auth
        from google.auth.transport.requests import Request as GoogleRequest

        publisher  = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(GCP_PROJECT_ID, PUBSUB_TOPIC)
        data       = json.dumps(payload).encode("utf-8")

        future = publisher.publish(
            topic_path,
            data       = data,
            trading_pair = payload["trading_pair"],
            environment  = payload["environment"],
            dedup_id     = payload["dedup_id"],
        )

        message_id = future.result(timeout=15)
        logger.info(f"Published to {topic_path} — message_id={message_id}")

    except ImportError:
        # google-cloud-pubsub not installed — log and continue
        # This happens when running locally without dependencies
        logger.warning("google-cloud-pubsub not installed — payload logged only")
        logger.info(f"PAYLOAD: {json.dumps(payload, indent=2)}")


# ── Lambda entry point ─────────────────────────────────────

def handler(event, context):
    """
    Main function. Called every minute by EventBridge.

    Flow:
      EventBridge → Lambda (here) → Binance API → compute features → Pub/Sub → Cloud Function
    """
    logger.info(f"=== Ingestion started === pair={TRADING_PAIR} env={ENVIRONMENT}")

    try:
        # 1. Fetch live BTC/USDT prices from Binance
        candles = fetch_candles(BINANCE_SYMBOL, interval="1m", limit=100)

        # 2. Compute all technical indicators
        payload = build_payload(candles)

        logger.info(
            f"BTC price=${payload['price']:,.2f} | "
            f"RSI={payload['rsi']} | "
            f"ATR={payload['atr']} | "
            f"MA20={payload['ma20']:,.2f} | "
            f"MA50={payload['ma50']:,.2f}"
        )

        # 3. Publish to GCP Pub/Sub
        publish_to_pubsub(payload)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "status"     : "ok",
                "pair"       : TRADING_PAIR,
                "price"      : payload["price"],
                "rsi"        : payload["rsi"],
                "dedup_id"   : payload["dedup_id"],
                "timestamp"  : payload["timestamp"],
            })
        }

    except Exception as e:
        logger.error(f"Ingestion failed: {e}", exc_info=True)
        raise