import { normaliseCustomerRemarks, normaliseRemarksRevision, remarksRetryAction } from './order_remarks.ts';

Deno.test('optional requests preserve Unicode and multiline content', () => {
  const input = '  မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nRing the bell.  ';
  if (normaliseCustomerRemarks(input) !== 'မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nRing the bell.') throw new Error('Requests were changed');
  for (const value of [undefined, null, '', '  \n ']) {
    if (normaliseCustomerRemarks(value) !== null) throw new Error('Blank requests must be null');
  }
});
Deno.test('server accepts 500 Unicode characters and rejects invalid requests', () => {
  if (normaliseCustomerRemarks('🐟'.repeat(500)) !== '🐟'.repeat(500)) throw new Error('Boundary rejected');
  for (const invalid of ['🐟'.repeat(501), { text: 'hello' }, 42, ['hello'], 'call\0me']) {
    let rejected = false;
    try { normaliseCustomerRemarks(invalid); } catch { rejected = true; }
    if (!rejected) throw new Error('Invalid requests accepted');
  }
});

Deno.test('reordered retries keep the latest request including clearing', () => {
  if (remarksRetryAction('Call first', 1, 'Ring bell', 2) !== 'update') throw new Error('Edit rejected');
  if (remarksRetryAction('Ring bell', 2, 'Call first', 1) !== 'stale') throw new Error('Old retry accepted');
  if (remarksRetryAction('Ring bell', 2, 'Ring bell', 2) !== 'unchanged') throw new Error('Identical retry rejected');
  if (remarksRetryAction('Ring bell', 2, 'Other text', 2) !== 'stale') throw new Error('Version reused');
  if (remarksRetryAction('Ring bell', 2, null, 3) !== 'update') throw new Error('Clear rejected');
  if (remarksRetryAction(null, 3, 'Ring bell', 2) !== 'stale') throw new Error('Cleared request restored');
});
Deno.test('revision accepts old clients and rejects invalid versions', () => {
  if (normaliseRemarksRevision(undefined) !== 0 || normaliseRemarksRevision(7) !== 7) throw new Error('Valid version rejected');
  for (const value of [-1, 1.5, '1', NaN, Infinity, 2147483648]) {
    let rejected = false;
    try { normaliseRemarksRevision(value); } catch { rejected = true; }
    if (!rejected) throw new Error('Invalid version accepted');
  }
});
