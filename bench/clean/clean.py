"""Text cleanup before TTS: one regex pass turns source text into segments that remember where they came from.

prepare(text) -> Prepared(spoken, segments, chunks)
  segment: source span -> spoken string ("" means skipped)
  chunk:   one piece to send to the voice, with its source span (for highlighting)

Stdlib only, so the rule tables port to Swift as-is.
"""
import re
import sys
from dataclasses import dataclass

# ---------- number words ----------
ONES = ("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen "
        "sixteen seventeen eighteen nineteen").split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()
SCALES = ["", "thousand", "million", "billion", "trillion"]
MONTHS = ("January February March April May June July August September October November December").split()


def _under_1000(n):
    out = []
    if n >= 100:
        out += [ONES[n // 100], "hundred"]
        n %= 100
    if n >= 20:
        out.append(TENS[n // 10] + (f"-{ONES[n % 10]}" if n % 10 else ""))
    elif n or not out:
        out.append(ONES[n])
    return " ".join(out)


def int_words(n):
    if n < 0:
        return "minus " + int_words(-n)
    if n < 1000:
        return _under_1000(n)
    parts, i = [], 0
    while n:
        n, r = divmod(n, 1000)
        if r:
            parts.append(_under_1000(r) + (f" {SCALES[i]}" if SCALES[i] else ""))
        i += 1
    return " ".join(reversed(parts))


def digits_words(s):
    return " ".join("oh" if d == "0" else ONES[int(d)] for d in s)


def num_words(s):
    """'1,234.5' -> 'one thousand two hundred thirty-four point five'."""
    s = s.replace(",", "")
    whole, _, frac = s.partition(".")
    out = int_words(int(whole or 0))
    return out + (" point " + " ".join(ONES[int(d)] for d in frac) if frac else "")


def ordinal_words(n):
    w = int_words(n)
    head, sep, last = w.rpartition(" ") if "-" not in w.split(" ")[-1] else w.rpartition("-")
    irregular = {"one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
                 "nine": "ninth", "twelve": "twelfth"}
    if last in irregular:
        last = irregular[last]
    elif last.endswith("y"):
        last = last[:-1] + "ieth"
    else:
        last += "th"
    return head + sep + last


def year_words(n):
    if 2000 <= n <= 2009:
        return "two thousand" + (f" {ONES[n % 10]}" if n % 10 else "")
    hi, lo = divmod(n, 100)
    if lo == 0:
        return f"{int_words(hi)} hundred"
    return f"{int_words(hi)} {'oh ' + ONES[lo] if lo < 10 else int_words(lo)}"


# ---------- rules: (name, pattern, handler(match, src) -> spoken) ----------
CURRENCY = {"$": ("dollar", "dollars", "cent", "cents"), "€": ("euro", "euros", "cent", "cents"),
            "£": ("pound", "pounds", "penny", "pence"), "¥": ("yen", "yen", "", "")}
SCALE = {"k": "thousand", "K": "thousand", "M": "million", "B": "billion", "T": "trillion",
         "thousand": "thousand", "million": "million", "billion": "billion", "trillion": "trillion"}
UNITS = {"ms": ("millisecond", "milliseconds"), "km": ("kilometer", "kilometers"), "cm": ("centimeter", "centimeters"),
         "mm": ("millimeter", "millimeters"), "kg": ("kilogram", "kilograms"), "mg": ("milligram", "milligrams"),
         "lb": ("pound", "pounds"), "lbs": ("pound", "pounds"), "GB": ("gigabyte", "gigabytes"),
         "MB": ("megabyte", "megabytes"), "KB": ("kilobyte", "kilobytes"), "TB": ("terabyte", "terabytes"),
         "Hz": ("hertz", "hertz"), "kHz": ("kilohertz", "kilohertz"), "MHz": ("megahertz", "megahertz"),
         "GHz": ("gigahertz", "gigahertz"), "mph": ("mile per hour", "miles per hour"),
         "km/h": ("kilometer per hour", "kilometers per hour"), "m": ("meter", "meters"), "°C": ("degree Celsius", "degrees Celsius"),
         "°F": ("degree Fahrenheit", "degrees Fahrenheit")}
ABBR = {"Mr.": "Mister", "Mrs.": "Missus", "Ms.": "Miz", "Prof.": "Professor", "Jr.": "Junior", "Sr.": "Senior",
        "vs.": "versus", "etc.": "et cetera", "e.g.": "for example", "i.e.": "that is", "approx.": "approximately",
        "Inc.": "Inc", "Ltd.": "Limited", "Co.": "Co", "Corp.": "Corp", "Fig.": "figure", "Ave.": "Avenue",
        "Blvd.": "Boulevard", "Jan.": "January", "Feb.": "February", "Aug.": "August", "Sept.": "September",
        "Oct.": "October", "Nov.": "November", "Dec.": "December"}
TLD = r"(?:com|org|net|io|dev|ai|app|co|edu|gov|me|xyz|sh|so|gg)"
NUM = r"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?"

EMOJI_WORDS = {"❤": "love", "♥": "love", "👍": "thumbs up"}

OPTIONS = {"urls": "domain"}  # "domain" -> "link to example dot com", "skip" -> ""


def _prev_word(src, i):
    m = re.search(r"(\S+)\s*$", src[:i])
    return m.group(1) if m else ""


def _next_word(src, i):
    m = re.match(r"\s*(\S+)", src[i:])
    return m.group(1) if m else ""


def _domain(url):
    host = re.sub(r"^(?:https?://)?(?:www\.)?", "", url).split("/")[0].split("?")[0]
    return host.replace(".", " dot ")


def _url(m, src):
    return "" if OPTIONS["urls"] == "skip" else f"link to {_domain(m.group(0))}"


def _currency(m, src):
    sym, amount, scale = m.group("sym"), m.group("amt"), m.group("scale")
    one, many, sub1, subn = CURRENCY[sym]
    if scale:
        return f"{num_words(amount)} {SCALE[scale]} {many}"
    whole, _, cents = amount.replace(",", "").partition(".")
    out = f"{int_words(int(whole))} {one if whole == '1' else many}"
    if cents and int(cents) and sub1:
        c = int(cents.ljust(2, "0")[:2])
        out += f" and {int_words(c)} {sub1 if c == 1 else subn}"
    return out


def _percent(m, src):
    return ("about " if m.group("approx") else "") + num_words(m.group("n")) + " percent"


def _month(tok):
    t = tok.rstrip(".")[:3].lower()
    return next(x for x in MONTHS if x[:3].lower() == t)


def _iso_date(m, src):
    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if not (1 <= mo <= 12 and 1 <= d <= 31):
        return m.group(0)
    return f"{MONTHS[mo - 1]} {ordinal_words(d)}, {year_words(y)}"


def _time(m, src):
    h, mi, ap = int(m.group("h")), m.group("m"), m.group("ap")
    out = int_words(h)
    if mi != "00":
        out += " " + (f"oh {ONES[int(mi)]}" if mi[0] == "0" else int_words(int(mi)))
    elif not ap:
        out += " o'clock"
    if ap:
        out += " " + ("A M" if ap[0] in "aA" else "P M")
    return out


def _unit(m, src):
    one, many = UNITS[m.group("u")]
    n = m.group("n")
    return f"{num_words(n)} {one if n == '1' else many}"


def _abbr_dr(m, src):
    nxt = _next_word(src, m.end())
    return "Doctor" if nxt[:1].isupper() else "Drive"


def _abbr_st(m, src):
    prev, nxt = _prev_word(src, m.start()), _next_word(src, m.end())
    if prev[:1].isupper() or prev[:1].isdigit():
        return "Street"
    return "Saint" if nxt[:1].isupper() else "Street"


def _int(m, src):
    s = m.group(0).replace(",", "")
    if len(s) >= 7 and "," not in m.group(0):
        return digits_words(s)
    n = int(s)
    if 1100 <= n <= 2099 and "," not in m.group(0):
        return year_words(n)
    return int_words(n)


RULES = [
    ("code_block", r"(?ms:^```.*?^```[ \t]*$)", lambda m, s: "Code block."),
    ("md_image", r"!\[([^\]]*)\]\([^)]*\)", lambda m, s: f"image, {m.group(1)}" if m.group(1) else ""),
    ("md_link", r"\[([^\]]+)\]\([^)]*\)", lambda m, s: m.group(1)),
    ("footnote", r"\[(?:\d+|[a-z]|citation needed|note \d+)\]", lambda m, s: ""),
    ("inline_code", r"`([^`\n]+)`", lambda m, s: m.group(1) if len(m.group(1).split()) <= 3 else "code"),
    ("email", r"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b", lambda m, s: "an email address"),
    ("url", r"\b(?:https?://|www\.)[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'\"]", _url),
    ("bare_url", rf"\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.{TLD}(?:/[^\s<>()]*[^\s<>().,;:!?'\"])?(?![\w.]*\w)", _url),
    ("hash_id", r"\b(?=[A-Fa-f0-9-]*\d)(?=[A-Fa-f0-9-]*[A-Fa-f])[A-Fa-f0-9]{8,}(?:-[A-Fa-f0-9]{4,})*\b", lambda m, s: ""),
    ("md_heading", r"(?m:^#{1,6}[ \t]+)", lambda m, s: "\n\n"),
    ("md_bullet", r"(?m:^[ \t]*(?:[-*+•]|\d+[.)])[ \t]+)", lambda m, s: "\n\n"),
    ("md_quote", r"(?m:^>[ \t]?)", lambda m, s: ""),
    ("md_emph", r"\*\*|__|(?<!\w)\*(?=\S)|(?<=\S)\*(?!\w)", lambda m, s: ""),
    ("dehyphen", r"(?<=[a-z])-\n(?=[a-z])", lambda m, s: ""),
    ("paragraph", r"\n[ \t]*\n\s*", lambda m, s: "\n\n"),
    ("newline", r"[ \t]*\n[ \t]*", lambda m, s: " "),
    ("currency", rf"(?P<sym>[$€£¥])\s?(?P<amt>{NUM})(?:\s?(?P<scale>[kKMBT]\b|thousand|million|billion|trillion))?", _currency),
    ("month_day", r"\b(?P<mon>(?:Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|Oct|Nov|Dec)\.?|January|February|March|April|May|June|July|August|September|October|November|December)\s(?P<d>[12]?\d|3[01])(?!\d|[.,]\d|:)\b",
     lambda m, s: f"{_month(m.group('mon'))} {ordinal_words(int(m.group('d')))}"),
    ("iso_date", r"\b(\d{4})-(\d{2})-(\d{2})\b", _iso_date),
    ("time", r"\b(?P<h>[01]?\d|2[0-3]):(?P<m>[0-5]\d)(?:\s?(?P<ap>[AaPp]\.?[Mm]\.?))?(?![\w:])", _time),
    ("percent", rf"(?P<approx>~)?(?P<n>{NUM})\s?%", _percent),
    ("dims", r"\b(\d+)\s?[x×]\s?(\d+)\b", lambda m, s: f"{int_words(int(m.group(1)))} by {int_words(int(m.group(2)))}"),
    ("times", r"\b(\d+(?:\.\d+)?)x\b", lambda m, s: f"{num_words(m.group(1))} times"),
    ("unit", rf"(?P<n>{NUM})\s?(?P<u>km/h|°[CF]|kHz|MHz|GHz|mph|lbs|ms|km|cm|mm|kg|mg|lb|GB|MB|KB|TB|Hz|m(?=\s+[a-z]))(?![\w/])", _unit),
    ("ordinal", r"\b(\d+)(?:st|nd|rd|th)\b", lambda m, s: ordinal_words(int(m.group(1)))),
    ("version", r"\b(?P<v>[vV])?(?P<n>\d+\.\d+\.\d+(?:\.\d+)*)\b",
     lambda m, s: ("version " if m.group("v") else "") + " point ".join(num_words(p) for p in m.group("n").split("."))),
    ("decimal", r"(?<![\d.])\d+\.\d+(?![\d.])", lambda m, s: num_words(m.group(0))),
    ("house_no", r"\b(\d+)([A-Z])\b", lambda m, s: f"{int_words(int(m.group(1)))} {m.group(2)}"),
    ("hashnum", r"#(\d+)\b", lambda m, s: "number " + (year_words(int(m.group(1))) if 1000 <= int(m.group(1)) <= 9999 else int_words(int(m.group(1))))),
    ("number_abbr", r"\bNo\.(?=\s?\d)", lambda m, s: "number"),
    ("int", r"\b\d{1,3}(?:,\d{3})+\b|\b\d+\b", _int),
    ("dr", r"\bDr\.", _abbr_dr),
    ("st", r"\bSt\.", _abbr_st),
    ("abbr", "|".join(re.escape(a) for a in sorted(ABBR, key=len, reverse=True)) + r"(?=[\s,;:)]|$)",
     lambda m, s: ABBR[m.group(0)] + (", " if m.group(0) in ("e.g.", "i.e.") and s[m.end():m.end() + 1] != "," else "")),
    ("acronym", r"\b(?:[A-Z]\.){2,}", lambda m, s: " ".join(m.group(0).replace(".", ""))),
    ("approx", r"~(?=\d)", lambda m, s: "about "),
    ("arrow", r"\s*(?:→|->|=>)\s*", lambda m, s: " to "),
    ("amp", r"\s&\s", lambda m, s: " and "),
    ("emoji", "[\U0001F000-\U0001FAFF☀-➿️‍]+", lambda m, s: EMOJI_WORDS.get(re.sub("[️‍]", "", m.group(0)), "")),
]
MASTER = re.compile("|".join(f"(?P<{name}>{re.sub(r'\(\?P<\w+>', '(?:', pat)})" for name, pat, _ in RULES))
HANDLERS = {name: fn for name, _, fn in RULES}
# Group names inside rule patterns collide across alternatives, so each rule is re-matched alone for its groups.
SINGLE = {name: re.compile(pat) for name, pat, _ in RULES}


@dataclass
class Segment:
    src_start: int
    src_end: int
    kind: str
    spoken: str


@dataclass
class Chunk:
    text: str
    src_start: int
    src_end: int


@dataclass
class Prepared:
    spoken: str
    segments: list
    chunks: list


def segments(src):
    out, pos = [], 0
    for m in MASTER.finditer(src):
        if m.start() > pos:
            out.append(Segment(pos, m.start(), "text", src[pos:m.start()]))
        kind = m.lastgroup
        single = SINGLE[kind].match(src, m.start())
        out.append(Segment(m.start(), m.end(), kind, HANDLERS[kind](single, src)))
        pos = m.end()
    if pos < len(src):
        out.append(Segment(pos, len(src), "text", src[pos:]))
    return out


SENTENCE_END = re.compile(r"(?:(?<=[.!?])|(?<=[.!?][\"')\]”’])|(?<=[.!?][\"')\]”’]{2}))\s+(?=[\"'(\[“‘]?[A-Z0-9])|\n\n")
CLAUSE = re.compile(r"[,;:—–](?=\s)")


def chunks(segs, first_max_words=12):
    cuttable = set()
    spoken, spans = "", []  # spans: (spoken_start, spoken_end, src_start, src_end, verbatim)
    for s in segs:
        verbatim = s.kind == "text"
        if verbatim:
            cuttable.update(range(len(spoken), len(spoken) + len(s.spoken)))
        spans.append((len(spoken), len(spoken) + len(s.spoken), s.src_start, s.src_end, verbatim))
        spoken += s.spoken

    def to_src(x, is_end):
        for ss, se, rs, re_, verbatim in spans:
            if ss <= x < se or (is_end and ss < x <= se):
                if verbatim:
                    return rs + (x - ss)
                return re_ if is_end else rs
        return spans[-1][3]

    def src_span(a, b):
        return to_src(a, False), to_src(b, True)

    pieces, start = [], 0
    for m in SENTENCE_END.finditer(spoken):
        pieces.append((start, m.start()))
        start = m.end()
    pieces.append((start, len(spoken)))

    out = []
    for a, b in pieces:
        text = spoken[a:b]
        lead = len(text) - len(text.lstrip())
        a, text = a + lead, text.strip()
        text = re.sub(r"\s{2,}", " ", text)
        if not re.search(r"\w", text):
            continue
        if not out and len(text.split()) > first_max_words:
            for cm in CLAUSE.finditer(text):
                if a + cm.start() in cuttable and 4 <= len(text[:cm.end()].split()) <= first_max_words:
                    cut = cm.end()
                    out.append(Chunk(text[:cut], *src_span(a, a + cut)))
                    text, a = text[cut:].strip(), a + cut + 1
                    break
        out.append(Chunk(text, *src_span(a, b)))
    return spoken, out


def prepare(src, **opts):
    OPTIONS.update(opts)
    segs = segments(src)
    spoken, ch = chunks(segs)
    return Prepared(spoken, segs, ch)


if __name__ == "__main__":
    text = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
    for c in prepare(text).chunks:
        print(f"[{c.src_start}:{c.src_end}] {c.text}")
