import test from 'node:test';
import assert from 'node:assert/strict';
import { personalWalletAmounts, custodyOwnership } from '../lib/finance-custody.ts';
const owner='5e5abc60-ecf5-416b-87a8-93cc0f30035a';
const wallet={id:'wallet-1',available_balance_minor:4731,account_code:'HQ-LEGACY-'+owner};
const seed={wallet_account_id:'wallet-1',entry_type:'legacy_wallet_migration',entry_side:'credit',amount_minor:3761};

test('profile and payout exclude the exact migrated seed while keeping the verified 9.70 deposit',async()=>{
  const [reconciled]=await personalWalletAmounts([wallet],owner,async()=>[seed]);
  assert.equal(reconciled.available_balance_minor,970);assert.equal(reconciled.excluded_legacy_seed_minor,3761);
  const confirmedInternalCredits=[1000,1000];
  assert.equal(reconciled.available_balance_minor+confirmedInternalCredits.reduce((a,b)=>a+b,0),2970);
  assert.equal(wallet.available_balance_minor,4731);
});

test('new deposits remain spendable and a ledger outage cannot authorize a legacy payout',async()=>{
  const [reconciled]=await personalWalletAmounts([{...wallet,available_balance_minor:5701}],owner,async()=>[seed]);
  assert.equal(reconciled.available_balance_minor,1940);
  await assert.rejects(personalWalletAmounts([wallet],owner,async()=>{throw new Error('ledger unavailable')}),/ledger unavailable/);
});

test('a corporate distribution changes ownership without inventing or removing custody',()=>{
  const before=custodyOwnership(62.84,0,109.23,49.15,0);
  const after=custodyOwnership(62.84,20,89.23,49.15,20);
  assert.deepEqual(after,{corporate_custody_available:42.84,employee_wallets_available:20,user_wallets_available:69.15,total_funds_controlled_available:111.99});
  assert.equal(before.total_funds_controlled_available,after.total_funds_controlled_available);
  assert.equal(custodyOwnership(62.84,10,99.23,49.15,10).corporate_custody_available,52.84);
});
