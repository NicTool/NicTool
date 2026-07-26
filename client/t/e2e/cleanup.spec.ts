import { test, expect } from '@playwright/test';
import {
  collectListingPages, isOwnedName, paginationStarts,
} from './global-teardown';

test.describe('E2E cleanup ownership', () => {
  test('does not infer ownership from timestamps or name prefixes', () => {
    const runs = new Set(['nt0123456789abcdef']);
    expect(isOwnedName('customer_1700000000000_1', runs)).toBe(false);
    expect(isOwnedName('e2e_ntfedcba9876543210_1', runs)).toBe(false);
  });

  test('recognizes only an eligible run marker', () => {
    const runs = new Set(['nt0123456789abcdef']);
    expect(isOwnedName('e2e_grp_nt0123456789abcdef_1', runs)).toBe(true);
    expect(isOwnedName('ns-nt0123456789abcdef-2.example.', runs)).toBe(true);
  });

  test('discovers every start-based pagination link', () => {
    const html = [
      '<a href="group.cgi?nt_group_id=1&amp;start=10">2</a>',
      '<a href="group.cgi?nt_group_id=1&start=20">3</a>',
      '<input type="hidden" name="start" value="999">',
    ].join('');
    expect(paginationStarts(html)).toEqual([10, 20]);
  });

  test('continues past an intermediate page with no owned rows', async () => {
    const loads: Array<number | null> = [];
    const pages = new Map<number | null, string>([
      [null, '<a href="group.cgi?nt_group_id=1&amp;start=10">next</a>'],
      [10, '<a href="group.cgi?nt_group_id=1&amp;start=20">next</a>'],
      [20, '<a href="group.cgi?nt_group_id=9">owned row</a>'],
    ]);
    const bodies = await collectListingPages(async start => {
      loads.push(start);
      return pages.get(start) || '';
    });
    expect(loads).toEqual([null, 10, 20]);
    expect(bodies).toHaveLength(3);
  });
});
