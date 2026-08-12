import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";

const allowedBuckets = new Set(["institutional-news","institutional-heroes","institutional-events","institutional-partners","institutional-team","institutional-gallery","institutional-careers"]);
const allowedTypes = new Set(["image/jpeg","image/png","image/webp","application/pdf"]);
export async function POST(request:NextRequest){
 const auth=await requireCorporatePermission("news.manage_media"),key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!auth||!key)return NextResponse.json({error:"Sem permissão para carregar media institucional."},{status:403});
 const form=await request.formData(),file=form.get("file"),bucket=String(form.get("bucket")||"institutional-news");if(!(file instanceof File)||!allowedBuckets.has(bucket)||!allowedTypes.has(file.type)||file.size>10*1024*1024)return NextResponse.json({error:"Ficheiro, tipo ou bucket inválido."},{status:400});
 const extension=file.name.includes(".")?file.name.split(".").pop()!.toLowerCase():"bin",path=`news/${auth.actor.employee_id}/${crypto.randomUUID()}.${extension}`;
 const response=await fetch(`${supabaseUrl()}/storage/v1/object/${bucket}/${path}`,{method:"POST",headers:{apikey:key,Authorization:`Bearer ${key}`,"Content-Type":file.type,"x-upsert":"false"},body:file.stream()});
 if(!response.ok)return NextResponse.json({error:"Não foi possível guardar o ficheiro."},{status:502});
 return NextResponse.json({url:`${supabaseUrl()}/storage/v1/object/public/${bucket}/${path}`,path});
}
