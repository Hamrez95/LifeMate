export function normalizeCareManagementPath(path: string): string {
  const segments = path.split('/').filter(Boolean);
  const functionIndex = segments.findIndex((segment) =>
    segment === 'lifemate-care-management' ||
    segment.startsWith('lifemate-care-management-')
  );
  if (functionIndex >= 0) {
    const remaining = segments.slice(functionIndex + 1);
    return remaining.length == 0 ? '/' : `/${remaining.join('/')}`;
  }
  return path || '/';
}
