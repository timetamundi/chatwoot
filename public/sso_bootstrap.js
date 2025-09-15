(function () {
  function parseHash() {
    var h = (location.hash || '').replace(/^#/, '');
    var out = {};
    h.split('&').forEach(function (kv) {
      if (!kv) return;
      var i = kv.indexOf('=');
      var k = decodeURIComponent(kv.slice(0, i));
      var v = decodeURIComponent(kv.slice(i + 1));
      out[k] = v;
    });
    return out;
  }

  function setStore(store, k, v) { try { store.setItem(k, v); } catch(_) {} }
  function setAll(k, v) { setStore(localStorage, k, v); setStore(sessionStorage, k, v); }
  function getHeader(resp, name) { try { return resp.headers.get(name); } catch(_) { return null; } }

  function persistAll(tokens, email, accountId) {
    // snake_case
    setAll('uid',          tokens.uid);
    setAll('client',       tokens.client);
    setAll('access-token', tokens['access-token']);
    if (tokens['token-type']) setAll('token-type', tokens['token-type']);
    if (tokens.expiry)       setAll('expiry', tokens.expiry);

    // camelCase (alguns bundles usam)
    setAll('uidToken',      tokens.uid);
    setAll('clientToken',   tokens.client);
    setAll('accessToken',   tokens['access-token']);
    if (tokens['token-type']) setAll('tokenType', tokens['token-type']);
    if (tokens.expiry)       setAll('expiryAt', tokens.expiry);

    // prefixos cw_ (versões que limpam o resto)
    setAll('cw_uid',          tokens.uid);
    setAll('cw_client',       tokens.client);
    setAll('cw_access_token', tokens['access-token']);

    // blobs comuns
    setAll('auth', JSON.stringify({
      'uid': tokens.uid,
      'client': tokens.client,
      'access-token': tokens['access-token'],
      'token-type': tokens['token-type'] || 'Bearer',
      'expiry': tokens.expiry || ''
    }));
    setAll('authData', JSON.stringify({
      uid: tokens.uid,
      client: tokens.client,
      accessToken: tokens['access-token'],
      tokenType: tokens['token-type'] || 'Bearer',
      expiry: tokens.expiry || ''
    }));
    setAll('cw_auth', JSON.stringify({
      uid: tokens.uid,
      client: tokens.client,
      access_token: tokens['access-token'],
      token_type: tokens['token-type'] || 'Bearer',
      expiry: tokens.expiry || ''
    }));

    // infos auxiliares
    if (email) setAll('userEmail', email);
    if (accountId) {
      setAll('account_id', String(accountId));
      setAll('currentAccountId', String(accountId));
      setAll('selectedAccountId', String(accountId));
      setAll('cwActiveAccountId', String(accountId));
    }

    // avisa listeners do SPA
    try { window.dispatchEvent(new StorageEvent('storage', { key: 'access-token', newValue: tokens['access-token'] })); } catch(_) {}
  }

  async function validateAndWarmUp(tokens) {
    let resp;
    try {
      resp = await fetch('/auth/validate_token', {
        headers: {
          'uid':          tokens.uid,
          'client':       tokens.client,
          'access-token': tokens['access-token'],
          'token-type':   tokens['token-type'] || 'Bearer',
          'expiry':       tokens.expiry || ''
        },
        credentials: 'same-origin'
      });
    } catch (_) {}

    // Se o backend girar novos headers, atualiza os tokens em memória
    if (resp && resp.ok) {
      const at = resp.headers.get('access-token');
      const cl = resp.headers.get('client');
      const uid = resp.headers.get('uid');
      const ex = resp.headers.get('expiry');
      const tt = resp.headers.get('token-type');
      if (at && cl && uid) {
        tokens['access-token'] = at;
        tokens.client = cl;
        tokens.uid = uid;
        if (tt) tokens['token-type'] = tt;
        if (ex) tokens.expiry = ex;
      }

      // >>> DEFINE o cookie cw_d_session_info exatamente como o SPA espera
      try {
        // Monte um objeto de headers semelhante ao response.headers do axios/fetch
        const headersJson = {
          'access-token': tokens['access-token'],
          client: tokens.client,
          uid: tokens.uid,
          expiry: tokens.expiry,
          'token-type': tokens['token-type'] || 'Bearer'
        };
        const cookieValue = encodeURIComponent(JSON.stringify(headersJson));
        // expira no exato horário do header `expiry` (UNIX seconds)
        const expDate = tokens.expiry ? new Date(parseInt(tokens.expiry, 10) * 1000) : null;
        const parts = [
          `cw_d_session_info=${cookieValue}`,
          'Path=/', 'SameSite=Lax'
        ];
        // Em produção HTTPS, adicione Secure
        if (location.protocol === 'https:') parts.push('Secure');
        if (expDate) parts.push(`Expires=${expDate.toUTCString()}`);
        document.cookie = parts.join('; ');
      } catch (e) {
        console.warn('[SSO] falha ao setar cw_d_session_info', e);
      }
    }

    // (opcional mas útil) buscar o profile para povoar `user` e contas
    try {
      const r = await fetch('/api/v1/profile', {
        headers: {
          'uid':          tokens.uid,
          'client':       tokens.client,
          'access-token': tokens['access-token'],
          'token-type':   tokens['token-type'] || 'Bearer',
          'expiry':       tokens.expiry || ''
        },
        credentials: 'same-origin'
      });
      if (r.ok) {
        const data = await r.json();
        // muitos bundles conferem `localStorage.user` no boot
        try { localStorage.setItem('user', JSON.stringify(data.data || data.user || {})); } catch(_) {}
        const accId =
          tokens.account_id ||
          (data.data && data.data.accounts && data.data.accounts[0] && data.data.accounts[0].id) || '';
        if (accId) {
          ['account_id','currentAccountId','selectedAccountId','cwActiveAccountId']
            .forEach(k => { try {
              localStorage.setItem(k, String(accId));
              sessionStorage.setItem(k, String(accId));
            } catch(_) {} });
        }
      }
    } catch (_) {}

    // regrava nos storages para manter consistência com outros leitores
    persistAll(tokens, tokens.email, tokens.account_id);
  }


  (async function main() {
    const p = parseHash();
    const required = ['uid', 'client', 'access-token'];
    if (!required.every(k => p[k])) return;

    const tokens = {
      uid: p['uid'],
      client: p['client'],
      'access-token': p['access-token'],
      'token-type': p['token-type'] || 'Bearer',
      expiry: p['expiry'] || '',
      email: p['email'] || '',
      account_id: p['account_id'] || ''
    };

    // grava tudo já
    persistAll(tokens, tokens.email, tokens.account_id);

    // valida e aquece
    await validateAndWarmUp(tokens);

    // segue pro dashboard
    const next = p['next'] || '/';
    location.replace(next);
  })();
})();
