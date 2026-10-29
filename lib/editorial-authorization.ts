import {corporateAuthorization} from "./hq-server";
const directActions=new Set(["news.view","news.create","news.edit","news.publish","news.schedule","news.archive","news.manage_media"]);
export async function requireEditorialPermission(permission:string){
 const authorization=await corporateAuthorization();if(!authorization)return null;
 const directPublisher=["SUPER_ADMIN","MARKETING"].includes(authorization.actor.role);
 if(authorization.isSuperAdmin||authorization.permissions.includes(permission)||(directPublisher&&directActions.has(permission)))return {...authorization,directPublisher};
 return null;
}
