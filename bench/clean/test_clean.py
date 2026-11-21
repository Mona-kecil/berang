"""Input text -> what the voice should be given. Run: python3 clean/test_clean.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from clean import prepare

CASES = [
    # money, percent, scale
    ("Dr. Patel raised $3.5M in March, roughly 40% more than last year.",
     "Doctor Patel raised three point five million dollars in March, roughly forty percent more than last year."),
    ("It costs $4.99 or €12.", "It costs four dollars and ninety-nine cents or twelve euros."),
    ("Revenue hit $1,250,000 last year.", "Revenue hit one million two hundred fifty thousand dollars last year."),
    ("Growth was ~12.5% this quarter.", "Growth was about twelve point five percent this quarter."),
    # dates and times
    ("The meeting starts at 10:45 AM on 2026-11-22, e.g. right after standup.",
     "The meeting starts at ten forty-five A M on November twenty-second, twenty twenty-six, for example, right after standup."),
    ("Lunch at 12:05 pm, dinner at 7:00.", "Lunch at twelve oh five P M, dinner at seven o'clock."),
    ("She was born in 1987 and moved in 2004.", "She was born in nineteen eighty-seven and moved in two thousand four."),
    ("It happened on the 21st and the 3rd.", "It happened on the twenty-first and the third."),
    # URLs, emails, code, ids
    ("Download version 2.1.4 from https://example.com/docs before Friday.",
     "Download version two point one point four from link to example dot com before Friday."),
    ("See www.github.com/anomalyco/hex for details.", "See link to github dot com for details."),
    ("Docs live at docs.python.org/3/library.", "Docs live at link to docs dot python dot org."),
    ("Email me at jane.doe@example.com today.", "Email me at an email address today."),
    ("Run `npm install` first.", "Run npm install first."),
    ("Commit 3f9a2c1e8b7d fixed it.", "Commit fixed it."),
    ("Use v3.0.1 now.", "Use version three point zero point one now."),
    # units, multipliers, dims
    ("Call the API 3x, then wait 250 ms and retry.", "Call the API three times, then wait two hundred fifty milliseconds and retry."),
    ("A 1920x1080 screen weighs 1.2 kg.", "A one thousand nine hundred twenty by one thousand eighty screen weighs one point two kilograms."),
    ("It runs at 3.2 GHz and 72 °F.", "It runs at three point two gigahertz and seventy-two degrees Fahrenheit."),
    # abbreviations
    ("She lives at 221B Baker St., about 3.2 km from the station.",
     "She lives at two hundred twenty-one B Baker Street, about three point two kilometers from the station."),
    ("We flew to St. Louis on Main St. yesterday.", "We flew to Saint Louis on Main Street yesterday."),
    ("Mr. Smith vs. Mrs. Jones, etc.", "Mister Smith versus Missus Jones, et cetera"),
    ("The U.S. economy grew.", "The U S economy grew."),
    ("Ticket No. 5 and issue #42.", "Ticket number five and issue number forty-two."),
    # cleanup
    ("Paris is the capital of France.[1] It is large.[citation needed]",
     "Paris is the capital of France. It is large."),
    ("Read the [setup guide](https://x.com/setup) and see ![logo](a.png).", "Read the setup guide and see image, logo."),
    ("This is **very** important 🎉.", "This is very important ."),
    ("The infor-\nmation was\nsplit across lines.", "The information was split across lines."),
    ("Order 48213377 shipped.", "Order four eight two one three three seven seven shipped."),
    ("Tom & Jerry → friends", "Tom and Jerry to friends"),
    ("It is 330 m tall.", "It is three hundred thirty meters tall."),
    ("SAN FRANCISCO (Nov. 21) — news.", "SAN FRANCISCO (November twenty-first) — news."),
    ("Due May 3, 2027.", "Due May third, twenty twenty-seven."),
    ("Built with ❤️ by us.", "Built with love by us."),
    ("Fixes #1902.", "Fixes number nineteen oh two."),
]

CHUNK_CASES = [
    # abbreviations must not split sentences; the first long sentence splits at a clause for fast start
    ("Dr. Smith arrived. He sat down.", ["Doctor Smith arrived.", "He sat down."]),
    ("Most people read faster than they can listen, but listening has one advantage reading never will. Short.",
     ["Most people read faster than they can listen,", "but listening has one advantage reading never will.", "Short."]),
    ("# Title\n\nFirst para here.\n\n- item one\n- item two", ["Title", "First para here.", "item one", "item two"]),
    ("The Eiffel Tower was completed on 1889-03-31 for the World's Fair, in Paris.",
     ["The Eiffel Tower was completed on March thirty-first, eighteen eighty-nine for the World's Fair, in Paris."]),
    ("1. Run it\n2. Open the app", ["Run it", "Open the app"]),
    ("```\ncode here\n```\nAfter code.", ["Code block.", "After code."]),
]

fails = 0
for src, want in CASES:
    got = " ".join(c.text for c in prepare(src).chunks)
    if got != want:
        fails += 1
        print(f"FAIL\n  in:   {src!r}\n  want: {want!r}\n  got:  {got!r}")
for src, want in CHUNK_CASES:
    got = [c.text for c in prepare(src).chunks]
    if got != want:
        fails += 1
        print(f"FAIL chunks\n  in:   {src!r}\n  want: {want!r}\n  got:  {got!r}")

# highlight mapping: every chunk's source span must cover the source text it was made from
p = prepare("Dr. Patel raised $3.5M. Visit https://example.com/docs now.")
spans = [(c.text, p.segments and "Dr. Patel raised $3.5M. Visit https://example.com/docs now."[c.src_start:c.src_end]) for c in p.chunks]
want_spans = [("Doctor Patel raised three point five million dollars.", "Dr. Patel raised $3.5M."),
              ("Visit link to example dot com now.", "Visit https://example.com/docs now.")]
if spans != want_spans:
    fails += 1
    print(f"FAIL spans\n  want: {want_spans}\n  got:  {spans}")

total = len(CASES) + len(CHUNK_CASES) + 1
print(f"{total - fails}/{total} passed")
sys.exit(1 if fails else 0)
