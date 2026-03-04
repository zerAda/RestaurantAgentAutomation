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

function getToken(): string | null {
  if (_token) return _token;
  return sessionStorage.getItem('admin_jwt');
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

  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), 10000);
  const signal = (options.signal as AbortSignal | undefined) ?? controller.signal;

  try {
    const res = await fetch(`${STRAPI_URL}${path}`, { ...options, headers, signal });
    clearTimeout(id);
    if (res.status === 401) {
      sessionStorage.removeItem('admin_jwt');
      sessionStorage.removeItem('admin_user');
      window.location.href = '/';
    }
    if (!res.ok) {
      throw new Error(`Strapi ${res.status}: ${res.statusText}`);
    }
    return res.json();
  } catch (error) {
    clearTimeout(id);
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
};
