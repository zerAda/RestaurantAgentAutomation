const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';

interface StrapiResponse<T> {
  data: T;
  meta?: Record<string, unknown>;
}

let _token: string | null = null;

export function setStrapiToken(token: string) {
  _token = token;
}

function getToken(): string | null {
  if (_token) return _token;
  // No VITE_STRAPI_API_TOKEN fallback — Vite bakes VITE_* vars into the public
  // JS bundle at build time. The kiosk is a public terminal; no server secret
  // should be embedded in its bundle. Use Strapi public role permissions instead.
  return null;
}

async function request<T>(path: string, options: RequestInit = {}, baseUrl?: string): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  // 10 s hard timeout — prevents kiosk UI hanging on network issues
  const signal = (options.signal as AbortSignal | undefined) ?? AbortSignal.timeout(10000);

  const finalUrl = baseUrl !== undefined ? `${baseUrl}${path}` : `${STRAPI_URL}${path}`;
  const res = await fetch(finalUrl, { ...options, headers, signal });
  if (!res.ok) {
    // BUG-004 FIX: Parse the Strapi error JSON body before throwing.
    // Previous code discarded the real error message (e.g. "Produit indisponible").
    let errorMessage = `Strapi ${res.status}: ${res.statusText}`;
    try {
      const errorBody = await res.json();
      const strapiMsg = errorBody?.error?.message;
      if (strapiMsg) errorMessage = strapiMsg;
    } catch {
      // If the body is not JSON, fall back to the HTTP status text
    }
    throw new Error(errorMessage);
  }
  return res.json();
}

export const strapi = {
  get: <T>(path: string) => request<StrapiResponse<T>>(path),

  post: <T>(path: string, data: unknown) =>
    request<StrapiResponse<T>>(path, {
      method: 'POST',
      body: JSON.stringify({ data }),
    }),

  put: <T>(path: string, data: unknown) =>
    request<StrapiResponse<T>>(path, {
      method: 'PUT',
      body: JSON.stringify({ data }),
    }),

  // Dedicated n8n caller for kiosk transactions.
  // SEC-P0-02: VITE_KIOSK_SECRET removed — Vite bakes VITE_* env vars into the
  // public JS bundle at build time. The kiosk is a public terminal; any secret
  // embedded here is visible in DevTools → Sources. Validate kiosk requests via
  // Traefik middleware (ipWhiteList) or n8n webhook auth instead.
  n8n: <T>(path: string, data: unknown, headers: Record<string, string> = {}) => {
    const N8N_BASE = import.meta.env.VITE_N8N_URL || '';
    return request<T>(path, {
      method: 'POST',
      body: JSON.stringify(data),
      headers: {
        ...headers,
        'x-kiosk-origin': 'kiosk-terminal',
      },
    }, N8N_BASE);
  }
};
