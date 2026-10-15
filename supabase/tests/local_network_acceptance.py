"""Real dropped checkout response and delayed webhook acceptance, local only.

Stop the local Stripe listener before running the delayed-delivery scenario.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
from threading import Thread
import urllib.error
import urllib.request
import uuid

from local_admin_acceptance import api, base, config, root, user

key = next(line.split('=', 1)[1].strip() for line in
           (root / 'functions.env').read_text().splitlines()
           if line.startswith('STRIPE_SECRET_KEY='))
assert key.startswith(('sk_test_', 'rk_test_'))
buyer = user('customer')
product = api('POST', '/rest/v1/products', {'name': 'Network acceptance fixture',
    'category': 'accessories', 'price': 1, 'stock_quantity': 5}, expect=201)[0]
payload = {'items': [{'product_id': product['id'], 'quantity': 1}],
    'shipping_address': {'recipient_name': 'Synthetic buyer', 'line1': 'Test only'},
    'idempotency_key': 'network-' + uuid.uuid4().hex}
headers = {'apikey': config['ANON_KEY'], 'Authorization': 'Bearer ' + buyer['token'],
           'Content-Type': 'application/json'}


class DropCommittedResponse(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        data = self.rfile.read(int(self.headers['Content-Length']))
        request = urllib.request.Request(base + '/functions/v1/create-payment-intent',
                                         data=data, headers=headers, method='POST')
        with urllib.request.urlopen(request, timeout=90) as response:
            self.server.created = json.loads(response.read())
        self.close_connection = True
        self.connection.shutdown(socket.SHUT_RDWR)
        self.connection.close()


server = ThreadingHTTPServer(('127.0.0.1', 0), DropCommittedResponse)
thread = Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    request = urllib.request.Request('http://127.0.0.1:' + str(server.server_port),
        data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'}, method='POST')
    try:
        urllib.request.urlopen(request, timeout=90)
        raise AssertionError('Response should have been dropped')
    except (urllib.error.URLError, ConnectionError):
        pass
    assert hasattr(server, 'created'), 'The upstream checkout must have committed'
finally:
    server.shutdown()
    server.server_close()
retry = api('POST', '/functions/v1/create-payment-intent', payload, token=buyer['token'])
assert retry['orderId'] == server.created['orderId']
assert retry['paymentIntentId'] == server.created['paymentIntentId']
stock_path = '/rest/v1/products?id=eq.' + product['id']
assert api('GET', stock_path)[0]['stock_quantity'] == 4
assert len(api('GET', '/rest/v1/orders?user_id=eq.' + buyer['id'])) == 1
print('PASS: committed response dropped on the wire; retry reuses one order/payment/reservation', flush=True)
api('POST', '/functions/v1/cancel-order', {'order_id': retry['orderId']}, token=buyer['token'])
assert api('GET', stock_path)[0]['stock_quantity'] == 5
payload['idempotency_key'] = 'delayed-' + uuid.uuid4().hex
created = api('POST', '/functions/v1/create-payment-intent', payload, token=buyer['token'])
args = ['stripe', 'post', '/v1/payment_intents/' + created['paymentIntentId'] + '/confirm',
        '-d', 'payment_method=pm_card_visa', '-d', 'return_url=marugen://stripe-redirect']
result = subprocess.run(args, capture_output=True, text=True,
                        env={**os.environ, 'STRIPE_API_KEY': key})
intent = json.loads(result.stdout)
assert result.returncode == 0 and intent['status'] == 'succeeded' and intent['livemode'] is False
order_path = '/rest/v1/orders?id=eq.' + created['orderId']
assert api('GET', order_path)[0]['status'] == 'pending', 'Keep the listener stopped for this case'
retry = api('POST', '/functions/v1/create-payment-intent', payload, token=buyer['token'])
assert retry['orderId'] == created['orderId'] and retry['clientSecret'] is None
assert api('GET', order_path)[0]['status'] == 'paid'
assert api('GET', stock_path)[0]['stock_quantity'] == 4
assert len(api('GET', '/rest/v1/orders?user_id=eq.' + buyer['id'])) == 2
print('PASS: delayed webhook is recovered from authoritative Stripe state on checkout retry', flush=True)
staff = user('staff')
api('POST', '/functions/v1/stripe-refund', {'order_id': created['orderId']}, token=staff['token'])
output = Path('output/releases/local-network-acceptance.json')
output.write_text(json.dumps({'scope': 'real local HTTP disconnect; Stripe test mode; listener deliberately stopped',
    'checks': ['dropped committed response retries exactly once',
               'delayed webhook recovery returns completed order without another charge'],
    'test_payment_refunded': True}, indent=2) + '\n')
