/** Build-time gate. Unset or any value other than "true" keeps the current site. */
export function publicationsEnabled(): boolean {
  return import.meta.env.PUBLIC_PUBLICATIONS_ENABLED === 'true';
}
