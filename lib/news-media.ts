export const maxNewsVideoBytes=50*1024*1024;
export const newsVideoTypes:Record<string,string>={"video/mp4":"mp4","video/webm":"webm"};
export type NewsVideo={kind:"file"|"youtube"|"vimeo";url:string};
export function newsVideoSource(value:unknown):NewsVideo|null{
 const raw=String(value||"").trim();if(!raw)return null;
 let url:URL;try{url=new URL(raw)}catch{return null}
 if(url.protocol!=="https:"||url.username||url.password)return null;
 const host=url.hostname.toLowerCase();if(host==="localhost"||host.endsWith(".local")||/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(host)||/^172\.(1[6-9]|2\d|3[01])\./.test(host)||host.includes(":"))return null;
 if(["youtube.com","www.youtube.com","m.youtube.com","youtube-nocookie.com","www.youtube-nocookie.com","youtu.be","www.youtu.be"].includes(host)){
  const parts=url.pathname.split("/").filter(Boolean);const id=host.endsWith("youtu.be")?parts[0]:parts[0]==="watch"?url.searchParams.get("v"):['embed','shorts','live'].includes(parts[0])?parts[1]:null;
  return id&&/^[A-Za-z0-9_-]{11}$/.test(id)?{kind:"youtube",url:`https://www.youtube-nocookie.com/embed/${id}?rel=0`}:null;
 }
 if(["vimeo.com","www.vimeo.com","player.vimeo.com"].includes(host)){
  const parts=url.pathname.split("/").filter(Boolean);const id=host==="player.vimeo.com"?parts[1]:parts[0];return id&&/^\d{5,12}$/.test(id)?{kind:"vimeo",url:`https://player.vimeo.com/video/${id}`}:null;
 }
 return /\.(mp4|webm)$/i.test(url.pathname)?{kind:"file",url:url.toString()}:null;
}
