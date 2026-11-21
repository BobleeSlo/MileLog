#!/usr/bin/env python3
"""Grant complimentary Paid entitlements to beta testers (KTD12).

During the beta every tester gets a `complimentary` row whose expiry sits well
past the expected launch, so a slipped App Review never drops testers to Free.
At launch the free-year rows are granted first, before any beta row expires.

The secret key is read from the environment only — never pass it on the command
line or commit it (any .env file is git-ignored):

    export SUPABASE_URL=https://rjkohvddlenyeywhxulc.supabase.co
    export SUPABASE_SERVICE_ROLE_KEY=...        # Supabase dashboard > API keys

Usage:
    python3 tools/grant_entitlement.py --tag beta-2026 --until 2027-06-30 a@x.com b@y.com
    python3 tools/grant_entitlement.py --tag tester-year --days 365 --emails testers.txt
    ... add --apply to write; without it this is a dry run that changes nothing.

Rules: only confirmed email addresses get a row, at most one row per user and
grant tag (a second run skips them), and the expiry is capped at two years.
"""

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

MAX_DAYS = 730


def request(method, url, key, body=None, prefer=None):
    headers = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as res:
        raw = res.read()
        return json.loads(raw) if raw else None


def all_users(base, key):
    """Every Auth user, keyed by lowercased email."""
    users, page = {}, 1
    while True:
        batch = request("GET", f"{base}/auth/v1/admin/users?page={page}&per_page=1000", key)["users"]
        for u in batch:
            if u.get("email"):
                users[u["email"].lower()] = u
        if len(batch) < 1000:
            return users
        page += 1


def expiry(args, now):
    if args.until:
        end = dt.datetime.fromisoformat(args.until).replace(tzinfo=dt.timezone.utc)
    else:
        end = now + dt.timedelta(days=args.days)
    cap = now + dt.timedelta(days=MAX_DAYS)
    if end > cap:
        print(f"Expiry capped at {cap.date()} (at most {MAX_DAYS} days).")
        end = cap
    if end <= now:
        sys.exit("The expiry is in the past.")
    return end


def read_emails(args):
    emails = list(args.addresses)
    if args.emails:
        with open(args.emails) as f:
            emails += [line.strip() for line in f if line.strip() and not line.startswith("#")]
    return sorted({e.lower() for e in emails})


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addresses", nargs="*", help="tester email addresses")
    parser.add_argument("--emails", help="file with one email per line")
    parser.add_argument("--tag", required=True, help="grant tag, e.g. beta-2026 or tester-year")
    when = parser.add_mutually_exclusive_group(required=True)
    when.add_argument("--until", help="expiry date, YYYY-MM-DD")
    when.add_argument("--days", type=int, help="expiry in days from now")
    parser.add_argument("--apply", action="store_true", help="write the rows (default: dry run)")
    args = parser.parse_args()

    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not base or not key:
        sys.exit("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.")

    emails = read_emails(args)
    if not emails:
        sys.exit("No email addresses given.")
    now = dt.datetime.now(dt.timezone.utc)
    end = expiry(args, now)
    users = all_users(base, key)

    granted = skipped = 0
    for email in emails:
        user = users.get(email)
        if not user:
            print(f"skip  {email}: no account")
            skipped += 1
            continue
        if not user.get("email_confirmed_at"):
            print(f"skip  {email}: email not confirmed")
            skipped += 1
            continue
        query = urllib.parse.urlencode({"user_id": f"eq.{user['id']}", "grant_tag": f"eq.{args.tag}", "select": "id"})
        if request("GET", f"{base}/rest/v1/entitlements?{query}", key):
            print(f"skip  {email}: already has '{args.tag}'")
            skipped += 1
            continue
        row = {"user_id": user["id"], "source": "complimentary", "status": "active",
               "expires_at": end.isoformat(), "grant_tag": args.tag}
        if args.apply:
            request("POST", f"{base}/rest/v1/entitlements", key, row, prefer="return=minimal")
            print(f"grant {email}: Paid until {end.date()} ({args.tag})")
        else:
            print(f"would grant {email}: Paid until {end.date()} ({args.tag})")
        granted += 1

    print(f"\n{granted} {'granted' if args.apply else 'to grant'}, {skipped} skipped."
          + ("" if args.apply else " Dry run — add --apply to write."))


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        sys.exit(f"Supabase answered {e.code}: {e.read().decode(errors='replace')}")
