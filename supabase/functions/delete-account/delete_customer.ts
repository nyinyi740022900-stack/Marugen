// Auth deletion cascades personal rows and detaches retained business records
// via migration 0051. Remove owned avatar objects through the Storage API first.
export interface DeletionPort {
  listAvatars(prefix: string, offset: number): Promise<{ files: { name: string; id: string | null }[]; error?: string }>;
  removeAvatars(paths: string[]): Promise<string | undefined>;
  deleteAuthUser(id: string): Promise<string | undefined>;
}

export async function deleteCustomer(port: DeletionPort, userId: string): Promise<void> {
  const paths: string[] = [];
  async function collect(prefix: string): Promise<void> {
    for (let offset = 0; ; offset += 100) {
      const result = await port.listAvatars(prefix, offset);
      if (result.error) throw new Error('Could not inspect profile photos: ' + result.error);
      for (const file of result.files) {
        const path = prefix + '/' + file.name;
        if (file.id === null) await collect(path);
        else paths.push(path);
      }
      if (result.files.length < 100) break;
    }
  }
  await collect('avatars/' + userId);
  for (let start = 0; start < paths.length; start += 100) {
    const error = await port.removeAvatars(paths.slice(start, start + 100));
    if (error) throw new Error('Could not remove profile photos: ' + error);
  }
  const error = await port.deleteAuthUser(userId);
  if (error) throw new Error('Could not delete account: ' + error);
}
