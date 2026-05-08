# app/lambda/ingest/main.py
#
# Runs every 1 minute triggered by EventBridge.
# 1. Fetches OHLCV data for the trading pair
# 2. Computes MA, RSI, ATR
# 3. Publishes a JSON payload to GCP Pub/Sub

import os
import json
import logging
import hashlib
from datetime import datetime, timezone

import boto3
import ccxt
import pandas as pd
import numpy as np

# ── logging ────────────────────────────────────────────────
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── environment variables ──────────────────────────────────
TRADING_PAIR   = os.environ.get("TRADING_PAIR", "BTC/USDT")
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
PUBSUB_TOPIC   = os.environ.get("PUBSUB_TOPIC")
ENVIRONMENT    = os.environ.get("ENVIRONMENT", "dev")
SSM_PREFIX     = os.environ.get("SSM_PREFIX", "/dev")

# ── SSM client — fetches secrets at cold start ─────────────
ssm = boto3.client("ssm", region_name=os.environ.get("AWS_REGION", "us-east-1"))

def get_parameter(name: str) -> str:
    """Fetch a parameter from SSM Parameter Store."""
    try:
        response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/{name}",
            WithDecryption=True
        )
        return response["Parameter"]["Value"]
    except Exception as e:
        logger.warning(f"Could not fetch SSM parameter {name}: {e}")
        return ""

# ── feature engineering ────────────────────────────────────

def compute_rsi(prices: pd.Series, period: int = 14) -> float:
    """Compute RSI for the most recent candle."""
    delta = prices.diff()
    gain  = delta.where(delta > 0, 0.0)
    loss  = -delta.where(delta < 0, 0.0)

    avg_gain = gain.rolling(window=period).mean()
    avg_loss = loss.rolling(window=period).mean()

    rs  = avg_gain / avg_loss.replace(0, np.nan)
    rsi = 100 - (100 / (1 + rs))

    return round(float(rsi.iloc[-1]), 2)


def compute_atr(highs: pd.Series, lows: pd.Series, closes: pd.Series, period: int = 14) -> float:
    """Compute Average True Range for the most recent candle."""
    prev_close = closes.shift(1)

    tr = pd.concat([
        highs - lows,
        (highs - prev_close).abs(),
        (lows  - prev_close).abs()
    ], axis=1).max(axis=1)

    atr = tr.rolling(window=period).mean()
    return round(float(atr.iloc[-1]), 2)


def compute_moving_averages(closes: pd.Series) -> dict:
    """Compute MA20 and MA50."""
    return {
        "ma20": round(float(closes.rolling(20).mean().iloc[-1]), 2),
        "ma50": round(float(closes.rolling(50).mean().iloc[-1]), 2),
    }


def fetch_ohlcv(exchange, pair: str, timeframe: str = "1m", limit: int = 100) -> pd.DataFrame:
    """Fetch OHLCV candles and return as a DataFrame."""
    raw = exchange.fetch_ohlcv(pair, timeframe=timeframe, limit=limit)

    df = pd.DataFrame(raw, columns=["timestamp", "open", "high", "low", "close", "volume"])
    df["timestamp"] = pd.to_datetime(df["timestamp"], unit="ms", utc=True)
    return df


def build_payload(df: pd.DataFrame, pair: str) -> dict:
    """Build the JSON payload to publish to Pub/Sub."""
    latest   = df.iloc[-1]
    closes   = df["close"]
    highs    = df["high"]
    lows     = df["low"]

    rsi      = compute_rsi(closes)
    atr      = compute_atr(highs, lows, closes)
    mas      = compute_moving_averages(closes)

    payload = {
        "timestamp"   : datetime.now(timezone.utc).isoformat(),
        "trading_pair": pair,
        "price"       : round(float(latest["close"]), 2),
        "open"        : round(float(latest["open"]),  2),
        "high"        : round(float(latest["high"]),  2),
        "low"         : round(float(latest["low"]),   2),
        "volume"      : round(float(latest["volume"]), 4),
        "rsi"         : rsi,
        "atr"         : atr,
        "ma20"        : mas["ma20"],
        "ma50"        : mas["ma50"],
        "features"    : [rsi, atr, mas["ma20"], mas["ma50"]],
        "environment" : ENVIRONMENT,
    }

    # Deduplication key — SHA256 of pair + minute timestamp
    minute_ts = latest["timestamp"].strftime("%Y%m%d%H%M")
    payload["dedup_id"] = hashlib.sha256(f"{pair}{minute_ts}".encode()).hexdigest()

    return payload


def publish_to_pubsub(payload: dict) -> None:
    """
    Publish payload to GCP Pub/Sub using the google-cloud-pubsub client.
    Lambda authenticates via Workload Identity Federation.
    """
    from google.cloud import pubsub_v1

    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(GCP_PROJECT_ID, PUBSUB_TOPIC)

    data = json.dumps(payload).encode("utf-8")

    future = publisher.publish(
        topic_path,
        data=data,
        # Message attributes for filtering and deduplication
        trading_pair=payload["trading_pair"],
        environment=payload["environment"],
        dedup_id=payload["dedup_id"],
    )

    message_id = future.result(timeout=10)
    logger.info(f"Published message {message_id} to {topic_path}")


# ── Lambda handler ─────────────────────────────────────────

def handler(event, context):
    """
    Main Lambda entry point.
    Called every 1 minute by EventBridge.
    """
    logger.info(f"Ingestion triggered for {TRADING_PAIR} in {ENVIRONMENT}")

    try:
        # Initialise exchange — binance works without API keys for public data
        exchange = ccxt.binance({
            "enableRateLimit": True,
            "options": {"defaultType": "spot"},
        })

        # Fetch candles
        df = fetch_ohlcv(exchange, TRADING_PAIR, timeframe="1m", limit=100)
        logger.info(f"Fetched {len(df)} candles for {TRADING_PAIR}")

        # Build payload
        payload = build_payload(df, TRADING_PAIR)
        logger.info(f"Built payload: price={payload['price']} rsi={payload['rsi']} atr={payload['atr']}")

        # Publish to Pub/Sub
        publish_to_pubsub(payload)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message"  : "Published successfully",
                "pair"     : TRADING_PAIR,
                "price"    : payload["price"],
                "rsi"      : payload["rsi"],
                "dedup_id" : payload["dedup_id"],
            })
        }

    except Exception as e:
        logger.error(f"Ingestion failed: {e}", exc_info=True)
        raise