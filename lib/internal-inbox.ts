import {corporateActor,hqRest} from "./hq-server";
export const inboxBucket="hq-internal-inbox";
export const maxAttachmentBytes=3*1024*1024;
export const attachmentTypes=new Set(["image/jpeg","image/png","image/webp","application/pdf","text/plain","text/csv","application/vnd.openxmlformats-officedocument.wordprocessingml.document","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","application/vnd.openxmlformats-officedocument.presentationml.presentation","audio/mpeg","audio/ogg","video/mp4"]);
export function isUuid(value:unknown):value is string{return typeof value==="string"&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)}
export class InboxError extends Error{constructor(message:string,public status=400){super(message)}}
export async function inboxActor(){const actor=await corporateActor();if(!actor)throw new InboxError("Inicie sessão com uma conta activa da Central.",401);return actor}
export async function requireConversation(employeeId:string,id:unknown){if(!isUuid(id))throw new InboxError("Conversa inválida.");const rows=await hqRest(`chat_members?conversation_id=eq.${id}&employee_id=eq.${employeeId}&select=conversation_id&limit=1`);if(!rows.length)throw new InboxError("Não participa nesta conversa.",403);return id}
export function meetingUrl(){const origin=new URL(process.env.HQ_MEET_BASE_URL||"https://meet.jit.si");if(origin.protocol!=="https:"||origin.username||origin.password)throw new InboxError("O serviço de reuniões não está configurado correctamente.",503);return new URL(`DeliGo-${crypto.randomUUID()}`,origin.origin).toString()}
