import psycopg2
import psycopg2.extras

# ── Database connection settings ─────────────────────────────────────────────
DB_CONFIG = {
    'dbname':   'expensetrack',
    'user':     'postgres',
    'password': '13791346',
    'host':     'localhost',
    'port':     5432,
}


def _connect():
    return psycopg2.connect(**DB_CONFIG)


def query(sql, params=None):
    """Run a SELECT and return all rows as a list of dicts."""
    conn = _connect()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            return cur.fetchall()
    finally:
        conn.close()


def execute(sql, params=None):
    """Run a write query (INSERT/UPDATE/DELETE) and commit. Returns rows for RETURNING clauses."""
    conn = _connect()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            conn.commit()
            if cur.description:
                return cur.fetchall()
            return []
    finally:
        conn.close()
