import {NextResponse} from "next/server";
import {requireCorporatePermission,hqRpc} from "@/lib/hq-server";
export const dynamic="force-dynamic";
export async function GET(){const auth=await requireCorporatePermission("operations.view","deligo");if(!auth)return NextResponse.json({error:"Sem permissão para consultar o mapa DeliGo."},{status:403});try{return NextResponse.json(await hqRpc("hq_deligo_operational_map_v1",{p_actor_auth_user_id:auth.actor.authUserId}),{headers:{"Cache-Control":"private, no-store"}})}catch{return NextResponse.json({error:"Mapa operacional temporariamente indisponível."},{status:502})}}
