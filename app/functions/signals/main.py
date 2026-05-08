# app/functions/signals/main.py
#
# Triggered by Pub/Sub push subscription every time
# the Lambda publishes a new market data payload.
# 1. Deserialises and validates the incoming message
# 2. Loads the ML model from GCS (cached in memory)
# 3. Runs inference
# 4. Checks RSI conditions
# 5. Archives raw data to BigQuery
# 6. Sends Telegram alert if confidence > 80%

import os
import json
import base64
import logging
import hashlib
import pickle
from datetime import datetime, timezone

import functions_framework
from google.cloud import bigquery
from google.cloud import storage

# ── logging ────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── environment variables ──────────────────────────────────
GCP_PROJECT_ID  = os.environ.get("GCP_PROJECT_ID")
BQ_DATASET      = os.environ.get("BQ_DATASET")
BQ_TABLE        = os.environ.get("BQ_TABLE", "signals")
ENVIRONMENT     = os.environ.get("ENVIRONMENT", "dev")
MODEL_BUCKET    = os.environ.get("MODEL_BUCKET", "")
MODEL_PATH      = os.environ.get("MODEL_PATH", "models/model.pkl")
TELEGRAM_TOKEN  = os.environ.get("TELEGRAM_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

# ── module-level cache ─────────────────────────────────────
# Model is loaded once per instance and reused across invocations
_model = None

# Deduplication set — stores dedup_ids seen in this instance's lifetime
_seen_dedup_ids: set = set()

# ── model loading ──────────────────────────────────────────

def load_model():
    """Load ML model from GCS into memory. Cached after first load."""
    global _model

    if _model is not None:
        logger.info("Model already loaded — using cached version")
        return _model

    if not MODEL_BUCKET:
        logger.warning("MODEL_BUCKET not set — using dummy model")
        _model = None
        return None

    try:
        client = storage.Client()
        bucket = client.bucket(MODEL_BUCKET)
        blob   = bucket.blob(MODEL_PATH)

        model_bytes = blob.download_as_bytes()
        _model = pickle.loads(model_bytes)
        logger.info(f"Model loaded from gs://{MODEL_BUCKET}/{MODEL_PATH}")
        return _model

    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        return None


# ── inference ──────────────────────────────────────────────

def run_inference(model, features: list) -> dict:
    """
    Run model prediction and return confidence + direction.
    Falls back to RSI-based rule if no model is loaded.
    """
    if model is not None:
        try:
            import numpy as np
            X = np.array(features).reshape(1, -1)

            proba     = model.predict_proba(X)[0]
            direction = model.predict(X)[0]
            confidence = round(float(max(proba)) * 100, 2)

            return {
                "direction" : "LONG" if direction == 1 else "SHORT",
                "confidence": confidence,
            }
        except Exception as e:
            logger.error(f"Model inference failed: {e}")

    # Fallback — simple RSI rule when no model is available
    rsi = features[0] if features else 50
    if rsi < 30:
        return {"direction": "LONG",  "confidence": 72.0}
    elif rsi > 70:
        return {"direction": "SHORT", "confidence": 68.0}
    else:
        return {"direction": "LONG",  "confidence": 45.0}


def calculate_stop_loss(price: float, atr: float, direction: str) -> float:
    """Calculate dynamic stop loss based on ATR."""
    multiplier = 1.5
    if direction == "LONG":
        return round(price - (atr * multiplier), 2)
    else:
        return round(price + (atr * multiplier), 2)


# ── BigQuery archival ──────────────────────────────────────

def archive_to_bigquery(payload: dict, signal: dict) -> None:
    """Write the enriched signal to BigQuery."""
    try:
        client    = bigquery.Client(project=GCP_PROJECT_ID)
        table_ref = f"{GCP_PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}"

        row = {
            "timestamp"   : payload["timestamp"],
            "trading_pair": payload["trading_pair"],
            "price"       : payload["price"],
            "rsi"         : payload.get("rsi"),
            "atr"         : payload.get("atr"),
            "direction"   : signal.get("direction"),
            "confidence"  : signal.get("confidence"),
            "stop_loss"   : signal.get("stop_loss"),
            "environment" : ENVIRONMENT,
        }

        errors = client.insert_rows_json(table_ref, [row])
        if errors:
            logger.error(f"BigQuery insert errors: {errors}")
        else:
            logger.info(f"Archived signal to BigQuery: {table_ref}")

    except Exception as e:
        logger.error(f"BigQuery archival failed: {e}")


# ── Telegram alert ─────────────────────────────────────────

def send_telegram_alert(payload: dict, signal: dict) -> None:
    """Send a Markdown formatted alert to Telegram."""
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
        logger.warning("Telegram not configured — skipping alert")
        return

    try:
        import urllib.request

        direction  = signal["direction"]
        confidence = signal["confidence"]
        price      = payload["price"]
        stop_loss  = signal["stop_loss"]
        pair       = payload["trading_pair"]
        rsi        = payload.get("rsi", "N/A")
        emoji      = "🟢" if direction == "LONG" else "🔴"

        message = (
            f"{emoji} *{direction} Signal — {pair}*\n\n"
            f"💰 *Entry Price:* `{price}`\n"
            f"🛑 *Stop Loss:* `{stop_loss}`\n"
            f"📊 *Confidence:* `{confidence}%`\n"
            f"📈 *RSI:* `{rsi}`\n"
            f"🌍 *Environment:* `{ENVIRONMENT}`\n"
            f"🕐 *Time:* `{payload['timestamp']}`"
        )

        url  = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = json.dumps({
            "chat_id"    : TELEGRAM_CHAT_ID,
            "text"       : message,
            "parse_mode" : "Markdown",
        }).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST"
        )

        with urllib.request.urlopen(req, timeout=10) as resp:
            logger.info(f"Telegram alert sent — status {resp.status}")

    except Exception as e:
        logger.error(f"Telegram alert failed: {e}")


# ── Cloud Function entry point ─────────────────────────────

@functions_framework.cloud_event
def handler(cloud_event):
    """
    Main Cloud Function entry point.
    Triggered by Pub/Sub push subscription.
    """
    try:
        # Decode the Pub/Sub message
        pubsub_message = cloud_event.data["message"]
        raw_data       = base64.b64decode(pubsub_message["data"]).decode("utf-8")
        payload        = json.loads(raw_data)

        logger.info(f"Received message for {payload.get('trading_pair')} at {payload.get('timestamp')}")

        # ── deduplication ──────────────────────────────────
        dedup_id = payload.get("dedup_id", "")
        if dedup_id and dedup_id in _seen_dedup_ids:
            logger.warning(f"Duplicate message detected — dedup_id={dedup_id} — skipping")
            return

        if dedup_id:
            _seen_dedup_ids.add(dedup_id)
            # Keep the set bounded — remove oldest if over 1000 entries
            if len(_seen_dedup_ids) > 1000:
                _seen_dedup_ids.pop()

        # ── load model ─────────────────────────────────────
        model = load_model()

        # ── run inference ──────────────────────────────────
        features = payload.get("features", [])
        signal   = run_inference(model, features)

        # ── calculate stop loss ────────────────────────────
        signal["stop_loss"] = calculate_stop_loss(
            price     = payload["price"],
            atr       = payload.get("atr", 0),
            direction = signal["direction"],
        )

        logger.info(
            f"Signal: {signal['direction']} | "
            f"confidence={signal['confidence']}% | "
            f"stop_loss={signal['stop_loss']}"
        )

        # ── archive to BigQuery ────────────────────────────
        archive_to_bigquery(payload, signal)

        # ── send Telegram alert if confidence > 80% ────────
        if signal["confidence"] > 80:
            logger.info("Confidence > 80% — sending Telegram alert")
            send_telegram_alert(payload, signal)
        else:
            logger.info(f"Confidence {signal['confidence']}% below threshold — no alert sent")

    except Exception as e:
        logger.error(f"Signal processing failed: {e}", exc_info=True)
        raise