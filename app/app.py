"""Tiny demo app for the Pilot Light DR project.

GET /        -> records a visit and shows which Region/AZ served it.
               Makes failover visible: the Region changes after DR.
GET /health  -> 200 if the DB is reachable, 503 otherwise
               (used by the ALB target group and the Route 53 health check).
GET /latest  -> newest visit timestamp. After failover, compare it with the
               time of the outage to measure the actual RPO.
"""
import json
import os
import urllib.request
from functools import lru_cache

import boto3
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

REGION = os.environ.get("AWS_REGION", "unknown")


def _imds(path: str) -> str:
    try:
        token_req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        req = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        return urllib.request.urlopen(req, timeout=1).read().decode()
    except Exception:  # noqa: BLE001
        return "unknown"


@lru_cache(maxsize=1)
def _credentials() -> dict:
    sm = boto3.client("secretsmanager", region_name=REGION)
    return json.loads(sm.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])["SecretString"])


def _conn():
    creds = _credentials()
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=creds["username"],
        password=creds["password"],
        connect_timeout=3,
    )


def _ensure_schema(cur):
    cur.execute(
        """CREATE TABLE IF NOT EXISTS visits (
               id         BIGSERIAL PRIMARY KEY,
               region     TEXT NOT NULL,
               az         TEXT NOT NULL,
               created_at TIMESTAMPTZ NOT NULL DEFAULT now()
           )"""
    )


@app.get("/health")
def health():
    try:
        with _conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify(status="ok", region=REGION), 200
    except Exception as exc:  # noqa: BLE001
        return jsonify(status="db_unreachable", error=str(exc)), 503


@app.get("/")
def index():
    az = _imds("placement/availability-zone")
    with _conn() as conn, conn.cursor() as cur:
        _ensure_schema(cur)
        cur.execute("INSERT INTO visits (region, az) VALUES (%s, %s)", (REGION, az))
        cur.execute("SELECT count(*) FROM visits")
        total = cur.fetchone()[0]
    return jsonify(served_by_region=REGION, availability_zone=az, total_visits=total)


@app.get("/latest")
def latest():
    with _conn() as conn, conn.cursor() as cur:
        _ensure_schema(cur)
        cur.execute("SELECT max(created_at), count(*) FROM visits")
        ts, total = cur.fetchone()
    return jsonify(latest_write=ts.isoformat() if ts else None, total_visits=total)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)