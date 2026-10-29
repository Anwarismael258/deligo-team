import test from 'node:test';
import assert from 'node:assert/strict';
import { pageOperations, markerName, markerGlyph, mapColor, escapeMapText, clusterMapMarkers } from '../lib/map-presentation.ts';

test('active operations are bounded to three items and clamp the page after real-time removals',()=>{
  const items=Array.from({length:20},(_,index)=>index);
  assert.deepEqual(pageOperations(items,0).items,[0,1,2]);
  assert.deepEqual(pageOperations(items,6).items,[18,19]);
  assert.deepEqual(pageOperations(items.slice(0,2),3),{page:0,pages:1,items:[0,1]});
  assert.equal(pageOperations([],9).pages,1);
});

test('names and distinct platform icons remain readable without treating supplied names as HTML',()=>{
  assert.equal(markerName({workerName:'Sara',service:'#123',role:'Driver'}),'Sara');
  assert.equal(markerName({service:'#123',role:'Driver'}),'#123');
  assert.notEqual(markerGlyph('Driver','SARCA'),markerGlyph('Estafeta','DeliGo'));
  assert.deepEqual(['DeliGo','SARCA','DeliGo Market'].map(mapColor),['#22d3ee','#a78bfa','#fb923c']);
  assert.equal(escapeMapText('<img src=x onerror="attack()">'),'&lt;img src=x onerror=&quot;attack()&quot;&gt;');
});

test('nearby positions cluster without changing their real coordinates',()=>{
  const positions=[{id:1,x:1,y:1},{id:2,x:10,y:10},{id:3,x:140,y:140}];
  const clusters=clusterMapMarkers(positions,p=>p);
  assert.deepEqual(clusters.map(group=>group.map(p=>p.id)),[[1,2],[3]]);
  assert.deepEqual(positions[0],{id:1,x:1,y:1});
});

test('clean map hides unrelated endpoints and people, keeps latest vehicle position and selected route endpoints',async()=>{
 const {cleanMapMarkers,markerIconSvg}=await import('../lib/map-presentation.ts');
 const rows=[{id:'trip:1:origin',role:'Viagem',platform:'SARCA',locationKind:'endpoint'},{id:'trip:2:origin',role:'Viagem',platform:'SARCA',locationKind:'endpoint'},{id:'trip:1:rider',role:'Rider',platform:'SARCA',locationKind:'gps'},{id:'old',workerId:'driver',role:'Driver',platform:'SARCA',locationKind:'gps',updatedAt:'2026-10-29T05:00:00Z'},{id:'latest',workerId:'driver',role:'Driver',platform:'SARCA',locationKind:'gps',updatedAt:'2026-10-29T06:00:00Z'}];
 assert.deepEqual(cleanMapMarkers(rows).map(row=>row.id),['latest']);
 assert.deepEqual(cleanMapMarkers(rows,'trip:1').map(row=>row.id),['latest','trip:1:origin']);
 assert.match(markerIconSvg('Driver','SARCA'),/<svg/);assert.doesNotMatch(markerIconSvg('<script>person</script>','SARCA'),/script|person/);
});
