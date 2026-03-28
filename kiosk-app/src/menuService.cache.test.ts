// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import fs from 'fs';
import path from 'path';

// Mock strapiClient BEFORE importing menuService
vi.mock('./services/strapiClient', () => ({
  strapi: {
    get: vi.fn().mockResolvedValue({
      data: [{ id: 1, name: 'Test Burger', price: 500, category: 'burgers', creative_assets: [] }],
    }),
  },
}));

describe('menuService — PERF-09: TTL cache prevents redundant API calls', () => {
  beforeEach(() => {
    // Clear localStorage and reset mock call history before each test
    localStorage.clear();
    vi.clearAllMocks();
  });

  it('should fetch from Strapi on first call to getProducts()', async () => {
    const { menuService } = await import('./services/menuService');
    const { strapi } = await import('./services/strapiClient');

    const products = await menuService.getProducts();

    expect(strapi.get).toHaveBeenCalledTimes(1);
    expect(products).toHaveLength(1);
    expect(products[0].name).toBe('Test Burger');
  });

  it('should return cached data on second call without making a network request', async () => {
    // Re-import fresh module instances to reset module-level state
    const { menuService } = await import('./services/menuService');
    const { strapi } = await import('./services/strapiClient');

    // First call — populates cache
    await menuService.getProducts();
    // Second call — should serve from localStorage TTL cache
    const products = await menuService.getProducts();

    expect(strapi.get).toHaveBeenCalledTimes(1);
    expect(products).toHaveLength(1);
    expect(products[0].name).toBe('Test Burger');
  });

  it('VerticalVideoFeed.tsx should use menuService (not raw fetch) for product data', () => {
    const feedSource = fs.readFileSync(
      path.resolve(__dirname, 'components/VerticalVideoFeed.tsx'),
      'utf-8'
    );

    expect(
      feedSource,
      'VerticalVideoFeed must import menuService for product data (PERF-09)'
    ).toContain('menuService');

    // Ensure there is no raw fetch() call targeting the products API endpoint
    expect(
      feedSource,
      'VerticalVideoFeed must NOT use raw fetch() for /api/products — use menuService with TTL cache'
    ).not.toMatch(/fetch\s*\([^)]*\/api\/products/);
  });
});
