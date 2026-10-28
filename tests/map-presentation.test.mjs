import test from 'node:test';
import assert from 'node:assert/strict';
import { pageOperations, markerName, markerGlyph, mapColor, escapeMapText, clusterMapMarkers } from '../lib/map-presentation.ts';

test('active operations are bounded to six items and clamp the page after real-time removals',()=>{
  const items=Array.from({length:20},(_,index)=>index);
  assert.deepEqual(pageOperations(items,0).items,[0,1,2,3,4,5]);
  assert.deepEqual(pageOperations(items,3).items,[18,19]);
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
