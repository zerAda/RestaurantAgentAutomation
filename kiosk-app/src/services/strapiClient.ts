const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';

interface StrapiResponse<T> {
  data: T;
  meta?: Record<string, unknown>;
}

let _token: string | null = null;

export function setStrapiToken(token: string) {
  _token = token;
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };
  if (_token) {
    headers['Authorization'] = `Bearer ${_token}`;
  }

  const res = await fetch(`${STRAPI_URL}${path}`, { ...options, headers });
  if (!res.ok) {
    throw new Error(`Strapi ${res.status}: ${res.statusText}`);
  }
  return res.json();
}

export const strapi = {
  get: <T>(path: string) => request<StrapiResponse<T>>(path),
  put: <T>(path: string, data: unknown) =>
    request<StrapiResponse<T>>(path, { method: 'PUT', body: JSON.stringify({ data }) }),
};
