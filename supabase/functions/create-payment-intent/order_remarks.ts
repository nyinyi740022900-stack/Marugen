export function normaliseCustomerRemarks(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== 'string') throw new Error('Order requests must be text.');
  const text = value.trim();
  if (text.length === 0) return null;
  if (Array.from(text).length > 500) throw new Error('Keep your requests within 500 characters.');
  if (text.includes('\0')) throw new Error('Please remove unsupported characters from your requests.');
  return text;
}

export function normaliseRemarksRevision(value: unknown): number {
  if (value == null) return 0;
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > 2147483647) {
    throw new Error('Invalid order requests revision.');
  }
  return value;
}

export function remarksRetryAction(
  savedText: string | null, savedRevision: number,
  incomingText: string | null, incomingRevision: number,
): 'unchanged' | 'update' | 'stale' {
  if (incomingRevision < savedRevision) return 'stale';
  if (incomingRevision === savedRevision) return savedText === incomingText ? 'unchanged' : 'stale';
  return 'update';
}
