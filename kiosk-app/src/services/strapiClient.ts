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

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
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

  const res = await fetch(`${STRAPI_URL}${path}`, { ...options, headers, signal });
  if (!res.ok) {
    throw new Error(`Strapi ${res.status}: ${res.statusText}`);
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
};
