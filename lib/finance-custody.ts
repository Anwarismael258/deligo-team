type Row=Record<string,unknown>;
/** Exclude only the legacy seed of previously excluded wallets, keeping real deposits. */
export function custodyWalletAmounts(wallets:Row[],ledger:Row[],excludedLegacyOwners:Set<string>):Row[]{
 const seeds=new Map<string,number>();
 for(const entry of ledger){if(entry.entry_type!=="legacy_wallet_migration")continue;const amount=Number(entry.amount_minor);if(!Number.isFinite(amount)||amount<0)throw new Error("Invalid legacy ledger amount");const id=String(entry.wallet_account_id);seeds.set(id,(seeds.get(id)||0)+(entry.entry_side==="credit"?amount:entry.entry_side==="debit"?-amount:0));}
 return wallets.map(wallet=>{
  if(!excludedLegacyOwners.has(String(wallet.owner_user_id)))return wallet;
  const seed=Math.max(seeds.get(String(wallet.id))||0,0),available=Number(wallet.available_balance_minor||0);
  return {...wallet,available_balance_minor:Math.max(available-seed,0),excluded_legacy_seed_minor:Math.min(seed,Math.max(available,0))};
 });
}
