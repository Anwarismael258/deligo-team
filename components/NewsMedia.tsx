import {newsVideoSource} from "@/lib/news-media";
type Props={videoUrl?:string|null;imageUrl?:string|null;title:string};
export function NewsMedia({videoUrl,imageUrl,title}:Props){
 const source=newsVideoSource(videoUrl);
 if(source?.kind==="file")return <video aria-label={`Vídeo: ${title}`} controls playsInline preload="metadata" poster={imageUrl||undefined} style={{display:"block",width:"100%",maxHeight:"70vh",aspectRatio:"16 / 9",background:"#071725",borderRadius:12}}><source src={source.url} type={/\.webm(?:$|\?)/i.test(source.url)?"video/webm":"video/mp4"}/>O navegador não suporta este vídeo. <a href={source.url}>Abrir vídeo</a></video>;
 if(source)return <iframe title={`Vídeo: ${title}`} src={source.url} loading="lazy" allow="encrypted-media; picture-in-picture; fullscreen" allowFullScreen referrerPolicy="strict-origin-when-cross-origin" sandbox="allow-scripts allow-same-origin allow-presentation" style={{display:"block",width:"100%",aspectRatio:"16 / 9",border:0,borderRadius:12,background:"#071725"}}/>;
 return imageUrl?<img src={imageUrl} alt={`Imagem: ${title}`} loading="lazy" style={{display:"block",width:"100%",maxHeight:"70vh",objectFit:"contain",borderRadius:12}}/>:null;
}
