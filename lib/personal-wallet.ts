import {hqRest} from "./hq-server";
export async function walletOwner(actor:{employee_id:string;authUserId:string}){
 const rows=await hqRest(`employees?id=eq.${encodeURIComponent(actor.employee_id)}&select=auth_user_id`);
 return String(rows?.[0]?.auth_user_id||actor.authUserId);
}
export function eligiblePersonalWallet(wallet:Record<string,unknown>){
 const m=(wallet.metadata&&typeof wallet.metadata==="object"?wallet.metadata:{}) as Record<string,unknown>;
 return m.withdrawal_disabled!==true&&m.test_mode!==true&&m.fictitious!==true&&m.is_test_user!==true&&!String(wallet.account_code||"").startsWith("TEST-");
}
