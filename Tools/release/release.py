#!/usr/bin/env python3
"""Outils de release de DynamicNotch (bibliothèque standard uniquement).

    release.py notes --tag v1.2.0 [--text "…"]    → notes de version (Markdown)
    release.py appcast --version 1.2.0 --build 202609301200 --url URL \\
        --signature SIG --length N --notes-file notes.md --output appcast.xml

Les notes viennent, dans l'ordre : de --text, du message du tag annoté, sinon
des commits `feat:` / `fix:` / `perf:` depuis le tag précédent (première
version : un texte d'accueil plutôt que tout l'historique).
"""

import argparse
import html
import re
import subprocess
import sys
from email.utils import formatdate

REPO_URL = "https://github.com/dev-thomass/DynamicNotch"
MINIMUM_SYSTEM_VERSION = "14.0"
USER_FACING_TYPES = {"feat", "fix", "perf"}
COMMIT_RE = re.compile(r"^(?P<type>[a-z]+)(\([^)]*\))?!?:\s*(?P<subject>.+)$")


def git(*args):
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def previous_tag(tag):
    """Tag de version précédent (le tag courant peut ne pas exister encore)."""
    reference = f"{tag}^" if git("rev-parse", "-q", "--verify", f"refs/tags/{tag}") else "HEAD"
    return git("describe", "--tags", "--abbrev=0", "--match", "v*", reference)


def commit_notes(tag):
    since = previous_tag(tag)
    if not since:
        return "Première version publique de DynamicNotch."
    log = git("log", "--no-merges", "--format=%s", f"{since}..HEAD")
    items = []
    for line in log.splitlines():
        match = COMMIT_RE.match(line)
        if not match or match["type"] not in USER_FACING_TYPES:
            continue
        subject = match["subject"].strip()
        subject = subject[0].upper() + subject[1:]
        if subject not in items:
            items.append(subject)
    if not items:
        return "Améliorations et corrections."
    return "\n".join(f"- {item}" for item in items)


def tag_message(tag):
    # %(contents) est vide pour un tag léger ; on ignore une éventuelle signature.
    message = git("tag", "-l", "--format=%(contents)", tag)
    return message.split("-----BEGIN PGP SIGNATURE-----")[0].strip()


def notes(args):
    body = (args.text or "").strip() or tag_message(args.tag) or commit_notes(args.tag)
    print(body)


def markdown_to_html(text):
    """Sous-ensemble de Markdown : titres, listes à puces, paragraphes."""
    parts, bullets = [], []

    def flush():
        if bullets:
            parts.append("<ul>" + "".join(f"<li>{b}</li>" for b in bullets) + "</ul>")
            bullets.clear()

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            flush()
        elif line.startswith(("- ", "* ")):
            bullets.append(html.escape(line[2:].strip()))
        elif line.startswith("#"):
            flush()
            parts.append(f"<h3>{html.escape(line.lstrip('#').strip())}</h3>")
        else:
            flush()
            parts.append(f"<p>{html.escape(line)}</p>")
    flush()
    return "\n".join(parts)


def appcast(args):
    with open(args.notes_file, encoding="utf-8") as handle:
        description = markdown_to_html(handle.read())
    tag = f"v{args.version}"
    attr = lambda value: html.escape(value, quote=True)  # noqa: E731
    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DynamicNotch</title>
    <link>{REPO_URL}</link>
    <description>Mises à jour de DynamicNotch</description>
    <language>fr</language>
    <item>
      <title>Version {html.escape(args.version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{REPO_URL}/releases/tag/{html.escape(tag)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
{description}
      ]]></description>
      <enclosure url="{attr(args.url)}" length="{int(args.length)}" type="application/octet-stream" sparkle:edSignature="{attr(args.signature)}"/>
    </item>
  </channel>
</rss>
"""
    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(xml)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    notes_parser = commands.add_parser("notes")
    notes_parser.add_argument("--tag", required=True)
    notes_parser.add_argument("--text", default="")
    notes_parser.set_defaults(func=notes)

    appcast_parser = commands.add_parser("appcast")
    for name in ("version", "build", "url", "signature", "length", "notes-file", "output"):
        appcast_parser.add_argument(f"--{name}", required=True)
    appcast_parser.set_defaults(func=appcast)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    sys.exit(main())
