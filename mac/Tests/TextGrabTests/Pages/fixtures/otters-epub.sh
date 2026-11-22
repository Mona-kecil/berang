#!/bin/sh
# Makes otters.epub, an EPUB 3 book with the text of otters.pdf (see pages.tsv for its license): a cover, a
# navigation document whose landmarks mark where the text starts, a footnote with its reference, a table, and an
# HTML entity. usage: sh otters-epub.sh otters.epub
set -e
out=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
dir=$(mktemp -d)
cd "$dir"
mkdir -p META-INF OEBPS/text
printf 'application/epub+zip' > mimetype
cat > META-INF/container.xml <<'X'
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
X
cat > OEBPS/content.opf <<'X'
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">otters</dc:identifier><dc:title>Field Notes on Otters</dc:title><dc:language>en</dc:language></metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="one" href="text/one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="text/two%20b.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="cover"/><itemref idref="nav"/><itemref idref="one"/><itemref idref="two"/></spine>
</package>
X
cat > OEBPS/nav.xhtml <<'X'
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body>
<nav epub:type="toc"><ol><li><a href="text/one.xhtml">Life in the Water</a></li></ol></nav>
<nav epub:type="landmarks"><ol><li><a epub:type="bodymatter" href="text/one.xhtml#start">Start</a></li></ol></nav>
</body></html>
X
cat > OEBPS/cover.xhtml <<'X'
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head><body><p>Field Notes on Otters</p><p>Copyright 2026</p></body></html>
X
cat > OEBPS/text/one.xhtml <<'X'
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>One</title></head><body>
<section id="start"><h1>Life in the Water</h1>
<p>Otters are distinguished by their long, slim bodies, powerful webbed&nbsp;feet for swimming, and their dense fur,
which keeps them warm and buoyant.<a epub:type="noteref" href="#n1"><sup>1</sup></a></p>
<p>Some species are adapted to cold waters and need a high <em>metabolic</em> rate to stay warm.</p>
<table><tr><td>Species</td><td>13</td></tr></table>
<aside epub:type="footnote" id="n1"><p>Kruuk, H. Otters: Ecology, Behaviour and Conservation. 2006.</p></aside>
</section></body></html>
X
cat > "OEBPS/text/two b.xhtml" <<'X'
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head><body>
<h2>How Otters Hunt</h2><p>Otters find prey with their whiskers, which sense movement in murky water.</p>
<ul><li>Sea otters use stones as tools.</li><li>River otters hunt at night.</li></ul>
</body></html>
X
rm -f "$out"
zip -X0q "$out" mimetype
zip -X9qr "$out" META-INF OEBPS
rm -rf "$dir"
