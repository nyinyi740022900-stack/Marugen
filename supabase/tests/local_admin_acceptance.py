#!/usr/bin/env python3
"""Authenticated customer/staff/owner acceptance on the disposable local DB."""
import json
import os
from pathlib import Path
import secrets
import urllib.error
import urllib.request
import uuid

root = Path(os.environ['LOCAL_SUPABASE_STATUS']).parent
config = json.loads((root / 'status.json').read_text())
base = config['API_URL'].rstrip('/')
assert base == 'http://127.0.0.1:54321', 'Local backend only'
checks = []


def api(method, path, body=None, token=None, expect=200):
    headers = {'apikey': config['ANON_KEY'], 'Content-Type': 'application/json',
               'Authorization': 'Bearer ' + (token or config['SERVICE_ROLE_KEY']),
               'Prefer': 'return=representation'}
    request = urllib.request.Request(base + path, method=method, headers=headers,
        data=None if body is None else json.dumps(body).encode())
    try:
        response = urllib.request.urlopen(request, timeout=45)
        status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    data = json.loads(raw) if raw else None
    allowed = expect if isinstance(expect, tuple) else (expect,)
    assert status in allowed, (path, status, str(data)[:400])
    return data


def user(role):
    email = role + '-' + uuid.uuid4().hex + '@example.invalid'
    password = secrets.token_urlsafe(24)
    identity = api('POST', '/auth/v1/admin/users',
                   {'email': email, 'password': password, 'email_confirm': True})
    if role != 'customer':
        api('PATCH', '/rest/v1/profiles?id=eq.' + identity['id'], {'role': role})
    session = api('POST', '/auth/v1/token?grant_type=password',
                  {'email': email, 'password': password}, token=config['ANON_KEY'])
    return {'id': identity['id'], 'token': session['access_token'],
            'email': email, 'password': password}


def passed(name):
    checks.append(name)
    print('PASS: ' + name, flush=True)


def main():
    customer, staff, owner = (user(role) for role in ('customer', 'staff', 'owner'))
    pending = api('POST', '/rest/v1/orders', {
        'user_id': customer['id'], 'status': 'pending', 'total': 10,
        'idempotency_key': 'admin-acceptance-' + uuid.uuid4().hex}, expect=201)[0]
    order_path = '/rest/v1/orders?id=eq.' + pending['id']
    for actor in (staff, owner):
        api('PATCH', order_path, {'status': 'paid'}, token=actor['token'], expect=400)
        api('PATCH', order_path, {'total': 0.01}, token=actor['token'], expect=400)
    passed('staff/owner cannot forge payment state or rewrite checkout amount')
    api('PATCH', order_path, {'status': 'paid'})  # synthetic service fixture, no real charge
    for actor in (staff, owner):
        api('PATCH', order_path, {'status': 'refunded', 'stripe_refund_id': 'fake'},
            token=actor['token'], expect=400)
    passed('staff/owner cannot label a refund without the server refund endpoint')
    own_profile = '/rest/v1/profiles?id=eq.' + customer['id']
    api('PATCH', own_profile, {'role': 'owner'}, token=customer['token'])
    assert api('GET', own_profile, token=customer['token'])[0]['role'] == 'customer'
    passed('customer cannot promote themselves to owner')
    product = api('POST', '/rest/v1/products', {'name': 'Admin local fixture',
        'category': 'accessories', 'price': 10, 'stock_quantity': 10},
        token=owner['token'], expect=201)[0]
    product_path = '/rest/v1/products?id=eq.' + product['id']
    assert api('PATCH', product_path, {'stock_quantity': 99}, token=customer['token']) == []
    api('POST', '/rest/v1/products', {'name': 'Unauthorized', 'category': 'koi'},
        token=customer['token'], expect=403)
    for actor in (staff, owner):
        assert api('PATCH', product_path, {'stock_quantity': 12}, token=actor['token'])[0]['stock_quantity'] == 12
    passed('product/stock management allows staff/owner and denies customer writes')
    settings_path = '/rest/v1/settings?id=eq.1'
    settings = api('GET', settings_path)[0]
    assert api('PATCH', settings_path, {'shop_name': 'Forbidden'}, token=customer['token']) == []
    for actor in (staff, owner):
        api('PATCH', settings_path, {'shop_name': 'Local acceptance shop'}, token=actor['token'])
    api('PATCH', settings_path, {'shop_name': settings['shop_name']}, token=owner['token'])
    passed('shop settings permissions match current shared staff/owner admin role')
    assert api('GET', '/rest/v1/profiles?id=eq.' + owner['id'], token=customer['token']) == []
    assert api('GET', own_profile, token=staff['token'])[0]['id'] == customer['id']
    assert api('GET', own_profile, token=owner['token'])[0]['id'] == customer['id']
    passed('customer profiles are isolated while staff/owner can serve customers')
    assert api('PATCH', order_path, {'status': 'packing'}, token=customer['token']) == []
    for status, actor in (('packing', staff), ('shipped', owner), ('delivered', staff)):
        assert api('PATCH', order_path, {'status': status}, token=actor['token'])[0]['status'] == status
    api('PATCH', order_path, {'status': 'paid'}, token=owner['token'], expect=400)
    history = api('GET', '/rest/v1/order_status_history?order_id=eq.' + pending['id'], token=owner['token'])
    assert {row['to_status'] for row in history} >= {'paid', 'packing', 'shipped', 'delivered'}
    passed('fulfillment progresses with audit history; customer and backward updates denied')
    api('POST', '/rest/v1/product_views', {'product_id': product['id'], 'user_id': customer['id']}, expect=201)
    assert api('GET', '/rest/v1/product_views?product_id=eq.' + product['id'], token=customer['token']) == []
    for actor in (staff, owner):
        assert len(api('GET', '/rest/v1/product_views?product_id=eq.' + product['id'], token=actor['token'])) == 1
    passed('raw analytics restricted to staff/owner')
    fixture = root / 'admin-fixture.json'
    fixture.write_text(json.dumps({'owner': owner, 'staff': staff, 'customer': customer,
                                   'product_id': product['id'], 'order_id': pending['id']}))
    fixture.chmod(0o600)
    output = Path('output/releases/local-admin-acceptance.json')
    output.write_text(json.dumps({'scope': 'real local Auth/REST/DB, synthetic service-seeded order',
                                 'checks': checks}, indent=2) + '\n')


if __name__ == "__main__":
    main()
