type Row=Record<string,unknown>;
export const unreconciledLegacyOwners = new Set([
 "5e5abc60-ecf5-416b-87a8-93cc0f30035a",
 "0efc4ae3-9b17-4695-940c-9c68b9473e12",
]);

export function custodyOwnership(revenue:number,transferred:number,cash:number,external:number,employees:number){
 const values=[revenue,transferred,cash,external,employees];
 if(values.some(value=>!Number.isFinite(value)))throw new Error("Custody source unavailable");
 const minor=(amount:number)=>Math.round(amount*100);
 const retained=Math.max(0,Math.min(minor(cash),minor(revenue)-minor(transferred)));
 const personal=minor(external)+minor(employees);
 return {corporate_custody_available:retained/100,employee_wallets_available:minor(employees)/100,user_wallets_available:personal/100,total_funds_controlled_available:(retained+personal)/100};
}

/** Use the same provenance rule for custody, profile and payout allocation. */
export async function personalWalletAmounts(wallets:Row[],owner:string,loadLedger:(path:string)=>Promise<Row[]>):Promise<Row[]>{
 if(!unreconciledLegacyOwners.has(owner))return wallets;
 const eligible=wallets.filter(wallet=>Number(wallet.available_balance_minor||0)>0&&!String(wallet.account_code||"").startsWith("TEST-"));
 if(!eligible.length)return wallets;
 const ids=eligible.map(wallet=>String(wallet.id));
 const ledger=await loadLedger(`wallet_ledger_entries?select=wallet_account_id,entry_side,entry_type,amount_minor&wallet_account_id=in.(${ids.join(",")})&entry_type=eq.legacy_wallet_migration`);
 if(!Array.isArray(ledger))throw new Error("Não foi possível reconciliar o saldo pessoal.");
 return custodyWalletAmounts(wallets.map(wallet=>({...wallet,owner_user_id:owner})),ledger,unreconciledLegacyOwners);
}
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
