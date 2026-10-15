"""Real concurrent psql sessions on the runner's private local database."""
import subprocess
import sys
import time

PSQL = ['psql', '-X', '-qAt', '-h', sys.argv[1], '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']


def run(sql):
    return subprocess.run(PSQL, input=sql, text=True, capture_output=True, check=True).stdout.strip()


def start(sql):
    process = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write(sql)
    process.stdin.close()
    process.stdin = None
    return process


def wait_state(name, condition):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if run(f"select exists(select 1 from pg_stat_activity where application_name='{name}' and {condition});") == 't':
            return
        time.sleep(0.05)
    raise AssertionError(f'{name} did not reach {condition}')


run("""
insert into auth.users(id,email) values ('93000000-0000-0000-0000-000000000001','race@example.invalid');
insert into public.products(id,name,category,stock_quantity,price) values
('93000000-0000-0000-0000-000000000002','Race food','fish_food',10,10);
insert into public.orders(id,user_id) values
('93000000-0000-0000-0000-000000000003','93000000-0000-0000-0000-000000000001'),
('93000000-0000-0000-0000-000000000004','93000000-0000-0000-0000-000000000001');
""")

for insert_first, suffix in [(True, '003'), (False, '004')]:
    order_id = '93000000-0000-0000-0000-000000000' + suffix
    insert = f"insert into public.order_items(order_id,product_id,product_name,quantity) values ('{order_id}','93000000-0000-0000-0000-000000000002','Race food',2);"
    cancel = f"update public.orders set status='cancelled' where id='{order_id}';"
    holder_sql, contender_sql = (insert, cancel) if insert_first else (cancel, insert)
    holder = start(f"set application_name='marugen_race_holder'; set role service_role; begin; {holder_sql} select pg_sleep(5); commit;")
    contender = None
    try:
        wait_state('marugen_race_holder', "wait_event='PgSleep'")
        contender = start(f"set application_name='marugen_race_contender'; set role service_role; {contender_sql}")
        # Assert the opposing operation actually waits on the parent's lock,
        # rather than merely checking a fortunate sequential interleaving.
        wait_state('marugen_race_contender', "wait_event_type='Lock'")
        _, holder_error = holder.communicate(timeout=10)
        assert holder.returncode == 0, holder_error
        _, contender_error = contender.communicate(timeout=10)
        if insert_first:
            assert contender.returncode == 0, contender_error
            expected_items = 1
        else:
            assert contender.returncode != 0 and 'pending order' in contender_error, contender_error
            expected_items = 0
        assert run("select stock_quantity from public.products where id='93000000-0000-0000-0000-000000000002';") == '10'
        assert run(f"select status from public.orders where id='{order_id}';") == 'cancelled'
        assert run(f"select count(*) from public.order_items where order_id='{order_id}';") == str(expected_items)
    finally:
        for process in (holder, contender):
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()

run("""
delete from public.orders where user_id='93000000-0000-0000-0000-000000000001';
delete from public.products where id='93000000-0000-0000-0000-000000000002';
delete from auth.users where id='93000000-0000-0000-0000-000000000001';
""")
print('Concurrent reservation/cancellation checks passed in both orderings')
