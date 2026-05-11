from flask import Flask, render_template, request
from db import query

app = Flask(__name__)


# ── Helpers ───────────────────────────────────────────────────────────────────

def current_user_id():
    return int(request.args.get('user_id', 1))

def get_users():
    return query("SELECT user_id, username, full_name FROM Users ORDER BY user_id")

def get_user_name(user_id):
    rows = query("SELECT full_name FROM Users WHERE user_id = %s", (user_id,))
    return rows[0]['full_name'] if rows else 'Unknown'


# ── Dashboard ─────────────────────────────────────────────────────────────────

@app.route('/')
def dashboard():
    uid = current_user_id()

    accounts = query("""
        SELECT name, type, initial_balance, current_balance
        FROM   AccountBalances
        WHERE  user_id = %s
        ORDER  BY name
    """, (uid,))

    net_worth_row = query("""
        SELECT COALESCE(SUM(current_balance), 0) AS net_worth
        FROM   AccountBalances
        WHERE  user_id = %s
    """, (uid,))
    net_worth = net_worth_row[0]['net_worth']

    return render_template('dashboard.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        accounts=accounts, net_worth=net_worth)


# ── Transactions ──────────────────────────────────────────────────────────────

@app.route('/transactions')
def transactions():
    uid = current_user_id()

    accounts = query("""
        SELECT account_id, name
        FROM   Accounts
        WHERE  user_id = %s
        ORDER  BY name
    """, (uid,))

    account_id = int(request.args.get('account_id',
                     accounts[0]['account_id'] if accounts else 1))

    # Q9 – running balance ledger
    txns = query("""
        SELECT
            t.transaction_date,
            t.type,
            t.amount,
            t.description,
            a.initial_balance + SUM(
                CASE t.type
                    WHEN 'income'   THEN  t.amount
                    WHEN 'expense'  THEN -t.amount
                    WHEN 'transfer' THEN -t.amount
                END
            ) OVER (ORDER BY t.transaction_date, t.transaction_id) AS running_balance
        FROM Transactions t
        JOIN Accounts a ON a.account_id = t.account_id
        WHERE t.account_id = %s
        ORDER BY t.transaction_date, t.transaction_id
    """, (account_id,))

    return render_template('transactions.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        accounts=accounts, account_id=account_id, transactions=txns)


# ── Spending ──────────────────────────────────────────────────────────────────

@app.route('/spending')
def spending():
    uid = current_user_id()

    # Q10 – all-time category breakdown with percentages
    breakdown = query("""
        SELECT
            c.name          AS category,
            SUM(t.amount)   AS category_total,
            ROUND(100.0 * SUM(t.amount) / SUM(SUM(t.amount)) OVER (), 2) AS percentage
        FROM Transactions t
        JOIN Accounts   a ON a.account_id  = t.account_id
        JOIN Categories c ON c.category_id = t.category_id
        WHERE a.user_id = %s
          AND t.type    = 'expense'
        GROUP BY c.name
        ORDER BY category_total DESC
    """, (uid,))

    # Q4 – top 5 categories this month
    top_month = query("""
        SELECT c.name AS category, SUM(t.amount) AS total_spent
        FROM Transactions t
        JOIN Accounts   a ON a.account_id  = t.account_id
        JOIN Categories c ON c.category_id = t.category_id
        WHERE a.user_id = %s
          AND t.type    = 'expense'
          AND DATE_TRUNC('month', t.transaction_date) = DATE_TRUNC('month', CURRENT_DATE)
        GROUP BY c.name
        ORDER BY total_spent DESC
        LIMIT 5
    """, (uid,))

    return render_template('spending.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        breakdown=breakdown, top_month=top_month)


# ── Monthly report ────────────────────────────────────────────────────────────

@app.route('/monthly')
def monthly():
    uid = current_user_id()

    # Q2 + Q8 combined – monthly summary
    rows = query("""
        SELECT
            EXTRACT(YEAR  FROM t.transaction_date)::int AS year,
            EXTRACT(MONTH FROM t.transaction_date)::int AS month,
            COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'income'),  0) AS total_income,
            COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'expense'), 0) AS total_expenses
        FROM Transactions t
        JOIN Accounts a ON a.account_id = t.account_id
        WHERE a.user_id = %s
        GROUP BY year, month
        ORDER BY year, month
    """, (uid,))

    return render_template('monthly.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        monthly_data=rows)


# ── Insights ──────────────────────────────────────────────────────────────────

@app.route('/insights')
def insights():
    uid = current_user_id()

    # Q6 – negative balance accounts
    negative = query("""
        SELECT name AS account_name, type, current_balance
        FROM   AccountBalances
        WHERE  user_id = %s AND current_balance < 0
        ORDER  BY current_balance
    """, (uid,))

    # Q11 – receipt coverage per account
    coverage = query("""
        SELECT
            a.name                                            AS account,
            COUNT(t.transaction_id)                           AS total,
            COUNT(r.receipt_id)                               AS with_receipt,
            COUNT(t.transaction_id) - COUNT(r.receipt_id)    AS without_receipt
        FROM Accounts     a
        JOIN Transactions t  ON t.account_id      = a.account_id
        LEFT JOIN Receipts r ON r.transaction_id  = t.transaction_id
        WHERE a.user_id = %s
        GROUP BY a.account_id, a.name
        ORDER BY a.name
    """, (uid,))

    # Q15 – categories never used
    unused = query("""
        SELECT c.name, c.type
        FROM   Categories c
        WHERE  c.user_id = %s
        EXCEPT
        SELECT c.name, c.type
        FROM   Categories  c
        JOIN   Transactions t ON t.category_id = c.category_id
        WHERE  c.user_id = %s
        ORDER  BY type, name
    """, (uid, uid))

    # Q7 – accounts with no transactions at all
    idle = query("""
        SELECT a.name AS account_name, a.type
        FROM   Accounts a
        WHERE  a.user_id = %s
          AND  NOT EXISTS (
              SELECT 1 FROM Transactions t WHERE t.account_id = a.account_id
          )
        ORDER  BY a.name
    """, (uid,))

    return render_template('insights.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        negative=negative, coverage=coverage, unused=unused, idle=idle)


# ── Run ───────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    app.run(debug=True)
