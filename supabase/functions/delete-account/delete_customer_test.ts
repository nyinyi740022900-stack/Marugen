import { deleteCustomer, type DeletionPort } from './delete_customer.ts';
function assert(value: unknown, message: string) { if (!value) throw new Error(message); }
Deno.test('removes every historical/nested avatar before hard deleting auth', async () => {
  const events: string[] = [];
  const port: DeletionPort = {
    listAvatars: async (prefix, offset) => ({files: prefix.endsWith('/nested') ? [{name:'photo.jpg',id:'x'}] : offset === 0 ? Array.from({length:100}, (_, i) => ({name:String(i),id:'x'})) : [{name:'nested',id:null}]}),
    removeAvatars: async paths => { events.push(...paths); return undefined; },
    deleteAuthUser: async id => { events.push('auth:' + id); return undefined; },
  };
  await deleteCustomer(port, 'customer');
  assert(events.length === 102, 'all 101 personal files must be removed');
  assert(events[100] === 'avatars/customer/nested/photo.jpg', 'nested avatars retained');
  assert(events[101] === 'auth:customer', 'auth deletion must be last');
  assert(events.slice(0,-1).every(p=>p.startsWith('avatars/customer/')), 'shop assets must remain untouched');
});
Deno.test('storage failures stop auth deletion and report failure', async () => {
  let deleted = false;
  const port: DeletionPort = {
    listAvatars: async () => ({files:[{name:'photo.jpg',id:'x'}]}),
    removeAvatars: async () => 'storage unavailable',
    deleteAuthUser: async () => { deleted = true; return undefined; },
  };
  let failed = false;
  try { await deleteCustomer(port, 'customer'); } catch { failed = true; }
  assert(failed && !deleted, 'must not report success or remove auth after storage failure');
});
Deno.test('no-order/no-photo accounts use hard deletion; auth failures propagate', async () => {
  let attempts = 0;
  const port: DeletionPort = {
    listAvatars: async () => ({files:[]}),
    removeAvatars: async () => { throw new Error('unexpected'); },
    deleteAuthUser: async () => { attempts++; return 'database unavailable'; },
  };
  let failed = false;
  try { await deleteCustomer(port, 'customer'); } catch { failed = true; }
  assert(failed && attempts === 1, 'auth failure must not become a success');
});
