#!/usr/bin/env python3
"""Exercise real local Auth/REST/Edge functions against Stripe test mode.

Requires an unlinked local Supabase stack and a Stripe CLI test-mode login.
Never accepts a remote Supabase URL. Credentials stay in private temp files.
Run with LOCAL_SUPABASE_STATUS and LOCAL_STRIPE_WEBHOOK_SECRET_FILE paths.
"""
import hashlib
import hmac
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import urllib.error
import urllib.request
import uuid


def require(condition, message):
    if not condition:
        raise AssertionError(message)


config = json.loads(Path(os.environ['LOCAL_SUPABASE_STATUS']).read_text())
base = config['API_URL'].rstrip('/')
require(base in ('http://127.0.0.1:54321', 'http://localhost:54321'),
        'Only the dedicated local stack is allowed')
service = config['SERVICE_ROLE_KEY']
anon = config['ANON_KEY']
webhook_secret = Path(os.environ['LOCAL_STRIPE_WEBHOOK_SECRET_FILE']).read_text().strip()
stripe_env_file = Path(os.environ['LOCAL_SUPABASE_STATUS']).with_name('functions.env')
stripe_test_key = next(
    line.split('=', 1)[1].strip() for line in stripe_env_file.read_text().splitlines()
    if line.startswith('STRIPE_SECRET_KEY=')
)
require(stripe_test_key.startswith(('sk_test_', 'rk_test_')),
        'A test-only Stripe key is required before any API mutation')
run = 'local-acceptance-' + uuid.uuid4().hex
checks = []


def api(method, path, body=None, token=None, expect=200):
    headers = {'apikey': anon, 'Content-Type': 'application/json',
               'Authorization': 'Bearer ' + (token or service),
               'Prefer': 'return=representation'}
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=90)
        status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    result = json.loads(raw) if raw else None
    expected = expect if isinstance(expect, tuple) else (expect,)
    require(status in expected, 'Unexpected HTTP status for ' + path + ': ' + str(status)
            + ' / ' + str(result)[:500])
    return result


def stripe(method, path, params=(), failure=False):
    args = ['stripe', method, path]
    for param in params:
        args.extend(['-d', param])
    result = subprocess.run(args, capture_output=True, text=True,
                            env={**os.environ, 'STRIPE_API_KEY': stripe_test_key})
    data = json.loads(result.stdout)
    if failure:
        require(data.get('error', {}).get('code') == 'card_declined', 'Expected card decline')
        return data
    require(result.returncode == 0 and not data.get('error'), 'Stripe test request failed')
    if data.get('object') == 'payment_intent':
        require(data.get('livemode') is False, 'Refusing non-test PaymentIntent')
    return data


def user(label):
    email = label + '-' + uuid.uuid4().hex + '@example.invalid'
    password = secrets.token_urlsafe(24)
    identity = api('POST', '/auth/v1/admin/users',
                   {'email': email, 'password': password, 'email_confirm': True})
    session = api('POST', '/auth/v1/token?grant_type=password',
                  {'email': email, 'password': password}, token=anon)
    return identity['id'], session['access_token'], email, password


def webhook(kind, intent_id, expect=200):
    event = {'id': 'evt_local_' + uuid.uuid4().hex, 'object': 'event',
             'type': kind, 'data': {'object': {'id': intent_id, 'object': 'payment_intent'}}}
    body = json.dumps(event, separators=(',', ':')).encode()
    timestamp = str(int(time.time()))
    signature = hmac.new(webhook_secret.encode(), timestamp.encode() + b'.' + body,
                         hashlib.sha256).hexdigest()
    request = urllib.request.Request(base + '/functions/v1/stripe-webhook', data=body,
        headers={'Content-Type': 'application/json',
                 'Stripe-Signature': 't=' + timestamp + ',v1=' + signature}, method='POST')
    try:
        response = urllib.request.urlopen(request, timeout=90)
        status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
    require(status == expect, 'Unexpected webhook response: ' + str(status))


def record(name):
    checks.append(name)
    print('PASS: ' + name, flush=True)


owner_id, owner_token, owner_email, owner_password = user('buyer')
other_id, other_token, _, _ = user('other')
staff_id, staff_token, _, _ = user('staff')
api('PATCH', '/rest/v1/profiles?id=eq.' + staff_id, {'role': 'staff'})
product = api('POST', '/rest/v1/products', {
    'name': 'Local acceptance fixture ' + run, 'category': 'accessories',
    'price': 1, 'stock_quantity': 5, 'show_price': True}, expect=201)[0]
product_id = product['id']
shipping = {'recipient_name': 'Local Test Buyer', 'line1': 'Test fixture only',
            'city': 'Singapore', 'postal_code': '000000', 'phone': '00000000'}
api('POST', '/rest/v1/addresses', {**shipping, 'user_id': owner_id,
    'label': 'Local test', 'is_default': True}, expect=201)
body = {'items': [{'product_id': product_id, 'quantity': 1}],
        'shipping_address': shipping, 'idempotency_key': run,
        'customer_remarks': 'Local acceptance note', 'customer_remarks_revision': 0}


def order(order_id):
    return api('GET', '/rest/v1/orders?id=eq.' + order_id)[0]


def stock():
    return api('GET', '/rest/v1/products?id=eq.' + product_id)[0]['stock_quantity']


api('POST', '/functions/v1/create-payment-intent', body, token='not-a-token', expect=401)
record('unauthenticated checkout rejected')
api('POST', '/rest/v1/orders', {'user_id': owner_id, 'status': 'pending', 'total': 1},
    token=owner_token, expect=403)
record('customer direct order insertion denied')
created = api('POST', '/functions/v1/create-payment-intent', body, token=owner_token)
order_id, intent_id = created['orderId'], created['paymentIntentId']
require(stock() == 4 and order(order_id)['status'] == 'pending', 'Reservation mismatch')
intent = stripe('get', '/v1/payment_intents/' + intent_id)
require(intent['metadata']['order_id'] == order_id, 'Payment/order link mismatch')
require(intent['amount'] == round(float(order(order_id)['total']) * 100), 'Amount mismatch')
record('server total, Stripe linkage and stock reservation agree')
retry = api('POST', '/functions/v1/create-payment-intent', body, token=owner_token)
require(retry['orderId'] == order_id and retry['paymentIntentId'] == intent_id
        and stock() == 4, 'Retry duplicated checkout/reservation')
record('pending retry reuses order/payment and reserves stock once')
api('POST', '/functions/v1/cancel-order', {'order_id': order_id}, token=other_token, expect=404)
require(stock() == 4, 'Cross-account cancellation changed stock')
record('cross-account cancellation denied')
api('POST', '/functions/v1/cancel-order', {'order_id': order_id}, token=owner_token)
require(order(order_id)['status'] == 'cancelled' and stock() == 5, 'Cancel did not restore stock')
require(stripe('get', '/v1/payment_intents/' + intent_id)['status'] == 'canceled',
        'Stripe cancellation not confirmed')
api('POST', '/functions/v1/cancel-order', {'order_id': order_id}, token=owner_token)
require(stock() == 5, 'Duplicate cancel restored stock twice')
record('verified cancellation restores stock exactly once')
created = api('POST', '/functions/v1/create-payment-intent', body, token=owner_token)
require(created['orderId'] != order_id and stock() == 4, 'Cancelled attempt key not reusable')
order_id, intent_id = created['orderId'], created['paymentIntentId']
record('cancelled checkout key can start a new attempt')
stripe('post', '/v1/payment_intents/' + intent_id + '/confirm',
       ['payment_method=pm_card_visa_chargeDeclined', 'return_url=marugen://stripe-redirect'], failure=True)
webhook('payment_intent.payment_failed', intent_id)
require(order(order_id)['status'] == 'pending' and stock() == 4,
        'Failed attempt prematurely released reservation')
record('declined payment remains pending and retryable')
stripe('post', '/v1/payment_intents/' + intent_id + '/confirm',
       ['payment_method=pm_card_visa', 'return_url=marugen://stripe-redirect'])
webhook('payment_intent.succeeded', intent_id)
require(order(order_id)['status'] == 'paid' and stock() == 4, 'Paid transition mismatch')
webhook('payment_intent.succeeded', intent_id)
webhook('payment_intent.payment_failed', intent_id)
require(order(order_id)['status'] == 'paid' and stock() == 4, 'Event replay/order corrupted state')
record('signed webhook marks paid; duplicates and late failure preserve stock/state')
retry = api('POST', '/functions/v1/create-payment-intent', body, token=owner_token)
require(retry['orderId'] == order_id and retry['clientSecret'] is None
        and retry['paymentStatus'] == 'paid' and stock() == 4, 'Paid retry became payable')
record('paid retry returns completed order without another payment')
api('POST', '/functions/v1/cancel-order', {'order_id': order_id}, token=owner_token, expect=409)
require(stock() == 4, 'Paid cancellation released stock')
record('paid cancellation rejected without releasing stock')
api('POST', '/functions/v1/stripe-refund', {'order_id': order_id}, token=owner_token, expect=403)
refund = api('POST', '/functions/v1/stripe-refund', {'order_id': order_id}, token=staff_token)
require(order(order_id)['status'] == 'refunded' and stock() == 4, 'Refund state mismatch')
api('POST', '/functions/v1/stripe-refund', {'order_id': order_id}, token=staff_token, expect=409)
require(len(stripe('get', '/v1/refunds', ['payment_intent=' + intent_id])['data']) == 1,
        'Duplicate refund was created')
record('staff-only refund recorded; duplicate refund denied')
fish = api('POST', '/rest/v1/products', {
    'name': 'Local single-stock fish ' + run, 'category': 'koi',
    'price': 1, 'stock_quantity': 1, 'show_price': True}, expect=201)[0]


def buy_fish(token):
    return api('POST', '/functions/v1/create-payment-intent', {
        'items': [{'product_id': fish['id'], 'quantity': 1}],
        'shipping_address': shipping, 'idempotency_key': str(uuid.uuid4())},
        token=token, expect=(200, 400, 409))


with ThreadPoolExecutor(max_workers=2) as pool:
    raced = list(pool.map(buy_fish, (owner_token, other_token)))
winners = [result for result in raced if result.get('paymentIntentId')]
require(len(winners) == 1, 'Single fish was sold to two buyers')
latest_fish = api('GET', '/rest/v1/products?id=eq.' + fish['id'])[0]
require(latest_fish['stock_quantity'] == 0 and latest_fish['is_sold'],
        'Single-fish reservation state mismatch')
winner = winners[0]
api('POST', '/functions/v1/cancel-order', {'order_id': winner['orderId']}, token=staff_token)
latest_fish = api('GET', '/rest/v1/products?id=eq.' + fish['id'])[0]
require(latest_fish['stock_quantity'] == 1 and not latest_fish['is_sold'],
        'Single-fish cancellation did not restore availability')
record('two concurrent buyers cannot reserve the same fish; verified cancel restores it')
output = Path('output/releases/local-payment-stack-acceptance.json')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({'run': run, 'backend': base, 'scope':
    'Real local Auth/REST/Edge/DB with Stripe test API; signed local replay events, not hosted delivery',
    'checks': checks, 'product_id': product_id, 'order_id': order_id}, indent=2) + '\n')
fixture = Path(os.environ['LOCAL_SUPABASE_STATUS']).with_name('android-fixture.json')
fixture.write_text(json.dumps({'email': owner_email, 'password': owner_password,
                              'product_id': product_id}))
fixture.chmod(0o600)
