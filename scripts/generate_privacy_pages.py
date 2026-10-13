"""Generate public policy pages from the exact text displayed in the app."""
from pathlib import Path
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'lib/features/legal/privacy_content.dart').read_text()
sections = [(json.loads(t), json.loads(b)) for t, b in re.findall(
    r'\(\s*title:\s*("(?:[^"\\]|\\.)*"),\s*body:\s*("(?:[^"\\]|\\.)*"),?\s*\)', source)]
assert len(sections) == 10, 'Expected complete policy sections'
email = re.search(r"privacyContactEmail = '([^']+)'", source).group(1)
email_link = f'<a href="mailto:{email}">{email}</a>'
request = f'mailto:{email}?subject=Marugen%20account%20deletion'
style = '''body{font-family:system-ui,-apple-system,sans-serif;max-width:760px;margin:auto;padding:32px 20px 64px;color:#171717;background:#faf9f7;line-height:1.65}h1{font-size:2rem;line-height:1.2}h2{font-size:1.15rem;margin-top:28px}a{color:#a71912;overflow-wrap:anywhere}nav{display:flex;flex-wrap:wrap;gap:18px}.contact{background:#fff;border:1px solid #dedbd6;border-radius:12px;padding:20px}.button{display:inline-block;padding:12px 18px;background:#b71c12;color:white;border-radius:8px;text-decoration:none}:focus-visible{outline:3px solid #a71912;outline-offset:4px}p{margin:12px 0}@media(prefers-color-scheme:dark){body{background:#171717;color:#f4f1ed}a{color:#ffaaa4}.contact{background:#252525;border-color:#555}.button{color:white}}'''
def page(title, body):
    return f'<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} — Marugen Fish Farm</title><style>{style}</style></head><body><nav aria-label="Legal navigation"><a href="https://marugen.pages.dev/">Marugen home</a><a href="https://marugen.pages.dev/privacy-policy/">Privacy Policy</a><a href="https://marugen.pages.dev/data-deletion/">Account &amp; data deletion</a></nav><main><h1>{title}</h1>{body}</main></body></html>\n'
body = '<p>Marugen shopping app and website · Updated 13 October 2026</p><aside class="contact"><strong>Privacy contact</strong><p>'+email_link+'</p><a href="https://marugen.pages.dev/data-deletion/">Request account or data deletion</a></aside>'
for title, text in sections:
    body += f'<section><h2>{html.escape(title)}</h2><p>{html.escape(text).replace(email, email_link)}</p></section>'
policy = page('Privacy Policy', body)
(ROOT/'docs/privacy.html').write_text(policy)
(ROOT/'docs/privacy-policy/index.html').write_text(policy)
delete = f'''<p>For the <strong>Marugen app by Marugen Fish Farm / Marugen Koi Farm</strong>.</p>
<section class="contact"><h2>Request deletion without the app</h2><p>Email {email_link} with the subject <strong>Marugen account deletion</strong>. Send from your account email if possible and include the account email you want deleted. If you cannot access it, explain this so we can verify ownership. You do not need to reinstall or sign in to the app.</p><a class="button" href="{request}">Email an account deletion request</a><p>If the button does not open your email app, copy the email address above and send the request using any email service. Never send your password, verification codes or full payment card details.</p></section>
<h2>Delete selected data instead</h2><p>You can request deletion of selected personal data without closing the entire account. Email the same address with the subject <strong>Marugen data request</strong> and describe what you want removed.</p>
<h2>In the app</h2><p>Open <strong>Profile → Delete Account</strong> and review the confirmation. Saved addresses, wishlist items and your reviews can also be removed individually.</p>
<h2>What is deleted and retained?</h2><p>{html.escape(sections[6][1])}</p>
<h2>Timing and verification</h2><p>We aim to respond to verified requests within 30 days. We may need information to verify account ownership, and will explain any required retention or delay. Deletion does not delete your Google or Apple account or cancel an existing order, refund or delivery obligation.</p><p>Read the <a href="https://marugen.pages.dev/privacy-policy/">Privacy Policy</a> for the information we collect, service providers, retention and your choices.</p>'''
(ROOT/'docs/data-deletion/index.html').write_text(page('Account &amp; data deletion',delete))
