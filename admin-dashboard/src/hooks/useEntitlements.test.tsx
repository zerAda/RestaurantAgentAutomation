import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';

// ── Mocks ──
// strapi.find is the single fetch seam the hook uses; authService.isAuthenticated gates the fetch.
const findMock = vi.fn();

vi.mock('../services/strapiClient', () => ({
  strapi: {
    find: (...args: unknown[]) => findMock(...args),
  },
}));

const isAuthenticatedMock = vi.fn(() => true);
vi.mock('../services/authService', () => ({
  authService: {
    isAuthenticated: () => isAuthenticatedMock(),
  },
}));

import { useEntitlements } from './useEntitlements';

beforeEach(() => {
  findMock.mockReset();
  isAuthenticatedMock.mockReset();
  isAuthenticatedMock.mockReturnValue(true);
});

describe('useEntitlements — ENT-01 fail-closed parity', () => {
  it('hasModule(non-core) === false WHILE loading (fail-OPEN reversal)', () => {
    // never-resolving fetch keeps the hook in the loading window
    findMock.mockReturnValue(new Promise(() => {}));
    const { result } = renderHook(() => useEntitlements());
    expect(result.current.loading).toBe(true);
    expect(result.current.hasModule('kiosk_instore')).toBe(false);
  });

  it('hasModule(shared_core: platform_runtime) === true WHILE loading (allowlist, no lockout)', () => {
    findMock.mockReturnValue(new Promise(() => {}));
    const { result } = renderHook(() => useEntitlements());
    expect(result.current.loading).toBe(true);
    expect(result.current.hasModule('platform_runtime')).toBe(true);
    expect(result.current.hasModule('order_bot_core')).toBe(true);
  });

  it('on fetch REJECT: error === true, hasModule(non-core) === false, shared_core still true', async () => {
    findMock.mockRejectedValue(new Error('network down'));
    const { result } = renderHook(() => useEntitlements());
    await waitFor(() => expect(result.current.error).toBe(true));
    expect(result.current.status).toBe('error');
    expect(result.current.hasModule('kiosk_instore')).toBe(false);
    expect(result.current.hasModule('platform_runtime')).toBe(true);
  });

  it('after a SUCCESSFUL v5-flat fetch: entitled true, non-entitled false, error false', async () => {
    // product-modules first, tenant-entitlements second (Promise.all order)
    findMock
      .mockResolvedValueOnce({
        data: [
          { id: 1, key: 'platform_runtime', tier: 'shared_core', enabled_globally: true },
          { id: 2, key: 'kiosk_instore', tier: 'addon' },
        ],
      })
      .mockResolvedValueOnce({
        data: [{ id: 9, module_key: 'kiosk_instore', enabled: true }],
      });
    const { result } = renderHook(() => useEntitlements());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.error).toBe(false);
    expect(result.current.status).toBe('ready');
    expect(result.current.hasModule('kiosk_instore')).toBe(true);
    expect(result.current.hasModule('voice')).toBe(false);
  });

  it('after a SUCCESSFUL v4-attributes fetch: unwrap tolerance proves entitled true', async () => {
    findMock
      .mockResolvedValueOnce({
        data: [{ id: 1, attributes: { key: 'kiosk_instore', tier: 'addon' } }],
      })
      .mockResolvedValueOnce({
        data: [{ id: 9, attributes: { module_key: 'kiosk_instore', enabled: true } }],
      });
    const { result } = renderHook(() => useEntitlements());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.error).toBe(false);
    expect(result.current.hasModule('kiosk_instore')).toBe(true);
    expect(result.current.hasModule('voice')).toBe(false);
  });

  it('when NOT authenticated: no fetch, loading resolves false, fail-closed defaults (shared_core still true)', async () => {
    isAuthenticatedMock.mockReturnValue(false);
    const { result } = renderHook(() => useEntitlements());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(findMock).not.toHaveBeenCalled();
    expect(result.current.error).toBe(false);
    expect(result.current.hasModule('kiosk_instore')).toBe(false);
    expect(result.current.hasModule('platform_runtime')).toBe(true);
  });
});
