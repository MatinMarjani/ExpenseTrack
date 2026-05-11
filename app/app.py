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

    # #8 – net worth trend (monthly cumulative)
    trend = query("""
        WITH monthly_delta AS (
            SELECT
                DATE_TRUNC('month', t.transaction_date) AS month_start,
                SUM(CASE t.type
                    WHEN 'income'  THEN  t.amount
                    WHEN 'expense' THEN -t.amount
                    ELSE 0
                END) AS delta
            FROM Transactions t
            JOIN Accounts a ON a.account_id = t.account_id
            WHERE a.user_id = %s
            GROUP BY DATE_TRUNC('month', t.transaction_date)
        ),
        initial AS (
            SELECT COALESCE(SUM(initial_balance), 0) AS total
            FROM Accounts WHERE user_id = %s
        )
        SELECT
            TO_CHAR(m.month_start, 'Mon YYYY') AS label,
            ROUND((i.total + SUM(m.delta) OVER (ORDER BY m.month_start))::numeric, 2) AS net_worth
        FROM monthly_delta m, initial i
        ORDER BY m.month_start
    """, (uid, uid))

    trend_labels = [row['label']     for row in trend]
    trend_data   = [float(row['net_worth']) for row in trend]

    return render_template('dashboard.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        accounts=accounts, net_worth=net_worth,
        trend_labels=trend_labels, trend_data=trend_data)


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

    start_date  = request.args.get('start_date')  or None
    end_date    = request.args.get('end_date')    or None
    tag_id      = request.args.get('tag_id',      '')
    category_id = request.args.get('category_id', '')

    # Scope dropdowns to transactions visible in this account (both legs)
    tags = query("""
        SELECT DISTINCT tg.tag_id, tg.name
        FROM Tags tg
        JOIN TransactionTags tt ON tt.tag_id      = tg.tag_id
        JOIN Transactions     t  ON t.transaction_id = tt.transaction_id
        WHERE t.account_id = %s
           OR (t.counterparty_account_id = %s AND t.type = 'transfer')
        ORDER BY tg.name
    """, (account_id, account_id))

    categories = query("""
        SELECT DISTINCT c.category_id, c.name
        FROM Categories  c
        JOIN Transactions t ON t.category_id = c.category_id
        WHERE t.account_id = %s
           OR (t.counterparty_account_id = %s AND t.type = 'transfer')
        ORDER BY c.name
    """, (account_id, account_id))

    date_filter = ""
    date_params = []
    if start_date:
        date_filter += " AND t.transaction_date >= %s"
        date_params.append(start_date)
    if end_date:
        date_filter += " AND t.transaction_date <= %s"
        date_params.append(end_date)

    tag_filter = ""
    tag_params = []
    if tag_id:
        tag_filter = " AND EXISTS (SELECT 1 FROM TransactionTags tt WHERE tt.transaction_id = t.transaction_id AND tt.tag_id = %s)"
        tag_params = [int(tag_id)]

    category_filter = ""
    category_params = []
    if category_id:
        category_filter = " AND t.category_id = %s"
        category_params = [int(category_id)]

    # Q9 + Q5 – ledger with transfer visibility, date/tag/category filters, category & tag columns
    txns = query(f"""
        WITH ledger AS (
            -- Outgoing: income, expense, and outgoing transfers
            SELECT
                t.transaction_id,
                t.transaction_date,
                t.type,
                t.amount,
                t.description,
                CASE WHEN t.type = 'transfer'
                     THEN 'To: ' || cp.name
                     ELSE NULL
                END                                        AS transfer_label,
                FALSE                                      AS incoming,
                CASE t.type
                    WHEN 'income'   THEN  t.amount
                    WHEN 'expense'  THEN -t.amount
                    WHEN 'transfer' THEN -t.amount
                END                                        AS signed_amount,
                c.name                                     AS category,
                (SELECT STRING_AGG(tg.name, ', ' ORDER BY tg.name)
                 FROM TransactionTags tt2
                 JOIN Tags tg ON tg.tag_id = tt2.tag_id
                 WHERE tt2.transaction_id = t.transaction_id) AS tag_names
            FROM Transactions t
            LEFT JOIN Accounts   cp ON cp.account_id  = t.counterparty_account_id
            LEFT JOIN Categories c  ON c.category_id  = t.category_id
            WHERE t.account_id = %s{date_filter}{tag_filter}{category_filter}

            UNION ALL

            -- Incoming: transfer legs where this account is the counterparty
            SELECT
                t.transaction_id,
                t.transaction_date,
                t.type,
                t.amount,
                t.description,
                'From: ' || src.name                       AS transfer_label,
                TRUE                                       AS incoming,
                t.amount                                   AS signed_amount,
                c.name                                     AS category,
                (SELECT STRING_AGG(tg.name, ', ' ORDER BY tg.name)
                 FROM TransactionTags tt2
                 JOIN Tags tg ON tg.tag_id = tt2.tag_id
                 WHERE tt2.transaction_id = t.transaction_id) AS tag_names
            FROM Transactions t
            JOIN Accounts     src ON src.account_id = t.account_id
            LEFT JOIN Categories c ON c.category_id = t.category_id
            WHERE t.counterparty_account_id = %s
              AND t.type = 'transfer'{date_filter}{tag_filter}{category_filter}
        )
        SELECT
            l.transaction_date,
            l.type,
            l.amount,
            l.description,
            l.transfer_label,
            l.incoming,
            l.category,
            l.tag_names,
            a.initial_balance + SUM(l.signed_amount)
                OVER (ORDER BY l.transaction_date, l.transaction_id) AS running_balance
        FROM ledger l
        CROSS JOIN (SELECT initial_balance FROM Accounts WHERE account_id = %s) a
        ORDER BY l.transaction_date, l.transaction_id
    """, (account_id, *date_params, *tag_params, *category_params,
          account_id, *date_params, *tag_params, *category_params,
          account_id))

    show_balance = not (start_date or end_date or tag_id or category_id)

    total_in  = sum(float(t['amount']) for t in txns
                    if t['type'] == 'income' or (t['type'] == 'transfer' and t['incoming']))
    total_out = sum(float(t['amount']) for t in txns
                    if not (t['type'] == 'income' or (t['type'] == 'transfer' and t['incoming'])))
    net = total_in - total_out

    return render_template('transactions.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        accounts=accounts, account_id=account_id, transactions=txns,
        start_date=start_date or '', end_date=end_date or '',
        tags=tags, tag_id=tag_id,
        categories=categories, category_id=category_id,
        show_balance=show_balance,
        total_in=total_in, total_out=total_out, net=net)


# ── Spending ──────────────────────────────────────────────────────────────────

@app.route('/spending')
def spending():
    uid = current_user_id()

    start_date = request.args.get('start_date') or None
    end_date   = request.args.get('end_date')   or None

    date_filter = ""
    date_params = []
    if start_date:
        date_filter += " AND t.transaction_date >= %s"
        date_params.append(start_date)
    if end_date:
        date_filter += " AND t.transaction_date <= %s"
        date_params.append(end_date)
    has_filter = bool(start_date or end_date)

    # Q10 – category breakdown with percentages (all-time or filtered)
    breakdown = query(f"""
        SELECT
            c.name          AS category,
            SUM(t.amount)   AS category_total,
            ROUND(100.0 * SUM(t.amount) / SUM(SUM(t.amount)) OVER (), 2) AS percentage
        FROM Transactions t
        JOIN Accounts   a ON a.account_id  = t.account_id
        JOIN Categories c ON c.category_id = t.category_id
        WHERE a.user_id = %s
          AND t.type    = 'expense'
          {date_filter}
        GROUP BY c.name
        ORDER BY category_total DESC
    """, (uid, *date_params))

    # Q4 – top 5 categories (this month, or selected period)
    if has_filter:
        top_filter = date_filter
        top_params = (uid, *date_params)
    else:
        top_filter = " AND DATE_TRUNC('month', t.transaction_date) = DATE_TRUNC('month', CURRENT_DATE)"
        top_params = (uid,)

    top_month = query(f"""
        SELECT c.name AS category, SUM(t.amount) AS total_spent
        FROM Transactions t
        JOIN Accounts   a ON a.account_id  = t.account_id
        JOIN Categories c ON c.category_id = t.category_id
        WHERE a.user_id = %s
          AND t.type    = 'expense'
          {top_filter}
        GROUP BY c.name
        ORDER BY total_spent DESC
        LIMIT 5
    """, top_params)

    top_label       = "Top Categories (Selected Period)"    if has_filter else "Top Categories This Month"
    breakdown_label = "Spending Breakdown (Selected Period)" if has_filter else "All-Time Spending Breakdown"

    _palette = [
        '#dc3545','#fd7e14','#ffc107','#198754','#0d6efd',
        '#6f42c1','#d63384','#20c997','#0dcaf0','#adb5bd',
    ]
    chart_labels = [row['category'] for row in breakdown]
    chart_data   = [float(row['category_total']) for row in breakdown]
    chart_colors = [_palette[i % len(_palette)] for i in range(len(breakdown))]

    return render_template('spending.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        breakdown=breakdown, top_month=top_month,
        start_date=start_date or '', end_date=end_date or '',
        top_label=top_label, breakdown_label=breakdown_label,
        chart_labels=chart_labels, chart_data=chart_data, chart_colors=chart_colors)


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

    month_names = ['','Jan','Feb','Mar','Apr','May','Jun',
                   'Jul','Aug','Sep','Oct','Nov','Dec']
    chart_labels   = [f"{month_names[r['month']]} {r['year']}" for r in rows]
    chart_income   = [float(r['total_income'])   for r in rows]
    chart_expenses = [float(r['total_expenses']) for r in rows]

    return render_template('monthly.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        monthly_data=rows,
        chart_labels=chart_labels, chart_income=chart_income, chart_expenses=chart_expenses)


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

    # Q7 – accounts with no transactions at all (either as source or counterparty)
    idle = query("""
        SELECT a.name AS account_name, a.type
        FROM   Accounts a
        WHERE  a.user_id = %s
          AND  NOT EXISTS (
              SELECT 1 FROM Transactions t
              WHERE  t.account_id = a.account_id
                 OR  t.counterparty_account_id = a.account_id
          )
        ORDER  BY a.name
    """, (uid,))

    return render_template('insights.html',
        users=get_users(), uid=uid, user_name=get_user_name(uid),
        negative=negative, coverage=coverage, unused=unused, idle=idle)


# ── Run ───────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    app.run(debug=True)
