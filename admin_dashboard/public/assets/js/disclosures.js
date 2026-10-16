// Every disclosure is identified by section and its ancestor summary path.
// DOM replacement must preserve both explicitly opened and explicitly closed cards.
function entries(root, section) {
  const keys = new Map(), duplicates = new Map();
  return [...root.querySelectorAll('details')].map(node => {
    const parent = node.parentElement.closest('details');
    const title = node.querySelector(':scope > summary')?.textContent.trim() ?? '';
    const base = `${keys.get(parent) ?? section}/${node.dataset.disclosureId ?? title}`;
    const index = duplicates.get(base) ?? 0;
    duplicates.set(base, index + 1);
    const key = `${base}#${index}`;
    keys.set(node, key);
    return [key,node];
  });
}
export function rememberDisclosures(root, states) {
  const section = root.dataset.renderSection;
  if (section) for (const [key,node] of entries(root, section)) states.set(key,node.open);
}
export function restoreDisclosures(root, states, section) {
  root.dataset.renderSection = section;
  for (const [key,node] of entries(root, section)) if (states.has(key)) node.open = states.get(key);
}
