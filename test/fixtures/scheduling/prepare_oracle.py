"""Independent G03 examples, not a Vital implementation or runtime test.

Python standard library only. Run without arguments to check the checked-in JSON;
use --write to regenerate it after reviewing changed expected facts. Literal
expected outcomes below are compared with independent arithmetic before export.
Calendar operations use dates; elapsed operations always use UTC instants.
"""

import argparse
import calendar
import json
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import TZPATH, ZoneInfo


UTC = timezone.utc
CASES = []


def day(value):
    return date.fromisoformat(value)


def instant(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)


def iso(value):
    return value.isoformat().replace("+00:00", "Z")


def record(key, ticket, status, inputs, expected, calculated, basis):
    if calculated != expected:
        raise ValueError(f"{key}: calculated {calculated!r}, expected {expected!r}")
    CASES.append(dict(id=key, ticket=ticket, status=status, inputs=inputs,
                      expected=expected, verification_basis=basis))


def dates(start, end):
    a, b = day(start), day(end)
    if b < a or (b - a).days > 366:
        raise ValueError("oracle range must be ordered and at most 366 days")
    return [a + timedelta(days=i) for i in range((b - a).days)]


def calendar_days(anchor, step, start, end):
    if step <= 0:
        raise ValueError("step must be positive")
    a = day(anchor)
    return [str(d) for d in dates(start, end) if d >= a and (d - a).days % step == 0]


def selected_weeks(anchor, step, weekdays, start, end):
    a = day(anchor)
    if a.weekday() != 0 or step <= 0:
        raise ValueError("explicit Monday anchor and positive step required")
    return [str(d) for d in dates(start, end)
            if d >= a and ((d - a).days // 7) % step == 0 and d.weekday() in weekdays]


def monthly(year, month, nominal_day, step, months, policy):
    if not 1 <= nominal_day <= 31 or step <= 0 or not 0 <= months <= 60:
        raise ValueError("invalid bounded monthly fixture")
    if policy not in ("last_day", "omit"):
        raise ValueError("explicit missing-date policy required")
    result = []
    for i in range(months):
        number = year * 12 + month - 1 + step * i
        y, m = divmod(number, 12)
        m += 1
        last = calendar.monthrange(y, m)[1]
        if nominal_day <= last or policy == "last_day":
            result.append(str(date(y, m, min(nominal_day, last))))
    return result


def candidates(local, zone):
    wall, location = datetime.fromisoformat(local), ZoneInfo(zone)
    result = set()
    for fold in (0, 1):
        utc = wall.replace(tzinfo=location, fold=fold).astimezone(UTC)
        if utc.astimezone(location).replace(tzinfo=None) == wall:
            result.add(iso(utc))
    return sorted(result)


def actual_next(records, hours):
    # P4 branch only. Qualification is supplied explicitly, not inferred.
    valid = [r for r in records if r.get("qualifies") and not r.get("voided")]
    if not valid:
        return dict(anchor=None, next=None)
    latest = max(instant(r["actual"]) for r in valid)
    chosen = min((r for r in valid if instant(r["actual"]) == latest), key=lambda r: r["id"])
    return dict(anchor=chosen["id"], next=iso(latest + timedelta(hours=hours)))


def next_calendar_day(anchor, step, cursor):
    if step <= 0:
        raise ValueError("step must be positive")
    a, c = day(anchor), day(cursor)
    ordinal = max(0, (c-a).days // step + 1)
    return str(a + timedelta(days=ordinal*step))


def build():
    CASES.clear()
    fixed = "accepted_family_explicit_input"
    conditional = "conditional_proposal_not_accepted"
    inherited = "existing_daily_engineering_policy"
    record("C01", 8, fixed, dict(weekdays=[0, 3], start="2026-10-19", end="2026-11-01"),
           ["2026-10-19", "2026-10-22", "2026-10-26", "2026-10-29"],
           [str(d) for d in dates("2026-10-19", "2026-11-01") if d.weekday() in (0, 3)],
           "Monday/Thursday calendar lookup; no elapsed spacing implied")
    for key, step, expected in [
            ("C02", 2, ["2026-03-28", "2026-03-30", "2026-04-01"]),
            ("C03", 3, ["2026-12-28", "2026-12-31", "2027-01-03"])]:
        start = "2026-03-28" if step == 2 else "2026-12-28"
        end = "2026-04-02" if step == 2 else "2027-01-04"
        record(key, 8, fixed, dict(anchor=start, every_days=step, start=start, end=end),
               expected, calendar_days(start, step, start, end), "integer civil-day difference from preserved anchor")
    record("C04", 8, conditional, dict(anchor_week="2026-12-28", every_weeks=2,
           weekdays=[0, 3], end="2027-01-15", composition="intersection"),
           ["2026-12-28", "2026-12-31", "2027-01-11", "2027-01-14"],
           selected_weeks("2026-12-28", 2, [0, 3], "2026-12-28", "2027-01-15"),
           "explicit anchored week parity and selected weekdays; locale cannot change anchor")
    for key, year, step, count, policy, expected in [
            ("C05", 2027, 1, 4, "last_day", ["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30"]),
            ("C06", 2027, 1, 5, "omit", ["2027-01-31", "2027-03-31", "2027-05-31"]),
            ("C07", 2028, 1, 3, "last_day", ["2028-01-31", "2028-02-29", "2028-03-31"]),
            ("C08", 2026, 2, 4, "last_day", ["2026-11-30", "2027-01-31", "2027-03-31", "2027-05-31"])]:
        month = 11 if key == "C08" else 1
        record(key, 8, conditional, dict(year=year, month=month, nominal_day=31,
               every_months=step, candidate_months=count, missing_date=policy), expected,
               monthly(year, month, 31, step, count, policy), "month-index arithmetic; nominal day never changes after substitution")
    record("C09", 8, conditional, dict(selector="last Monday", months=["2027-01", "2027-02", "2027-03"]),
           ["2027-01-25", "2027-02-22", "2027-03-29"],
           [str(max(d for d in dates(f"2027-{m:02d}-01", f"2027-{m+1:02d}-01") if d.weekday() == 0)) for m in (1, 2, 3)],
           "independent weekday enumeration, not a missing-day substitute")
    record("C10", 8, conditional, dict(anchor="2028-02-29", every_months=12,
           missing_date="omit", cursor="2028-03-01", preview_end="2028-04-01"),
           dict(range=[], next_date="2032-02-29"),
           dict(range=[], next_date=monthly(2028, 2, 29, 12, 5, "omit")[-1]),
           "2029/2030/2031 non-leap; 2032 leap; separate sparse next beyond empty preview")
    record("C11", 8, conditional, dict(anchor="2028-02-29", every_months=12,
           missing_date="last_day", cursor="2028-03-01"), "2029-02-28",
           monthly(2029, 2, 29, 12, 1, "last_day")[0], "explicit alternate missing-date branch")
    record("B01", 8, fixed, dict(anchor="2000-01-01", every_days=2, cursor="2090-01-01", zone="Etc/UTC", operation="next_date_strict_after"),
           "2090-01-02", next_calendar_day("2000-01-01", 2, "2090-01-01"),
           "90*365+23 = 32873 elapsed calendar days to cursor; next ordinal at 32874; UTC avoids asset extrapolation")
    record("B02", 10, conditional, dict(anchor="2000-01-01", every_days=2, pause_start="2026-01-01", resume="2046-01-01", choice="preserve", zone="Etc/UTC"),
           "2046-01-01", next_calendar_day("2000-01-01", 2, "2045-12-31"),
           "seek to resume-eligible day algebraically; no paused-day materialization")
    rejected = []
    for key, operation in [("zero_interval", lambda: next_calendar_day("2026-01-01", 0, "2026-01-01")),
                           ("negative_interval", lambda: next_calendar_day("2026-01-01", -1, "2026-01-01")),
                           ("unbounded_oracle_range", lambda: dates("2000-01-01", "2090-01-01")),
                           ("missing_month_policy", lambda: monthly(2027, 1, 31, 1, 3, None))]:
        try:
            operation()
        except ValueError:
            rejected.append(key)
    record("B03", 8, "oracle_defensive_validation", dict(invalid=["zero_interval", "negative_interval", "unbounded_oracle_range", "missing_month_policy"]),
           ["zero_interval", "negative_interval", "unbounded_oracle_range", "missing_month_policy"], rejected,
           "bounded reference tool rejects malformed inputs; these are not application product limits")
    for key, local, zone, expected in [
            ("Z01", "2026-03-29T01:30:00", "Europe/London", []),
            ("Z02", "2026-10-25T01:30:00", "Europe/London", ["2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z"]),
            ("Z03", "2026-10-04T02:15:00", "Australia/Lord_Howe", []),
            ("Z04", "2026-04-05T01:45:00", "Australia/Lord_Howe", ["2026-04-04T14:45:00Z", "2026-04-04T15:15:00Z"])]:
        record(key, 8, inherited, dict(local=local, zone=zone), expected, candidates(local, zone),
               "UTC round-trip validates each fold; no constructor normalization or automatic choice")
    record("Z05", 8, inherited, dict(next_local="2026-07-11T08:00:00", local_zone="America/New_York", home_zone="Europe/London"),
           dict(follow_local="2026-07-11T12:00:00Z", fixed_home="2026-07-11T07:00:00Z"),
           dict(follow_local=candidates("2026-07-11T08:00:00", "America/New_York")[0], fixed_home=candidates("2026-07-11T08:00:00", "Europe/London")[0]),
           "same wall time, separately saved plan-zone bases")
    record("Z06", 8, inherited, dict(switch="2026-07-10T09:00:00Z", before="Pacific/Kiritimati", after="Pacific/Honolulu", bucket_progress={"2026-07-09": 2, "2026-07-10": 1}),
           ["2026-07-10", "2026-07-09", "2026-07-10"],
           [str(instant(t).astimezone(ZoneInfo(z)).date()) for t, z in [
               ("2026-07-10T09:00:00Z", "Pacific/Kiritimati"), ("2026-07-10T09:00:00Z", "Pacific/Honolulu"), ("2026-07-10T10:00:00Z", "Pacific/Honolulu")]],
           "date visits reuse original date identity/progress; no third bucket")
    for key, anchor, expected in [
            ("E01", "2026-03-28T22:00:00Z", ["2026-03-28T22:00:00Z", "2026-03-29T04:00:00Z", "2026-03-29T10:00:00Z", "2026-03-29T16:00:00Z"]),
            ("E02", "2026-10-24T21:00:00Z", ["2026-10-24T21:00:00Z", "2026-10-25T03:00:00Z", "2026-10-25T09:00:00Z", "2026-10-25T15:00:00Z"])]:
        record(key, 9, fixed, dict(anchor=anchor, every_hours=6, ordinals=[0, 1, 2, 3]), expected,
               [iso(instant(anchor) + timedelta(hours=6*i)) for i in range(4)],
               "UTC arithmetic: every adjacent gap exactly 21600 seconds across clock transition")
    a1 = dict(id="a1", actual="2026-03-29T06:00:00Z", entered="2026-03-29T06:10:00Z", qualifies=True)
    earlier = dict(id="a0", actual="2026-03-28T23:00:00Z", entered="2026-03-29T07:00:00Z", qualifies=True)
    later = dict(id="a2", actual="2026-03-29T06:30:00Z", qualifies=True)
    for key, records, expected in [
            ("A01", [a1], dict(anchor="a1", next="2026-03-29T12:00:00Z")),
            ("A02", [{**a1, "actual": "2026-03-29T05:00:00Z"}], dict(anchor="a1", next="2026-03-29T11:00:00Z")),
            ("A03", [a1, earlier], dict(anchor="a1", next="2026-03-29T12:00:00Z")),
            ("A04", [a1, later], dict(anchor="a2", next="2026-03-29T12:30:00Z")),
            ("A05", [a1, {**later, "qualifies": False}], dict(anchor="a1", next="2026-03-29T12:00:00Z")),
            ("A06", [a1, {**later, "actual": a1["actual"]}], dict(anchor="a1", next="2026-03-29T12:00:00Z")),
            ("A07", [{**a1, "voided": True}], dict(anchor=None, next=None)),
            ("A08", [a1, {**later, "voided": True}], dict(anchor="a1", next="2026-03-29T12:00:00Z"))]:
        record(key, 9, conditional, dict(records=records, every_hours=6, policy="P4-most-recent-qualifying-actual-single-next"), expected,
               actual_next(records, 6), "max actual instant then smallest stable ID; explicit qualification/voiding; entry time excluded")
    record("A09", 9, conditional, dict(records=[a1], now="2026-03-29T13:00:00Z", every_hours=6, policy="P4-single-next"),
           ["2026-03-29T12:00:00Z"], [actual_next([a1], 6)["next"]],
           "overdue single next remains; no independent 18:00 expectation without another qualifying actual")
    record("P01", 10, conditional, dict(anchor="2026-03-28", every_days=2, resume="2026-04-02", choice="preserve"),
           ["2026-04-03", "2026-04-05"], calendar_days("2026-03-28", 2, "2026-04-02", "2026-04-06"), "anchor parity survives suppression; no catch-up")
    record("P02", 10, conditional, dict(old_anchor="2026-03-28", new_segment="2026-04-02", every_days=2, choice="restart"),
           ["2026-04-02", "2026-04-04", "2026-04-06"], calendar_days("2026-04-02", 2, "2026-04-02", "2026-04-07"), "new segment, old history retained")
    for key, anchor, expected in [("P03", "2026-10-19", ["2026-10-25", "2026-10-26", "2026-10-29", "2026-10-30", "2026-10-31"]),
                                   ("P04", "2026-10-25", ["2026-10-25", "2026-10-26", "2026-10-27", "2026-10-30", "2026-10-31", "2026-11-01"])]:
        record(key, 10, conditional, dict(anchor=anchor, on_days=3, off_days=2, start="2026-10-25", end="2026-11-02"), expected,
               [str(d) for d in dates("2026-10-25", "2026-11-02") if (d-day(anchor)).days % 5 < 3], "calendar modulo block; preserve vs restart use different explicit anchors")
    record("P05", 10, conditional, dict(anchor="2026-10-24T21:00:00Z", pause="2026-10-25T01:00:00Z", resume="2026-10-25T08:00:00Z", choice="preserve", every_hours=6),
           "2026-10-25T09:00:00Z", iso(instant("2026-10-24T21:00:00Z") + timedelta(hours=12)), "03:00 suppressed; ordinal 2 at 09:00 retained")
    record("P06", 10, conditional, dict(resume="2026-10-25T08:00:00Z", first_selected="2026-10-25T08:00:00Z", choice="restart", every_hours=6),
           ["2026-10-25T08:00:00Z", "2026-10-25T14:00:00Z"], [iso(instant("2026-10-25T08:00:00Z")+timedelta(hours=i)) for i in (0, 6)], "resume is not an actual record; first chosen planned anchor is explicit")
    for key, value, expected in [("F01", "2026-03-29", dict(cutoff="2026-03-29T23:00:00Z", hours=23)),
                                  ("F02", "2026-10-25", dict(cutoff="2026-10-26T00:00:00Z", hours=25))]:
        start = candidates(value+"T00:00:00", "Europe/London")[0]
        cutoff = candidates(str(day(value)+timedelta(days=1))+"T00:00:00", "Europe/London")[0]
        record(key, 11, conditional, dict(inclusive_item_end=value, bound_zone="Europe/London"), expected,
               dict(cutoff=cutoff, hours=int((instant(cutoff)-instant(start)).total_seconds()/3600)), "next civil midnight, never midnight plus 24 elapsed hours")
    original = dict(owner="ada", plan="p1", date="2026-10-31", slot="late")
    record("F03", 11, conditional, dict(original=original, original_amount="1 tablet", destination_phase_amount="2 tablets", target="2026-11-01T00:30:00Z", policy="P6-original-amount"),
           dict(original=original, effective="2026-11-01T00:30:00Z", amount="1 tablet", extra_expectations=0),
           dict(original=dict(original), effective=iso(instant("2026-10-31T23:30:00Z")+timedelta(hours=1)), amount="1 tablet", extra_expectations=0),
           "one-hour move; explicit original ownership/amount branch, no destination-phase inheritance")
    record("F04", 11, conditional, dict(end_exclusive="2026-11-01T00:00:00Z", candidates=["2026-10-31T23:30:00Z", "2026-11-01T00:00:00Z", "2026-11-01T00:30:00Z"]),
           [True, False, False], [instant(t)<instant("2026-11-01T00:00:00Z") for t in ["2026-10-31T23:30:00Z", "2026-11-01T00:00:00Z", "2026-11-01T00:30:00Z"]], "hard end excludes boundary and moved target beyond it")
    record("F05", 11, conditional, dict(pause="2026-11-01T00:00:00Z", resume="2026-11-01T01:00:00Z", targets=["2026-11-01T00:00:00Z", "2026-11-01T00:30:00Z", "2026-11-01T01:00:00Z"]),
           [False, False, True], [not (instant("2026-11-01T00:00:00Z") <= instant(t) < instant("2026-11-01T01:00:00Z")) for t in ["2026-11-01T00:00:00Z", "2026-11-01T00:30:00Z", "2026-11-01T01:00:00Z"]], "pause veto after override; resume boundary is active unless ended")
    record("V01", 15, "accepted_event_rule", dict(event_last_date="2026-03-29", zone="Europe/London", item_ongoing=True),
           dict(event_end_exclusive="2026-03-29T23:00:00Z", next_item="2026-03-30T07:00:00Z"),
           dict(event_end_exclusive=candidates("2026-03-30T00:00:00", "Europe/London")[0], next_item=candidates("2026-03-30T08:00:00", "Europe/London")[0]), "event includes final day; independent plan continues")
    return dict(schema="vital-g03-oracle-1", scope="Preparation only. No production resolver, transaction, UI or native delivery evidence.",
                timezone_basis="Host zoneinfo; version is reported by verification, not silently treated as admitted Dart 2026e.", cases=CASES)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    output = Path(__file__).with_name("08-11-expected.json")
    data = build()
    text = json.dumps(data, indent=2, ensure_ascii=False)+"\n"
    if args.write:
        output.write_text(text)
    elif output.read_text() != text:
        raise ValueError("checked-in fixture differs; review before regenerating with --write")
    versions = [p.read_text().splitlines()[0] for root in TZPATH if (p := Path(root)/"tzdata.zi").exists()]
    print(f"PASS: {len(CASES)} independently compared cases; fixture {'written' if args.write else 'matches'}")
    print(f"Host timezone data: {versions or ['unknown']}")
    print("Scope: bounded arithmetic and explicit conditional examples; no app/runtime/gate acceptance.")


if __name__ == "__main__":
    main()
