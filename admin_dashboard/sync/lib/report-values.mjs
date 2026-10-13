// Missing labels retain metrics in a separate bucket. Never merge their distinct
// users with GA4's existing '(not set)' group.
// Missing event names must never be presented as a real feature.
export const dimensionLabel = value => typeof value === 'string' && value.trim() ? value : '(missing)';
export const eventName = value => typeof value === 'string' && value.trim() ? value : null;

/** Report empty dimensions by report/column only; never log credentials or user data. */
export function emptyDimensions(raw, prefix = '') {
  const findings = [];
  for (const [key, report] of Object.entries(raw ?? {})) {
    const path = prefix ? prefix + '.' + key : key;
    if (!report || typeof report !== 'object') continue;
    if (Array.isArray(report.rows)) {
      const counts = new Map();
      for (const row of report.rows) for (const [i, dimension] of (row.dimensionValues ?? []).entries()) {
        if (eventName(dimension.value) != null) continue;
        const column = report.dimensionHeaders?.[i]?.name ?? 'dimension[' + i + ']';
        counts.set(column, (counts.get(column) ?? 0) + 1);
      }
      for (const [column, count] of counts) findings.push({report: path, column, count});
    } else findings.push(...emptyDimensions(report, path));
  }
  return findings;
}

/** Add the exact document field path to errors before Firestore batch validation. */
export function assertNonemptyFields(value, path = '$') {
  if (value == null || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    const field = path + '[' + JSON.stringify(key) + ']';
    if (key === '') throw new Error('Empty Firestore field at ' + field);
    assertNonemptyFields(child, field);
  }
}
