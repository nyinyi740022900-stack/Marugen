"""Update the current Pages homepage after its deployment source is available."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old_email = 'hello@marugenkoi.example'
email = 'marugenfishfarmaiagent@gmail.com'
assert old_email in source or email in source, 'Unexpected homepage; do not overwrite another site'
source = source.replace(old_email, email)
source = source.replace('to our farm in Japan.', 'to our farm in Singapore.')
# Make the real contact visible rather than only available behind a mail link.
source = source.replace('<b>Contact Us</b><small>Get in touch</small>', f'<b>Contact Us</b><small>{email}</small>')
path.write_text(source)
