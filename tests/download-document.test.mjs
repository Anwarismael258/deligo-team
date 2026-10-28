import test from 'node:test';
import assert from 'node:assert/strict';
import { downloadDocument } from '../lib/download-document.ts';

test('cross-origin photo becomes a local download with the correct file type', async () => {
  const original = { fetch: globalThis.fetch, document: globalThis.document, setTimeout: globalThis.setTimeout };
  let clicked = false;
  const anchor = { click() { clicked = true; }, remove() {} };
  globalThis.document = { createElement: () => anchor, body: { appendChild() {} } };
  globalThis.fetch = async (url, options) => {
    assert.equal(options.credentials, 'omit');
    return new Response(new Blob(['photo'], { type: 'image/jpeg' }));
  };
  globalThis.setTimeout = callback => { callback(); return 0; };
  try {
    await downloadDocument('https://storage.example/photo?token=private', 'documento-1');
    assert.equal(clicked, true);
    assert.equal(anchor.download, 'documento-1.jpg');
    assert.match(anchor.href, /^blob:/);
    globalThis.fetch = async () => new Response('', { status: 403 });
    await assert.rejects(downloadDocument('https://storage.example/expired', 'documento'), /renovar/);
  } finally { Object.assign(globalThis, original); }
});
