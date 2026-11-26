# Makes a self-contained copy of the site for screenshots, with a scripted state appended.
import sys, re
site, out, state = sys.argv[1], sys.argv[2], sys.argv[3]
h = open(f"{site}/index.html").read()
h = h.replace('<script src="assets/timing.js"></script>', "<script>" + open(f"{site}/assets/timing.js").read() + "</script>")
h = re.sub(r'src="assets/', f'src="{site}/assets/', h)
h = h.replace("</body>", f"<script>{state}</script></body>")
open(out, "w").write(h)
