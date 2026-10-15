'use strict';
// Share refreshes between JavaScript screens. Retry only explicit authentication
// failures; network failures may have committed a write and must not be replayed.
(() => {
  let refreshing = null;
  let generation = 0;
  const expired = () => Object.assign(new Error('Your session expired. Sign in again in another tab, then retry. Your entries are kept.'), {status: 401});
  window.CRMAuthenticatedFetch = async (path, options = {}) => {
    if (window.CRMAccountChanging) throw new Error('The signed-in account changed. Reloading the workspace.');
    const expectedUser = window.document?.querySelector('#workspace-navigation')?.getAttribute('data-user-id');
    const observedGeneration = generation;
    const request = () => fetch(path, {credentials: 'same-origin', ...options});
    let response = await request();
    if (response.status !== 401) return response;
    if (observedGeneration === generation) {
      if (!refreshing) {
        refreshing = fetch('/api/session/refresh', {method: 'POST', credentials: 'same-origin'})
          .then(async result => {
            if (!result.ok) {
              if (result.status === 401) throw expired();
              throw Object.assign(new Error('Could not refresh your session. Try again. Your entries are kept.'), {status: result.status});
            }
            if (expectedUser && result.clone) {
              const data = await result.clone().json();
              if (data.user?.id && data.user.id !== expectedUser) {
                window.dispatchEvent(new CustomEvent('crm:account-changed'));
                throw new Error('The signed-in account changed. Your previous entries will not be submitted.');
              }
            }
            generation++;
          })
          .finally(() => { refreshing = null; });
      }
      await refreshing;
    }
    if (window.CRMAccountChanging) throw new Error('The signed-in account changed. Your previous entries will not be submitted.');
    response = await request();
    if (response.status === 401) throw expired();
    return response;
  };
})();
