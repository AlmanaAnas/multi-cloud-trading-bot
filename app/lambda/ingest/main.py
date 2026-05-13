# app/lambda/ingest/main.py
#
# AWS Lambda function — triggered every 1 minute by EventBridge
#
# DATA SOURCE: Binance Public REST API
#   URL: https://api.binance.com/api/v3/klines
#   No API key required. Free public endpoint.
#   Returns 1-minute OHLCV candles for BTCUSDT.
#   Current BTC price: ~$80,000-$82,000 (May 2026)

import os
import json
import logging
import hashlib
import urllib.request
import urllib.parse
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TRADING_PAIR   = os.environ.get("TRADING_PAIR", "BTC/USDT")
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
PUBSUB_TOPIC   = os.environ.get("PUBSUB_TOPIC", "")
ENVIRONMENT    = os.environ.get("ENVIRONMENT", "dev")
BINANCE_SYMBOL = TRADING_PAIR.replace("/", "")  # BTCUSDT
BINANCE_URL    = "https://api.binance.com/api/v3/klines"


# ─────────────────────────────────────────────
# STEP 1: Fetch live BTC prices from Binance
#
# Binance public API — no key needed.
# Returns last 100 one-minute candles.
# Each candle = [open_time, open, high, low, close, volume, ...]
# ─────────────────────────────────────────────

def fetch_candles(symbol: str, interval: str = "1m", limit: int = 100) -> list:
    params = urllib.parse.urlencode({
        "symbol":   symbol,
        "interval": interval,
        "limit":    limit,
    })
    url = f"{BINANCE_URL}?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        candles = json.loads(resp.read().decode())
    logger.info(f"Fetched {len(candles)} candles · latest close=${float(candles[-1][4]):,.2f}")
    return candles


# ─────────────────────────────────────────────
# STEP 2: Compute technical indicators
#
# RSI  — is the market overbought or oversold?
# ATR  — how much is price moving? (volatility)
# MA20 — 20-period moving average (short-term trend)
# MA50 — 50-period moving average (long-term trend)
# ─────────────────────────────────────────────

def compute_rsi(closes: list, period: int = 14) -> float:
    """
    RSI = 100 - (100 / (1 + RS))
    RS = average gain / average loss over last `period` candles
    RSI < 30 = oversold (potential buy signal)
    RSI > 70 = overbought (potential sell signal)
    """
    if len(closes) < period + 1:
        return 50.0

    gains, losses = [], []
    for i in range(-period, 0):
        diff = closes[i] - closes[i - 1]
        gains.append(max(diff, 0))
        losses.append(max(-diff, 0))

    avg_gain = sum(gains) / period
    avg_loss = sum(losses) / period

    if avg_loss == 0:
        return 100.0

    rs = avg_gain / avg_loss
    return round(100 - (100 / (1 + rs)), 2)


def compute_atr(highs: list, lows: list, closes: list, period: int = 14) -> float:
    """
    ATR = average of True Range over `period` candles
    True Range = max(high-low, abs(high-prev_close), abs(low-prev_close))
    Used for stop loss: stop_loss = entry_price - (ATR * 1.5)
    At BTC ~$81,000 with normal volatility, ATR is typically $500-$1,500
    """
    if len(closes) < period + 1:
        return 0.0

    true_ranges = []
    for i in range(-period, 0):
        tr = max(
            highs[i] - lows[i],
            abs(highs[i] - closes[i - 1]),
            abs(lows[i]  - closes[i - 1]),
        )
        true_ranges.append(tr)

    return round(sum(true_ranges) / period, 2)


def compute_ma(closes: list, period: int) -> float:
    """Simple moving average of last `period` closes."""
    if len(closes) < period:
        return closes[-1]
    return round(sum(closes[-period:]) / period, 2)


# ─────────────────────────────────────────────
# STEP 3: Build the payload
#
# Parses raw Binance candle format:
# [0] open_time (ms unix)
# [1] open price
# [2] high price
# [3] low price
# [4] close price
# [5] volume (BTC)
# ─────────────────────────────────────────────

def build_payload(candles: list) -> dict:
    opens   = [float(c[1]) for c in candles]
    highs   = [float(c[2]) for c in candles]
    lows    = [float(c[3]) for c in candles]
    closes  = [float(c[4]) for c in candles]
    volumes = [float(c[5]) for c in candles]

    price = closes[-1]
    rsi   = compute_rsi(closes)
    atr   = compute_atr(highs, lows, closes)
    ma20  = compute_ma(closes, 20)
    ma50  = compute_ma(closes, 50)

    # Stop loss calculation (for reference — actual signal computed in Cloud Function)
    # LONG stop loss  = price - (ATR * 1.5)
    # SHORT stop loss = price + (ATR * 1.5)
    # At BTC ~$81,000 and ATR ~$800: stop loss ≈ $81,000 - $1,200 = $79,800
    stop_loss_long  = round(price - (atr * 1.5), 2)
    stop_loss_short = round(price + (atr * 1.5), 2)

    # Dedup ID — prevents Cloud Function processing the same candle twice
    # Uses the candle's open timestamp (unique per minute)
    dedup_id = hashlib.sha256(
        f"{BINANCE_SYMBOL}{candles[-1][0]}".encode()
    ).hexdigest()[:16]

    return {
        "timestamp"       : datetime.now(timezone.utc).isoformat(),
        "trading_pair"    : TRADING_PAIR,
        "price"           : round(price, 2),
        "open"            : round(opens[-1], 2),
        "high"            : round(highs[-1], 2),
        "low"             : round(lows[-1], 2),
        "volume_btc"      : round(volumes[-1], 6),
        "rsi"             : rsi,
        "atr"             : atr,
        "ma20"            : ma20,
        "ma50"            : ma50,
        "stop_loss_long"  : stop_loss_long,
        "stop_loss_short" : stop_loss_short,
        "features"        : [rsi, atr, ma20, ma50, price],
        "environment"     : ENVIRONMENT,
        "dedup_id"        : dedup_id,
        "source"          : "binance_public_api",
    }


# ─────────────────────────────────────────────
# STEP 4: Publish to GCP Pub/Sub
#
# Uses google-cloud-pubsub.
# Auth via Workload Identity Federation — no keys stored.
# ─────────────────────────────────────────────

def publish_to_pubsub(payload: dict) -> None:
    if not GCP_PROJECT_ID or not PUBSUB_TOPIC:
        logger.warning("GCP_PROJECT_ID or PUBSUB_TOPIC not set — skipping publish")
        logger.info(f"PAYLOAD PREVIEW: price={payload['price']} rsi={payload['rsi']}")
        return

    try:
        from google.cloud import pubsub_v1
        publisher  = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(GCP_PROJECT_ID, PUBSUB_TOPIC)
        data       = json.dumps(payload).encode("utf-8")

        future     = publisher.publish(
            topic_path,
            data         = data,
            trading_pair = payload["trading_pair"],
            environment  = payload["environment"],
            dedup_id     = payload["dedup_id"],
        )
        message_id = future.result(timeout=15)
        logger.info(f"Published · message_id={message_id}")

    except ImportError:
        logger.warning("google-cloud-pubsub not installed — logging payload only")
        logger.info(json.dumps(payload, indent=2))


# ─────────────────────────────────────────────
# Lambda entry point
# ─────────────────────────────────────────────

def handler(event, context):
    logger.info(f"=== Ingestion start === {TRADING_PAIR} · {ENVIRONMENT}")

    candles = fetch_candles(BINANCE_SYMBOL)
    payload = build_payload(candles)

    logger.info(
        f"BTC=${payload['price']:,.2f} | "
        f"RSI={payload['rsi']} | "
        f"ATR=${payload['atr']:,.2f} | "
        f"SL(L)=${payload['stop_loss_long']:,.2f} | "
        f"MA20=${payload['ma20']:,.2f}"
    )

    publish_to_pubsub(payload)

    return {
        "statusCode": 200,
        "body": json.dumps({
            "price"          : payload["price"],
            "rsi"            : payload["rsi"],
            "stop_loss_long" : payload["stop_loss_long"],
            "dedup_id"       : payload["dedup_id"],
        })
    }