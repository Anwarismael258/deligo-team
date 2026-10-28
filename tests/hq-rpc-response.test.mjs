import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import ts from 'typescript';
const source=ts.transpileModule(await readFile(new URL('../lib/hq-server.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
function client(response){const exports={};vm.runInNewContext(source,{exports,require:()=>({}),process:{env:{SUPABASE_URL:'https://example.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-key'}},AbortSignal,fetch:async()=>response});return exports.hqRpc;}
for(const status of [200,204])test(`void RPC HTTP ${status} succeeds without JSON`,async()=>assert.equal(await client(new Response(null,{status}))('chat_read_v1',{},'hq'),null));
test('JSON RPC responses still decode',async()=>assert.equal((await client(new Response('{"ok":true}'))('chat_send_v1')).ok,true));
test('RPC errors are not swallowed',async()=>assert.rejects(client(new Response('permission denied',{status:403}))('chat_read_v1'),/permission denied/));
test('malformed nonempty successful payload remains an error',async()=>assert.rejects(client(new Response('{'))('chat_list_v1'),/JSON/));
