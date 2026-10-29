"""Disposable PostgreSQL concurrency regression; uses synthetic shipping fixture."""
import subprocess
import sys
import time
args = ['psql', *sys.argv[1:], '-qAt']
order = 'd5820000-0000-0000-0000-000000000002'
user = 'd5800000-0000-0000-0000-000000000001'
request = f"select public.transition_order_cancellation('{order}','{user}','request','Race test');"
claim = f"select public.claim_courier_shipment('{order}','easyparcel');"
def run(sql):
    return subprocess.run(args+['-c', sql], text=True, capture_output=True)
def lock_first(first, second):
    a = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    a.stdin.write('begin;\n'+first+'\n\\echo LOCKED\n'); a.stdin.flush()
    while True:
        line = a.stdout.readline()
        if line.strip() == 'LOCKED': break
        if not line: raise AssertionError(a.stderr.read())
    b = subprocess.Popen(args+['-c', second], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(0.15)
    assert b.poll() is None, 'Competing operation did not serialize on order lock'
    a.stdin.write('commit;\n\\q\n'); a.stdin.flush()
    a.communicate(timeout=5)
    out, err = b.communicate(timeout=5)
    assert b.returncode != 0, f'Both cancellation and booking won: {out} {err}'
setup = run(f"update public.orders set tracking_registered=false,tracking_provider=null,easyparcel_booking_state=null,easyparcel_booking_started_at=null,stripe_payment_intent_id='pi_cancel_race' where id='{order}';")
assert setup.returncode == 0, setup.stderr
lock_first(request, claim)
cleanup = run(f"delete from public.order_cancellation_requests where order_id='{order}';")
assert cleanup.returncode == 0, cleanup.stderr
lock_first(claim, request)
print('Cancellation/single booking races passed in both lock orders')
reset = run(f"""update public.orders set tracking_registered=false,tracking_provider=null,easyparcel_booking_state=null,easyparcel_booking_started_at=null where id='{order}';
insert into public.order_parcels(order_id,parcel_number,items,weight_kg,length_cm,width_cm,height_cm,collection_date,service_id,quoted_total_cents,quote_signature,quote_expires_at)
select '{order}',n,'[{{}}]',1,10,10,10,'2099-01-01','S1',100,'race_quote',now()+interval '10 minutes' from generate_series(1,2)n;""")
assert reset.returncode == 0, reset.stderr
parcel_claim = f"select public.claim_order_parcel_plan('{order}','race_quote',200);"
lock_first(request, parcel_claim)
cleanup = run(f"delete from public.order_cancellation_requests where order_id='{order}';")
assert cleanup.returncode == 0, cleanup.stderr
lock_first(parcel_claim, request)
print('Cancellation/split parcel booking races passed in both lock orders')
