const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';

interface StrapiResponse<T> {
  data: T;
  meta?: {
    pagination?: {
      page: number;
      pageSize: number;
      pageCount: number;
      total: number;
    };
    [key: string]: unknown;
  };
}

interface FindParams {
  sort?: string[];
  pagination?: { limit?: number; page?: number; pageSize?: number };
  filters?: Record<string, unknown>;
  populate?: string | string[];
}

let _token: string | null = null;

export function setStrapiToken(token: string) {
  _token = token;
}

export function getToken(): string | null {
  if (_token) return _token;
  // SEC-P0-03: Use sessionStorage ONLY — matches authService.ts F-02 fix.
  // localStorage fallback removed: XSS-stolen tokens in localStorage survive
  // browser restarts; sessionStorage is tab-isolated and wiped on close.
  return sessionStorage.getItem('admin_jwt');
}

// Global event dispatcher for network errors
const emitNetworkError = (message: string) => {
  window.dispatchEvent(new CustomEvent('strapi-network-error', { detail: { message } }));
};

export interface RequestOptions extends RequestInit {
  timeoutMs?: number;
}

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  // Default timeout 10s, but configurable (e.g. 60s for agent chat)
  const timeoutMs = options.timeoutMs || 10000;
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  const signal = (options.signal as AbortSignal | undefined) ?? controller.signal;

  try {
    const res = await fetch(`${STRAPI_URL}${path}`, { ...options, headers, signal });
    clearTimeout(id);

    if (res.status === 401) {
      sessionStorage.removeItem('admin_jwt');
      localStorage.removeItem('admin_jwt');
      sessionStorage.removeItem('admin_user');
      localStorage.removeItem('admin_user');
      // BUG-011 FIX: Preserve the current route so the manager returns to
      // their page after re-login instead of being dumped on the home screen.
      sessionStorage.setItem('redirect_after_login', window.location.pathname + window.location.search);
      window.dispatchEvent(new CustomEvent('strapi-auth-error', { detail: { code: 401 } }));
      window.location.href = '/';
    }

    if (!res.ok) {
      if (res.status >= 500) {
        emitNetworkError(`Le serveur a retourné une erreur ${res.status}`);
      }
      // BUG-010 FIX: Parse the Strapi error JSON body before throwing so the
      // manager sees the real validation message, not a generic HTTP status text.
      let errorMessage = `Strapi ${res.status}: ${res.statusText}`;
      try {
        const errorBody = await res.json();
        const strapiMsg = errorBody?.error?.message;
        if (strapiMsg) errorMessage = strapiMsg;
      } catch { /* If body isn't JSON, fall back to HTTP status */ }
      throw new Error(errorMessage);
    }
    return res.json();
  } catch (error) {
    clearTimeout(id);

    // Check if it's a network error (CORS or offline) or timeout
    if (error instanceof Error) {
      if (error.name === 'AbortError') {
        emitNetworkError('La requête a expiré (Timeout).');
      } else if (error.message.includes('Failed to fetch')) {
        emitNetworkError('Erreur réseau. Impossible de contacter le serveur.');
      }
    }
    throw error;
  }
}

function buildQueryString(params: FindParams): string {
  const parts: string[] = [];
  if (params.sort) {
    params.sort.forEach((s, i) => parts.push(`sort[${i}]=${encodeURIComponent(s)}`));
  }
  if (params.pagination) {
    if (params.pagination.limit !== undefined)
      parts.push(`pagination[limit]=${params.pagination.limit}`);
    if (params.pagination.page !== undefined)
      parts.push(`pagination[page]=${params.pagination.page}`);
    if (params.pagination.pageSize !== undefined)
      parts.push(`pagination[pageSize]=${params.pagination.pageSize}`);
  }
  if (params.populate) {
    if (Array.isArray(params.populate)) {
      params.populate.forEach((p, i) => parts.push(`populate[${i}]=${encodeURIComponent(p)}`));
    } else {
      parts.push(`populate=${encodeURIComponent(params.populate)}`);
    }
  }
  if (params.filters) {
    const flattenFilters = (obj: Record<string, unknown>, prefix = 'filters') => {
      for (const [k, v] of Object.entries(obj)) {
        const key = `${prefix}[${k}]`;
        if (Array.isArray(v)) {
          v.forEach((item, i) => parts.push(`${key}[${i}]=${encodeURIComponent(String(item))}`));
        } else if (v !== null && typeof v === 'object') {
          flattenFilters(v as Record<string, unknown>, key);
        } else {
          parts.push(`${key}=${encodeURIComponent(String(v))}`);
        }
      }
    };
    flattenFilters(params.filters);
  }
  return parts.length ? `?${parts.join('&')}` : '';
}

export const strapi = {
  get: <T>(path: string) => request<StrapiResponse<T>>(path),

  find: <T>(contentType: string, params: FindParams = {}) =>
    request<StrapiResponse<T[]>>(`/api/${contentType}${buildQueryString(params)}`),

  findOne: <T>(contentType: string, id: string | number) =>
    request<StrapiResponse<T>>(`/api/${contentType}/${id}`),

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

  delete: <T>(path: string) =>
    request<StrapiResponse<T>>(path, { method: 'DELETE' }),

  // Raw request: returns the JSON body directly without StrapiResponse wrapper.
  // Use for custom controllers that call ctx.send() with a non-standard shape.
  rawGet: <T>(path: string, options?: RequestOptions) => request<T>(path, options),

  getCortexData: async (keys: string[]) => {
    // SEC-001: token sent via Authorization header (already handled by request()),
    // NOT as a query param (which would leak in server logs / browser history).
    return request<Record<string, unknown>>(`/api/realtime/cortex?keys=${keys.join(',')}`);
  }
};
